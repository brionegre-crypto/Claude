import Foundation
import SwiftData
import FoundationModels

/// Finds a product: your own library first (instant, offline), then Open Food Facts, a free open database.
/// Only the barcode number is sent. Every new product is saved, so your library grows with each scan.
@MainActor
enum FoodLibrary {
    enum Outcome {
        case found(FoodProduct, isNew: Bool)
        case notFound(String)          // barcode: scan the label to add it
        case failed(String)
    }

    static func lookup(barcode raw: String, ctx: ModelContext) async -> Outcome {
        let code = raw.filter(\.isNumber)
        guard code.count >= 6 else { return .failed("That barcode didn't read cleanly. Try again, a little further away.") }
        if let p = existing(code, ctx: ctx) {
            p.scanCount += 1
            p.lastScanned = Date()
            if p.resultData == nil { p.recheck() }
            try? ctx.save()
            return .found(p, isNew: false)
        }
        do {
            guard let p = try await OpenFoodFacts.fetch(code) else { return .notFound(code) }
            p.scanCount = 1
            p.recheck()
            ctx.insert(p)
            try? ctx.save()
            return .found(p, isNew: true)
        } catch {
            return .failed("Couldn't reach the food database. Check your connection, or scan the label instead.")
        }
    }

    static func existing(_ code: String, ctx: ModelContext) -> FoodProduct? {
        // Barcodes are stored as digits; UPC-A and EAN-13 differ by a leading zero.
        let variants = Array(Set([code, "0" + code, code.hasPrefix("0") ? String(code.dropFirst()) : code]))
        var d = FetchDescriptor<FoodProduct>(predicate: #Predicate { variants.contains($0.barcode) })
        d.fetchLimit = 1
        return (try? ctx.fetch(d))?.first
    }

    /// Adds (or fills in) a product from a photographed label.
    static func fromLabel(_ text: String, barcode: String?, name: String, ctx: ModelContext) -> FoodProduct {
        let parsed = LabelParser.parse(text)
        let p: FoodProduct
        if let b = barcode, let found = existing(b, ctx: ctx) { p = found }
        else {
            p = FoodProduct(barcode: barcode ?? "label-\(UUID().uuidString.prefix(8))", name: name)
            p.source = "Label scan"
            ctx.insert(p)
        }
        if !name.isEmpty { p.name = name }
        if !parsed.ingredients.isEmpty { p.ingredients = parsed.ingredients }
        if parsed.facts.calories != nil || parsed.facts.protein != nil { p.facts = parsed.facts }
        p.scanCount += 1
        p.lastScanned = Date()
        p.recheck()
        try? ctx.save()
        return p
    }
}

// MARK: - Open Food Facts

@MainActor
enum OpenFoodFacts {
    private struct Response: Decodable {
        var status: Int?
        var product: Product?
    }
    private struct Product: Decodable {
        var product_name: String?
        var product_name_en: String?
        var brands: String?
        var ingredients_text: String?
        var ingredients_text_en: String?
        var categories_tags: [String]?
        var additives_tags: [String]?
        var allergens_tags: [String]?
        var image_front_small_url: String?
        var serving_size: String?
        var serving_quantity: Double?
        var nutriments: [String: Flexible]?
    }
    /// The database mixes numbers and strings.
    private struct Flexible: Decodable {
        var value: Double?
        init(from d: Decoder) throws {
            let c = try d.singleValueContainer()
            if let v = try? c.decode(Double.self) { value = v }
            else if let s = try? c.decode(String.self) { value = Double(s) }
        }
    }

    static func fetch(_ code: String) async throws -> FoodProduct? {
        let fields = "product_name,product_name_en,brands,ingredients_text,ingredients_text_en,categories_tags,additives_tags,allergens_tags,image_front_small_url,serving_size,serving_quantity,nutriments"
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=\(fields)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Keel/1.0 (iOS food scanner)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12
        let (data, resp) = try await URLSession.shared.data(for: req)
        if (resp as? HTTPURLResponse)?.statusCode == 404 { return nil }
        let r = try JSONDecoder().decode(Response.self, from: data)
        guard r.status == 1, let p = r.product else { return nil }

        let name = [p.product_name_en, p.product_name].compactMap { $0 }.first { !$0.isEmpty } ?? ""
        let product = FoodProduct(barcode: code, name: name)
        do {
            product.brand = (p.brands ?? "").components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? ""
            product.ingredients = [p.ingredients_text_en, p.ingredients_text].compactMap { $0 }.first { !$0.isEmpty } ?? ""
            product.categories = p.categories_tags ?? []
            product.additives = p.additives_tags ?? []
            product.allergens = p.allergens_tags ?? []
            product.imageURL = p.image_front_small_url
            product.servingGrams = p.serving_quantity
            product.facts = facts(p.nutriments ?? [:], serving: p.serving_size, hasServing: (p.serving_quantity ?? 0) > 0)
        }
        return product
    }

