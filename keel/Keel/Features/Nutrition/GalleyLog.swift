import SwiftUI
import SwiftData
import Speech
import AVFoundation

// MARK: - Galley: logging
//
// One bar at the bottom of Food: type it, say it, snap it or scan it. Whatever you give it becomes a confirm card: every
// item, how sure Keel is, portions you tap to change, the oil Keel can't see, "add what it missed", plain-words fixes
// ("only half", "no cheese"), and what it does to today's score before you save. The meal is picked from the time; one
// tap on the card changes it. No menus.

// MARK: Score, with its reasons

/// The day's Nutrition Score as separate contributions, so "why 78" can show each one with its points.
/// Same rules as NutritionScore (protein, fiber, sugar, sodium, plan fit, brain foods), plus late eating.
enum GalleyScore {
    struct Bite { let facts: NutritionFacts; let verdict: DietVerdict; let brain: Bool; let date: Date }
    struct Part: Identifiable { let id = UUID(); let label: String; let points: Int; let detail: String }
    struct Result { let score: Int; let parts: [Part]; let early: Bool }

    static func bites(_ entries: [FoodEntry]) -> [Bite] {
        entries.map { Bite(facts: $0.facts, verdict: $0.verdict, brain: !$0.tags.isEmpty, date: $0.date) }
    }

    static func score(_ bites: [Bite], proteinGoal: Double) -> Result? {
        guard !bites.isEmpty else { return nil }
        let protein = bites.reduce(0) { $0 + ($1.facts.protein ?? 0) }
        let fiber = bites.reduce(0) { $0 + ($1.facts.fiber ?? 0) }
        let sugar = bites.reduce(0) { $0 + ($1.facts.addedSugar ?? ($1.facts.sugar ?? 0) * 0.5) }
        let sodium = bites.reduce(0) { $0 + ($1.facts.sodiumMg ?? 0) }
        let kcal = bites.reduce(0) { $0 + ($1.facts.calories ?? 0) }
        let n = Double(bites.count)
        let green = Double(bites.filter { $0.verdict == .green }.count) / n
        let red = Double(bites.filter { $0.verdict == .red }.count) / n
        var parts: [Part] = []
        let p = Int(min(15, protein / max(1, proteinGoal) * 15).rounded())
        parts.append(Part(label: "Protein", points: p, detail: "\(Int(protein)) of \(Int(proteinGoal)) g"))
        let f = Int(min(15, fiber / max(1, NutritionGoals.fiber) * 15).rounded())
        parts.append(Part(label: "Fiber", points: f, detail: "\(Int(fiber)) of \(Int(NutritionGoals.fiber)) g"))
        let cap = NutritionGoals.addedSugarCap
        if sugar <= cap { parts.append(Part(label: "Added sugar", points: 10, detail: "\(Int(sugar)) g, under your \(Int(cap)) g cap")) }
        else { parts.append(Part(label: "Added sugar", points: -Int(min(15, (sugar - cap) / 2).rounded()), detail: "\(Int(sugar)) g, over your \(Int(cap)) g cap")) }
        if sodium > 0 {
            parts.append(sodium <= 2300 ? Part(label: "Sodium", points: 5, detail: "\(Int(sodium)) mg, in range")
                                        : Part(label: "Sodium", points: -5, detail: "\(Int(sodium)) mg, over 2,300"))
        }
        let fit = Int((green * 15 - red * 20).rounded())
        if fit != 0 { parts.append(Part(label: "Fits your plan", points: fit, detail: "\(bites.filter { $0.verdict == .green }.count) good, \(bites.filter { $0.verdict == .red }.count) off-plan")) }
        if bites.contains(where: \.brain) { parts.append(Part(label: "Brain foods", points: 5, detail: "oily fish, nuts, seeds or greens")) }
        if let late = bites.map(\.date).max(), Calendar.current.component(.hour, from: late) >= 21 {
            parts.append(Part(label: "Late meal", points: -3, detail: "eating late tends to lower your Anchor"))
        }
        let s = 45 + parts.reduce(0) { $0 + $1.points }
        return Result(score: min(100, max(0, s)), parts: parts, early: kcal < NutritionGoals.calories / 3)
    }
}

