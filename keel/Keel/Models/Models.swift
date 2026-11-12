import Foundation
import SwiftData

// MARK: - Mail

enum MailProviderKind: String, Codable, CaseIterable, Identifiable {
    case gmail, outlook, icloud, yahoo, aol, imap
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .gmail: "Gmail"; case .outlook: "Outlook"; case .icloud: "iCloud Mail"
        case .yahoo: "Yahoo Mail"; case .aol: "AOL Mail"; case .imap: "Email (IMAP)"
        }
    }
    var usesIMAP: Bool { ![.gmail, .outlook].contains(self) }
}

@Model final class MailAccount {
    @Attribute(.unique) var id: String          // provider + address
    var provider: MailProviderKind
    var address: String
    var displayName: String
    var colorHex: String
    var syncCursor: String?                      // Gmail historyId / Graph deltaLink / IMAP UIDNEXT
    var lastSyncedAt: Date?
    var lastSentScanAt: Date?                    // promise tracker: last time Sent mail was scanned
    var isEnabled: Bool = true
    var signature: String?                       // per-account; nil uses the shared signature

    init(provider: MailProviderKind, address: String, displayName: String, colorHex: String = "#5B8DEF") {
        self.id = "\(provider.rawValue):\(address.lowercased())"
        self.provider = provider
        self.address = address
        self.displayName = displayName
        self.colorHex = colorHex
    }
}

/// AI-assigned buckets — the "Split Inbox" (Superhuman) / "Smart Inbox" (Spark) idea.
enum TriageCategory: String, Codable, CaseIterable, Identifiable {
    case important      // needs a human reply from you
    case actionable     // contains a task or deadline
    case calendar       // invite, reschedule, booking
    case updates        // receipts, shipping, notifications
    case newsletters
    case promotions
    case lowPriority
    var id: String { rawValue }
}

@Model final class EmailMessage {
    @Attribute(.unique) var id: String          // accountId + provider message id
    var accountId: String
    var providerMessageId: String
    var threadId: String
    var from: String
    var fromName: String
    var subject: String
    var snippet: String
    var bodyPlain: String
    var receivedAt: Date
    var isRead: Bool
    var isArchived: Bool = false
    var snoozedUntil: Date?
    // Full mail client fields
    var bodyHTML: String?
    var messageIdHeader: String?               // RFC Message-ID, for threaded replies
    var toLine: String = ""
    var ccLine: String = ""
    var isStarred: Bool = false
    var isPinned: Bool = false                  // pinned to the top of Inbox
    var hasAttachments: Bool = false
    var unsubscribeHeader: String?              // raw List-Unsubscribe header (mailto: and/or https:)
    var unsubscribeOneClick: Bool = false       // List-Unsubscribe-Post: one-click supported

    // AI fields
    var category: TriageCategory?
    var priorityScore: Double = 0               // 0…1
    var aiSummary: String?
    var suggestedReply: String?
    var extractedTaskTitle: String?
    var extractedDueDate: Date?
    var triagedAt: Date?

    init(accountId: String, providerMessageId: String, threadId: String, from: String, fromName: String,
         subject: String, snippet: String, bodyPlain: String, receivedAt: Date, isRead: Bool) {
        self.id = "\(accountId)|\(providerMessageId)"
        self.accountId = accountId
        self.providerMessageId = providerMessageId
        self.threadId = threadId
        self.from = from
        self.fromName = fromName
        self.subject = subject
        self.snippet = snippet
        self.bodyPlain = bodyPlain
        self.receivedAt = receivedAt
        self.isRead = isRead
    }

    convenience init(accountId: String, fetched m: FetchedMessage) {
        self.init(accountId: accountId, providerMessageId: m.providerId, threadId: m.threadId, from: m.from,
                  fromName: m.fromName, subject: m.subject, snippet: m.snippet, bodyPlain: m.body,
                  receivedAt: m.date, isRead: m.isRead)
        bodyHTML = m.html
        messageIdHeader = m.messageIdHeader
        toLine = m.to
        ccLine = m.cc
        isStarred = m.isStarred
        hasAttachments = m.hasAttachments
        unsubscribeHeader = m.unsubscribe
        unsubscribeOneClick = m.unsubscribeOneClick
    }

    var replyContext: ReplyContext {
        ReplyContext(providerMessageId: providerMessageId, threadId: threadId, messageIdHeader: messageIdHeader, replyAll: false)
    }
}

