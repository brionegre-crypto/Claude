import Foundation

/// What the iPhone sends to Apple Watch (compiled into both apps).
struct WatchPayload: Codable {
    struct TaskRow: Codable, Identifiable, Hashable {
        var id: UUID
        var title: String
        var due: Date?
        var hasTime: Bool
        var priority: Int
    }
    struct HabitRow: Codable, Identifiable, Hashable {
        var id: UUID
        var name: String
        var icon: String
        var stack: String
        var doneToday: Bool
    }
    struct EventRow: Codable, Hashable {
        var title: String
        var start: Date
        var end: Date
    }

    var nextThing: String?
    var nextThingStep: String?
    var tasks: [TaskRow] = []
    var habits: [HabitRow] = []
    var events: [EventRow] = []
    var focusEndsAt: Date?
    var updatedAt = Date()
}

/// What Apple Watch asks the iPhone to do.
enum WatchAction: Codable {
    case completeTask(UUID)
    case addTask(String)
    case completeHabit(UUID)
    case startFocus(Int)
    case endFocus
}

enum WatchCoding {
    static func encode<T: Encodable>(_ v: T) -> Data? {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        return try? e.encode(v)
    }
    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) -> T? {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(type, from: data)
    }
}
