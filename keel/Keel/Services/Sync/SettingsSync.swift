import Foundation
import SwiftData
import UIKit

// MARK: - Your settings on every device
//
// Settings (look, AI model, mail layout, focus, notes, booking…) go through iCloud's key-value store, so the Mac
// and iPad match your iPhone. Passwords, AI keys and mail sign-ins go through iCloud Keychain (KeychainStore).
// Things that only make sense on one device stay local: which device syncs Reminders, calendar choices
// (calendar ids differ per device), caches, and "last ran" timestamps of background jobs.

@MainActor
final class SettingsSync {
    static let shared = SettingsSync()
    private let kvs = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard
    private var pending: Task<Void, Never>?
    private var started = false
    static let prefix = "s:"
    static let seededKey = "settingsSync.seeded"        // local only (starts with "settingsSync", denied below)

    /// Kept on this device.
    static let deny: [String] = [
        "settingsSync.", "sync.", "kitlocal.", "throttle.", "push.", "keychain.", "mac.", "body.connected", "body.alerted", "body.refresh", "reminders.bridge", "store.split", "calendar.hidden",
        "mail.notified", "mail.retriage", "scanners.", "trips.backfilled", "appointments.scanned",
        "savepoints.", "timer.", "backup.", "mirror.", "briefing.text", "briefing.polishedAt",
        "health.connected", "nutrition.health.sync", "printableRect", "paperRect", "autopilot.notified",
        "notes.autofile.last", "notes.autofile.seen", "spaces.seen", "batch.revealed",
        // Device-only: calendar ids differ per device; these are about this device's screen, alarms or files.
        "calendar.roles", "focus.bar.", "focus.live.", "alarms.asked", "tasks.timeZone", "md.mirror.", "health.metrics.asked",
        "reminders.failed", "hub.tab.", "notes.search.recents", "routine.alarms",
    ]

    /// Keel's own settings start with a lowercase letter; iOS and its frameworks use NS…, Apple…, com.apple… and so on.
    static func syncs(_ key: String) -> Bool {
        // iCloud allows keys of at most 64 bytes ("s:" + the setting's name).
        guard let first = key.first, first.isLowercase, !key.hasPrefix("com."), key.utf8.count <= 60 else { return false }
        return !deny.contains { key == $0 || key.hasPrefix($0) }
    }

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: kvs, queue: .main) { n in
            let keys = n.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            MainActor.assumeIsolated {
                SettingsSync.shared.pull(keys)
                if keys?.contains(where: { $0.hasPrefix("sync.mail") }) ?? true { MailAccountSync.adopt(ctx: KeelStore.container.mainContext) }
            }
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { _ in
            MainActor.assumeIsolated { SettingsSync.shared.schedulePush() }
        }
        kvs.synchronize()
        let firstTime = !defaults.bool(forKey: Self.seededKey)
        // The first time on a device: your iPhone's settings win; a new Mac or iPad takes what's already in iCloud.
        if firstTime && UIDevice.current.userInterfaceIdiom == .phone {
            push(overwrite: true, deleteMissing: false)
            pull(nil, onlyMissing: true)
        } else {
            pull(nil)
            push(overwrite: true, deleteMissing: !firstTime)
        }
        defaults.set(true, forKey: Self.seededKey)
    }

    func schedulePush() {
        guard started else { return }
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            push(overwrite: true, deleteMissing: true)
        }
    }

    private func blob(_ v: Any) -> Data? {
        try? PropertyListSerialization.data(fromPropertyList: v, format: .binary, options: 0)
    }

    /// When settings last went to or came from iCloud (shown in Keel status).
    static var lastSync: Date? {
        let t = UserDefaults.standard.double(forKey: "settingsSync.last"); return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
    private func stamp() { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "settingsSync.last") }

    /// What this device last sent (value and size), so settings that haven't changed aren't re-encoded every time.
    private var sent: [String: (value: NSObject, size: Int)] = [:]

    /// Sends this device's settings up (only what changed).
    private func push(overwrite: Bool, deleteMissing: Bool) {
        var changed = false
        // Stamp only when something went up: the stamp is itself a settings write, so stamping every time
        // scheduled another push 2 s later, forever (a main-thread pass over every setting every 2 seconds).
        defer { if changed { stamp() } }
        let mine = defaults.dictionaryRepresentation().filter { Self.syncs($0.key) }
        var used = 0
        var count = 0
        // Small settings first: iCloud holds 1 MB and 1,024 keys in total. Going alphabetically let a few big logs
        // early in the alphabet use it all, so settings later on (routines, tasks, Today…) never reached your Mac.
        let ordered = mine.map { item -> (k: String, v: Any, size: Int) in
            if let obj = item.value as? NSObject, let prev = sent[item.key], prev.value.isEqual(obj) { return (item.key, item.value, prev.size) }
            return (item.key, item.value, blob(item.value)?.count ?? .max)      // only re-measured when it changed
        }.sorted { $0.size < $1.size }
        for (k, v, _) in ordered {
            count += 1
            guard count <= 1_000 else { break }
            let obj = v as? NSObject
            if let obj, let prev = sent[k], prev.value.isEqual(obj) {          // unchanged since last time
                used += prev.size
                guard used < 900_000 else { break }
                continue
            }
            guard let data = blob(v), data.count < 64_000 else { continue }       // big blobs stay local
            used += data.count
            guard used < 900_000 else { break }                                  // iCloud allows 1 MB in total
            if let obj { sent[k] = (obj, data.count) }
            let rk = Self.prefix + k
            if let cur = kvs.object(forKey: rk) {
                if !overwrite || blob(cur) == data { continue }
            }
            kvs.set(v, forKey: rk)
            changed = true
        }
        if deleteMissing {
            for rk in kvs.dictionaryRepresentation.keys where rk.hasPrefix(Self.prefix) {
                let k = String(rk.dropFirst(Self.prefix.count))
                if Self.syncs(k) && mine[k] == nil { kvs.removeObject(forKey: rk); sent[k] = nil; changed = true }    // you cleared it here
            }
        }
    }

    /// Takes settings saved on your other devices.
    private func pull(_ changed: [String]?, onlyMissing: Bool = false) {
        defer { stamp() }
        let keys = changed ?? Array(kvs.dictionaryRepresentation.keys)
        for rk in keys where rk.hasPrefix(Self.prefix) {
            let k = String(rk.dropFirst(Self.prefix.count))
            guard Self.syncs(k) else { continue }
            if onlyMissing && defaults.object(forKey: k) != nil { continue }
            if let v = kvs.object(forKey: rk) {
                if let cur = defaults.object(forKey: k), blob(cur) == blob(v) { continue }
                defaults.set(v, forKey: k)
            } else if changed != nil {
                defaults.removeObject(forKey: k)
            }
        }
    }
}

