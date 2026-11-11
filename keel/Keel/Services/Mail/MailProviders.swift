import Foundation

/// Common surface over Gmail API, Microsoft Graph and iCloud IMAP.
struct FetchedMessage {
    var providerId, threadId, from, fromName, subject, snippet, body: String
    var date: Date
    var isRead: Bool
}

protocol MailProvider {
    /// Incremental fetch from `cursor`; returns new messages and the next cursor.
    func fetchChanges(cursor: String?) async throws -> (messages: [FetchedMessage], cursor: String?)
    func archive(_ providerId: String) async throws
    func markRead(_ providerId: String, read: Bool) async throws
    /// Writes Keel's AI category back as a label/category so other clients (and Claude Duet) see it.
    func applyLabel(_ providerId: String, label: String) async throws
    func send(to: String, subject: String, body: String, inReplyTo: String?) async throws
    /// Emails YOU sent since `since` — the promise tracker reads these. `from` holds the first recipient.
    func fetchSent(since: Date) async throws -> [FetchedMessage]
}

enum MailProviderFactory {
    @MainActor static func make(for account: MailAccount) -> MailProvider {
        switch account.provider {
        case .gmail: GmailProvider(account: account.id)
        case .outlook: OutlookProvider(account: account.id)
        case .icloud: ICloudMailProvider(address: account.address)
        }
    }
}

// MARK: - Authorized JSON helper

struct AuthedClient {
    let account: String
    let cfg: OAuthManager.Config

    @MainActor func token() async throws -> String {
        guard var t = KeychainStore.tokens(account: account) else { throw URLError(.userAuthenticationRequired) }
        if t.expiresAt < Date(), let r = t.refresh {
            t = try await OAuthManager.shared.refresh(cfg, refreshToken: r)
            KeychainStore.saveTokens(t, account: account)
        }
        return t.access
    }

    @MainActor func json(_ url: URL, method: String = "GET", body: Any? = nil) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

// MARK: - Gmail (REST API, history-based incremental sync)

struct GmailProvider: MailProvider {
    let account: String
    private var api: AuthedClient { AuthedClient(account: account, cfg: OAuthManager.google) }
    private let base = "https://gmail.googleapis.com/gmail/v1/users/me"