// MARK: - Tasks (TickTick-style)

enum TaskPriority: Int, Codable, CaseIterable { case none = 0, low, medium, high }

/// ADHD: pick tasks by how much brain you have right now, not just by priority.
enum EnergyLevel: Int, Codable, CaseIterable, Identifiable {
    case low = 1, medium, high
    var id: Int { rawValue }
    var label: String { switch self { case .low: "Low battery"; case .medium: "Steady"; case .high: "Locked in" } }
    var icon: String { switch self { case .low: "battery.25"; case .medium: "battery.50"; case .high: "battery.100.bolt" } }
}

/// Repeat rule for tasks (mirrors to Apple Reminders as an EKRecurrenceRule).
struct Recurrence: Codable, Hashable {
    enum Frequency: String, Codable, CaseIterable, Identifiable {
        case daily, weekly, monthly, yearly
        var id: String { rawValue }
        var unit: String { switch self { case .daily: "day"; case .weekly: "week"; case .monthly: "month"; case .yearly: "year" } }
    }
    var frequency: Frequency
    var interval: Int = 1
    var weekdays: [Int] = []                    // Calendar weekday numbers (1 = Sunday … 7 = Saturday), weekly only
    var endDate: Date? = nil
    /// "Water plants 7 days after I last did it": the next date counts from when you complete it.
    var fromCompletion: Bool?

    static let weekdaysOnly = Recurrence(frequency: .weekly, weekdays: [2, 3, 4, 5, 6])

    /// The next due date after `date`, keeping the time of day. Nil once the repeat has ended.
    func next(after date: Date) -> Date? {
        let cal = Calendar.current
        var result: Date?
        if frequency == .weekly && !weekdays.isEmpty {
            for offset in 1...(7 * max(interval, 1) + 7) {
                guard let d = cal.date(byAdding: .day, value: offset, to: date) else { continue }
                if weekdays.contains(cal.component(.weekday, from: d)) { result = d; break }
            }
        } else {
            let comp: Calendar.Component = switch frequency { case .daily: .day; case .weekly: .weekOfYear; case .monthly: .month; case .yearly: .year }
            result = cal.date(byAdding: comp, value: max(interval, 1), to: date)
        }
        if let r = result, let end = endDate, r > end { return nil }
        return result
    }

    var label: String {
        if self == .weekdaysOnly { return "Every weekday" }
        if frequency == .weekly && !weekdays.isEmpty {
            let names = Calendar.current.shortWeekdaySymbols
            let days = weekdays.sorted().map { names[($0 - 1) % 7] }.joined(separator: ", ")
            return interval > 1 ? "Every \(interval) weeks on \(days)" : "Every \(days)"
        }
        let base = interval == 1 ? "Every \(frequency.unit)" : "Every \(interval) \(frequency.unit)s"
        return fromCompletion == true ? base + " after done" : base
    }
}

/// ADHD: big tasks are paralyzing — AI splits them into ≤10-minute physical next actions.
struct MicroStep: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var minutes: Int
    var done = false
}

@Model final class TaskItem {
    var id: UUID = UUID()
    var title: String
    var notes: String = ""
    var dueDate: Date?
    var priority: TaskPriority = TaskPriority.none
    var isDone: Bool = false
    var completedAt: Date?
    var estimatedMinutes: Int?
    var scheduledBlockStart: Date?              // time-blocked onto the calendar
    var listName: String = "Inbox"
    var tags: [String] = []
    var sourceEmailId: String?                  // created from an email
    var sourceNoteId: UUID?                     // created from a note
    var ekReminderId: String?                   // mirrored to Apple Reminders
    var createdAt: Date = Date()
    var updatedAt: Date = Date()                // for two-way Reminders conflict resolution
    // ADHD support
    var energy: EnergyLevel = EnergyLevel.medium
    var microSteps: [MicroStep] = []
    var isWaitingOn: Bool = false               // "waiting for" someone else — out of sight, not out of mind
    var timesRescheduled: Int = 0               // AI offers to break down or drop tasks that keep slipping
    var actualMinutes: Int?                     // learns your real estimates (time blindness)
    var goalId: UUID?                           // the goal this task moves forward
    var feeling: TaskFeeling?                   // Feel-Good Productivity: how it felt to do
    // Location reminder (mirrors to Apple Reminders as a location alarm)
    var locationName: String?
    var latitude: Double?
    var longitude: Double?
    var remindOnArrive: Bool = true             // false = when leaving
    var stage: String = "todo"                  // board view: todo | doing | done
    var projectId: UUID?                        // project this task belongs to
    var isSomeday: Bool = false                 // parked for later, out of today's lists
    var fromParkingLot: Bool = false            // captured during focus, reviewed after
    // TickTick-style
    var recurrence: Recurrence?                 // repeating task; completing it moves it to the next date
    var alertOffsetMinutes: Int?                // nil = no Keel alert; 0 = at due time; 15 = 15 min before…
    var completionCount: Int = 0                // times a repeating task has been completed
    var lastCompletedOccurrence: Date?
    var isPinned: Bool = false                  // pinned to the top of Tasks and Today
    var blockedById: UUID?                      // can't start until this task is done
    var useAlarm: Bool?                         // full-screen alarm instead of a banner; nil = follow Settings