    private static func facts(_ n: [String: Flexible], serving: String?, hasServing: Bool) -> NutritionFacts {
        let usesServing = hasServing && n["energy-kcal_serving"]?.value != nil
        let suffix = usesServing ? "_serving" : "_100g"
        func v(_ key: String) -> Double? { n[key + suffix]?.value }
        var f = NutritionFacts()
        f.calories = v("energy-kcal")
        f.protein = v("proteins")
        f.carbs = v("carbohydrates")
        f.fat = v("fat")
        f.fiber = v("fiber")
        f.sugar = v("sugars")
        f.addedSugar = v("added-sugars")
        f.sodiumMg = v("sodium").map { $0 * 1000 }
        f.caffeineMg = v("caffeine").map { $0 * 1000 }
        f.magnesiumMg = v("magnesium").map { $0 * 1000 }
        f.zincMg = v("zinc").map { $0 * 1000 }
        f.ironMg = v("iron").map { $0 * 1000 }
        f.servingLabel = usesServing ? "per serving" + (serving.map { " (\($0))" } ?? "") : "per 100 g"
        return f
    }
}

// MARK: - Reading a label photo

enum LabelParser {
    struct Parsed {
        var ingredients: String
        var facts: NutritionFacts
    }

    static func parse(_ text: String) -> Parsed {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        var ingredients = ""
        if let r = flat.range(of: "ingredients", options: .caseInsensitive) {
            var rest = String(flat[r.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: ": ").union(.whitespaces))
            for stop in ["contains:", "contains ", "allergen", "distributed by", "manufactured", "nutrition facts", "may contain", "keep refrigerated"] {
                if let s = rest.range(of: stop, options: .caseInsensitive) { rest = String(rest[..<s.lowerBound]) }
            }
            ingredients = rest.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        }
        func num(_ pattern: String) -> Double? {
            guard let r = flat.range(of: pattern + #"[^0-9]{0,12}([0-9]+(?:\.[0-9]+)?)"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
            let s = String(flat[r])
            guard let n = s.range(of: #"[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) else { return nil }
            return Double(s[n])
        }
        var f = NutritionFacts()
        f.calories = num("calories")
        f.fat = num("total fat")
        f.sodiumMg = num("sodium")
        f.carbs = num("total carbohydrate")
        f.fiber = num("dietary fiber") ?? num("fibre")
        f.sugar = num("total sugars")
        f.addedSugar = num("added sugars") ?? num("incl\\.? added")
        f.protein = num("protein")
        f.caffeineMg = num("caffeine")
        return Parsed(ingredients: ingredients, facts: f)
    }
}

// MARK: - Describing a meal (no barcode)

@MainActor
enum MealEstimator {
    @Generable
    struct Estimate {
        @Guide(description: "A short name for the meal") var name: String
        @Guide(description: "Main ingredients, comma separated, including oils, sauces and sweeteners if likely") var ingredients: String
        @Guide(description: "Estimated calories for the whole portion") var calories: Int
        @Guide(description: "Grams of protein") var protein: Int
        @Guide(description: "Grams of carbohydrate") var carbs: Int
        @Guide(description: "Grams of fat") var fat: Int
        @Guide(description: "Grams of fiber") var fiber: Int
        @Guide(description: "Grams of added sugar") var addedSugar: Int
        @Guide(description: "Milligrams of sodium") var sodiumMg: Int
    }

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Rough numbers from a description, on device. Returns nil without Apple Intelligence.
    static func estimate(_ text: String) async -> (name: String, ingredients: String, facts: NutritionFacts)? {
        guard isAvailable else { return nil }
        let session = LanguageModelSession(instructions: "You estimate nutrition for a described meal. Use typical US portions unless amounts are given. Be realistic, not optimistic.")
        guard let e = try? await session.respond(to: "Meal: \(text)", generating: Estimate.self).content else { return nil }
        var f = NutritionFacts()
        f.calories = Double(e.calories); f.protein = Double(e.protein); f.carbs = Double(e.carbs); f.fat = Double(e.fat)
        f.fiber = Double(e.fiber); f.addedSugar = Double(e.addedSugar); f.sodiumMg = Double(e.sodiumMg)
        f.servingLabel = "estimate"
        return (e.name, e.ingredients, f)
    }
}
