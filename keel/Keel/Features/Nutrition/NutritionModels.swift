import Foundation
import SwiftData

/// A product you've scanned. Your own food library: checked first on every scan, works offline,
/// and grows with every barcode or label you scan.
@Model final class FoodProduct {
    var id: UUID = UUID()
    var barcode: String = ""                   // "label-…" when added from a label photo with no barcode
    var name: String = ""
    var brand: String = ""
    var ingredients: String = ""
    var categories: [String] = []
    var additives: [String] = []
    var allergens: [String] = []
    var imageURL: String?
    var facts: NutritionFacts = NutritionFacts()
    var servingGrams: Double?
    var source: String = "Open Food Facts"     // "Open Food Facts", "Label scan", "You"
    var resultData: Data?                      // DietResult as JSON
    var overrideRaw: String?                   // your own call, when you've checked it yourself
    var note: String = ""
    var scanCount: Int = 0
    var firstScanned: Date = Date()
    var lastScanned: Date = Date()
    var isFavorite: Bool = false

    init(barcode: String, name: String) {
        self.barcode = barcode
        self.name = name
    }

    var result: DietResult? {
        get { resultData.flatMap { try? JSONDecoder().decode(DietResult.self, from: $0) } }
        set { resultData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var checkedVerdict: DietVerdict { result?.verdict ?? .unknown }
    var verdict: DietVerdict { overrideRaw.flatMap(DietVerdict.init(rawValue:)) ?? checkedVerdict }
    var displayName: String { name.isEmpty ? "Unnamed product" : name }

    /// Runs the diet checker again (after an edit, a label scan, or a guide update).
    func recheck() {
        result = DietChecker.check(name: name, brand: brand, ingredientsText: ingredients, additiveTags: additives,
                                   allergenTags: allergens, facts: facts)
    }
}

/// One thing you ate or drank.
@Model final class FoodEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var name: String = ""
    var meal: String = "snack"                 // breakfast | lunch | dinner | snack
    var servings: Double = 1
    var facts: NutritionFacts = NutritionFacts()   // totals for what you ate (already × servings)
    var barcode: String?
    var verdictRaw: String = DietVerdict.unknown.rawValue
    var tagsRaw: String = ""                   // "oilyfish,pumpkin,omega3…" for the brain-food checklist
    var savedToHealth: Bool = false
    var note: String = ""

    init(name: String, facts: NutritionFacts, meal: String, verdict: DietVerdict) {
        self.name = name
        self.facts = facts
        self.meal = meal
        self.verdictRaw = verdict.rawValue
    }

    var verdict: DietVerdict { DietVerdict(rawValue: verdictRaw) ?? .unknown }
    var tags: Set<String> { Set(tagsRaw.split(separator: ",").map(String.init)) }

    static func mealNow(for date: Date = Date()) -> String {
        let h = Calendar.current.component(.hour, from: date)
        return h < 11 ? "breakfast" : h < 15 ? "lunch" : h < 17 ? "snack" : h < 21 ? "dinner" : "snack"
    }
}

/// The brain foods your guide asks for, spotted from names and ingredients.
enum BrainFoods {
    struct Item: Identifiable {
        let id: String
        let title: String
        let icon: String
        let goal: String
        let perWeek: Int?          // weekly goal, or nil for a daily one
        let words: [String]
    }

    static let items: [Item] = [
        Item(id: "oilyfish", title: "Oily fish", icon: "fish.fill", goal: "2–3 servings a week for omega-3", perWeek: 2,
             words: ["salmon", "sardine", "mackerel", "herring", "trout", "anchov", "tuna"]),
        Item(id: "pumpkin", title: "Pumpkin seeds", icon: "leaf.fill", goal: "A small handful daily for zinc", perWeek: nil,
             words: ["pumpkin seed", "pepita"]),
        Item(id: "magnesium", title: "Magnesium food", icon: "bolt.heart.fill", goal: "Leafy greens, nuts, seeds or 70%+ dark chocolate", perWeek: nil,
             words: ["spinach", "kale", "almond", "cashew", "chia", "dark chocolate", "avocado", "black bean", "pumpkin seed", "swiss chard"]),
        Item(id: "omega3", title: "Omega-3 plant food", icon: "drop.fill", goal: "Walnuts, chia or flax", perWeek: nil,
             words: ["walnut", "chia", "flax"]),
        Item(id: "protein", title: "Protein at breakfast", icon: "sunrise.fill", goal: "Steadier focus through the morning", perWeek: nil,
             words: []),
        Item(id: "probiotic", title: "Gut food", icon: "allergens", goal: "Yogurt, kefir, sauerkraut or kimchi", perWeek: nil,
             words: ["yogurt", "yoghurt", "kefir", "sauerkraut", "kimchi", "live cultures", "probiotic"]),
    ]

    static func tags(for text: String) -> [String] {
        let t = text.lowercased()
        return items.filter { !$0.words.isEmpty && $0.words.contains(where: { w in t.contains(w) }) }.map(\.id)
    }
}
