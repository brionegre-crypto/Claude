import SwiftUI
import UniformTypeIdentifiers
import PDFKit

// MARK: - Your own diets
//
// Most food apps only know a few big diets (keto, vegan…). Here you can bring your own: upload the plan your
// doctor, dietitian or faith gave you (PDF, Word, text), paste it, or start from a template. Keel turns it into
// three plain lists (avoid, careful, good) that every scan, search and logged meal is checked against.
// You can switch the built-in brain diet off and use only yours.

struct PersonalDiet: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var avoid: [String] = []
    var caution: [String] = []
    var favor: [String] = []
    var notes: String = ""
    var on = true

    var summary: String {
        "\(avoid.count) to avoid · \(caution.count) careful · \(favor.count) good"
    }
}

enum PersonalDiets {
    static let key = "diet.personal.v1"
    static let builtInKey = "diet.builtIn.on"

    // Read on every scan (sometimes off the main thread), so it is kept in memory and refreshed on save.
    nonisolated(unsafe) private static var cache: [PersonalDiet]?

    static var all: [PersonalDiet] {
        get {
            if let c = cache { return c }
            let v = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([PersonalDiet].self, from: $0) } ?? []
            cache = v
            return v
        }
        set {
            cache = newValue
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key)
        }
    }

    static var active: [PersonalDiet] { all.filter(\.on) }

    /// The built-in brain diet (soy, dyes, sweeteners, Leviticus 11…). On unless you switch it off.
    static var builtInOn: Bool { UserDefaults.standard.object(forKey: builtInKey) as? Bool ?? true }

    static func save(_ d: PersonalDiet) {
        var list = all
        if let i = list.firstIndex(where: { $0.id == d.id }) { list[i] = d } else { list.append(d) }
        all = list
    }

    static func delete(_ id: UUID) { all = all.filter { $0.id != id } }

    // MARK: Templates

    static let templates: [PersonalDiet] = [
        PersonalDiet(name: "Gluten-free",
                     avoid: ["wheat", "barley", "rye", "malt", "spelt", "semolina", "durum", "farro", "couscous", "seitan", "bulgur", "triticale", "brewer's yeast", "wheat flour", "graham"],
                     caution: ["oats", "modified food starch", "natural flavors"], favor: ["rice", "quinoa", "buckwheat", "certified gluten-free"]),
        PersonalDiet(name: "Dairy-free",
                     avoid: ["milk", "whey", "casein", "caseinate", "butter", "cream", "cheese", "yogurt", "lactose", "ghee", "milk solids", "buttermilk", "curds"],
                     caution: ["natural flavors", "lactic acid"], favor: ["oat milk", "almond milk", "coconut milk"]),
        PersonalDiet(name: "Peanut & tree-nut allergy",
                     avoid: ["peanut", "peanuts", "almond", "cashew", "walnut", "pecan", "pistachio", "hazelnut", "macadamia", "brazil nut", "pine nut", "praline", "marzipan", "nougat"],
                     caution: ["may contain nuts", "processed in a facility", "natural flavors"]),
        PersonalDiet(name: "Vegetarian",
                     avoid: ["beef", "chicken", "pork", "turkey", "lamb", "veal", "fish", "anchovy", "gelatin", "lard", "tallow", "chicken broth", "beef broth", "bacon", "ham", "rennet"],
                     caution: ["natural flavors", "carmine", "worcestershire"], favor: ["beans", "lentils", "tofu", "eggs"]),
        PersonalDiet(name: "Vegan",
                     avoid: ["beef", "chicken", "pork", "turkey", "lamb", "fish", "anchovy", "gelatin", "lard", "tallow", "milk", "whey", "casein", "butter", "cheese", "cream", "egg", "eggs", "honey", "carmine", "shellac", "rennet"],
                     caution: ["natural flavors", "vitamin d3", "sugar"], favor: ["beans", "lentils", "tofu", "tempeh", "nuts", "seeds"]),
        PersonalDiet(name: "Keto / low-carb",
                     avoid: ["sugar", "cane sugar", "corn syrup", "high fructose corn syrup", "dextrose", "maltodextrin", "wheat flour", "rice", "potato", "corn", "oats", "bread", "pasta", "cereal"],
                     caution: ["honey", "maple syrup", "fruit juice", "beans", "lentils"], favor: ["avocado", "olive oil", "eggs", "salmon", "beef", "cheese", "leafy greens"]),
        PersonalDiet(name: "Low-FODMAP",
                     avoid: ["onion", "garlic", "wheat", "inulin", "chicory root", "high fructose corn syrup", "honey", "agave", "apple", "pear", "mango", "sorbitol", "mannitol", "xylitol", "lactose"],
                     caution: ["cashew", "beans", "chickpeas", "lentils", "mushroom"], favor: ["rice", "oats", "carrot", "spinach", "chicken", "eggs"]),
        PersonalDiet(name: "Halal",
                     avoid: ["pork", "bacon", "ham", "lard", "alcohol", "wine", "beer", "rum", "pork gelatin"],
                     caution: ["gelatin", "natural flavors", "vanilla extract", "l-cysteine"]),
        PersonalDiet(name: "Kosher-style",
                     avoid: ["pork", "bacon", "ham", "lard", "shrimp", "crab", "lobster", "clam", "oyster", "scallop", "catfish", "eel"],
                     caution: ["gelatin", "natural flavors", "rennet"]),
        PersonalDiet(name: "Blood-sugar friendly",
                     avoid: ["high fructose corn syrup", "corn syrup", "cane sugar", "dextrose", "maltodextrin", "candy", "soda"],
                     caution: ["honey", "maple syrup", "fruit juice", "white rice", "white bread", "agave"],
                     favor: ["fiber", "protein", "beans", "lentils", "leafy greens", "nuts"]),
        PersonalDiet(name: "Heart healthy (low sodium)",
                     avoid: ["partially hydrogenated", "hydrogenated oil", "shortening"],
                     caution: ["salt", "sodium", "monosodium glutamate", "msg", "bacon", "sausage", "processed cheese"],
                     favor: ["oats", "salmon", "olive oil", "beans", "walnuts", "berries"]),
    ]

    // MARK: Reading a plan you upload

    static let fileTypes: [UTType] = [.pdf, .plainText, .utf8PlainText, .rtf, .text, UTType(filenameExtension: "docx"), UTType(filenameExtension: "md")].compactMap { $0 }

    /// The words in a PDF, Word document or text file.
    static func text(from data: Data, name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        if ext == "pdf", let doc = PDFDocument(data: data) {
            return (0..<min(doc.pageCount, 40)).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
        }
        if ext == "docx", ZipReader.isZip(data),
           let e = ZipReader.entries(data).first(where: { $0.path == "word/document.xml" }),
           let xml = ZipReader.extract(e, from: data), let s = String(data: xml, encoding: .utf8) {
            return s.replacingOccurrences(of: "</w:p>", with: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&apos;", with: "'")
        }
        if ext == "rtf", let a = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            return a.string
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// Turns a written plan into avoid / careful / good lists. Apple Intelligence first; a plain reading if it can't.
    @MainActor
    static func read(_ text: String, name: String) async -> PersonalDiet {
        let trimmed = String(text.prefix(9_000))
        var d = PersonalDiet(name: name.isEmpty ? "My diet" : name, notes: String(text.prefix(4_000)))
        let prompt = """
        Read this diet plan and list the specific foods and ingredients it names. Reply with exactly these four lines and nothing else:
        NAME: <short name for the diet, 2-4 words>
        AVOID: <comma-separated foods or ingredients to avoid>
        CAREFUL: <comma-separated foods to limit or check>
        GOOD: <comma-separated foods it recommends>
        Use short ingredient words as they appear on food labels (e.g. "soy lecithin", "pork", "red 40"). No explanations.
        Plan:
        \(trimmed)
        """
        if let out = await AIRouter.shared.write(prompt) {
            for line in out.split(whereSeparator: \.isNewline) {
                let clean = line.replacingOccurrences(of: "*", with: "")
                guard let sep = clean.firstIndex(of: ":") else { continue }
                let key = clean[..<sep].trimmingCharacters(in: .whitespaces).uppercased()
                let items = terms(String(clean[clean.index(after: sep)...]))
                switch key {
                case "NAME": if name.isEmpty, let n = items.first { d.name = n.capitalized }
                case "AVOID": d.avoid = items
                case "CAREFUL", "CAUTION", "LIMIT": d.caution = items
                case "GOOD", "EAT", "FAVOR": d.favor = items
                default: break
                }
            }
        }
        if d.avoid.isEmpty && d.caution.isEmpty && d.favor.isEmpty { d = plainRead(text, into: d) }
        return d
    }

    /// Without AI: sorts each line by its wording ("avoid", "limit", "eat more"…).
    static func plainRead(_ text: String, into base: PersonalDiet) -> PersonalDiet {
        var d = base
        let avoidWords = ["avoid", "no ", "never", "don't", "do not", "eliminate", "cut out", "skip", "forbidden", "unclean", "not allowed", "red"]
        let cautionWords = ["limit", "moderation", "sometimes", "occasionally", "caution", "careful", "check", "yellow", "small amount"]
        let goodWords = ["eat", "enjoy", "approved", "include", "focus on", "allowed", "yes", "green", "recommended", "best"]
        var mode = 0     // 0 unknown, 1 avoid, 2 caution, 3 good: headings carry over to the lines under them
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.lowercased()
            if avoidWords.contains(where: { line.contains($0) }) { mode = 1 }
            else if cautionWords.contains(where: { line.contains($0) }) { mode = 2 }
            else if goodWords.contains(where: { line.contains($0) }) { mode = 3 }
            var body = line
            for w in avoidWords + cautionWords + goodWords { body = body.replacingOccurrences(of: w, with: " ") }
            let items = terms(body).filter { $0.split(separator: " ").count <= 4 }
            switch mode {
            case 1: d.avoid += items
            case 2: d.caution += items
            case 3: d.favor += items
            default: break
            }
        }
        d.avoid = unique(d.avoid); d.caution = unique(d.caution.filter { !d.avoid.contains($0) }); d.favor = unique(d.favor)
        return d
    }

    static func terms(_ s: String) -> [String] {
        let parts = s.lowercased()
            .replacingOccurrences(of: " and ", with: ",").replacingOccurrences(of: " or ", with: ",")
            .components(separatedBy: CharacterSet(charactersIn: ",;•·|/\t"))
        return unique(parts.map { $0.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—.:()[]\"'0123456789"))) }
            .filter { $0.count >= 3 && $0.count <= 40 && !["none", "n/a", "etc", "foods", "food", "the", "all"].contains($0) })
    }

    private static func unique(_ xs: [String]) -> [String] {
        var seen = Set<String>(); return xs.filter { seen.insert($0).inserted }
    }

    /// Edits a list typed as "a, b, c".
    static func list(_ s: String) -> [String] { terms(s) }
}

