import SwiftUI
import AppIntents
#if !targetEnvironment(macCatalyst)
import AlarmKit
import ActivityKit
#endif

/// Opens a routine's step-by-step player from anywhere (its alarm, or its stop on Today).
@MainActor @Observable
final class RoutineLaunch {
    static let shared = RoutineLaunch()
    var routine: Routine?

    func start(_ id: UUID) {
        guard let r = RoutineStore.all.first(where: { $0.id == id }) else { return }
        AppRouter.shared.tab = .today
        routine = r
    }
}

#if !targetEnvironment(macCatalyst)
struct KeelRoutineAlarmMetadata: AlarmMetadata {
    var routineId: String = ""
}

/// Timed routines can ring like an alarm clock (full screen, through Silent and Focus) when it's time to start.
/// "Start" opens the routine's player; "Snooze" asks again in 10 minutes. Set for the next time each one is due,
/// and refreshed whenever routines change and each time Keel opens.
@MainActor
enum RoutineAlarms {
    private static func id(_ r: Routine) -> UUID { r.id }

    static func refresh() {
        Task {
            for r in RoutineStore.all { try? AlarmManager.shared.cancel(id: id(r)) }
            let due = RoutineStore.all.filter { $0.alarm == true && $0.startMinute != nil }
            guard !due.isEmpty, await TaskAlarms.authorize() else { return }
            for r in due { await schedule(r, at: nextStart(r)) }
        }
    }

    static func nextStart(_ r: Routine, now: Date = Date()) -> Date {
        let m = r.startMinute ?? 0
        let cal = Calendar.current
        let today = cal.date(bySettingHour: max(0, m) / 60, minute: max(0, m) % 60, second: 0, of: now) ?? now
        return today > now ? today : (cal.date(byAdding: .day, value: 1, to: today) ?? today)
    }

    static func schedule(_ r: Routine, at fire: Date) async {
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: "\(r.name) routine"),
            stopButton: AlarmButton(text: "Start", textColor: .white, systemImageName: "play.fill"),
            secondaryButton: AlarmButton(text: "Snooze 10 min", textColor: .white, systemImageName: "zzz"),
            secondaryButtonBehavior: .custom)
        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert),
                                         metadata: KeelRoutineAlarmMetadata(routineId: r.id.uuidString),
                                         tintColor: DS.Palette.accent)
        let config = AlarmManager.AlarmConfiguration<KeelRoutineAlarmMetadata>(
            countdownDuration: nil, schedule: .fixed(fire), attributes: attributes,
            stopIntent: StartRoutineFromAlarmIntent(routineId: r.id.uuidString),
            secondaryIntent: SnoozeRoutineAlarmIntent(routineId: r.id.uuidString),
            sound: .default)
        _ = try? await AlarmManager.shared.schedule(id: id(r), configuration: config)
    }
}

struct StartRoutineFromAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Routine"
    static let isDiscoverable = false
    static let openAppWhenRun = true
    @Parameter(title: "Routine ID") var routineId: String
    init() {}
    init(routineId: String) { self.routineId = routineId }
    @MainActor func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: routineId) { RoutineLaunch.shared.start(id) }
        RoutineAlarms.refresh()                       // set tomorrow's
        return .result()
    }
}

struct SnoozeRoutineAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Snooze Routine"
    static let isDiscoverable = false
    @Parameter(title: "Routine ID") var routineId: String
    init() {}
    init(routineId: String) { self.routineId = routineId }
    @MainActor func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: routineId), let r = RoutineStore.all.first(where: { $0.id == id }) {
            await RoutineAlarms.schedule(r, at: Date().addingTimeInterval(600))
        }
        return .result()
    }
}
#else
@MainActor
enum RoutineAlarms { static func refresh() {} }
#endif