    /// True when the due date carries a time (not just a day).
    var hasDueTime: Bool {
        guard let d = dueDate else { return false }
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return !(c.hour == 0 && c.minute == 0)
    }

    init(title: String, dueDate: Date? = nil, priority: TaskPriority = .none) {
        self.title = title
        self.dueDate = dueDate
        self.priority = priority
    }
}

// MARK: - Notes (Notion-style blocks)

enum BlockKind: String, Codable {
    case text, heading, todo, bullet, quote, divider, emailEmbed, taskEmbed, image
    // Workspace blocks
    case heading2, heading3, numbered, toggle, callout, code, table, bookmark, page
}

struct NoteBlock: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: BlockKind
    var text: String                            // inline markdown: **bold**, *italic*, ==highlight==, `code`, [link](url)
    var checked: Bool = false
    var refId: String?                          // email / task / attachment / sub-page id, or a bookmark URL
    // Optional, so notes saved before these existed still load.
    var body: String?                           // toggle contents
    var collapsed: Bool?                        // toggle open/closed
    var icon: String?                           // callout emoji
    var lang: String?                           // code language
    var rows: [[String]]?                       // table cells, first row is the header
    var color: String?                          // gray | brown | red | orange | yellow | green | blue | purple | pink (+ "bg:" prefix for background)
    var indent: Int?                            // nesting level: 0 (or nil) is the left edge; children of lists and toggles are 1, 2…
}

/// A column in a notes database: Status, Due, Tags…
struct DBProperty: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable { case text, number, select, multiSelect, status, date, checkbox, url, person }
    var id: String = UUID().uuidString
    var name: String
    var kind: Kind
    var options: [String] = []
}

@Model final class Note {
    var id: UUID = UUID()
    var title: String
    var blocks: [NoteBlock] = []
    var parentId: UUID?                         // nested pages
    var linkedEventId: String?                  // meeting notes tied to a calendar event
    var isPinned: Bool = false
    var updatedAt: Date = Date()
    var aiSummary: String?
    var isTemplate: Bool = false                // a reusable note template, hidden from Notes
    var folder: String?                         // nil = no folder
    var isLocked: Bool = false                  // needs Face ID to open; hidden from search, Spotlight and AI
    // Workspace
    var icon: String?                           // page emoji
    @Attribute(.externalStorage) var cover: Data?
    var createdAt: Date = Date()
    var sortIndex: Double = 0                   // order among sibling pages
    // Databases: a database is a page whose child pages are its rows.
    var isDatabase: Bool = false
    var schema: [DBProperty] = []
    var dbView: String = "table"                // table | board | calendar | gallery | list
    var dbGroupBy: String?                      // property id for board columns
    var dbSortBy: String?                       // property id, or "title" / "created"
    var dbSortAscending: Bool = true
    var dbFilterProp: String?
    var dbFilterValue: String?
    var props: [String: String] = [:]           // this page's values when it's a database row

    init(title: String, blocks: [NoteBlock] = [NoteBlock(kind: .text, text: "")]) {
        self.title = title
        self.blocks = blocks
    }

    var plainText: String {
        blocks.map { b in
            [RichText.plain(b.text), b.body ?? "", (b.rows ?? []).map { $0.joined(separator: " ") }.joined(separator: "\n")]
                .filter { !$0.isEmpty }.joined(separator: "\n")
        }.joined(separator: "\n")
    }
}

// MARK: - Habits & habit stacking