// MARK: Speech in the log bar

@MainActor @Observable
final class FoodDictation {
    var text = ""
    var listening = false
    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() async {
        let ok = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        guard ok, await AVAudioApplication.requestRecordPermission(), let recognizer, recognizer.isAvailable else { return }
        stop()
        text = ""
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request = req
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buf, _ in req.append(buf) }
        engine.prepare()
        guard (try? engine.start()) != nil else { return }
        listening = true
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            let said = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            Task { @MainActor in
                guard let self else { return }
                if let said { self.text = said }
                if final || error != nil { self.stop() }
            }
        }
    }

    func stop() {
        guard listening || task != nil else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil; request = nil
        listening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: The log bar

struct GalleyLogBar: View {
    @State private var text = ""
    @State private var dictation = FoodDictation()
    @State private var confirming: ConfirmSource?
    @State private var scanning = false
    @State private var snapping = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: $text, prompt: Text(dictation.listening ? "Listening…" : "Describe, snap or scan a meal…").foregroundStyle(Color.white.opacity(0.6)), axis: .vertical)
                .lineLimit(1...3)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(send)
                .foregroundStyle(.white)
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                circle("arrow.up", label: "Log it", action: send).tint(Nautical.chartRed)
            } else {
                circle("camera.fill", label: "Snap a meal") { snapping = true }
                circle("barcode.viewfinder", label: "Scan a barcode") { scanning = true }
                circle(dictation.listening ? "stop.fill" : "mic.fill", label: dictation.listening ? "Stop" : "Say it") {
                    if dictation.listening { dictation.stop(); text = dictation.text; if !text.isEmpty { send() } }
                    else { Task { await dictation.start() } }
                }
            }
        }
        .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
        .background(DS.Palette.ink.opacity(0.96), in: .rect(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
        .onChange(of: dictation.text) { _, t in if dictation.listening { text = t } }
        .fullScreenCover(isPresented: $scanning) { BarcodeReaderView() }
        .sheet(isPresented: $snapping) {
            NavigationStack {
                MealScanView { items in
                    let found = items.map { DetectedFood(food: $0.food, servings: $0.servings, confidence: 0.7) }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))     // the photo sheet closes first, then the confirm card opens
                        confirming = .photo(found)
                    }
                }
            }
        }
        .sheet(item: $confirming) { src in
            MealConfirmSheet(source: src)
                .presentationDetents([.large])
        }
    }

    private func circle(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 36, height: 36).background(Color.white.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        focused = false
        text = ""
        confirming = .text(t)
    }
}

enum ConfirmSource: Identifiable {
    case text(String)
    case photo([DetectedFood])
    var id: String {
        switch self { case .text(let t): "t:" + t; case .photo(let d): "p:" + d.map(\.id.uuidString).joined() }
    }
}

// MARK: The confirm card

struct MealConfirmSheet: View {
    let source: ConfirmSource
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var today: [FoodEntry]

    struct Row: Identifiable {
        let id = UUID()
        var name: String
        var portion: String
        var base: NutritionFacts       // for the portion as first estimated
        var factor: Double = 1
        var confidence: Int
        var include = true
        var facts: NutritionFacts { base.scaled(factor) }
    }

    @State private var rows: [Row] = []
    @State private var title = ""
    @State private var cuisine = ""
    @State private var meal = FoodEntry.mealNow()
    @State private var oil = 0                    // 0 none · 1 tsp · 2 tbsp · 3 lots
    @State private var working = true
    @State private var missed = ""
    @State private var change = ""
    @State private var breakdown: FoodAI.Breakdown?
    @State private var failed = false