// MARK: - Mail accounts on every device

/// Your mail accounts follow you: their sign-ins travel in iCloud Keychain, and this list tells the other devices
/// which accounts to set up. Each device still downloads its own mail.
@MainActor
enum MailAccountSync {
    static let listKey = "sync.mailAccounts"
    static let removedKey = "sync.mailRemoved"
    private struct Entry: Codable { var id: String; var provider: String; var address: String; var displayName: String; var colorHex: String; var signature: String? }

    private static var kvs: NSUbiquitousKeyValueStore { .default }
    private static func list() -> [Entry] {
        kvs.data(forKey: listKey).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }
    private static var removed: Set<String> {
        get { Set(kvs.array(forKey: removedKey) as? [String] ?? []) }
        set { kvs.set(Array(newValue), forKey: removedKey) }
    }
    static func hasSignIn(_ id: String) -> Bool {
        KeychainStore.read("tokens.\(id)") != nil || KeychainStore.read("imap.\(id)") != nil
    }

    /// Adds this device's accounts to the shared list.
    static func publish(ctx: ModelContext) {
        let local = (try? ctx.fetch(FetchDescriptor<MailAccount>())) ?? []
        var byId = Dictionary(list().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for a in local {
            byId[a.id] = Entry(id: a.id, provider: a.provider.rawValue, address: a.address, displayName: a.displayName, colorHex: a.colorHex, signature: a.signature)
        }
        let gone = removed
        let entries = byId.values.filter { !gone.contains($0.id) }.sorted { $0.id < $1.id }
        if let d = try? JSONEncoder().encode(entries), d != kvs.data(forKey: listKey) { kvs.set(d, forKey: listKey) }
    }

    /// Sets up accounts added on another device (once their sign-in has arrived), and drops ones you removed there.
    static func adopt(ctx: ModelContext) {
        let local = (try? ctx.fetch(FetchDescriptor<MailAccount>())) ?? []
        let localIds = Set(local.map(\.id))
        let gone = removed
        var added = 0
        for e in list() where !localIds.contains(e.id) && !gone.contains(e.id) && hasSignIn(e.id) {
            guard let kind = MailProviderKind(rawValue: e.provider) else { continue }
            let a = MailAccount(provider: kind, address: e.address, displayName: e.displayName, colorHex: e.colorHex)
            a.signature = e.signature
            ctx.insert(a)
            added += 1
        }
        for a in local where gone.contains(a.id) && !hasSignIn(a.id) {
            let id = a.id
            for m in (try? ctx.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { $0.accountId == id }))) ?? [] { ctx.delete(m) }
            ctx.delete(a)
        }
        try? ctx.save()
        if added > 0 { UndoCenter.shared.notify("Added \(added) mail account\(added == 1 ? "" : "s") from your other devices") }
    }

    static func didAdd(_ id: String, ctx: ModelContext) {
        var r = removed; r.remove(id); removed = r
        publish(ctx: ctx)
    }
    static func didRemove(_ id: String, ctx: ModelContext) {
        var r = removed; r.insert(id); removed = r
        publish(ctx: ctx)
    }
}