@Model final class Habit {
    var id: UUID = UUID()
    var name: String
    var icon: String                            // SF Symbol
    var minutes: Int                            // tiny-habit duration
    var orderInStack: Int = 0
    var stackId: UUID?
    var currentStreak: Int = 0
    var bestStreak: Int = 0
    /// ADHD-friendly streaks: missing a day spends a grace token instead of resetting to 0.
    var graceTokens: Int = 2
    /// Count of all-time completions — never goes down, so a bad week doesn't erase progress.
    var totalCompletions: Int = 0
    /// Auto-complete from Apple Health, e.g. "steps:8000", "workout:20", "mindful:5" (minutes).
    var healthGoal: String?

    init(name: String, icon: String = "circle", minutes: Int = 2) {
        self.name = name
        self.icon = icon
        self.minutes = minutes
    }
}

/// "After I <anchor>, I will <habit 1> → <habit 2> → …" (James Clear habit stacking)
enum StackAnchor: Codable, Hashable {
    case time(hour: Int, minute: Int)
    case afterEvent(keyword: String)            // e.g. after a calendar event containing "standup"
    case afterFocusSession
    case afterInboxZero
    case location(name: String)                 // geofence, e.g. "Gym"
    case manual(label: String)                  // "After I pour my coffee"

    var label: String {
        switch self {
        case .time(let h, let m): String(format: "At %02d:%02d", h, m)
        case .afterEvent(let k): "After \"\(k)\" ends"
        case .afterFocusSession: "After a focus session"
        case .afterInboxZero: "After I hit inbox zero"
        case .location(let n): "When I arrive at \(n)"
        case .manual(let l): "After I \(l)"
        }
    }
}

@Model final class HabitStack {
    var id: UUID = UUID()
    var name: String
    var anchor: StackAnchor
    var weekdays: [Int] = [1, 2, 3, 4, 5, 6, 7]   // Calendar weekday numbers
    var isActive: Bool = true

    init(name: String, anchor: StackAnchor) {
        self.name = name
        self.anchor = anchor
    }
}

@Model final class HabitLog {
    var habitId: UUID
    var day: Date                                // start of day
    var completedAt: Date

    init(habitId: UUID, day: Date, completedAt: Date = Date()) {
        self.habitId = habitId
        self.day = day
        self.completedAt = completedAt
    }
}

// MARK: - Promise tracker

/// A commitment YOU made in an email you sent ("I'll send the deck Friday").
enum CommitmentStatus: String, Codable { case open, done, dismissed }

@Model final class Commitment {
    @Attribute(.unique) var id: String          // sent message id + index
    var accountId: String
    var sourceMessageId: String                 // provider id of the sent email
    var threadId: String
    var promise: String                         // "Send the Q3 deck"
    var quote: String                           // the exact sentence you wrote
    var recipient: String                       // address you promised
    var recipientName: String
    var subject: String
    var sentAt: Date
    var dueDate: Date?
    var status: CommitmentStatus = CommitmentStatus.open
    var taskId: UUID?                           // if turned into a task
    var completedAt: Date?
    var likelyKept: Bool = false                // a later reply in the thread looks like you delivered

    init(id: String, accountId: String, sourceMessageId: String, threadId: String, promise: String, quote: String,
         recipient: String, recipientName: String, subject: String, sentAt: Date, dueDate: Date?) {
        self.id = id; self.accountId = accountId; self.sourceMessageId = sourceMessageId; self.threadId = threadId
        self.promise = promise; self.quote = quote; self.recipient = recipient; self.recipientName = recipientName
        self.subject = subject; self.sentAt = sentAt; self.dueDate = dueDate
    }

    var isOverdue: Bool { status == .open && (dueDate.map { $0 < Calendar.current.startOfDay(for: Date()) } ?? false) }
    /// No date given: treat as owed within a week of sending (people remember "I'll get back to you").
    var effectiveDue: Date { dueDate ?? sentAt.addingTimeInterval(7 * 86_400) }
}

// MARK: - Goals & life areas (Ali Abdaal-style: yearly theme → goals per life area → tasks)

enum LifeArea: String, Codable, CaseIterable, Identifiable {
    case health, wealth, relationships, work, growth, fun
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .health: "heart.fill"; case .wealth: "banknote.fill"; case .relationships: "person.2.fill"
        case .work: "briefcase.fill"; case .growth: "leaf.fill"; case .fun: "gamecontroller.fill"
        }
    }
}

