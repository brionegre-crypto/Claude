import SwiftUI
import Speech
import AVFoundation
import Observation
import AudioToolbox

/// Talk to Keel: a hands-free conversation. Speak, pause, and Keel answers out loud, then listens again.
/// Speech recognition runs on the iPhone; answers come from Ask Keel and Apple Intelligence.
@MainActor @Observable
final class VoiceLoop: NSObject, AVSpeechSynthesizerDelegate {
    enum State { case idle, waiting, listening, thinking, speaking }      // waiting = hands-free, listening for "Hey Keel"
    struct Line: Identifiable { let id = UUID(); let fromUser: Bool; let text: String }

    var state: State = .idle
    var partial = ""
    var lines: [Line] = []
    var error: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silence: Task<Void, Never>?
    private var wakeWords = 0                 // words before your request ("hey keel"), dropped from what Keel hears
    /// What Keel hears while waiting for "Hey Keel", shown on screen so you can see it's listening.
    var hearing = ""
    private let synth = AVSpeechSynthesizer()
    private var active = false
    /// Hands-free: Keel listens on the device for "Hey Keel" while this screen is open, then takes your request.
    private(set) var handsFree = false
    private var awaitingWake = false
    private var restart: Task<Void, Never>?
    private var followUp: Task<Void, Never>?

    override init() {
        super.init()
        synth.delegate = self
    }

    func start() async {
        let speechOK = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard speechOK, micOK else { error = "Keel needs microphone and speech recognition access. Turn them on in Settings → Keel."; return }
        active = true
        listen()
    }

    /// Starts hands-free mode: nothing happens until you say "Hey Keel".
    func startHandsFree() async {
        let speechOK = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard speechOK, micOK else { error = "Keel needs microphone and speech recognition access. Turn them on in Settings → Keel."; return }
        error = nil
        handsFree = true
        active = true
        awaitingWake = true
        UIApplication.shared.isIdleTimerDisabled = true        // the screen stays on while Keel listens
        listen()
    }

