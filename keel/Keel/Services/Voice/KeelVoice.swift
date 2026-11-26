import Foundation
import AVFoundation
import Speech

/// Keel Voice: one dictation engine for every mic in Keel.
/// Hears with Apple's SpeechAnalyzer (iOS 26: on-device, long-form, far more accurate than the old recognizer),
/// primed with your own names and words; falls back to SFSpeechRecognizer where SpeechAnalyzer can't run.
/// Shows live text while you talk. VoiceCleanup then turns the words into finished text.
@MainActor @Observable
final class KeelVoice {
    enum State: Equatable { case idle, preparing, listening, finishing }

    private(set) var state: State = .idle
    private(set) var finalized = ""            // settled text
    private(set) var volatile = ""             // the words still being worked out
    private(set) var level: Float = 0          // microphone level 0…1, for the waveform
    private(set) var error: String?
    private(set) var engineName = ""           // "SpeechAnalyzer" or "Speech" (shown in Settings → Keel Voice)

    var liveText: String { [finalized, volatile].filter { !$0.isEmpty }.joined(separator: " ") }
    var isActive: Bool { state != .idle }

    /// Every buffer the microphone hears (voice notes keep the recording). Called off the main thread.
    var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    private let audio = AVAudioEngine()
    private let router = TapRouter()
    private var feeder: Feeder?
    // SpeechAnalyzer
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Never>?
    // Fallback
    private var legacyRequest: SFSpeechAudioBufferRecognitionRequest?
    private var legacyTask: SFSpeechRecognitionTask?
    private var legacyDone: CheckedContinuation<Void, Never>?

    /// Standby (the Keel keyboard's session): the microphone keeps running between dictations, so Keel stays
    /// listening-ready in the background and each dictation starts at once. iOS shows its orange mic dot meanwhile.
    private(set) var inStandby = false

    // MARK: Microphone

