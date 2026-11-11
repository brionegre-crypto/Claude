import Foundation
import ActivityKit

/// Shared between the app and the widget extension. The app writes a small snapshot of your day
/// into the App Group; widgets read it (no database access needed in the extension).
struct WidgetSnapshot: Codable {
    struct Event: Codable, Hashable {
        var title: String
        var start: Date
        var end: Date
        var colorHex: String
    }
    struct TaskLine: Codable, Hashable {
        var title: String
        var due: Date?
        var priority: Int
    }

    var nextThing: String?
    var nextThingStep: String?
    var events: [Event] = []
    var tasks: [TaskLine] = []
    var tasksLeftToday: Int = 0
    var tasksDoneToday: Int = 0
    var updatedAt = Date()

    static let groupId = "group.com.briangreenejr.keel"
    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId)?.appendingPathComponent("widget-snapshot.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let url = Self.fileURL else { return }
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        try? e.encode(self).write(to: url, options: .atomic)
    }

    static let sample = WidgetSnapshot(
        nextThing: "Approve Q4 roadmap", nextThingStep: "Open the roadmap doc",
        events: [Event(title: "Team standup", start: Date().addingTimeInterval(1_800), end: Date().addingTimeInterval(3_600), colorHex: "#5B8DEF"),
                 Event(title: "Lunch with Sam", start: Date().addingTimeInterval(10_800), end: Date().addingTimeInterval(14_400), colorHex: "#46B39E")],
        tasks: [TaskLine(title: "Approve Q4 roadmap", due: Date(), priority: 3), TaskLine(title: "Call the dentist", due: Date(), priority: 1)],
        tasksLeftToday: 4, tasksDoneToday: 3)
}

/// Live Activity for a running focus session (Lock Screen + Dynamic Island).
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endsAt: Date
        var taskTitle: String?
    }
    var startedAt: Date
}
