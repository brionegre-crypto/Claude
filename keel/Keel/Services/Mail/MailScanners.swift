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
            if let s = trial(from: e) ?? subscription(from: e) {
                if let existing = subsByKey[s.key] {
                    if e.receivedAt >= existing.lastCharged {
                        // A price rise on something you already pay for: flag it once.
                        if existing.kind == "subscription", s.kind == "subscription", existing.amount > 0,
                           s.amount > existing.amount * 1.02, s.period == existing.period {
                            UserDefaults.standard.set(existing.amount, forKey: "price.up.\(s.key)")
                            notifyPriceRise(s.name, from: existing.amount, to: s.amount, currency: s.currency)
                        }
                        // A trial followed by a receipt means you're now paying.
                        if existing.kind == "trial" && s.kind != "trial" { existing.kind = s.kind }
                        // An old "your trial" email never overrides something you already pay for.
                        let staleTrial = s.kind == "trial" && existing.kind != "trial"
                        if !staleTrial {
                            if s.amount > 0 { existing.amount = s.amount }
                            existing.lastCharged = s.lastCharged
                            existing.nextDate = s.nextDate; existing.period = s.period; existing.sourceEmailId = e.id
                        }
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
        addBillTasks(ctx: ctx)
        scheduleRenewalReminders(ctx: ctx)
    }

    // MARK: Free trials

    private static let trialWords = ["free trial", "trial ends", "trial will end", "trial is ending", "trial period", "your trial", "trial expires"]

    /// "Your 14-day free trial ends on March 3, then $9.99/month": the date it ends and what it will cost.
    static func trial(from e: EmailMessage) -> Subscription? {
        let source = e.subject + " " + e.snippet + " " + e.bodyPlain.prefix(1500)
        let hay = source.lowercased()
        guard trialWords.contains(where: { hay.contains($0) }),
              !hay.contains("trial has ended"), !hay.contains("trial ended") else { return nil }
        var amount = 0.0, currency = "$"
        if let r = source.range(of: amountPattern, options: .regularExpression) {
            let match = String(source[r])
            currency = String(match.first { "$€£".contains($0) } ?? "$")
            amount = Double(match.filter { $0.isNumber || $0 == "." }) ?? 0
        }
        let s = Subscription(name: merchant(e), amount: amount, lastCharged: e.receivedAt)
        s.kind = "trial"
        s.currency = currency
        s.sourceEmailId = e.id
        s.period = hay.contains("year") || hay.contains("annual") ? "yearly" : "monthly"
        s.nextDate = trialEnd(in: source, after: e.receivedAt)
        return s
    }

    static func trialEnd(in text: String, after: Date) -> Date {
        if let r = text.range(of: #"(ends?|expires?|until|through|on)\s[^.\n]{3,30}"#, options: [.regularExpression, .caseInsensitive]),
           let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let s = String(text[r])
            if let d = det.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))?.date, d > after { return d }
        }
        // "7-day free trial", "30 day trial"
        if let r = text.range(of: #"(\d{1,2})[- ]day"#, options: .regularExpression),
           let n = Int(text[r].prefix { $0.isNumber }), n > 0 {
            return after.addingTimeInterval(Double(n) * 86_400)
        }
        return after.addingTimeInterval(7 * 86_400)
    }

    private static func notifyPriceRise(_ name: String, from old: Double, to new: Double, currency: String) {
        let c = UNMutableNotificationContent()
        c.title = "\(name) went up"
        c.body = "Now \(currency)\(String(format: "%.2f", new)), was \(currency)\(String(format: "%.2f", old)). Still worth it?"
        c.userInfo = ["deeplink": "com.keel.app://money"]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "price.\(name.lowercased())", content: c, trigger: nil))
    }

    // MARK: Bills become tasks

    static var billTasksOn: Bool { UserDefaults.standard.object(forKey: "bills.autoTask") as? Bool ?? true }

    /// Each upcoming bill gets a "Pay …" task on its due date (once per bill email).
    static func addBillTasks(ctx: ModelContext) {
        guard billTasksOn else { return }
        let now = Date()
        let bills = ((try? ctx.fetch(FetchDescriptor<Subscription>())) ?? [])
            .filter { $0.kind == "bill" && !$0.isHidden && ($0.nextDate ?? .distantPast) > now }
        for b in bills {
            guard let source = b.sourceEmailId, let due = b.nextDate else { continue }
            let src: String? = source
            let exists = (try? ctx.fetchCount(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.sourceEmailId == src }))) ?? 0
            guard exists == 0 else { continue }
            let t = TaskItem(title: "Pay \(b.name) \(b.currency)\(String(format: "%.2f", b.amount))", dueDate: Calendar.current.startOfDay(for: due), priority: .medium)
            t.sourceEmailId = source
            t.listName = "Bills"
            t.alertOffsetMinutes = 0
            ctx.insert(t)
            TaskAlerts.schedule(t)
        }
        try? ctx.save()
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
                guard let next = s.nextDate, var fire = Calendar.current.date(byAdding: .day, value: -2, to: next) else { continue }
                // A trial ending sooner than 2 days still gets a warning, 6 hours before it ends.
                var lastMinute = false
                if fire <= Date() && s.kind == "trial" { fire = next.addingTimeInterval(-6 * 3600); lastMinute = true }
                guard fire > Date() else { continue }
                let c = UNMutableNotificationContent()
                c.title = s.kind == "trial" ? "\(s.name) free trial ends \(lastMinute ? "soon" : "in 2 days")"
                    : s.kind == "bill" ? "\(s.name) bill due in 2 days" : "\(s.name) renews in 2 days"
                c.body = s.kind == "trial"
                    ? "Cancel before \(next.formatted(date: .abbreviated, time: .omitted)) if you don't want to pay\(s.amount > 0 ? " \(s.currency)\(String(format: "%.2f", s.amount))" : "")."
                    : "\(s.currency)\(String(format: "%.2f", s.amount))\(s.kind == "bill" ? " due " : " on ")\(next.formatted(date: .abbreviated, time: .omitted)). Still want it?"
                c.userInfo = ["deeplink": "com.keel.app://money"]
                if s.kind == "trial" { c.interruptionLevel = .timeSensitive }
                var at = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                if !lastMinute { at.hour = 10; at.minute = 0 }
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