    func fetchChanges(cursor: String?) async throws -> (messages: [FetchedMessage], cursor: String?) {
        var ids: [String] = []
        var newCursor = cursor
        if let cursor {
            let h = try await api.json(URL(string: "\(base)/history?startHistoryId=\(cursor)&historyTypes=messageAdded")!)
            for item in h["history"] as? [[String: Any]] ?? [] {
                for added in item["messagesAdded"] as? [[String: Any]] ?? [] {
                    if let m = added["message"] as? [String: Any], let id = m["id"] as? String { ids.append(id) }
                }
            }
            newCursor = h["historyId"] as? String ?? cursor
        } else {
            let list = try await api.json(URL(string: "\(base)/messages?maxResults=100&q=newer_than:14d")!)
            ids = (list["messages"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            let profile = try await api.json(URL(string: "\(base)/profile")!)
            newCursor = profile["historyId"] as? String
        }
        var out: [FetchedMessage] = []
        for id in ids.prefix(200) {
            let m = try await api.json(URL(string: "\(base)/messages/\(id)?format=full")!)
            out.append(Self.parse(m))
        }
        return (out, newCursor)
    }

    static func parse(_ m: [String: Any]) -> FetchedMessage {
        let payload = m["payload"] as? [String: Any] ?? [:]
        let headers = (payload["headers"] as? [[String: String]] ?? []).reduce(into: [String: String]()) { $0[$1["name"]?.lowercased() ?? ""] = $1["value"] }
        let fromRaw = headers["from"] ?? ""
        let (name, email) = parseFrom(fromRaw)
        let labels = m["labelIds"] as? [String] ?? []
        let ms = Double(m["internalDate"] as? String ?? "0") ?? 0
        return FetchedMessage(providerId: m["id"] as? String ?? "", threadId: m["threadId"] as? String ?? "",
                              from: email, fromName: name, subject: headers["subject"] ?? "(no subject)",
                              snippet: m["snippet"] as? String ?? "", body: plainBody(payload),
                              date: Date(timeIntervalSince1970: ms / 1000), isRead: !labels.contains("UNREAD"))
    }

    static func plainBody(_ part: [String: Any]) -> String {
        if part["mimeType"] as? String == "text/plain",
           let data = (part["body"] as? [String: Any])?["data"] as? String,
           let d = Data(base64Encoded: data.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/").padding(toLength: ((data.count + 3) / 4) * 4, withPad: "=", startingAt: 0)) {
            return String(decoding: d, as: UTF8.self)
        }
        for p in part["parts"] as? [[String: Any]] ?? [] { let b = plainBody(p); if !b.isEmpty { return b } }
        return ""
    }

    func archive(_ id: String) async throws {
        _ = try await api.json(URL(string: "\(base)/messages/\(id)/modify")!, method: "POST", body: ["removeLabelIds": ["INBOX"]])
    }
    func markRead(_ id: String, read: Bool) async throws {
        let key = read ? "removeLabelIds" : "addLabelIds"
        _ = try await api.json(URL(string: "\(base)/messages/\(id)/modify")!, method: "POST", body: [key: ["UNREAD"]])
    }
    func applyLabel(_ id: String, label: String) async throws {
        // Production: cache label ids; create "Keel/<label>" via POST /labels on first use.
        _ = try await api.json(URL(string: "\(base)/messages/\(id)/modify")!, method: "POST", body: ["addLabelIds": [label]])
    }
    func fetchSent(since: Date) async throws -> [FetchedMessage] {
        let after = Int(since.timeIntervalSince1970)
        let list = try await api.json(URL(string: "\(base)/messages?maxResults=50&q=in:sent%20after:\(after)")!)
        var out: [FetchedMessage] = []
        for id in (list["messages"] as? [[String: Any]] ?? []).compactMap({ $0["id"] as? String }) {
            let m = try await api.json(URL(string: "\(base)/messages/\(id)?format=full")!)
            var f = Self.parse(m)
            let headers = ((m["payload"] as? [String: Any])?["headers"] as? [[String: String]] ?? [])
            let to = headers.first { $0["name"]?.lowercased() == "to" }?["value"] ?? ""
            let (name, email) = parseFrom(to.components(separatedBy: ",").first ?? to)
            f.from = email; f.fromName = name
            f.body = Self.stripQuotedReply(f.body)
            out.append(f)
        }
        return out
    }

    /// Only YOUR new text matters — drop the quoted thread below "On … wrote:" / ">" lines.
    static func stripQuotedReply(_ body: String) -> String {
        var kept: [Substring] = []
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix(">") || (t.hasPrefix("On ") && t.hasSuffix("wrote:")) || t.hasPrefix("-----Original Message") { break }
            kept.append(line)
        }
        return kept.joined(separator: "\n")
    }

    func send(to: String, subject: String, body: String, inReplyTo: String?) async throws {
        var raw = "To: \(to)\r\nSubject: \(subject)\r\nContent-Type: text/plain; charset=utf-8\r\n"
        if let inReplyTo { raw += "In-Reply-To: \(inReplyTo)\r\nReferences: \(inReplyTo)\r\n" }
        raw += "\r\n\(body)"
        _ = try await api.json(URL(string: "\(base)/messages/send")!, method: "POST", body: ["raw": Data(raw.utf8).base64URL])
    }
}

// MARK: - Outlook / Microsoft 365 (Graph, delta query)

struct OutlookProvider: MailProvider {
    let account: String
    private var api: AuthedClient { AuthedClient(account: account, cfg: OAuthManager.microsoft) }
    private let base = "https://graph.microsoft.com/v1.0/me"

