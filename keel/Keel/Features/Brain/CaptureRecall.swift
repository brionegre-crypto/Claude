import SwiftUI
import SwiftData
import Speech
import AVFoundation
import PDFKit
import EventKit
import AppIntents
import UniformTypeIdentifiers

// MARK: - Reader + highlights (read-later)

struct ReaderHighlight: Codable, Identifiable, Hashable { var id = UUID(); var text: String; var at = Date() }

@MainActor
enum ReaderStore {
    private static var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Reader", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func paragraphs(_ id: UUID) -> [String]? {
        (try? String(contentsOf: dir.appendingPathComponent("\(id).txt"), encoding: .utf8))?.components(separatedBy: "\n\n")
    }
    static func save(_ id: UUID, _ paras: [String]) { try? paras.joined(separator: "\n\n").write(to: dir.appendingPathComponent("\(id).txt"), atomically: true, encoding: .utf8) }
    static func highlights(_ id: UUID) -> [ReaderHighlight] {
        (try? Data(contentsOf: dir.appendingPathComponent("\(id).hl.json"))).flatMap { try? JSONDecoder().decode([ReaderHighlight].self, from: $0) } ?? []
    }
    static func setHighlights(_ id: UUID, _ h: [ReaderHighlight]) { try? JSONEncoder().encode(h).write(to: dir.appendingPathComponent("\(id).hl.json")) }

    /// Fetches the article and keeps just its readable paragraphs.
    static func fetch(_ urlString: String) async -> (title: String, paras: [String])? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url); req.timeoutInterval = 20
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile Safari/604.1", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req), let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        return extract(html)
    }

    nonisolated static func extract(_ html: String) -> (title: String, paras: [String]) {
        var h = html
        for tag in ["script", "style", "nav", "header", "footer", "aside", "form", "noscript", "svg"] {
            h = h.replacingOccurrences(of: "<\(tag)[\\s\\S]*?</\(tag)>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        let title = h.range(of: "<title[^>]*>([\\s\\S]*?)</title>", options: [.regularExpression, .caseInsensitive])
            .map { String(h[$0]).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression) } ?? ""
        let body = h.range(of: "<article[\\s\\S]*?</article>", options: [.regularExpression, .caseInsensitive]).map { String(h[$0]) } ?? h
        var paras: [String] = []
        let ns = body as NSString
        if let re = try? NSRegularExpression(pattern: "<(p|h2|h3|li|blockquote)[^>]*>([\\s\\S]*?)</\\1>", options: .caseInsensitive) {
            for m in re.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
                let inner = ns.substring(with: m.range(at: 2))
                let text = decode(inner.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
                if text.count > 40 || (ns.substring(with: m.range(at: 1)).lowercased().hasPrefix("h") && text.count > 3) { paras.append(text) }
            }
        }
        return (decode(title).trimmingCharacters(in: .whitespacesAndNewlines), paras)
    }

    nonisolated static func decode(_ s: String) -> String {
        var t = s
        for (k, v) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&#x27;": "'", "&nbsp;": " ", "&rsquo;": "’", "&lsquo;": "‘", "&ldquo;": "“", "&rdquo;": "”", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…"] {
            t = t.replacingOccurrences(of: k, with: v)
        }
        return t
    }

    /// The article's highlights as a page in Notes → Resources → Highlights.
    static func sendToNote(_ link: SavedLink, ctx: ModelContext) -> Note {
        let hl = highlights(link.id)
        let title = "Highlights · \(link.title.isEmpty ? (URL(string: link.url)?.host() ?? "Article") : link.title)"
        let existing = try? ctx.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.title == title })).first
        let n = existing ?? Note(title: title, blocks: [])
        n.blocks = [NoteBlock(kind: .bookmark, text: link.title, refId: link.url)] + hl.map { NoteBlock(kind: .quote, text: $0.text) }
        n.icon = "🖍️"
        n.folder = n.folder ?? NotePath.make("Resources", "Highlights")
        n.updatedAt = Date()
        if existing == nil { ctx.insert(n) }
        return n
    }
}

struct ReaderView: View {
    @Bindable var link: SavedLink
    @Environment(\.modelContext) private var ctx
    @State private var paras: [String] = []
    @State private var highlights: [ReaderHighlight] = []
    @State private var loading = true
    @State private var saved: Note?
    @AppStorage("reader.size") private var size = 19.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(link.title).font(.system(size: size + 8, weight: .bold, design: .serif))
                Text(URL(string: link.url)?.host() ?? "").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if !loading && paras.isEmpty {
                    Text("This page can't be shown in reader view.").foregroundStyle(DS.Palette.inkSoft)
                    Link("Open in Safari", destination: URL(string: link.url) ?? URL(string: "https://apple.com")!)
                }
                ForEach(Array(paras.enumerated()), id: \.offset) { _, p in
                    let on = highlights.contains { $0.text == p }
                    Text(p).font(.system(size: size, design: .serif)).lineSpacing(5)
                        .padding(on ? 6 : 0)
                        .background(on ? Color.yellow.opacity(0.35) : .clear, in: .rect(cornerRadius: 4))
                        .textSelection(.enabled)
                        .contextMenu {
                            Button(on ? "Remove highlight" : "Highlight", systemImage: "highlighter") { toggle(p) }
                            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = p }
                        }
                        .onTapGesture(count: 2) { toggle(p) }
                }
            }
            .padding(.horizontal, 22).padding(.vertical)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Reader").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("Smaller text", systemImage: "textformat.size.smaller") { size = max(14, size - 1) }
                    Button("Larger text", systemImage: "textformat.size.larger") { size = min(30, size + 1) }
                } label: { Image(systemName: "textformat.size") }
                Button { saved = ReaderStore.sendToNote(link, ctx: ctx); Haptics.success() } label: { Image(systemName: "note.text.badge.plus") }
                    .disabled(highlights.isEmpty).accessibilityLabel("Save highlights to Notes")
            }
        }
        .navigationDestination(item: $saved) { NoteEditor(note: $0) }
        .safeAreaInset(edge: .bottom) {
            if !highlights.isEmpty {
                Text("\(highlights.count) highlight\(highlights.count == 1 ? "" : "s") · double-tap a paragraph to highlight").font(.caption)
                    .padding(8).frame(maxWidth: .infinity).background(.bar)
            }
        }
        .task {
            highlights = ReaderStore.highlights(link.id)
            if let cached = ReaderStore.paragraphs(link.id), !cached.isEmpty { paras = cached; loading = false }
            else if let r = await ReaderStore.fetch(link.url) {
                paras = r.paras; ReaderStore.save(link.id, r.paras)
                if link.title.isEmpty && !r.title.isEmpty { link.title = r.title }
            }
            loading = false
            if !link.isRead { link.isRead = true; link.readAt = Date() }
        }
    }

    private func toggle(_ p: String) {
        if let i = highlights.firstIndex(where: { $0.text == p }) { highlights.remove(at: i) } else { highlights.append(ReaderHighlight(text: p)) }
        ReaderStore.setHighlights(link.id, highlights)
        Haptics.tap()
    }
}