@Model final class Goal {
    var id: UUID = UUID()
    var title: String
    var area: LifeArea
    var why: String = ""                        // the reason it matters (shown when motivation dips)
    var targetDate: Date?
    var emoji: String = "🎯"
    var isArchived: Bool = false
    var createdAt: Date = Date()
    @Attribute(.externalStorage) var visionImage: Data?     // a picture of what achieving it looks like

    init(title: String, area: LifeArea) {
        self.title = title
        self.area = area
    }
}

/// Feel-Good Productivity energizers (Play, Power, People) and drainers.
enum TaskFeeling: String, Codable, CaseIterable, Identifiable {
    case play, power, people, drained
    var id: String { rawValue }
    var label: String {
        switch self { case .play: "Felt like play"; case .power: "Felt capable"; case .people: "Felt connected"; case .drained: "Drained me" }
    }
    var emoji: String { switch self { case .play: "🎈"; case .power: "💪"; case .people: "🤝"; case .drained: "🪫" } }
}

// MARK: - Read later

@Model final class SavedLink {
    var id: UUID = UUID()
    var url: String
    var title: String
    var summary: String?
    var siteName: String = ""
    var addedAt: Date = Date()
    var isRead: Bool = false
    var readAt: Date?
    var notes: String = ""

    init(url: String, title: String) {
        self.url = url
        self.title = title
    }
}

// MARK: - Time tracking & ideal week

@Model final class TimeEntry {
    var id: UUID = UUID()
    var title: String
    var area: LifeArea
    var start: Date
    var end: Date?                              // nil while the timer is running
    var source: String = "manual"               // manual | focus | calendar

    init(title: String, area: LifeArea, start: Date = Date(), end: Date? = nil) {
        self.title = title
        self.area = area
        self.start = start
        self.end = end
    }

    var minutes: Int { Int(((end ?? Date()).timeIntervalSince(start)) / 60) }
}

/// One block of your ideal week (e.g. Mon–Fri 9:00–11:30 Deep work, Work).
@Model final class IdealBlock {
    var id: UUID = UUID()
    var title: String
    var area: LifeArea
    var weekdays: [Int]                         // 1 = Sunday … 7 = Saturday
    var startMinute: Int                        // minutes after midnight
    var endMinute: Int

    init(title: String, area: LifeArea, weekdays: [Int], startMinute: Int, endMinute: Int) {
        self.title = title
        self.area = area
        self.weekdays = weekdays
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    var minutes: Int { max(0, endMinute - startMinute) }
    var timeLabel: String {
        func f(_ m: Int) -> String { String(format: "%d:%02d", m / 60, m % 60) }
        return "\(f(startMinute))–\(f(endMinute))"
    }
}

// MARK: - Odyssey plan (Designing Your Life: three different 5-year futures)

enum OdysseyKind: String, Codable, CaseIterable, Identifiable {
    case current, alternative, wildcard
    var id: String { rawValue }
    var title: String {
        switch self { case .current: "Life as planned"; case .alternative: "Plan B"; case .wildcard: "Wild card" }
    }
    var prompt: String {
        switch self {
        case .current: "Where your current path leads if things go well."
        case .alternative: "If your current path disappeared tomorrow, what would you do?"
        case .wildcard: "If money and what people think didn't matter, what would you do?"
        }
    }
}

@Model final class OdysseyPath {
    var id: UUID = UUID()
    var kind: OdysseyKind
    var title: String = ""
    var years: [String] = ["", "", "", "", ""]  // one line per year
    var questions: String = ""                  // questions this path raises
    var resources: Int = 3                      // 1…5 ratings
    var likability: Int = 3
    var confidence: Int = 3
    var coherence: Int = 3

    init(kind: OdysseyKind) { self.kind = kind }
}

// MARK: - Screener (approve first-time senders)

@Model final class SenderRule {
    @Attribute(.unique) var address: String     // lowercased email address
    var allowed: Bool
    var name: String = ""
    var decidedAt: Date = Date()

    init(address: String, allowed: Bool, name: String = "") {
        self.address = address.lowercased()
        self.allowed = allowed
        self.name = name
    }
}

// MARK: - Keep in touch

@Model final class Person {
    var id: UUID = UUID()
    var name: String
    var email: String = ""
    var phone: String = ""
    var cadenceDays: Int = 14                   // how often you want to be in touch
    var lastContact: Date?
    var notes: String = ""
    var createdAt: Date = Date()

