import Foundation
import AppIntents
#if !targetEnvironment(macCatalyst)
import ActivityKit
import MediaPlayer

// Lock Screen and Dynamic Island music controls for a focus session (Apple Music).
// These run in the app's process, so the Music app's player is the one being controlled.

enum FocusActivityMusic {
    /// What's playing in the Music app right now, as a short line.
    static var current: (title: String?, playing: Bool) {
        let p = MPMusicPlayerController.systemMusicPlayer
        let title = p.nowPlayingItem.map { [$0.title, $0.artist].compactMap { $0 }.joined(separator: " · ") }
        return (title, p.playbackState == .playing)
    }

    /// Puts the song and play state on the running focus Live Activity.
    static func refreshActivity() async {
        let (title, playing) = current
        for a in Activity<FocusActivityAttributes>.activities {
            var s = a.content.state
            guard s.music != title || s.musicPlaying != playing else { continue }
            s.music = title
            s.musicPlaying = playing
            await a.update(ActivityContent(state: s, staleDate: s.endsAt.addingTimeInterval(60)))
        }
    }
}

struct FocusMusicPlayPauseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Play or pause focus music"
    static let isDiscoverable = false
    init() {}
    func perform() async throws -> some IntentResult {
        await MainActor.run {
            let p = MPMusicPlayerController.systemMusicPlayer
            if p.playbackState == .playing { p.pause() } else { p.play() }
        }
        try? await Task.sleep(for: .milliseconds(300))
        await FocusActivityMusic.refreshActivity()
        return .result()
    }
}

struct FocusMusicNextIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Next song"
    static let isDiscoverable = false
    init() {}
    func perform() async throws -> some IntentResult {
        await MainActor.run { MPMusicPlayerController.systemMusicPlayer.skipToNextItem() }
        try? await Task.sleep(for: .milliseconds(400))
        await FocusActivityMusic.refreshActivity()
        return .result()
    }
}
#endif