/// Kindle "My Clippings.txt" → one page of highlights per book.
@MainActor
enum KindleImport {
    static func run(_ url: URL, ctx: ModelContext) -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        var books: [String: [String]] = [:]
        for entry in text.components(separatedBy: "==========") {
            let lines = entry.split(separator: "\n", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard lines.count >= 3, lines[1].lowercased().contains("highlight") else { continue }
            let book = lines[0].replacingOccurrences(of: "\u{FEFF}", with: "")
            books[book, default: []].append(lines[2...].joined(separator: " "))
        }
        for (book, quotes) in books {
            let n = Note(title: book, blocks: [NoteBlock(kind: .text, text: "#book")] + Array(Set(quotes)).sorted().map { NoteBlock(kind: .quote, text: $0) })
            n.icon = "📚"
            n.folder = NotePath.make("Resources", "Books")
            ctx.insert(n)
        }
        try? ctx.save()
        return books.count
    }
}

// MARK: - Capture inbox

/// Everything quick lands here (voice, photos, links, shared text) until you file it.
@MainActor
enum CaptureInbox {
    static let flag = "capture"
    static func add(title: String, blocks: [NoteBlock], ctx: ModelContext) -> Note {
        let n = Note(title: title, blocks: blocks.isEmpty ? [NoteBlock(kind: .text, text: "")] : blocks)
        n.props[flag] = "1"
        n.icon = "📥"
        ctx.insert(n)
        try? ctx.save()
        return n
    }
    static func isPending(_ n: Note) -> Bool { n.props[flag] == "1" }
    static func done(_ n: Note) { n.props[flag] = nil; if n.icon == "📥" { n.icon = nil }; n.updatedAt = Date() }
}

struct CaptureInboxView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @State private var text = ""
    @State private var link = ""
    @State private var filing = false
    @State private var showVoice = false
    @State private var open: Note?
    @State private var message: String?

    private var pending: [Note] { notes.filter(CaptureInbox.isPending) }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Jot anything…", text: $text, axis: .vertical)
                    Button("Add") { _ = CaptureInbox.add(title: String(text.prefix(60)), blocks: [NoteBlock(kind: .text, text: text)], ctx: ctx); text = ""; Haptics.tap() }
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack {
                    TextField("Paste a link (articles, YouTube…)", text: $link).keyboardType(.URL).textInputAutocapitalization(.never)
                    Button("Add") { Task { await addLink() } }.disabled(!link.contains("."))
                }
                Button { showVoice = true } label: { Label("Voice note", systemImage: "mic.fill") }
            } header: { Text("Capture") }
            Section {
                if pending.isEmpty { Text("Inbox zero. Everything is filed.").foregroundStyle(DS.Palette.inkSoft) }
                ForEach(pending) { n in
                    Button { open = n } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(n.title.isEmpty ? "Untitled" : n.title).foregroundStyle(DS.Palette.ink).lineLimit(1)
                            Text(n.plainText.prefix(100)).font(.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                        }
                    }
                    .swipeActions {
                        Button("Filed") { CaptureInbox.done(n) }.tint(DS.Palette.calm)
                        Button("Task") { let t = QuickAdd.create(n.title, in: ctx); t.sourceNoteId = n.id; CaptureInbox.done(n) }.tint(DS.Palette.warmth)
                        Button("Delete", role: .destructive) { NoteTrash.delete(n, ctx: ctx) }
                    }
                }
            } header: { Text("To sort (\(pending.count))") } footer: {
                if !pending.isEmpty { Text("Swipe to file, make a task or delete. Or let Keel file them all into the right folders.") }
            }
            if !pending.isEmpty {
                Section {
                    Button(filing ? "Filing…" : "File everything with AI", systemImage: "sparkles") { Task { await fileAll() } }.disabled(filing)
                    if let message { Text(message).font(.caption).foregroundStyle(DS.Palette.inkSoft) }
                }
            }
        }
        .navigationTitle("Capture inbox")
        .sheet(isPresented: $showVoice) { VoiceNoteView() }
        .navigationDestination(item: $open) { NoteEditor(note: $0) }
    }

    private func addLink() async {
        let raw = link.trimmingCharacters(in: .whitespaces)
        let urlString = raw.hasPrefix("http") ? raw : "https://" + raw
        link = ""
        if let yt = await MediaCapture.youtube(urlString) { _ = CaptureInbox.add(title: yt.title, blocks: yt.blocks, ctx: ctx); return }
        let l = SavedLink(url: urlString, title: "")
        ctx.insert(l)
        if let r = await ReaderStore.fetch(urlString) {
            l.title = r.title
            ReaderStore.save(l.id, r.paras)
            let summary = await AIRouter.shared.summarize(r.paras.prefix(30).joined(separator: "\n"))
            var blocks = [NoteBlock(kind: .bookmark, text: r.title, refId: urlString)]
            if let summary { blocks.append(NoteBlock(kind: .text, text: summary)) }
            _ = CaptureInbox.add(title: r.title.isEmpty ? urlString : r.title, blocks: blocks, ctx: ctx)
        } else {
            _ = CaptureInbox.add(title: urlString, blocks: [NoteBlock(kind: .bookmark, text: "", refId: urlString)], ctx: ctx)
        }
    }

    private func fileAll() async {
        filing = true; defer { filing = false }
        let all = Array(notes)
        let picks = await NotesOrganizer.propose(for: pending, all: all, allowNew: true) { _, _ in }
        var moved = 0
        for p in picks { if let n = all.first(where: { $0.id == p.id }) { n.folder = p.folder; CaptureInbox.done(n); moved += 1 } }
        message = "Filed \(moved) item\(moved == 1 ? "" : "s")."
        Haptics.success()
    }
}