    func fetchChanges(cursor: String?) async throws -> (messages: [FetchedMessage], cursor: String?) {
        var url = URL(string: cursor ?? "\(base)/mailFolders/inbox/messages/delta?$select=subject,from,bodyPreview,body,receivedDateTime,isRead,conversationId")!
        var out: [FetchedMessage] = []
        while true {
            let page = try await api.json(url)
            for m in page["value"] as? [[String: Any]] ?? [] {
                let from = ((m["from"] as? [String: Any])?["emailAddress"] as? [String: Any]) ?? [:]
                let body = (m["body"] as? [String: Any])?["content"] as? String ?? ""
                out.append(FetchedMessage(
                    providerId: m["id"] as? String ?? "", threadId: m["conversationId"] as? String ?? "",
                    from: from["address"] as? String ?? "", fromName: from["name"] as? String ?? "",
                    subject: m["subject"] as? String ?? "", snippet: m["bodyPreview"] as? String ?? "",
                    body: body.strippingHTML,
                    date: ISO8601DateFormatter().date(from: m["receivedDateTime"] as? String ?? "") ?? Date(),
                    isRead: m["isRead"] as? Bool ?? false))
            }
            if let next = page["@odata.nextLink"] as? String { url = URL(string: next)!; continue }
            return (out, page["@odata.deltaLink"] as? String)
        }
    }

    func archive(_ id: String) async throws {
        _ = try await api.json(URL(string: "\(base)/messages/\(id)/move")!, method: "POST", body: ["destinationId": "archive"])
    }
    func markRead(_ id: String, read: Bool) async throws {
        _ = try await api.json(URL(string: "\(base)/messages/\(id)")!, method: "PATCH", body: ["isRead": read])
    }
    func applyLabel(_ id: String, label: String) async throws {
        _ = try await api.json(URL(string: "\(base)/messages/\(id)")!, method: "PATCH", body: ["categories": ["Keel/\(label)"]])
    }
    func fetchSent(since: Date) async throws -> [FetchedMessage] {
        let iso = ISO8601DateFormatter().string(from: since)
        let filter = "sentDateTime ge \(iso)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let page = try await api.json(URL(string: "\(base)/mailFolders/sentitems/messages?$top=50&$filter=\(filter)&$select=subject,toRecipients,body,uniqueBody,sentDateTime,conversationId")!)
        return (page["value"] as? [[String: Any]] ?? []).map { m in
            let to = (((m["toRecipients"] as? [[String: Any]])?.first)?["emailAddress"] as? [String: Any]) ?? [:]
            // uniqueBody = only the text new in this message (Graph strips the quoted thread for us)
            let body = ((m["uniqueBody"] ?? m["body"]) as? [String: Any])?["content"] as? String ?? ""
            return FetchedMessage(providerId: m["id"] as? String ?? "", threadId: m["conversationId"] as? String ?? "",
                                  from: to["address"] as? String ?? "", fromName: to["name"] as? String ?? "",
                                  subject: m["subject"] as? String ?? "", snippet: "", body: body.strippingHTML,
                                  date: ISO8601DateFormatter().date(from: m["sentDateTime"] as? String ?? "") ?? Date(),
                                  isRead: true)
        }
    }

    func send(to: String, subject: String, body: String, inReplyTo: String?) async throws {
        _ = try await api.json(URL(string: "\(base)/sendMail")!, method: "POST", body: [
            "message": ["subject": subject, "body": ["contentType": "Text", "content": body],
                        "toRecipients": [["emailAddress": ["address": to]]]] as [String: Any],
        ] as [String: Any])
    }
}

// MARK: - iCloud Mail (IMAP — Apple offers no mail API)

/// iCloud requires IMAP (imap.mail.me.com:993) with an app-specific password from appleid.apple.com.
/// TODO: implement with Apple's swift-nio-imap package (add via SPM). Until then this provider is inert.
struct ICloudMailProvider: MailProvider {
    let address: String
    func fetchChanges(cursor: String?) async throws -> (messages: [FetchedMessage], cursor: String?) { ([], cursor) }
    func archive(_ id: String) async throws {}
    func markRead(_ id: String, read: Bool) async throws {}
    func applyLabel(_ id: String, label: String) async throws {}
    func send(to: String, subject: String, body: String, inReplyTo: String?) async throws {}
    func fetchSent(since: Date) async throws -> [FetchedMessage] { [] }
}

extension String {
    var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func parseFrom(_ raw: String) -> (String, String) {
    if let lt = raw.firstIndex(of: "<"), let gt = raw.firstIndex(of: ">") {
        let name = raw[..<lt].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
        return (name, String(raw[raw.index(after: lt)..<gt]))
    }
    return (raw, raw)
}
