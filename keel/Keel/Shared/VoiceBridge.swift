import Foundation

/// How the Keel keyboard and the Keel app talk during a Keel Voice session. iOS doesn't let keyboards use the
/// microphone, so (like Wispr Flow) the app listens and cleans up, and the keyboard types what it sends back.
/// Signals are Darwin notifications (they reach other processes instantly); the details sit in the shared App Group.
enum VoiceBridge {
    static let group = "group.com.briangreenejr.keel"
    static var defaults: UserDefaults? { UserDefaults(suiteName: group) }

    enum Signal: String {
        case start = "com.keel.voice.start"          // keyboard → app: listen (details in `request`)
        case stop = "com.keel.voice.stop"            // keyboard → app: done talking
        case cancel = "com.keel.voice.cancel"        // keyboard → app: throw it away
        case state = "com.keel.voice.state"          // app → keyboard: state changed
        case partial = "com.keel.voice.partial"      // app → keyboard: live words
        case result = "com.keel.voice.result"        // app → keyboard: text to type
    }

    /// The session, as the app last wrote it.
    enum State: String, Codable { case off, ready, listening, working }

    /// What the keyboard sends with "start": the text before the cursor (for context and "Keel, …" edits) and
    /// what kind of field it is.
    struct Request: Codable, Equatable {
        var id = UUID()
        var before: String
        var kind: String          // "message", "email", "search", "general"
    }

    /// What the app sends back for the keyboard to type.
    struct Result: Codable, Equatable {
        enum Kind: String, Codable { case insert, polish, replaceBefore }
        var id = UUID()
        var request: UUID
        var kind: Kind
        var text: String
        var replacing: String = ""      // polish: the words just typed; replaceBefore: the text before the cursor it edits
    }

    private static let stateKey = "voice.kb.state", heartbeatKey = "voice.kb.heartbeat", requestKey = "voice.kb.request"
    private static let partialKey = "voice.kb.partial", resultKey = "voice.kb.result", sessionEndsKey = "voice.kb.ends"

    // MARK: Shared values

    static var state: State {
        get { State(rawValue: defaults?.string(forKey: stateKey) ?? "") ?? .off }
        set { defaults?.set(newValue.rawValue, forKey: stateKey); post(.state) }
    }
    /// The app writes this every second while a session runs; a stale heartbeat means the app isn't there.
    static var heartbeat: Date? {
        get { defaults?.object(forKey: heartbeatKey) as? Date }
        set { defaults?.set(newValue, forKey: heartbeatKey) }
    }
    static var sessionAlive: Bool { (heartbeat.map { Date().timeIntervalSince($0) < 3.5 } ?? false) && state != .off }
    static var sessionEnds: Date? {
        get { defaults?.object(forKey: sessionEndsKey) as? Date }
        set { defaults?.set(newValue, forKey: sessionEndsKey) }
    }
    static var request: Request? {
        get { defaults?.data(forKey: requestKey).flatMap { try? JSONDecoder().decode(Request.self, from: $0) } }
        set { defaults?.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: requestKey) }
    }
    static var partial: String {
        get { defaults?.string(forKey: partialKey) ?? "" }
        set { defaults?.set(newValue, forKey: partialKey) }
    }
    static var result: Result? {
        get { defaults?.data(forKey: resultKey).flatMap { try? JSONDecoder().decode(Result.self, from: $0) } }
        set { defaults?.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: resultKey) }
    }

    // MARK: Darwin notifications

    static func post(_ s: Signal) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(s.rawValue as CFString), nil, nil, true)
    }

    nonisolated(unsafe) private static var handlers: [String: () -> Void] = [:]

    /// Calls `handler` on the main queue whenever `s` is posted (by either process).
    static func observe(_ s: Signal, _ handler: @escaping () -> Void) {
        handlers[s.rawValue] = handler
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, name, _, _ in
            guard let n = name?.rawValue as String? else { return }
            DispatchQueue.main.async { VoiceBridge.handlers[n]?() }
        }, s.rawValue as CFString, nil, .deliverImmediately)
    }

    // MARK: Typing it (keyboard side; pure, so it's tested)

    /// What the keyboard should do with a result, given the text now before the cursor:
    /// delete this many characters, then insert this text. Nil means leave it (you've typed since).
    static func edit(for r: Result, before: String) -> (delete: Int, insert: String)? {
        switch r.kind {
        case .insert:
            let needsSpace = !(before.isEmpty || before.hasSuffix(" ") || before.hasSuffix("\n")) && !r.text.hasPrefix("\n")
            return (0, (needsSpace ? " " : "") + r.text)
        case .polish:
            guard !r.replacing.isEmpty, before.hasSuffix(r.replacing) else { return nil }
            return (r.replacing.count, r.text)
        case .replaceBefore:
            guard !r.replacing.isEmpty, before.hasSuffix(r.replacing) else { return nil }
            return (r.replacing.count, r.text)
        }
    }
}