    init(name: String) { self.name = name }

    var nextDue: Date { (lastContact ?? createdAt).addingTimeInterval(Double(cadenceDays) * 86_400) }
    var isDue: Bool { nextDue <= Date() }
}

// MARK: - Daily check-in

@Model final class CheckIn {
    var id: UUID = UUID()
    var day: Date                               // start of day
    var mood: Int                               // 1…5
    var highlight: String = ""
    var gratitude: String = ""
    var energy: Int?                            // 1…3, captured with the check-in
    var sleepHours: Double?
    var createdAt: Date = Date()
    var journal: String = ""                    // the 1-minute evening journal
    var prompt: String = ""                     // the question it answered

    init(day: Date, mood: Int) {
        self.day = day
        self.mood = mood
    }

    static let faces = ["😞", "😕", "😐", "🙂", "😄"]
}

// MARK: - Note attachments (photos, sketches, scans)

@Model final class NoteAttachment {
    var id: UUID = UUID()
    var noteId: UUID
    @Attribute(.externalStorage) var data: Data
    var kind: String                            // photo | sketch | scan
    var recognizedText: String = ""             // OCR from scans, so they're searchable
    var createdAt: Date = Date()

    init(noteId: UUID, data: Data, kind: String) {
        self.noteId = noteId
        self.data = data
        self.kind = kind
    }
}

// MARK: - Countdowns

@Model final class Countdown {
    var id: UUID = UUID()
    var title: String
    var date: Date
    var emoji: String = "🎉"
    var createdAt: Date = Date()

    init(title: String, date: Date) {
        self.title = title
        self.date = date
    }

    var daysLeft: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0
    }
}

// MARK: - Projects

@Model final class Project {
    var id: UUID = UUID()
    var name: String
    var emoji: String = "📁"
    var area: LifeArea = LifeArea.work
    var goalId: UUID?
    var deadline: Date?
    var notes: String = ""
    var milestones: [String] = []               // ordered milestone names; tasks can be tagged with one
    var isArchived: Bool = false
    var createdAt: Date = Date()

    init(name: String) { self.name = name }
}

// MARK: - Email snippets

@Model final class Snippet {
    var id: UUID = UUID()
    var name: String
    var body: String
    var uses: Int = 0

    init(name: String, body: String) {
        self.name = name
        self.body = body
    }
}

// MARK: - Smart email rules

@Model final class MailRule {
    var id: UUID = UUID()
    var field: String                           // from | subject | any
    var contains: String                        // case-insensitive match
    var action: String                          // archive | star | read | category:<name> | task
    var isOn: Bool = true
    var timesApplied: Int = 0
    var createdAt: Date = Date()

    init(field: String, contains: String, action: String) {
        self.field = field
        self.contains = contains
        self.action = action
    }
}

// MARK: - Templates

@Model final class TaskTemplate {
    var id: UUID = UUID()
    var name: String
    var icon: String = "doc.on.doc"
    var items: [String] = []                    // one task per line; quick-add syntax works (e.g. "Pack charger !high")
    var listName: String = ""                   // empty = default list
    var createdAt: Date = Date()

    init(name: String, items: [String] = []) {
        self.name = name
        self.items = items
    }
}

// MARK: - Follow-ups ("remind me if no reply")

@Model final class FollowUp {
    var id: UUID = UUID()
    var accountId: String
    var recipient: String
    var recipientName: String
    var subject: String
    var sentAt: Date
    var remindAt: Date
    var resolvedAt: Date?                       // set when they reply (or you dismiss it)

    init(accountId: String, recipient: String, recipientName: String, subject: String, sentAt: Date, remindAt: Date) {
        self.accountId = accountId
        self.recipient = recipient
        self.recipientName = recipientName
        self.subject = subject
        self.sentAt = sentAt
        self.remindAt = remindAt
    }

    var isDue: Bool { resolvedAt == nil && remindAt <= Date() }
}

// MARK: - Focus / Shutdown

@Model final class FocusSession {
    var id: UUID = UUID()
    var startedAt: Date
    var plannedMinutes: Int
    var endedAt: Date?
    var taskId: UUID?
    var mode: String                             // "deep", "shutdown"
    var interruptionsBlocked: Int = 0
    var brokeEarly: Bool = false

