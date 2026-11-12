import Foundation
import SwiftData
import UserNotifications

/// Reads new mail on the phone for receipts, bills and shipping updates. Nothing is sent anywhere.
@MainActor
enum MailScanners {
    static func scan(_ emails: [EmailMessage], ctx: ModelContext) {
        guard !emails.isEmpty else { return }
        let subs = (try? ctx.fetch(FetchDescriptor<Subscription>())) ?? []
        let deliveries = (try? ctx.fetch(FetchDescriptor<Delivery>())) ?? []
        var subsByKey = Dictionary(subs.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var delByNumber = Dictionary(deliveries.map { ($0.tracking, $0) }, uniquingKeysWith: { a, _ in a })
        for e in emails.sorted(by: { $0.receivedAt < $1.receivedAt }) {
            if let s = subscription(from: e) {
                if let existing = subsByKey[s.key] {
                    if e.receivedAt >= existing.lastCharged {
                        existing.amount = s.amount; existing.lastCharged = s.lastCharged
                        existing.nextDate = s.nextDate; existing.period = s.period; existing.sourceEmailId = e.id
                    }
                } else {
                    ctx.insert(s); subsByKey[s.key] = s
                }
            }
            if let d = delivery(from: e) {
                if let existing = delByNumber[d.tracking] {
                    if rank(d.status) >= rank(existing.status) { existing.status = d.status }
                    existing.expected = d.expected ?? existing.expected
                    existing.updatedAt = Date(); existing.isArchived = false
                } else {
                    ctx.insert(d); delByNumber[d.tracking] = d
                }
            }
        }
        try? ctx.save()
        scheduleRenewalReminders(ctx: ctx)
    }

    /// One-time look back over mail already on the phone.
    static func backfillIfNeeded(ctx: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: "scanners.backfilled") else { return }
        UserDefaults.standard.set(true, forKey: "scanners.backfilled")
        let since = Date().addingTimeInterval(-90 * 86_400)
        let mail = ((try? ctx.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { $0.receivedAt > since }))) ?? [])
        scan(mail, ctx: ctx)
    }

    // MARK: Subscriptions and bills

    private static let receiptWords = ["receipt", "subscription", "renew", "your plan", "membership", "billing", "invoice", "payment received", "you've been charged", "you were charged", "thanks for your payment", "statement", "amount due", "payment due", "bill is ready"]
    private static let amountPattern = #"([$€£])\s?(\d{1,4}(?:,\d{3})*(?:\.\d{2}))"#

    static func subscription(from e: EmailMessage) -> Subscription? {
        let hay = (e.subject + " " + e.snippet + " " + e.bodyPlain.prefix(1500)).lowercased()
        guard receiptWords.contains(where: { hay.contains($0) }) else { return nil }
        guard !["shipped", "order confirmed", "your order", "refund"].contains(where: { e.subject.lowercased().contains($0) }) || hay.contains("subscription") else { return nil }
        let source = e.subject + " " + e.snippet + " " + e.bodyPlain.prefix(1500)
        guard let r = source.range(of: amountPattern, options: .regularExpression) else { return nil }
        let match = String(source[r])
        let currency = String(match.first { "$€£".contains($0) } ?? "$")
        guard let amount = Double(match.filter { $0.isNumber || $0 == "." }), amount > 0, amount < 5_000 else { return nil }
        let name = merchant(e)
        let s = Subscription(name: name, amount: amount, lastCharged: e.receivedAt)
        s.currency = currency
        s.sourceEmailId = e.id
        let isBill = ["amount due", "payment due", "bill is ready", "statement"].contains { hay.contains($0) }
        s.kind = isBill ? "bill" : "subscription"
        s.period = hay.contains("annual") || hay.contains("yearly") || hay.contains("per year") || hay.contains("/yr") ? "yearly"
            : hay.contains("weekly") || hay.contains("per week") ? "weekly" : "monthly"
        if isBill {
            s.nextDate = dueDate(in: source, after: e.receivedAt)
        } else {
            let cal = Calendar.current
            s.nextDate = cal.date(byAdding: s.period == "yearly" ? .year : s.period == "weekly" ? .weekOfYear : .month, value: 1, to: e.receivedAt)
        }
        return s
    }

    private static func merchant(_ e: EmailMessage) -> String {
        var n = e.fromName.isEmpty ? (e.from.split(separator: "@").last.map(String.init) ?? e.from) : e.fromName
        for junk in [" Billing", " billing", " Receipts", " Payments", " Team", " Support", " via Stripe", "noreply", "no-reply"] {
            n = n.replacingOccurrences(of: junk, with: "")
        }
        return n.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).isEmpty ? e.from : n.trimmingCharacters(in: .whitespaces)
    }

    private static func dueDate(in text: String, after: Date) -> Date? {
        guard let r = text.range(of: #"due (on|by)?\s?[^.\n]{3,25}"#, options: [.regularExpression, .caseInsensitive]),
              let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let s = String(text[r])
        return det.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))?.date.flatMap { $0 > after ? $0 : nil }
    }

    /// A reminder 2 days before a renewal or bill due date.
    static func scheduleRenewalReminders(ctx: ModelContext) {
        let subs = ((try? ctx.fetch(FetchDescriptor<Subscription>())) ?? []).filter { !$0.isHidden && $0.remind }
        let center = UNUserNotificationCenter.current()
        Task {
            let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("renew.") }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for s in subs {
                guard let next = s.nextDate, let fire = Calendar.current.date(byAdding: .day, value: -2, to: next), fire > Date() else { continue }
                let c = UNMutableNotificationContent()
                c.title = s.kind == "bill" ? "\(s.name) bill due in 2 days" : "\(s.name) renews in 2 days"
                c.body = "\(s.currency)\(String(format: "%.2f", s.amount))\(s.kind == "bill" ? " due " : " on ")\(next.formatted(date: .abbreviated, time: .omitted)). Still want it?"
                let comps = Calendar.current.dateComponents([.year, .month, .day], from: fire)
                var at = comps; at.hour = 10
                try? await center.add(UNNotificationRequest(identifier: "renew.\(s.id)", content: c,
                                                            trigger: UNCalendarNotificationTrigger(dateMatching: at, repeats: false)))
            }
        }
    }

    // MARK: Deliveries

    private static let patterns: [(carrier: String, regex: String)] = [
        ("UPS", #"\b1Z[0-9A-Z]{16}\b"#),
        ("USPS", #"\b9[2-5]\d{20}\b"#),
        ("DHL", #"\bJ[A-Z]{3}\d{10}\b"#),
    ]

    static func delivery(from e: EmailMessage) -> Delivery? {
        let subject = e.subject.lowercased()
        let shippingWords = ["shipped", "on its way", "on the way", "out for delivery", "delivered", "arriving", "tracking", "shipment", "your package"]
        guard shippingWords.contains(where: { subject.contains($0) || e.snippet.lowercased().contains($0) }) else { return nil }
        let text = e.subject + " " + e.snippet + " " + e.bodyPlain.prefix(4000)
        var carrier: String?, number: String?
        for p in patterns {
            if let r = text.range(of: p.regex, options: .regularExpression) { carrier = p.carrier; number = String(text[r]); break }
        }
        let from = (e.from + " " + e.fromName).lowercased()
        if number == nil, from.contains("fedex") || text.lowercased().contains("fedex"),
           let r = text.range(of: #"\b\d{12}(\d{3})?\b"#, options: .regularExpression) { carrier = "FedEx"; number = String(text[r]) }
        if number == nil, from.contains("amazon"), let r = text.range(of: #"\b\d{3}-\d{7}-\d{7}\b"#, options: .regularExpression) {
            carrier = "Amazon"; number = String(text[r])
        }
        guard let carrier, let number else { return nil }
        let title = e.subject
            .replacingOccurrences(of: #"(?i)^(re:|fwd:)\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let d = Delivery(carrier: carrier, tracking: number, title: title.isEmpty ? "Package from \(e.fromName)" : title)
        d.sourceEmailId = e.id
        d.status = subject.contains("delivered") ? "delivered" : subject.contains("out for delivery") ? "out" : "shipped"
        if d.status == "out" { d.expected = Calendar.current.startOfDay(for: e.receivedAt) }
        else if let r = text.range(of: #"(?i)(arriving|arrives|expected|estimated delivery)[:\s]+[^.\n]{3,30}"#, options: .regularExpression),
                let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let s = String(text[r])
            d.expected = det.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))?.date
        }
        return d
    }

    static func rank(_ status: String) -> Int { ["ordered": 0, "shipped": 1, "out": 2, "delivered": 3][status] ?? 0 }
}
