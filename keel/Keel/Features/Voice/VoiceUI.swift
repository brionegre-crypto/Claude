import SwiftUI
import SwiftData

/// One Keel Voice session at a time, shared by every mic: who's listening, the live words, and the last result
/// (so "Use what I said" can put the raw words back).
@MainActor @Observable
final class KeelVoiceCenter {
    static let shared = KeelVoiceCenter()
    let engine = KeelVoice()

    enum Phase: Equatable { case idle, listening, cleaning, done(polished: Bool) }
    private(set) var phase: Phase = .idle
    private(set) var host: UUID?                  // which screen shows the bar
    private(set) var owner: UUID?                 // which mic is listening
    private var context: VoiceContext = .general
    private var insert: ((VoiceCleanup.Result) -> Void)?
    private var undoRaw: (() -> Void)?
    private var doneTimer: Task<Void, Never>?

    func isListening(_ mic: UUID) -> Bool { owner == mic && (phase == .listening || engine.isActive) }

    func start(mic: UUID, host: UUID?, context: VoiceContext, ctx: ModelContext, insert: @escaping (VoiceCleanup.Result) -> Void) {
        if engine.isActive { engine.cancel() }
        doneTimer?.cancel()
        owner = mic; self.host = host; self.context = context; self.insert = insert; undoRaw = nil
        phase = .listening
        let words = VoiceVocabulary.words(ctx)
        Task {
            await engine.start(vocabulary: words)
            if engine.error != nil { phase = .idle; owner = nil }
        }
        pendingCtx = ctx
    }
    private var pendingCtx: ModelContext?

    /// Stop, tidy up, put the words in.
    func finish() {
        guard phase == .listening else { return }
        phase = .cleaning
        Task {
            let raw = await engine.stop()
            let ctx = pendingCtx
            let result = await VoiceCleanup.clean(raw, context: context,
                                                  vocabulary: ctx.map(VoiceVocabulary.words) ?? [],
                                                  snippets: ctx.map(VoiceVocabulary.snippets) ?? [])
            guard !result.text.isEmpty else { phase = .idle; owner = nil; return }
            insert?(result)
            Haptics.success()
            phase = .done(polished: result.polished)
            doneTimer = Task { try? await Task.sleep(for: .seconds(5)); if !Task.isCancelled { phase = .idle; owner = nil; undoRaw = nil } }
        }
    }

    func cancel() {
        engine.cancel()
        phase = .idle; owner = nil
    }

    /// Registered by the mic that inserted the text: swaps the tidied words for exactly what was said.
    func setUndo(_ f: @escaping () -> Void) { undoRaw = f }
    func useWhatISaid() {
        undoRaw?(); undoRaw = nil
        doneTimer?.cancel(); phase = .idle; owner = nil
        Haptics.tap()
    }
    var canUseRaw: Bool { undoRaw != nil }
}

private struct VoiceHostKey: EnvironmentKey { static let defaultValue: UUID? = nil }
extension EnvironmentValues {
    var voiceHost: UUID? { get { self[VoiceHostKey.self] } set { self[VoiceHostKey.self] = newValue } }
}

/// Shows Keel Voice's bar on this screen (or sheet) while one of its mics is listening.
private struct VoiceHostModifier: ViewModifier {
    @State private var id = UUID()
    @State private var center = KeelVoiceCenter.shared
    func body(content: Content) -> some View {
        content
            .environment(\.voiceHost, id)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if center.host == id && center.phase != .idle {
                    VoiceBar().padding(.horizontal, 12).padding(.bottom, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.22), value: center.phase)
    }
}

extension View {
    /// Put on a screen or sheet that has Keel Voice mics; the listening bar appears at its bottom.
    func keelVoiceHost() -> some View { modifier(VoiceHostModifier()) }
}

/// The listening bar: a live waveform, the words as they come, Done and Cancel; then "Use what I said".
struct VoiceBar: View {
    @State private var center = KeelVoiceCenter.shared