    init(plannedMinutes: Int, mode: String, taskId: UUID? = nil) {
        self.startedAt = Date()
        self.plannedMinutes = plannedMinutes
        self.mode = mode
        self.taskId = taskId
    }
}

// MARK: - Send later

/// An email waiting to be sent at `sendAt`. Sent by Keel's sync (foreground or background refresh).
@Model final class ScheduledMail {
    var id: UUID = UUID()
    var accountId: String
    var to: [String]
    var cc: [String] = []
    var bcc: [String] = []
    var subject: String
    var body: String
    var replyProviderId: String?
    var replyThreadId: String?
    var replyMessageIdHeader: String?
    var replyAll: Bool = false
    var attachmentsJSON: Data?                  // [StoredAttachment]
    var sendAt: Date
    var lastError: String?
    var createdAt: Date = Date()

    init(accountId: String, to: [String], subject: String, body: String, sendAt: Date) {
        self.accountId = accountId
        self.to = to
        self.subject = subject
        self.body = body
        self.sendAt = sendAt
    }
}

struct StoredAttachment: Codable {
    var filename: String
    var mimeType: String
    var data: Data
}

// MARK: - Medications

@Model final class Medication {
    var id: UUID = UUID()
    var name: String
    var dose: String = ""                       // "20 mg"
    var times: [Int] = [480]                    // minutes after midnight, e.g. 8:00 = 480
    var remind: Bool = true
    var isActive: Bool = true
    var pillsLeft: Int?                         // optional refill tracking
    var refillAt: Int = 7                       // warn when this many are left
    var createdAt: Date = Date()

    init(name: String, dose: String = "", times: [Int] = [480]) {
        self.name = name
        self.dose = dose
        self.times = times
    }
}

@Model final class MedDose {
    var id: UUID = UUID()
    var medicationId: UUID
    var slot: Int                               // which scheduled time (minutes after midnight)
    var day: Date                               // start of day
    var takenAt: Date = Date()

    init(medicationId: UUID, slot: Int, day: Date) {
        self.medicationId = medicationId
        self.slot = slot
        self.day = day
    }
}

// MARK: - Found in email: subscriptions, bills and deliveries

@Model final class Subscription {
    var id: UUID = UUID()
    var name: String                            // merchant, e.g. "Netflix"
    var key: String                             // lowercased name, for de-duplication
    var amount: Double
    var currency: String = "$"
    var period: String = "monthly"              // monthly | yearly | weekly | once (bills)
    var kind: String = "subscription"           // subscription | bill
    var lastCharged: Date
    var nextDate: Date?                         // renewal or due date
    var sourceEmailId: String?
    var isHidden: Bool = false                  // "not a subscription"
    var remind: Bool = true

    init(name: String, amount: Double, lastCharged: Date) {
        self.name = name
        self.key = name.lowercased()
        self.amount = amount
        self.lastCharged = lastCharged
    }

    var monthlyCost: Double {
        switch period { case "yearly": amount / 12; case "weekly": amount * 52 / 12; case "once": 0; default: amount }
    }
}

@Model final class Delivery {
    var id: UUID = UUID()
    var carrier: String                         // UPS | USPS | FedEx | DHL | Amazon
    var tracking: String                        // tracking or order number
    var title: String                           // what's coming, from the subject
    var status: String = "shipped"              // ordered | shipped | out | delivered
    var expected: Date?
    var sourceEmailId: String?
    var updatedAt: Date = Date()
    var isArchived: Bool = false

    init(carrier: String, tracking: String, title: String) {
        self.carrier = carrier
        self.tracking = tracking
        self.title = title
    }

    var trackURL: URL? {
        let n = tracking.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tracking
        switch carrier {
        case "UPS": return URL(string: "https://www.ups.com/track?tracknum=\(n)")
        case "USPS": return URL(string: "https://tools.usps.com/go/TrackConfirmAction?tLabels=\(n)")
        case "FedEx": return URL(string: "https://www.fedex.com/fedextrack/?trknbr=\(n)")
        case "DHL": return URL(string: "https://www.dhl.com/global-en/home/tracking.html?tracking-id=\(n)")
        default: return nil
        }
    }
}

// MARK: - Trips (reservations found in email)

