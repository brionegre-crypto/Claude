import Foundation

/// Common surface over Gmail API, Microsoft Graph and iCloud IMAP.
struct FetchedMessage {
    var providerId, threadId, from, fromName, subject, snippet, body: String
    var date: Date
    var isRead: Bool
    var html: String? = nil
    var messageIdHeader: String? = nil      // RFC Message-ID, for threading replies
    var to: String = ""
    var cc: String = ""
    var isStarred: Bool = false
    var hasAttachments: Bool = false
}

struct MailAttachment: Identifiable, Hashable {
    var id: String                          // provider attachment id
    var filename: String
    var mimeType: String
    var size: Int
}

struct OutgoingAttachment: Identifiable, Hashable {
    var id = UUID()
    var filename: String
    var mimeType: String
    var data: Data
}

/// Set when replying, so the message lands in the same thread on the server.
struct ReplyContext: Hashable {
    var providerMessageId: String
    var threadId: String
    var messageIdHeader: String?
    var replyAll: Bool
}

struct OutgoingMail {
    var to: [String]
    var cc: [String] = []
    var bcc: [String] = []
    var subject: String
    var body: String
    var replyTo: ReplyContext? = nil
    var attachments: [OutgoingAttachment] = []
}

protocol MailProvider {
    /// Incremental fetch from `cursor`; returns new messages and the next cursor.
    func fetchChanges(cursor: String?) async throws -> (messages: [FetchedMessage], cursor: String?)
    func archive(_ providerId: String) async throws
    func markRead(_ providerId: String, read: Bool) async throws
    func setStarred(_ providerId: String, starred: Bool) async throws
    func trash(_ providerId: String) async throws
    /// Writes Keel's AI category back as a label/category so other clients (and Claude Duet) see it.
    func applyLabel(_ providerId: String, label: String) async throws
    func send(_ mail: OutgoingMail) async throws
    /// Emails YOU sent since `since` — the promise tracker and Sent mailbox read these. `from` holds the first recipient.
    func fetchSent(since: Date) async throws -> [FetchedMessage]
    /// Server-side search across ALL mail (not just what's synced to the phone).
    func search(_ query: String) async throws -> [FetchedMessage]
    func attachments(for providerId: String) async throws -> [MailAttachment]
    func download(_ attachment: MailAttachment, messageId: String) async throws -> Data
}

extension MailProvider {
    /// Simple form used by quick replies and promise follow-ups.
    func send(to: String, subject: String, body: String, inReplyTo: ReplyContext?) async throws {
        try await send(OutgoingMail(to: [to], subject: subject, body: body, replyTo: inReplyTo))
    }
}

