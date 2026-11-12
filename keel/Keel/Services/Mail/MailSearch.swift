import Foundation

/// Search operators for mail, typed straight into the Inbox search bar:
///   from:sam  to:alex  subject:invoice  has:attachment  is:unread  is:starred  is:pinned  is:vip  is:read
///   before:2026-11-01  after:friday  newer_than:7d  older_than:2w  in:archive  category:newsletters
///   "exact phrase"   -word (exclude)   plain words (all must match)
/// Anything that isn't an operator is treated as plain text, so ordinary searches work the same as before.
struct MailQuery: Equatable {
    var words: [String] = []
    var phrases: [String] = []
    var excluded: [String] = []
    var from: [String] = []
    var to: [String] = []
    var subject: [String] = []
    var flags: Set<String> = []            // attachment unread read starred pinned vip
    var after: Date?
    var before: Date?
    var category: TriageCategory?
    var inArchive: Bool?                    // nil = wherever you're looking

    /// True when the text used at least one operator (so Inbox shows the chips).
    var hasOperators: Bool {
        !from.isEmpty || !to.isEmpty || !subject.isEmpty || !flags.isEmpty || after != nil || before != nil
            || category != nil || inArchive != nil || !excluded.isEmpty || !phrases.isEmpty
    }

    var chips: [String] {
        var c: [String] = []
        c += from.map { "From \($0)" }
        c += to.map { "To \($0)" }
        c += subject.map { "Subject “\($0)”" }
        c += flags.sorted().map { $0 == "attachment" ? "Has attachment" : $0 == "vip" ? "VIP" : $0.capitalized }
        if let a = after { c.append("After \(a.formatted(.dateTime.month(.abbreviated).day()))") }
        if let b = before { c.append("Before \(b.formatted(.dateTime.month(.abbreviated).day()))") }
        if let k = category { c.append(k.rawValue.capitalized) }
        if inArchive == true { c.append("Archive") }
        c += phrases.map { "“\($0)”" }
        c += excluded.map { "Not “\($0)”" }
        return c
    }

    func matches(_ e: EmailMessage, isVIP: Bool = false) -> Bool {
        let sender = (e.fromName + " " + e.from).lowercased()
        if !from.allSatisfy({ sender.contains($0) }) { return false }
        let rcpt = (e.toLine + " " + e.ccLine).lowercased()
        if !to.allSatisfy({ rcpt.contains($0) }) { return false }
        let subj = e.subject.lowercased()
        if !subject.allSatisfy({ subj.contains($0) }) { return false }
        if flags.contains("attachment") && !e.hasAttachments { return false }
        if flags.contains("unread") && e.isRead { return false }
        if flags.contains("read") && !e.isRead { return false }
        if flags.contains("starred") && !e.isStarred { return false }
        if flags.contains("pinned") && !e.isPinned { return false }
        if flags.contains("vip") && !isVIP { return false }
        if let a = after, e.receivedAt < a { return false }
        if let b = before, e.receivedAt >= b { return false }
        if let k = category, e.category != k { return false }
        if let arch = inArchive, e.isArchived != arch { return false }
        if words.isEmpty && phrases.isEmpty && excluded.isEmpty { return true }
        let hay = [e.subject, e.fromName, e.from, e.snippet, e.bodyPlain, e.toLine].joined(separator: " ").lowercased()
        return words.allSatisfy { hay.contains($0) }
            && phrases.allSatisfy { hay.contains($0) }
            && !excluded.contains { hay.contains($0) }
    }

    /// Plain text for providers that don't understand operators (Outlook, IMAP).
    var serverText: String { (phrases + words + subject + from).joined(separator: " ") }
}

enum MailQueryParser {
    static let help: [(String, String)] = [
        ("from:sam", "Mail from someone (name or address)"),
        ("to:alex", "Mail you sent or copied to someone"),
        ("subject:invoice", "Word in the subject"),
        ("has:attachment", "Only mail with attachments"),
        ("is:unread", "Also is:read, is:starred, is:pinned, is:vip"),
        ("after:2026-11-01", "Also before:, or a word like friday, yesterday"),
        ("newer_than:7d", "Also older_than:, with d, w, m or y"),
        ("in:archive", "Search archived mail"),
        ("category:newsletters", "important, updates, promotions…"),
        ("\"exact phrase\"", "Words in this order"),
        ("-word", "Leave out mail containing a word"),
    ]

