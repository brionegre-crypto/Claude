import Foundation
import SwiftData
import UserNotifications

/// The smart parts of Inbox: tabs, learning from how you treat senders, VIPs, quick-win estimates,
/// batched delivery and which mail deserves a notification.
enum InboxTab: String, CaseIterable, Identifiable {
    case priority, updates, newsletters, quick
    var id: String { rawValue }
    var title: String { switch self { case .priority: "Priority"; case .updates: "Updates"; case .newsletters: "Newsletters"; case .quick: "Quick wins" } }
    var icon: String { switch self { case .priority: "person.fill"; case .updates: "bell"; case .newsletters: "newspaper"; case .quick: "bolt.fill" } }
}

@MainActor
enum InboxBrain {
    // MARK: Learning

    enum Signal { case open, reply, ignored }

    static func record(_ signal: Signal, sender raw: String, name: String = "", ctx: ModelContext) {
        let sender = raw.lowercased().trimmingCharacters(in: .whitespaces)
        guard !sender.isEmpty else { return }
        let s = findOrCreate(sender, name: name, ctx: ctx)
        switch signal {
        case .open: s.opens += 1
        case .reply: s.replies += 1
        case .ignored: s.ignored += 1
        }
        if s.name.isEmpty { s.name = name }
        s.updatedAt = Date()
    }

    static func setVIP(_ on: Bool, sender raw: String, name: String, ctx: ModelContext) {
        let sender = raw.lowercased().trimmingCharacters(in: .whitespaces)
        guard !sender.isEmpty else { return }
        let s = findOrCreate(sender, name: name, ctx: ctx)
        s.isVIP = on
        s.updatedAt = Date()
    }

    private static func findOrCreate(_ sender: String, name: String, ctx: ModelContext) -> SenderScore {
        if let existing = try? ctx.fetch(FetchDescriptor<SenderScore>(predicate: #Predicate { $0.sender == sender })).first {
            return existing
        }
        let n = SenderScore(sender: sender, name: name)
        ctx.insert(n)
        return n
    }

    static func scores(_ ctx: ModelContext) -> [String: SenderScore] {
        Dictionary(((try? ctx.fetch(FetchDescriptor<SenderScore>())) ?? []).map { ($0.sender, $0) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: Tabs

    /// Which tab an email belongs in, using AI sorting corrected by what Keel has learned.
    static func tab(_ e: EmailMessage, score: SenderScore?) -> InboxTab {
        if score?.isVIP == true { return .priority }
        if let s = score, s.replies >= 1 { return .priority }                       // you've written back: they matter
        if MailNoise.needsAttention(e) { return .priority }                           // payment failed, security alert, action required
        let subj = e.subject.lowercased()
        if (subj.hasPrefix("re:") || subj.hasPrefix("re :")) && !MailNoise.isAutomated(e) { return .priority }   // a real reply in a conversation
        switch e.category ?? .important {
        case .newsletters, .promotions: return .newsletters
        case .updates, .lowPriority: return .updates
        default:
            if MailNoise.isAutomated(e) { return e.unsubscribeHeader != nil ? .newsletters : .updates }
            if let s = score, s.ignored >= 3, s.opens == 0, s.replies == 0 { return .updates }   // you never read them
            return .priority
        }
    }

    /// Minutes a reply probably takes: short notes with a clear ask are 2-minute wins.
    static func replyMinutes(_ e: EmailMessage) -> Int {
        if e.category == .calendar { return 1 }
        let body = GmailProvider.stripQuotedReply(e.bodyPlain)
        let words = body.split(whereSeparator: { $0.isWhitespace }).count
        let questions = body.filter { $0 == "?" }.count
        switch (words, questions) {
        case (..<80, ...1): return 2
        case (..<200, ...2): return 5
        default: return words < 500 ? 10 : 20
        }
    }

    static func isQuickWin(_ e: EmailMessage, score: SenderScore?) -> Bool {
        !e.isArchived && tab(e, score: score) == .priority && replyMinutes(e) <= 2 && !MailNoise.isAutomated(e)
    }

    /// Urgent: VIP, or a person with a deadline today/tomorrow, or very high priority.
    static func isUrgent(_ e: EmailMessage, score: SenderScore?) -> Bool {
        if score?.isVIP == true { return true }
        guard tab(e, score: score) == .priority else { return false }
        if let due = e.extractedDueDate, due < Date().addingTimeInterval(36 * 3600) { return true }
        return e.priorityScore >= 0.8
    }

    // MARK: Batched delivery

    static let batchOnKey = "batch.on", batchTimesKey = "batch.times", batchRevealKey = "batch.revealed"
    static var batchingOn: Bool { UserDefaults.standard.bool(forKey: batchOnKey) }
    /// Minutes after midnight, e.g. [540, 780, 1020] = 9:00, 1:00, 5:00.
    static var batchTimes: [Int] {
        let raw = UserDefaults.standard.string(forKey: batchTimesKey) ?? "540,780,1020"
        let t = raw.split(separator: ",").compactMap { Int($0) }.sorted()
        return t.isEmpty ? [540, 780, 1020] : t
    }

    /// The most recent delivery time at or before `now`.
    static func lastDelivery(_ now: Date = Date()) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let past = batchTimes.compactMap { cal.date(byAdding: .minute, value: $0, to: today) }.filter { $0 <= now }
        if let last = past.last { return last }
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        return cal.date(byAdding: .minute, value: batchTimes.last ?? 1020, to: yesterday) ?? today
    }

    static func nextDelivery(_ now: Date = Date()) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        if let next = batchTimes.compactMap({ cal.date(byAdding: .minute, value: $0, to: today) }).first(where: { $0 > now }) { return next }
        return cal.date(byAdding: .minute, value: batchTimes.first ?? 540, to: cal.date(byAdding: .day, value: 1, to: today)!) ?? now
    }

    /// Held until the next delivery: non-urgent mail that arrived after the last one (unless you tapped "Show now").
    static func isHeld(_ e: EmailMessage, score: SenderScore?) -> Bool {
        guard batchingOn, !e.isPinned, !isUrgent(e, score: score) else { return false }
        let revealed = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: batchRevealKey))
        return e.receivedAt > max(lastDelivery(), revealed)
    }

