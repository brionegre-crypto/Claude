import SwiftUI
import SwiftData
import EventKit
import AudioToolbox
#if !targetEnvironment(macCatalyst)
import ActivityKit
#endif

// MARK: - Evening calm

/// After sunset Keel's whole screen takes on a soft warm tint, so evenings feel quieter. A plain see-through
/// layer (no blending), so it costs nothing while scrolling.
struct EveningCalm: View {
    static let key = "evening.calm"
    @AppStorage(EveningCalm.key) private var on = true
    var body: some View {
        TimelineView(.periodic(from: .now, by: 300)) { ctx in
            let sun = SunClock.today(ctx.date)
            let evening = on && (ctx.date > sun.set || ctx.date < sun.dawn)
            Color(red: 1, green: 0.55, blue: 0.2).opacity(evening ? 0.06 : 0)
                .animation(.easeInOut(duration: 2), value: evening)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Haptic & sound polish

extension Haptics {
    private static var hapticsOff: Bool { UserDefaults.standard.bool(forKey: "haptics.off") }
    /// Soft sounds are off by default; turn them on in Settings → Appearance.
    private static var soundsOn: Bool { UserDefaults.standard.bool(forKey: "sounds.on") }

    /// Finishing something: a success tap and, if you like, a soft "tink".
    static func done() {
        success()
        if soundsOn { AudioServicesPlaySystemSound(1057) }
    }
    /// Starting focus: one firm tap.
    static func start() {
        if !hapticsOff { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8) }
        if soundsOn { AudioServicesPlaySystemSound(1113) }
    }
    /// Capturing a thought: a soft, quick tap.
    static func capture() {
        if !hapticsOff { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        if soundsOn { AudioServicesPlaySystemSound(1104) }
    }
}

struct PolishSettingsSection: View {
    @AppStorage(EveningCalm.key) private var evening = true
    @AppStorage("sounds.on") private var sounds = false
    @AppStorage(DayActivityKeys.on) private var dayLive = false
    var body: some View {
        Section {
            Toggle("Evening calm", isOn: $evening)
            Toggle("Soft sounds", isOn: $sounds)
            #if !targetEnvironment(macCatalyst)
            Toggle("My day on the Lock Screen", isOn: $dayLive)
                .onChange(of: dayLive) { Task { await DayActivity.refresh() } }
            #endif
        } footer: {
            Text("Evening calm warms Keel's colors after sunset. Soft sounds add a gentle tink when you finish a task, start focus or capture something. My day on the Lock Screen shows what you're in now and what's next.")
        }
    }
}

enum DayActivityKeys { static let on = "day.live" }

// MARK: - My day on the Lock Screen (Live Activity)

#if !targetEnvironment(macCatalyst)
@MainActor
enum DayActivity {
    static var on: Bool { UserDefaults.standard.bool(forKey: DayActivityKeys.on) }

    /// What you're in now and what's next today (meetings and timed tasks), plus tonight's bedtime.
    static func state(now: Date = Date()) -> DayActivityAttributes.ContentState? {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let events = CalendarService.shared.events(from: now.addingTimeInterval(-12 * 3600), to: end).filter { !$0.isAllDay && $0.endDate > now }
        let ctx = KeelStore.container.mainContext
        let tasks = ((try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? [])
            .filter { $0.hasDueTime && ($0.dueDate.map { $0 > now && $0 < end } ?? false) }
        typealias Stop = (title: String, at: Date, ends: Date?)
        var upcoming: [Stop] = events.filter { $0.startDate > now }.map { e -> Stop in (title: e.title ?? "Event", at: e.startDate, ends: e.endDate) }
        for t in tasks { if let d = t.dueDate { upcoming.append((title: t.title, at: d, ends: nil)) } }
        upcoming.sort { $0.at < $1.at }
        let bedtime = BodyScores.today()?.bedtime
        if let current = events.first(where: { $0.startDate <= now }) {
            return .init(nowTitle: current.title ?? "Event", nowEnds: current.endDate, nextTitle: upcoming.first?.title, nextAt: upcoming.first?.at, bedtime: bedtime)
        }
        guard let next = upcoming.first else {
            return bedtime.map { .init(nowTitle: "Open water", nowEnds: $0, nextTitle: "Bedtime", nextAt: $0, bedtime: $0) }
        }
        return .init(nowTitle: "Open water", nowEnds: next.at, nextTitle: next.title, nextAt: next.at, bedtime: bedtime)
    }

    static func refresh() async {
        let existing = Activity<DayActivityAttributes>.activities
        let today = Calendar.current.startOfDay(for: Date())
        guard on, ActivityAuthorizationInfo().areActivitiesEnabled, let s = state() else {
            for a in existing { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let content = ActivityContent(state: s, staleDate: s.nextAt ?? Date().addingTimeInterval(3600))
        if let a = existing.first(where: { Calendar.current.isDate($0.attributes.day, inSameDayAs: today) }) {
            await a.update(content)
            for other in existing where other.id != a.id { await other.end(nil, dismissalPolicy: .immediate) }
        } else {
            for a in existing { await a.end(nil, dismissalPolicy: .immediate) }
            _ = try? Activity.request(attributes: DayActivityAttributes(day: today), content: content)
        }
    }
}
#endif