// MARK: - Screens

/// Settings → Health & Nutrition → Your diets.
struct MyDietsView: View {
    @State private var diets = PersonalDiets.all
    @AppStorage(PersonalDiets.builtInKey) private var builtIn = true
    @State private var editing: PersonalDiet?
    @State private var importing = false
    @State private var pasting = false
    @State private var reading = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                Toggle(isOn: $builtIn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ADHD brain diet")
                        Text("No soy, dyes, artificial sweeteners or refined sugar; Leviticus 11").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
                .tint(DS.Palette.calm)
            } header: { Text("Built in") } footer: { Text("Switch off to check food only against your own diets.") }

            Section {
                if diets.isEmpty {
                    Text("Add the plan you follow: from your dietitian, doctor, faith or your own rules. Every scan, search and meal is checked against it.")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                ForEach(diets) { d in
                    HStack {
                        Button { editing = d } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.name).foregroundStyle(DS.Palette.ink)
                                Text(d.summary).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Toggle("On", isOn: Binding(get: { d.on }, set: { v in var x = d; x.on = v; PersonalDiets.save(x); diets = PersonalDiets.all }))
                            .labelsHidden().tint(DS.Palette.calm)
                    }
                }
                .onDelete { idx in for i in idx { PersonalDiets.delete(diets[i].id) }; diets = PersonalDiets.all }
            } header: { Text("Your diets") }