    static func revealNow() { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: batchRevealKey) }

    // MARK: Smart notifications

    static let notifyKey = "mail.notify"                 // off | vip | urgent (default)
    static var notifyMode: String { UserDefaults.standard.string(forKey: notifyKey) ?? "urgent" }

    /// After sync: one notification per new VIP / urgent email. Never for newsletters, promos or automated mail.
    static func notify(_ fresh: [EmailMessage], ctx: ModelContext) async {
        guard notifyMode != "off", !fresh.isEmpty else { return }
        let known = scores(ctx)
        var order = UserDefaults.standard.stringArray(forKey: "mail.notified") ?? []      // oldest first
        var sent = Set(order)
        let center = UNUserNotificationCenter.current()
        for e in fresh where !e.isRead && !e.isArchived && e.receivedAt > Date().addingTimeInterval(-3 * 3600) && !sent.contains(e.id) {
            let score = known[e.from.lowercased()]
            let vip = score?.isVIP == true
            guard vip || (notifyMode == "urgent" && isUrgent(e, score: score)) else { continue }
            let c = UNMutableNotificationContent()
            c.title = (vip ? "⭐️ " : "") + (e.fromName.isEmpty ? e.from : e.fromName)
            c.subtitle = e.subject
            c.body = e.aiSummary ?? e.snippet
            c.sound = .default
            c.threadIdentifier = "mail"
            c.userInfo = ["deeplink": "com.keel.app://inbox"]
            try? await center.add(UNNotificationRequest(identifier: "mail.\(e.id)", content: c, trigger: nil))
            sent.insert(e.id)
            order.append(e.id)
        }
        // Keep the newest 500, in order, so recent emails are never announced twice.
        UserDefaults.standard.set(Array(order.suffix(500)), forKey: "mail.notified")
    }

    // MARK: Sections

    static func section(for d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        if d > cal.date(byAdding: .day, value: -7, to: Date())! { return "This week" }
        return "Older"
    }
}
