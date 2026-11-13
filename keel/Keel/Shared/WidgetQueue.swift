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

    static func append(_ action: WatchAction) {
        var all = pending()
        all.append(action)
        if let url, let data = try? JSONEncoder().encode(all) { try? data.write(to: url, options: .atomic) }
    }

    static func pending() -> [WatchAction] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([WatchAction].self, from: data)) ?? []
    }

    static func drain() -> [WatchAction] {
        let all = pending()
        if let url { try? FileManager.default.removeItem(at: url) }
        return all
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
