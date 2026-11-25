import SwiftUI
import SwiftData

// MARK: - Condition (Chart Table's Body home)
//
// Under the three readings: today's one coaching waypoint (the single most useful move), then the Galley: today's
// calories against your target, a big "Log a meal", and what you've eaten so far with times. Everything else on Body
// stays below, unchanged.

/// Today's single most useful move, as a numbered waypoint.
struct ConditionWaypoint: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ThemedSectionHeader(title: "Today's waypoint")
            HStack(alignment: .top, spacing: 12) {
                WaypointBadge(number: 1, isNext: true)
                Text(text).font(.body).foregroundStyle(DS.Palette.ink).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(DS.Palette.ink.opacity(0.15)).frame(height: 0.7) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Food, right under your readings: today's total against your target, Log a meal, and today's meals.
struct GalleyCard: View {
    @Query private var today: [FoodEntry]
    var openFood: () -> Void

    init(openFood: @escaping () -> Void) {
        self.openFood = openFood
        let start = Calendar.current.startOfDay(for: Date())
        _today = Query(filter: #Predicate<FoodEntry> { $0.date >= start }, sort: \FoodEntry.date)
    }

    var body: some View {
        let kcal = Int(today.reduce(0) { $0 + ($1.facts.calories ?? 0) })
        let goal = Int(NutritionGoals.calories)
        VStack(alignment: .leading, spacing: 8) {
            ThemedSectionHeader(title: "Galley · \(kcal.formatted()) / \(goal.formatted()) kcal")
            Button(action: openFood) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Log a meal").font(.system(.headline, design: .serif)).foregroundStyle(DS.Palette.ink)
                        Text("Type a brand, snap a photo or scan").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                    Spacer()
                    Label("Food", systemImage: "plus").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(DS.Palette.ink, in: Capsule())
                        .foregroundStyle(DS.Palette.canvas)
                }
                .padding(12)
                .background(DS.Palette.elevated, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DS.Palette.ink.opacity(0.25), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            ForEach(today.suffix(5)) { e in
                HStack {
                    Text(Nautical.clock(e.date))
                        .font(DS.Font.mono).foregroundStyle(DS.Palette.inkSoft).frame(width: 64, alignment: .leading)
                    Text(e.name).lineLimit(1).foregroundStyle(DS.Palette.ink)
                    Spacer()
                    Text("\(Int(e.facts.calories ?? 0))").font(DS.Font.mono).foregroundStyle(DS.Palette.inkSoft)
                }
                .padding(.vertical, 7)
                .overlay(alignment: .bottom) { Rectangle().fill(DS.Palette.ink.opacity(0.12)).frame(height: 0.6) }
            }
            if today.isEmpty {
                Text("Nothing logged yet today.").font(.system(.footnote, design: .serif).italic()).foregroundStyle(DS.Palette.inkSoft)
            }
        }
    }
}