// MARK: - Voice notes (audio kept)

@MainActor @Observable
final class VoiceNoteRecorder {
    var transcript = ""
    var recording = false
    var error: String?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var file: AVAudioFile?
    private(set) var fileURL: URL?

    func start() async {
        let ok = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        guard ok, await AVAudioApplication.requestRecordPermission() else { error = "Allow microphone and speech recognition in Settings."; return }
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
            try s.setActive(true)
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VoiceNotes", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("\(UUID().uuidString).caf")
            let fmt = engine.inputNode.outputFormat(forBus: 0)
            file = try AVAudioFile(forWriting: url, settings: fmt.settings)
            fileURL = url
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if SFSpeechRecognizer()?.supportsOnDeviceRecognition == true { req.requiresOnDeviceRecognition = true }
            request = req
            let f = file
            engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: fmt) { buf, _ in
                req.append(buf); try? f?.write(from: buf)
            }
            engine.prepare(); try engine.start()
            task = SFSpeechRecognizer()?.recognitionTask(with: req) { [weak self] r, _ in
                guard let r else { return }
                let t = r.bestTranscription.formattedString
                Task { @MainActor in self?.transcript = t }
            }
            recording = true
        } catch { self.error = error.localizedDescription }
    }

    func stop() {
        guard recording else { return }
        engine.stop(); engine.inputNode.removeTap(onBus: 0)
        request?.endAudio(); task?.finish()
        file = nil
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct VoiceNoteView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var rec = VoiceNoteRecorder()
    @State private var saving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.l) {
                ScrollView {
                    Text(rec.transcript.isEmpty ? (rec.recording ? "Listening…" : "Tap to start talking.") : rec.transcript)
                        .font(DS.Font.body).foregroundStyle(rec.transcript.isEmpty ? DS.Palette.inkSoft : DS.Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading).padding()
                }
                .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.card))
                if let e = rec.error { Text(e).font(.caption).foregroundStyle(.red) }
                Button {
                    if rec.recording { rec.stop() } else { Task { await rec.start() } }
                } label: {
                    Image(systemName: rec.recording ? "stop.fill" : "mic.fill").font(.system(size: 30)).foregroundStyle(.white)
                        .frame(width: 80, height: 80).background(rec.recording ? Color.red : DS.Palette.accent, in: Circle())
                }
                .accessibilityLabel(rec.recording ? "Stop" : "Record")
                Button { Task { await save() } } label: {
                    Label(saving ? "Tidying up…" : "Save", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).disabled(rec.recording || rec.transcript.isEmpty || saving)
            }
            .padding()
            .navigationTitle("Voice note").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { rec.stop(); dismiss() } } }
            .task { await rec.start() }
        }
    }

    /// Cleans up the words (keeps your meaning), files it in the capture inbox, and keeps the recording on the page.
    private func save() async {
        saving = true; defer { saving = false }
        let raw = rec.transcript
        let clean = await AIRouter.shared.write("Tidy this voice note: fix punctuation, remove filler words and repeats, keep my words and meaning. If it's clearly a to-do, start the first line with TASK:. Reply with only the text.\n\n\(raw)") ?? raw
        if clean.hasPrefix("TASK:") {
            _ = QuickAdd.create(String(clean.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines), in: ctx)
            UndoCenter.shared.notify("Added to Tasks")
        } else {
            var blocks = clean.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { NoteBlock(kind: .text, text: $0) }
            if let url = rec.fileURL, let data = try? Data(contentsOf: url) {
                let n = CaptureInbox.add(title: String(clean.prefix(50)), blocks: [], ctx: ctx)
                let a = NoteAttachment(noteId: n.id, data: data, kind: "audio")
                ctx.insert(a)
                var audio = NoteBlock(kind: .code, text: "Voice note"); audio.lang = "keel-audio"; audio.refId = a.id.uuidString
                blocks.insert(audio, at: 0)
                n.blocks = blocks
                try? FileManager.default.removeItem(at: url)
            } else {
                _ = CaptureInbox.add(title: String(clean.prefix(50)), blocks: blocks, ctx: ctx)
            }
        }
        Haptics.success()
        dismiss()
    }
}

