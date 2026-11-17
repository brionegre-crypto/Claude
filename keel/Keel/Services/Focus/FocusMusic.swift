import SwiftUI
import MediaPlayer

// MARK: - Music while you focus
//
// Pick where your music comes from: an Apple Music playlist (Keel plays it through the Music app, so it keeps
// going behind Keel, with play/pause/skip in the focus screen), or any other music app (Spotify, YouTube Music,
// Amazon Music, Pandora, Tidal, Audible, Podcasts). Keel's focus sounds mix with your music, so both are audible.

@MainActor
@Observable
final class FocusMusic {
    static let shared = FocusMusic()

    enum Source: String, CaseIterable, Identifiable {
        case none, appleMusic, spotify, youtubeMusic, amazonMusic, pandora, tidal, audible, podcasts
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: "No music"; case .appleMusic: "Apple Music"; case .spotify: "Spotify"; case .youtubeMusic: "YouTube Music"
            case .amazonMusic: "Amazon Music"; case .pandora: "Pandora"; case .tidal: "Tidal"; case .audible: "Audible"; case .podcasts: "Podcasts"
            }
        }
        var icon: String {
            switch self {
            case .none: "speaker.slash"; case .appleMusic: "music.note"; case .audible: "headphones"; case .podcasts: "mic"
            default: "music.note.list"
            }
        }
        /// Opens the app (its own play button then takes over).
        var url: URL? {
            switch self {
            case .none: nil
            case .appleMusic: URL(string: "music://")
            case .spotify: URL(string: "spotify://")
            case .youtubeMusic: URL(string: "youtubemusic://")
            case .amazonMusic: URL(string: "amznmp3://")
            case .pandora: URL(string: "pandora://")
            case .tidal: URL(string: "tidal://")
            case .audible: URL(string: "audible://")
            case .podcasts: URL(string: "podcasts://")
            }
        }
    }

    static let sourceKey = "focus.music.source"
    static let playlistKey = "focus.music.playlist"          // Apple Music playlist persistent ID
    static let autoKey = "focus.music.auto"                  // start the music when focus starts

    var source: Source {
        get { Source(rawValue: UserDefaults.standard.string(forKey: Self.sourceKey) ?? "none") ?? .none }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.sourceKey); bump += 1 }
    }
    var bump = 0                                             // redraws views when the choice changes
    private(set) var nowPlaying: String?
    private(set) var isPlaying = false
    private(set) var playlists: [MPMediaPlaylist] = []
    private(set) var libraryAllowed = MPMediaLibrary.authorizationStatus() == .authorized

    private var player: MPMusicPlayerController { .systemMusicPlayer }

    // MARK: Apple Music

    func loadPlaylists() async {
        #if !targetEnvironment(macCatalyst)
        if MPMediaLibrary.authorizationStatus() == .notDetermined {
            _ = await withCheckedContinuation { (c: CheckedContinuation<MPMediaLibraryAuthorizationStatus, Never>) in
                MPMediaLibrary.requestAuthorization { c.resume(returning: $0) }
            }
        }
        libraryAllowed = MPMediaLibrary.authorizationStatus() == .authorized
        guard libraryAllowed else { return }
        playlists = (MPMediaQuery.playlists().collections as? [MPMediaPlaylist] ?? []).filter { $0.count > 0 }
        #endif
    }

    var chosenPlaylistId: UInt64 {
        get { UInt64(UserDefaults.standard.string(forKey: Self.playlistKey) ?? "") ?? 0 }
        set { UserDefaults.standard.set(String(newValue), forKey: Self.playlistKey); bump += 1 }
    }

    func playChosenPlaylist() {
        #if !targetEnvironment(macCatalyst)
        guard libraryAllowed else { return }
        let id = chosenPlaylistId
        if id != 0, let pl = (MPMediaQuery.playlists().collections as? [MPMediaPlaylist])?.first(where: { $0.persistentID == id }) {
            player.setQueue(with: pl)
            player.shuffleMode = .songs
        }
        player.play()
        refresh()
        #endif
    }

    func togglePlay() {
        #if !targetEnvironment(macCatalyst)
        if player.playbackState == .playing { player.pause() } else { player.play() }
        refresh()
        #endif
    }
    func next() {
        #if !targetEnvironment(macCatalyst)
        player.skipToNextItem(); refresh()
        #endif
    }
    func pauseIfOurs() {
        #if !targetEnvironment(macCatalyst)
        if source == .appleMusic, player.playbackState == .playing { player.pause() }
        refresh()
        #endif
    }

    func refresh() {
        #if !targetEnvironment(macCatalyst)
        isPlaying = player.playbackState == .playing
        let item = player.nowPlayingItem
        nowPlaying = item.map { [$0.title, $0.artist].compactMap { $0 }.joined(separator: " · ") }
        #endif
    }

    // MARK: Focus hooks

    /// Focus started: start your music (Apple Music plays here; another app opens so you can press play).
    func focusStarted() {
        guard UserDefaults.standard.object(forKey: Self.autoKey) as? Bool ?? true else { return }
        switch source {
        case .none: return
        case .appleMusic: playChosenPlaylist()
        default: open()
        }
    }

    func focusEnded() {
        if UserDefaults.standard.bool(forKey: "focus.music.stopAtEnd") { pauseIfOurs() }
    }

    func open() {
        guard let u = source.url else { return }
        UIApplication.shared.open(u) { ok in
            if !ok { Task { @MainActor in UndoCenter.shared.notify("\(self.source.title) isn't installed") } }
        }
    }
}

