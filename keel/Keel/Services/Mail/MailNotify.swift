import Foundation
import SwiftData
import UserNotifications

/// Buttons on new-mail alerts: Archive, Mark as read and Reply (type a reply right in the notification).
@MainActor
enum MailNotify {
    static let category = "MAIL"
    static let archiveAction = "MAIL_ARCHIVE"
    static let readAction = "MAIL_READ"
    static let replyAction = "MAIL_REPLY"

    static var categoryDefinition: UNNotificationCategory {
        UNNotificationCategory(identifier: category, actions: [
            UNTextInputNotificationAction(identifier: replyAction, title: "Reply", options: [],
                                          textInputButtonTitle: "Send", textInputPlaceholder: "Your reply"),
            UNNotificationAction(identifier: archiveAction, title: "Archive", options: []),
            UNNotificationAction(identifier: readAction, title: "Mark as Read", options: []),
        ], intentIdentifiers: [], options: [])
    }

    /// Runs a button tapped on a mail alert. Returns false when it wasn't one of ours.
    static func handle(action: String, emailId: String, replyText: String?) async -> Bool {
        guard [archiveAction, readAction, replyAction].contains(action) else { return false }
        let ctx = KeelStore.container.mainContext
        guard let e = try? ctx.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { $0.id == emailId })).first else { return true }
        let accountId = e.accountId
        let account = ((try? ctx.fetch(FetchDescriptor<MailAccount>())) ?? []).first { $0.id == accountId }
        let provider = account.map { MailProviderFactory.make(for: $0) }
        switch action {
        case archiveAction:
            e.isArchived = true; e.isRead = true
            try? await provider?.archive(e.providerMessageId)
        case readAction:
            e.isRead = true
            try? await provider?.markRead(e.providerMessageId, read: true)
        default:
            let text = (replyText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let provider else { break }
            let subject = e.subject.lowercased().hasPrefix("re:") ? e.subject : "Re: " + e.subject
            do {
                try await provider.send(to: e.from, subject: subject, body: text, inReplyTo: e.replyContext)
                e.isRead = true
                try? await provider.markRead(e.providerMessageId, read: true)
            } catch {
                let c = UNMutableNotificationContent()
                c.title = "Reply not sent"
                c.body = "Keel couldn't send your reply to \(e.fromName.isEmpty ? e.from : e.fromName). Open Keel to try again."
                try? await UNUserNotificationCenter.current().addKeel(UNNotificationRequest(identifier: "mail.fail.\(e.id)", content: c, trigger: nil))
            }
        }
        try? ctx.save()
        return true
    }
}
