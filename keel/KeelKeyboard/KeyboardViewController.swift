import UIKit
import SwiftUI

/// The Keel keyboard: Keel Voice in any app. iOS doesn't let keyboards use the microphone, so (like Wispr Flow)
/// the keyboard asks the Keel app to listen and types what Keel sends back: first the words, then, a moment later,
/// the tidied version (only if you haven't typed since).
final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        model.controller = self
        let host = UIHostingController(rootView: KeyboardView(model: model, globe: GlobeKey(controller: self)))
        host.view.backgroundColor = .clear
        host.sizingOptions = []
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.heightAnchor.constraint(equalToConstant: 268),
        ])
        host.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.appeared()
    }

    /// iOS tells the keyboard when the text or cursor changes (also right after it appears): recheck the capital.
    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        model.contextChanged()
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

    // Keys
    func type(_ s: String) { controller?.textDocumentProxy.insertText(s) }
    /// True at the start of the field or after ". ", "? ", "! " or a new line (for the automatic capital).
    var atSentenceStart: Bool {
        let before = controller?.textDocumentProxy.documentContextBeforeInput ?? ""
        let t = before.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression)
        return t.isEmpty || before.hasSuffix("\n") || ((t.hasSuffix(".") || t.hasSuffix("?") || t.hasSuffix("!")) && before.hasSuffix(" "))
    }
    func space() { controller?.textDocumentProxy.insertText(" ") }
    func newline() { controller?.textDocumentProxy.insertText("\n") }
    func delete() { controller?.textDocumentProxy.deleteBackward() }
    func dismissNote() { note = nil }
    /// Bumped when the text around the cursor changes, so the keys can update the automatic capital.
    private(set) var contextVersion = 0
    func contextChanged() { contextVersion += 1 }
}

/// The 🌐 key: has to be a UIKit control so iOS can show the keyboard list on it.
struct GlobeKey: UIViewRepresentable {
    weak var controller: UIInputViewController?
    func makeUIView(context: Context) -> UIButton {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "globe"), for: .normal)
        b.tintColor = .label
        b.accessibilityLabel = "Next keyboard"
        if let c = controller { b.addTarget(c, action: #selector(UIInputViewController.handleInputModeList(from:with:)), for: .allTouchEvents) }
        return b
    }
    func updateUIView(_ uiView: UIButton, context: Context) {}
}

/// A full keyboard with Keel Voice built in (like Flow): letters, numbers and symbols, and a mic always one tap
/// away in the bar on top, which also shows your words as you talk.
struct KeyboardView: View {
    let model: KeyboardModel
    let globe: GlobeKey
    @State private var holdTask: Task<Void, Never>?
    @State private var holding = false
    @State private var deleteTimer: Timer?
    @State private var page: Page = .letters
    @State private var shift: Shift = .off
    @State private var lastShiftTap = Date.distantPast

    enum Page { case letters, numbers, symbols }
    enum Shift { case off, once, locked }

    private static let letters = [["q","w","e","r","t","y","u","i","o","p"], ["a","s","d","f","g","h","j","k","l"], ["z","x","c","v","b","n","m"]]
    private static let numbers = [["1","2","3","4","5","6","7","8","9","0"], ["-","/",":",";","(",")","$","&","@","\""], [".",",","?","!","'"]]
    private static let symbols = [["[","]","{","}","#","%","^","*","+","="], ["_","\\","|","~","<",">","€","£","¥","•"], [".",",","?","!","'"]]

