import Foundation
#if !targetEnvironment(macCatalyst)
import ActivityKit
#endif

/// Shared between the app and the widget extension. The app writes a small snapshot of your day
/// into the App Group; widgets read it (no database access needed in the extension).
struct WidgetSnapshot: Codable {
    struct Event: Codable, Hashable {
        var title: String
        var start: Date
        var end: Date
        var colorHex: String
        var joinURL: String? = nil          // video-call link, if the event has one
    }
    struct TaskLine: Codable, Hashable {
        var title: String
        var due: Date?
        var priority: Int
        var id: UUID? = nil
    }
    struct HabitLine: Codable, Hashable {
        var id: UUID
        var name: String
        var icon: String
        var done: Bool
    }

    var nextThing: String?
    var nextThingStep: String?
    var events: [Event] = []
    var tasks: [TaskLine] = []
    var tasksLeftToday: Int = 0
    var tasksDoneToday: Int = 0
    var countdowns: [CountdownLine]? = nil
    var habits: [HabitLine]? = nil
    var briefing: String? = nil
    var nextMed: String? = nil            // "Adderall 20 mg"
    var nextMedAt: Date? = nil
    var medsLeftToday: Int? = nil
    var momentum: Int? = nil
    // Newer widgets (optional so older snapshots still load)
    var groceries: [TaskLine]? = nil       // open items in the Groceries list
    var evening: [TaskLine]? = nil         // This Evening
    var deadlines: [TaskLine]? = nil       // due = the deadline
    var level: Int? = nil
    var levelProgress: Double? = nil       // 0…1 toward the next level
    var coins: Int? = nil

    struct CountdownLine: Codable, Hashable {
        var title: String
        var emoji: String
        var date: Date
    }
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

#if !targetEnvironment(macCatalyst)   // Live Activities are iPhone-only
/// Live Activity for a running focus session (Lock Screen + Dynamic Island).
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endsAt: Date
        var taskTitle: String?
    }
    var startedAt: Date
}

/// Live Activity for a meeting in progress: time left, Join, and whether Keel is recording notes.
struct MeetingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var start: Date
        var end: Date
        var recording: Bool
        var since: Date? = nil              // when recording began, for the elapsed timer on the Lock Screen
    }
    var eventId: String
    /// A recording with no calendar event behind it ("rec-…"): shows elapsed time instead of time left.
    var isAdHoc: Bool { eventId.hasPrefix("rec-") }
    var title: String
    var joinURL: String?
    var service: String?

    /// Opens Keel, which opens the call (Live Activity links must go through the app).
    var joinDeepLink: URL? {
        guard let joinURL, let q = joinURL.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        return URL(string: "com.keel.app://join?url=\(q)")
    }
}
#endif