    func stop() {
        handsFree = false
        awaitingWake = false
        restart?.cancel(); followUp?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
        active = false
        silence?.cancel()
        endRecognition()
        synth.stopSpeaking(at: .immediate)
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func listen() {
        guard active, let recognizer, recognizer.isAvailable else { error = "Speech recognition isn't available right now."; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .duckOthers, .allowBluetoothA2DP])
            try session.setActive(true)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
            request = req
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in req.append(buffer) }
            engine.prepare()
            try engine.start()
            partial = ""
            state = awaitingWake ? .waiting : .listening
            if awaitingWake { scheduleRestart() } else if handsFree { armFollowUpWindow() }
            task = recognizer.recognitionTask(with: req) { [weak self] result, err in
                Task { @MainActor in
                    guard let self else { return }
                    if let r = result {
                        let heard = r.bestTranscription.formattedString
                        if self.awaitingWake {
                            self.checkWake(heard)
                            if r.isFinal && self.awaitingWake { self.endRecognition(); self.listen() }   // keep listening after a pause
                        } else {
                            if self.wakeWords > 0 {
                                // Recognition may rewrite earlier words; find the wake phrase again and keep what follows.
                                self.partial = Self.wakeMatch(heard)?.rest ?? Self.words(heard).dropFirst(self.wakeWords).joined(separator: " ")
                            } else {
                                self.partial = heard
                            }
                            self.followUp?.cancel()
                            self.armSilenceTimer()
                        }
                    }
                    if err != nil && (self.state == .listening || self.state == .waiting) && self.partial.isEmpty { self.endRecognition(); self.listen() }
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// "Hey Keel" however speech recognition writes it: "Hey, Keel.", "hey kiel", "Hey Kyle", "heykeel", "okay Keel"…
    /// Returns how many words the wake phrase used and the request said after it.
    nonisolated static func wakeMatch(_ heard: String) -> (words: Int, rest: String)? {
        let w = Self.words(heard)
        guard !w.isEmpty else { return nil }
        let leads: Set<String> = ["hey", "hi", "hay", "a", "okay", "ok", "hello", "yo", "eh", "hei"]
        var i = w.count - 1
        while i >= 0 {
            if w[i].hasPrefix("hey") && w[i].count > 3 && isKeel(String(w[i].dropFirst(3))) {        // "heykeel"
                return (i + 1, w[(i + 1)...].joined(separator: " "))
            }
            if i + 1 < w.count, leads.contains(w[i]), isKeel(w[i + 1]) {
                return (i + 2, w[(i + 2)...].joined(separator: " "))
            }
            i -= 1
        }
        return nil
    }
    nonisolated static func words(_ s: String) -> [String] {
        s.lowercased().components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted).filter { !$0.isEmpty }
    }
    nonisolated static func isKeel(_ w: String) -> Bool {
        let close: Set<String> = ["keel", "kiel", "keal", "keele", "keil", "kiehl", "kheel", "keels", "keel's", "kyle", "kill", "kil", "keyl", "kneel", "ceil", "keal's", "kale", "cheel", "kiehls", "keelie"]
        if close.contains(w) { return true }
        guard w.count >= 3 && w.count <= 6, w.first == "k" || w.first == "c" else { return false }
        // One letter off "keel" (k-e-e-l) counts too.
        let a = Array("keel"), b = Array(w)
        var row = Array(0...b.count)
        for x in 1...a.count {
            var prev = row[0]; row[0] = x
            for y in 1...b.count { let t = row[y]; row[y] = min(row[y] + 1, row[y - 1] + 1, prev + (a[x - 1] == b[y - 1] ? 0 : 1)); prev = t }
        }
        return row[b.count] <= 1
    }

    /// Waiting for the wake phrase: everything said after "Hey Keel" is your request.
    private func checkWake(_ heard: String) {
        hearing = String(heard.suffix(60))
        guard let m = Self.wakeMatch(heard) else {
            if heard.count > 220 { endRecognition(); listen() }       // keep the rolling transcript short
            return
        }
        awaitingWake = false
        restart?.cancel()
        AudioServicesPlaySystemSound(1113)                          // a soft "I'm listening" tone
        Haptics.tap()
        state = .listening
        let rest = m.rest
        // Keep listening in the same recognition: the request continues after the wake words.
        wakeWords = m.words
        hearing = ""
        partial = rest
        if rest.isEmpty { armFollowUpWindow(seconds: 6) } else { armSilenceTimer() }
    }

    /// After an answer (or a bare "Hey Keel"), a few seconds to keep talking without the wake words.
    private func armFollowUpWindow(seconds: Double = 7) {
        followUp?.cancel()
        followUp = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.handsFree, self.partial.isEmpty else { return }
            self.awaitingWake = true
            self.endRecognition()
            self.listen()
        }
    }

    /// Long listening is restarted every 50 seconds so recognition stays quick and reliable.
    private func scheduleRestart() {
        restart?.cancel()
        restart = Task { [weak self] in
            try? await Task.sleep(for: .seconds(50))
            guard !Task.isCancelled, let self, self.awaitingWake else { return }
            self.endRecognition()
            self.listen()
        }
    }

    /// 1.5 seconds without new words = you've finished speaking.
    private func armSilenceTimer() {
        silence?.cancel()
        silence = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.finishUtterance()
        }
    }

    private func endRecognition() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil
    }

    private func finishUtterance() async {
        let text = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        endRecognition()
        wakeWords = 0
        guard active else { return }
        guard !text.isEmpty else { if handsFree { awaitingWake = true }; listen(); return }
        let lower = text.lowercased()
        if ["stop", "that's all", "thanks keel", "thank you keel", "goodbye", "bye", "never mind", "nevermind"].contains(where: { lower == $0 || lower.hasSuffix($0) }) {
            lines.append(Line(fromUser: true, text: text))
            speak("Okay. I'm here when you need me.")
            if handsFree { awaitingWake = true } else { active = false }   // hands-free keeps waiting for "Hey Keel"
            return
        }
        lines.append(Line(fromUser: true, text: text))
        partial = ""
        state = .thinking
        let answer = await KeelAssistant.shared.ask(text)
        lines.append(Line(fromUser: false, text: answer))
        speak(answer)
    }

    private func speak(_ text: String) {
        state = .speaking
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier) ?? AVSpeechSynthesisVoice(language: "en-US")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        synth.speak(u)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if self.active { self.listen() } else { self.state = .idle }       // hands-free: a short follow-up window, then back to "Hey Keel"
        }
    }
}

