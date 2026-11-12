import Foundation

/// Where an IMAP account lives. Presets cover the big providers; "Other" takes any server.
struct IMAPServer: Codable, Hashable {
    var imapHost: String
    var imapPort: Int = 993
    var smtpHost: String
    var smtpPort: Int = 465                      // 465 = TLS from the start; 587 = STARTTLS
    var sent = "Sent"
    var archive = "Archive"
    var trash = "Trash"
    var username: String? = nil                  // when the login isn't the email address
    var saveSentCopy = true                      // false where the server files sent mail itself

    static let icloud = IMAPServer(imapHost: "imap.mail.me.com", smtpHost: "smtp.mail.me.com", smtpPort: 587,
                                   sent: "Sent Messages", archive: "Archive", trash: "Deleted Messages")
    static let yahoo = IMAPServer(imapHost: "imap.mail.yahoo.com", smtpHost: "smtp.mail.yahoo.com", saveSentCopy: false)
    static let aol = IMAPServer(imapHost: "imap.aol.com", smtpHost: "smtp.aol.com", saveSentCopy: false)
    static let fastmail = IMAPServer(imapHost: "imap.fastmail.com", smtpHost: "smtp.fastmail.com")
    static let zoho = IMAPServer(imapHost: "imap.zoho.com", smtpHost: "smtp.zoho.com")

    /// Saved per account (iCloud accounts use the preset).
    static func load(accountId: String) -> IMAPServer? {
        guard let d = UserDefaults.standard.data(forKey: "imap.server.\(accountId)") else { return nil }
        return try? JSONDecoder().decode(IMAPServer.self, from: d)
    }
    func save(accountId: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: "imap.server.\(accountId)")
    }

    /// Best guess from the address, for "Other" accounts on well-known domains.
    static func guess(for email: String) -> IMAPServer? {
        let domain = email.split(separator: "@").last.map { $0.lowercased() } ?? ""
        switch domain {
        case "icloud.com", "me.com", "mac.com": return .icloud
        case "yahoo.com", "ymail.com", "rocketmail.com": return .yahoo
        case "aol.com", "aim.com": return .aol
        case "fastmail.com", "fastmail.fm": return .fastmail
        case "zoho.com", "zohomail.com": return .zoho
        default: return domain.isEmpty ? nil : IMAPServer(imapHost: "imap.\(domain)", smtpHost: "smtp.\(domain)")
        }
    }
}

extension IMAPClient {
    /// Finds Sent / Archive / Trash from the server's special-use flags, e.g. `* LIST (\HasNoChildren \Sent) "/" "Sent Items"`.
    func specialFolders() async throws -> [String: String] {
        let lines = try await run("LIST \"\" \"*\"")
        var out: [String: String] = [:]
        for (line, _) in lines where line.hasPrefix("* LIST") {
            guard let open = line.firstIndex(of: "("), let close = line.firstIndex(of: ")") else { continue }
            let flags = line[line.index(after: open)..<close].split(separator: " ").map(String.init)
            var name = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            // drop the delimiter ("/" or NIL), keep the mailbox name
            if let space = name.firstIndex(of: " ") { name = String(name[name.index(after: space)...]).trimmingCharacters(in: .whitespaces) }
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            for f in flags where ["\\Sent", "\\Archive", "\\All", "\\Trash"].contains(f) { out[f] = name }
        }
        return out
    }
}
