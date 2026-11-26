import UIKit
import SwiftUI

/// The Keel keyboard: Keel Voice in any app. iOS doesn't let keyboards use the microphone, so (like Wispr Flow)
/// the keyboard asks the Keel app to listen and types what Keel sends back: first the words, then, a moment later,
/// the tidied version (only if you haven't typed since).
final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private let keysView = KeysView()
    private let assist = TextAssist()
    static let barHeight: CGFloat = 46

    /// The system keyboard's own background and key clicks (UIInputViewAudioFeedback).
    override func loadView() {
        let v = ClickInputView(frame: .zero, inputViewStyle: .keyboard)
        v.allowsSelfSizing = true
        inputView = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        model.controller = self
        model.assist = assist
        assist.proxy = textDocumentProxy
        // The Keel Voice bar on top (also suggestions while you type).
        let host = UIHostingController(rootView: KeyboardBar(model: model))
        host.view.backgroundColor = .clear
        host.sizingOptions = []
        addChild(host)
        view.addSubview(host.view)
        view.addSubview(keysView)                         // above the bar, so the top row's popups can rise over it
        host.view.translatesAutoresizingMaskIntoConstraints = false
        keysView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.heightAnchor.constraint(equalToConstant: Self.barHeight),
            keysView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keysView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keysView.topAnchor.constraint(equalTo: host.view.bottomAnchor),
            keysView.heightAnchor.constraint(equalToConstant: KeysView.height),
            keysView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        wireKeys()
    }

    private func wireKeys() {
        let k = keysView, a = assist, m = model
        k.atSentenceStart = { a.atSentenceStart }
        k.onType = { s in a.type(s); m.textEdited() }
        k.onPunctuation = { s in a.punctuation(s); m.textEdited() }
        k.onSpace = { a.space(); m.textEdited() }
        k.onReturn = { a.newline(); m.textEdited() }
        k.onDelete = { a.delete(); m.textEdited() }
        k.onDeleteWord = { a.deleteWord(); m.textEdited() }
        k.onMoveCursor = { [weak self] n in self?.textDocumentProxy.adjustTextPosition(byCharacterOffset: n) }
        k.onGlobe = { [weak self] view, event in
            guard let self, let event else { return }
            self.handleInputModeList(from: view, with: event)
        }
        k.onSwipe = { path, keys in
            let words = SwipeDecoder.shared.decode(path: path, centre: { keys.centre(of: $0) }, nearest: { keys.nearestLetters($0, $1) }, keyWidth: keys.keyWidth)
            guard let first = words.first else { return }
            let cap = keys.shift != .off || a.atSentenceStart
            a.insertSwiped(first, capitalise: cap)
            m.swiped(first, alternatives: Array(words.dropFirst()), capitalised: cap)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.appeared()
        refreshReturnKey()
        keysView.showsGlobe = needsInputModeSwitchKey
        keysView.autoShift()
    }

    /// iOS tells the keyboard when the text or cursor changes (also right after it appears).
    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        refreshReturnKey()
        keysView.autoShift()
        model.textEdited()
    }

    /// The return key says what the app wants ("Send", "Search", "Go"…), blue like Apple's when it's an action.
    private func refreshReturnKey() {
        let t = textDocumentProxy.returnKeyType ?? .default
        let titles: [UIReturnKeyType: String] = [.go: "go", .google: "search", .join: "join", .next: "next", .route: "route",
                                                 .search: "search", .send: "send", .yahoo: "search", .done: "done",
                                                 .emergencyCall: "emergency", .continue: "continue"]
        keysView.returnTitle = titles[t]
        keysView.returnIsBlue = [.go, .google, .join, .route, .search, .send, .yahoo, .done, .continue].contains(t)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        model.disappeared()
    }

    /// Opens the Keel app. Keyboards can't use UIApplication.shared, so this finds the application object in the
    /// responder chain and calls its open-URL method directly (what dictation keyboards like Flow do).
    func openKeel(_ url: URL) {
        let sel = NSSelectorFromString("openURL:options:completionHandler:")
        var r: UIResponder? = self
        while let x = r {
            if x is UIApplication, x.responds(to: sel) {
                typealias Open = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                unsafeBitCast(x.method(for: sel), to: Open.self)(x, sel, url as NSURL, NSDictionary(), nil)
                return
            }
            r = x.next
        }
    }
}