/// Plays a recording kept on a page.
struct AudioBlockView: View {
    let attachmentId: String?
    @Query private var attachments: [NoteAttachment]
    @State private var player: AVAudioPlayer?
    @State private var playing = false
    var body: some View {
        HStack {
            Button {
                if playing { player?.pause(); playing = false; return }
                if player == nil, let id = attachmentId.flatMap(UUID.init(uuidString:)), let a = attachments.first(where: { $0.id == id }) {
                    try? AVAudioSession.sharedInstance().setCategory(.playback)
                    player = try? AVAudioPlayer(data: a.data)
                }
                player?.play(); playing = player != nil
            } label: { Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill").font(.title) }
            .buttonStyle(.plain).foregroundStyle(DS.Palette.accent)
            Text("Recording").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            Spacer()
        }
        .padding(8).background(DS.Palette.elevated, in: .rect(cornerRadius: 8))
    }
}

// MARK: - YouTube and podcasts

@MainActor
enum MediaCapture {
    /// A YouTube video → its transcript and the key points as a page.
    static func youtube(_ urlString: String) async -> (title: String, blocks: [NoteBlock])? {
        guard let u = URL(string: urlString), let host = u.host(), host.contains("youtu") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: u), let html = String(data: data, encoding: .utf8) else { return nil }
        let title = ReaderStore.decode(html.range(of: "<title>([\\s\\S]*?)</title>", options: .regularExpression)
            .map { String(html[$0]).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).replacingOccurrences(of: " - YouTube", with: "") } ?? "YouTube video")
        var transcript = ""
        if let r = html.range(of: "\"baseUrl\":\"(https://www.youtube.com/api/timedtext[^\"]+)\"", options: .regularExpression) {
            let raw = String(html[r]).replacingOccurrences(of: "\"baseUrl\":\"", with: "").dropLast()
            let capURL = raw.replacingOccurrences(of: "\\u0026", with: "&")
            if let cu = URL(string: String(capURL)), let (cd, _) = try? await URLSession.shared.data(from: cu), let xml = String(data: cd, encoding: .utf8) {
                transcript = ReaderStore.decode(xml.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            }
        }
        var blocks = [NoteBlock(kind: .bookmark, text: title, refId: urlString)]
        if !transcript.isEmpty {
            if let pts = await AIRouter.shared.write("List the 5 to 8 key points of this video as short bullet lines starting with '- '. Reply with only the list.\n\n\(transcript.prefix(9_000))") {
                blocks.append(NoteBlock(kind: .heading2, text: "Key points"))
                blocks += pts.components(separatedBy: "\n").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-•* ").union(.whitespaces)) }
                    .filter { !$0.isEmpty }.map { NoteBlock(kind: .bullet, text: $0) }
            }
            var t = NoteBlock(kind: .toggle, text: "Transcript"); t.body = transcript; t.collapsed = true
            blocks.append(t)
        } else {
            blocks.append(NoteBlock(kind: .text, text: "This video has no captions Keel can read."))
        }
        return (title, blocks)
    }
}

// MARK: - PDF reader with highlights and margin notes

struct PDFReaderView: View {
    @Bindable var attachment: NoteAttachment
    let note: Note
    @Environment(\.modelContext) private var ctx
    @State private var pdf: PDFView?
    @State private var noteText = ""
    @State private var addingNote = false

    var body: some View {
        PDFKitView(data: attachment.data) { pdf = $0 }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("PDF").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { highlight() } label: { Image(systemName: "highlighter") }.accessibilityLabel("Highlight selection")
                    Button { addingNote = true } label: { Image(systemName: "text.bubble") }.accessibilityLabel("Note on selection")
                }
            }
            .alert("Note on this passage", isPresented: $addingNote) {
                TextField("Your thought", text: $noteText)
                Button("Save") { highlight(comment: noteText); noteText = "" }
                Button("Cancel", role: .cancel) {}
            }
    }

    /// Highlights the selected text in the PDF and copies it (with your note) onto the page, linked by page number.
    private func highlight(comment: String = "") {
        guard let v = pdf, let sel = v.currentSelection, let text = sel.string, !text.isEmpty else { return }
        for line in sel.selectionsByLine() {
            guard let page = line.pages.first else { continue }
            let a = PDFAnnotation(bounds: line.bounds(for: page), forType: .highlight, withProperties: nil)
            a.color = UIColor.systemYellow.withAlphaComponent(0.5)
            if !comment.isEmpty { a.contents = comment }
            page.addAnnotation(a)
        }
        let pageNo = (sel.pages.first.flatMap { v.document?.index(for: $0) } ?? 0) + 1
        note.blocks.append(NoteBlock(kind: .quote, text: "\(text.trimmingCharacters(in: .whitespacesAndNewlines)) (p. \(pageNo))"))
        if !comment.isEmpty { note.blocks.append(NoteBlock(kind: .bullet, text: comment)) }
        if let d = v.document?.dataRepresentation() { attachment.data = d }
        note.updatedAt = Date()
        v.clearSelection()
        Haptics.success()
    }
}

struct PDFKitView: UIViewRepresentable {
    let data: Data
    var ready: (PDFView) -> Void
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.document = PDFDocument(data: data)
        DispatchQueue.main.async { ready(v) }
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {}
}

struct PDFBlockView: View {
    let attachmentId: String?
    let note: Note
    @Query private var attachments: [NoteAttachment]
    var body: some View {
        if let id = attachmentId.flatMap(UUID.init(uuidString:)), let a = attachments.first(where: { $0.id == id }) {
            NavigationLink { PDFReaderView(attachment: a, note: note) } label: {
                Label("\(a.recognizedText.isEmpty ? "PDF" : a.recognizedText) · open to read and highlight", systemImage: "doc.richtext")
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Palette.elevated, in: .rect(cornerRadius: 8))
            }
        } else {
            Label("PDF not found", systemImage: "doc.questionmark").foregroundStyle(DS.Palette.inkSoft)
        }
    }
}

