import Foundation
import SwiftUI

// MARK: - Your diet guide (bundled from Brian's ADHD Brain Diet guide)

struct GuideEntry: Codable, Hashable, Identifiable {
    var s: Int                     // section number in the guide
    var section: String
    var group: String
    var name: String
    var status: String             // approved | caution | avoid | best
    var details: String
    var alt: String?
    var id: String { "\(s)|\(name)" }

    var verdict: DietVerdict {
        switch status { case "approved", "best": .green; case "caution": .yellow; case "avoid": .red; default: .unknown }
    }
}

enum DietGuide {
    private struct File: Codable { var version: Int; var entries: [GuideEntry] }

    static let entries: [GuideEntry] = {
        guard let url = Bundle.main.url(forResource: "DietGuide", withExtension: "json"),
              let d = try? Data(contentsOf: url), let f = try? JSONDecoder().decode(File.self, from: d) else { return [] }
        return f.entries
    }()

    static let generic: Set<String> = ["the", "and", "any", "all", "flavor", "flavors", "organic", "original", "plain", "with", "for",
                                       "brand", "brands", "store", "version", "varieties", "only", "unsweetened", "natural", "naturals", "classic", "style"]

    static func tokens(_ s: String) -> [String] {
        s.lowercased()
            .replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !generic.contains($0) }
    }

    /// The guide's own word on this product, if it names it (brand + product words).
    static func match(name: String, brand: String) -> GuideEntry? {
        let hay = Set(tokens(brand + " " + name))
        guard !hay.isEmpty else { return nil }
        let brandTokens = Set(tokens(brand))
        var best: (GuideEntry, Double)?
        for e in entries where e.s != 19 && e.s != 0 {
            let t = tokens(e.name)
            guard t.count >= 2 else { continue }
            let hits = t.filter(hay.contains).count
            let score = Double(hits) / Double(t.count)
            // The brand has to match, and most of the entry's words.
            guard hits >= 2, score >= 0.6, brandTokens.isEmpty || !brandTokens.isDisjoint(with: t) else { continue }
            if score > (best?.1 ?? 0) { best = (e, score) }
        }
        return best?.0
    }

    // MARK: Swaps ("what to grab instead")

    static let sectionWords: [Int: [String]] = [
        1: ["meat", "jerky", "sausage", "hot dog", "deli", "turkey", "chicken", "beef", "ham", "bacon", "meat stick", "pepperoni", "salami"],
        2: ["tuna", "salmon", "sardine", "fish", "seafood", "mackerel", "anchov"],
        3: ["yogurt", "yoghurt", "cheese", "egg", "kefir", "butter", "cottage", "dairy", "cow milk", "whole milk"],
        4: ["almond milk", "oat milk", "plant milk", "walnut milk", "coconut milk", "creamer", "milk substitute", "non-dairy", "plant-based beverage"],
        5: ["bread", "bagel", "bun", "cracker", "sourdough", "muffin", "loaf"],
        6: ["tortilla", "wrap"],
        7: ["pasta", "rice", "oat", "cereal", "granola", "quinoa", "flour", "noodle", "grain"],
        9: ["nut", "almond", "peanut butter", "seed", "olive oil", "avocado oil", "cooking oil", "trail mix", "cashew", "walnut", "pistachio"],
        10: ["bean", "lentil", "chickpea", "hummus", "legume", "refried"],
        11: ["jam", "jelly", "preserve", "spread", "marmalade", "hazelnut spread"],
        12: ["ketchup", "mayo", "mayonnaise", "sauce", "dressing", "bbq", "barbecue", "mustard", "seasoning", "marinade", "ranch", "vinegar", "salsa", "hot sauce", "condiment"],
        13: ["soda", "drink", "beverage", "water", "juice", "tea", "coffee", "energy", "kombucha", "lemonade", "sports drink", "electrolyte", "cola", "sparkling"],
        14: ["chip", "crisp", "protein bar", "snack", "popcorn", "pretzel", "cookie", "bar"],
        15: ["candy", "candies", "chocolate", "gummy", "gummies", "confection", "licorice", "lollipop", "sweets"],
        16: ["supplement", "vitamin", "capsule", "softgel", "multivitamin"],
        17: ["sweetener", "syrup", "honey", "stevia", "monk fruit", "sugar substitute"],
    ]

    /// Which section of the guide a product belongs to, from its name and store categories.
    static func section(for name: String, categories: [String]) -> Int? {
        let hay = (name + " " + categories.joined(separator: " ").replacingOccurrences(of: "en:", with: "").replacingOccurrences(of: "-", with: " ")).lowercased()
        var best: (Int, Int)?
        for (s, words) in sectionWords {
            let hits = words.reduce(0) { $0 + (hay.contains($1) ? ($1.count > 5 ? 2 : 1) : 0) }
            if hits > (best?.1 ?? 0) { best = (s, hits) }
        }
        return best?.0
    }

    /// Up to `limit` approved picks from the same part of the guide, closest match first.
    static func swaps(for name: String, categories: [String], excluding: String? = nil, limit: Int = 3) -> [GuideEntry] {
        guard let s = section(for: name, categories: categories) else { return [] }
        let words = Set(tokens(name + " " + categories.joined(separator: " ").replacingOccurrences(of: "en:", with: "")))
        let candidates = entries.filter { $0.s == s && ($0.status == "approved" || $0.status == "best") && $0.name != excluding }
        return candidates
            .map { e -> (GuideEntry, Int) in
                let t = Set(tokens(e.name + " " + e.group + " " + e.details.prefix(160)))
                return (e, t.intersection(words).count)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}

// MARK: - Verdicts

enum DietVerdict: String, Codable, Comparable {
    case green, yellow, red, unknown
    private var rank: Int { switch self { case .green: 0; case .unknown: 1; case .yellow: 2; case .red: 3 } }
    static func < (a: DietVerdict, b: DietVerdict) -> Bool { a.rank < b.rank }

    var label: String {
        switch self {
        case .green: "Yes, go for it"
        case .yellow: "Okay sometimes"
        case .red: "Skip it"
        case .unknown: "Couldn't check"
        }
    }
    var emoji: String { switch self { case .green: "🟢"; case .yellow: "🟡"; case .red: "🔴"; case .unknown: "⚪️" } }
    var color: Color { switch self { case .green: DS.Palette.calm; case .yellow: .orange; case .red: .red; case .unknown: .gray } }
}

struct DietFinding: Codable, Hashable, Identifiable {
    var level: DietVerdict
    var rule: String               // "Soy", "Artificial dye", "Pork [Lev 11:7-8]"…
    var matched: String            // the ingredient that triggered it
    var why: String
    var id: String { rule + "|" + matched }
}

struct DietResult: Codable, Hashable {
    var verdict: DietVerdict
    var findings: [DietFinding]
    var positives: [String]
    var score: Int                 // 0–100 brain-food score
    var guideNote: String?         // what the guide says about this exact product
}

/// The values the checker needs, from a label, a database or an estimate.
struct NutritionFacts: Codable, Hashable {
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var fiber: Double?
    var sugar: Double?
    var addedSugar: Double?
    var sodiumMg: Double?
    var caffeineMg: Double?
    var magnesiumMg: Double?
    var zincMg: Double?
    var ironMg: Double?
    var servingLabel: String = "per serving"

    func scaled(_ x: Double) -> NutritionFacts {
        func s(_ v: Double?) -> Double? { v.map { $0 * x } }
        return NutritionFacts(calories: s(calories), protein: s(protein), carbs: s(carbs), fat: s(fat), fiber: s(fiber),
                              sugar: s(sugar), addedSugar: s(addedSugar), sodiumMg: s(sodiumMg), caffeineMg: s(caffeineMg),
                              magnesiumMg: s(magnesiumMg), zincMg: s(zincMg), ironMg: s(ironMg), servingLabel: servingLabel)
    }
}

/// Checks a product against the guide's "7 things to scan on every label", the sweetener tiers and Leviticus 11.
/// Red = the guide says avoid. Yellow = read the label / a small allowance. Green = clean.
enum DietChecker {
    struct Rule {
        let terms: [String]
        let level: DietVerdict
        let rule: String
        let why: String
    }

    static let rules: [Rule] = [
        // Soy, in every form (sunflower lecithin is fine).
        Rule(terms: ["soy lecithin", "soya lecithin", "soybean oil", "soy protein", "soy flour", "soybean", "soybeans", "soya", "soy sauce", "tamari", "shoyu",
                     "textured vegetable protein", "tvp", "edamame", "tofu", "miso", "tempeh", "hydrolyzed soy", "soy"],
             level: .red, rule: "Soy", why: "Soy is off your plan in every form."),
        Rule(terms: ["vegetable oil", "vegetable shortening"], level: .red, rule: "Soy (vegetable oil)",
             why: "Store “vegetable oil” is a soybean and canola blend. Choose avocado, olive or coconut oil."),
        // Artificial dyes.
        Rule(terms: ["red 40", "red no. 40", "red #40", "allura red", "e129", "red 3", "erythrosine", "e127", "yellow 5", "yellow no. 5", "tartrazine", "e102",
                     "yellow 6", "yellow no. 6", "sunset yellow", "e110", "blue 1", "blue no. 1", "brilliant blue", "e133", "blue 2", "indigotine", "indigo carmine",
                     "e132", "green 3", "fast green", "e143", "fd&c", "artificial color", "artificial colour", "artificial colors"],
             level: .red, rule: "Artificial dye", why: "Artificial dyes are out. Any one present means avoid."),
        // Leviticus 11.
        Rule(terms: ["pork", "ham", "bacon", "lard", "prosciutto", "pepperoni", "pancetta", "chorizo", "pork gelatin", "pork fat", "pork broth", "guanciale"],
             level: .red, rule: "Pork [Lev 11:7-8]", why: "All pork in every form is removed from your diet."),
        Rule(terms: ["shrimp", "prawn", "crab", "lobster", "oyster", "clam", "mussel", "scallop", "squid", "calamari", "octopus", "crawfish", "crayfish",
                     "catfish", "eel", "shark", "swordfish", "sturgeon", "caviar", "shellfish", "crustacean", "mollusc", "mollusk"],
             level: .red, rule: "Shellfish or no-scale fish [Lev 11:9-12]", why: "Only fish with fins and scales. No shellfish."),
        // Sweeteners, tier 5 and the avoided sugar alcohols.
        Rule(terms: ["sucralose", "splenda", "aspartame", "saccharin", "acesulfame", "ace-k", "neotame", "advantame"],
             level: .red, rule: "Artificial sweetener (Tier 5)", why: "Artificial sweeteners disrupt the gut you're rebuilding."),
        Rule(terms: ["sorbitol", "maltitol"], level: .red, rule: "Sugar alcohol (avoid)", why: "Sorbitol and maltitol work against your gut and blood sugar."),
        // Caution list.
        Rule(terms: ["erythritol", "xylitol"], level: .yellow, rule: "Sugar alcohol (Tier 3)",
             why: "Cardiovascular signal in recent studies. Prefer allulose; keep erythritol under 10 g a day."),
        Rule(terms: ["honey", "maple syrup", "date syrup", "coconut sugar", "coconut palm sugar"], level: .yellow, rule: "Whole-food sugar (Tier 2)",
             why: "Real sugar, but unrefined. A small, intentional allowance, not a daily habit."),
        Rule(terms: ["natural flavor", "natural flavors", "natural flavour", "natural flavours"], level: .yellow, rule: "Natural flavors",
             why: "Can legally hide soy or pork derivatives. When in doubt, skip it."),
        Rule(terms: ["carrageenan", "gellan gum"], level: .yellow, rule: "Gums", why: "Your plan avoids carrageenan and gellan gum."),
        Rule(terms: ["canola oil", "rapeseed oil", "corn oil", "cottonseed oil"], level: .yellow, rule: "Seed oil",
             why: "Not the cleanest fat. Avocado, olive, coconut oil or tallow are better."),
        Rule(terms: ["gelatin", "gelatine"], level: .yellow, rule: "Gelatin (check source)", why: "Often pork-derived [Lev 11:7-8]. Look for beef gelatin or pectin."),
        Rule(terms: ["lecithin"], level: .yellow, rule: "Lecithin (check source)", why: "If it isn't sunflower lecithin, it may be soy."),
        Rule(terms: ["sodium nitrite", "sodium nitrate", "potassium nitrite"], level: .yellow, rule: "Nitrites", why: "Prefer uncured, no-nitrite options."),
    ]

    /// Tier 4: refined sugars under all their names.
    static let refinedSugars = ["high fructose corn syrup", "hfcs", "corn syrup", "glucose syrup", "glucose-fructose", "dextrose", "maltodextrin",
                                "cane sugar", "evaporated cane juice", "cane juice", "raw cane sugar", "turbinado", "demerara", "sucanat", "brown sugar",
                                "invert sugar", "rice syrup", "malt syrup", "barley malt", "agave", "fruit juice concentrate", "juice concentrate",
                                "sucrose", "fructose", "sugar"]

    static let positiveWords: [(String, String)] = [
        ("salmon", "Omega-3 (oily fish)"), ("sardine", "Omega-3 (oily fish)"), ("mackerel", "Omega-3 (oily fish)"), ("herring", "Omega-3 (oily fish)"),
        ("trout", "Omega-3 (oily fish)"), ("walnut", "Omega-3 (walnuts)"), ("flax", "Omega-3 (flax)"), ("chia", "Omega-3 (chia)"),
        ("pumpkin seed", "Zinc + magnesium (pumpkin seeds)"), ("pepitas", "Zinc + magnesium (pumpkin seeds)"),
        ("live cultures", "Probiotic"), ("live and active cultures", "Probiotic"), ("probiotic", "Probiotic"), ("kefir", "Probiotic"),
        ("inulin", "Prebiotic fiber"), ("chicory", "Prebiotic fiber"), ("beef liver", "Iron + B12"), ("spinach", "Iron + magnesium"),
    ]

    /// Splits an ingredients list into ingredients, in order (sub-ingredients in brackets included).
    static func ingredients(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .components(separatedBy: CharacterSet(charactersIn: ",;()[]"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".*"))) }
            .filter { !$0.isEmpty }
    }

    static func containsWord(_ hay: String, _ term: String) -> Bool {
        hay.range(of: "(^|[^a-z0-9])" + NSRegularExpression.escapedPattern(for: term) + "($|[^a-z0-9])", options: .regularExpression) != nil
    }

    static func check(name: String, brand: String = "", ingredientsText: String, additiveTags: [String] = [], allergenTags: [String] = [],
                      facts: NutritionFacts?) -> DietResult {
        var findings: [DietFinding] = []
        let cleaned = ingredientsText.lowercased()
            .replacingOccurrences(of: #"(soy|dairy|gluten|nut)[- ]free"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"no (added )?sugar(s)? added|no added sugar|no soy"#, with: " ", options: .regularExpression)
        let list = ingredients(cleaned)
        let haystack = list.joined(separator: " , ") + " , " + name.lowercased()

        func add(_ level: DietVerdict, _ rule: String, _ matched: String, _ why: String) {
            if !findings.contains(where: { $0.rule == rule }) { findings.append(DietFinding(level: level, rule: rule, matched: matched, why: why)) }
        }

        for r in rules {
            for t in r.terms where containsWord(haystack, t) {
                // Sunflower lecithin and beef gelatin are fine; specific soy terms take priority over the generic ones.
                if t == "lecithin" && (haystack.contains("sunflower lecithin") || haystack.contains("soy lecithin")) { continue }
                if (t == "gelatin" || t == "gelatine") && (haystack.contains("beef gelatin") || haystack.contains("bovine gelatin") || haystack.contains("pork gelatin")) { continue }
                if t == "ham" && (haystack.contains("hamburger") || haystack.contains("graham")) { continue }
                add(r.level, r.rule, t, r.why)
                break
            }
        }

        // Tier 4 sugars: red when it's a main ingredient (first five) or there's real added sugar.
        let added = facts?.addedSugar
        for (i, ing) in list.enumerated() {
            guard let term = refinedSugars.first(where: { containsWord(ing, $0) }) else { continue }
            if ["coconut sugar", "coconut palm sugar", "date sugar", "maple sugar"].contains(where: { ing.contains($0) }) { continue }
            if term == "sugar" && (ing.contains("sugar alcohol") || ing.contains("no sugar")) { continue }
            let main = i < 5
            let lots = (added ?? 0) > 6
            add(main || lots ? .red : .yellow, "Refined sugar (Tier 4)", ing,
                main ? "\(ing.capitalized) is one of the first five ingredients. Your rule: put it back."
                     : "Refined sugar appears in the list. Keep it rare.")
            break
        }
        if let a = added, a > 6, !findings.contains(where: { $0.rule == "Refined sugar (Tier 4)" }) {
            add(a > 10 ? .red : .yellow, "Added sugar", String(format: "%.0f g", a), "That's a lot of added sugar for one serving.")
        }
        if let c = facts?.caffeineMg, c > 200 {
            add(.yellow, "High caffeine", String(format: "%.0f mg", c), "Over 200 mg is pre-workout territory, not a daily drink. 50–150 mg with L-theanine is the sweet spot.")
        }

        // Database tags catch what the text misses.
        let dyeE = ["en:e129", "en:e127", "en:e102", "en:e110", "en:e133", "en:e132", "en:e143"]
        if let tag = additiveTags.first(where: dyeE.contains) { add(.red, "Artificial dye", tag.replacingOccurrences(of: "en:", with: "").uppercased(), "Artificial dyes are out.") }
        if let tag = additiveTags.first(where: { ["en:e955", "en:e951", "en:e954", "en:e950", "en:e961", "en:e969"].contains($0) }) {
            add(.red, "Artificial sweetener (Tier 5)", tag.replacingOccurrences(of: "en:", with: "").uppercased(), "Artificial sweeteners disrupt the gut you're rebuilding.")
        }
        if allergenTags.contains("en:soybeans") { add(.red, "Soy", "soy (allergen list)", "The allergen list says this contains soy.") }
        if allergenTags.contains(where: { ["en:crustaceans", "en:molluscs"].contains($0) }) {
            add(.red, "Shellfish or no-scale fish [Lev 11:9-12]", "shellfish (allergen list)", "The allergen list says this contains shellfish.")
        }

        // Good stuff.
        var positives: [String] = []
        if let p = facts?.protein, p >= 10 { positives.append(String(format: "%.0f g protein", p)) }
        if let f = facts?.fiber, f >= 5 { positives.append(String(format: "%.0f g fiber", f)) }
        for (w, label) in positiveWords where haystack.contains(w) && !positives.contains(label) { positives.append(label) }
        if haystack.contains("dark chocolate"), let pct = Int(haystack.range(of: #"\d{2}%"#, options: .regularExpression).map { String(haystack[$0].dropLast()) } ?? ""), pct >= 70 {
            positives.append("Magnesium (\(pct)% dark chocolate)")
        }

        // The guide's own word on this exact product.
        var note: String?
        if let g = DietGuide.match(name: name, brand: brand) {
            note = "Your guide: \(g.name) — \(g.status.uppercased()). \(g.details)"
            if g.verdict == .red { add(.red, "On your avoid list", g.name, g.details) }
            if g.verdict == .yellow { add(.yellow, "Caution in your guide", g.name, g.details) }
        }

        var verdict: DietVerdict = findings.map(\.level).max() ?? .green
        if ingredientsText.trimmingCharacters(in: .whitespaces).isEmpty && note == nil { verdict = max(verdict, .unknown) }

        var score = 70
        score -= findings.filter { $0.level == .yellow }.count * 12
        score -= findings.filter { $0.level == .red }.count * 30
        score += positives.count * 8
        if let s = facts?.addedSugar { score -= Int(min(20, s * 2)) }
        if verdict == .red { score = min(score, 25) }
        return DietResult(verdict: verdict, findings: findings.sorted { $0.level > $1.level }, positives: positives,
                          score: max(0, min(100, score)), guideNote: note)
    }

    /// A described meal ("two eggs and bacon") checked by its words, for logging without a label.
    static func checkWords(_ text: String) -> DietResult {
        check(name: text, ingredientsText: text, facts: nil)
    }
}
