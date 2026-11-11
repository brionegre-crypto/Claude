import Foundation

// iCloud Mail has no web API, so Keel speaks the standard mail protocols itself:
// IMAP (imap.mail.me.com:993, TLS) to read and organize, SMTP (smtp.mail.me.com:587, STARTTLS) to send.
// Sign-in uses an app-specific password from account.apple.com, kept only in the Keychain.

enum MailNetError: LocalizedError {
    case closed, server(String), auth
    var errorDescription: String? {
        switch self {
        case .closed: "The mail server closed the connection."
        case .server(let msg): "Mail server: \(msg)"
        case .auth: "iCloud rejected the sign-in. Check the email address and app-specific password."
        }
    }
}

/// Reads lines and fixed-size literals over a TLS stream.
final class MailSocket {
    private let task: URLSessionStreamTask
    private var buffer = Data()

    init(host: String, port: Int, tlsNow: Bool) {
        task = URLSession.shared.streamTask(withHostName: host, port: port)
        task.resume()
        if tlsNow { task.startSecureConnection() }
    }

    func startTLS() { task.startSecureConnection() }

    func close() {
        task.closeWrite()
        task.closeRead()
        task.cancel()
    }

    func write(_ s: String) async throws { try await task.write(Data(s.utf8), timeout: 60) }
    func write(_ d: Data) async throws { try await task.write(d, timeout: 120) }

    private func fill() async throws {
        let (data, eof) = try await task.readData(ofMinLength: 1, maxLength: 1 << 16, timeout: 60)
        if let data, !data.isEmpty { buffer.append(data) } else if eof { throw MailNetError.closed }
    }

    func readLine() async throws -> String {
        while true {
            if let r = buffer.range(of: Data([13, 10])) {
                let line = buffer.subdata(in: buffer.startIndex..<r.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<r.upperBound)
                return String(decoding: line, as: UTF8.self)
            }
            try await fill()
        }
    }

    func readBytes(_ n: Int) async throws -> Data {
        while buffer.count < n { try await fill() }
        let out = Data(buffer.prefix(n))
        buffer.removeFirst(n)
        return out
    }
}

// MARK: - IMAP

struct IMAPFetch {
    var uid: Int
    var flags: [String]
    var internalDate: Date?
    var raw: Data
}

final class IMAPClient {
    private let socket: MailSocket
    private var tagCounter = 0

    private init(socket: MailSocket) { self.socket = socket }

    static func connect(user: String, password: String) async throws -> IMAPClient {
        let c = IMAPClient(socket: MailSocket(host: "imap.mail.me.com", port: 993, tlsNow: true))
        _ = try await c.socket.readLine()                       // server greeting
        do {
            try await c.run("LOGIN \(quote(user)) \(quote(password))")
        } catch MailNetError.server {
            throw MailNetError.auth
        }
        return c
    }

    func logout() async {
        _ = try? await run("LOGOUT")
        socket.close()
    }

    /// Sends a tagged command and collects untagged responses (with any literals) until the tagged reply.
    @discardableResult
    func run(_ command: String) async throws -> [(line: String, literals: [Data])] {
        tagCounter += 1
        let tag = "K\(tagCounter)"
        try await socket.write("\(tag) \(command)\r\n")
        var out: [(line: String, literals: [Data])] = []
        while true {
            var line = try await socket.readLine()
            if line.hasPrefix(tag + " ") {
                let status = line.dropFirst(tag.count + 1)
                if status.hasPrefix("OK") { return out }
                throw MailNetError.server(String(status))
            }
            var literals: [Data] = []
            while let n = Self.literalLength(line) {
                literals.append(try await socket.readBytes(n))
                line += " \u{1}" + (try await socket.readLine())   // \u{1} marks where a literal sat
            }
            out.append((line, literals))
        }
    }

    /// Returns (UIDVALIDITY, UIDNEXT).
    @discardableResult
    func select(_ mailbox: String) async throws -> (Int, Int) {
        let lines = try await run("SELECT \(Self.quote(mailbox))").map(\.line)
        func number(_ key: String) -> Int {
            for l in lines {
                if let r = l.range(of: "\(key) (\\d+)", options: .regularExpression) {
                    return Int(l[r].split(separator: " ").last ?? "") ?? 0
                }
            }
            return 0
        }
        return (number("UIDVALIDITY"), number("UIDNEXT"))
    }

    func search(_ criteria: String) async throws -> [Int] {
        let lines = try await run("UID SEARCH \(criteria)").map(\.line)
        return lines.filter { $0.hasPrefix("* SEARCH") }
            .flatMap { $0.dropFirst(8).split(separator: " ").compactMap { Int($0) } }
    }

