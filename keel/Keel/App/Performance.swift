import SwiftUI
import SwiftData

// MARK: - Speed helpers shared by the busiest screens

/// Remembers derived values (filtered lists, groups, summaries) for the length of one screen update.
/// Screens call `reset()` at the top of `body`; every later use in the same update is a lookup, not a rescan.
/// A plain class kept in @State: writing to it never triggers another update.
final class RenderMemo {
    private var values: [String: Any] = [:]
    func reset() { values.removeAll(keepingCapacity: true) }
    func get<T>(_ key: String, _ make: () -> T) -> T {
        if let v = values[key] as? T { return v }
        let v = make()
        values[key] = v
        return v
    }
}

/// A page's preview text, built once per edit instead of on every redraw while you scroll.
/// Building it means reading every block of the page, which is slow for long pages.
@MainActor
enum NoteSnippet {
    private static var cache: [UUID: (stamp: Date, text: String)] = [:]

    static func text(_ n: Note) -> String {
        if n.isLocked { return "" }                 // a locked page's text never shows in a preview
        if let c = cache[n.id], c.stamp == n.updatedAt { return c.text }
        let full = n.plainText
        let text = full.count > 400 ? String(full.prefix(400)) : full
        if cache.count > 3000 { cache.removeAll(keepingCapacity: true) }
        cache[n.id] = (n.updatedAt, text)
        return text
    }
}

// MARK: - Search highlighting in mail rows

private struct MailSearchTermsKey: EnvironmentKey { static let defaultValue: [String] = [] }
extension EnvironmentValues {
    /// The words being searched for in Inbox, so each row can highlight them (empty when not searching).
    var mailSearchTerms: [String] {
        get { self[MailSearchTermsKey.self] }
        set { self[MailSearchTermsKey.self] = newValue }
    }
}


/// Newest-first fetches with a cap, for cards that only look at recent history.
enum Limits {
    static func checkIns(_ n: Int) -> FetchDescriptor<CheckIn> {
        var d = FetchDescriptor<CheckIn>(sortBy: [SortDescriptor(\.day, order: .reverse)]); d.fetchLimit = n; return d
    }
    static func sessions(_ n: Int) -> FetchDescriptor<FocusSession> {
        var d = FetchDescriptor<FocusSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]); d.fetchLimit = n; return d
    }
}
