import SwiftUI
import SwiftData
import HealthKit

// MARK: - Galley: the Food home
//
// Score first: the day's Nutrition Score with its pluses and minuses (shown from the first meal, marked "early"), fuel
// gauges for protein, carbs, fat and fiber against your targets, one-tap repeats, and the day's meals as a timeline you
// can act on. Tap the score for "why": every contribution with its points, pinned micronutrients, one next move,
// glucose from Apple Health if you wear a monitor, and how meal timing shows up in your sleep (Anchor).

struct GalleyHeader: View {
    let eaten: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased()) · \(Int(eaten).formatted()) OF \(Int(NutritionGoals.calories).formatted()) KCAL")
                .font(DS.Font.mono).tracking(0.8).foregroundStyle(DS.Palette.inkSoft)
            Text("Galley").font(.system(.largeTitle, design: .serif, weight: .semibold)).foregroundStyle(DS.Palette.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

struct GalleyScoreCard: View {
    let entries: [FoodEntry]
    let proteinGoal: Double

    var body: some View {
        let r = GalleyScore.score(GalleyScore.bites(entries), proteinGoal: proteinGoal)
        NavigationLink { LazyView(WhyScoreView(proteinGoal: proteinGoal)) } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(DS.Palette.ink.opacity(0.1), lineWidth: 7)
                    Circle().trim(from: 0, to: CGFloat(r?.score ?? 0) / 100)
                        .stroke(color(r?.score), style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text(r.map { "\($0.score)" } ?? "–").font(.system(size: 24, design: .serif)).foregroundStyle(DS.Palette.ink)
                }
                .frame(width: 70, height: 70)
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.map { "Nutrition score · \(word($0.score))" } ?? "Nutrition score")
                        .font(.system(.headline, design: .serif)).foregroundStyle(DS.Palette.ink)
                    if let r {
                        let best = r.parts.filter { $0.points > 0 }.sorted { $0.points > $1.points }.prefix(2)
                        let worst = r.parts.filter { $0.points < 0 }.sorted { $0.points < $1.points }.prefix(1)
                        ForEach(Array(best)) { p in Text("+ \(p.label) · \(p.detail)").font(.caption).foregroundStyle(DS.Palette.calm).lineLimit(1) }
                        ForEach(Array(worst)) { p in Text("− \(p.label) · \(p.detail)").font(.caption).foregroundStyle(Nautical.chartRed).lineLimit(1) }
                        if r.early { Text("EARLY · \(entries.count) LOGGED · TAP FOR WHY").font(DS.Font.mono).foregroundStyle(DS.Palette.inkSoft) }
                        else { Text("TAP FOR WHY").font(DS.Font.mono).foregroundStyle(DS.Palette.inkSoft) }
                    } else {
                        Text("Log your first meal and your score starts.").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(DS.Palette.elevated, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DS.Palette.ink.opacity(0.2), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    private func word(_ s: Int) -> String { s >= 80 ? "great" : s >= 65 ? "good" : s >= 45 ? "fair" : "rough" }
    private func color(_ s: Int?) -> Color { guard let s else { return DS.Palette.inkSoft }; return s >= 65 ? DS.Palette.calm : s >= 45 ? DS.Palette.warmth : Nautical.chartRed }
}

/// Protein, carbs, fat and fiber as slim gauges against your targets.
struct FuelGauges: View {
    let eaten: NutritionFacts
    let proteinGoal: Double
    var body: some View {
        let kcal = NutritionGoals.calories
        let carbGoal = (kcal * 0.45 / 4).rounded(), fatGoal = (kcal * 0.3 / 9).rounded()
        VStack(alignment: .leading, spacing: 6) {
            ThemedSectionHeader(title: "Fuel")
            Grid(horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    gauge("Protein", eaten.protein ?? 0, proteinGoal, BodyStyle.tide)
                    gauge("Carbs", eaten.carbs ?? 0, carbGoal, DS.Palette.warmth)
                }
                GridRow {
                    gauge("Fat", eaten.fat ?? 0, fatGoal, .purple)
                    gauge("Fiber", eaten.fiber ?? 0, NutritionGoals.fiber, DS.Palette.calm)
                }
            }
        }
    }

    private func gauge(_ name: String, _ v: Double, _ goal: Double, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.subheadline)
                Spacer()
                Text("\(Int(v))/\(Int(goal)) g").font(DS.Font.mono).foregroundStyle(DS.Palette.inkSoft)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Palette.ink.opacity(0.08))
                    Capsule().fill(c).frame(width: g.size.width * CGFloat(min(1, v / max(1, goal))))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(Int(v)) of \(Int(goal)) grams")
    }
}

