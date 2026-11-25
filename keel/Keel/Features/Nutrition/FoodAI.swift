import Foundation
import FoundationModels
import SwiftData

// MARK: - Food intelligence (Apple Intelligence, on this iPhone)
//
// Everything the new Galley asks of the on-device model: a meal broken into items with portions and how sure it is
// (cuisine- and restaurant-aware, hidden oils counted), fixes in plain words ("only half", "no cheese"), a personal
// verdict on a scanned product, reading a nutrition label, and ranking a restaurant menu. Nothing leaves the phone.
// Without Apple Intelligence every caller falls back to the catalog, the barcode database and the label parser.

@MainActor
enum FoodAI {
    static var isAvailable: Bool { MealEstimator.isAvailable }

    // MARK: Your day, in a sentence the model can use

    /// Today's totals against your targets, your diets, and your Body scores.
    static func context(ctx: ModelContext) -> String {
        let start = Calendar.current.startOfDay(for: Date())
        let today = (try? ctx.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.date >= start }))) ?? []
        let t = today.reduce(NutritionFacts()) { $0 + $1.facts }
        var parts = [
            "Eaten today: \(Int(t.calories ?? 0)) of \(Int(NutritionGoals.calories)) kcal, \(Int(t.protein ?? 0)) g protein (goal \(Int(NutritionGoals.protein(weightKg: nil))) g), \(Int(t.fiber ?? 0)) of \(Int(NutritionGoals.fiber)) g fiber, \(Int(t.addedSugar ?? 0)) g added sugar (cap \(Int(NutritionGoals.addedSugarCap)) g)."
        ]
        let diets = PersonalDiets.all.map(\.name)
        if !diets.isEmpty { parts.append("Diets they follow: \(diets.joined(separator: ", ")).") }
        let avoid = PersonalDiets.all.flatMap(\.avoid).prefix(20)
        if !avoid.isEmpty { parts.append("They avoid: \(avoid.joined(separator: ", ")).") }
        if let b = BodyEngine.shared.today {
            if let tide = b.tide { parts.append("Recovery (Tide) today: \(tide)%.") }
            if b.hasSleep { parts.append("Slept \(Int(b.asleep) / 60) h \(Int(b.asleep) % 60) m last night.") }
        }
        parts.append("Local time \(Date().formatted(date: .omitted, time: .shortened)).")
        return parts.joined(separator: " ")
    }

    // MARK: A meal, broken down

    @Generable
    struct Breakdown {
        @Guide(description: "A short name for the whole meal, e.g. 'Salmon, rice & greens'") var title: String
        @Guide(description: "The cuisine, e.g. Thai, Southern, Ethiopian, American") var cuisine: String
        @Guide(description: "Each separate food or drink, including cooking oil, butter, sauces and dressings when likely") var items: [Item]
    }

    @Generable
    struct Item {
        @Guide(description: "Food name") var name: String
        @Guide(description: "Portion in everyday words, e.g. '1 cup', '150 g', '6 pieces'") var portion: String
        @Guide(description: "Estimated grams for the portion") var grams: Int
        @Guide(description: "Calories for the portion") var calories: Int
        @Guide(description: "Grams of protein") var protein: Int
        @Guide(description: "Grams of carbohydrate") var carbs: Int
        @Guide(description: "Grams of fat") var fat: Int
        @Guide(description: "Grams of fiber") var fiber: Int
        @Guide(description: "Grams of added sugar") var addedSugar: Int
        @Guide(description: "Milligrams of sodium") var sodiumMg: Int
        @Guide(description: "How sure you are about this item and its portion, 0 to 100") var confidence: Int
        @Guide(description: "True if this is a cooking fat, oil, butter or dressing you assumed") var isAddedFat: Bool
    }

    private static let breakdownRules = """
    You log meals for a nutrition app. Split the meal into its separate foods. Respect any amounts given ("large", \
    "half", "2 slices", "extra"). Use the cuisine's real dishes and restaurant portions when it sounds like takeout or a \
    restaurant, home portions otherwise. Count cooking oil, butter, sauces and dressings as their own items when a dish \
    is usually made with them, and mark them isAddedFat. Be realistic, never optimistic. Lower confidence when a \
    portion is a guess.
    """

    static func breakdown(_ text: String, ctx: ModelContext) async -> Breakdown? {
        guard isAvailable else { return nil }
        let s = LanguageModelSession(instructions: breakdownRules)
        return try? await s.respond(to: "Meal: \(text)\nAbout the person: \(context(ctx: ctx))", generating: Breakdown.self).content
    }

    /// "Only half", "no cheese", "make it a large", "split with Brittney": the same meal, changed.
    static func revise(_ b: Breakdown, instruction: String) async -> Breakdown? {
        guard isAvailable else { return nil }
        let s = LanguageModelSession(instructions: breakdownRules + " You are changing a meal already broken down; keep what wasn't mentioned.")
        let current = b.items.map { "\($0.name) · \($0.portion) · \($0.calories) kcal · \($0.protein)P \($0.carbs)C \($0.fat)F" }.joined(separator: "\n")
        return try? await s.respond(to: "Current meal '\(b.title)':\n\(current)\n\nChange: \(instruction)", generating: Breakdown.self).content
    }

    static func facts(_ i: Item) -> NutritionFacts {
        var f = NutritionFacts()
        f.calories = Double(i.calories); f.protein = Double(i.protein); f.carbs = Double(i.carbs); f.fat = Double(i.fat)
        f.fiber = Double(i.fiber); f.addedSugar = Double(i.addedSugar); f.sodiumMg = Double(i.sodiumMg)
        f.servingLabel = i.portion
        return f
    }

    // MARK: A scanned product, for you

    @Generable
    struct Verdict {
        @Guide(description: "Three to six words, e.g. 'Great pick right now' or 'Fine, watch the sugar'") var headline: String
        @Guide(description: "Two short sentences for this person today: how it fits their goals, gaps and diet") var detail: String
        @Guide(description: "good, okay or poor for this person right now") var rating: String
        @Guide(description: "One better swap in a few words, or empty") var swap: String
        @Guide(description: "One thing to add that closes a gap, in a few words, or empty") var addOn: String
        @Guide(description: "Allergens present, comma separated, or empty") var allergens: String
    }

    static func verdict(name: String, brand: String, ingredients: String, facts: NutritionFacts, ctx: ModelContext) async -> Verdict? {
        guard isAvailable else { return nil }
        let s = LanguageModelSession(instructions: "You are a calm, practical nutrition coach. Judge a packaged food for this person today, using their numbers. Never shame. Be specific with numbers.")
        let f = "\(Int(facts.calories ?? 0)) kcal, \(Int(facts.protein ?? 0)) g protein, \(Int(facts.carbs ?? 0)) g carbs, \(Int(facts.fat ?? 0)) g fat, \(Int(facts.fiber ?? 0)) g fiber, \(Int(facts.addedSugar ?? facts.sugar ?? 0)) g sugar, \(Int(facts.sodiumMg ?? 0)) mg sodium per \(facts.servingLabel)"
        let prompt = "Product: \(brand) \(name)\nIngredients: \(ingredients.prefix(600))\nNutrition: \(f)\nThe person: \(context(ctx: ctx))"
        return try? await s.respond(to: prompt, generating: Verdict.self).content
    }

    // MARK: A nutrition label, read

    @Generable
    struct Label {
        @Guide(description: "Product name if visible, else empty") var name: String
        @Guide(description: "Serving size as printed") var serving: String
        @Guide(description: "Serving size in grams, 0 if not printed") var servingGrams: Int
        @Guide(description: "Calories per serving") var calories: Int
        @Guide(description: "Grams of protein per serving") var protein: Int
        @Guide(description: "Grams of total carbohydrate per serving") var carbs: Int
        @Guide(description: "Grams of total fat per serving") var fat: Int
        @Guide(description: "Grams of fiber per serving") var fiber: Int
        @Guide(description: "Grams of total sugars per serving") var sugar: Int
        @Guide(description: "Grams of added sugars per serving") var addedSugar: Int
        @Guide(description: "Milligrams of sodium per serving") var sodiumMg: Int
        @Guide(description: "The ingredients list as printed, or empty") var ingredients: String
        @Guide(description: "Allergens named on the label, comma separated, or empty") var allergens: String
    }

    static func readLabel(_ text: String) async -> Label? {
        guard isAvailable, text.count > 20 else { return nil }
        let s = LanguageModelSession(instructions: "Read a nutrition facts panel and ingredients list captured by a camera (the text may be jumbled or split across lines). Return only what is printed; use 0 when a value is missing.")
        return try? await s.respond(to: String(text.prefix(3000)), generating: Label.self).content
    }

    // MARK: A restaurant menu, ranked

    @Generable
    struct MenuPick {
        @Guide(description: "Dish name as on the menu") var dish: String
        @Guide(description: "Estimated calories") var calories: Int
        @Guide(description: "Estimated grams of protein") var protein: Int
        @Guide(description: "One short reason it fits or doesn't, for this person today") var why: String
        @Guide(description: "Score 0 to 100 for this person right now") var score: Int
    }

    @Generable
    struct MenuRanking { @Guide(description: "The best five or so dishes, best first") var picks: [MenuPick] }

    static func rankMenu(_ text: String, ctx: ModelContext) async -> [MenuPick] {
        guard isAvailable, text.count > 30 else { return [] }
        let s = LanguageModelSession(instructions: "Rank dishes from a restaurant menu captured by a camera, for this person today: their remaining calories and protein, their diets and what they avoid. Estimate realistically.")
        let r = try? await s.respond(to: "Menu:\n\(text.prefix(3000))\n\nThe person: \(context(ctx: ctx))", generating: MenuRanking.self).content
        return (r?.picks ?? []).sorted { $0.score > $1.score }
    }
}
