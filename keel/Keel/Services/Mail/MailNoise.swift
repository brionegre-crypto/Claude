import Foundation

/// Tells real people apart from machines. Automated mail (verification codes, alerts, receipts, bank and
/// card notices, newsletters) is never "Needs you", whatever the AI thought.
enum MailNoise {
    private static let automatedSenders = ["noreply", "no-reply", "donotreply", "do-not-reply", "notification", "notify", "alerts", "alert@",
                                           "security", "mailer", "bounce", "billing", "receipts", "statements", "support@", "info@",
                                           "news@", "newsletter", "updates@", "accounts@", "team@", "hello@", "marketing", "digest"]
    private static let automatedSubjects = ["verification code", "verify", "security code", "one-time", "one time", "otp", "passcode",
                                            "sign in", "sign-in", "signin", "log in", "login", "password", "2fa", "two-factor", "authentication",
                                            "your code", "confirm your", "receipt", "your order", "order #", "shipped", "delivered", "out for delivery",
                                            "declined", "transaction", "statement", "payment received", "autopay", "invoice available",
                                            "welcome to", "new device", "security alert", "unusual activity", "sudo"]

    static func isAutomated(_ e: EmailMessage) -> Bool {
        let from = (e.from + " " + e.fromName).lowercased()
        let subject = e.subject.lowercased()
        if e.unsubscribeHeader != nil { return true }                      // bulk mail always carries one
        if automatedSenders.contains(where: from.contains) { return true }
        if automatedSubjects.contains(where: subject.contains) { return true }
        return false
    }

    /// Mail a person actually wrote to you and is waiting on.
    static func needsYou(_ e: EmailMessage, myAddresses: Set<String>) -> Bool {
        guard !e.isArchived, !e.isRead || e.isStarred,
              e.category == .important || e.category == .actionable,
              !myAddresses.contains(e.from.lowercased()),
              e.receivedAt > Date().addingTimeInterval(-7 * 86_400) else { return false }
        return !isAutomated(e)
    }
}
