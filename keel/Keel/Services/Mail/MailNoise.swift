import Foundation

/// Tells real people apart from machines. Automated mail (verification codes, alerts, receipts, bank and
/// card notices, newsletters) is never "Needs you", whatever the AI thought.
enum MailNoise {
    // Only addresses that are clearly machines. Business inboxes like info@, hello@, support@ or billing@ often carry
    // real replies (a support ticket, a booking), so those are judged by their content and the AI instead.
    private static let automatedSenders = ["noreply", "no-reply", "donotreply", "do-not-reply", "notification", "notify@", "alerts@", "alert@",
                                           "mailer", "bounce", "receipts@", "statements@", "news@", "newsletter", "updates@", "marketing", "digest"]

    /// Automated, but needs you: never left in Updates.
    private static let needsAction = ["action required", "action needed", "past due", "overdue", "payment failed", "payment declined",
                                      "card declined", "final notice", "suspicious", "unusual activity", "security alert", "account locked",
                                      "expires today", "expiring today", "last chance to respond", "response needed", "reply needed"]

    static func needsAttention(_ e: EmailMessage) -> Bool {
        let subject = e.subject.lowercased()
        return needsAction.contains(where: subject.contains)
    }
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

    // MARK: Sales and promotions

    private static let promoWords = ["% off", "percent off", "flash sale", "big sale", "sale ends", "sale starts", "on sale", "limited time",
                                     "limited-time", "promo code", "coupon", "use code", "free shipping", "shop now", "buy now", "order now",
                                     "exclusive offer", "special offer", "deal of", "deals", "black friday", "cyber monday", "doorbuster",
                                     "new arrivals", "last chance", "ends tonight", "ends today", "ends soon", "don't miss", "save up to",
                                     "save $", "clearance", "bogo", "buy one", "gift with purchase", "members-only", "early access",
                                     "your cart", "left in your cart", "back in stock", "price drop", "upgrade now", "subscribe and save"]
    private static let pitchWords = ["quick call", "15 minutes", "15-minute", "20 minutes", "30-minute call", "book a demo",
                                     "schedule a demo", "a quick demo", "would you be open", "are you open to", "open to a",
                                     "our platform", "our solution", "our software", "our agency", "our team helps", "we help companies",
                                     "we help businesses", "we help brands", "we specialize in", "increase your revenue", "grow your business",
                                     "boost your", "more leads", "qualified leads", "lead generation", "seo services", "web design services",
                                     "partnership opportunity", "partner with you", "circling back", "following up on my last", "following up on my previous",
                                     "bumping this", "just bumping", "worth a conversation", "worth a chat", "grab time", "calendly.com",
                                     "reply stop", "reply \"stop\"", "not the right person", "who handles", "decision maker",
                                     "case study", "free audit", "free consultation"]

    /// Promotional or sales mail: store promotions, offers and cold sales pitches. These get their own
    /// "Sales & promos" tab, never count as needing you, and Keel never drafts replies to them.
    /// `knownSender`: someone you've written back to before. Their mail is never treated as a cold pitch.
    static func isSalesOrPromo(_ e: EmailMessage, knownSender: Bool = false) -> Bool {
        if needsAttention(e) { return false }
        let subject = e.subject.lowercased()
        let text = subject + " " + e.bodyPlain.prefix(2_000).lowercased()
        let from = (e.from + " " + e.fromName).lowercased()
        if from.contains("marketing") || from.contains("promo") || from.contains("offers@") || from.contains("deals@") || from.contains("sales@") { return true }
        let promoHits = promoWords.filter { text.contains($0) }.count
        if promoHits >= 2 || (promoHits >= 1 && e.unsubscribeHeader != nil) { return true }
        if subject.contains("% off") || (subject.contains(" sale") && (subject.contains("off") || subject.contains("ends"))) { return true }
        // A cold pitch written to look personal: several sales phrases at once.
        guard !knownSender else { return false }
        let pitchHits = pitchWords.filter { text.contains($0) }.count
        return pitchHits >= 3
    }

    /// Mail a person actually wrote to you and is waiting on.
    static func needsYou(_ e: EmailMessage, myAddresses: Set<String>) -> Bool {
        guard !e.isArchived, !e.isRead || e.isStarred,
              e.category == .important || e.category == .actionable,
              !myAddresses.contains(e.from.lowercased()),
              e.receivedAt > Date().addingTimeInterval(-7 * 86_400) else { return false }
        return !isAutomated(e) && !isSalesOrPromo(e)
    }
}