            Section {
                Button { importing = true } label: { Label("Upload a diet (PDF, Word or text)", systemImage: "doc.badge.arrow.up") }
                Button { pasting = true } label: { Label("Paste or type a diet", systemImage: "doc.on.clipboard") }
                Menu {
                    ForEach(PersonalDiets.templates, id: \.name) { t in
                        Button(t.name) { var x = t; x.id = UUID(); editing = x }
                    }
                } label: { Label("Start from a template", systemImage: "square.grid.2x2") }
                if reading { HStack { ProgressView(); Text("Reading your plan…").foregroundStyle(DS.Palette.inkSoft) } }
                if let error { Text(error).font(DS.Font.caption).foregroundStyle(.red) }
            } footer: { Text("Keel reads your plan on this device and turns it into simple lists you can check and edit before saving.") }
        }
        .navigationTitle("Your diets")
        .premiumBackground(.green)
        .fileImporter(isPresented: $importing, allowedContentTypes: PersonalDiets.fileTypes) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { error = "Couldn't open that file."; return }
            let text = PersonalDiets.text(from: data, name: url.lastPathComponent)
            guard text.trimmingCharacters(in: .whitespacesAndNewlines).count > 10 else { error = "That file has no readable text. Try a PDF with text, a Word file, or paste it."; return }
            read(text, name: (url.lastPathComponent as NSString).deletingPathExtension)
        }
        .sheet(isPresented: $pasting) { PasteDietSheet { text, name in read(text, name: name) } }
        .sheet(item: $editing, onDismiss: { diets = PersonalDiets.all }) { DietEditor(diet: $0) }
    }

    private func read(_ text: String, name: String) {
        error = nil; reading = true
        Task {
            let d = await PersonalDiets.read(text, name: name)
            reading = false
            if d.avoid.isEmpty && d.caution.isEmpty && d.favor.isEmpty { error = "Couldn't find foods in that plan. Try a template or type the lists yourself." }
            editing = d
        }
    }
}