@MainActor
enum PDFImport {
    /// Adds a PDF to a page (synced with the page through iCloud).
    static func add(_ url: URL, to note: Note, ctx: ModelContext) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let a = NoteAttachment(noteId: note.id, data: data, kind: "pdf")
        a.recognizedText = url.deletingPathExtension().lastPathComponent
        // Searchable: the PDF's own text.
        if let doc = PDFDocument(data: data) { a.recognizedText += "\n" + String((doc.string ?? "").prefix(50_000)) }
        ctx.insert(a)
        var b = NoteBlock(kind: .code, text: url.lastPathComponent); b.lang = "keel-pdf"; b.refId = a.id.uuidString
        note.blocks.append(b)
        note.updatedAt = Date()
    }
}

// MARK: - Ask everything (notes, mail, tasks, calendar, meetings)

struct AskEverythingView: View {
    var initial: String? = nil
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query(InboxView.recentMail) private var mail: [EmailMessage]
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var tasks: [TaskItem]
    @State private var question = ""
    @State private var answer: String?
    @State private var srcNotes: [Note] = []
    @State private var srcMail: [EmailMessage] = []
    @State private var working = false
    @State private var saved: Note?

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Ask anything about your life, work or notes…", text: $question, axis: .vertical).onSubmit { Task { await ask() } }
                    Button { Task { await ask() } } label: { if working { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title2) } }
                        .disabled(question.count < 3 || working)
                }
            } footer: { Text("Keel looks through your pages, email, tasks, calendar and meeting notes, and answers with sources.") }
            if let answer {
                Section("Answer") {
                    Text(answer).textSelection(.enabled)
                    HStack {
                        Button("Save as a page", systemImage: "doc.badge.plus") {
                            let n = Note(title: question, blocks: [NoteBlock(kind: .text, text: answer)]); ctx.insert(n); saved = n
                        }
                        Spacer()
                        Button("Make a task", systemImage: "checklist") { _ = QuickAdd.create(question, in: ctx); UndoCenter.shared.notify("Added to Tasks") }
                    }
                    .buttonStyle(.borderless).font(DS.Font.caption)
                }
            }
            if !srcNotes.isEmpty {
                Section("Pages") {
                    ForEach(srcNotes) { n in NavigationLink { NoteOrCanvas(note: n) } label: { Label(n.title.isEmpty ? "Untitled" : n.title, systemImage: "doc.text") } }
                }
            }
            if !srcMail.isEmpty {
                Section("Emails") {
                    ForEach(srcMail) { e in NavigationLink { EmailDetailView(email: e) } label: { Label(e.subject, systemImage: "envelope").lineLimit(1) } }
                }
            }
        }
        .navigationTitle("Ask everything")
        .navigationDestination(item: $saved) { NoteEditor(note: $0) }
        .task { if let initial, question.isEmpty { question = initial; await ask() } }
    }

    private func ask() async {
        working = true; defer { working = false }
        let q = question
        BrainIndex.shared.refresh(ctx: ctx)
        let meaning = BrainIndex.shared.search(q, limit: 12, minScore: 0.4)
        let byMeaningNotes = meaning.filter { $0.kind == "note" }.compactMap { h in notes.first { $0.id.uuidString == h.id } }
        srcNotes = Array((byMeaningNotes + NotesAsk.search(q, in: Array(notes), limit: 5)).reduce(into: [Note]()) { if !$0.contains($1) { $0.append($1) } }.prefix(6))
        let byMeaningMail = meaning.filter { $0.kind == "mail" }.compactMap { h in mail.first { $0.id == h.id } }
        srcMail = Array((byMeaningMail + MailAsk.search(q, in: Array(mail), limit: 5)).reduce(into: [EmailMessage]()) { if !$0.contains($1) { $0.append($1) } }.prefix(6))
        let cal = CalendarService.shared.events(from: Date().addingTimeInterval(-14 * 86_400), to: Date().addingTimeInterval(30 * 86_400))
            .filter { e in q.lowercased().split(separator: " ").contains { w in w.count > 3 && (e.title ?? "").lowercased().contains(w) } }.prefix(6)
        let taskHits = tasks.filter { t in q.lowercased().split(separator: " ").contains { w in w.count > 3 && t.title.lowercased().contains(w) } }.prefix(6)
        var ctxText = srcNotes.enumerated().map { "[P\($0.offset + 1)] \($0.element.title): \($0.element.plainText.prefix(900))" }.joined(separator: "\n\n")
        ctxText += "\n\n" + srcMail.enumerated().map { "[E\($0.offset + 1)] \($0.element.fromName) – \($0.element.subject): \($0.element.bodyPlain.prefix(500))" }.joined(separator: "\n\n")
        if !cal.isEmpty { ctxText += "\n\nCALENDAR: " + cal.map { "\($0.title ?? "") on \($0.startDate.formatted(date: .abbreviated, time: .shortened))" }.joined(separator: "; ") }
        if !taskHits.isEmpty { ctxText += "\n\nOPEN TASKS: " + taskHits.map { $0.title + ($0.dueDate.map { " (due \($0.formatted(date: .abbreviated, time: .omitted)))" } ?? "") }.joined(separator: "; ") }
        let prompt = """
        Answer my question using only what's below from my own pages [P#], emails [E#], calendar and tasks. Be specific and brief, \
        cite sources like [P1] or [E2], and say so if the answer isn't there. Today is \(Date().formatted(date: .complete, time: .omitted)).

        QUESTION: \(q)

        \(ctxText.prefix(11_000))
        """
        answer = await AIRouter.shared.write(prompt) ?? "Keel's AI isn't available right now; the closest sources are below."
    }
}

