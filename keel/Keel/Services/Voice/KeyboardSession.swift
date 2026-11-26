import Foundation
import SwiftData
import UIKit
import AVFoundation

/// The app's half of the Keel keyboard (like Wispr Flow's "Flow session"): the keyboard opens Keel once, Keel
/// keeps the microphone ready in the background, and every tap of the keyboard's mic after that dictates at once
/// in whatever app you're in. Keel does the listening and the cleanup; the keyboard types the result.
@MainActor @Observable
final class KeyboardVoiceSession {
    static let shared = KeyboardVoiceSession()

    let voice = KeelVoice()
    private(set) var active = false
    private(set) var endsAt: Date?
    private var heartbeat: Task<Void, Never>?
    private var partials: Task<Void, Never>?
    private var current: VoiceBridge.Request?
    private var observing = false

    static let lengthKey = "voice.kb.minutes"
    /// "Until I end it": the session never times out, so the keyboard only sends you to Keel once
    /// (until you end it, restart the iPhone, or iOS closes Keel).
    static let untilEnded = -1
    /// How long the session waits for the next dictation before letting the microphone go.
    static var minutes: Int {
        get { let m = UserDefaults.standard.integer(forKey: lengthKey); return m != 0 ? m : 15 }
        set { UserDefaults.standard.set(newValue, forKey: lengthKey) }
    }
    static var lengthText: String { minutes == untilEnded ? "until you end it" : "for \(minutes) minutes after you last dictate" }

    static let autoReadyKey = "voice.kb.autoReady"
    /// Get the keyboard ready whenever Keel opens, so the keyboard's mic works at once later instead of
    /// bouncing to Keel first.
    static var readyWhenKeelOpens: Bool {
        get { UserDefaults.standard.bool(forKey: autoReadyKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoReadyKey) }
    }

    /// Keel came to the front: start the session quietly if you asked for that (and the mic is already allowed,
    /// so no prompt appears out of nowhere).
    func keelOpened() {
        #if !targetEnvironment(macCatalyst)
        guard Self.readyWhenKeelOpens, !active, AVAudioApplication.shared.recordPermission == .granted else { return }
        Task { await begin(startListening: false) }
        #endif
    }

    /// From the keyboard (com.keel.app://voice-session): get the microphone ready and, if asked, start listening.
    func begin(startListening: Bool) async {
        observe()
        if !active {
            guard await voice.enterStandby() else {
                VoiceBridge.state = .off
                return
            }
            active = true
            beat()
        }
        extend()
        VoiceBridge.state = .ready
        if startListening { await start() }
    }

    func end() {
        heartbeat?.cancel(); partials?.cancel()
        if voice.isActive { voice.cancel() }
        voice.leaveStandby()
        active = false; endsAt = nil
        VoiceBridge.heartbeat = nil
        VoiceBridge.sessionEnds = nil
        VoiceBridge.state = .off
    }

    private func extend() {
        endsAt = Self.minutes == Self.untilEnded ? nil : Date().addingTimeInterval(Double(Self.minutes * 60))
        VoiceBridge.sessionEnds = endsAt
    }

    /// Every second: tell the keyboard Keel is here; end when the session has been quiet long enough.
    private func beat() {
        heartbeat?.cancel()
        heartbeat = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                VoiceBridge.heartbeat = Date()
                if let e = self.endsAt, Date() > e, !self.voice.isActive { self.end(); return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func observe() {
        guard !observing else { return }
        observing = true
        VoiceBridge.observe(.start) { Task { @MainActor in await KeyboardVoiceSession.shared.start() } }
        VoiceBridge.observe(.stop) { Task { @MainActor in await KeyboardVoiceSession.shared.finish() } }
        VoiceBridge.observe(.cancel) { Task { @MainActor in KeyboardVoiceSession.shared.cancel() } }
    }

    private var ctx: ModelContext { KeelStore.container.mainContext }

    private func start() async {
        guard active, !voice.isActive else { return }
        current = VoiceBridge.request
        extend()
        VoiceBridge.partial = ""
        await voice.start(vocabulary: VoiceVocabulary.words(ctx))
        guard voice.state == .listening else { VoiceBridge.state = .ready; return }
        VoiceBridge.state = .listening
        // Live words for the keyboard, a few times a second.
        partials?.cancel()
        partials = Task { @MainActor [weak self] in
            var last = ""
            while !Task.isCancelled, let self, self.voice.state == .listening || self.voice.state == .preparing {
                let t = self.voice.liveText
                if t != last { last = t; VoiceBridge.partial = t; VoiceBridge.post(.partial) }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    private func cancel() {
        partials?.cancel()
        voice.cancel()
        VoiceBridge.partial = ""
        VoiceBridge.state = active ? .ready : .off
    }

    private func finish() async {
        guard voice.state == .listening || voice.state == .preparing else { return }
        partials?.cancel()
        VoiceBridge.state = .working
        let raw = await voice.stop().trimmingCharacters(in: .whitespacesAndNewlines)
        extend()
        let req = current ?? VoiceBridge.Request(before: "", kind: "general")
        let context = Self.context(req.kind)
        defer { VoiceBridge.partial = ""; VoiceBridge.state = active ? .ready : .off }
        guard !raw.isEmpty else { return }
        let words = VoiceVocabulary.words(ctx), snippets = VoiceVocabulary.snippets(ctx)

        // "Keel, …" edits what's before the cursor (the current paragraph), or writes something new.
        if let instruction = VoiceCommandMode.instruction(in: raw) {
            let paragraph = Self.lastParagraph(req.before)
            if let out = await VoiceCommandMode.apply(instruction, to: paragraph, context: context) {
                send(.init(request: req.id, kind: paragraph.isEmpty ? .insert : .replaceBefore, text: out, replacing: paragraph))
            }
            return
        }
        // Instant, then polished in place (the keyboard only swaps it if you haven't typed since).
        let quick = VoiceCleanup.quick(raw, context: context, vocabulary: words, snippets: snippets)
        guard !quick.isEmpty else { return }
        send(.init(request: req.id, kind: .insert, text: quick))
        VoiceBridge.state = .working
        if let polished = await VoiceCleanup.polish(quick, context: context, vocabulary: words, snippets: snippets, before: req.before) {
            send(.init(request: req.id, kind: .polish, text: polished, replacing: quick))
        }
    }

    private func send(_ r: VoiceBridge.Result) {
        VoiceBridge.result = r
        VoiceBridge.post(.result)
    }

    static func context(_ kind: String) -> VoiceContext {
        switch kind {
        case "email": .email
        case "message": .message
        case "search": .search
        default: .general
        }
    }

    /// The text after the last blank line (what "Keel, make this shorter" means in a long field).
    static func lastParagraph(_ before: String) -> String {
        guard let r = before.range(of: "\n\n", options: .backwards) else { return before }
        return String(before[r.upperBound...])
    }
}
