import Foundation
import AppIntents
#if !targetEnvironment(macCatalyst)

// Lock Screen and Dynamic Island music controls for a focus session (Apple Music).
// The buttons live in the widget extension, but these intents run in the app's process: the app plugs in
// what they do at launch (FocusMusic.installLockScreenControls), so the extension never touches the music player.

enum FocusMusicBridge {
    nonisolated(unsafe) static var playPause: (@Sendable () async -> Void)?
    nonisolated(unsafe) static var next: (@Sendable () async -> Void)?
}

struct FocusMusicPlayPauseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Play or pause focus music"
    static let isDiscoverable = false
    init() {}
    func perform() async throws -> some IntentResult {
        await FocusMusicBridge.playPause?()
        return .result()
    }
}

struct FocusMusicNextIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Next song"
    static let isDiscoverable = false
    init() {}
    func perform() async throws -> some IntentResult {
        await FocusMusicBridge.next?()
        return .result()
    }
}
#endif
