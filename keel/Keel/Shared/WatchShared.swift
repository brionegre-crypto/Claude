import Foundation

/// What the iPhone sends to Apple Watch (compiled into the iPhone app, the watch app and its complications).
/// Fields added later are optional so an older watch app can still read a newer payload.
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
    struct MailRow: Codable, Identifiable, Hashable {
        var id: String            // EmailMessage.id
        var from: String
        var subject: String
        var summary: String
    }
    struct PersonRow: Codable, Identifiable, Hashable {
        var id: UUID
        var name: String
        var phone: String
        var lastContact: Date?
    }
    struct ProjectRow: Codable, Hashable {
        var name: String
        var emoji: String
        var done: Int
        var total: Int
    }
    struct WeatherRow: Codable, Hashable {
        var temperature: String
        var symbol: String
        var condition: String
        var high: String
        var low: String
        var rainFrom: Date?
    }
    struct MoodDay: Codable, Hashable {
        var day: Date
        var mood: Int
        var energy: Int?
    }
    struct MedRow: Codable, Hashable {
        var id: UUID
        var name: String
        var slot: Int             // minutes after midnight
        var takenAt: Date?
    }
    struct DeliveryRow: Codable, Hashable {
        var title: String
        var carrier: String
        var status: String        // human label: "Arriving today", "Out for delivery"…
    }
    struct CountdownRow: Codable, Hashable {
        var title: String
        var emoji: String
        var date: Date
    }

    var nextThing: String?
    var nextThingStep: String?
    var tasks: [TaskRow] = []
    var habits: [HabitRow] = []
    var events: [EventRow] = []
    var focusEndsAt: Date?
    var updatedAt = Date()

    // Added for the full watch app
    var energy: Int? = nil                // 1 low, 2 steady, 3 locked in
    var checkedInMood: Int? = nil         // today's check-in, if any
    var mail: [MailRow]? = nil            // important unread
    var promises: [String]? = nil         // promises due today/overdue
    var followUps: [String]? = nil        // people who haven't replied
    var people: [PersonRow]? = nil        // keep in touch: due now
    var countdowns: [CountdownRow]? = nil
    var doneToday: Int? = nil
    var focusMinutesWeek: Int? = nil
    var projects: [ProjectRow]? = nil
    var weather: WeatherRow? = nil
    var focusDays: [Int]? = nil           // minutes focused, oldest → today (7 days)
    var moodWeek: [MoodDay]? = nil
    var meds: [MedRow]? = nil
    var momentum: Int? = nil              // today's 0–100 momentum score
    var achievementsUnlocked: Int? = nil
    var scheduledMail: Int? = nil
    var briefing: String? = nil
    var deliveries: [DeliveryRow]? = nil
    var subscriptionsMonthly: String? = nil
    var nextTrip: String? = nil           // "✈︎ UA 1234 SFO → JFK · Fri 7:05 AM · ABC123"
    var unreadCount: Int? = nil
    var worldClock: [String]? = nil       // time zone identifiers
    var calm: Bool? = nil
    var weekDone: Int? = nil              // tasks completed in the last 7 days
    var doneStreak: Int? = nil            // days in a row with something done
}

/// What Apple Watch asks the iPhone to do.
enum WatchAction: Codable {
    case completeTask(UUID)
    case addTask(String)
    case completeHabit(UUID)
    case startFocus(Int)
    case endFocus
    case moveTaskTomorrow(UUID)
    case setEnergy(Int)
    case checkIn(Int)
    case archiveMail(String)
    case loggedContact(UUID)
    case carryOverToday
    case parkThought(String)
    case takeMed(UUID, Int)
    case brainDump(String)
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