    /// `partial` caps each message at 400 KB (enough for text and HTML; attachments are fetched on demand).
    func fetch(_ uids: [Int], partial: Bool = true) async throws -> [IMAPFetch] {
        guard !uids.isEmpty else { return [] }
        let body = partial ? "BODY.PEEK[]<0.400000>" : "BODY.PEEK[]"
        let responses = try await run("UID FETCH \(uids.map(String.init).joined(separator: ",")) (UID FLAGS INTERNALDATE \(body))")
        return responses.compactMap { r in
            guard r.line.contains(" FETCH ("), let raw = r.literals.first else { return nil }
            func match(_ pattern: String) -> String? {
                guard let range = r.line.range(of: pattern, options: .regularExpression) else { return nil }
                return String(r.line[range])
            }
            guard let uidText = match(#"UID \d+"#), let uid = Int(uidText.dropFirst(4)) else { return nil }
            let flags = match(#"FLAGS \([^)]*\)"#).map { $0.dropFirst(7).dropLast().split(separator: " ").map(String.init) } ?? []
            let date = match(#"INTERNALDATE "[^"]+""#).flatMap { Self.internalDate.date(from: String($0.dropFirst(14).dropLast()).trimmingCharacters(in: .whitespaces)) }
            return IMAPFetch(uid: uid, flags: flags, internalDate: date, raw: raw)
        }
    }

    func store(_ uid: Int, flag: String, add: Bool) async throws {
        try await run("UID STORE \(uid) \(add ? "+" : "-")FLAGS.SILENT (\(flag))")
    }

    func move(_ uid: Int, to mailbox: String) async throws {
        try await run("UID MOVE \(uid) \(Self.quote(mailbox))")
    }

    /// Saves a sent message into a mailbox (iCloud doesn't file SMTP sends into Sent by itself).
    func append(_ data: Data, to mailbox: String) async throws {
        tagCounter += 1
        let tag = "K\(tagCounter)"
        try await socket.write("\(tag) APPEND \(Self.quote(mailbox)) (\\Seen) {\(data.count)}\r\n")
        let ready = try await socket.readLine()
        guard ready.hasPrefix("+") else { throw MailNetError.server(ready) }
        try await socket.write(data)
        try await socket.write("\r\n")
        while true {
            let line = try await socket.readLine()
            if line.hasPrefix(tag + " ") {
                if line.dropFirst(tag.count + 1).hasPrefix("OK") { return }
                throw MailNetError.server(line)
            }
        }
    }

    static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func literalLength(_ line: String) -> Int? {
        guard line.hasSuffix("}"), let open = line.lastIndex(of: "{") else { return nil }
        return Int(line[line.index(after: open)..<line.index(before: line.endIndex)])
    }

    static let searchDate: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "dd-MMM-yyyy"; return f
    }()

    static let internalDate: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "d-MMM-yyyy HH:mm:ss Z"; return f
    }()
}

// MARK: - SMTP

enum SMTPClient {
    /// Sends via iCloud SMTP and returns the exact message bytes (so they can be filed in Sent).
    static func send(_ mail: OutgoingMail, from: String, password: String) async throws -> Data {
        let s = MailSocket(host: "smtp.mail.me.com", port: 587, tlsNow: false)
        defer { s.close() }

        func expect(_ code: String) async throws {
            while true {
                let line = try await s.readLine()
                let isLast = line.count < 4 || line[line.index(line.startIndex, offsetBy: 3)] != "-"
                if isLast {
                    guard line.hasPrefix(code) else { throw MailNetError.server(line) }
                    return
                }
            }
        }

        try await expect("220")
        try await s.write("EHLO keel.app\r\n"); try await expect("250")
        try await s.write("STARTTLS\r\n"); try await expect("220")
        s.startTLS()
        try await s.write("EHLO keel.app\r\n"); try await expect("250")
        let auth = Data("\u{0}\(from)\u{0}\(password)".utf8).base64EncodedString()
        try await s.write("AUTH PLAIN \(auth)\r\n")
        do { try await expect("235") } catch { throw MailNetError.auth }
        try await s.write("MAIL FROM:<\(from)>\r\n"); try await expect("250")
        for rcpt in mail.to + mail.cc + mail.bcc {
            try await s.write("RCPT TO:<\(rcpt)>\r\n"); try await expect("25")
        }
        try await s.write("DATA\r\n"); try await expect("354")

        var visible = mail
        visible.bcc = []                                   // Bcc must never appear in the message itself
        let message = MIME.build(visible, from: from)
        var text = String(decoding: message, as: UTF8.self).replacingOccurrences(of: "\r\n.", with: "\r\n..")
        if text.hasPrefix(".") { text = "." + text }
        try await s.write(text + "\r\n.\r\n"); try await expect("250")
        try? await s.write("QUIT\r\n")
        return message
    }
}

// MARK: - RFC 822 / MIME parsing

struct ParsedMail {
    var headers: [String: String] = [:]
    var text: String?
    var html: String?
    var attachments: [(info: MailAttachment, data: Data)] = []
}

enum RFC822 {
    static func parse(_ raw: Data) -> ParsedMail {
        var result = ParsedMail()
        let (headers, body) = split(raw)
        result.headers = headers
        walk(headers: headers, body: body, path: "1", into: &result)
        return result
    }

