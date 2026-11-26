import SwiftUI
import SwiftData

/// What a mic writes into. Each mic makes one: Keel Voice puts words in at once, upgrades them when they're
/// polished (only if you haven't touched them), edits the text on "Keel, …", and can swap in your exact words.
struct VoiceTarget {
    /// The text already there (context for the polish, and what "Keel, …" edits).
    var current: () -> String
    /// Put new words in. Returns false if it couldn't.
    var insert: (String) -> Void
    /// Replace the words just put in (`old`) with `new`, if they're still exactly there. True if it did.
    var replace: (_ old: String, _ new: String) -> Bool
    /// Replace the editable text as a whole ("Keel, make this shorter").
    var setAll: (String) -> Void
}

/// One Keel Voice session at a time, shared by every mic.
@MainActor @Observable
final class KeelVoiceCenter {
    static let shared = KeelVoiceCenter()
    let engine = KeelVoice()

    enum Phase: Equatable {
        case idle, listening
        case working(String)                           // "Editing: make it shorter"
        case inserted(polishing: Bool)                 // the words are in; polishing may still be running
        case done(String, undo: String?)               // "Tidied up" + "Use what I said" / "Undo edit"
    }
    private(set) var phase: Phase = .idle
    private(set) var host: UUID?                       // which screen shows the bar
    private(set) var owner: UUID?                      // which mic is listening
    private var context: VoiceContext = .general
    private var target: VoiceTarget?
    private var ctx: ModelContext?
    private var undo: (() -> Void)?
    private var doneTimer: Task<Void, Never>?
    /// The last words a mic put in, so the mic can learn from your fixes to them.
    private(set) var lastInserted: (mic: UUID, text: String, at: Date)?

    func isListening(_ mic: UUID) -> Bool { owner == mic && phase == .listening }
    func isBusy(_ mic: UUID) -> Bool { owner == mic && phase != .idle }

    func start(mic: UUID, host: UUID?, context: VoiceContext, ctx: ModelContext, target: VoiceTarget) {
        if engine.isActive { engine.cancel() }
        doneTimer?.cancel()
        owner = mic; self.host = host; self.context = context; self.target = target; self.ctx = ctx; undo = nil
        phase = .listening
        let words = VoiceVocabulary.words(ctx)
        Task {
            await engine.start(vocabulary: words)
            if engine.error != nil { phase = .idle; owner = nil }
        }
    }

