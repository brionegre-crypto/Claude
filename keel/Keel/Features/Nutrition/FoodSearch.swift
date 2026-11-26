import SwiftUI
import SwiftData
import PhotosUI
import Vision

// MARK: - A food you can pick: from Keel's catalog, your own history, your scanned library, or the open food database

struct CatalogFood: Identifiable, Hashable, Codable {
    enum Source: String, Codable { case catalog, mine, library, web, photo }
    var id: String
    var emoji: String
    var name: String
    var aliases: [String] = []
    var serving: String
    var grams: Double?
    var facts: NutritionFacts             // for one serving
    var words: [String] = []              // what the camera calls it
    var imageURL: String?
    var barcode: String?
    var brand: String = ""
    var ingredients: String = ""
    var source: Source = .catalog
    var timesEaten = 0

    var kcal: Int { Int((facts.calories ?? 0).rounded()) }
}

private struct RankedFood { let food: CatalogFood; let score: Int; let order: Int }

enum FoodCatalog {
    static let all: [CatalogFood] = raw.split(separator: "\n").compactMap { parse(String($0)) }

    static func parse(_ line: String) -> CatalogFood? {
        let c = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard c.count == 13 else { return nil }
        func d(_ i: Int) -> Double { Double(c[i]) ?? 0 }
        var f = NutritionFacts()
        f.calories = d(5); f.protein = d(6); f.carbs = d(7); f.fat = d(8)
        f.fiber = d(9); f.sugar = d(10); f.sodiumMg = d(11)
        f.servingLabel = c[3]
        return CatalogFood(id: "c:" + c[1].lowercased(), emoji: c[0], name: c[1],
                           aliases: c[2].split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                           serving: c[3], grams: d(4), facts: f,
                           words: c[12].split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
    }

    /// How well a food matches what's typed so far (0 = not at all).
    static func score(_ f: CatalogFood, _ q: String) -> Int {
        let n = f.name.lowercased()
        let aliases = f.aliases.map { $0.lowercased() }
        if n == q || aliases.contains(q) { return 100 }
        if n.hasPrefix(q) { return 85 }
        if aliases.contains(where: { $0.hasPrefix(q) }) { return 70 }
        let words = n.split(whereSeparator: { !$0.isLetter }).map(String.init)
        if words.contains(where: { $0.hasPrefix(q) }) { return 60 }
        if n.contains(q) { return 45 }
        if aliases.contains(where: { $0.contains(q) }) { return 35 }
        let tokens = q.split(separator: " ").map(String.init).filter { $0.count > 1 }
        if tokens.count > 1 {
            let hay = ([n] + aliases).joined(separator: " ")
            if tokens.allSatisfy({ hay.contains($0) }) { return 40 }
        }
        if !f.brand.isEmpty, f.brand.lowercased().hasPrefix(q) { return 30 }
        return 0
    }

    /// Best matches first. Foods you eat often get a lift, so your usual comes up after a letter or two.
    static func search(_ query: String, in pool: [CatalogFood], limit: Int = 14) -> [CatalogFood] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var seen = Set<String>()
        // Ties keep the pool's order: your foods first, then the catalog, which lists everyday foods before variations.
        return pool.enumerated().compactMap { i, f -> RankedFood? in
            let s = score(f, q)
            guard s > 0 else { return nil }
            return RankedFood(food: f, score: s + min(25, f.timesEaten * 5) + (f.source == .mine ? 10 : 0), order: i)
        }
        .sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
        .compactMap { r -> CatalogFood? in
            let key = r.food.name.lowercased()
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return r.food
        }
        .prefix(limit).map { $0 }
    }

    /// The catalog food a camera label most likely means ("hamburger" → Hamburger).
    static func match(label: String) -> CatalogFood? {
        let l = label.lowercased()
        return all.first { $0.words.contains(l) }
            ?? all.first { $0.name.lowercased() == l }
            ?? all.first { f in f.words.contains { w in w.count > 3 && (l.contains(w) || w.contains(l)) } }
    }

    /// A picture for any food name, borrowed from the closest catalog food.
    static func emoji(for name: String) -> String {
        search(name, in: all, limit: 1).first?.emoji ?? "🍽️"
    }
}

// MARK: - Typing several things at once: "2 eggs, toast and a latte"

enum MealPhrase {
    struct Part: Hashable { var servings: Double; var text: String }

    private static let numbers: [String: Double] = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
                                                   "half": 0.5, "½": 0.5, "¼": 0.25, "¾": 0.75, "couple": 2, "few": 3]

    static func parts(_ text: String) -> [Part] {
        let pieces = text.lowercased()
            .replacingOccurrences(of: " with ", with: ",").replacingOccurrences(of: " and ", with: ",")
            .replacingOccurrences(of: "&", with: ",").replacingOccurrences(of: "+", with: ",")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return pieces.map { piece in
            var words = piece.split(separator: " ").map(String.init)
            var n = 1.0
            if let first = words.first {
                if let v = Double(first.replacingOccurrences(of: "x", with: "")) { n = v; words.removeFirst() }
                else if let v = numbers[first] { n = v; words.removeFirst(); if words.first == "of" { words.removeFirst() } }
            }
            if let unit = words.first, ["cups", "cup", "slices", "slice", "pieces", "piece", "bowls", "bowl", "glasses", "glass", "servings", "serving"].contains(unit), words.count > 1 {
                words.removeFirst()
                if words.first == "of" { words.removeFirst() }
            }
            return Part(servings: max(0.25, n), text: words.joined(separator: " "))
        }
    }

    /// For a phrase with more than one food, the best food for each part.
    static func resolve(_ text: String, pool: [CatalogFood]) -> [PlateItem] {
        let ps = parts(text)
        guard ps.count > 1 || (ps.first?.servings ?? 1) != 1 else { return [] }
        return ps.compactMap { p in
            guard let f = FoodCatalog.search(p.text, in: pool, limit: 1).first ?? FoodCatalog.search(String(p.text.dropLast()), in: pool, limit: 1).first
            else { return nil }
            return PlateItem(food: f, servings: p.servings)
        }
    }
}

