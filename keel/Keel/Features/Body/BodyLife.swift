import SwiftUI

// MARK: - "Not a normal day"
//
// The top complaint about recovery apps: one rough night (a sick kid, a red-eye flight, a late service) drags your
// "normal" down for weeks and the app keeps scolding you. Mark the day and Keel leaves it out of your baselines,
// changes its advice to fit, and labels it in your history so the dip makes sense later.

enum LifeEvent: String, CaseIterable, Identifiable {
    case sick, travel, lateNight, alcohol, stress, kids, period, shift, bigEvent

    var id: String { rawValue }
    var title: String {
        switch self {
        case .sick: "Sick"
        case .travel: "Travel"
        case .lateNight: "Late night"
        case .alcohol: "Drinks"
        case .stress: "Stressful day"
        case .kids: "Kids up at night"
        case .period: "Period"
        case .shift: "Odd hours"
        case .bigEvent: "Big event"
        }
    }
    var icon: String {
        switch self {
        case .sick: "thermometer.medium"
        case .travel: "airplane"
        case .lateNight: "moon.haze.fill"
        case .alcohol: "wineglass.fill"
        case .stress: "bolt.heart.fill"
        case .kids: "figure.and.child.holdinghands"
        case .period: "drop.fill"
        case .shift: "clock.arrow.2.circlepath"
        case .bigEvent: "star.fill"
        }
    }
    var advice: String {
        switch self {
        case .sick: "Rest is the training today. Fluids, sleep, no hard workouts until your resting heart rate is back to normal."
        case .travel: "Get daylight at your destination's morning, drink water, and keep effort easy for a day."
        case .lateNight: "Keep today light and get to bed on time tonight. One short nap before 3 PM is fine."
        case .alcohol: "Expect higher heart rate and lower HRV tonight. Water now, easy effort today."
        case .stress: "A 10-minute walk or slow breathing helps your body come down. Don't pile on a hard workout."
        case .kids: "Broken sleep counts. Go easy and grab rest when you can."
        case .period: "Higher resting heart rate and temperature are normal this week. Keel won't count it against you."
        case .shift: "Your body clock is off. Keep meals and light at regular times where you can."
        case .bigEvent: "A big day uses energy even when it's good. Plan a calm evening."
        }
    }
}

enum LifeEvents {
    private static let key = "body.lifeEvents.v1"        // "yyyy-MM-dd" → [LifeEvent]

    private static func dayKey(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static var store: [String: [String]] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:] }
        set {
            // Keep about a year.
            let cutoff = dayKey(Date().addingTimeInterval(-370 * 86_400))
            UserDefaults.standard.set(newValue.filter { $0.key >= cutoff && !$0.value.isEmpty }, forKey: key)
        }
    }

    static func events(on day: Date) -> [LifeEvent] {
        (store[dayKey(day)] ?? []).compactMap(LifeEvent.init(rawValue:))
    }

    static func toggle(_ e: LifeEvent, on day: Date) {
        var s = store
        var list = s[dayKey(day)] ?? []
        if let i = list.firstIndex(of: e.rawValue) { list.remove(at: i) } else { list.append(e.rawValue) }
        s[dayKey(day)] = list
        store = s
    }

    /// Days you marked, so the recovery maths can leave them out of your normal.
    static func markedDayKeys() -> Set<String> { Set(store.filter { !$0.value.isEmpty }.keys) }
    static func isMarked(_ day: Date, in keys: Set<String>) -> Bool { keys.contains(dayKey(day)) }
}

/// On Body → Today: one tap to say "today isn't normal".
struct LifeEventsCard: View {
    let day: Date
    @State private var marked: [LifeEvent] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Not a normal day?", systemImage: "calendar.badge.exclamationmark").font(DS.Font.headline)
                Spacer()
                if !marked.isEmpty { Text("Left out of your normal").font(.caption2.weight(.semibold)).foregroundStyle(DS.Palette.calm) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LifeEvent.allCases) { e in
                        let on = marked.contains(e)
                        Button {
                            LifeEvents.toggle(e, on: day)
                            marked = LifeEvents.events(on: day)
                            BodyEngine.shared.rescore()
                            Haptics.tap()
                        } label: {
                            Label(e.title, systemImage: e.icon)
                                .font(.subheadline.weight(on ? .semibold : .regular))
                                .padding(.horizontal, 11).padding(.vertical, 7)
                                .foregroundStyle(on ? Color.white : DS.Palette.ink)
                                .background(on ? AnyShapeStyle(DS.Palette.accent) : AnyShapeStyle(.thinMaterial), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            if let first = marked.first {
                Text(first.advice).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    .transition(.opacity)
            } else {
                Text("Sick, travelling, a late night? Mark it and Keel won't let one rough day drag down your normal.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
        }
        .bodyCard()
        .onAppear { marked = LifeEvents.events(on: day) }
        .onChange(of: day) { marked = LifeEvents.events(on: day) }
    }
}