    var body: some View {
        VStack(spacing: 8) {
            voiceBar
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                HStack(spacing: 5) {
                    if i == 2 { leftOfThirdRow }
                    ForEach(row, id: \.self) { k in charKey(k) }
                    if i == 2 { deleteKey }
                }
                .padding(.horizontal, i == 1 && page == .letters ? 18 : 3)
            }
            HStack(spacing: 5) {
                Button { page = page == .letters ? .numbers : .letters } label: { Text(page == .letters ? "123" : "ABC").frame(width: 46, height: 42) }
                    .buttonStyle(.plain).background(special, in: .rect(cornerRadius: 6))
                if model.needsGlobe { globe.frame(width: 42, height: 42).background(special, in: .rect(cornerRadius: 6)) }
                Button { model.space(); autoShift() } label: { Text("space").frame(maxWidth: .infinity, minHeight: 42) }
                    .buttonStyle(.plain).background(key, in: .rect(cornerRadius: 6))
                Button { model.newline(); autoShift() } label: { Image(systemName: "return").frame(width: 70, height: 42) }
                    .buttonStyle(.plain).background(special, in: .rect(cornerRadius: 6)).accessibilityLabel("Return")
            }
            .padding(.horizontal, 3)
        }
        .font(.system(size: 21))
        .foregroundStyle(.primary)
        .padding(.top, 4).padding(.bottom, 2)
        .onAppear { autoShiftLater() }
        .onChange(of: model.contextVersion) { autoShift() }
    }

    // MARK: Keel Voice bar

    private var voiceBar: some View {
        HStack(spacing: 10) {
            if model.listening { Image(systemName: "waveform").symbolEffect(.variableColor.iterative).foregroundStyle(.red) }
            else if model.working { ProgressView().controlSize(.small) }
            Text(status).font(.subheadline).foregroundStyle(model.listening && !model.partial.isEmpty ? .primary : .secondary)
                .lineLimit(2).truncationMode(.head).frame(maxWidth: .infinity, alignment: .leading)
                .onTapGesture { model.dismissNote() }
            if model.listening {
                Button { model.cancel() } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary) }
                    .accessibilityLabel("Cancel dictation")
            }
            ZStack {
                Capsule().fill(model.listening ? Color.red : Color.accentColor).frame(width: 64, height: 40)
                Image(systemName: model.listening ? "stop.fill" : "mic.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            }
            .contentShape(Capsule())
            .onLongPressGesture(minimumDuration: 0.3, maximumDistance: 60, perform: {}, onPressingChanged: pressing)
            .accessibilityElement()
            .accessibilityLabel(model.listening ? "Stop dictating" : "Dictate with Keel Voice")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.mic() }
        }
        .frame(height: 44)
        .padding(.horizontal, 10)
    }

    private var status: String {
        if let n = model.note { return n }
        if !model.hasFullAccess { return "Turn on Allow Full Access for Keel to dictate." }
        if model.listening { return model.partial.isEmpty ? "Listening…" : model.partial }
        if model.working { return "Tidying up…" }
        return model.alive ? "Tap the mic and talk · “Keel, …” edits" : "Tap the mic to talk with Keel Voice"
    }

    // MARK: Keys

    private var rows: [[String]] {
        switch page {
        case .letters: Self.letters.map { $0.map { shift == .off ? $0 : $0.uppercased() } }
        case .numbers: Self.numbers
        case .symbols: Self.symbols
        }
    }

    private var key: Color { Color(uiColor: .systemBackground).opacity(0.95) }
    private var special: Color { Color(uiColor: .systemGray3).opacity(0.7) }

    private func charKey(_ k: String) -> some View {
        Button {
            model.type(k)
            if shift == .once { shift = .off }
            if ".?!".contains(k) { autoShiftLater() }
        } label: {
            Text(k).frame(maxWidth: .infinity, minHeight: 42)
        }
        .buttonStyle(.plain)
        .background(key, in: .rect(cornerRadius: 6))
        .shadow(color: .black.opacity(0.18), radius: 0, y: 1)
    }

    @ViewBuilder private var leftOfThirdRow: some View {
        switch page {
        case .letters:
            Button {
                // Tap: once. Tap again quickly: caps lock. Tap when on: off.
                if shift == .off { shift = Date().timeIntervalSince(lastShiftTap) < 0.35 ? .locked : .once }
                else if shift == .once && Date().timeIntervalSince(lastShiftTap) < 0.35 { shift = .locked }
                else { shift = .off }
                lastShiftTap = Date()
            } label: {
                Image(systemName: shift == .locked ? "capslock.fill" : (shift == .once ? "shift.fill" : "shift")).frame(width: 44, height: 42)
            }
            .buttonStyle(.plain).background(shift == .off ? special : key, in: .rect(cornerRadius: 6)).accessibilityLabel("Shift")
        case .numbers:
            Button { page = .symbols } label: { Text("#+=").font(.system(size: 15)).frame(width: 44, height: 42) }
                .buttonStyle(.plain).background(special, in: .rect(cornerRadius: 6))
        case .symbols:
            Button { page = .numbers } label: { Text("123").font(.system(size: 15)).frame(width: 44, height: 42) }
                .buttonStyle(.plain).background(special, in: .rect(cornerRadius: 6))
        }
    }

    private var deleteKey: some View {
        Image(systemName: "delete.left").frame(width: 44, height: 42).background(special, in: .rect(cornerRadius: 6))
            .onLongPressGesture(minimumDuration: 0.4, maximumDistance: 40, perform: {}, onPressingChanged: deleting)
            .accessibilityElement().accessibilityLabel("Delete").accessibilityAddTraits(.isButton).accessibilityAction { model.delete() }
    }

    /// Capital at the start of a sentence, like the system keyboard.
    private func autoShift() {
        guard page == .letters, shift != .locked else { return }
        shift = model.atSentenceStart ? .once : .off
    }
    private func autoShiftLater() { Task { @MainActor in try? await Task.sleep(for: .milliseconds(120)); autoShift() } }

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

    /// Delete: once on tap; keeps deleting while held.
    private func deleting(_ down: Bool) {
        if down {
            model.delete()
            deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in MainActor.assumeIsolated { model.delete() } }
            deleteTimer?.fireDate = Date().addingTimeInterval(0.45)
        } else {
            deleteTimer?.invalidate(); deleteTimer = nil
            autoShift()
        }
    }
}