    static func split(_ data: Data) -> ([String: String], Data) {
        let sep = data.range(of: Data("\r\n\r\n".utf8)) ?? data.range(of: Data("\n\n".utf8))
        let headerData = sep.map { data.subdata(in: data.startIndex..<$0.lowerBound) } ?? data
        let body = sep.map { data.subdata(in: $0.upperBound..<data.endIndex) } ?? Data()
        return (headers(String(decoding: headerData, as: UTF8.self)), body)
    }

    static func headers(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        var current: (String, String)?
        for line in text.components(separatedBy: .newlines) {
            if line.first == " " || line.first == "\t", let c = current {
                current = (c.0, c.1 + " " + line.trimmingCharacters(in: .whitespaces))
            } else if let colon = line.firstIndex(of: ":") {
                if let c = current, out[c.0] == nil { out[c.0] = c.1 }
                current = (line[..<colon].lowercased(), line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
            }
        }
        if let c = current, out[c.0] == nil { out[c.0] = c.1 }
        return out
    }

    static func param(_ header: String?, _ name: String) -> String? {
        guard let header else { return nil }
        let pattern = "(?i)\(name)\\*?=\\s*(\"[^\"]*\"|[^;\\s]+)"
        guard let r = header.range(of: pattern, options: .regularExpression) else { return nil }
        let value = header[r].split(separator: "=", maxSplits: 1).last.map(String.init) ?? ""
        let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        // RFC 2231 (filename*=utf-8''name.pdf)
        if let quoteEnd = cleaned.range(of: "''") { return cleaned[quoteEnd.upperBound...].removingPercentEncoding }
        return decodeWords(cleaned)
    }

    private static func walk(headers: [String: String], body: Data, path: String, into result: inout ParsedMail) {
        let type = headers["content-type"] ?? "text/plain"
        let mime = type.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? "text/plain"

        if mime.hasPrefix("multipart/"), let boundary = param(type, "boundary") {
            let delimiter = Data("--\(boundary)".utf8)
            var pieces: [Data] = []
            var searchStart = body.startIndex
            var partStart: Data.Index?
            while let r = body.range(of: delimiter, in: searchStart..<body.endIndex) {
                if let s = partStart { pieces.append(body.subdata(in: s..<r.lowerBound)) }
                partStart = r.upperBound
                searchStart = r.upperBound
                if body[r.upperBound...].starts(with: Data("--".utf8)) { break }
            }
            for (i, piece) in pieces.enumerated() {
                let trimmed = piece.drop { $0 == 13 || $0 == 10 }
                let (h, b) = split(Data(trimmed))
                walk(headers: h, body: b, path: "\(path).\(i + 1)", into: &result)
            }
            return
        }

        let decoded = decodeTransfer(body, encoding: headers["content-transfer-encoding"])
        let disposition = headers["content-disposition"]?.lowercased() ?? ""
        let filename = param(headers["content-disposition"], "filename") ?? param(type, "name")
        let isAttachment = disposition.hasPrefix("attachment") || (filename != nil && !mime.hasPrefix("text/"))

        if isAttachment {
            let info = MailAttachment(id: path, filename: filename ?? "attachment", mimeType: mime, size: decoded.count)
            result.attachments.append((info, decoded))
        } else if mime == "text/plain", result.text == nil {
            result.text = string(decoded, charset: param(type, "charset"))
        } else if mime == "text/html", result.html == nil {
            result.html = string(decoded, charset: param(type, "charset"))
        }
    }

    static func decodeTransfer(_ data: Data, encoding: String?) -> Data {
        switch encoding?.lowercased().trimmingCharacters(in: .whitespaces) {
        case "base64":
            let clean = String(decoding: data, as: UTF8.self).components(separatedBy: .whitespacesAndNewlines).joined()
            return Data(base64Encoded: clean, options: .ignoreUnknownCharacters) ?? data
        case "quoted-printable":
            return quotedPrintable(data)
        default:
            return data
        }
    }

    static func quotedPrintable(_ data: Data, underscoreIsSpace: Bool = false) -> Data {
        var out = Data()
        let bytes = [UInt8](data)
        var i = 0
        func hex(_ b: UInt8) -> UInt8? {
            switch b { case 48...57: b - 48; case 65...70: b - 55; case 97...102: b - 87; default: nil }
        }
        while i < bytes.count {
            let b = bytes[i]
            if b == 61 {                                                   // "="
                if i + 1 < bytes.count, bytes[i + 1] == 13 || bytes[i + 1] == 10 {   // soft line break
                    i += (i + 2 < bytes.count && bytes[i + 1] == 13 && bytes[i + 2] == 10) ? 3 : 2
                    continue
                }
                if i + 2 < bytes.count, let h = hex(bytes[i + 1]), let l = hex(bytes[i + 2]) {
                    out.append(h << 4 | l); i += 3; continue
                }
            }
            out.append(underscoreIsSpace && b == 95 ? 32 : b)
            i += 1
        }
        return out
    }

    static func encoding(_ charset: String?) -> String.Encoding {
        guard let c = charset?.lowercased(), !c.isEmpty else { return .utf8 }
        let cf = CFStringConvertIANACharSetNameToEncoding(c as CFString)
        guard cf != kCFStringEncodingInvalidId else { return .utf8 }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }

    static func string(_ data: Data, charset: String?) -> String {
        String(data: data, encoding: encoding(charset)) ?? String(decoding: data, as: UTF8.self)
    }

    /// RFC 2047 encoded words: =?utf-8?B?…?= / =?iso-8859-1?Q?…?=
    static func decodeWords(_ s: String) -> String {
        guard s.contains("=?") else { return s }
        let joined = s.replacingOccurrences(of: #"\?=\s+=\?"#, with: "?==?", options: .regularExpression)
        var out = ""
        var rest = Substring(joined)
        while let r = rest.range(of: #"=\?[^?]+\?[BbQq]\?[^?]*\?="#, options: .regularExpression) {
            out += rest[..<r.lowerBound]
            let parts = rest[r].dropFirst(2).dropLast(2).split(separator: "?", maxSplits: 2, omittingEmptySubsequences: false)
            if parts.count == 3 {
                let payload = Data(parts[2].utf8)
                let data = parts[1].uppercased() == "B"
                    ? (Data(base64Encoded: String(parts[2]), options: .ignoreUnknownCharacters) ?? payload)
                    : quotedPrintable(payload, underscoreIsSpace: true)
                out += string(data, charset: String(parts[0]))
            }
            rest = rest[r.upperBound...]
        }
        return out + rest
    }

    static let headerDate: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"; return f
    }()
}

// MARK: - Provider

struct ICloudMailProvider: MailProvider {
    let accountId: String
    let address: String

