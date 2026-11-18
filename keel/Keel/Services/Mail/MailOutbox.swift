import Foundation
import SwiftData

// MARK: - Mail changes that must reach the server
//
// Archive, read, flag, delete and labels used to be sent once, and any failure (offline, a sign-in that had
// expired, a server hiccup) was ignored. The email changed on this phone but not on the server, so the next sync
// could flip a read email back to unread, and archived or deleted mail stayed in your inbox everywhere else.
// Now a change that doesn't go through is kept here and sent again on every sync until the server takes it.
// While it waits, sync doesn't overwrite it with the server's old state.

enum MailOutbox {
    struct Item: Codable, Hashable {
        var accountId: String
        var providerId: String
        var kind: String            // archive | read | star | trash | label
        var flag: Bool = false      // read / starred value
        var label: String?
        var since: Date = Date()
        var tries: Int = 0
        var key: String { "\(accountId)|\(providerId)|\(kind)" }
    }

    private static let lock = NSLock()
    private static var url: URL { URL.applicationSupportDirectory.appending(path: "mail-outbox.json") }

    private static func load() -> [Item] {
        guard let d = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Item].self, from: d)) ?? []
    }
    private static func save(_ items: [Item]) {
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        if items.isEmpty { try? FileManager.default.removeItem(at: url); return }
        try? JSONEncoder().encode(items).write(to: url, options: .atomic)
    }

    static var items: [Item] { lock.lock(); defer { lock.unlock() }; return load() }
    static var count: Int { items.count }

    /// Keeps a change that didn't go through (replacing an older one of the same kind for the same email).
    static func add(_ item: Item) {
        lock.lock(); defer { lock.unlock() }
        var all = load().filter { $0.key != item.key }
        all.append(item)
        save(all)
    }

    /// A change of this kind went through: anything older of the same kind is no longer needed.
    static func done(_ accountId: String, _ providerId: String, _ kind: String) {
        lock.lock(); defer { lock.unlock() }
        let key = "\(accountId)|\(providerId)|\(kind)"
        let all = load()
        if all.contains(where: { $0.key == key }) { save(all.filter { $0.key != key }) }
    }

    /// Emails with a read or flag change still waiting, so sync leaves Keel's state alone for them.
    static func waiting(accountId: String) -> (read: Set<String>, star: Set<String>, trash: Set<String>) {
        let mine = items.filter { $0.accountId == accountId }
        func ids(_ k: String) -> Set<String> { Set(mine.filter { $0.kind == k }.map(\.providerId)) }
        return (ids("read"), ids("star"), ids("trash"))
    }

    /// Sends everything waiting. Gives up on a change after a week or 20 tries (say, the email was deleted on
    /// the server), so nothing waits forever.
    @MainActor static func flush(accounts: [MailAccount]) async {
        let pending = items
        guard !pending.isEmpty else { return }
        let byId = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for item in pending.prefix(150) {               // a big batch goes over a few syncs, so none drags on
            guard let account = byId[item.accountId] else { forget(item); continue }
            let p = MailProviderFactory.base(for: account)
            do {
                switch item.kind {
                case "archive": try await p.archive(item.providerId)
                case "read": try await p.markRead(item.providerId, read: item.flag)
                case "star": try await p.setStarred(item.providerId, starred: item.flag)
                case "trash": try await p.trash(item.providerId)
                case "label": if let l = item.label { try await p.applyLabel(item.providerId, label: l) }
                default: break
                }
                forget(item)
            } catch {
                var next = item
                next.tries += 1
                if next.tries >= 20 || Date().timeIntervalSince(item.since) > 7 * 86_400 { forget(item) } else { replace(next) }
            }
        }
    }

    private static func forget(_ item: Item) {
        lock.lock(); defer { lock.unlock() }
        save(load().filter { $0.key != item.key })
    }
    private static func replace(_ item: Item) {
        lock.lock(); defer { lock.unlock() }
        var all = load()
        if let i = all.firstIndex(where: { $0.key == item.key && $0.since == item.since }) { all[i] = item; save(all) }
    }
}

/// Wraps each mail account's connection: changes that fail are kept in the outbox and retried, instead of lost.
struct ReliableMailProvider: MailProvider {
    let base: MailProvider
    let accountId: String

    private func run(_ kind: String, _ id: String, flag: Bool = false, label: String? = nil, _ op: () async throws -> Void) async throws {
        do {
            try await op()
            MailOutbox.done(accountId, id, kind)
        } catch {
            MailOutbox.add(.init(accountId: accountId, providerId: id, kind: kind, flag: flag, label: label))
            throw error
        }
    }

    func archive(_ providerId: String) async throws {
        try await run("archive", providerId) { try await base.archive(providerId) }
    }
    func markRead(_ providerId: String, read: Bool) async throws {
        try await run("read", providerId, flag: read) { try await base.markRead(providerId, read: read) }
    }
    func setStarred(_ providerId: String, starred: Bool) async throws {
        try await run("star", providerId, flag: starred) { try await base.setStarred(providerId, starred: starred) }
    }
    func trash(_ providerId: String) async throws {
        try await run("trash", providerId) { try await base.trash(providerId) }
    }
    func applyLabel(_ providerId: String, label: String) async throws {
        try await run("label", providerId, label: label) { try await base.applyLabel(providerId, label: label) }
    }

    func fetchChanges(cursor: String?) async throws -> (messages: [FetchedMessage], cursor: String?) { try await base.fetchChanges(cursor: cursor) }
    func send(_ mail: OutgoingMail) async throws { try await base.send(mail) }
    func fetchSent(since: Date) async throws -> [FetchedMessage] { try await base.fetchSent(since: since) }
    func search(_ query: String) async throws -> [FetchedMessage] { try await base.search(query) }
    func attachments(for providerId: String) async throws -> [MailAttachment] { try await base.attachments(for: providerId) }
    func download(_ attachment: MailAttachment, messageId: String) async throws -> Data { try await base.download(attachment, messageId: messageId) }
    func unsubscribeHeader(for providerId: String) async throws -> (header: String?, oneClick: Bool) { try await base.unsubscribeHeader(for: providerId) }
}