struct TalkView: View {
    @State private var loop = VoiceLoop()

    var body: some View {
        VStack(spacing: DS.Space.l) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        if loop.lines.isEmpty {
                            Text(loop.handsFree
                                 ? "Hands-free is on. Say “Hey Keel”, then ask: “Add milk to groceries”, “What's next?”, “Remind me when I get to the office”, “Read my important email”. The screen stays on; everything is heard on your device."
                                 : "Try: “What's on today?”, “Move my dentist task to Friday”, “Remember that I'm sharpest before noon”, or “Did I take my meds?” Say “that's all” to finish.")
                                .font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft).padding(.top)
                        }
                        ForEach(loop.lines) { l in
                            Text(l.text)
                                .padding(DS.Space.m)
                                .background(l.fromUser ? DS.Palette.accent.opacity(0.15) : DS.Palette.elevated, in: .rect(cornerRadius: 16))
                                .frame(maxWidth: .infinity, alignment: l.fromUser ? .trailing : .leading)
                                .id(l.id)
                        }
                        if loop.state == .waiting && !loop.hearing.isEmpty {
                            Text("Hearing: “\(loop.hearing)”").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                                .frame(maxWidth: .infinity, alignment: .center).accessibilityHidden(true)
                        }
                        if !loop.partial.isEmpty {
                            Text(loop.partial).italic().foregroundStyle(DS.Palette.inkSoft).frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: loop.lines.count) { if let last = loop.lines.last { withAnimation { proxy.scrollTo(last.id) } } }
            }
            if let e = loop.error { Text(e).font(DS.Font.caption).foregroundStyle(.red).padding(.horizontal) }
            Button {
                if loop.state == .idle { Task { await loop.start() } } else { loop.stop() }
            } label: {
                ZStack {
                    Circle().fill(orbColor.gradient).frame(width: 110, height: 110)
                        .scaleEffect(loop.state == .listening ? 1.08 : 1)
                        .animation(loop.state == .listening ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: loop.state)
                    Image(systemName: icon).font(.system(size: 40, weight: .semibold)).foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(loop.state == .idle ? "Start talking" : "Stop")
            Text(label).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            Toggle(isOn: Binding(get: { loop.handsFree }, set: { on in
                if on { loop.stop(); Task { await loop.startHandsFree() } } else { loop.stop() }
            })) {
                Label("Hands-free: “Hey Keel”", systemImage: "ear.and.waveform")
            }
            .toggleStyle(.button).tint(DS.Palette.accent)
            .accessibilityHint("While this screen is open, Keel listens on your device for “Hey Keel”")
            .padding(.bottom)
        }
        .navigationTitle("Talk to Keel")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { loop.stop() }
    }

    private var orbColor: Color {
        switch loop.state { case .idle: DS.Palette.accent; case .waiting: DS.Palette.accent.opacity(0.55); case .listening: .red; case .thinking: .purple; case .speaking: DS.Palette.calm }
    }
    private var icon: String {
        switch loop.state { case .idle: "waveform"; case .waiting: "ear"; case .listening: "mic.fill"; case .thinking: "sparkles"; case .speaking: "speaker.wave.2.fill" }
    }
    private var label: String {
        switch loop.state {
        case .idle: "Tap to start a conversation"
        case .waiting: "Say “Hey Keel”… (tap to stop)"
        case .listening: "Listening… pause when you're done"
        case .thinking: "Thinking…"
        case .speaking: "Speaking. Tap to stop"
        }
    }
}
