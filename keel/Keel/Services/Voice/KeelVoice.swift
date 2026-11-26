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
    private var feeder: Feeder?
    // SpeechAnalyzer
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Never>?
    // Fallback
    private var legacyRequest: SFSpeechAudioBufferRecognitionRequest?
    private var legacyTask: SFSpeechRecognitionTask?
    private var legacyDone: CheckedContinuation<Void, Never>?

    // MARK: Start / stop

    func start(vocabulary: [String] = []) async {
        guard state == .idle else { return }
        error = nil; finalized = ""; volatile = ""; level = 0; engineName = ""
        state = .preparing
        guard await AVAudioApplication.requestRecordPermission() else {
            error = "Allow the microphone for Keel in Settings."
            state = .idle; return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers])
            try session.setActive(true)
            guard session.isInputAvailable else {
                error = "No microphone is available right now."
                state = .idle; return
            }
            // SpeechAnalyzer runs on this iPhone, so try it before asking for speech-recognition permission (iOS's
            // prompt for that talks about sending audio to Apple, which is about the older recognizer).
            var started = (try? await startAnalyzer(vocabulary: vocabulary)) ?? false
            if !started, await Self.speechAuthorized() {
                teardownAudio()                              // a half-started attempt mustn't leave the mic attached
                started = (try? await startAnalyzer(vocabulary: vocabulary)) ?? false
                if !started { teardownAudio(); try startLegacy(vocabulary: vocabulary); engineName = "Speech" }
                else { engineName = "SpeechAnalyzer" }
            } else if started { engineName = "SpeechAnalyzer" }
            guard started || engineName == "Speech" else {
                error = "Allow speech recognition for Keel in Settings to dictate."
                teardownAudio(); state = .idle; return
            }
            state = .listening
            Haptics.tap()
        } catch {
            self.error = "Couldn't start listening: \(error.localizedDescription)"
            teardownAudio()
            state = .idle
        }
    }

    /// Stops listening and returns everything heard (raw words, before cleanup).
    @discardableResult
    func stop() async -> String {
        guard state == .listening || state == .preparing else { return liveText }
        state = .finishing
        teardownAudio()
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
        teardownAudio()
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
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Only touches the microphone if Keel attached to it: reading `inputNode` starts the audio hardware, and with
    /// nothing to stop that was a crash (an audio timeout aborts the app) when speech couldn't start at all.
    private var tapInstalled = false
    private func teardownAudio() {
        if audio.isRunning { audio.stop() }
        if tapInstalled { audio.inputNode.removeTap(onBus: 0); tapInstalled = false }
    }

    private func finishLegacyWait() { legacyDone?.resume(); legacyDone = nil }

    private static func speechAuthorized() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
    }

    // MARK: SpeechAnalyzer (iOS 26)

    private func startAnalyzer(vocabulary: [String]) async throws -> Bool {
        guard SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else { return false }
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
        let input = audio.inputNode.outputFormat(forBus: 0)
        let feeder = Feeder(input: input, output: format, continuation: continuation, onBuffer: onBuffer) { [weak self] lvl in
            Task { @MainActor in self?.level = lvl }
        }
        self.feeder = feeder
        audio.inputNode.installTap(onBus: 0, bufferSize: 2048, format: input) { buf, _ in feeder.feed(buf) }
        tapInstalled = true
        audio.prepare()
        try audio.start()
        self.analyzer = analyzer
        return true
    }

    // MARK: Fallback: SFSpeechRecognizer

    private func startLegacy(vocabulary: [String]) throws {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else { throw NSError(domain: "KeelVoice", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognition isn't available right now."]) }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        req.contextualStrings = Array(vocabulary.prefix(100))
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        legacyRequest = req
        let input = audio.inputNode.outputFormat(forBus: 0)
        let onBuffer = self.onBuffer
        tapInstalled = true
        audio.inputNode.installTap(onBus: 0, bufferSize: 2048, format: input) { [weak self] buf, _ in
            req.append(buf)
            onBuffer?(buf)
            let lvl = Feeder.level(of: buf)
            Task { @MainActor in self?.level = lvl }
        }
        audio.prepare()
        try audio.start()
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
        if SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) {
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
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else { return "" }
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

/// Runs on the audio thread: converts the microphone's buffers to the analyzer's format and passes them on.
private final class Feeder: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let output: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private let onLevel: @Sendable (Float) -> Void
    private var lastLevel = Date.distantPast

    init(input: AVAudioFormat, output: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation,
         onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?, onLevel: @escaping @Sendable (Float) -> Void) {
        self.converter = input == output ? nil : AVAudioConverter(from: input, to: output)
        self.output = output
        self.continuation = continuation
        self.onBuffer = onBuffer
        self.onLevel = onLevel
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        onBuffer?(buffer)
        if Date().timeIntervalSince(lastLevel) > 0.05 { lastLevel = Date(); onLevel(Self.level(of: buffer)) }   // ~20 updates a second
        guard let converter else { continuation.yield(AnalyzerInput(buffer: buffer)); return }
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
