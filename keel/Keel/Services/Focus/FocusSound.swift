import AVFoundation

/// Focus sounds generated on-device (no downloads): brown, pink and white noise, and ocean waves.
@MainActor
final class FocusSound {
    static let shared = FocusSound()

    enum Kind: String, CaseIterable, Identifiable {
        case off, brown, pink, white, ocean
        var id: String { rawValue }
        var label: String { rawValue == "off" ? "Off" : rawValue.capitalized + (self == .ocean ? " waves" : " noise") }
    }

    /// Audio-thread state (kept off the main actor; only the render block touches it).
    private final class Generator: @unchecked Sendable {
        var kind: Kind = .brown
        var brown: Float = 0
        var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
        var phase: Double = 0
        var sampleRate: Double = 44_100
        var volume: Float = 0.35

        func next() -> Float {
            let white = Float.random(in: -1...1)
            switch kind {
            case .white, .off:
                return white * 0.5
            case .brown:
                brown = (brown + 0.02 * white) / 1.02
                return brown * 3.5
            case .pink, .ocean:
                // Paul Kellet's pink-noise filter
                b0 = 0.99886 * b0 + white * 0.0555179; b1 = 0.99332 * b1 + white * 0.0750759
                b2 = 0.96900 * b2 + white * 0.1538520; b3 = 0.86650 * b3 + white * 0.3104856
                b4 = 0.55000 * b4 + white * 0.5329522; b5 = -0.7616 * b5 - white * 0.0168980
                let pink = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362) * 0.11
                b6 = white * 0.115926
                guard kind == .ocean else { return pink }
                // Slow swell, roughly one wave every 8 seconds
                phase += 1 / sampleRate
                let swell = Float(0.55 + 0.45 * sin(2 * Double.pi * phase / 8))
                return pink * swell * swell * 1.4
            }
        }
    }

    private let engine = AVAudioEngine()
    private let generator = Generator()
    private var node: AVAudioSourceNode?
    private(set) var playing: Kind = .off

    func play(_ kind: Kind) {
        guard kind != .off else { stop(); return }
        generator.kind = kind
        if node == nil {
            let format = engine.outputNode.inputFormat(forBus: 0)
            generator.sampleRate = format.sampleRate
            let gen = generator
            let source = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
                let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
                for frame in 0..<Int(frameCount) {
                    let v = gen.next() * gen.volume
                    for buffer in buffers {
                        buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = v
                    }
                }
                return noErr
            }
            engine.attach(source)
            engine.connect(source, to: engine.mainMixerNode,
                           format: AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1))
            node = source
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning { try engine.start() }
            playing = kind
        } catch {
            playing = .off
        }
    }

    func stop() {
        engine.pause()
        playing = .off
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