// MARK: - Resurfacing

@MainActor
enum Resurface {
    /// A few older pages worth seeing again today (same picks all day), plus "on this day".
    static func today(_ notes: [Note]) -> (old: [Note], onThisDay: [Note]) {
        let cal = Calendar.current
        let pool = notes.filter { !$0.isTemplate && !$0.isLocked && !$0.isDatabase && $0.updatedAt < Date().addingTimeInterval(-21 * 86_400) && $0.plainText.count > 80 }
        let seed = cal.ordinality(of: .day, in: .era, for: Date()) ?? 0
        var picks: [Note] = []
        if !pool.isEmpty { for k in 0..<min(3, pool.count) { picks.append(pool[(seed * 7 + k * 13) % pool.count]) } }
        let md = cal.dateComponents([.month, .day], from: Date())
        let otd = notes.filter { n in
            let c = cal.dateComponents([.year, .month, .day], from: n.createdAt)
            return c.month == md.month && c.day == md.day && c.year != cal.component(.year, from: Date()) && !n.isLocked && !n.isTemplate
        }
        return (Array(Set(picks)), otd)
    }

    /// Reader highlights to see again.
    struct Pick: Identifiable { let link: SavedLink; let highlight: ReaderHighlight; var id: UUID { highlight.id } }
    static func highlights(_ links: [SavedLink]) -> [Pick] {
        let all = links.flatMap { l in ReaderStore.highlights(l.id).map { Pick(link: l, highlight: $0) } }
        guard !all.isEmpty else { return [] }
        let seed = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return [all[seed % all.count]]
    }
}

// MARK: - Flashcards (spaced repetition)

struct Flashcard: Identifiable { let id: UUID; let note: Note; let question: String; let answer: String }

@MainActor
enum Flashcards {
    /// "Question :: Answer" lines, and toggles (question = toggle, answer = what's inside).
    static func cards(_ notes: [Note]) -> [Flashcard] {
        notes.filter { !$0.isLocked && !$0.isTemplate }.flatMap { n in
            n.blocks.compactMap { b -> Flashcard? in
                if b.text.contains("::") {
                    let p = b.text.components(separatedBy: "::")
                    let q = RichText.plain(p[0]).trimmingCharacters(in: .whitespaces), a = RichText.plain(p.dropFirst().joined(separator: "::")).trimmingCharacters(in: .whitespaces)
                    return q.isEmpty || a.isEmpty ? nil : Flashcard(id: b.id, note: n, question: q, answer: a)
                }
                if b.kind == .toggle, let body = b.body, !body.isEmpty, b.text.hasSuffix("?") {
                    return Flashcard(id: b.id, note: n, question: RichText.plain(b.text), answer: body)
                }
                return nil
            }
        }
    }
    /// Stored on the page: "ease|intervalDays|dueTimestamp".
    static func state(_ c: Flashcard) -> (ease: Double, interval: Double, due: Date) {
        let p = (c.note.props["fc.\(c.id.uuidString)"] ?? "").split(separator: "|").compactMap { Double($0) }
        return p.count == 3 ? (p[0], p[1], Date(timeIntervalSince1970: p[2])) : (2.5, 0, .distantPast)
    }
    static func due(_ notes: [Note]) -> [Flashcard] { cards(notes).filter { state($0).due <= Date() } }

    /// SM-2: 0 again, 1 hard, 2 good, 3 easy.
    static func grade(_ c: Flashcard, _ g: Int) {
        var (ease, interval, _) = state(c)
        switch g {
        case 0: interval = 0; ease = max(1.3, ease - 0.2)
        case 1: interval = max(1, interval * 1.2); ease = max(1.3, ease - 0.15)
        case 2: interval = interval == 0 ? 1 : (interval < 2 ? 3 : interval * ease)
        default: interval = interval == 0 ? 3 : interval * ease * 1.3; ease += 0.15
        }
        let due = g == 0 ? Date().addingTimeInterval(10 * 60) : Date().addingTimeInterval(interval * 86_400)
        c.note.props["fc.\(c.id.uuidString)"] = "\(ease)|\(interval)|\(due.timeIntervalSince1970)"
    }

    /// AI writes question :: answer cards from a page.
    static func generate(for n: Note) async -> Int {
        guard let r = await AIRouter.shared.write("Write 5 to 10 flashcards from these notes, one per line, as: question :: answer. Short, factual, only from the notes. Reply with only the lines.\n\n\(n.plainText.prefix(6_000))") else { return 0 }
        let lines = r.components(separatedBy: "\n").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-•* ").union(.whitespaces)) }.filter { $0.contains("::") }
        guard !lines.isEmpty else { return 0 }
        n.blocks.append(NoteBlock(kind: .heading2, text: "Flashcards"))
        n.blocks += lines.map { NoteBlock(kind: .text, text: $0) }
        n.updatedAt = Date()
        return lines.count
    }
}

struct FlashcardReviewView: View {
    @Query private var notes: [Note]
    @State private var queue: [Flashcard] = []
    @State private var showAnswer = false
    @State private var done = 0

