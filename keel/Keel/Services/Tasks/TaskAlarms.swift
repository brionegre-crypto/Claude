import Foundation
import SwiftUI
import SwiftData
#if !targetEnvironment(macCatalyst)
import AlarmKit
import ActivityKit
#endif
import AppIntents

#if !targetEnvironment(macCatalyst)
/// Full-screen task alarms (iOS 26 AlarmKit): a due task takes over the Lock Screen like an alarm clock,
/// with Done and Snooze buttons, and breaks through Silent mode and Focus. Banners stay the default.
struct KeelAlarmMetadata: AlarmMetadata {
    var taskId: String = ""
}

@MainActor
enum TaskAlarms {
    static let globalKey = "tasks.fullScreenAlarms"
    /// On by default, like an alarm-clock reminder: timed tasks take over the screen until you tap Done or Snooze.
    static var globalOn: Bool { UserDefaults.standard.object(forKey: globalKey) as? Bool ?? true }

    /// The task's own choice wins; otherwise the setting.
    static func wanted(_ t: TaskItem) -> Bool { t.useAlarm ?? globalOn }

    static func authorize() async -> Bool {
        switch AlarmManager.shared.authorizationState {
        case .authorized: return true
        case .denied: return false
        default: return ((try? await AlarmManager.shared.requestAuthorization()) ?? .denied) == .authorized
        }
    }

    static func schedule(_ t: TaskItem, at fire: Date) async {
        cancel(t)
        guard await authorize() else { return }
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: t.title),
            stopButton: AlarmButton(text: "Done", textColor: .white, systemImageName: "checkmark.circle.fill"),
            secondaryButton: AlarmButton(text: "Snooze 10 min", textColor: .white, systemImageName: "zzz"),
            secondaryButtonBehavior: .custom)
        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert),
                                         metadata: KeelAlarmMetadata(taskId: t.id.uuidString),
                                         tintColor: DS.Palette.accent)
        let config = AlarmManager.AlarmConfiguration<KeelAlarmMetadata>(
            countdownDuration: nil,
            schedule: .fixed(fire),
            attributes: attributes,
            stopIntent: CompleteTaskFromAlarmIntent(taskId: t.id.uuidString),
            secondaryIntent: SnoozeTaskAlarmIntent(taskId: t.id.uuidString),
            sound: .default)
        _ = try? await AlarmManager.shared.schedule(id: t.id, configuration: config)
    }

    static func cancel(_ t: TaskItem) {
        try? AlarmManager.shared.cancel(id: t.id)
    }
}

#else
/// Full-screen alarms are an iPhone feature; on Mac, tasks use regular Time Sensitive notifications.
@MainActor
enum TaskAlarms {
    static let globalKey = "tasks.fullScreenAlarms"
    static var globalOn: Bool { false }
    static func wanted(_ t: TaskItem) -> Bool { false }
    static func authorize() async -> Bool { false }
    static func schedule(_ t: TaskItem, at fire: Date) async {}
    static func cancel(_ t: TaskItem) {}
}
#endif

#if targetEnvironment(macCatalyst)
typealias KeelAlarmIntent = AppIntent
#else
typealias KeelAlarmIntent = LiveActivityIntent
#endif

/// "Done" on the alarm.
struct CompleteTaskFromAlarmIntent: KeelAlarmIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let isDiscoverable = false
    @Parameter(title: "Task ID") var taskId: String

    init() {}
    init(taskId: String) { self.taskId = taskId }

    @MainActor func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskId) else { return .result() }
        let ctx = KeelStore.container.mainContext
        if let t = try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first {
            TaskActions.setDone(t, true)
            try? ctx.save()
        }
        return .result()
    }
}

/// "Snooze 10 min" on the alarm.
struct SnoozeTaskAlarmIntent: KeelAlarmIntent {
    static let title: LocalizedStringResource = "Snooze Task"
    static let isDiscoverable = false
    @Parameter(title: "Task ID") var taskId: String

    init() {}
    init(taskId: String) { self.taskId = taskId }

    @MainActor func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskId) else { return .result() }
        let ctx = KeelStore.container.mainContext
        if let t = try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first {
            await TaskAlarms.schedule(t, at: Date().addingTimeInterval(600))
        }
        return .result()
    }
}