    static func parse(_ raw: String, now: Date = Date()) -> MailQuery {
        var q = MailQuery()
        for token in tokenize(raw) {
            let t = token.lowercased()
            if token.hasPrefix("\"") {
                let p = t.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if !p.isEmpty { q.phrases.append(p) }
                continue
            }
            if t.hasPrefix("-"), t.count > 1 { q.excluded.append(String(t.dropFirst())); continue }
            guard let colon = t.firstIndex(of: ":"), colon != t.startIndex else {
                if !t.isEmpty { q.words.append(t) }
                continue
            }
            let key = String(t[..<colon])
            let value = String(t[t.index(after: colon)...]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard !value.isEmpty else { continue }
            switch key {
            case "from": q.from.append(value)
            case "to", "cc": q.to.append(value)
            case "subject": q.subject.append(value)
            case "has" where value.hasPrefix("attach"): q.flags.insert("attachment")
            case "is":
                let map = ["unread": "unread", "read": "read", "starred": "starred", "flagged": "starred",
                           "pinned": "pinned", "vip": "vip", "important": "vip"]
                if let f = map[value] { q.flags.insert(f) } else { q.words.append(t) }
            case "after", "since": q.after = date(value, now: now)
            case "before", "until": q.before = date(value, now: now)
            case "newer_than", "newer": q.after = relative(value, now: now)
            case "older_than", "older": q.before = relative(value, now: now)
            case "in":
                if value.hasPrefix("arch") || value == "all" { q.inArchive = value == "all" ? nil : true }
                else if value == "inbox" { q.inArchive = false }
            case "category", "label":
                q.category = TriageCategory.allCases.first { $0.rawValue.lowercased().hasPrefix(value) }
            default:
                q.words.append(t)       // a URL or a time like 10:30: plain text
            }
        }
        return q
    }

    /// Splits on spaces but keeps "quoted phrases" and from:"Sam Lee" together.
    static func tokenize(_ s: String) -> [String] {
        var out: [String] = [], cur = "", quoted = false
        for ch in s {
            if ch == "\"" { quoted.toggle(); cur.append(ch); continue }
            if ch == " " && !quoted {
                if !cur.isEmpty { out.append(cur) }
                cur = ""
            } else { cur.append(ch) }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    static func date(_ v: String, now: Date) -> Date? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        switch v {
        case "today": return today
        case "yesterday": return cal.date(byAdding: .day, value: -1, to: today)
        case "tomorrow": return cal.date(byAdding: .day, value: 1, to: today)
        default: break
        }
        let days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        if let i = days.firstIndex(where: { $0.hasPrefix(v) && v.count >= 3 }) {
            // The most recent such weekday (search looks backwards).
            let todayW = cal.component(.weekday, from: today) - 1
            var back = (todayW - i + 7) % 7
            if back == 0 { back = 7 }
            return cal.date(byAdding: .day, value: -back, to: today)
        }
        for f in ["yyyy-MM-dd", "yyyy/MM/dd", "M/d/yyyy", "M/d/yy", "M/d"] {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = f
            if var d = df.date(from: v) {
                if f == "M/d" {      // no year: this year, or last year if that's in the future
                    var c = cal.dateComponents([.month, .day], from: d)
                    c.year = cal.component(.year, from: now)
                    d = cal.date(from: c) ?? d
                    if d > now { d = cal.date(byAdding: .year, value: -1, to: d) ?? d }
                }
                return cal.startOfDay(for: d)
            }
        }
        return nil
    }

    static func relative(_ v: String, now: Date) -> Date? {
        guard let unit = v.last, let n = Int(v.dropLast()), n > 0 else { return nil }
        let cal = Calendar.current
        switch unit {
        case "h": return now.addingTimeInterval(-Double(n) * 3600)
        case "d": return cal.date(byAdding: .day, value: -n, to: now)
        case "w": return cal.date(byAdding: .day, value: -7 * n, to: now)
        case "m": return cal.date(byAdding: .month, value: -n, to: now)
        case "y": return cal.date(byAdding: .year, value: -n, to: now)
        default: return nil
        }
    }
}
