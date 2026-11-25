import SwiftUI
import SwiftData

/// Body → Food: food front and center. Today's calories and macros, one-tap logging, what you ate and whether it
/// fit your plan, your diets, brain foods, and every food tool, on one page (no digging through menus).
struct BodyFoodPage: View {
    @Query private var entries: [FoodEntry]           // the last 7 days
    @State private var healthTotals: NutritionFacts?
    @State private var weight: Double?
    @AppStorage(PersonalDiets.builtInKey) private var builtIn = true

    init() {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        _entries = Query(filter: #Predicate<FoodEntry> { $0.date >= start }, sort: \FoodEntry.date, order: .reverse)
    }

    var body: some View {
        let cal = Calendar.current
        let today = entries.filter { cal.isDateInToday($0.date) }
        let totals = today.reduce(NutritionFacts()) { $0 + $1.facts }
        let shown = healthTotals ?? totals

        CalorieRingCard(eaten: shown, proteinGoal: NutritionGoals.protein(weightKg: weight))
        TellKeelFoodBox()                                       // "two eggs and toast": logged like a message

        HStack(spacing: 10) {
            NavigationLink { LazyView(LogFoodView()) } label: { BigAction(title: "Log food", icon: "magnifyingglass", color: .green) }
            NavigationLink { LazyView(LogFoodView(startWithCamera: true)) } label: { BigAction(title: "Snap meal", icon: "camera.fill", color: .orange) }
            NavigationLink { LazyView(FoodScanView()) } label: { BigAction(title: "Barcode", icon: "barcode.viewfinder", color: DS.Palette.accent) }
            NavigationLink { LazyView(FoodHistoryView()) } label: { BigAction(title: "History", icon: "calendar", color: .purple) }
        }
        .buttonStyle(.plain)

        Group {
            mealsCard(today)
            savedMealsRow
            NetEnergyCard(eaten: shown.calories ?? 0)
            planCard
        }
        VStack(alignment: .leading, spacing: 10) {
            Text("Fiber & sugar").font(DS.Font.headline)
            GoalBar(title: "Fiber", value: shown.fiber ?? 0, goal: NutritionGoals.fiber, unit: "g", color: DS.Palette.calm)
            GoalBar(title: "Added sugar", value: totals.addedSugar ?? 0, goal: NutritionGoals.addedSugarCap, unit: "g", color: .orange, isCeiling: true)
        }
        .bodyCard()
        Group {
            MicronutrientsCard(keel: totals)
            brainFoods(today: today)
            NutritionScoreCard().overlay(alignment: .topTrailing) { MetricInfoButton(id: "nutritionScore").padding(6) }
        }
        tools
            .task {
                weight = await NutritionHealth.weightKg()
                healthTotals = await NutritionHealth.todayTotals()
            }
    }

    // MARK: Meals

    private func mealsCard(_ today: [FoodEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Eaten today", systemImage: "fork.knife").font(DS.Font.headline).foregroundStyle(DS.Palette.calm)
                Spacer()
                if !today.isEmpty {
                    let tally = Dictionary(grouping: today, by: \.verdict).mapValues(\.count)
                    HStack(spacing: 10) {
                        ForEach([DietVerdict.green, .yellow, .red], id: \.self) { v in
                            Label("\(tally[v] ?? 0)", systemImage: "circle.fill").foregroundStyle(v.color)
                        }
                    }
                    .font(DS.Font.caption).labelStyle(.titleAndIcon)
                }
            }
            if today.isEmpty {
                Text("Nothing logged yet. Log a meal, snap a photo or scan a barcode: Keel checks it against your plan.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            ForEach(["breakfast", "lunch", "dinner", "snack"], id: \.self) { m in
                let items = today.filter { $0.meal == m }
                if !items.isEmpty {
                    HStack {
                        Text(m.capitalized).font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft)
                        Menu {
                            Button("Save as a meal", systemImage: "star") { SavedMeals.save(m.capitalized + " · " + Date().formatted(.dateTime.month().day()), entries: items); savedTick += 1; Haptics.success() }
                            Button("Copy to tomorrow", systemImage: "arrow.right") { copy(items, meal: m, days: 1) }
                            Button("Copy to yesterday", systemImage: "arrow.left") { copy(items, meal: m, days: -1) }
                        } label: { Image(systemName: "ellipsis.circle").font(.caption) }
                        Spacer()
                        Text("\(Int(items.reduce(0) { $0 + ($1.facts.calories ?? 0) })) kcal").font(DS.Font.caption).monospacedDigit().foregroundStyle(DS.Palette.inkSoft)
                    }
                    ForEach(items) { e in EntryRow(e: e) }
                }
            }
            NavigationLink { LazyView(NutritionView()) } label: {
                Label("Edit today's food", systemImage: "square.and.pencil").font(DS.Font.caption.weight(.semibold))
            }
        }
        .bodyCard()
    }