    private func prepareAudio() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else {
            error = "Allow the microphone for Keel in Settings."; return false
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
            try session.setActive(true)
            guard session.isInputAvailable else { error = "No microphone is available right now."; return false }
            return true
        } catch { self.error = "Couldn't use the microphone: \(error.localizedDescription)"; return false }
    }

    /// Attaches to the microphone once; every dictation plugs into the router.
    private func startMic() throws {
        if !tapInstalled {
            let input = audio.inputNode.outputFormat(forBus: 0)
            let router = self.router
            audio.inputNode.installTap(onBus: 0, bufferSize: 2048, format: input) { buf, _ in router.route(buf) }
            tapInstalled = true
            router.onLevel = { [weak self] lvl in Task { @MainActor in self?.level = lvl } }
        }
        router.onBuffer = onBuffer
        if !audio.isRunning { audio.prepare(); try audio.start() }
    }

    /// Only touches the microphone if Keel attached to it: reading `inputNode` starts the audio hardware, and with
    /// nothing to stop that was a crash (an audio timeout aborts the app) when speech couldn't start at all.
    private var tapInstalled = false
    private func teardownAudio() {
        if audio.isRunning { audio.stop() }
        if tapInstalled { audio.inputNode.removeTap(onBus: 0); tapInstalled = false }
    }

    func enterStandby() async -> Bool {
        if inStandby { return true }
        guard await prepareAudio() else { return false }
        do { try startMic(); inStandby = true; return true }
        catch { self.error = error.localizedDescription; teardownAudio(); return false }
    }

    func leaveStandby() {
        guard inStandby else { return }
        inStandby = false
        if state == .idle { teardownAudio(); try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    // MARK: Start / stop

    func start(vocabulary: [String] = []) async {
        guard state == .idle else { return }
        error = nil; finalized = ""; volatile = ""; level = 0; engineName = ""
        state = .preparing
        if !inStandby { guard await prepareAudio() else { state = .idle; return } }
        do {
            // SpeechAnalyzer runs on this iPhone, so try it before asking for speech-recognition permission (iOS's
            // prompt for that talks about sending audio to Apple, which is about the older recognizer).
            var started = (try? await startAnalyzer(vocabulary: vocabulary)) ?? false
            if !started, await Self.speechAuthorized() {
                started = (try? await startAnalyzer(vocabulary: vocabulary)) ?? false
                if !started { try startLegacy(vocabulary: vocabulary); engineName = "Speech" }
                else { engineName = "SpeechAnalyzer" }
            } else if started { engineName = "SpeechAnalyzer" }
            guard started || engineName == "Speech" else {
                error = "Allow speech recognition for Keel in Settings to dictate."
                release(); state = .idle; return
            }
            try startMic()
            state = .listening
            Haptics.tap()
        } catch {
            self.error = "Couldn't start listening: \(error.localizedDescription)"
            release(); state = .idle
        }
    }

    /// Stops listening and returns everything heard (raw words, before cleanup).
    @discardableResult
    func stop() async -> String {
        guard state == .listening || state == .preparing else { return liveText }
        state = .finishing
        router.clear()
        if let analyzer {
            feeder?.finish()
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
            await resultsTask?.value
        } else if let legacyRequest {
            legacyRequest.endAudio()
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                legacyDone = c
                Task { try? await Task.sleep(for: .seconds(1.5)); self.finishLegacyWait() }     // never wait forever
            }
            legacyTask?.finish()
        }
        let text = liveText
        reset()
        return text
    }

    /// Stops and throws the words away.
    func cancel() {
        guard state != .idle else { return }
        router.clear()
        feeder?.finish()
        resultsTask?.cancel()
        legacyTask?.cancel()
        reset()
    }

    private func reset() {
        analyzer = nil; resultsTask = nil; feeder = nil
        legacyRequest = nil; legacyTask = nil
        volatile = ""; level = 0
        state = .idle
        release()
    }

    /// Lets go of the microphone, unless the keyboard session wants it kept ready.
    private func release() {
        router.clear()
        guard !inStandby else { return }
        teardownAudio()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func finishLegacyWait() { legacyDone?.resume(); legacyDone = nil }

    private static func speechAuthorized() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
    }

    // MARK: SpeechAnalyzer (iOS 26)

    private func startAnalyzer(vocabulary: [String]) async throws -> Bool {
        guard SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: VoiceLanguage.locale) else { return false }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
        // The language model downloads once (Apple keeps it on the device); after that dictation starts at once.
        if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) { try await install.downloadAndInstall() }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if !vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = Array(vocabulary.prefix(100))
            try? await analyzer.setContext(context)
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { return false }
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        try await analyzer.start(inputSequence: stream)
        resultsTask = Task { @MainActor [weak self] in
            do {
                for try await r in transcriber.results {
                    guard let self else { return }
                    let text = String(r.text.characters).trimmingCharacters(in: .whitespaces)
                    if r.isFinal {
                        if !text.isEmpty { self.finalized += (self.finalized.isEmpty ? "" : " ") + text }
                        self.volatile = ""
                    } else {
                        self.volatile = text
                    }
                }
            } catch { self?.error = error.localizedDescription }
        }
        let feeder = Feeder(output: format, continuation: continuation)
        self.feeder = feeder
        router.set(feeder: feeder)
        self.analyzer = analyzer
        return true
    }

    // MARK: Fallback: SFSpeechRecognizer

    private func startLegacy(vocabulary: [String]) throws {
        guard let recognizer = SFSpeechRecognizer(locale: VoiceLanguage.locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else { throw NSError(domain: "KeelVoice", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognition isn't available right now."]) }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        req.contextualStrings = Array(vocabulary.prefix(100))
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        legacyRequest = req
        router.set(legacy: req)
        legacyTask = recognizer.recognitionTask(with: req) { [weak self] r, err in
            let text = r?.bestTranscription.formattedString
            let done = r?.isFinal == true || err != nil
            Task { @MainActor in
                guard let self else { return }
                if let text { self.volatile = text }        // the old recognizer re-sends the whole text each time
                if done { self.finishLegacyWait() }
            }
        }
    }

    // MARK: Files (imports, and the engine's own tests)

    /// Transcribes a recording. Uses SpeechAnalyzer when it can, else the older recognizer.
    static func transcribe(file url: URL, vocabulary: [String] = []) async throws -> String {
        if SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: VoiceLanguage.locale) {
            let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
            if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) { try await install.downloadAndInstall() }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            if !vocabulary.isEmpty {
                let context = AnalysisContext()
                context.contextualStrings[.general] = Array(vocabulary.prefix(100))
                try? await analyzer.setContext(context)
            }
            async let collected: String = {
                var out: [String] = []
                for try await r in transcriber.results where r.isFinal { out.append(String(r.text.characters)) }
                return out.joined(separator: " ")
            }()
            let file = try AVAudioFile(forReading: url)
            try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
            return try await collected.trimmingCharacters(in: .whitespaces)
        }
        guard let recognizer = SFSpeechRecognizer(locale: VoiceLanguage.locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else { return "" }
        let req = SFSpeechURLRecognitionRequest(url: url)
        req.addsPunctuation = true
        req.contextualStrings = vocabulary
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        return try await withCheckedThrowingContinuation { c in
            var resumed = false
            recognizer.recognitionTask(with: req) { r, err in
                guard !resumed else { return }
                if let err { resumed = true; c.resume(throwing: err) }
                else if let r, r.isFinal { resumed = true; c.resume(returning: r.bestTranscription.formattedString) }
            }
        }
    }
}

/// Runs on the audio thread: hands each microphone buffer to whatever is listening now (or to nothing, in standby).
private final class TapRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var feeder: Feeder?
    private var legacy: SFSpeechAudioBufferRecognitionRequest?
    var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    var onLevel: (@Sendable (Float) -> Void)?
    private var lastLevel = Date.distantPast

    func set(feeder: Feeder) { lock.lock(); self.feeder = feeder; legacy = nil; lock.unlock() }
    func set(legacy: SFSpeechAudioBufferRecognitionRequest) { lock.lock(); self.legacy = legacy; feeder = nil; lock.unlock() }
    func clear() { lock.lock(); feeder = nil; legacy = nil; lock.unlock() }

    func route(_ buf: AVAudioPCMBuffer) {
        lock.lock(); let f = feeder, l = legacy, b = onBuffer, lv = onLevel; lock.unlock()
        guard f != nil || l != nil else { return }               // standby: heard, not kept
        b?(buf)
        if let lv, Date().timeIntervalSince(lastLevel) > 0.05 { lastLevel = Date(); lv(Feeder.level(of: buf)) }
        if let f { f.feed(buf) } else { l?.append(buf) }
    }
}

/// Converts the microphone's buffers to the analyzer's format and passes them on.
private final class Feeder: @unchecked Sendable {
    private var converter: AVAudioConverter?
    private var from: AVAudioFormat?
    private let output: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation

    init(output: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) {
        self.output = output
        self.continuation = continuation
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        if buffer.format == output { continuation.yield(AnalyzerInput(buffer: buffer)); return }
        if from != buffer.format { converter = AVAudioConverter(from: buffer.format, to: output); from = buffer.format }
        guard let converter else { return }
        let ratio = output.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return }
        var given = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true; status.pointee = .haveData; return buffer
        }
        if err == nil, out.frameLength > 0 { continuation.yield(AnalyzerInput(buffer: out)) }
    }

    func finish() { continuation.finish() }

    /// Loudness of a buffer as 0…1 (for the waveform).
    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let ch = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += ch[i] * ch[i] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        return min(1, max(0, (20 * log10(max(rms, 1e-6)) + 50) / 50))        // -50 dB … 0 dB
    }
}
