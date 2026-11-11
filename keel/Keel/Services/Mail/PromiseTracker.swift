import Foundation
import SwiftData
import UserNotifications

/// Promise tracker: finds commitments YOU made in sent mail ("I'll send the deck Friday"),
/// keeps them in one place, notices when you've likely delivered, and nudges you before they're due.
@MainActor
enum PromiseTracker {
    /// First scan looks back 21 days; later scans continue from the last one.
    static let initialLookback: TimeInterval = 21 * 86_400

    static func scan(accounts: [MailAccount], ctx: ModelContext) async {
        for account in accounts where account.isEnabled {
            let since = account.lastSentScanAt ?? Date().addingTimeInterval(-initialLookback)
            guard let sent = try? await MailProviderFactory.make(for: account).fetchSent(since: since) else { continue }

            for m in sent.sorted(by: { $0.date < $1.date }) {
                markLikelyKept(by: m, accountId: account.id, ctx: ctx)

                let candidates = await AIRouter.shared.extractPromises(body: m.body, sentAt: m.date)
                for (i, c) in candidates.enumerated() {
                    let id = "\(account.id)|\(m.providerId)|\(i)"
                    let exists = (try? ctx.fetchCount(FetchDescriptor<Commitment>(predicate: #Predicate { $0.id == id }))) ?? 0
                    guard exists == 0 else { continue }
                    let due = c.dueDateISO.flatMap { ISO8601DateFormatter.dateOnly.date(from: $0) }
                        .map { Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: $0) ?? $0 }
                    ctx.insert(Commitment(id: id, accountId: account.id, sourceMessageId: m.providerId, threadId: m.threadId,
                                          promise: c.promise, quote: c.quote, recipient: m.from, recipientName: m.fromName,
                                          subject: m.subject, sentAt: m.date, dueDate: due))
                }
            }
            account.lastSentScanAt = Date()
        }
        try? ctx.save()
        await scheduleNudges(ctx: ctx)
    }

    /// If you later replied in the same thread with "attached" / "here's", the promise was probably kept.
    /// Keel never closes it silently — it asks you to confirm with one tap.
    private static func markLikelyKept(by m: FetchedMessage, accountId: String, ctx: ModelContext) {
        let thread = m.threadId
        let sentAt = m.date
        let open = (try? ctx.fetch(FetchDescriptor<Commitment>(predicate: #Predicate {
            $0.threadId == thread && $0.sentAt < sentAt
        }))) ?? []
        let body = m.body.lowercased()
        let deliveryWords = ["attached", "here's", "here is", "please find", "just sent", "sharing", "as promised", "done"]
        guard deliveryWords.contains(where: body.contains) else { return }
        for c in open where c.status == .open && c.accountId == accountId { c.likelyKept = true }
    }

    /// One gentle heads-up at 9am on the due day (5pm deadline), never a barrage.
    static func scheduleNudges(ctx: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        let open = (try? ctx.fetch(FetchDescriptor<Commitment>())) ?? []
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("promise.") }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        for c in open where c.status == .open && !c.likelyKept {
            let fire = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: c.effectiveDue) ?? c.effectiveDue
            guard fire > Date() else { continue }
            let n = UNMutableNotificationContent()
            n.title = "You told \(c.recipientName.isEmpty ? c.recipient : c.recipientName)"
            n.body = "“\(c.promise)” — due today. Tap for a quick draft."
            n.categoryIdentifier = "PROMISE"
            n.userInfo = ["commitmentId": c.id]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            try? await center.add(UNNotificationRequest(identifier: "promise.\(c.id)", content: n,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }
}