@Model final class Reservation {
    var id: UUID = UUID()
    var kind: String                            // flight | hotel | car | train | event | restaurant
    var title: String                           // "UA 1234 SFO → JFK", "Hilton Midtown"
    var confirmation: String = ""
    var start: Date
    var end: Date?
    var location: String = ""
    var detail: String = ""                     // seat, terminal, address…
    var sourceEmailId: String?
    var calendarEventId: String?                // set once added to Calendar
    var isHidden: Bool = false
    var createdAt: Date = Date()

    init(kind: String, title: String, start: Date) {
        self.kind = kind
        self.title = title
        self.start = start
    }

    var icon: String {
        switch kind {
        case "flight": "airplane"; case "hotel": "bed.double.fill"; case "car": "car.fill"
        case "train": "tram.fill"; case "restaurant": "fork.knife"; default: "ticket.fill"
        }
    }
}

@Model final class TaskAttachment {
    var id: UUID = UUID()
    var taskId: UUID
    @Attribute(.externalStorage) var data: Data
    var filename: String
    var kind: String                            // photo | file
    var createdAt: Date = Date()

    init(taskId: UUID, data: Data, filename: String, kind: String) {
        self.taskId = taskId
        self.data = data
        self.filename = filename
        self.kind = kind
    }
}

// MARK: - Smart lists (saved task filters)

@Model final class SmartList {
    var id: UUID = UUID()
    var name: String
    var icon: String = "line.3.horizontal.decrease.circle"
    var priorities: [Int] = []                  // TaskPriority raw values; empty = any
    var tags: [String] = []                     // any of these; empty = any
    var lists: [String] = []                    // any of these; empty = any
    var dueWithinDays: Int?                     // nil = any date; 0 = today (incl. overdue)
    var includeNoDate: Bool = true
    var energy: Int?                            // EnergyLevel raw value
    var createdAt: Date = Date()

    init(name: String) { self.name = name }

    func matches(_ t: TaskItem, now: Date = Date()) -> Bool {
        guard !t.isDone, !t.isSomeday else { return false }
        if !priorities.isEmpty && !priorities.contains(t.priority.rawValue) { return false }
        if !tags.isEmpty && !t.tags.contains(where: tags.contains) { return false }
        if !lists.isEmpty && !lists.contains(t.listName) { return false }
        if let e = energy, t.energy.rawValue != e { return false }
        if let days = dueWithinDays {
            guard let due = t.dueDate else { return includeNoDate }
            let end = Calendar.current.date(byAdding: .day, value: days + 1, to: Calendar.current.startOfDay(for: now))!
            return due < end
        }
        return t.dueDate != nil || includeNoDate
    }
}

// MARK: - Autopilot

/// Something Keel prepared for you to approve with one tap.
@Model final class Suggestion {
    var id: UUID = UUID()
    var key: String                             // de-duplication, e.g. "reply:<email id>"
    var kind: String                            // reply | declutter | overload | focus | stale | promise | bill | prep | followup
    var title: String
    var detail: String
    var acceptLabel: String
    var refId: String?                          // email / task / event id
    var payload: String = ""                    // draft text, id list or ISO date, depending on kind
    var status: String = "pending"              // pending | accepted | dismissed
    var createdAt: Date = Date()

    init(key: String, kind: String, title: String, detail: String, acceptLabel: String) {
        self.key = key
        self.kind = kind
        self.title = title
        self.detail = detail
        self.acceptLabel = acceptLabel
    }

    var icon: String {
        switch kind {
        case "reply": "arrowshape.turn.up.left.fill"; case "declutter": "tray.and.arrow.down.fill"
        case "overload": "scalemass.fill"; case "focus": "moon.zzz.fill"; case "stale": "arrow.triangle.2.circlepath"
        case "promise": "hand.raised.fill"; case "bill": "creditcard.fill"; case "prep": "doc.text.magnifyingglass"
        case "followup": "bubble.left.and.exclamationmark.bubble.right.fill"; default: "sparkles"
        }
    }
}

// MARK: - Inbox learning

/// What Keel has learned about a sender from how you treat their mail.
@Model final class SenderScore {
    var sender: String = ""                     // lowercased address
    var name: String = ""
    var opens: Int = 0
    var replies: Int = 0
    var ignored: Int = 0                        // archived without reading
    var isVIP: Bool = false
    var updatedAt: Date = Date()

    init(sender: String, name: String = "") {
        self.sender = sender
        self.name = name
    }

    /// Positive = you engage, negative = you ignore.
    var affinity: Double {
        Double(replies) * 3 + Double(opens) - Double(ignored) * 2
    }
}