    /// Stop; put the words in at once (instant cleanup); then upgrade them in place when the polish is ready.
    func finish() {
        guard phase == .listening, let target else { return }
        phase = .working("")
        Task {
            let raw = await engine.stop().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { end(); return }
            let words = ctx.map(VoiceVocabulary.words) ?? []
            let snippets = ctx.map(VoiceVocabulary.snippets) ?? []

            // "Keel, …": an instruction for the text, not words to type.
            if let instruction = VoiceCommandMode.instruction(in: raw) {
                phase = .working("Keel: " + instruction)
                let before = target.current()
                if let out = await VoiceCommandMode.apply(instruction, to: before, context: context) {
                    target.setAll(out)
                    lastInserted = nil
                    undo = { target.setAll(before) }
                    Haptics.success()
                    show(before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Written" : "Edited", undo: "Undo")
                } else {
                    show("Couldn't do that one. Nothing changed.", undo: nil)
                }
                return
            }

            let before = target.current()
            let quick = VoiceCleanup.quick(raw, context: context, vocabulary: words, snippets: snippets)
            guard !quick.isEmpty else { end(); return }
            target.insert(quick)                                   // instant: no waiting on AI
            lastInserted = (owner ?? UUID(), quick, Date())
            Haptics.success()
            var shown = quick
            undo = { _ = target.replace(shown, raw) }
            phase = .inserted(polishing: VoiceCleanup.isOn)
            if let polished = await VoiceCleanup.polish(quick, context: context, vocabulary: words, snippets: snippets, before: before),
               target.replace(quick, polished) {
                shown = polished
                lastInserted = (owner ?? UUID(), polished, Date())
                undo = { _ = target.replace(shown, raw) }
                show("Tidied up", undo: "Use what I said")
            } else {
                show("Added", undo: raw != quick ? "Use what I said" : nil)
            }
        }
    }

    private func show(_ message: String, undo label: String?) {
        phase = .done(message, undo: label)
        doneTimer = Task { try? await Task.sleep(for: .seconds(5)); if !Task.isCancelled { end() } }
    }

    private func end() { phase = .idle; owner = nil; undo = nil; target = nil }

    func cancel() { engine.cancel(); end() }

    func runUndo() {
        undo?(); undo = nil
        lastInserted = nil
        doneTimer?.cancel(); end()
        Haptics.tap()
    }
}

private struct VoiceHostKey: EnvironmentKey { static let defaultValue: UUID? = nil }
extension EnvironmentValues {
    var voiceHost: UUID? { get { self[VoiceHostKey.self] } set { self[VoiceHostKey.self] = newValue } }
}

/// Shows Keel Voice's bar on this screen (or sheet) while one of its mics is busy.
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

/// The bar: a live waveform and your words as they come, then what happened, with Undo / "Use what I said".
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
                Button { center.cancel() } label: { Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 34, height: 34) }
                    .buttonStyle(.plain).foregroundStyle(DS.Palette.inkSoft).accessibilityLabel("Cancel dictation")
                Button { center.finish() } label: {
                    Image(systemName: "checkmark").font(.body.weight(.bold)).foregroundStyle(.white).frame(width: 34, height: 34)
                        .background(DS.Palette.accent, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("Done dictating")
            case .working(let what):
                ProgressView().controlSize(.small)
                Text(what.isEmpty ? "One moment…" : what).font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .inserted(let polishing):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.Palette.calm)
                Text(polishing ? "Added · polishing…" : "Added").font(DS.Font.body).frame(maxWidth: .infinity, alignment: .leading)
                if polishing { ProgressView().controlSize(.mini) }
            case .done(let message, let undo):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.Palette.calm)
                Text(message).font(DS.Font.body).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                if let undo { Button(undo) { center.runUndo() }.font(DS.Font.caption.weight(.semibold)) }
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
/// Words go after what's there (above an email's signature); "Keel, …" edits the text instead.
struct KeelMicButton: View {
    @Binding var text: String
    var context: VoiceContext = .general
    /// Between existing text and the new words: a space for short fields, a blank line for longer writing.
    var separator: String = " "
    var size: CGFloat = 17
    /// Put the words above the first of these that's in the text (an email's signature or quoted reply), not at the end.
    var above: [String] = []
    /// A custom place for the words (notes put them in as blocks); nil writes into `text`.
    var customTarget: VoiceTarget? = nil

    @Environment(\.modelContext) private var ctx
    @Environment(\.voiceHost) private var host
    @State private var center = KeelVoiceCenter.shared
    @State private var id = UUID()
    @State private var holdTask: Task<Void, Never>?
    @State private var holding = false
    @State private var snapshot: String?               // the field right after Keel Voice wrote in it (to learn from your fixes)

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
            .accessibilityHint("Tap to talk, tap again to finish. Or hold, talk, and let go. Start with “Keel” to edit what's written.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { toggle() }
            .accessibilityIdentifier("keelVoice.mic")
            .onChange(of: text) { _, now in learnFromFix(now) }
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
        center.start(mic: id, host: host, context: context, ctx: ctx, target: customTarget ?? fieldTarget())
    }