// MARK: - Your own foods: everything you've logged, with how often, and what you usually have at each meal

@MainActor
enum MyFoods {
    private static let picturesKey = "nutrition.foodPictures"

    static func picture(for name: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: picturesKey) as? [String: String])?[name.lowercased()]
    }
    static func remember(_ f: CatalogFood) {
        var d = (UserDefaults.standard.dictionary(forKey: picturesKey) as? [String: String]) ?? [:]
        d[f.name.lowercased()] = f.imageURL ?? f.emoji
        if d.count > 600 { d = Dictionary(uniqueKeysWithValues: d.prefix(500).map { ($0.key, $0.value) }) }
        UserDefaults.standard.set(d, forKey: picturesKey)
    }

    /// One food per name: the latest serving's numbers, and how many times you've had it.
    static func foods(from entries: [FoodEntry]) -> [CatalogFood] {
        var out: [String: CatalogFood] = [:]
        for e in entries {                                         // newest first
            let key = e.name.lowercased()
            if var f = out[key] { f.timesEaten += 1; out[key] = f; continue }
            let per = e.facts.scaled(1 / max(e.servings, 0.25))
            let pic = picture(for: e.name)
            let isURL = pic?.hasPrefix("http") == true
            out[key] = CatalogFood(id: "m:" + key, emoji: isURL ? FoodCatalog.emoji(for: e.name) : (pic ?? FoodCatalog.emoji(for: e.name)),
                                   name: e.name, serving: per.servingLabel == "estimate" || per.servingLabel.isEmpty ? "1 serving" : per.servingLabel,
                                   facts: per, imageURL: isURL ? pic : nil, barcode: e.barcode, source: .mine, timesEaten: 1)
        }
        return Array(out.values)
    }

    /// What you usually eat at this meal, most often first, then the catalog's usual picks for it.
    static func usual(entries: [FoodEntry], meal: String, mine: [CatalogFood]) -> [CatalogFood] {
        let counts = Dictionary(grouping: entries.filter { $0.meal == meal }, by: { $0.name.lowercased() }).mapValues(\.count)
        let byName = Dictionary(mine.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        let yours = counts.sorted { $0.value > $1.value }.prefix(8).compactMap { byName[$0.key] }
        let starters: [String: [String]] = [
            "breakfast": ["Greek yogurt, plain", "Egg, large", "Oatmeal", "Banana", "Coffee, black", "Avocado toast", "Protein shake", "Toast, whole wheat"],
            "lunch": ["Chicken salad bowl", "Turkey sandwich", "Burrito bowl", "Poke bowl", "Grilled chicken breast", "Garden salad", "Tacos", "Wrap, chicken"],
            "dinner": ["Salmon fillet", "Grilled chicken breast", "Steak", "Spaghetti with marinara", "White rice", "Broccoli", "Chicken curry", "Roasted vegetables"],
            "snack": ["Apple", "Almonds", "Protein bar", "Greek yogurt, plain", "String cheese", "Hummus", "Dark chocolate", "Popcorn"],
        ]
        let fill = (starters[meal] ?? []).compactMap { n in FoodCatalog.all.first { $0.name == n } }
            .filter { f in !yours.contains { $0.name.lowercased() == f.name.lowercased() } }
        return Array((yours + fill).prefix(10))
    }
}

// MARK: - The open food database (branded and packaged foods, with photos)

@MainActor
enum FoodWebSearch {
    private static var cache: [String: [CatalogFood]] = [:]
    private static var lastAsk = Date.distantPast

