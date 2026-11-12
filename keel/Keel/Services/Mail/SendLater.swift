import Foundation
import SwiftData
import UserNotifications

/// Send later: messages are stored on the phone and sent by Keel's sync at or after their time.
/// iPhone decides when background refresh runs, so a message can go out a few minutes late if Keel is closed.
@MainActor
enum SendLater {
    @discardableResult
    static func schedule(_ mail: OutgoingMail, accountId: String, at date: Date, ctx: ModelContext) -> ScheduledMail {
        let s = ScheduledMail(accountId: accountId, to: mail.to, subject: mail.subject, body: mail.body, sendAt: date)
        s.cc = mail.cc; s.bcc = mail.bcc
        if let r = mail.replyTo {
            s.replyProviderId = r.providerMessageId; s.replyThreadId = r.threadId
            s.replyMessageIdHeader = r.messageIdHeader; s.replyAll = r.replyAll
        }
        if !mail.attachments.isEmpty {
            s.attachmentsJSON = try? JSONEncoder().encode(mail.attachments.map { StoredAttachment(filename: $0.filename, mimeType: $0.mimeType, data: $0.data) })
        }
        // Remember the alias without changing the stored model (kept beside it in settings).
        if let a = mail.fromAlias { UserDefaults.standard.set(a, forKey: "sendlater.alias.\(s.id)") }
        ctx.insert(s)
        try? ctx.save()
        SyncEngine.scheduleRefresh(at: date)
        return s
    }

    static func outgoing(_ s: ScheduledMail) -> OutgoingMail {
        let files = s.attachmentsJSON.flatMap { try? JSONDecoder().decode([StoredAttachment].self, from: $0) } ?? []
        var m = OutgoingMail(
            to: s.to, cc: s.cc, bcc: s.bcc, subject: s.subject, body: s.body,
            replyTo: s.replyProviderId.map { ReplyContext(providerMessageId: $0, threadId: s.replyThreadId ?? "", messageIdHeader: s.replyMessageIdHeader, replyAll: s.replyAll) },
            attachments: files.map { OutgoingAttachment(filename: $0.filename, mimeType: $0.mimeType, data: $0.data) })
        m.fromAlias = UserDefaults.standard.string(forKey: "sendlater.alias.\(s.id)")
        return m
    }

    /// Sends everything that's due. Called at the start of every sync.
    static func sendDue(ctx: ModelContext) async {
        let now = Date()
        let due = ((try? ctx.fetch(FetchDescriptor<ScheduledMail>())) ?? []).filter { $0.sendAt <= now }
        guard !due.isEmpty else { return }
        let accounts = (try? ctx.fetch(FetchDescriptor<MailAccount>())) ?? []
        for s in due {
            guard let account = accounts.first(where: { $0.id == s.accountId }) else { s.lastError = "Account removed"; continue }
            do {
                try await MailProviderFactory.make(for: account).send(outgoing(s))
                UserDefaults.standard.removeObject(forKey: "sendlater.alias.\(s.id)")
                ctx.delete(s)
            } catch {
                s.lastError = error.localizedDescription
                let c = UNMutableNotificationContent()
                c.title = "Scheduled email didn't send"
                c.body = "“\(s.subject)” will retry on the next sync. Open Inbox → Scheduled to send it now."
                try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "sendlater.\(s.id)", content: c, trigger: nil))
            }
        }
        try? ctx.save()
    }

    /// Quick picks for the Send later menu.
    static func presets(now: Date = Date()) -> [(String, Date)] {
        let cal = Calendar.current
        var out: [(String, Date)] = []
        if let six = cal.date(bySettingHour: 18, minute: 0, second: 0, of: now), six > now.addingTimeInterval(1800) { out.append(("This evening, 6 PM", six)) }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), let t8 = cal.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) {
            out.append(("Tomorrow morning, 8 AM", t8))
        }
        if let mon = cal.nextDate(after: now, matching: DateComponents(hour: 8, minute: 0, weekday: 2), matchingPolicy: .nextTime) {
            out.append(("Monday morning, 8 AM", mon))
        }
        return out
    }
}