/// The keyboard's state, kept in step with the Keel app through VoiceBridge.
@MainActor @Observable
final class KeyboardModel {
    weak var controller: KeyboardViewController?
    var assist: TextAssist?
    /// The bar's three suggestions while you type (or the other words a slide could have meant).
    private(set) var suggestions: [String] = []
    private var lastSwipe: (word: String, alternatives: [String])?
    private(set) var state: VoiceBridge.State = .off
    private(set) var partial = ""
    private(set) var alive = false
    private(set) var note: String?            // "Opening Keel…", "Turn on Allow Full Access…"
    private var poll: Timer?
    private var handled: UUID?
    private var sent: Set<UUID> = []
    private var observing = false

    var hasFullAccess: Bool { controller?.hasFullAccess ?? false }
    var listening: Bool { alive && state == .listening }
    var working: Bool { alive && state == .working }
    var needsGlobe: Bool { controller?.needsInputModeSwitchKey ?? true }

    func appeared() {
        handled = VoiceBridge.result?.id                 // don't type an old result again
        refresh()
        if !observing {
            observing = true
            VoiceBridge.observe(.result) { [weak self] in self?.refresh() }
            VoiceBridge.observe(.partial) { [weak self] in self?.refresh() }
            VoiceBridge.observe(.state) { [weak self] in self?.refresh() }
        }
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func disappeared() { poll?.invalidate(); poll = nil }

    private func refresh() {
        guard hasFullAccess else { alive = false; state = .off; return }
        alive = VoiceBridge.sessionAlive
        state = VoiceBridge.state
        partial = state == .listening ? VoiceBridge.partial : ""
        if alive, note == "Opening Keel…" { note = nil }
        if let r = VoiceBridge.result, r.id != handled, sent.contains(r.request) {
            handled = r.id
            type(r)
        }
    }

    private func type(_ r: VoiceBridge.Result) {
        guard let proxy = controller?.textDocumentProxy else { return }
        guard let e = VoiceBridge.edit(for: r, before: proxy.documentContextBeforeInput ?? "") else { return }
        for _ in 0..<e.delete { proxy.deleteBackward() }
        proxy.insertText(e.insert)
    }

    /// Tap: start or finish. Before the session is running, this opens Keel once to turn the microphone on.
    func mic() {
        guard hasFullAccess else {
            note = "Turn on Allow Full Access: Settings → General → Keyboard → Keyboards → Keel."
            return
        }
        if listening { VoiceBridge.post(.stop); return }
        guard !working else { return }
        let req = VoiceBridge.Request(before: String((controller?.textDocumentProxy.documentContextBeforeInput ?? "").suffix(1_500)), kind: fieldKind())
        sent.insert(req.id)
        VoiceBridge.request = req
        if alive {
            VoiceBridge.post(.start)
        } else {
            note = "Opening Keel…"
            controller?.openKeel(URL(string: "com.keel.app://voice-session?start=1")!)
        }
    }

    func cancel() { VoiceBridge.post(.cancel) }

    /// What the field is, from the keyboard settings the app gave it.
    private func fieldKind() -> String {
        guard let t = controller?.textDocumentProxy else { return "general" }
        switch t.returnKeyType {
        case .send: return "message"
        case .search, .google, .yahoo, .go: return "search"
        default: break
        }
        if t.keyboardType == .emailAddress || t.keyboardType == .URL || t.keyboardType == .webSearch { return "search" }
        return "general"
    }

    // Suggestions
    func textEdited() {
        guard let a = assist else { return }
        if let sw = lastSwipe, (controller?.textDocumentProxy.documentContextBeforeInput ?? "").hasSuffix(sw.word) {
            suggestions = Array(([sw.word] + sw.alternatives).prefix(3))
        } else {
            lastSwipe = nil
            suggestions = a.suggestions()
        }
    }

    func swiped(_ word: String, alternatives: [String], capitalised: Bool) {
        let alts = alternatives.map { capitalised ? $0.prefix(1).uppercased() + $0.dropFirst() : $0 }
        let w = capitalised ? word.prefix(1).uppercased() + word.dropFirst() : word
        lastSwipe = (w, alts)
        suggestions = Array(([w] + alts).prefix(3))
    }

    func choose(_ s: String) {
        guard let a = assist else { return }
        if let sw = lastSwipe {
            a.replaceSwiped(sw.word, with: s)
            lastSwipe = (s, ([sw.word] + sw.alternatives).filter { $0 != s })
        } else {
            a.accept(s.trimmingCharacters(in: CharacterSet(charactersIn: "“”")))
        }
        textEdited()
    }

    func dismissNote() { note = nil }
    /// Bumped when the text around the cursor changes, so the keys can update the automatic capital.
    private(set) var contextVersion = 0
    func contextChanged() { contextVersion += 1 }
}

/// The system keyboard view with key clicks (Settings → Sounds → Keyboard Clicks).
final class ClickInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

/// The bar above the keys: Keel Voice (status, live words, the mic) and, while you type, three suggestions like
/// Apple's predictive bar.
struct KeyboardBar: View {
    let model: KeyboardModel
    @State private var holdTask: Task<Void, Never>?
    @State private var holding = false