/// One-tap repeats right above the timeline.
struct GalleyChips: View {
    @Environment(\.modelContext) private var ctx
    var onQuickAdd: () -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Same as yesterday", "arrow.counterclockwise", action: sameAsYesterday)
                chip("Quick add", "bolt.fill", action: onQuickAdd)
                NavigationLink { LazyView(FoodHistoryView()) } label: { chipLabel("History", "calendar") }.buttonStyle(.plain)
                NavigationLink { LazyView(LogFoodView()) } label: { chipLabel("Search foods", "magnifyingglass") }.buttonStyle(.plain)
            }
        }
    }

    private func chip(_ t: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(t, icon) }.buttonStyle(.plain)
    }
    private func chipLabel(_ t: String, _ icon: String) -> some View {
        Label(t, systemImage: icon).font(.caption.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(DS.Palette.elevated, in: Capsule())
            .overlay(Capsule().strokeBorder(DS.Palette.ink.opacity(0.2), lineWidth: 0.7))
            .foregroundStyle(DS.Palette.ink)
    }

    /// Yesterday's food for this meal (breakfast at breakfast time, and so on), logged again for today.
    private func sameAsYesterday() {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date())) ?? Date()
        let end = cal.startOfDay(for: Date())
        let meal = FoodEntry.mealNow()
        let items = ((try? ctx.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.date >= start && $0.date < end }))) ?? []).filter { $0.meal == meal }
        guard !items.isEmpty else { UndoCenter.shared.notify("Nothing logged for \(meal) yesterday"); return }
        SavedMeals.log(SavedMeals.items(items), meal: meal, on: Date(), ctx: ctx)
        Haptics.success()
        UndoCenter.shared.notify("Logged yesterday's \(meal)")
    }
}

/// Today's meals in time order, each a row you can save, copy, share or edit.
struct MealTimeline: View {
    let today: [FoodEntry]
    @Environment(\.modelContext) private var ctx