    init(source: ConfirmSource) {
        self.source = source
        let start = Calendar.current.startOfDay(for: Date())
        _today = Query(filter: #Predicate<FoodEntry> { $0.date >= start })
    }

    private static let oils: [(String, Double, Double)] = [("None", 0, 0), ("1 tsp", 40, 4.5), ("1 tbsp", 120, 14), ("Lots", 240, 27)]

    private var oilFacts: NutritionFacts {
        var f = NutritionFacts()
        f.calories = Self.oils[oil].1; f.fat = Self.oils[oil].2; f.protein = 0; f.carbs = 0
        f.servingLabel = Self.oils[oil].0
        return f
    }

    private var total: NutritionFacts {
        rows.filter(\.include).reduce(oil > 0 ? oilFacts : NutritionFacts()) { $0 + $1.facts }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(header).font(DS.Font.mono).foregroundStyle(DS.Palette.inkSoft)
                    MealChips(meal: $meal)
                    if working {
                        HStack(spacing: 10) { ProgressView(); Text("Working out what's on the plate…").foregroundStyle(DS.Palette.inkSoft) }
                            .padding(.vertical, 30).frame(maxWidth: .infinity)
                    } else {
                        Text(title.isEmpty ? "Your meal" : title).font(.system(.title2, design: .serif).weight(.semibold))
                        if failed {
                            Text("Couldn't break that down on this iPhone. Add the foods one at a time below, or use Quick add.").font(.subheadline).foregroundStyle(DS.Palette.inkSoft)
                        }
                        ForEach($rows) { $r in rowView($r) }
                        oilCard
                        addMissed
                        if breakdown != nil { changeInWords }
                        totals
                    }
                }
                .padding(18)
            }
            .background(DS.Palette.canvas)
            .navigationTitle("Log a meal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Log it") { log() }.disabled(working || !rows.contains(where: \.include)) }
            }
        }
        .task { await start() }
    }

    private var header: String {
        let how: String
        switch source { case .text: how = "FROM WHAT YOU SAID"; case .photo: how = "FROM YOUR PHOTO" }
        return [how, cuisine.isEmpty ? nil : cuisine.uppercased(), Date().formatted(date: .omitted, time: .shortened)].compactMap { $0 }.joined(separator: " · ")
    }

    private func rowView(_ r: Binding<Row>) -> some View {
        let v = r.wrappedValue
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Button { r.wrappedValue.include.toggle(); Haptics.tap() } label: {
                    Image(systemName: v.include ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(v.include ? DS.Palette.ink : DS.Palette.inkSoft)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(v.include ? "Leave out \(v.name)" : "Include \(v.name)")
                VStack(alignment: .leading, spacing: 2) {
                    Text(v.name).font(.body.weight(.medium))
                    Text("\(portionLabel(v)) · \(Int(v.facts.calories ?? 0)) kcal · \(Int(v.facts.protein ?? 0)) P".uppercased())
                        .font(DS.Font.mono).foregroundStyle(DS.Palette.inkSoft)
                }
                Spacer()
                Text(v.confidence >= 75 ? "sure" : "check").font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background((v.confidence >= 75 ? DS.Palette.calm : DS.Palette.warmth).opacity(0.15), in: .rect(cornerRadius: 6))
                    .foregroundStyle(v.confidence >= 75 ? DS.Palette.calm : DS.Palette.warmth)
                    .accessibilityLabel(v.confidence >= 75 ? "Keel is sure" : "Worth checking")
            }
            HStack(spacing: 6) {
                ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { x in
                    Button { r.wrappedValue.factor = x; Haptics.tap() } label: {
                        Text(x == 0.5 ? "½" : x == 1.5 ? "1½" : x == 2 ? "2×" : "As said").font(.caption)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(v.factor == x ? DS.Palette.ink : DS.Palette.elevated, in: Capsule())
                            .foregroundStyle(v.factor == x ? DS.Palette.canvas : DS.Palette.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 34)
        }
        .padding(.vertical, 8)
        .opacity(v.include ? 1 : 0.45)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.Palette.ink.opacity(0.12)).frame(height: 0.6) }
    }

    private func portionLabel(_ r: Row) -> String {
        r.factor == 1 ? r.portion : "\(r.factor == 0.5 ? "½" : r.factor == 1.5 ? "1½" : "2") × \(r.portion)"
    }

    private var oilCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Cooked with oil or butter? Photos can't see it.", systemImage: "drop.fill").font(.subheadline.weight(.medium))
            HStack(spacing: 6) {
                ForEach(0..<Self.oils.count, id: \.self) { i in
                    Button { oil = i; Haptics.tap() } label: {
                        Text(Self.oils[i].0).font(.caption)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(oil == i ? DS.Palette.ink : DS.Palette.elevated, in: Capsule())
                            .foregroundStyle(oil == i ? DS.Palette.canvas : DS.Palette.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(DS.Palette.elevated.opacity(0.6), in: .rect(cornerRadius: 12))
    }

    private var addMissed: some View {
        HStack {
            Image(systemName: "plus.circle").foregroundStyle(DS.Palette.inkSoft)
            TextField("Add something it missed, e.g. ranch", text: $missed).onSubmit { Task { await add(missed) } }
        }
        .font(.subheadline)
    }

    private var changeInWords: some View {
        HStack {
            Image(systemName: "text.bubble").foregroundStyle(DS.Palette.inkSoft)
            TextField("Change it in words: “only half”, “no cheese”", text: $change).onSubmit { Task { await revise() } }
        }
        .font(.subheadline)
    }

    private var totals: some View {
        let t = total
        let before = GalleyScore.score(GalleyScore.bites(today), proteinGoal: NutritionGoals.protein(weightKg: nil))?.score
        let added = rows.filter(\.include).map { r in
            GalleyScore.Bite(facts: r.facts, verdict: DietChecker.check(name: r.name, ingredientsText: r.name, facts: r.facts).verdict,
                             brain: !BrainFoods.tags(for: r.name).isEmpty, date: Date())
        }
        let after = GalleyScore.score(GalleyScore.bites(today) + added, proteinGoal: NutritionGoals.protein(weightKg: nil))?.score
        let delta = (after ?? 0) - (before ?? 0)
        return VStack(alignment: .leading, spacing: 4) {
            Text("TOTAL \(Int(t.calories ?? 0)) KCAL · \(Int(t.protein ?? 0)) P · \(Int(t.carbs ?? 0)) C · \(Int(t.fat ?? 0)) F")
                .font(DS.Font.mono).foregroundStyle(DS.Palette.ink)
            if let after {
                Text(before == nil ? "STARTS TODAY'S SCORE AT \(after)" : "\(delta >= 0 ? "+" : "")\(delta) SCORE → \(after)")
                    .font(DS.Font.mono).foregroundStyle(delta >= 0 ? DS.Palette.calm : Nautical.chartRed)
            }
        }
        .padding(.top, 6)
    }

    // MARK: Work

    private func start() async {
        defer { working = false }
        switch source {
        case .photo(let found):
            title = found.count == 1 ? found[0].food.name : found.prefix(3).map(\.food.name).joined(separator: ", ")
            rows = found.map { Row(name: $0.food.name, portion: $0.food.serving, base: $0.food.facts.scaled($0.servings), confidence: Int($0.confidence * 100)) }
        case .text(let t):
            if let b = await FoodAI.breakdown(t, ctx: ctx), !b.items.isEmpty {
                apply(b)
            } else if let e = await MealEstimator.estimate(t) {
                title = e.name
                rows = [Row(name: e.name, portion: "1 serving", base: e.facts, confidence: 60)]
            } else if let f = FoodCatalog.search(t, in: FoodCatalog.all, limit: 1).first {
                title = f.name
                rows = [Row(name: f.name, portion: f.serving, base: f.facts, confidence: 70)]
            } else {
                title = t
                failed = true
            }
        }
    }

    private func apply(_ b: FoodAI.Breakdown) {
        breakdown = b
        title = b.title
        cuisine = b.cuisine
        // The model counts the oil it assumed as an item; show it as the oil choice instead, so it's one tap to change.
        let fats = b.items.filter(\.isAddedFat)
        let food = b.items.filter { !$0.isAddedFat }
        let fatKcal = fats.reduce(0) { $0 + $1.calories }
        oil = fatKcal == 0 ? 0 : fatKcal < 80 ? 1 : fatKcal < 180 ? 2 : 3
        rows = food.map { Row(name: $0.name, portion: $0.portion, base: FoodAI.facts($0), confidence: $0.confidence) }
    }

    private func add(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        missed = ""
        if let b = await FoodAI.breakdown(t, ctx: ctx) {
            rows += b.items.map { Row(name: $0.name, portion: $0.portion, base: FoodAI.facts($0), confidence: $0.confidence) }
        } else if let f = FoodCatalog.search(t, in: FoodCatalog.all, limit: 1).first {
            rows.append(Row(name: f.name, portion: f.serving, base: f.facts, confidence: 80))
        } else if let e = await MealEstimator.estimate(t) {
            rows.append(Row(name: e.name, portion: "1 serving", base: e.facts, confidence: 60))
        }
        failed = rows.isEmpty
        Haptics.tap()
    }

    private func revise() async {
        let t = change.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let b = breakdown else { return }
        change = ""
        working = true
        if let nb = await FoodAI.revise(b, instruction: t) { withAnimation(DS.spring) { apply(nb) } }
        working = false
    }

    private func log() {
        var items = rows.filter(\.include)
        if oil > 0 { items.append(Row(name: "Cooking oil or butter", portion: Self.oils[oil].0, base: oilFacts, confidence: 100)) }
        let made: [FoodEntry] = items.map { r in
            var f = r.facts
            f.servingLabel = portionLabel(r)
            let verdict = DietChecker.check(name: r.name, ingredientsText: r.name, facts: f).verdict
            return NutritionLog.logMeal(name: r.name, ingredients: r.name, facts: f, verdict: verdict, meal: meal, ctx: ctx)
        }
        try? ctx.save()
        Haptics.success()
        UndoCenter.shared.offer("Logged \(title.isEmpty ? "your meal" : title)") { [ctx] in made.forEach { NutritionLog.delete($0, ctx: ctx) }; try? ctx.save() }
        dismiss()
    }
}

// MARK: Quick add

/// Just numbers: calories and macros, no food needed.
struct QuickAddSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var meal = FoodEntry.mealNow()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (optional)", text: $name)
                    number("Calories", $kcal, "kcal")
                    number("Protein", $protein, "g")
                    number("Carbs", $carbs, "g")
                    number("Fat", $fat, "g")
                } footer: { Text("For a restaurant receipt, a coach's plan or anything you already know the numbers for.") }
                Section { MealChips(meal: $meal) }
            }
            .navigationTitle("Quick add").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Log") { log() }.disabled(Double(kcal) == nil && Double(protein) == nil) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func number(_ label: String, _ v: Binding<String>, _ unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: v).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
            Text(unit).foregroundStyle(DS.Palette.inkSoft)
        }
    }

    private func log() {
        var f = NutritionFacts()
        f.calories = Double(kcal); f.protein = Double(protein); f.carbs = Double(carbs); f.fat = Double(fat)
        f.servingLabel = "quick add"
        let n = name.trimmingCharacters(in: .whitespaces)
        _ = NutritionLog.logMeal(name: n.isEmpty ? "Quick add" : n, ingredients: "", facts: f, verdict: .unknown, meal: meal, ctx: ctx)
        try? ctx.save()
        Haptics.success()
        dismiss()
    }
}
