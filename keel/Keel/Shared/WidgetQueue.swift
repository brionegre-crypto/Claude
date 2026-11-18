import Foundation
import AppIntents
import WidgetKit

/// Taps on interactive widgets run in the widget extension, which can't open Keel's database.
/// They're queued in the App Group and applied by the app the next time it's active (or syncs);
/// the widget updates its own snapshot right away so the checkmark shows instantly.
enum WidgetQueue {
    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.groupId)?
            .appendingPathComponent("widget-actions.json")
    }

    /// Darwin notification the widget posts so a Keel that's open (iPad, Mac) applies the tap right away.
    static let changedName = "com.keel.widget-actions.changed"

    /// The widget and the app both touch this file. Each read-and-write is coordinated, so a tap that lands
    /// while Keel is applying earlier taps is never lost (before, it could be wiped and the task stayed open).
    private static func withFile<T>(_ body: (URL) -> T) -> T? {
        guard let url else { return nil }
        var result: T?
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &error) { u in result = body(u) }
        return result
    }

    private static func read(_ u: URL) -> [WatchAction] {
        guard let data = try? Data(contentsOf: u) else { return [] }
        return (try? JSONDecoder().decode([WatchAction].self, from: data)) ?? []
    }

    static func append(_ action: WatchAction) {
        _ = withFile { u in
            var all = read(u)
            all.append(action)
            if let data = try? JSONEncoder().encode(all) { try? data.write(to: u, options: .atomic) }
        }
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(changedName as CFString), nil, nil, true)
    }

    static func pending() -> [WatchAction] {
        withFile { read($0) } ?? []
    }

    static func drain() -> [WatchAction] {
        withFile { u -> [WatchAction] in
            let all = read(u)
            if !all.isEmpty { try? FileManager.default.removeItem(at: u) }
            return all
        } ?? []
    }
}

struct WidgetCompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let isDiscoverable = false
    @Parameter(title: "Task ID") var taskId: String

    init() {}
    init(id: UUID) { taskId = id.uuidString }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskId) else { return .result() }
        WidgetQueue.append(.completeTask(id))
        if var s = WidgetSnapshot.load() {
            s.tasks.removeAll { $0.id == id }
            s.groceries?.removeAll { $0.id == id }
            s.evening?.removeAll { $0.id == id }
            s.tasksLeftToday = max(0, s.tasksLeftToday - 1)
            s.tasksDoneToday += 1
            s.save()
        }
        return .result()
    }
}

struct WidgetArchiveMailIntent: AppIntent {
    static let title: LocalizedStringResource = "Archive Email"
    static let isDiscoverable = false
    @Parameter(title: "Email ID") var emailId: String

    init() {}
    init(id: String) { emailId = id }

    func perform() async throws -> some IntentResult {
        WidgetQueue.append(.archiveMail(emailId))
        if var s = WidgetSnapshot.load() {
            s.mail?.removeAll { $0.id == emailId }
            s.save()
        }
        return .result()
    }
}

struct WidgetCompleteHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Habit"
    static let isDiscoverable = false
    @Parameter(title: "Habit ID") var habitId: String

    init() {}
    init(id: UUID) { habitId = id.uuidString }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: habitId) else { return .result() }
        if var s = WidgetSnapshot.load(), let i = s.habits?.firstIndex(where: { $0.id == id }), s.habits?[i].done == false {
            s.habits?[i].done = true
            s.save()
            WidgetQueue.append(.completeHabit(id))
        }
        return .result()
    }
}