    var body: some View {
        VStack(spacing: DS.Space.l) {
            if let c = queue.first {
                Text("\(queue.count) to review").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                VStack(spacing: DS.Space.m) {
                    Text(c.question).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                    if showAnswer {
                        Divider()
                        Text(c.answer).font(.title3).multilineTextAlignment(.center).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
                .padding(DS.Space.l).frame(maxWidth: .infinity, minHeight: 240)
                .background(DS.Palette.elevated, in: .rect(cornerRadius: 20))
                Text("from \(c.note.title)").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                if showAnswer {
                    HStack {
                        ForEach(Array(["Again", "Hard", "Good", "Easy"].enumerated()), id: \.offset) { i, label in
                            Button(label) { Flashcards.grade(c, i); next() }
                                .buttonStyle(.bordered).tint([Color.red, .orange, DS.Palette.calm, .blue][i]).frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    Button("Show answer") { withAnimation(DS.spring) { showAnswer = true } }.buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView("All caught up", systemImage: "rectangle.on.rectangle.angled",
                                       description: Text(done > 0 ? "You reviewed \(done) card\(done == 1 ? "" : "s"). Come back tomorrow." : "Write “question :: answer” on any line, or a toggle ending in “?”, and it becomes a card. Or open a page → ✨ → Make flashcards."))
            }
        }
        .padding()
        .navigationTitle("Flashcards")
        .onAppear { queue = Flashcards.due(Array(notes)).shuffled() }
    }

    private func next() {
        showAnswer = false
        done += 1
        if !queue.isEmpty { queue.removeFirst() }
        Haptics.tap()
    }
}

// MARK: - People pages

struct PersonPageView: View {
    let person: Person
    @Query(InboxView.recentMail) private var mail: [EmailMessage]
    @Query private var notes: [Note]
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var tasks: [TaskItem]
    @Query private var promises: [Commitment]

    private var email: String { person.email.lowercased() }
    private var first: String { String(person.name.split(separator: " ").first ?? "").lowercased() }

    var body: some View {
        let theirMail = email.isEmpty ? [] : Array(mail.filter { $0.from.lowercased() == email || $0.toLine.lowercased().contains(email) }.prefix(8))
        let pages = notes.filter { n in !n.isLocked && !n.isTemplate && (n.plainText.localizedCaseInsensitiveContains(person.name) || n.title.localizedCaseInsensitiveContains(person.name)) }.prefix(8)
        let theirTasks = tasks.filter { first.count > 2 && $0.title.lowercased().contains(first) }.prefix(6)
        let owed = promises.filter { (!email.isEmpty && $0.recipient.lowercased() == email) && $0.status == .open }.prefix(5)
        let meetings = CalendarService.shared.events(from: Date().addingTimeInterval(-30 * 86_400), to: Date().addingTimeInterval(30 * 86_400))
            .filter { e in (e.attendees ?? []).contains { ($0.url.absoluteString.lowercased().contains(email) && !email.isEmpty) || ($0.name ?? "").localizedCaseInsensitiveContains(person.name) } }
        List {
            Section {
                if !person.email.isEmpty { LabeledContent("Email", value: person.email) }
                if !person.phone.isEmpty { LabeledContent("Phone", value: person.phone) }
                LabeledContent("Last in touch", value: person.lastContact.map { $0.formatted(.relative(presentation: .named)) } ?? "Not logged")
                if !person.notes.isEmpty { Text(person.notes).font(DS.Font.caption) }
            }
            if !owed.isEmpty { Section("You promised") { ForEach(Array(owed)) { Text($0.promise) } } }
            if !meetings.isEmpty {
                Section("Meetings") {
                    ForEach(meetings.prefix(8), id: \.calendarItemIdentifier) { e in
                        LabeledContent(e.title ?? "Meeting", value: e.startDate.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
            if !theirMail.isEmpty {
                Section("Email") { ForEach(theirMail) { e in NavigationLink { EmailDetailView(email: e) } label: { Text(e.subject).lineLimit(1) } } }
            }
            if !pages.isEmpty {
                Section("Pages that mention them") { ForEach(Array(pages)) { n in NavigationLink { NoteOrCanvas(note: n) } label: { Label(n.title.isEmpty ? "Untitled" : n.title, systemImage: "doc.text") } } }
            }
            if !theirTasks.isEmpty { Section("Tasks") { ForEach(Array(theirTasks)) { Label($0.title, systemImage: "checklist") } } }
        }
        .navigationTitle(person.name)
    }
}

// MARK: - Second-brain home (the brain map stays exactly as it is, as the centerpiece)

struct BrainHomeView: View {
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query private var links: [SavedLink]
    @Environment(\.modelContext) private var ctx
    @State private var fullMap = false

    var body: some View {
        let surf = Resurface.today(Array(notes))
        let inbox = notes.filter(CaptureInbox.isPending).count
        let due = Flashcards.due(Array(notes)).count
        let projects = notes.filter { ($0.folder ?? "").hasPrefix("Projects") && !$0.isTemplate }.prefix(6)
        let todays = CalendarService.shared.todaysEvents().filter { !$0.isAllDay }
        List {
            Section {
                BrainMapView()
                    .frame(height: 380)
                    .clipShape(.rect(cornerRadius: 20))
                    .listRowInsets(EdgeInsets())
                Button("Open the brain map full screen", systemImage: "arrow.up.left.and.arrow.down.right") { fullMap = true }.font(DS.Font.caption)
            }
            Section {
                NavigationLink { CaptureInboxView() } label: { LabeledContent { Text("\(inbox)") } label: { Label("Capture inbox", systemImage: "tray.and.arrow.down.fill") } }
                NavigationLink { FlashcardReviewView() } label: { LabeledContent { Text("\(due)") } label: { Label("Flashcards due", systemImage: "rectangle.on.rectangle.angled") } }
                NavigationLink { AskEverythingView() } label: { Label("Ask everything", systemImage: "sparkle.magnifyingglass") }
            }
            if !surf.old.isEmpty || !surf.onThisDay.isEmpty {
                Section("Worth another look") {
                    ForEach(surf.onThisDay) { n in NavigationLink { NoteOrCanvas(note: n) } label: { Label("On this day: \(n.title)", systemImage: "calendar.badge.clock") } }
                    ForEach(surf.old) { n in NavigationLink { NoteOrCanvas(note: n) } label: { Label(n.title.isEmpty ? "Untitled" : n.title, systemImage: "arrow.counterclockwise") } }
                    ForEach(Resurface.highlights(links)) { p in
                        NavigationLink { ReaderView(link: p.link) } label: { Text("“\(p.highlight.text.prefix(160))”").font(DS.Font.caption).italic() }
                    }
                }
            }
            if !todays.isEmpty {
                Section("For today's meetings") {
                    ForEach(todays.prefix(4), id: \.calendarItemIdentifier) { e in
                        let rel = BrainIndex.shared.search(e.title ?? "", kinds: ["note"], limit: 2, minScore: 0.5)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(e.title ?? "Meeting").font(DS.Font.headline)
                            ForEach(rel) { h in
                                if let n = notes.first(where: { $0.id.uuidString == h.id }) {
                                    NavigationLink { NoteOrCanvas(note: n) } label: { Label(n.title, systemImage: "doc.text").font(DS.Font.caption) }
                                }
                            }
                        }
                    }
                }
            }
            if !projects.isEmpty {
                Section("Projects") { ForEach(Array(projects)) { n in NavigationLink { NoteOrCanvas(note: n) } label: { Label(n.title.isEmpty ? "Untitled" : n.title, systemImage: "folder") } } }
            }
            Section("Recent") {
                ForEach(notes.filter { !$0.isTemplate }.prefix(6)) { n in NavigationLink { NoteOrCanvas(note: n) } label: { Label(n.title.isEmpty ? "Untitled" : n.title, systemImage: "clock") } }
            }
        }
        .navigationTitle("Second brain")
        .fullScreenCover(isPresented: $fullMap) {
            NavigationStack { BrainMapView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { fullMap = false } } } }
        }
        .task { BrainIndex.shared.refresh(ctx: ctx) }
    }
}

struct KindleImportView: View {
    @Environment(\.modelContext) private var ctx
    @State private var picking = false
    @State private var message: String?
    var body: some View {
        Form {
            Section {
                Button("Choose My Clippings.txt", systemImage: "doc.badge.plus") { picking = true }
                if let message { Text(message).foregroundStyle(DS.Palette.inkSoft) }
            } footer: { Text("Plug in your Kindle, copy “documents/My Clippings.txt” to Files, then choose it here. Each book becomes a page of highlights tagged #book in Resources → Books.") }
        }
        .navigationTitle("Kindle highlights")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.plainText, .text]) { r in
            if case .success(let url) = r { let n = KindleImport.run(url, ctx: ctx); message = n == 0 ? "No highlights found in that file." : "Added \(n) book\(n == 1 ? "" : "s")." }
        }
    }
}

// MARK: - Siri & Shortcuts for the second brain

struct VoiceNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Record a Voice Note"
    static let description: IntentDescription = "Talk, and Keel turns it into a tidy note (or a task), keeping the recording."
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult { AppRouter.shared.showVoice = true; return .result() }
}

struct AddToCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Capture Inbox"
    @Parameter(title: "Text", requestValueDialog: "What should I capture?") var text: String
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = CaptureInbox.add(title: String(text.prefix(60)), blocks: [NoteBlock(kind: .text, text: text)], ctx: KeelStore.container.mainContext)
        return .result(dialog: "Captured.")
    }
}

struct SaveToReadingListIntent: AppIntent {
    static let title: LocalizedStringResource = "Save to Keel Reading List"
    @Parameter(title: "Link") var url: URL
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = KeelStore.container.mainContext
        let l = SavedLink(url: url.absoluteString, title: "")
        ctx.insert(l)
        if let r = await ReaderStore.fetch(url.absoluteString) { l.title = r.title; ReaderStore.save(l.id, r.paras) }
        try? ctx.save()
        return .result(dialog: "Saved to your reading list.")
    }
}