    /// Writes into `text`: after what's there, or above a signature / quoted reply.
    private func fieldTarget() -> VoiceTarget {
        let binding = $text, sep = separator, anchors = above
        var place: ((String) -> String)?
        return VoiceTarget(
            current: { Self.split(binding.wrappedValue, above: anchors).head },
            insert: { words in
                let p = Self.placer(binding.wrappedValue, separator: sep, above: anchors)
                place = p
                binding.wrappedValue = p(words)
                snapshotLater(binding.wrappedValue)
            },
            replace: { old, new in
                guard let p = place, binding.wrappedValue == p(old) else { return false }    // you've edited it since: leave it
                binding.wrappedValue = p(new)
                snapshotLater(binding.wrappedValue)
                return true
            },
            setAll: { new in
                let parts = Self.split(binding.wrappedValue, above: anchors)
                binding.wrappedValue = parts.tail.map { new + "\n\n" + $0 } ?? new
                snapshotLater(nil)
            })
    }

    private func snapshotLater(_ value: String?) {
        // After SwiftUI applies the change, so onChange doesn't take our own write for your fix.
        Task { @MainActor in snapshot = value }
    }

    /// You typed over a word Keel Voice wrote ("Shal" → "Shah"): remember the spelling.
    private func learnFromFix(_ now: String) {
        guard let before = snapshot, before != now, let last = center.lastInserted, last.mic == id,
              Date().timeIntervalSince(last.at) < 600 else { return }
        if let word = VoiceLearning.correction(dictated: last.text, before: before, after: now) {
            VoiceLearning.add(word)
        }
        snapshot = now
    }

    /// The text split at the first signature / quoted reply: what you're writing, and what stays below it.
    static func split(_ current: String, above: [String]) -> (head: String, tail: String?) {
        if let a = above.first(where: { !$0.isEmpty && current.contains($0) }), let r = current.range(of: a) {
            let head = String(current[..<r.lowerBound]).replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
            return (head, String(current[r.lowerBound...]))
        }
        return (current, nil)
    }

    /// Where new words go in `current`: after what you've written, above a signature or quoted reply if there is one.
    static func placer(_ current: String, separator: String, above: [String]) -> (String) -> String {
        let parts = split(current, above: above)
        if let tail = parts.tail {
            let head = parts.head
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
    @State private var language = VoiceLanguage.chosen
    @State private var languages: [Locale] = []
    @State private var fixes = VoiceLearning.learned

    var body: some View {
        Form {
            Section {
                Toggle("Tidy up as I speak", isOn: $cleanup)
            } footer: {
                Text("Removes “um” and repeats, keeps only your corrections (“Friday, no, Thursday”), adds punctuation and lists, and fits the tone to where you're writing. Apple Intelligence does it on this iPhone; Claude only if Apple Intelligence can't and you've connected it. “Use what I said” always puts back your exact words.")
            }
            Section {
                Picker("Language", selection: $language) {
                    Text("iPhone's language").tag("")
                    ForEach(languages, id: \.identifier) { l in Text(VoiceLanguage.name(l)).tag(l.identifier) }
                }
                .onChange(of: language) { _, l in VoiceLanguage.chosen = l }
            } footer: { Text("Keel Voice listens on this iPhone in the language you pick; the first time, Apple downloads it once.") }
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
            if !fixes.isEmpty {
                Section {
                    ForEach(fixes, id: \.self) { Text($0) }
                        .onDelete { offs in offs.map { fixes[$0] }.forEach(VoiceLearning.forget); fixes = VoiceLearning.learned }
                } header: { Text("Learned from your fixes") } footer: {
                    Text("When you correct a name or term Keel Voice wrote, it remembers your spelling.")
                }
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
                Text("Tap the mic to talk and tap again to finish, or hold it while you talk and let go. Say “new line”, “new paragraph”, “bullet point” or “scratch that”, and “insert …” with a Snippet's name. Start with “Keel” to edit what's written (“Keel, make this shorter”, “Keel, make it warmer”) or to have it written (“Keel, write a thank-you to Sam for the deck”).")
            }
        }
        .navigationTitle("Keel Voice")
        .keelVoiceHost()
        .task {
            languages = await VoiceLanguage.available()
            fixes = VoiceLearning.learned
            learned = VoiceVocabulary.words(ctx).filter { w in !custom.contains(w) && !fixes.contains(w) }
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
