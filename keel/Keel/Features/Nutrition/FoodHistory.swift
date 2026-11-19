import SwiftUI
import SwiftData
import Charts

/// Everything you've eaten, day by day: a 30-day calorie chart, a strip of days with a ring for each, and the
/// chosen day's meals with their calories and macros. Tap "Log again" to add a food to today in one tap.
struct FoodHistoryView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var entries: [FoodEntry]
    @State private var day = Calendar.current.startOfDay(for: Date())

    init() {
        let start = Calendar.current.date(byAdding: .day, value: -60, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        _entries = Query(filter: #Predicate<FoodEntry> { $0.date >= start }, sort: \FoodEntry.date, order: .reverse)
    }

    private var goal: Double { NutritionGoals.calories }
    private var byDay: [Date: [FoodEntry]] { Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.date) } }

    var body: some View {
        let groups = byDay
        let days = (0..<30).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Calendar.current.startOfDay(for: Date())) }
        let chosen = groups[day] ?? []
        let total = chosen.reduce(NutritionFacts()) { $0 + $1.facts }
        List {
            Section {
                Chart(days.reversed(), id: \.self) { d in
                    BarMark(x: .value("Day", d, unit: .day), y: .value("kcal", (groups[d] ?? []).reduce(0) { $0 + ($1.facts.calories ?? 0) }))
                        .foregroundStyle(Calendar.current.isDate(d, inSameDayAs: day) ? Color.green : Color.green.opacity(0.35))
                        .cornerRadius(3)
                    RuleMark(y: .value("Goal", goal)).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .chartXAxis(.hidden)
                .frame(height: 120)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(days, id: \.self) { d in
                            let kcal = (groups[d] ?? []).reduce(0) { $0 + ($1.facts.calories ?? 0) }
                            Button { withAnimation(DS.spring) { day = d }; Haptics.tap() } label: {
                                VStack(spacing: 4) {
                                    ZStack {
                                        Circle().stroke(Color.green.opacity(0.15), lineWidth: 4)
                                        Circle().trim(from: 0, to: min(1, kcal / max(goal, 1))).stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                                        Text(d.formatted(.dateTime.day())).font(.caption.weight(.semibold))
                                    }
                                    .frame(width: 38, height: 38)
                                    Text(d.formatted(.dateTime.weekday(.abbreviated))).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                                }
                                .padding(6)
                                .background(Calendar.current.isDate(d, inSameDayAs: day) ? Color.green.opacity(0.12) : .clear, in: .rect(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(total.calories ?? 0))").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("of \(Int(goal)) kcal").foregroundStyle(DS.Palette.inkSoft)
                    Spacer()
                }
                HStack(spacing: 10) {
                    macro("Protein", total.protein, .blue)
                    macro("Carbs", total.carbs, .orange)
                    macro("Fat", total.fat, .pink)
                }
            } header: { Text(Calendar.current.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.wide).month().day())) }
            if chosen.isEmpty {
                ContentUnavailableView("Nothing logged", systemImage: "fork.knife", description: Text("Pick another day, or log food from Today."))
                    .listRowBackground(Color.clear)
            }
            ForEach(["breakfast", "lunch", "dinner", "snack"], id: \.self) { meal in
                let items = chosen.filter { $0.meal == meal }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { e in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.name).font(DS.Font.body)
                                    Text("\(e.date.formatted(date: .omitted, time: .shortened))" + (e.servings != 1 ? " · \(e.servings.formatted()) servings" : ""))
                                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                                }
                                Spacer()
                                Text("\(Int(e.facts.calories ?? 0)) kcal").font(.callout.weight(.semibold)).monospacedDigit()
                            }
                            .swipeActions(edge: .leading) {
                                Button { NutritionLog.logAgain(e, ctx: ctx); Haptics.success(); UndoCenter.shared.notify("Logged \(e.name) again") } label: {
                                    Label("Log again", systemImage: "plus.circle")
                                }.tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { NutritionLog.delete(e, ctx: ctx) } label: { Label("Delete", systemImage: "trash") }
                            }
                            .contextMenu {
                                Button("Log again today", systemImage: "plus.circle") { NutritionLog.logAgain(e, ctx: ctx); Haptics.success() }
                                Button("Delete", systemImage: "trash", role: .destructive) { NutritionLog.delete(e, ctx: ctx) }
                            }
                        }
                    } header: {
                        HStack {
                            Text(meal.capitalized)
                            Spacer()
                            Text("\(Int(items.reduce(0) { $0 + ($1.facts.calories ?? 0) })) kcal")
                        }
                    }
                }
            }
        }
        .navigationTitle("Food history")
    }

    private func macro(_ name: String, _ grams: Double?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.caption).foregroundStyle(DS.Palette.inkSoft)
            Text("\(Int(grams ?? 0)) g").font(.headline).monospacedDigit()
            Capsule().fill(color.gradient).frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