struct AskBrainIntent: AppIntent {
    static let title: LocalizedStringResource = "Search My Second Brain"
    static let description: IntentDescription = "Ask what you wrote about something; Keel answers from your pages."
    @Parameter(title: "Question", requestValueDialog: "What do you want to find?") var question: String
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let notes = (try? KeelStore.container.mainContext.fetch(FetchDescriptor<Note>())) ?? []
        let src = NotesAsk.search(question, in: notes, limit: 5)
        let a = await NotesAsk.answer(question, sources: src)
        return .result(dialog: "\(a.replacingOccurrences(of: #"\[\d+\]"#, with: "", options: .regularExpression))")
    }
}

/// Highlights saved with the Safari extension join their article in the reading list.
@MainActor
enum SafariHighlights {
    private struct Item: Codable { var url: String; var title: String; var text: String; var date: Date }
    static func importQueued(ctx: ModelContext) {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.groupId) else { return }
        let file = dir.appendingPathComponent("safari-highlights.json")
        guard let data = try? Data(contentsOf: file), let items = try? JSONDecoder().decode([Item].self, from: data), !items.isEmpty else { return }
        try? FileManager.default.removeItem(at: file)
        let links = (try? ctx.fetch(FetchDescriptor<SavedLink>())) ?? []
        for it in items {
            let link = links.first { $0.url == it.url } ?? { let l = SavedLink(url: it.url, title: it.title); ctx.insert(l); return l }()
            var h = ReaderStore.highlights(link.id)
            if !h.contains(where: { $0.text == it.text }) { h.append(ReaderHighlight(text: it.text, at: it.date)); ReaderStore.setHighlights(link.id, h) }
        }
        try? ctx.save()
    }
}