/// The music picker on the focus setup screen.
struct FocusMusicPicker: View {
    @State private var music = FocusMusic.shared
    @AppStorage(FocusMusic.autoKey) private var auto = true
    @AppStorage("focus.music.stopAtEnd") private var stopAtEnd = false

    var body: some View {
        let _ = music.bump
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                Picker("Music", selection: Binding(get: { music.source }, set: { music.source = $0; if $0 == .appleMusic { Task { await music.loadPlaylists() } } })) {
                    ForEach(FocusMusic.Source.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                }
            } label: {
                HStack {
                    Label("Music", systemImage: "music.note")
                    Spacer()
                    Text(music.source.title).foregroundStyle(DS.Palette.inkSoft)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                }
            }
            .foregroundStyle(DS.Palette.ink)
            if music.source == .appleMusic {
                if !music.libraryAllowed {
                    Button("Allow Keel to see your Apple Music playlists") { Task { await music.loadPlaylists() } }.font(.caption)
                } else {
                    Picker("Playlist", selection: Binding(get: { music.chosenPlaylistId }, set: { music.chosenPlaylistId = $0 })) {
                        Text("Whatever's in Music").tag(UInt64(0))
                        ForEach(music.playlists, id: \.persistentID) { pl in Text(pl.name ?? "Playlist").tag(pl.persistentID) }
                    }
                    .font(.caption)
                }
            }
            if music.source != .none {
                Toggle("Start it when focus starts", isOn: $auto).font(.caption)
                if music.source == .appleMusic { Toggle("Pause it when focus ends", isOn: $stopAtEnd).font(.caption) }
                Text(music.source == .appleMusic ? "Plays through the Music app, alongside any focus sound." :
                        "Keel opens \(music.source.title) so you can press play, then come back. Your focus sound keeps playing too. If you block apps during focus, leave \(music.source.title) unblocked.")
                    .font(.caption2).foregroundStyle(DS.Palette.inkSoft)
            }
        }
        .task { if music.source == .appleMusic { await music.loadPlaylists() } }
    }
}

/// Now playing and controls on the running focus screen.
struct FocusMusicControls: View {
    @State private var music = FocusMusic.shared
    private let tick = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        let _ = music.bump
        if music.source != .none {
            HStack(spacing: 12) {
                Image(systemName: music.source.icon).foregroundStyle(DS.Palette.focus)
                VStack(alignment: .leading, spacing: 1) {
                    Text(music.source == .appleMusic ? (music.nowPlaying ?? "Apple Music") : music.source.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(music.source == .appleMusic ? (music.isPlaying ? "Playing" : "Paused") : "Playing in its app").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                }
                Spacer()
                if music.source == .appleMusic {
                    Button { music.togglePlay() } label: { Image(systemName: music.isPlaying ? "pause.fill" : "play.fill") }
                    Button { music.next() } label: { Image(systemName: "forward.fill") }
                } else {
                    Button("Open") { music.open() }.font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.borderless)
            .padding(12)
            .background { PremiumSurface(tint: DS.Palette.focus, radius: 16) }
            .onAppear { music.refresh() }
            .onReceive(tick) { _ in music.refresh() }
        }
    }
}
