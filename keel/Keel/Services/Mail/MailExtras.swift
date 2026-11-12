import Foundation
import SwiftUI
import SwiftData
import UIKit
import UserNotifications

// MARK: - One-tap unsubscribe

@MainActor
enum Unsubscribe {
    enum Outcome { case done, openedWebPage, unavailable }

    /// Parses `List-Unsubscribe: <mailto:…>, <https://…>`.
    nonisolated static func links(_ header: String?) -> (web: URL?, mail: URL?) {
        guard let header else { return (nil, nil) }
        let parts = header.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " <>\t\r\n")) }
        let web = parts.first { $0.lowercased().hasPrefix("https://") || $0.lowercased().hasPrefix("http://") }.flatMap(URL.init(string:))
        let mail = parts.first { $0.lowercased().hasPrefix("mailto:") }.flatMap(URL.init(string:))
        return (web, mail)
    }

    nonisolated static func canUnsubscribe(_ e: EmailMessage) -> Bool {
        let l = links(e.unsubscribeHeader)
        return l.web != nil || l.mail != nil
    }

    /// Tries, in order: one-click (RFC 8058) → email request → the sender's unsubscribe page.
    /// On success, archives everything already in your inbox from that sender.
    static func run(_ e: EmailMessage, provider: MailProvider?, ctx: ModelContext, allowWebPage: Bool = true) async -> Outcome {
        if e.unsubscribeHeader == nil, let provider, let info = try? await provider.unsubscribeHeader(for: e.providerMessageId) {
            e.unsubscribeHeader = info.header
            e.unsubscribeOneClick = info.oneClick
        }
        let l = links(e.unsubscribeHeader)

        if let web = l.web, e.unsubscribeOneClick {
            var req = URLRequest(url: web)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data("List-Unsubscribe=One-Click".utf8)
            if let result = try? await URLSession.shared.data(for: req),
               let code = (result.1 as? HTTPURLResponse)?.statusCode, (200..<400).contains(code) {
                await archiveSender(e, provider: provider, ctx: ctx)
                return .done
            }
        }
        if let mail = l.mail, let provider {
            let comps = URLComponents(url: mail, resolvingAgainstBaseURL: false)
            let to = comps?.path ?? ""
            let subject = comps?.queryItems?.first { $0.name.lowercased() == "subject" }?.value ?? "unsubscribe"
            let body = comps?.queryItems?.first { $0.name.lowercased() == "body" }?.value ?? "unsubscribe"
            if !to.isEmpty, (try? await provider.send(OutgoingMail(to: [to], subject: subject, body: body))) != nil {
                await archiveSender(e, provider: provider, ctx: ctx)
                return .done
            }
        }
        if let web = l.web, allowWebPage {
            await UIApplication.shared.open(web)
            await archiveSender(e, provider: provider, ctx: ctx)
            return .openedWebPage
        }
        return .unavailable
    }

    private static func archiveSender(_ e: EmailMessage, provider: MailProvider?, ctx: ModelContext) async {
        let sender = e.from.lowercased()
        let all = (try? ctx.fetch(FetchDescriptor<EmailMessage>())) ?? []
        for m in all where m.from.lowercased() == sender && !m.isArchived {
            m.isArchived = true
            try? await provider?.archive(m.providerMessageId)
        }
        Haptics.success()
    }
}

// MARK: - Remind me if no reply

@MainActor
enum FollowUps {
    static let options: [(label: String, days: Int?)] = [("Off", nil), ("Tomorrow", 1), ("In 3 days", 3), ("In a week", 7)]

    static func create(account: String, to: String, name: String, subject: String, days: Int, ctx: ModelContext) {
        let remindAt = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        let f = FollowUp(accountId: account, recipient: to.lowercased(), recipientName: name, subject: subject,
                         sentAt: Date(), remindAt: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: remindAt) ?? remindAt)
        ctx.insert(f)
        schedule(f)
    }

    static func schedule(_ f: FollowUp) {
        let c = UNMutableNotificationContent()
        c.title = "No reply from \(f.recipientName.isEmpty ? f.recipient : f.recipientName)"
        c.body = "“\(f.subject)” · tap to send a friendly nudge"
        KeelAlerts.urgent(c, relevance: 0.6)
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: f.remindAt)
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "followup.\(f.id.uuidString)", content: c,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }

    static func resolve(_ f: FollowUp) {
        f.resolvedAt = Date()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["followup.\(f.id.uuidString)"])
    }

    /// After each sync: a reply from that person on the same subject closes the follow-up.
    static func check(ctx: ModelContext) {
        let open = ((try? ctx.fetch(FetchDescriptor<FollowUp>())) ?? []).filter { $0.resolvedAt == nil }
        guard !open.isEmpty else { return }
        let mail = (try? ctx.fetch(FetchDescriptor<EmailMessage>())) ?? []
        for f in open {
            let topic = normalized(f.subject)
            if mail.contains(where: { $0.from.lowercased() == f.recipient && $0.receivedAt > f.sentAt && normalized($0.subject).contains(topic) }) {
                resolve(f)
            }
        }
    }

    static func normalized(_ subject: String) -> String {
        subject.lowercased()
            .replacingOccurrences(of: #"^((re|fwd|fw|aw)\s*:\s*)+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func nudgeDraft(_ f: FollowUp) -> ComposeDraft {
        let first = f.recipientName.split(separator: " ").first.map(String.init) ?? ""
        return ComposeDraft(accountId: f.accountId, to: f.recipient, subject: ComposeDraft.prefixed("Re:", f.subject),
                            body: "Hi\(first.isEmpty ? "" : " \(first)"),\n\nJust bumping this up in case it got buried. Any thoughts?\n\nThanks!")
    }
}

/// Inbox → "Awaiting reply"
struct FollowUpsView: View {
    @Query(sort: \FollowUp.remindAt) private var all: [FollowUp]
    @State private var compose: ComposeDraft?
    private var open: [FollowUp] { all.filter { $0.resolvedAt == nil } }

    var body: some View {
        List {
            if open.isEmpty {
                ContentUnavailableView("No one owes you a reply", systemImage: "checkmark.bubble",
                                       description: Text("When you send an email, choose “Remind me if no reply” and it shows up here."))
                    .listRowBackground(Color.clear)
            }
            ForEach(open) { f in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(f.recipientName.isEmpty ? f.recipient : f.recipientName).font(DS.Font.headline)
                        Spacer()
                        Chip(text: f.isDue ? "Nudge now" : "Remind \(f.remindAt.formatted(.relative(presentation: .named)))",
                             color: f.isDue ? DS.Palette.warmth : DS.Palette.inkSoft, icon: "clock")
                    }
                    Text(f.subject).font(DS.Font.body).lineLimit(1)
                    Text("Sent \(f.sentAt.formatted(.relative(presentation: .named)))").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                .contentShape(Rectangle())
                .onTapGesture { compose = FollowUps.nudgeDraft(f) }
                .swipeActions {
                    Button { FollowUps.resolve(f) } label: { Label("Got a reply", systemImage: "checkmark") }.tint(DS.Palette.calm)
                }
            }
        }
        .navigationTitle("Awaiting reply")
        .sheet(item: $compose) { ComposeView(draft: $0) }
    }
}