    static let inbox = "INBOX", sentBox = "Sent Messages", archiveBox = "Archive", trashBox = "Deleted Messages"

    private var password: String { KeychainStore.read("imap.\(accountId)") ?? "" }

    /// Checks the address + app-specific password before saving the account.
    static func verify(address: String, password: String) async throws {
        let c = try await IMAPClient.connect(user: address, password: password)
        await c.logout()
    }

    private func session<T>(_ work: (IMAPClient) async throws -> T) async throws -> T {
        let c = try await IMAPClient.connect(user: address, password: password)
        do {
            let result = try await work(c)
            await c.logout()
            return result
        } catch {
            await c.logout()
            throw error
        }
    }

    /// Provider ids are the IMAP UID; Sent-folder messages are prefixed "S:".
    private func locate(_ id: String) -> (mailbox: String, uid: Int) {
        id.hasPrefix("S:") ? (Self.sentBox, Int(id.dropFirst(2)) ?? 0) : (Self.inbox, Int(id) ?? 0)
    }

    private func message(_ f: IMAPFetch, prefix: String = "") -> FetchedMessage {
        let p = RFC822.parse(f.raw)
        let h = p.headers
        let (name, email) = parseFrom(RFC822.decodeWords(h["from"] ?? ""))
        let plain = p.text ?? p.html?.strippingHTML ?? ""
        let messageId = h["message-id"]
        let thread = (h["references"]?.split(separator: " ").first.map(String.init)) ?? h["in-reply-to"] ?? messageId ?? "\(f.uid)"
        return FetchedMessage(
            providerId: "\(prefix)\(f.uid)", threadId: thread, from: email, fromName: name,
            subject: RFC822.decodeWords(h["subject"] ?? "(no subject)"),
            snippet: String(plain.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(160)),
            body: plain,
            date: f.internalDate ?? h["date"].flatMap { RFC822.headerDate.date(from: $0) } ?? Date(),
            isRead: f.flags.contains("\\Seen"), html: p.html, messageIdHeader: messageId,
            to: RFC822.decodeWords(h["to"] ?? ""), cc: RFC822.decodeWords(h["cc"] ?? ""),
            isStarred: f.flags.contains("\\Flagged"),
            hasAttachments: !p.attachments.isEmpty || (h["content-type"]?.lowercased().contains("multipart/mixed") ?? false),
            unsubscribe: h["list-unsubscribe"],
            unsubscribeOneClick: h["list-unsubscribe-post"]?.lowercased().contains("one-click") ?? false)
    }