    var body: some View {
        let meals = ["breakfast", "lunch", "snack", "dinner"].compactMap { m -> (String, [FoodEntry])? in
            let items = today.filter { $0.meal == m }.sorted { $0.date < $1.date }
            return items.isEmpty ? nil : (m, items)
        }
        .sorted { ($0.1.first?.date ?? .distantFuture) < ($1.1.first?.date ?? .distantFuture) }
        VStack(alignment: .leading, spacing: 0) {
            if meals.isEmpty {
                Text("Nothing logged yet. Type, say, snap or scan below.").font(.system(.subheadline, design: .serif).italic())
                    .foregroundStyle(DS.Palette.inkSoft).padding(.vertical, 8)
            }
            ForEach(meals, id: \.0) { m, items in
                let kcal = Int(items.reduce(0) { $0 + ($1.facts.calories ?? 0) })
                let protein = Int(items.reduce(0) { $0 + ($1.facts.protein ?? 0) })
                let verdict = items.map(\.verdict).max { rank($0) < rank($1) } ?? .unknown
                NavigationLink { LazyView(NutritionView()) } label: {
                    HStack(spacing: 12) {
                        Text(items.prefix(2).map { FoodCatalog.emoji(for: $0.name) }.joined())
                            .font(.system(size: 20)).frame(width: 44, height: 44)
                            .background(DS.Palette.elevated, in: .rect(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("**\(m.capitalized)** · \(items.map(\.name).joined(separator: ", "))").font(.subheadline).lineLimit(2)
                                .foregroundStyle(DS.Palette.ink)
                            Text("\(Nautical.clock(items[0].date)) · \(kcal) KCAL · \(protein) P".uppercased()).font(DS.Font.mono).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        Circle().fill(verdict.color).frame(width: 8, height: 8).accessibilityLabel(verdict.label)
                    }
                    .padding(.vertical, 9)
                    .overlay(alignment: .bottom) { Rectangle().fill(DS.Palette.ink.opacity(0.12)).frame(height: 0.6) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Save as a meal", systemImage: "star") {
                        SavedMeals.save(m.capitalized + " · " + Date().formatted(.dateTime.month().day()), entries: items); Haptics.success()
                    }
                    Button("Copy to tomorrow", systemImage: "arrow.right") { copy(items, m, 1) }
                    Button("Copy to yesterday", systemImage: "arrow.left") { copy(items, m, -1) }
                    ShareLink(item: shareText(m, items)) { Label("Share this meal", systemImage: "square.and.arrow.up") }
                    Button("Delete", systemImage: "trash", role: .destructive) { items.forEach { NutritionLog.delete($0, ctx: ctx) }; try? ctx.save() }
                }
            }
        }
    }

    private func rank(_ v: DietVerdict) -> Int { switch v { case .green: 0; case .unknown: 1; case .yellow: 2; case .red: 3 } }

    private func copy(_ items: [FoodEntry], _ meal: String, _ days: Int) {
        let day = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        SavedMeals.log(SavedMeals.items(items), meal: meal, on: day, ctx: ctx)
        Haptics.success()
        UndoCenter.shared.notify(days > 0 ? "Copied to tomorrow" : "Copied to yesterday")
    }

    /// A meal anyone can log: each item with its portion and numbers.
    private func shareText(_ meal: String, _ items: [FoodEntry]) -> String {
        let lines = items.map { "• \($0.name) (\($0.facts.servingLabel)): \(Int($0.facts.calories ?? 0)) kcal, \(Int($0.facts.protein ?? 0)) g protein" }
        let kcal = Int(items.reduce(0) { $0 + ($1.facts.calories ?? 0) })
        return "\(meal.capitalized) · \(kcal) kcal\n" + lines.joined(separator: "\n") + "\n\nLog your share in Keel: type “\(items.map(\.name).joined(separator: ", "))” in Body → Food."
    }
}

// MARK: - Why this score

struct WhyScoreView: View {
    let proteinGoal: Double
    @Query private var today: [FoodEntry]
    @Query private var month: [FoodEntry]
    @State private var glucose: [(Date, Double)] = []

    init(proteinGoal: Double) {
        self.proteinGoal = proteinGoal
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let since = cal.date(byAdding: .day, value: -30, to: start) ?? start
        _today = Query(filter: #Predicate<FoodEntry> { $0.date >= start }, sort: \FoodEntry.date)
        _month = Query(filter: #Predicate<FoodEntry> { $0.date >= since }, sort: \FoodEntry.date)
    }

    var body: some View {
        let r = GalleyScore.score(GalleyScore.bites(today), proteinGoal: proteinGoal)
        let totals = today.reduce(NutritionFacts()) { $0 + $1.facts }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(r.map { "Why \($0.score)" } ?? "Your score").font(.system(.largeTitle, design: .serif, weight: .semibold))
                if let r {
                    Text("Starts at 45, then each part adds or takes points.\(r.early ? " Early: it settles once about a third of your day is logged." : "")")
                        .font(.subheadline).foregroundStyle(DS.Palette.inkSoft)
                    section("Adding points", r.parts.filter { $0.points > 0 }.sorted { $0.points > $1.points })
                    let minus = r.parts.filter { $0.points < 0 }.sorted { $0.points < $1.points }
                    if !minus.isEmpty { section("Taking points", minus) }
                } else {
                    Text("Log a meal and the score shows what it's made of.").foregroundStyle(DS.Palette.inkSoft)
                }
                nextMove(totals)
                MicronutrientsCard(keel: totals)
                if !glucose.isEmpty { glucoseCard }
                timingCard
            }
            .padding(.horizontal, DS.Space.m).padding(.bottom, 40)
        }
        .premiumBackground(DS.Palette.calm)
        .navigationTitle("Nutrition score").navigationBarTitleDisplayMode(.inline)
        .task { glucose = await Self.todaysGlucose() }
    }

    private func section(_ title: String, _ parts: [GalleyScore.Part]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ThemedSectionHeader(title: title).padding(.bottom, 4)
            ForEach(parts) { p in
                HStack(spacing: 12) {
                    Text("\(p.points > 0 ? "+" : "−")\(abs(p.points))").font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundStyle(p.points > 0 ? DS.Palette.calm : Nautical.chartRed).frame(width: 40, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.label).font(.body)
                        Text(p.detail).font(.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(DS.Palette.ink.opacity(0.12)).frame(height: 0.6) }
            }
        }
    }

    /// The single most useful thing to eat next.
    private func nextMove(_ t: NutritionFacts) -> some View {
        let proteinGap = proteinGoal - (t.protein ?? 0)
        let fiberGap = NutritionGoals.fiber - (t.fiber ?? 0)
        let sugar = t.addedSugar ?? 0
        let text: String
        if proteinGap > 20 { text = "A cup of Greek yogurt, two eggs or a palm of chicken closes about 20 g of your \(Int(proteinGap)) g protein gap." }
        else if fiberGap > 8 { text = "An apple and a handful of almonds add about 8 g of the \(Int(fiberGap)) g fiber you're short." }
        else if sugar > NutritionGoals.addedSugarCap { text = "You're over your sugar cap: keep the rest of today's food unsweetened." }
        else { text = "You're on course. Keep dinner simple and you'll land your targets." }
        return HStack(alignment: .top, spacing: 12) {
            WaypointBadge(number: 1, isNext: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Next move").font(.headline)
                Text(text).font(.subheadline).foregroundStyle(DS.Palette.ink)
            }
        }
        .padding(12)
        .background(DS.Palette.elevated, in: .rect(cornerRadius: 12))
    }

    private var glucoseCard: some View {
        let lo = glucose.map(\.1).min() ?? 0, hi = max((glucose.map(\.1).max() ?? 1), lo + 1)
        let start = Calendar.current.startOfDay(for: Date()), span = 86_400.0
        return VStack(alignment: .leading, spacing: 6) {
            ThemedSectionHeader(title: "Glucose today · from Apple Health")
            GeometryReader { g in
                ZStack {
                    Path { p in
                        for (i, pt) in glucose.enumerated() {
                            let x = g.size.width * CGFloat(pt.0.timeIntervalSince(start) / span)
                            let y = g.size.height * (1 - CGFloat((pt.1 - lo) / (hi - lo)))
                            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(Nautical.chartRed, lineWidth: 1.8)
                    ForEach(today) { e in
                        Rectangle().fill(DS.Palette.ink.opacity(0.25)).frame(width: 1)
                            .position(x: g.size.width * CGFloat(e.date.timeIntervalSince(start) / span), y: g.size.height / 2)
                    }
                }
            }
            .frame(height: 70)
            Text("Lines mark your meals. Range today \(Int(lo))–\(Int(hi)).").font(.caption).foregroundStyle(DS.Palette.inkSoft)
        }
    }

    /// Nights after an earlier last meal vs a late one, from your last 30 days.
    @ViewBuilder private var timingCard: some View {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: month, by: { cal.startOfDay(for: $0.date) })
        let days = BodyEngine.shared.days
        let pairs: [(lastHour: Int, anchor: Int)] = byDay.compactMap { day, es in
            guard let last = es.map(\.date).max(),
                  let next = cal.date(byAdding: .day, value: 1, to: day),
                  let a = days.first(where: { cal.isDate($0.day, inSameDayAs: next) })?.anchor else { return nil }
            return (cal.component(.hour, from: last), a)
        }
        let early = pairs.filter { $0.lastHour < 19 }.map(\.anchor), late = pairs.filter { $0.lastHour >= 20 }.map(\.anchor)
        if early.count >= 3 && late.count >= 3 {
            let diff = Int((Double(early.reduce(0, +)) / Double(early.count) - Double(late.reduce(0, +)) / Double(late.count)).rounded())
            VStack(alignment: .leading, spacing: 4) {
                ThemedSectionHeader(title: "Meal timing × Anchor")
                Text(diff >= 0 ? "Nights you finish eating before 7 PM, your Anchor is \(diff) higher than after a late meal."
                               : "Your Anchor doesn't drop after late meals (\(abs(diff)) higher, in fact). Timing isn't your lever.")
                    .font(.subheadline)
            }
            .padding(12).background(DS.Palette.elevated, in: .rect(cornerRadius: 12))
        }
    }

    static func todaysGlucose() async -> [(Date, Double)] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let type = HKQuantityType(.bloodGlucose)
        let start = Calendar.current.startOfDay(for: Date())
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date())
        let unit = HKUnit(from: "mg/dL")
        return await withCheckedContinuation { c in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: 600,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, _ in
                let pts = (samples as? [HKQuantitySample] ?? []).map { ($0.startDate, $0.quantity.doubleValue(for: unit)) }
                c.resume(returning: pts)
            }
            BodyHealth.store.execute(q)
        }
    }
}
