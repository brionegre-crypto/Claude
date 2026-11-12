import Foundation
import FoundationModels

/// Natural-language search: "emails from sarah last week about invoice", "overdue tasks", "notes this month".
/// A fast local parser runs as you type; pressing Search refines it with Apple Intelligence when available.
struct SmartQuery: Equatable {
    var kinds: Set<String> = []          // task | note | email | event
    var words: [String] = []             // remaining keywords (all must match)
    var from: String?
    var range: DateInterval?
    var rangeLabel: String?
    var flags: Set<String> = []          // overdue | done | open | unread | starred | attachments

    var isStructured: Bool { !kinds.isEmpty || from != nil || range != nil || !flags.isEmpty }
    func allows(_ kind: String) -> Bool { kinds.isEmpty || kinds.contains(kind) }
    func inRange(_ d: Date?) -> Bool { range.map { r in d.map { r.contains($0) } ?? false } ?? true }
    func matches(_ fields: String...) -> Bool {
        guard !words.isEmpty else { return true }
        let hay = fields.joined(separator: " ").lowercased()
        return words.allSatisfy { hay.contains($0) }
    }

    /// Chips shown under the search bar, e.g. ["Email", "from sarah", "Last week"].
    var chips: [String] {
        var c = kinds.sorted().map { $0.capitalized }
        if let f = from { c.append("from \(f)") }
        if let r = rangeLabel { c.append(r) }
        c += flags.sorted().map { $0.capitalized }
        return c
    }
}

enum SmartQueryParser {
    private static let kindWords: [String: String] = [
        "email": "email", "emails": "email", "mail": "email", "message": "email", "messages": "email",
        "task": "task", "tasks": "task", "todo": "task", "todos": "task", "reminder": "task", "reminders": "task",
        "note": "note", "notes": "note",
        "event": "event", "events": "event", "meeting": "event", "meetings": "event",
    ]
    private static let flagWords: [String: String] = [
        "overdue": "overdue", "late": "overdue", "done": "done", "completed": "done", "finished": "done",
        "open": "open", "unfinished": "open", "unread": "unread", "starred": "starred", "flagged": "starred",
        "attachment": "attachments", "attachments": "attachments",
    ]
    private static let stop: Set<String> = ["about", "with", "in", "the", "my", "show", "find", "all", "me", "and", "a", "an",
                                            "of", "for", "on", "to", "any", "that", "what", "were", "was", "i", "have", "had"]

    static func parse(_ raw: String, now: Date = Date()) -> SmartQuery {
        var q = SmartQuery()
        var text = " " + raw.lowercased() + " "
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today)! }
        let week = cal.dateInterval(of: .weekOfYear, for: now)!
        let month = cal.dateInterval(of: .month, for: now)!
        let phrases: [(String, DateInterval, String)] = [
            ("last week", DateInterval(start: cal.date(byAdding: .day, value: -7, to: week.start)!, end: week.start), "Last week"),
            ("this week", week, "This week"),
            ("next week", DateInterval(start: week.end, end: cal.date(byAdding: .day, value: 7, to: week.end)!), "Next week"),
            ("last month", DateInterval(start: cal.date(byAdding: .month, value: -1, to: month.start)!, end: month.start), "Last month"),
            ("this month", month, "This month"),
            ("yesterday", DateInterval(start: day(-1), end: today), "Yesterday"),
            ("today", DateInterval(start: today, end: day(1)), "Today"),
            ("tomorrow", DateInterval(start: day(1), end: day(2)), "Tomorrow"),
        ]
        for (p, r, label) in phrases where text.contains(" \(p) ") {
            q.range = r; q.rangeLabel = label
            text = text.replacingOccurrences(of: " \(p) ", with: " ")
            break
        }
        var tokens = text.split(separator: " ").map(String.init)
        if let i = tokens.firstIndex(of: "from"), i + 1 < tokens.count {
            q.from = tokens[i + 1]
            q.kinds.insert("email")
            tokens.removeSubrange(i...(i + 1))
        }
        for t in tokens {
            if let k = kindWords[t] { q.kinds.insert(k) }
            else if let f = flagWords[t] { q.flags.insert(f) }
            else if !stop.contains(t), t.count > 1 { q.words.append(t) }
        }
        return q
    }

    // MARK: Apple Intelligence refinement

    @Generable
    struct Parsed {
        @Guide(description: "Which kinds of items to search: any of task, note, email, event. Empty for all.")
        var kinds: [String]
        @Guide(description: "Topic keywords to match, lowercase, without filler words or dates")
        var keywords: [String]
        @Guide(description: "Sender name or address if the user wants email from someone, otherwise empty")
        var from: String
        @Guide(description: "Start date YYYY-MM-DD if a time range is stated, otherwise empty")
        var startDate: String
        @Guide(description: "End date YYYY-MM-DD (exclusive) if a time range is stated, otherwise empty")
        var endDate: String
        @Guide(description: "Any of: overdue, done, open, unread, starred, attachments")
        var flags: [String]
    }

    @MainActor
    static func refine(_ raw: String) async -> SmartQuery? {
        guard AIRouter.shared.onDeviceAvailable else { return nil }
        let session = LanguageModelSession(instructions: "Turn a search request for a personal productivity app into filters. Today is \(Date().formatted(.iso8601.year().month().day())), \(Date().formatted(.dateTime.weekday(.wide))).")
        guard let p = try? await session.respond(to: raw, generating: Parsed.self).content else { return nil }
        var q = SmartQuery()
        q.kinds = Set(p.kinds.map { $0.lowercased() }.filter { ["task", "note", "email", "event"].contains($0) })
        q.words = p.keywords.map { $0.lowercased() }.filter { !$0.isEmpty }
        q.from = p.from.isEmpty ? nil : p.from.lowercased()
        if q.from != nil { q.kinds.insert("email") }
        let f = ISO8601DateFormatter.dateOnly
        if let s = f.date(from: p.startDate) {
            let e = f.date(from: p.endDate) ?? Calendar.current.date(byAdding: .day, value: 1, to: s)!
            q.range = DateInterval(start: s, end: max(s, e))
            q.rangeLabel = "\(s.formatted(.dateTime.month(.abbreviated).day())) – \(e.formatted(.dateTime.month(.abbreviated).day()))"
        }
        q.flags = Set(p.flags.map { $0.lowercased() }.filter { ["overdue", "done", "open", "unread", "starred", "attachments"].contains($0) })
        return q
    }
}