    /// Products matching the words, with photos. The database asks apps to keep searches to a few a minute,
    /// so Keel waits for you to pause typing, spaces searches out and remembers every answer.
    static func search(_ query: String) async -> [CatalogFood] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 3 else { return [] }
        if let c = cache[q] { return c }
        let wait = 4 - Date().timeIntervalSince(lastAsk)
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        if Task.isCancelled { return [] }
        lastAsk = Date()
        var comps = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        comps.queryItems = [
            URLQueryItem(name: "search_terms", value: q), URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"), URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "12"), URLQueryItem(name: "sort_by", value: "unique_scans_n"),
            URLQueryItem(name: "fields", value: "code,product_name,product_name_en,brands,image_front_small_url,serving_size,serving_quantity,nutriments,ingredients_text"),
        ]
        guard let url = comps.url else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Keel/1.0 (iOS food search)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = obj["products"] as? [[String: Any]] else { return [] }
        let foods = products.compactMap(food(from:))
        cache[q] = foods
        return foods
    }

    private static func num(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) }
        return nil
    }

    // MARK: As you type (with photos)

    private static var suggestCache: [String: [CatalogFood]] = [:]

    /// Brand and product suggestions while you type, with product photos: Open Food Facts' fast search, which
    /// matches the start of each word ("kirkl chick" finds Kirkland chicken). Answers in a few milliseconds and is
    /// remembered, so going back over the same letters is instant. Falls back to the slower search if it fails.
    static func suggest(_ query: String) async -> [CatalogFood] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 2 else { return [] }
        if let c = suggestCache[q] { return c }
        let words = q.split(whereSeparator: { $0.isWhitespace }).map { String($0).filter { $0.isLetter || $0.isNumber || $0 == "'" } }.filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        let lucene = words.map { $0.count >= 2 ? $0 + "*" : $0 }.joined(separator: " ")
        var comps = URLComponents(string: "https://search.openfoodfacts.org/search")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: lucene), URLQueryItem(name: "page_size", value: "16"), URLQueryItem(name: "langs", value: "en"),
            URLQueryItem(name: "sort_by", value: "-unique_scans_n"),
            URLQueryItem(name: "fields", value: "code,product_name,product_name_en,brands,image_front_small_url,serving_size,serving_quantity,nutriments,ingredients_text"),
        ]
        guard let url = comps.url else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Keel/1.0 (iOS food search)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 6
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hits = obj["hits"] as? [[String: Any]] else {
            return q.count >= 3 ? await search(q) : []
        }
        var seen = Set<String>()
        let foods = hits.compactMap { loose(from: $0) }
            .filter { seen.insert(($0.brand + "|" + $0.name).lowercased()).inserted }
            // Ones with a photo first: that's what makes the list easy to scan.
            .sorted { ($0.imageURL != nil ? 1 : 0) > ($1.imageURL != nil ? 1 : 0) }
        if suggestCache.count > 300 { suggestCache.removeAll() }
        suggestCache[q] = foods
        return foods
    }

    /// Like `food(from:)`, but keeps products that don't have their nutrition in the search result yet
    /// (they're filled in by barcode when you pick one).
    static func loose(from p: [String: Any]) -> CatalogFood? {
        var item = p
        // The fast search returns brands as a list ("xx:chobani"); the product page as text.
        if let list = p["brands"] as? [String] {
            item["brands"] = list.map { b -> String in
                let raw = b.hasPrefix("xx:") ? String(b.dropFirst(3)) : b
                return raw.replacingOccurrences(of: "-", with: " ").capitalized
            }.first ?? ""
        }
        if let full = food(from: item) { return full }
        let name = [p["product_name_en"], p["product_name"]].compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
        guard !name.isEmpty, let code = p["code"] as? String, !code.isEmpty else { return nil }
        var f = NutritionFacts(); f.servingLabel = "1 serving"
        return CatalogFood(id: "w:" + code, emoji: FoodCatalog.emoji(for: name), name: name, serving: "Tap for details",
                           grams: nil, facts: f, imageURL: p["image_front_small_url"] as? String, barcode: code,
                           brand: (item["brands"] as? String) ?? "", ingredients: (p["ingredients_text"] as? String) ?? "", source: .web)
    }

    /// Fills in the nutrition for a suggestion that came without it, from the product's barcode page.
    static func complete(_ f: CatalogFood) async -> CatalogFood {
        guard f.facts.calories == nil, let code = f.barcode, let p = try? await OpenFoodFacts.fetch(code) else { return f }
        var out = f
        out.facts = p.facts
        out.serving = p.facts.servingLabel.isEmpty ? "1 serving" : p.facts.servingLabel
        out.grams = p.servingGrams
        if out.ingredients.isEmpty { out.ingredients = p.ingredients }
        if out.imageURL == nil { out.imageURL = p.imageURL }
        if out.brand.isEmpty { out.brand = p.brand }
        return out
    }

    static func food(from p: [String: Any]) -> CatalogFood? {
        let name = [p["product_name_en"], p["product_name"]].compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
        guard !name.isEmpty else { return nil }
        let n = p["nutriments"] as? [String: Any] ?? [:]
        let perServing = num(n["energy-kcal_serving"]) != nil && (num(p["serving_quantity"]) ?? 0) > 0
        let suffix = perServing ? "_serving" : "_100g"
        func v(_ k: String) -> Double? { num(n[k + suffix]) }
        guard let kcal = v("energy-kcal") else { return nil }
        var f = NutritionFacts()
        f.calories = kcal; f.protein = v("proteins"); f.carbs = v("carbohydrates"); f.fat = v("fat")
        f.fiber = v("fiber"); f.sugar = v("sugars"); f.addedSugar = v("added-sugars")
        f.sodiumMg = v("sodium").map { $0 * 1000 }; f.caffeineMg = v("caffeine").map { $0 * 1000 }
        let serving = perServing ? ((p["serving_size"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "1 serving") : "100 g"
        f.servingLabel = serving
        let brand = ((p["brands"] as? String) ?? "").components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? ""
        let code = (p["code"] as? String) ?? ""
        return CatalogFood(id: "w:" + (code.isEmpty ? name.lowercased() : code), emoji: FoodCatalog.emoji(for: name), name: name, serving: serving,
                           grams: perServing ? num(p["serving_quantity"]) : 100, facts: f,
                           imageURL: p["image_front_small_url"] as? String, barcode: code.isEmpty ? nil : code, brand: brand,
                           ingredients: (p["ingredients_text"] as? String) ?? "", source: .web)
    }
}

// MARK: - The plate: what you're about to log

struct PlateItem: Identifiable, Hashable {
    var id = UUID()
    var food: CatalogFood
    var servings: Double = 1
    var facts: NutritionFacts { food.facts.scaled(servings) }
}

@MainActor
enum PlateLogger {
    /// Logs each item as its own entry (so you can delete one later), checked against your diet, and saved to Apple Health.
    static func log(_ items: [PlateItem], meal: String, at date: Date, ctx: ModelContext) {
        for item in items {
            let f = item.food
            let ingredients = f.ingredients.isEmpty ? f.name : f.ingredients
            let verdict = DietChecker.check(name: f.name, brand: f.brand, ingredientsText: ingredients, facts: item.facts).verdict
            var facts = item.facts
            facts.servingLabel = f.serving
            let e = NutritionLog.logMeal(name: f.name, ingredients: ingredients, facts: facts, verdict: verdict, meal: meal, ctx: ctx)
            e.servings = item.servings
            e.barcode = f.barcode
            e.date = date
            MyFoods.remember(f)
        }
        try? ctx.save()
    }
}

// MARK: - Pieces

/// The food's picture: its product photo when there is one, otherwise a soft tile with its emoji.
struct FoodThumb: View {
    let food: CatalogFood
    var size: CGFloat = 44

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        ZStack {
            shape.fill(Self.tint(food.name).opacity(0.18))
            Text(food.emoji).font(.system(size: size * 0.55))
            if let s = food.imageURL, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image { img.resizable().scaledToFill() } else { Color.clear }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    static func tint(_ name: String) -> Color {
        let palette: [Color] = [.orange, .green, .pink, .yellow, .mint, .teal, .red, .purple, .brown, .cyan]
        let n = name.lowercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }   // same color every launch
        return palette[n % palette.count]
    }
}

/// "32P · 40C · 12F" in their colors.
struct MacroLine: View {
    let facts: NutritionFacts
    var body: some View {
        HStack(spacing: 6) {
            part(facts.protein, "P", DS.Palette.focus)
            part(facts.carbs, "C", .orange)
            part(facts.fat, "F", .pink)
        }
        .font(.caption2.weight(.semibold)).monospacedDigit()
    }
    private func part(_ v: Double?, _ l: String, _ c: Color) -> some View {
        Text("\(Int((v ?? 0).rounded()))\(l)").foregroundStyle(c)
    }
}

private struct FoodPickRow: View {
    let food: CatalogFood
    let added: Bool
    var onAdd: () -> Void
    var onOpen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    FoodThumb(food: food)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(food.name).font(DS.Font.body).foregroundStyle(DS.Palette.ink).lineLimit(1)
                        HStack(spacing: 6) {
                            Text([food.brand.isEmpty ? nil : food.brand, food.serving, food.facts.calories == nil ? nil : "\(food.kcal) kcal"].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                        }
                        MacroLine(facts: food.facts)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onAdd) {
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title2).symbolRenderingMode(.hierarchical)
                    .foregroundStyle(added ? DS.Palette.calm : DS.Palette.accent)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(added ? "Added \(food.name)" : "Add \(food.name)")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Log food: search with predictions, snap a meal, scan a barcode, build a plate, log it in one go

struct LogFoodView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var history: [FoodEntry]
    @Query(sort: \FoodProduct.lastScanned, order: .reverse) private var library: [FoodProduct]

    @State private var query = ""
    @State private var meal = FoodEntry.mealNow()
    @State private var when = Date()
    @State private var plate: [PlateItem] = []
    @State private var web: [CatalogFood] = []
    @State private var searchingWeb = false
    @State private var portion: CatalogFood?
    @State private var snapping = false
    @State private var scanning = false
    @State private var reviewing = false
    @State private var estimating = false
    @State private var mine: [CatalogFood] = []
    @State private var pool: [CatalogFood] = FoodCatalog.all

    init(startWithCamera: Bool = false) {
        let start = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        var d = FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.date >= start }, sortBy: [SortDescriptor(\.date, order: .reverse)])
        d.fetchLimit = 600
        _history = Query(d)
        _snapping = State(initialValue: startWithCamera)
    }

    // Worked out once per keystroke (the screen reads them several times per redraw).
    @State private var local: [CatalogFood] = []
    @State private var phrase: [PlateItem] = []
    private func recompute() {
        local = FoodCatalog.search(query, in: pool)
        phrase = query.count > 3 ? MealPhrase.resolve(query, pool: pool) : []
    }
    private var recent: [CatalogFood] {
        var seen = Set<String>()
        return history.compactMap { e -> CatalogFood? in
            let k = e.name.lowercased()
            guard !seen.contains(k) else { return nil }
            seen.insert(k)
            return mine.first { $0.name.lowercased() == k }
        }
        .prefix(12).map { $0 }
    }

    var body: some View {
        List {
            if query.isEmpty {
                Section {
                    FoodActionStrip {
                        Button { snapping = true } label: { BigAction(title: "Snap meal", icon: "camera") }
                        Button { scanning = true } label: { BigAction(title: "Barcode", icon: "barcode.viewfinder") }
                        Button { query = ""; focusHint = true } label: { BigAction(title: "Say it", icon: "text.bubble") }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
                } footer: {
                    if focusHint { Text("Type it the way you'd say it: “2 eggs, toast and a latte”. Keel splits it into foods and portions.") }
                }
                let yesterday = history.filter { Calendar.current.isDateInYesterday($0.date) && $0.meal == meal }
                if !yesterday.isEmpty {
                    Section {
                        Button {
                            let items = yesterday.map { e -> PlateItem in
                                let f = mine.first { $0.name.lowercased() == e.name.lowercased() }
                                    ?? CatalogFood(id: "y:" + e.id.uuidString, emoji: FoodCatalog.emoji(for: e.name), name: e.name, serving: "1 serving",
                                                   facts: e.facts.scaled(1 / max(e.servings, 0.25)), source: .mine)
                                return PlateItem(food: f, servings: e.servings)
                            }
                            withAnimation(DS.spring) { plate.append(contentsOf: items) }
                            Haptics.success()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.uturn.backward.circle.fill").font(.title2).foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Same as yesterday's \(meal)").font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                                    Text(yesterday.map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                                }
                                Spacer()
                                Text("\(Int(yesterday.reduce(0) { $0 + ($1.facts.calories ?? 0) })) kcal").font(.caption.weight(.semibold)).monospacedDigit()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                let usual = MyFoods.usual(entries: history, meal: meal, mine: mine)
                if !usual.isEmpty {
                    Section(history.isEmpty ? "Popular for \(meal)" : "Your usual \(meal)") { rows(usual) }
                }
                if !recent.isEmpty { Section("Recent") { rows(recent) } }
            } else {
                if phrase.count > 1 || (phrase.count == 1 && phrase[0].servings != 1) {
                    Section {
                        Button {
                            withAnimation(DS.spring) { plate.append(contentsOf: phrase) }
                            Haptics.success()
                            query = ""
                        } label: {
                            HStack(spacing: 12) {
                                HStack(spacing: -10) { ForEach(phrase.prefix(4)) { FoodThumb(food: $0.food, size: 34) } }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Add all \(phrase.count)").font(DS.Font.headline)
                                    Text(phrase.map { "\($0.servings.formatted())× \($0.food.name)" }.joined(separator: ", "))
                                        .font(.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                                }
                                Spacer()
                                Text("\(Int(phrase.reduce(0) { $0 + ($1.facts.calories ?? 0) })) kcal").font(.caption.weight(.semibold)).monospacedDigit()
                            }
                        }
                        .buttonStyle(.plain)
                    } header: { Text("Keel heard") }
                }
                if !local.isEmpty { Section("Best matches") { rows(local) } }
                Section {
                    if searchingWeb && web.isEmpty {
                        HStack { ProgressView(); Text("Looking up products…").font(.caption).foregroundStyle(DS.Palette.inkSoft) }
                    }
                    rows(web)
                } header: { if searchingWeb || !web.isEmpty { Text("Products") } }
                Section {
                    Button { Task { await estimate() } } label: {
                        HStack {
                            Label("Estimate “\(query)” on this iPhone", systemImage: "sparkles")
                            if estimating { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(estimating || !MealEstimator.isAvailable)
                } footer: {
                    if !MealEstimator.isAvailable { Text("Estimates for anything not in the list need Apple Intelligence.") }
                }
            }
        }
        .listStyle(.insetGrouped)
        .premiumBackground(.green)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search foods, or type what you ate")
        .autocorrectionDisabled()
        .navigationTitle("Log food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Meal", selection: $meal) {
                        ForEach(["breakfast", "lunch", "dinner", "snack"], id: \.self) { Text($0.capitalized) }
                    }
                } label: { Label(meal.capitalized, systemImage: "fork.knife").labelStyle(.titleAndIcon) }
            }
        }
        .safeAreaInset(edge: .bottom) { if !plate.isEmpty { tray } }
        .task {
            mine = MyFoods.foods(from: history)
            let lib = library.prefix(300).map { p in
                CatalogFood(id: "l:" + p.barcode, emoji: FoodCatalog.emoji(for: p.displayName), name: p.displayName,
                            serving: p.facts.servingLabel, grams: p.servingGrams, facts: p.facts, imageURL: p.imageURL,
                            barcode: p.barcode, brand: p.brand, ingredients: p.ingredients, source: .library, timesEaten: min(5, p.scanCount))
            }
            pool = mine + lib + FoodCatalog.all
        }
        .onChange(of: query) { recompute() }
        .onChange(of: pool.count) { recompute() }
        .task(id: query) {
            let q = query
            // Earlier suggestions stay up until the new ones arrive (no empty flash between letters).
            guard q.count >= 2, MealPhrase.parts(q).count == 1 else { web = []; searchingWeb = false; return }
            try? await Task.sleep(for: .milliseconds(160))           // a beat between letters, then search
            if Task.isCancelled { return }
            searchingWeb = true
            let found = await FoodWebSearch.suggest(q)               // brands and products with photos, as you type
            if Task.isCancelled { return }
            let localNames = Set(local.map { $0.name.lowercased() })
            web = found.filter { !localNames.contains($0.name.lowercased()) }
            searchingWeb = false
        }
        .sheet(item: $portion) { f in
            NavigationStack {
                PortionView(food: f) { servings in
                    withAnimation(DS.spring) { plate.append(PlateItem(food: f, servings: servings)) }
                    Haptics.success()
                }
            }
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $snapping) {
            NavigationStack {
                MealScanView { items in
                    withAnimation(DS.spring) { plate.append(contentsOf: items) }
                }
            }
        }
        .sheet(isPresented: $scanning) { NavigationStack { FoodScanView() } }
        .sheet(isPresented: $reviewing) {
            NavigationStack { PlateReview(plate: $plate, meal: $meal, when: $when) { logPlate() } }
                .presentationDetents([.medium, .large])
        }
    }

    @State private var focusHint = false

    private func rows(_ foods: [CatalogFood]) -> some View {
        ForEach(foods) { f in
            FoodPickRow(food: f, added: plate.contains { $0.food.id == f.id }, onAdd: {
                Haptics.tap()
                Task {
                    let full = await FoodWebSearch.complete(f)          // nutrition by barcode, if the suggestion had none
                    withAnimation(DS.spring) { plate.append(PlateItem(food: full)) }
                }
            }, onOpen: { Task { portion = await FoodWebSearch.complete(f) } })
        }
    }


    private var tray: some View {
        let total = plate.reduce(NutritionFacts()) { $0 + $1.facts }
        return HStack(spacing: 12) {
            Button { reviewing = true } label: {
                HStack(spacing: 10) {
                    HStack(spacing: -12) { ForEach(plate.suffix(3)) { FoodThumb(food: $0.food, size: 36).overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.Palette.canvas, lineWidth: 2)) } }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(plate.count) item\(plate.count == 1 ? "" : "s") · \(Int((total.calories ?? 0).rounded())) kcal").font(.subheadline.weight(.semibold))
                        MacroLine(facts: total)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button("Log") { logPlate() }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 12).padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func logPlate() {
        PlateLogger.log(plate, meal: meal, at: when, ctx: ctx)
        plate = []
        reviewing = false
        dismiss()
    }

    private func estimate() async {
        estimating = true
        defer { estimating = false }
        guard let e = await MealEstimator.estimate(query) else { return }
        var f = e.facts
        f.servingLabel = "1 serving"
        let food = CatalogFood(id: "e:" + UUID().uuidString, emoji: FoodCatalog.emoji(for: e.name), name: e.name.isEmpty ? query : e.name,
                               serving: "1 serving", facts: f, ingredients: e.ingredients, source: .photo)
        withAnimation(DS.spring) { plate.append(PlateItem(food: food)) }
        Haptics.success()
        query = ""
    }
}

// MARK: - Portion

struct PortionView: View {
    let food: CatalogFood
    var onAdd: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var servings = 1.0

    var body: some View {
        let f = food.facts.scaled(servings)
        Form {
            Section {
                HStack(spacing: 14) {
                    FoodThumb(food: food, size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(food.name).font(DS.Font.headline)
                        Text([food.brand.isEmpty ? nil : food.brand, food.serving].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
                HStack {
                    ForEach([0.5, 1, 1.5, 2], id: \.self) { v in
                        Button(v == 0.5 ? "½" : v == 1.5 ? "1½" : v.formatted()) { withAnimation(DS.spring) { servings = v } }
                            .buttonStyle(.bordered).tint(servings == v ? DS.Palette.accent : .gray)
                    }
                }
                Stepper("\(servings.formatted()) × \(food.serving)\(food.grams.map { " · \(Int(($0 * servings).rounded())) g" } ?? "")", value: $servings, in: 0.25...20, step: 0.25)
            }
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(Int((f.calories ?? 0).rounded()))").font(.largeTitle.weight(.bold)).monospacedDigit().contentTransition(.numericText())
                        Text("calories").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                    Spacer()
                    MacroDonut(facts: f).frame(width: 70, height: 70)
                }
                FactsGrid(facts: f)
            }
        }
        .navigationTitle("Portion")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Add") { onAdd(servings); dismiss() } }
        }
    }
}

/// Protein, carbs and fat as shares of the calories.
struct MacroDonut: View {
    let facts: NutritionFacts
    var body: some View {
        let p = (facts.protein ?? 0) * 4, c = (facts.carbs ?? 0) * 4, fat = (facts.fat ?? 0) * 9
        let total = max(p + c + fat, 1)
        ZStack {
            Circle().stroke(Color.gray.opacity(0.15), lineWidth: 9)
            Circle().trim(from: 0, to: p / total).stroke(DS.Palette.focus, style: StrokeStyle(lineWidth: 9, lineCap: .butt))
            Circle().trim(from: p / total, to: (p + c) / total).stroke(Color.orange, style: StrokeStyle(lineWidth: 9, lineCap: .butt))
            Circle().trim(from: (p + c) / total, to: 1).stroke(Color.pink, style: StrokeStyle(lineWidth: 9, lineCap: .butt))
                .opacity(fat > 0 ? 1 : 0)
        }
        .rotationEffect(.degrees(-90))
        .animation(DS.spring, value: total)
        .accessibilityLabel("Protein \(Int(p / total * 100))%, carbs \(Int(c / total * 100))%, fat \(Int(fat / total * 100))% of calories")
    }
}

// MARK: - Review the plate

private struct PlateReview: View {
    @Binding var plate: [PlateItem]
    @Binding var meal: String
    @Binding var when: Date
    var onLog: () -> Void

    var body: some View {
        let total = plate.reduce(NutritionFacts()) { $0 + $1.facts }
        List {
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(Int((total.calories ?? 0).rounded())) kcal").font(.title2.weight(.bold)).monospacedDigit()
                        MacroLine(facts: total)
                    }
                    Spacer()
                    MacroDonut(facts: total).frame(width: 54, height: 54)
                }
                Picker("Meal", selection: $meal) { ForEach(["breakfast", "lunch", "dinner", "snack"], id: \.self) { Text($0.capitalized) } }
                DatePicker("When", selection: $when, in: ...Date().addingTimeInterval(3600))
            }
            Section("On your plate") {
                ForEach($plate) { $item in
                    HStack(spacing: 12) {
                        FoodThumb(food: item.food, size: 38)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.food.name).lineLimit(1)
                            Text("\(item.servings.formatted()) × \(item.food.serving) · \(Int((item.facts.calories ?? 0).rounded())) kcal")
                                .font(.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        Stepper("", value: $item.servings, in: 0.25...20, step: 0.25).labelsHidden()
                    }
                }
                .onDelete { plate.remove(atOffsets: $0) }
            }
            Section { Button("Log \(plate.count) item\(plate.count == 1 ? "" : "s")", systemImage: "checkmark.circle.fill") { onLog() }.disabled(plate.isEmpty) }
        }
        .premiumBackground(.green)
        .navigationTitle("Your plate")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Snap a meal: the camera finds each food and its portion

struct DetectedFood: Identifiable, Hashable {
    var id = UUID()
    var food: CatalogFood
    var servings: Double = 1
    var confidence: Double
    var include = true
}

@MainActor
enum MealVision {
    private static let generic: Set<String> = ["food", "meal", "dish", "plate", "table", "tableware", "dining", "cuisine", "produce", "dinnerware",
                                               "kitchen", "restaurant", "bowl", "cup", "drink", "beverage", "utensil", "fork", "spoon", "structure",
                                               "people", "adult", "hand", "indoor", "outdoor", "container", "wood", "textile", "fast food", "baked goods",
                                               "dessert", "fruit", "vegetable", "meat", "seafood", "bread", "snack", "sweet", "jar", "bottle", "glass"]

    /// On this iPhone, nothing sent anywhere: Apple's image recognition names the foods, Keel matches each to its catalog.
    static func onDevice(_ image: UIImage) async -> [DetectedFood] {
        guard let cg = image.cgImage else { return [] }
        let labels: [(String, Double)] = await Task.detached(priority: .userInitiated) {
            let req = VNClassifyImageRequest()
            try? VNImageRequestHandler(cgImage: cg, orientation: .up).perform([req])
            return (req.results ?? []).filter { $0.confidence > 0.12 }.sorted { $0.confidence > $1.confidence }.prefix(12)
                .map { ($0.identifier.replacingOccurrences(of: "_", with: " "), Double($0.confidence)) }
        }.value
        var out: [DetectedFood] = []
        for (label, conf) in labels where !generic.contains(label) {
            guard let f = FoodCatalog.match(label: label), !out.contains(where: { $0.food.id == f.id }) else { continue }
            out.append(DetectedFood(food: f, confidence: conf))
            if out.count == 5 { break }
        }
        if out.isEmpty, MealEstimator.isAvailable {
            let words = labels.map(\.0).filter { !generic.contains($0) }.prefix(4).joined(separator: ", ")
            if !words.isEmpty, let e = await MealEstimator.estimate(words) {
                var f = e.facts
                f.servingLabel = "1 plate"
                out.append(DetectedFood(food: CatalogFood(id: "p:" + UUID().uuidString, emoji: FoodCatalog.emoji(for: e.name), name: e.name,
                                                          serving: "1 plate", facts: f, ingredients: e.ingredients, source: .photo), confidence: 0.4))
            }
        }
        return out
    }

    static var canSharpen: Bool { DirectAI.isConfigured }
    static var sharpenName: String { DirectAI.provider.name }

    /// With your own AI key: every food and drink on the plate, each with an estimated portion and its numbers.
    static func withAI(_ image: UIImage) async throws -> [DetectedFood] {
        guard let jpeg = resized(image, maxSide: 1024).jpegData(compressionQuality: 0.7) else { return [] }
        let item: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "required": ["name", "emoji", "portion", "grams", "calories", "protein", "carbs", "fat", "fiber", "sugar", "sodium_mg", "confidence"],
            "properties": [
                "name": ["type": "string"], "emoji": ["type": "string"], "portion": ["type": "string"],
                "grams": ["type": "number"], "calories": ["type": "number"], "protein": ["type": "number"], "carbs": ["type": "number"],
                "fat": ["type": "number"], "fiber": ["type": "number"], "sugar": ["type": "number"], "sodium_mg": ["type": "number"],
                "confidence": ["type": "number"],
            ] as [String: Any],
        ]
        let schema: [String: Any] = ["type": "object", "additionalProperties": false, "required": ["items"],
                                     "properties": ["items": ["type": "array", "items": item] as [String: Any]]]
        let data = try await DirectAI.json(
            task: "meal_photo",
            system: "You are a careful dietitian estimating what is in a meal photo. List each distinct food or drink separately (e.g. rice, chicken, sauce, drink). Estimate the visible portion from plate, bowl and utensil sizes, and give realistic totals for that portion, including cooking oil and sauces you can see. Confidence is 0 to 1. Use one food emoji per item. If nothing edible is visible, return no items.",
            user: "What's in this meal, with portions and nutrition for each item?",
            schema: schema, images: [jpeg])
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let items = obj["items"] as? [[String: Any]] else { return [] }
        func n(_ d: [String: Any], _ k: String) -> Double { (d[k] as? Double) ?? (d[k] as? Int).map(Double.init) ?? 0 }
        return items.compactMap { d in
            guard let name = d["name"] as? String, !name.isEmpty else { return nil }
            var f = NutritionFacts()
            f.calories = n(d, "calories"); f.protein = n(d, "protein"); f.carbs = n(d, "carbs"); f.fat = n(d, "fat")
            f.fiber = n(d, "fiber"); f.sugar = n(d, "sugar"); f.sodiumMg = n(d, "sodium_mg")
            let portion = (d["portion"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "1 serving"
            f.servingLabel = portion
            let emoji = (d["emoji"] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(2)) } ?? FoodCatalog.emoji(for: name)
            let food = CatalogFood(id: "p:" + UUID().uuidString, emoji: emoji, name: name.prefix(1).uppercased() + name.dropFirst(), serving: portion,
                                   grams: n(d, "grams") > 0 ? n(d, "grams") : nil, facts: f, source: .photo)
            return DetectedFood(food: food, confidence: min(1, max(0, n(d, "confidence"))))
        }
    }

    static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let s = image.size
        let scale = min(1, maxSide / max(s.width, s.height))
        guard scale < 1 || image.imageOrientation != .up else { return image }     // redrawing also turns camera photos upright
        let size = CGSize(width: s.width * scale, height: s.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

struct MealScanView: View {
    var onAdd: ([PlateItem]) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("nutrition.photo.autoSharpen") private var autoSharpen = false
    @State private var image: UIImage?
    @State private var found: [DetectedFood] = []
    @State private var busy = false
    @State private var sharpened = false
    @State private var error: String?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var addingMissed = false
    @State private var missedText = ""

    var body: some View {
        List {
            Section {
                ZStack(alignment: .bottomLeading) {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill().frame(height: 240).frame(maxWidth: .infinity).clipped()
                    } else {
                        RoundedRectangle(cornerRadius: 20).fill(Color.orange.opacity(0.12)).frame(height: 200)
                            .overlay { Label("Take a photo of your meal", systemImage: "camera.fill").foregroundStyle(.orange) }
                    }
                    if busy {
                        HStack(spacing: 8) { ProgressView().tint(.white); Text(sharpened ? "Sharpening…" : "Finding the foods…").foregroundStyle(.white) }
                            .font(.caption.weight(.semibold)).padding(10).background(.black.opacity(0.55), in: Capsule()).padding(10)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                HStack {
                    if CameraCapture.available { Button("Retake", systemImage: "camera") { showCamera = true } }
                    Spacer()
                    PhotosPicker(selection: $pickerItem, matching: .images) { Label("From Photos", systemImage: "photo") }
                }
                .buttonStyle(.bordered).controlSize(.small)
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            if image != nil && !busy {
                Section {
                    if found.isEmpty {
                        Text("Keel couldn't name the food in this photo. Add it below, or try a closer, brighter shot.").foregroundStyle(DS.Palette.inkSoft)
                    }
                    ForEach($found) { $d in
                        HStack(spacing: 12) {
                            Button { d.include.toggle() } label: {
                                Image(systemName: d.include ? "checkmark.circle.fill" : "circle").font(.title3)
                                    .foregroundStyle(d.include ? DS.Palette.accent : DS.Palette.inkSoft)
                            }
                            .buttonStyle(.plain)
                            FoodThumb(food: d.food, size: 40)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(d.food.name).lineLimit(1)
                                Text("\(d.servings.formatted()) × \(d.food.serving) · \(Int(((d.food.facts.calories ?? 0) * d.servings).rounded())) kcal")
                                    .font(.caption).foregroundStyle(DS.Palette.inkSoft)
                                MacroLine(facts: d.food.facts.scaled(d.servings))
                            }
                            Spacer()
                            Stepper("", value: $d.servings, in: 0.25...10, step: 0.25).labelsHidden()
                        }
                        .opacity(d.include ? 1 : 0.45)
                    }
                    .onDelete { found.remove(atOffsets: $0) }
                    if addingMissed {
                        HStack {
                            TextField("Something it missed, e.g. ranch", text: $missedText).onSubmit(addMissed)
                            Button("Add", action: addMissed).disabled(missedText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } else {
                        Button("Add something it missed", systemImage: "plus") { addingMissed = true }
                    }
                } header: { Text("On the plate") } footer: {
                    Text(sharpened ? "Portions estimated by \(MealVision.sharpenName) from your photo. Adjust anything that looks off." :
                         "Found on this iPhone. Portions start at one typical serving; adjust them with + and −.")
                }
                if MealVision.canSharpen && !sharpened {
                    Section {
                        Button { Task { await sharpen() } } label: { Label("Sharper read with \(MealVision.sharpenName)", systemImage: "wand.and.stars") }
                        Toggle("Always do this for meal photos", isOn: $autoSharpen)
                    } footer: { Text("Sends this photo to \(MealVision.sharpenName) with your own key, for every item and its portion.") }
                }
                if let error { Section { Text(error).font(.caption).foregroundStyle(.red) } }
            }
        }
        .premiumBackground(.orange)
        .navigationTitle("Snap a meal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add \(found.filter(\.include).count)") {
                    onAdd(found.filter(\.include).map { PlateItem(food: $0.food, servings: $0.servings) })
                    Haptics.success()
                    dismiss()
                }
                .disabled(found.filter(\.include).isEmpty)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture { img in
                showCamera = false
                if let img { Task { await analyze(img) } } else if image == nil { dismiss() }
            }
            .ignoresSafeArea()
        }
        .task {
            guard image == nil, CameraCapture.available else { return }
            try? await Task.sleep(for: .milliseconds(350))              // let this screen finish appearing first
            showCamera = true
        }
        .onChange(of: pickerItem) {
            guard let pickerItem else { return }
            Task {
                if let data = try? await pickerItem.loadTransferable(type: Data.self), let img = UIImage(data: data) { await analyze(img) }
            }
        }
    }

    private func analyze(_ img: UIImage) async {
        let upright = MealVision.resized(img, maxSide: 1600)
        withAnimation { image = upright }
        busy = true
        sharpened = false
        error = nil
        found = await MealVision.onDevice(upright)
        busy = false
        if autoSharpen && MealVision.canSharpen { await sharpen() }
    }

    private func sharpen() async {
        guard let image else { return }
        busy = true
        sharpened = true
        defer { busy = false }
        do {
            let items = try await MealVision.withAI(image)
            if !items.isEmpty { withAnimation(DS.spring) { found = items } }
            else { error = "\(MealVision.sharpenName) didn't see any food in this photo." }
        } catch {
            sharpened = false
            self.error = error.localizedDescription
        }
    }

    private func addMissed() {
        let t = missedText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        if let f = FoodCatalog.search(t, in: FoodCatalog.all, limit: 1).first {
            withAnimation(DS.spring) { found.append(DetectedFood(food: f, confidence: 1)) }
            missedText = ""
            addingMissed = false
        } else {
            Task {
                if let e = await MealEstimator.estimate(t) {
                    var f = e.facts
                    f.servingLabel = "1 serving"
                    found.append(DetectedFood(food: CatalogFood(id: "e:" + UUID().uuidString, emoji: FoodCatalog.emoji(for: e.name), name: e.name,
                                                                serving: "1 serving", facts: f, source: .photo), confidence: 1))
                } else {
                    error = "Couldn't find “\(t)”. Try a simpler name, like “salad dressing”."
                }
                missedText = ""
                addingMissed = false
            }
        }
    }
}

/// The system camera, for one photo.
struct CameraCapture: UIViewControllerRepresentable {
    var onDone: (UIImage?) -> Void

    static var available: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return UIImagePickerController.isSourceTypeAvailable(.camera)
        #endif
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        vc.sourceType = Self.available ? .camera : .photoLibrary
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onDone: (UIImage?) -> Void
        init(onDone: @escaping (UIImage?) -> Void) { self.onDone = onDone }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onDone(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onDone(nil) }
    }
}