    var body: some View {
        HStack(spacing: 8) {
            if showStatus {
                if model.listening { Image(systemName: "waveform").symbolEffect(.variableColor.iterative).foregroundStyle(.red) }
                else if model.working { ProgressView().controlSize(.small) }
                Text(status).font(.subheadline).foregroundStyle(model.listening && !model.partial.isEmpty ? .primary : .secondary)
                    .lineLimit(2).truncationMode(.head).frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture { model.dismissNote() }
                if model.listening {
                    Button { model.cancel() } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary) }
                        .accessibilityLabel("Cancel dictation")
                }
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(model.suggestions.enumerated()), id: \.offset) { i, s in
                        if i > 0 { Divider().frame(height: 22) }
                        Button { model.choose(s) } label: {
                            Text(s).font(.system(size: 17)).lineLimit(1).frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.plain)
                    }
                    if model.suggestions.isEmpty { Text(status).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                }
            }
            ZStack {
                Capsule().fill(model.listening ? Color.red : Color.accentColor).frame(width: 56, height: 36)
                Image(systemName: model.listening ? "stop.fill" : "mic.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
            }
            .contentShape(Capsule())
            .onLongPressGesture(minimumDuration: 0.3, maximumDistance: 60, perform: {}, onPressingChanged: pressing)
            .accessibilityElement()
            .accessibilityLabel(model.listening ? "Stop dictating" : "Dictate with Keel Voice")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.mic() }
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
    }

    private var showStatus: Bool { model.listening || model.working || model.note != nil || !model.hasFullAccess || model.suggestions.isEmpty }

    private var status: String {
        if let n = model.note { return n }
        if !model.hasFullAccess { return "Turn on Allow Full Access for Keel to dictate." }
        if model.listening { return model.partial.isEmpty ? "Listening…" : model.partial }
        if model.working { return "Tidying up…" }
        return model.alive ? "Tap the mic and talk · “Keel, …” edits" : "Tap the mic to talk with Keel Voice"
    }

    private func pressing(_ down: Bool) {
        if down {
            guard !model.listening else { return }
            holdTask = Task { try? await Task.sleep(for: .milliseconds(300)); guard !Task.isCancelled else { return }; holding = true; model.mic() }
        } else {
            holdTask?.cancel(); holdTask = nil
            if holding { holding = false; if model.listening || model.alive { VoiceBridge.post(.stop) } }
            else { model.mic() }
        }
    }
}