enum MailProviderFactory {
    @MainActor static func make(for account: MailAccount) -> MailProvider {
        switch account.provider {
        case .gmail: GmailProvider(account: account.id)
        case .outlook: OutlookProvider(account: account.id)
        case .icloud: ICloudMailProvider(accountId: account.id, address: account.address)
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
            let list = try await api.json(URL(string: "\(base)/messages?maxResults=100&q=in:inbox%20newer_than:14d")!)
            ids = (list["messages"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            let profile = try await api.json(URL(string: "\(base)/profile")!)
            newCursor = profile["historyId"] as? String
        }
        var out: [FetchedMessage] = []
        for id in ids.prefix(200) {
            let m = try await api.json(URL(string: "\(base)/messages/\(id)?format=full")!)
            // History includes sent mail too; the inbox only shows what's in INBOX.
            guard (m["labelIds"] as? [String] ?? []).contains("INBOX") else { continue }
            out.append(Self.parse(m))
        }
        return (out, newCursor)
    }

    static func parse(_ m: [String: Any]) -> FetchedMessage {
        let payload = m["payload"] as? [String: Any] ?? [:]
        let headers = (payload["headers"] as? [[String: String]] ?? []).reduce(into: [String: String]()) { $0[$1["name"]?.lowercased() ?? ""] = $1["value"] }
        let (name, email) = parseFrom(headers["from"] ?? "")
        let labels = m["labelIds"] as? [String] ?? []
        let ms = Double(m["internalDate"] as? String ?? "0") ?? 0
        let html = body(payload, mime: "text/html")
        var plain = body(payload, mime: "text/plain") ?? ""
        if plain.isEmpty, let html { plain = html.strippingHTML }
        return FetchedMessage(providerId: m["id"] as? String ?? "", threadId: m["threadId"] as? String ?? "",
                              from: email, fromName: name, subject: headers["subject"] ?? "(no subject)",
                              snippet: m["snippet"] as? String ?? "", body: plain,
                              date: Date(timeIntervalSince1970: ms / 1000), isRead: !labels.contains("UNREAD"),
                              html: html, messageIdHeader: headers["message-id"],
                              to: headers["to"] ?? "", cc: headers["cc"] ?? "",
                              isStarred: labels.contains("STARRED"),
                              hasAttachments: !attachmentParts(payload).isEmpty)
    }

    /// Kept for callers that only want plain text.
    static func plainBody(_ part: [String: Any]) -> String { body(part, mime: "text/plain") ?? "" }

    static func body(_ part: [String: Any], mime: String) -> String? {
        if part["mimeType"] as? String == mime, (part["filename"] as? String ?? "").isEmpty,
           let data = (part["body"] as? [String: Any])?["data"] as? String, let d = Data(base64URLEncoded: data) {
            return String(decoding: d, as: UTF8.self)
        }
        for p in part["parts"] as? [[String: Any]] ?? [] { if let b = body(p, mime: mime), !b.isEmpty { return b } }
        return nil
    }

    static func attachmentParts(_ part: [String: Any]) -> [MailAttachment] {
        var out: [MailAttachment] = []
        let filename = part["filename"] as? String ?? ""
        if !filename.isEmpty, let b = part["body"] as? [String: Any], let attId = b["attachmentId"] as? String {
            out.append(MailAttachment(id: attId, filename: filename, mimeType: part["mimeType"] as? String ?? "application/octet-stream",
                                      size: b["size"] as? Int ?? 0))
        }
        for p in part["parts"] as? [[String: Any]] ?? [] { out += attachmentParts(p) }
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

    private func modify(_ id: String, add: [String] = [], remove: [String] = []) async throws {
        _ = try await api.json(URL(string: "\(base)/messages/\(id)/modify")!, method: "POST",
                               body: ["addLabelIds": add, "removeLabelIds": remove] as [String: Any])
    }

    func archive(_ id: String) async throws { try await modify(id, remove: ["INBOX"]) }
    func markRead(_ id: String, read: Bool) async throws { try await read ? modify(id, remove: ["UNREAD"]) : modify(id, add: ["UNREAD"]) }
    func setStarred(_ id: String, starred: Bool) async throws { try await starred ? modify(id, add: ["STARRED"]) : modify(id, remove: ["STARRED"]) }
    func trash(_ id: String) async throws { _ = try await api.json(URL(string: "\(base)/messages/\(id)/trash")!, method: "POST") }

    func applyLabel(_ id: String, label: String) async throws {
        // Labels must exist first: find or create "Keel/<label>", then apply its id.
        let name = "Keel/\(label.capitalized)"
        let list = try await api.json(URL(string: "\(base)/labels")!)
        var labelId = (list["labels"] as? [[String: Any]] ?? []).first { $0["name"] as? String == name }?["id"] as? String
        if labelId == nil {
            let created = try await api.json(URL(string: "\(base)/labels")!, method: "POST",
                                             body: ["name": name, "labelListVisibility": "labelShow", "messageListVisibility": "show"])
            labelId = created["id"] as? String
        }
        if let labelId { try await modify(id, add: [labelId]) }
    }

    func send(_ mail: OutgoingMail) async throws {
        var body: [String: Any] = ["raw": MIME.build(mail).base64URL]
        if let r = mail.replyTo { body["threadId"] = r.threadId }
        _ = try await api.json(URL(string: "\(base)/messages/send")!, method: "POST", body: body)
    }

    func fetchSent(since: Date) async throws -> [FetchedMessage] {
        let after = Int(since.timeIntervalSince1970)
        let list = try await api.json(URL(string: "\(base)/messages?maxResults=50&q=in:sent%20after:\(after)")!)
        var out: [FetchedMessage] = []
        for id in (list["messages"] as? [[String: Any]] ?? []).compactMap({ $0["id"] as? String }) {
            let m = try await api.json(URL(string: "\(base)/messages/\(id)?format=full")!)
            var f = Self.parse(m)
            let (name, email) = parseFrom(f.to.components(separatedBy: ",").first ?? f.to)
            f.from = email; f.fromName = name
            f.body = Self.stripQuotedReply(f.body)
            out.append(f)
        }
        return out
    }

    func search(_ query: String) async throws -> [FetchedMessage] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let list = try await api.json(URL(string: "\(base)/messages?maxResults=25&q=\(q)")!)
        var out: [FetchedMessage] = []
        for id in (list["messages"] as? [[String: Any]] ?? []).compactMap({ $0["id"] as? String }) {
            out.append(Self.parse(try await api.json(URL(string: "\(base)/messages/\(id)?format=full")!)))
        }
        return out
    }

    func attachments(for id: String) async throws -> [MailAttachment] {
        let m = try await api.json(URL(string: "\(base)/messages/\(id)?format=full")!)
        return Self.attachmentParts(m["payload"] as? [String: Any] ?? [:])
    }

    func download(_ attachment: MailAttachment, messageId: String) async throws -> Data {
        let r = try await api.json(URL(string: "\(base)/messages/\(messageId)/attachments/\(attachment.id)")!)
        guard let s = r["data"] as? String, let d = Data(base64URLEncoded: s) else { throw URLError(.cannotDecodeContentData) }
        return d
    }
}

// MARK: - Outlook / Microsoft 365 (Graph, delta query)

struct OutlookProvider: MailProvider {
    let account: String
    private var api: AuthedClient { AuthedClient(account: account, cfg: OAuthManager.microsoft) }
    private let base = "https://graph.microsoft.com/v1.0/me"
    private static let select = "subject,from,toRecipients,ccRecipients,bodyPreview,body,receivedDateTime,isRead,conversationId,internetMessageId,flag,hasAttachments"

    static func parse(_ m: [String: Any]) -> FetchedMessage {
        let from = ((m["from"] as? [String: Any])?["emailAddress"] as? [String: Any]) ?? [:]
        let bodyObj = m["body"] as? [String: Any] ?? [:]
        let content = bodyObj["content"] as? String ?? ""
        let isHTML = (bodyObj["contentType"] as? String)?.lowercased() == "html"
        func addresses(_ key: String) -> String {
            ((m[key] as? [[String: Any]]) ?? []).compactMap { ($0["emailAddress"] as? [String: Any])?["address"] as? String }.joined(separator: ", ")
        }
        return FetchedMessage(
            providerId: m["id"] as? String ?? "", threadId: m["conversationId"] as? String ?? "",
            from: from["address"] as? String ?? "", fromName: from["name"] as? String ?? "",
            subject: m["subject"] as? String ?? "", snippet: m["bodyPreview"] as? String ?? "",
            body: isHTML ? content.strippingHTML : content,
            date: ISO8601DateFormatter().date(from: m["receivedDateTime"] as? String ?? "") ?? Date(),
            isRead: m["isRead"] as? Bool ?? false,
            html: isHTML ? content : nil, messageIdHeader: m["internetMessageId"] as? String,
            to: addresses("toRecipients"), cc: addresses("ccRecipients"),
            isStarred: ((m["flag"] as? [String: Any])?["flagStatus"] as? String) == "flagged",
            hasAttachments: m["hasAttachments"] as? Bool ?? false)
    }

    func fetchChanges(cursor: String?) async throws -> (messages: [FetchedMessage], cursor: String?) {
        var url = URL(string: cursor ?? "\(base)/mailFolders/inbox/messages/delta?$select=\(Self.select)")!
        var out: [FetchedMessage] = []
        while true {
            let page = try await api.json(url)
            for m in page["value"] as? [[String: Any]] ?? [] where m["@removed"] == nil { out.append(Self.parse(m)) }
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
    func setStarred(_ id: String, starred: Bool) async throws {
        _ = try await api.json(URL(string: "\(base)/messages/\(id)")!, method: "PATCH",
                               body: ["flag": ["flagStatus": starred ? "flagged" : "notFlagged"]])
    }
    func trash(_ id: String) async throws {
        _ = try await api.json(URL(string: "\(base)/messages/\(id)/move")!, method: "POST", body: ["destinationId": "deleteditems"])
    }
    func applyLabel(_ id: String, label: String) async throws {
        _ = try await api.json(URL(string: "\(base)/messages/\(id)")!, method: "PATCH", body: ["categories": ["Keel/\(label)"]])
    }

    private static func recipients(_ list: [String]) -> [[String: Any]] {
        list.map { ["emailAddress": ["address": $0]] }
    }

    private static func attachmentsJSON(_ list: [OutgoingAttachment]) -> [[String: Any]] {
        list.map { ["@odata.type": "#microsoft.graph.fileAttachment", "name": $0.filename,
                    "contentType": $0.mimeType, "contentBytes": $0.data.base64EncodedString()] }
    }

    func send(_ mail: OutgoingMail) async throws {
        var message: [String: Any] = [
            "toRecipients": Self.recipients(mail.to),
            "ccRecipients": Self.recipients(mail.cc),
            "bccRecipients": Self.recipients(mail.bcc),
            "attachments": Self.attachmentsJSON(mail.attachments),
        ]
        if let r = mail.replyTo {
            // /reply keeps the conversation threaded on the server.
            let action = r.replyAll ? "replyAll" : "reply"
            _ = try await api.json(URL(string: "\(base)/messages/\(r.providerMessageId)/\(action)")!, method: "POST",
                                   body: ["message": message, "comment": mail.body] as [String: Any])
        } else {
            message["subject"] = mail.subject
            message["body"] = ["contentType": "Text", "content": mail.body]
            _ = try await api.json(URL(string: "\(base)/sendMail")!, method: "POST", body: ["message": message] as [String: Any])
        }
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

    func search(_ query: String) async throws -> [FetchedMessage] {
        let q = "\"\(query.replacingOccurrences(of: "\"", with: ""))\"".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let page = try await api.json(URL(string: "\(base)/messages?$search=\(q)&$top=25&$select=\(Self.select)")!)
        return (page["value"] as? [[String: Any]] ?? []).map(Self.parse)
    }

    func attachments(for id: String) async throws -> [MailAttachment] {
        let page = try await api.json(URL(string: "\(base)/messages/\(id)/attachments?$select=id,name,contentType,size")!)
        return (page["value"] as? [[String: Any]] ?? []).map {
            MailAttachment(id: $0["id"] as? String ?? "", filename: $0["name"] as? String ?? "attachment",
                           mimeType: $0["contentType"] as? String ?? "application/octet-stream", size: $0["size"] as? Int ?? 0)
        }
    }

    func download(_ attachment: MailAttachment, messageId: String) async throws -> Data {
        let r = try await api.json(URL(string: "\(base)/messages/\(messageId)/attachments/\(attachment.id)")!)
        guard let s = r["contentBytes"] as? String, let d = Data(base64Encoded: s) else { throw URLError(.cannotDecodeContentData) }
        return d
    }
}

// iCloud Mail (IMAP/SMTP) lives in ICloudMail.swift.

// MARK: - MIME (RFC 5322) for Gmail sends, with attachments and threading headers

enum MIME {
    /// `from` is set for SMTP (iCloud); Gmail's API fills From, Date and Message-ID itself.
    static func build(_ mail: OutgoingMail, from: String? = nil) -> Data {
        var h = ""
        if let from {
            h += "From: \(from)\r\nDate: \(RFC822.headerDate.string(from: Date()))\r\n"
            h += "Message-ID: <\(UUID().uuidString)@keel.app>\r\n"
        }
        h += "To: \(mail.to.joined(separator: ", "))\r\n"
        if !mail.cc.isEmpty { h += "Cc: \(mail.cc.joined(separator: ", "))\r\n" }
        if !mail.bcc.isEmpty { h += "Bcc: \(mail.bcc.joined(separator: ", "))\r\n" }
        h += "Subject: \(encodeHeader(mail.subject))\r\nMIME-Version: 1.0\r\n"
        if let ref = mail.replyTo?.messageIdHeader { h += "In-Reply-To: \(ref)\r\nReferences: \(ref)\r\n" }

        let textPart = "Content-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n\r\n" + wrap(Data(mail.body.utf8).base64EncodedString())
        guard !mail.attachments.isEmpty else {
            return Data((h + textPart).utf8)
        }
        let boundary = "keel-\(UUID().uuidString)"
        var s = h + "Content-Type: multipart/mixed; boundary=\"\(boundary)\"\r\n\r\n"
        s += "--\(boundary)\r\n" + textPart + "\r\n"
        for a in mail.attachments {
            let name = a.filename.replacingOccurrences(of: "\"", with: "")
            s += "--\(boundary)\r\nContent-Type: \(a.mimeType); name=\"\(name)\"\r\n"
            s += "Content-Disposition: attachment; filename=\"\(name)\"\r\nContent-Transfer-Encoding: base64\r\n\r\n"
            s += wrap(a.data.base64EncodedString()) + "\r\n"
        }
        s += "--\(boundary)--\r\n"
        return Data(s.utf8)
    }

    /// Non-ASCII subjects must be RFC 2047 encoded.
    static func encodeHeader(_ s: String) -> String {
        s.allSatisfy(\.isASCII) ? s : "=?UTF-8?B?\(Data(s.utf8).base64EncodedString())?="
    }

    static func wrap(_ b64: String) -> String {
        var out = ""; var i = b64.startIndex
        while i < b64.endIndex {
            let j = b64.index(i, offsetBy: 76, limitedBy: b64.endIndex) ?? b64.endIndex
            out += String(b64[i..<j]) + "\r\n"; i = j
        }
        return out
    }
}

extension Data {
    init?(base64URLEncoded s: String) {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b += String(repeating: "=", count: (4 - b.count % 4) % 4)
        self.init(base64Encoded: b)
    }
}

extension String {
    var strippingHTML: String {
        replacingOccurrences(of: "<(style|script)[^>]*>[\\s\\S]*?</(style|script)>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<br\\s*/?>|</p>|</div>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n\\s*\\n\\s*\\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

func parseFrom(_ raw: String) -> (String, String) {
    if let lt = raw.firstIndex(of: "<"), let gt = raw.firstIndex(of: ">") {
        let name = raw[..<lt].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
        return (name, String(raw[raw.index(after: lt)..<gt]))
    }
    let t = raw.trimmingCharacters(in: .whitespaces)
    return (t, t)
}