    // MARK: Saved meals

    @Environment(\.modelContext) private var ctx
    @State private var savedTick = 0

    private func copy(_ items: [FoodEntry], meal: String, days: Int) {
        let day = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        SavedMeals.log(SavedMeals.items(items), meal: meal, on: day, ctx: ctx)
        Haptics.success()
        UndoCenter.shared.notify(days > 0 ? "Copied to tomorrow" : "Copied to yesterday")
    }

    @ViewBuilder private var savedMealsRow: some View {
        let _ = savedTick
        let saved = SavedMeals.all
        if !saved.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your meals").font(DS.Font.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(saved) { s in
                            Button {
                                let h = Calendar.current.component(.hour, from: Date())
                                SavedMeals.log(s.items, meal: h < 11 ? "breakfast" : h < 15 ? "lunch" : h < 21 ? "dinner" : "snack", on: Date(), ctx: ctx)
                                Haptics.success(); UndoCenter.shared.notify("Logged \(s.name)")
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text("\(s.items.count) items · \(s.kcal) kcal").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                                }
                                .padding(10)
                                .background { PremiumSurface(tint: .green, radius: 14) }
                            }
                            .buttonStyle(.plain)
                            .contextMenu { Button("Remove", systemImage: "trash", role: .destructive) { SavedMeals.all = SavedMeals.all.filter { $0.id != s.id }; savedTick += 1 } }
                        }
                    }
                }
            }
        }
    }

    // MARK: Your plan

    private var planCard: some View {
        let diets = PersonalDiets.active
        return NavigationLink { LazyView(MyDietsView()) } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.clipboard.fill").font(.title2).foregroundStyle(DS.Palette.calm)
                    .frame(width: 44, height: 44).background(Color.green.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your plan").font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                    let names = (builtIn ? ["ADHD brain diet"] : []) + diets.map(\.name)
                    Text(names.isEmpty ? "No diet set. Upload yours or pick a template." : names.joined(separator: " · "))
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft)
            }
            .bodyCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: Brain foods

    private func brainFoods(today: [FoodEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Brain foods").font(DS.Font.headline)
            ForEach(BrainFoods.items) { item in
                let n = (item.perWeek != nil ? entries : today).filter { $0.tags.contains(item.id) }.count
                let done = n >= (item.perWeek ?? 1)
                HStack {
                    Image(systemName: done ? "checkmark.circle.fill" : item.icon).foregroundStyle(done ? DS.Palette.calm : DS.Palette.inkSoft).frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(.subheadline)
                        Text(item.goal).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                    }
                    Spacer()
                    if let w = item.perWeek { Text("\(n)/\(w)").font(DS.Font.caption).monospacedDigit().foregroundStyle(DS.Palette.inkSoft) }
                }
            }
        }
        .bodyCard()
    }

    // MARK: Every food tool

    private var tools: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            tile("Food library", "books.vertical.fill", .green) { FoodLibraryView() }
            tile("Diet guide", "book.closed.fill", .brown) { DietGuideView() }
            tile("Your diets", "list.bullet.clipboard.fill", .green) { MyDietsView() }
            tile("Caffeine & water", "cup.and.saucer.fill", .brown) {
                ScrollView { VStack(spacing: 16) { DrinksCard(); CaffeineCurveCard() }.padding() }.navigationTitle("Caffeine & water").premiumBackground(.brown)
            }
            tile("Fasting", "timer", .orange) { FastingView() }
            tile("Goals & Apple Health", "heart.text.square.fill", .red) { NutritionSettingsView() }
        }
        .buttonStyle(.plain)
    }

    private func tile<V: View>(_ title: String, _ icon: String, _ color: Color, @ViewBuilder _ dest: @escaping () -> V) -> some View {
        NavigationLink { LazyView(dest()) } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.body.weight(.semibold)).foregroundStyle(color)
                    .frame(width: 34, height: 34).background(color.opacity(0.12), in: .rect(cornerRadius: 10, style: .continuous))
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(DS.Palette.ink).lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { PremiumSurface(radius: 16) }
        }
    }
}