private struct PasteDietSheet: View {
    var onDone: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var text = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (optional)", text: $name)
                Section {
                    TextField("Paste your plan, or write rules like “No pork, no shellfish, limit sugar, eat more fish”", text: $text, axis: .vertical)
                        .lineLimit(8...20)
                    Button("Paste from clipboard", systemImage: "doc.on.clipboard") { text = UIPasteboard.general.string ?? text }
                }
            }
            .navigationTitle("Your diet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Read it") { onDone(text, name); dismiss() }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).count < 4)
                }
            }
        }
    }
}

struct DietEditor: View {
    @State var diet: PersonalDiet
    @Environment(\.dismiss) private var dismiss
    @State private var avoid = ""
    @State private var caution = ""
    @State private var favor = ""

    init(diet: PersonalDiet) {
        _diet = State(initialValue: diet)
        _avoid = State(initialValue: diet.avoid.joined(separator: ", "))
        _caution = State(initialValue: diet.caution.joined(separator: ", "))
        _favor = State(initialValue: diet.favor.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Name", text: $diet.name) }
                Section { TextField("pork, shellfish, red 40…", text: $avoid, axis: .vertical).lineLimit(2...8) }
                    header: { Label("Avoid", systemImage: "xmark.octagon.fill").foregroundStyle(.red) }
                    footer: { Text("Anything on a label that matches is marked 🔴 Skip it.") }
                Section { TextField("honey, natural flavors…", text: $caution, axis: .vertical).lineLimit(2...8) }
                    header: { Label("Careful", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    footer: { Text("Marked 🟡 Okay sometimes.") }
                Section { TextField("salmon, leafy greens…", text: $favor, axis: .vertical).lineLimit(2...8) }
                    header: { Label("Good", systemImage: "checkmark.seal.fill").foregroundStyle(DS.Palette.calm) }
                    footer: { Text("Shown as a plus when a food has them.") }
                if !diet.notes.isEmpty {
                    Section("From your plan") { Text(diet.notes).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(12) }
                }
            }
            .navigationTitle("Check your diet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        diet.avoid = PersonalDiets.list(avoid); diet.caution = PersonalDiets.list(caution); diet.favor = PersonalDiets.list(favor)
                        if diet.name.trimmingCharacters(in: .whitespaces).isEmpty { diet.name = "My diet" }
                        PersonalDiets.save(diet); Haptics.success(); dismiss()
                    }
                }
            }
        }
    }
}
