import SwiftUI
import Speech
import AVFoundation
import Observation

/// Talk to Keel: a hands-free conversation. Speak, pause, and Keel answers out loud, then listens again.
/// Speech recognition runs on the iPhone; answers come from Ask Keel and Apple Intelligence.
@MainActor @Observable
final class VoiceLoop: NSObject, AVSpeechSynthesizerDelegate {
    enum State { case idle, listening, thinking, speaking }
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
    private let synth = AVSpeechSynthesizer()
    private var active = false

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

    func stop() {
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
            state = .listening
            task = recognizer.recognitionTask(with: req) { [weak self] result, err in
                Task { @MainActor in
                    guard let self else { return }
                    if let r = result {
                        self.partial = r.bestTranscription.formattedString
                        self.armSilenceTimer()
                    }
                    if err != nil && self.state == .listening && self.partial.isEmpty { self.endRecognition(); self.listen() }
                }
            }
        } catch {
            self.error = error.localizedDescription
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
        guard active else { return }
        guard !text.isEmpty else { listen(); return }
        let lower = text.lowercased()
        if ["stop", "that's all", "thanks keel", "thank you keel", "goodbye", "bye"].contains(where: { lower == $0 || lower.hasSuffix($0) }) {
            lines.append(Line(fromUser: true, text: text))
            speak("Okay. I'm here when you need me.")
            active = false
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
            if self.active { self.listen() } else { self.state = .idle }
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
                            Text("Try: “What's on today?”, “Move my dentist task to Friday”, “Remember that I'm sharpest before noon”, or “Did I take my meds?” Say “that's all” to finish.")
                                .font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft).padding(.top)
                        }
                        ForEach(loop.lines) { l in
                            Text(l.text)
                                .padding(DS.Space.m)
                                .background(l.fromUser ? DS.Palette.accent.opacity(0.15) : DS.Palette.elevated, in: .rect(cornerRadius: 16))
                                .frame(maxWidth: .infinity, alignment: l.fromUser ? .trailing : .leading)
                                .id(l.id)
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
            Text(label).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).padding(.bottom)
        }
        .navigationTitle("Talk to Keel")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { loop.stop() }
    }

    private var orbColor: Color {
        switch loop.state { case .idle: DS.Palette.accent; case .listening: .red; case .thinking: .purple; case .speaking: DS.Palette.calm }
    }
    private var icon: String {
        switch loop.state { case .idle: "waveform"; case .listening: "mic.fill"; case .thinking: "sparkles"; case .speaking: "speaker.wave.2.fill" }
    }
    private var label: String {
        switch loop.state {
        case .idle: "Tap to start a conversation"
        case .listening: "Listening… pause when you're done"
        case .thinking: "Thinking…"
        case .speaking: "Speaking. Tap to stop"
        }
    }
}
