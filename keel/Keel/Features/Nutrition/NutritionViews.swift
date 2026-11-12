import SwiftUI
import SwiftData

// MARK: - Pieces

struct VerdictHeader: View {
    let verdict: DietVerdict
    let title: String
    let subtitle: String?
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(verdict.color.gradient).frame(width: 54, height: 54)
                Image(systemName: verdict == .green ? "checkmark" : verdict == .yellow ? "exclamationmark" : verdict == .red ? "xmark" : "questionmark")
                    .font(.title2.weight(.bold)).foregroundStyle(.white)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verdict.label).font(DS.Font.headline).foregroundStyle(verdict.color)
                Text(title).font(DS.Font.title).lineLimit(2)
                if let subtitle, !subtitle.isEmpty { Text(subtitle).font(DS.Font.caption).foregroundStyle(.secondary) }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct FindingRow: View {
    let f: DietFinding
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(f.level.color).frame(width: 10, height: 10).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.rule).font(DS.Font.body.weight(.semibold))
                Text("Found: \(f.matched)").font(DS.Font.caption).foregroundStyle(f.level.color)
                Text(f.why).font(DS.Font.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct FactsGrid: View {
    let facts: NutritionFacts
    private struct Row: Identifiable { let id: String; let value: String }
    private var rows: [Row] {
        func g(_ v: Double?, _ unit: String) -> String? { v.map { String(format: $0 < 10 && $0 != $0.rounded() ? "%.1f" : "%.0f", $0) + unit } }
        let all: [(String, String?)] = [
            ("Calories", g(facts.calories, "")), ("Protein", g(facts.protein, " g")), ("Carbs", g(facts.carbs, " g")),
            ("Fat", g(facts.fat, " g")), ("Fiber", g(facts.fiber, " g")), ("Sugar", g(facts.sugar, " g")),
            ("Added sugar", g(facts.addedSugar, " g")), ("Sodium", g(facts.sodiumMg, " mg")), ("Caffeine", g(facts.caffeineMg, " mg")),
            ("Magnesium", g(facts.magnesiumMg, " mg")), ("Zinc", g(facts.zincMg, " mg")), ("Iron", g(facts.ironMg, " mg")),
        ]
        return all.compactMap { pair in pair.1.map { Row(id: pair.0, value: $0) } }
    }
    var body: some View {
        if rows.isEmpty {
            Text("No nutrition numbers yet. Scan the label to add them.").font(DS.Font.caption).foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                ForEach(rows) { r in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.value).font(DS.Font.headline).monospacedDigit()
                        Text(r.id).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
            Text(facts.servingLabel.capitalized).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Result

/// What a product means for your plan: the verdict and why, better picks from your guide, the numbers, and Log.
struct FoodResultView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Bindable var product: FoodProduct
    @State private var servings = 1.0
    @State private var meal = FoodEntry.mealNow()
    @State private var logged = false
    @State private var showIngredients = false

    private var result: DietResult? { product.result }
    private var swaps: [GuideEntry] {
        guard product.verdict != .green else { return [] }
        return DietGuide.swaps(for: product.name, categories: product.categories)
    }

    var body: some View {
        List {
            Section {
                VerdictHeader(verdict: product.verdict, title: product.displayName,
                              subtitle: [product.brand, product.overrideRaw != nil ? "Your call" : nil].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                if let r = result {
                    HStack {
                        Label("Brain-food score", systemImage: "brain.head.profile")
                        Spacer()
                        Text("\(r.score)").font(DS.Font.headline).monospacedDigit().foregroundStyle(product.verdict.color)
                    }
                }
            }

            if let r = result, !r.findings.isEmpty {
                Section("Why") { ForEach(r.findings) { FindingRow(f: $0) } }
            }
            if let r = result, !r.positives.isEmpty {
                Section("The good stuff") {
                    ForEach(r.positives, id: \.self) { Label($0, systemImage: "leaf.fill").foregroundStyle(DS.Palette.calm) }
                }
            }
            if let note = result?.guideNote {
                Section("Your guide") { Text(note).font(DS.Font.caption) }
            }
            if !swaps.isEmpty {
                Section {
                    ForEach(swaps) { SwapRow(entry: $0) }
                } header: { Text("Grab this instead") } footer: { Text("From your diet guide, same kind of food.") }
            }

            Section("Nutrition") { FactsGrid(facts: product.facts) }

            Section {
                Stepper(value: $servings, in: 0.25...10, step: 0.25) {
                    Text("\(servings.formatted(.number.precision(.fractionLength(0...2)))) serving\(servings == 1 ? "" : "s")")
                }
                Picker("Meal", selection: $meal) {
                    ForEach(["breakfast", "lunch", "dinner", "snack"], id: \.self) { Text($0.capitalized) }
                }
                Button {
                    NutritionLog.log(product, servings: servings, meal: meal, ctx: ctx)
                    withAnimation(DS.spring) { logged = true }
                } label: {
                    Label(logged ? "Logged" : "Log it", systemImage: logged ? "checkmark.circle.fill" : "plus.circle.fill")
                }
                .disabled(logged)
            } footer: {
                Text(NutritionHealth.isOn ? "Also saved to Apple Health." : "Turn on Apple Health in Health & Nutrition settings to share meals.")
            }

            Section {
                if !product.ingredients.isEmpty {
                    DisclosureGroup("Ingredients", isExpanded: $showIngredients) {
                        Text(product.ingredients).font(DS.Font.caption).textSelection(.enabled)
                    }
                } else {
                    Label("No ingredients list yet. Scan the label to check it properly.", systemImage: "text.viewfinder").font(DS.Font.caption)
                }
                Menu {
                    Button("It's fine for me (Green)") { setOverride(.green) }
                    Button("Sometimes (Yellow)") { setOverride(.yellow) }
                    Button("Not for me (Red)") { setOverride(.red) }
                    if product.overrideRaw != nil { Button("Use Keel's check", role: .destructive) { setOverride(nil) } }
                } label: { Label("I checked it myself…", systemImage: "hand.raised") }
                Toggle(isOn: $product.isFavorite) { Label("Favorite", systemImage: "star") }
            } footer: {
                Text("Product data: \(product.source). Scanned \(product.scanCount)×. Keel checks ingredients against your guide; when a label is unclear, trust the label.")
            }
        }
        .navigationTitle("Check")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func setOverride(_ v: DietVerdict?) {
        product.overrideRaw = v?.rawValue
        try? ctx.save()
        Haptics.tap()
    }
}

struct SwapRow: View {
    let entry: GuideEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(entry.name).font(DS.Font.body.weight(.semibold))
                if entry.status == "best" { Text("BEST").font(.caption2.weight(.bold)).padding(.horizontal, 5).padding(.vertical, 1).background(DS.Palette.calm.opacity(0.2), in: Capsule()) }
            }
            Text(entry.details).font(DS.Font.caption).foregroundStyle(.secondary).lineLimit(3)
        }
    }
}

// MARK: - Nutrition home

/// Today's food at a glance: what you ate, how it fits your plan, and the brain foods still to get.
struct NutritionView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var entries: [FoodEntry]           // the last 7 days only
    @State private var healthTotals: NutritionFacts?

    init() {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        _entries = Query(filter: #Predicate<FoodEntry> { $0.date >= start }, sort: \FoodEntry.date, order: .reverse)
    }
    @State private var weight: Double?

    private var today: [FoodEntry] { entries.filter { Calendar.current.isDateInToday($0.date) } }
    private var week: [FoodEntry] {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return entries.filter { $0.date >= start }
    }
    private var totals: NutritionFacts { today.reduce(NutritionFacts()) { $0 + $1.facts } }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    NavigationLink { FoodScanView() } label: { BigAction(title: "Scan", icon: "barcode.viewfinder", color: DS.Palette.accent) }
                    NavigationLink { DescribeMealView() } label: { BigAction(title: "Describe", icon: "text.bubble.fill", color: .orange) }
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
            }

            Section {
                let shown = healthTotals ?? totals
                let proteinGoal = NutritionGoals.protein(weightKg: weight)
                GoalBar(title: "Protein", value: shown.protein ?? 0, goal: proteinGoal, unit: "g", color: DS.Palette.focus)
                GoalBar(title: "Fiber", value: shown.fiber ?? 0, goal: NutritionGoals.fiber, unit: "g", color: DS.Palette.calm)
                GoalBar(title: "Added sugar", value: totals.addedSugar ?? 0, goal: NutritionGoals.addedSugarCap, unit: "g", color: .orange, isCeiling: true)
                HStack {
                    Text("Calories").foregroundStyle(.secondary)
                    Spacer()
                    Text((shown.calories ?? 0).formatted(.number.precision(.fractionLength(0)))).monospacedDigit()
                }
                .font(DS.Font.caption)
            } header: { Text("Today") } footer: {
                Text(healthTotals != nil ? "Totals include food other apps saved to Apple Health." : "From what you've logged in Keel.")
            }

            Section("Brain foods") {
                ForEach(BrainFoods.items) { item in
                    let n = (item.perWeek != nil ? week : today).filter { $0.tags.contains(item.id) }.count
                    let done = n >= (item.perWeek ?? 1)
                    HStack {
                        Image(systemName: done ? "checkmark.circle.fill" : item.icon).foregroundStyle(done ? DS.Palette.calm : .secondary).frame(width: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(DS.Font.body)
                            Text(item.goal).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let w = item.perWeek { Text("\(n)/\(w) this week").font(DS.Font.caption).foregroundStyle(.secondary) }
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Section {
                if today.isEmpty {
                    Text("Nothing logged yet today.").foregroundStyle(.secondary)
                } else {
                    let tally = Dictionary(grouping: today, by: \.verdict).mapValues(\.count)
                    HStack(spacing: 16) {
                        ForEach([DietVerdict.green, .yellow, .red], id: \.self) { v in
                            Label("\(tally[v] ?? 0)", systemImage: "circle.fill").foregroundStyle(v.color).font(DS.Font.caption)
                        }
                    }
                    ForEach(today) { e in EntryRow(e: e) }
                        .onDelete { idx in idx.map { today[$0] }.forEach { NutritionLog.delete($0, ctx: ctx) } }
                }
            } header: { Text("Eaten today") }

            Section {
                NavigationLink { FoodLibraryView() } label: { Label("Your food library", systemImage: "books.vertical.fill") }
                NavigationLink { DietGuideView() } label: { Label("Your diet guide", systemImage: "book.closed.fill") }
                NavigationLink { NutritionSettingsView() } label: { Label("Goals & Apple Health", systemImage: "heart.text.square.fill") }
            }
        }
        .navigationTitle("Food")
        .task {
            weight = await NutritionHealth.weightKg()
            healthTotals = await NutritionHealth.todayTotals()
        }
    }
}

private struct BigAction: View {
    let title: String
    let icon: String
    let color: Color
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 28, weight: .semibold))
            Text(title).font(DS.Font.headline)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity).frame(height: 96)
        .background(color.gradient, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

private struct GoalBar: View {
    let title: String
    let value: Double
    let goal: Double
    let unit: String
    let color: Color
    var isCeiling = false
    var body: some View {
        let over = isCeiling && value > goal
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(DS.Font.body)
                Spacer()
                Text("\(Int(value)) / \(Int(goal)) \(unit)\(isCeiling ? " max" : "")").font(DS.Font.caption).monospacedDigit()
                    .foregroundStyle(over ? .red : .secondary)
            }
            ProgressView(value: min(value, goal), total: max(goal, 1)).tint(over ? .red : color)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct EntryRow: View {
    let e: FoodEntry
    var body: some View {
        HStack {
            Circle().fill(e.verdict.color).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.name).lineLimit(1)
                Text([e.meal.capitalized, e.date.formatted(date: .omitted, time: .shortened),
                      e.facts.protein.map { "\(Int($0)) g protein" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if let c = e.facts.calories { Text("\(Int(c))").font(DS.Font.caption).monospacedDigit().foregroundStyle(.secondary) }
            if e.savedToHealth { Image(systemName: "heart.fill").font(.caption2).foregroundStyle(.pink).accessibilityLabel("In Apple Health") }
        }
    }
}

// MARK: - Library & guide

/// Every product you've scanned. Grows with each scan, works offline, and remembers your own calls.
struct FoodLibraryView: View {
    @Query(sort: \FoodProduct.lastScanned, order: .reverse) private var products: [FoodProduct]
    @Environment(\.modelContext) private var ctx
    @State private var search = ""
    @State private var filter: DietVerdict?

    private var shown: [FoodProduct] {
        products.filter { p in
            (filter == nil || p.verdict == filter) &&
            (search.isEmpty || p.name.localizedCaseInsensitiveContains(search) || p.brand.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $filter) {
                    Text("All").tag(DietVerdict?.none)
                    Text("🟢").tag(DietVerdict?.some(.green))
                    Text("🟡").tag(DietVerdict?.some(.yellow))
                    Text("🔴").tag(DietVerdict?.some(.red))
                }
                .pickerStyle(.segmented)
            } footer: { Text("\(products.count) products. Checked here first on every scan, even offline.") }
            ForEach(shown) { p in
                NavigationLink { FoodResultView(product: p) } label: {
                    HStack {
                        Text(p.verdict.emoji)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.displayName).lineLimit(1)
                            Text([p.brand, "\(p.scanCount)×"].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if p.isFavorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
                    }
                }
            }
            .onDelete { idx in idx.map { shown[$0] }.forEach(ctx.delete) }
        }
        .searchable(text: $search, prompt: "Search your library")
        .overlay { if products.isEmpty { ContentUnavailableView("No products yet", systemImage: "barcode", description: Text("Everything you scan is saved here.")) } }
        .navigationTitle("Food library")
    }
}

/// Your diet guide, searchable, by section.
struct DietGuideView: View {
    @State private var search = ""
    private struct Sec: Identifiable { let id: Int; let title: String; let items: [GuideEntry] }
    private var sections: [Sec] {
        let list = DietGuide.entries.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.details.localizedCaseInsensitiveContains(search) }
        let grouped = Dictionary(grouping: list, by: \.s)
        return grouped.keys.sorted().map { k in Sec(id: k, title: grouped[k]?.first?.section ?? "", items: grouped[k] ?? []) }
    }
    var body: some View {
        List {
            ForEach(sections) { sec in
                Section(sec.title) {
                    ForEach(sec.items) { e in
                        HStack(alignment: .top) {
                            Text(e.verdict.emoji)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.name).font(DS.Font.body)
                                Text(e.details).font(DS.Font.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Search foods and brands")
        .navigationTitle("Diet guide")
    }
}

struct NutritionSettingsView: View {
    @AppStorage(NutritionHealth.syncKey) private var sync = false
    @AppStorage(NutritionGoals.proteinKey) private var protein = 0.0
    @AppStorage(NutritionGoals.fiberKey) private var fiber = 0.0
    @AppStorage(NutritionGoals.sugarKey) private var sugar = 0.0

    var body: some View {
        Form {
            Section {
                Toggle("Share with Apple Health", isOn: Binding(get: { sync }, set: { on in
                    if on { Task { sync = await NutritionHealth.connect() } } else { sync = false }
                }))
            } footer: {
                Text("Meals you log are saved to Health with calories, protein, carbs, fat, fiber, sugar, sodium and caffeine. Keel also reads food other apps saved, and your weight for a protein goal. Deleting a meal in Keel removes it from Health.")
            }
            Section {
                Stepper("Protein: \(protein > 0 ? "\(Int(protein)) g" : "automatic")", value: $protein, in: 0...300, step: 5)
                Stepper("Fiber: \(Int(NutritionGoals.fiber)) g", value: Binding(get: { NutritionGoals.fiber }, set: { fiber = $0 }), in: 10...60, step: 5)
                Stepper("Added sugar max: \(Int(NutritionGoals.addedSugarCap)) g", value: Binding(get: { NutritionGoals.addedSugarCap }, set: { sugar = $0 }), in: 0...50, step: 5)
            } header: { Text("Daily goals") } footer: {
                Text("Automatic protein is about 1.6 g per kg of your weight from Health, or 120 g without it.")
            }
            Section {
                Text("🟢 Fits your plan. 🟡 Fine sometimes, or check the label (natural flavors, honey, erythritol, gelatin, seed oils, high caffeine). 🔴 Skip: soy in any form, artificial dyes, artificial sweeteners, sorbitol or maltitol, pork or shellfish [Lev 11], refined sugar in the first five ingredients, or more than 10 g added sugar.")
                    .font(DS.Font.caption)
            } header: { Text("How Keel decides") }
        }
        .navigationTitle("Health & Nutrition")
    }
}