    private func since(days: Int) -> String {
        IMAPClient.searchDate.string(from: Date().addingTimeInterval(-Double(days) * 86_400))
    }

    func fetchChanges(cursor: String?) async throws -> (messages: [FetchedMessage], cursor: String?) {
        try await session { c in
            let (validity, _) = try await c.select(Self.inbox)
            let parts = cursor?.split(separator: ":").compactMap { Int($0) } ?? []
            let resume = parts.count == 2 && parts[0] == validity
            var uids: [Int]
            if resume {
                uids = try await c.search("UID \(parts[1] + 1):*").filter { $0 > parts[1] }
            } else {
                uids = try await c.search("SINCE \(since(days: 14))")
            }
            uids = Array(uids.sorted().suffix(150))
            var out: [FetchedMessage] = []
            var i = 0
            while i < uids.count {
                let chunk = Array(uids[i..<min(i + 20, uids.count)])
                out += try await c.fetch(chunk).map { message($0) }
                i += 20
            }
            let last = max(uids.max() ?? 0, resume ? parts[1] : 0)
            return (out, "\(validity):\(last)")
        }
    }

    func archive(_ id: String) async throws {
        let (box, uid) = locate(id)
        try await session { c in try await c.select(box); try await c.move(uid, to: Self.archiveBox) }
    }

    func trash(_ id: String) async throws {
        let (box, uid) = locate(id)
        try await session { c in try await c.select(box); try await c.move(uid, to: Self.trashBox) }
    }

    func markRead(_ id: String, read: Bool) async throws {
        let (box, uid) = locate(id)
        try await session { c in try await c.select(box); try await c.store(uid, flag: "\\Seen", add: read) }
    }

    func setStarred(_ id: String, starred: Bool) async throws {
        let (box, uid) = locate(id)
        try await session { c in try await c.select(box); try await c.store(uid, flag: "\\Flagged", add: starred) }
    }

    func applyLabel(_ id: String, label: String) async throws {}   // iCloud has no labels; sorting stays in Keel

    func send(_ mail: OutgoingMail) async throws {
        let raw = try await SMTPClient.send(mail, from: address, password: password)
        try? await session { c in try await c.append(raw, to: Self.sentBox) }
    }

    func fetchSent(since date: Date) async throws -> [FetchedMessage] {
        try await session { c in
            try await c.select(Self.sentBox)
            let uids = try await c.search("SINCE \(IMAPClient.searchDate.string(from: date))").sorted().suffix(50)
            return try await c.fetch(Array(uids)).map { f in
                var m = message(f, prefix: "S:")
                let (name, email) = parseFrom(m.to.components(separatedBy: ",").first ?? m.to)
                m.from = email; m.fromName = name
                m.body = GmailProvider.stripQuotedReply(m.body)
                return m
            }
        }
    }

    func search(_ query: String) async throws -> [FetchedMessage] {
        try await session { c in
            try await c.select(Self.inbox)
            let uids = try await c.search("TEXT \(IMAPClient.quote(query))").sorted().suffix(25)
            return try await c.fetch(Array(uids)).map { message($0) }
        }
    }

    func attachments(for id: String) async throws -> [MailAttachment] {
        try await full(id).attachments.map(\.info)
    }

    func download(_ attachment: MailAttachment, messageId: String) async throws -> Data {
        guard let hit = try await full(messageId).attachments.first(where: { $0.info.id == attachment.id }) else {
            throw URLError(.fileDoesNotExist)
        }
        return hit.data
    }

    private func full(_ id: String) async throws -> ParsedMail {
        let (box, uid) = locate(id)
        return try await session { c in
            try await c.select(box)
            guard let f = try await c.fetch([uid], partial: false).first else { throw URLError(.fileDoesNotExist) }
            return RFC822.parse(f.raw)
        }
    }
}
