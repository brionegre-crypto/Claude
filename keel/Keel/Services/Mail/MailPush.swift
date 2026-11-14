import Foundation
import SwiftData
import UIKit

/// Instant new-mail alerts, even when Keel is closed: Gmail and Outlook tell your Keel server "new mail",
/// the server sends this device a silent push, and Keel wakes up, fetches the mail and alerts you as usual.
/// iCloud and other IMAP mail can't do this, so they keep using background refresh.
@MainActor
enum MailPush {
    static let tokenKey = "push.deviceToken"            // "push." keys stay on this device (SettingsSync)

    /// Called with this device's push address: tell your Keel server where to wake it.
    static func register(_ token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: tokenKey)
        Task {
            #if DEBUG
            let sandbox = true                           // apps run from Xcode use Apple's test push service
            #else
            let sandbox = false                          // TestFlight and App Store use the real one
            #endif
            _ = try? await KeelCloud.call("push/register", method: "POST", body: ["token": hex, "sandbox": sandbox], auth: true)
        }
    }

    /// Keeps each Gmail and Outlook account subscribed (Gmail lasts 7 days, Outlook about 3, so they're renewed).
    static func refresh(ctx: ModelContext) async {
        guard KeelServer.isConfigured, let base = KeelServer.baseURL,
              let data = try? await KeelCloud.call("push/config", auth: true),
              let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              cfg["ready"] as? Bool == true else { return }
        let accounts = ((try? ctx.fetch(FetchDescriptor<MailAccount>())) ?? []).filter(\.isEnabled)
        for a in accounts {
            switch a.provider {
            case .gmail:
                guard let topic = cfg["gmailTopic"] as? String, !topic.isEmpty, Throttle.due("push.gmail.\(a.id)", every: 5 * 86_400) else { continue }
                let api = AuthedClient(account: a.id, cfg: OAuthManager.google)
                _ = try? await api.json(URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/watch")!, method: "POST",
                                        body: ["topicName": topic, "labelIds": ["INBOX"], "labelFilterBehavior": "INCLUDE"])
            case .outlook:
                guard let state = cfg["clientState"] as? String, !state.isEmpty, Throttle.due("push.graph.\(a.id)", every: 36 * 3600) else { continue }
                let api = AuthedClient(account: a.id, cfg: OAuthManager.microsoft)
                let expires = ISO8601DateFormatter().string(from: Date().addingTimeInterval(4_200 * 60))
                let key = "push.graph.sub.\(a.id)"
                if let sub = UserDefaults.standard.string(forKey: key),
                   (try? await api.json(URL(string: "https://graph.microsoft.com/v1.0/subscriptions/\(sub)")!, method: "PATCH",
                                         body: ["expirationDateTime": expires])) != nil {
                    continue                              // renewed
                }
                let r = try? await api.json(URL(string: "https://graph.microsoft.com/v1.0/subscriptions")!, method: "POST", body: [
                    "changeType": "created",
                    "notificationUrl": base.appendingPathComponent("push/graph").absoluteString,
                    "resource": "me/mailFolders('Inbox')/messages",
                    "expirationDateTime": expires,
                    "clientState": state,
                ])
                if let id = r?["id"] as? String { UserDefaults.standard.set(id, forKey: key) }
            default:
                continue
            }
        }
    }
}