    var body: some View {
        HStack(spacing: 12) {
            switch center.phase {
            case .listening:
                Waveform(level: center.engine.level).frame(width: 34, height: 22)
                Text(center.engine.liveText.isEmpty ? (center.engine.state == .preparing ? "Getting ready…" : "Listening…") : center.engine.liveText)
                    .font(DS.Font.body).foregroundStyle(center.engine.liveText.isEmpty ? DS.Palette.inkSoft : DS.Palette.ink)
                    .lineLimit(2).truncationMode(.head).frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.opacity)
                Button { center.cancel() } label: { Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 34, height: 34) }
                    .buttonStyle(.plain).foregroundStyle(DS.Palette.inkSoft).accessibilityLabel("Cancel dictation")
                Button { center.finish() } label: {
                    Image(systemName: "checkmark").font(.body.weight(.bold)).foregroundStyle(.white).frame(width: 34, height: 34)
                        .background(DS.Palette.accent, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("Done dictating")
            case .cleaning:
                ProgressView().controlSize(.small)
                Text("Tidying up…").font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft).frame(maxWidth: .infinity, alignment: .leading)
            case .done(let polished):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.Palette.calm)
                Text(polished ? "Tidied up" : "Added").font(DS.Font.body).frame(maxWidth: .infinity, alignment: .leading)
                if polished && center.canUseRaw {
                    Button("Use what I said") { center.useWhatISaid() }.font(DS.Font.caption.weight(.semibold))
                }
            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(DS.Palette.ink.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .overlay(alignment: .top) {
            if let e = center.engine.error { Text(e).font(.caption2).foregroundStyle(.red).offset(y: -18) }
        }
    }
}

private struct Waveform: View {
    let level: Float
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { t in
            let phase = t.date.timeIntervalSinceReferenceDate * 7
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    let wobble = 0.55 + 0.45 * sin(phase + Double(i) * 1.3)
                    Capsule().fill(DS.Palette.accent)
                        .frame(width: 3.5, height: max(4, 22 * CGFloat(level) * CGFloat(wobble)))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

/// A Keel Voice mic for a text field. Tap to start and tap again (or ✓) to finish; or hold, talk, and let go.
/// The tidied words go after what's already there; "Use what I said" swaps in the exact words.
struct KeelMicButton: View {
    @Binding var text: String
    var context: VoiceContext = .general
    /// Between existing text and the new words: a space for short fields, a blank line for longer writing.
    var separator: String = " "
    var size: CGFloat = 17
    /// Put the words above the first of these that's in the text (an email's signature or quoted reply), not at the end.
    var above: [String] = []

    @Environment(\.modelContext) private var ctx
    @Environment(\.voiceHost) private var host
    @State private var center = KeelVoiceCenter.shared
    @State private var id = UUID()
    @State private var holdTask: Task<Void, Never>?
    @State private var holding = false

    private var listening: Bool { center.isListening(id) }

    var body: some View {
        Image(systemName: listening ? "waveform" : "mic.fill")
            .font(.system(size: size, weight: .semibold))
            .symbolEffect(.variableColor.iterative, isActive: listening)
            .foregroundStyle(listening ? Color.white : DS.Palette.accent)
            .frame(width: size + 17, height: size + 17)
            .background(listening ? AnyShapeStyle(DS.Palette.accent) : AnyShapeStyle(DS.Palette.accent.opacity(0.12)), in: Circle())
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: 0.3, maximumDistance: 60, perform: {}, onPressingChanged: pressing)
            .accessibilityElement()
            .accessibilityLabel(listening ? "Stop dictating" : "Dictate")
            .accessibilityHint("Tap to talk, tap again to finish. Or hold, talk, and let go.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { toggle() }
            .accessibilityIdentifier("keelVoice.mic")
    }

    private func pressing(_ down: Bool) {
        if down {
            guard !listening else { return }
            holdTask = Task { try? await Task.sleep(for: .milliseconds(300)); guard !Task.isCancelled else { return }; holding = true; begin() }
        } else {
            holdTask?.cancel(); holdTask = nil
            if holding { holding = false; center.finish() }       // hold, talk, let go
            else { toggle() }                                      // a quick tap
        }
    }

    private func toggle() { if listening { center.finish() } else { begin() } }

    private func begin() {
        let binding = $text
        let sep = separator
        let anchors = above
        center.start(mic: id, host: host, context: context, ctx: ctx) { result in
            let place = Self.placer(binding.wrappedValue, separator: sep, above: anchors)
            binding.wrappedValue = place(result.text)
            if result.polished {
                let raw = result.raw
                KeelVoiceCenter.shared.setUndo { binding.wrappedValue = place(raw) }
            }
        }
    }

    /// Where new words go in `current`: after what you've written, above a signature or quoted reply if there is one.
    static func placer(_ current: String, separator: String, above: [String]) -> (String) -> String {
        if let a = above.first(where: { !$0.isEmpty && current.contains($0) }), let r = current.range(of: a) {
            let head = String(current[..<r.lowerBound]).replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
            let tail = String(current[r.lowerBound...])
            return { words in (head.isEmpty ? "" : head + separator) + words + "\n\n" + tail }
        }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "" : current.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
        return { words in base + (trimmed.isEmpty ? "" : separator) + words }
    }
}

// MARK: - Settings → Keel Voice

struct KeelVoiceSettings: View {
    @Environment(\.modelContext) private var ctx
    @AppStorage(VoiceCleanup.onKey) private var cleanup = true
    @State private var custom = VoiceVocabulary.custom
    @State private var newWord = ""
    @State private var learned: [String] = []
    @State private var tryText = ""
    @State private var work = VoiceVocabulary.work
    @State private var fieldTerms = VoiceVocabulary.fieldTerms
    @State private var generating = false

    var body: some View {
        Form {
            Section {
                Toggle("Tidy up as I speak", isOn: $cleanup)
            } footer: {
                Text("Removes “um” and repeats, keeps only your corrections (“Friday, no, Thursday”), adds punctuation and lists, and fits the tone to where you're writing. Apple Intelligence does it on this iPhone; Claude only if Apple Intelligence can't and you've connected it. “Use what I said” always puts back your exact words.")
            }
            Section {
                TextField("e.g. Pastor and men's coach, ICU nurse, tax attorney", text: $work, axis: .vertical)
                    .onSubmit(saveWork)
                if work.isEmpty, let hint = VoiceVocabulary.workFromMemory {
                    Button("Use: “\(hint)”") { work = hint; saveWork() }.font(DS.Font.caption)
                }
                if work != VoiceVocabulary.work {
                    Button(generating ? "Learning your field's words…" : "Save and learn my field's words") { saveWork() }.disabled(generating)
                }
            } header: { Text("Your work") } footer: {
                Text("Keel Voice uses your field's terms, names and spellings, and Apple Intelligence suggests the words people in it say (you can remove any). It's also saved to what Keel knows about you.")
            }
            if !fieldTerms.isEmpty {
                Section {
                    ForEach(fieldTerms, id: \.self) { Text($0) }
                        .onDelete { fieldTerms.remove(atOffsets: $0); VoiceVocabulary.fieldTerms = fieldTerms }
                    Button("Suggest again") { Task { generating = true; fieldTerms = await VoiceVocabulary.generateFieldTerms(); generating = false } }
                        .disabled(generating)
                } header: { Text("Words from your field") }
            }
            Section {
                ForEach(custom, id: \.self) { Text($0) }
                    .onDelete { custom.remove(atOffsets: $0); VoiceVocabulary.custom = custom; VoiceVocabulary.forget() }
                HStack {
                    TextField("Add a name or word", text: $newWord).onSubmit(add)
                    Button("Add", action: add).disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: { Text("Your words") } footer: {
                Text("Names, places and terms Keel Voice should always spell your way.")
            }
            if !learned.isEmpty {
                Section {
                    Text(learned.prefix(30).joined(separator: " · ")).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                } header: { Text("Also listening for") } footer: { Text("Names and terms you use most in your notes, tasks, calendar and email, plus your people, projects and lists. Worked out on this iPhone; nothing leaves it.") }
            }
            Section {
                HStack(alignment: .top) {
                    TextField("Try it: tap or hold the mic", text: $tryText, axis: .vertical).lineLimit(2...6)
                    KeelMicButton(text: $tryText, context: .note, separator: "\n\n")
                }
            } header: { Text("Try it") } footer: {
                Text("Tap the mic to talk and tap again to finish, or hold it while you talk and let go. Say “new line”, “new paragraph”, “bullet point” or “scratch that”, and “insert …” with a Snippet's name.")
            }
        }
        .navigationTitle("Keel Voice")
        .keelVoiceHost()
        .task {
            learned = VoiceVocabulary.words(ctx).filter { w in !custom.contains(w) }
            await VoiceVocabulary.mine(ctx)                      // at most once a day
            learned = VoiceVocabulary.words(ctx).filter { w in !custom.contains(w) }
        }
    }

    private func saveWork() {
        VoiceVocabulary.work = work
        Task { generating = true; fieldTerms = await VoiceVocabulary.generateFieldTerms(); generating = false; VoiceVocabulary.forget() }
    }

    private func add() {
        let w = newWord.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty, !custom.contains(w) else { return }
        custom.append(w); VoiceVocabulary.custom = custom; VoiceVocabulary.forget()
        newWord = ""
    }
}
