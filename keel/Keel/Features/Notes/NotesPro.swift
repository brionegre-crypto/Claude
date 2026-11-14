import SwiftUI
import SwiftData
import WebKit
import UniformTypeIdentifiers

// Notes power features: page embeds (synced blocks), outline, equations, diagrams, linked database views,
// comments, find & replace, quick switcher, unlinked mentions, a Markdown folder copy, and database relations
// and formulas.
//
// New block types are stored as code blocks with a special language (like the canvas), so pages stay readable
// in any version of Keel and nothing in the synced data model changes.

enum SpecialBlock {
    static let embed = "keel-embed"          // refId = the page shown here (edits there show everywhere)
    static let toc = "keel-toc"              // table of contents of this page
    static let math = "keel-math"            // text = LaTeX
    static let mermaid = "keel-mermaid"      // text = Mermaid diagram source
    static let dbview = "keel-dbview"        // refId = a database shown inline
    static let blockref = "keel-blockref"    // refId = "noteId/blockId": one line from another page, live

    static func kind(_ b: NoteBlock) -> String? {
        guard b.kind == .code, let l = b.lang, l.hasPrefix("keel-"), l != "keel-canvas" else { return nil }
        return l
    }

    /// Extra entries for the "/" menu.
    static let commands: [SlashCommand] = [
        .init(id: "embed", title: "Embed a page", subtitle: "Show another page here; edits stay in sync", icon: "rectangle.on.rectangle", keywords: ["synced", "transclude", "embed", "![[", "include"], kind: .code),
        .init(id: "dbview", title: "Linked database", subtitle: "Show a database inside this page", icon: "tablecells.badge.ellipsis", keywords: ["database", "view", "linked", "table", "board"], kind: .code),
        .init(id: "toc", title: "Table of contents", subtitle: "Every heading on this page", icon: "list.bullet.indent", keywords: ["toc", "outline", "contents"], kind: .code),
        .init(id: "math", title: "Equation", subtitle: "Math written in LaTeX", icon: "function", keywords: ["math", "latex", "katex", "formula", "equation", "tex"], kind: .code),
        lineEmbed,
        .init(id: "mermaid", title: "Diagram", subtitle: "Flowcharts and sequence diagrams (Mermaid)", icon: "point.3.connected.trianglepath.dotted", keywords: ["mermaid", "flowchart", "diagram", "chart", "graph"], kind: .code),
    ]
    static let commandIds: Set<String> = Set((commands + moreCommands).map(\.id))
    static let lineEmbed = SlashCommand(id: "blockref", title: "Line embed", subtitle: "Show a line copied with “Copy line embed”", icon: "text.quote", keywords: ["block", "reference", "line", "embed", "(("], kind: .code)
    static func lang(for commandId: String) -> String? {
        ["embed": embed, "dbview": dbview, "toc": toc, "math": math, "mermaid": mermaid, "blockref": blockref][commandId] ?? moreLangs[commandId]
    }
}

// MARK: - Embedded page (synced block)

struct EmbeddedPageView: View {
    let pageId: String?
    let allNotes: [Note]
    var open: (Note) -> Void
    var choose: () -> Void

    var body: some View {
        let target = pageId.flatMap(UUID.init(uuidString:)).flatMap { id in allNotes.first { $0.id == id } }
        VStack(alignment: .leading, spacing: 6) {
            if let t = target {
                HStack {
                    Text(t.icon ?? "📄")
                    Text(t.title.isEmpty ? "Untitled" : t.title).font(DS.Font.headline)
                    Spacer()
                    Button("Open") { open(t) }.font(DS.Font.caption)
                }
                if t.isLocked {
                    Label("Locked page", systemImage: "lock.fill").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                } else {
                    ForEach(t.blocks.prefix(40)) { b in EmbeddedBlockLine(block: b) }
                    if t.blocks.count > 40 { Text("…").foregroundStyle(DS.Palette.inkSoft) }
                }
            } else {
                Button(action: choose) { Label(pageId == nil ? "Choose a page to embed" : "Page not found. Choose another", systemImage: "rectangle.on.rectangle") }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { Rectangle().fill(DS.Palette.accent.opacity(0.5)).frame(width: 3) }
        .background(DS.Palette.elevated.opacity(0.5), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Embedded page")
    }
}

private struct EmbeddedBlockLine: View {
    let block: NoteBlock
    var body: some View {
        let pad = CGFloat(block.indent ?? 0) * 16
        Group {
            switch block.kind {
            case .heading: Text(RichText.render(block.text)).font(.title3.weight(.bold))
            case .heading2, .heading3: Text(RichText.render(block.text)).font(.headline)
            case .bullet: Text("•  ") + Text(RichText.render(block.text))
            case .numbered: Text("–  ") + Text(RichText.render(block.text))
            case .todo: Text(block.checked ? "☑︎  " : "☐  ") + Text(RichText.render(block.text))
            case .quote, .callout: Text(RichText.render(block.text)).italic()
            case .divider: Divider()
            case .code: Text(block.text).font(.system(.caption, design: .monospaced))
            case .table: Text((block.rows ?? []).map { $0.joined(separator: " · ") }.joined(separator: "\n")).font(.caption)
            default: if !block.text.isEmpty { Text(RichText.render(block.text)) }
            }
        }
        .font(DS.Font.body)
        .padding(.leading, pad)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Table of contents / outline

struct OutlineEntry: Identifiable { let id: UUID; let level: Int; let title: String }

enum PageOutline {
    static func entries(_ n: Note) -> [OutlineEntry] {
        n.blocks.compactMap { b in
            let level: Int? = switch b.kind { case .heading: 0; case .heading2: 1; case .heading3: 2; default: nil }
            guard let level, !b.text.isEmpty else { return nil }
            return OutlineEntry(id: b.id, level: level, title: RichText.plain(b.text))
        }
    }
}

struct TableOfContentsView: View {
    let note: Note
    var jump: (UUID) -> Void
    var body: some View {
        let items = PageOutline.entries(note)
        VStack(alignment: .leading, spacing: 4) {
            if items.isEmpty {
                Text("Table of contents: add headings and they appear here.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            ForEach(items) { e in
                Button { jump(e.id) } label: {
                    Text(e.title).underline().foregroundStyle(DS.Palette.inkSoft)
                        .padding(.leading, CGFloat(e.level) * 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

struct OutlineSheet: View {
    let note: Note
    var jump: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                let items = PageOutline.entries(note)
                if items.isEmpty { Text("This page has no headings yet.").foregroundStyle(DS.Palette.inkSoft) }
                ForEach(items) { e in
                    Button { dismiss(); jump(e.id) } label: {
                        Text(e.title).font(e.level == 0 ? DS.Font.headline : DS.Font.body).padding(.leading, CGFloat(e.level) * 16)
                    }
                }
            }
            .navigationTitle("Outline").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Equations (KaTeX) and diagrams (Mermaid)

/// Renders LaTeX or Mermaid in a small web view. The renderer loads from a public CDN the first time and is then
/// cached; offline, the source text shows instead.
struct RichRenderView: UIViewRepresentable {
    enum Mode { case math, mermaid }
    let mode: Mode
    let source: String
    @Binding var height: CGFloat
    @Environment(\.colorScheme) private var scheme

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "size")
        let v = WKWebView(frame: .zero, configuration: config)
        v.isOpaque = false
        v.backgroundColor = .clear
        v.scrollView.isScrollEnabled = false
        v.navigationDelegate = context.coordinator
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) {
        let key = "\(mode)|\(scheme)|\(source)"
        guard context.coordinator.loaded != key else { return }
        context.coordinator.loaded = key
        v.loadHTMLString(html, baseURL: URL(string: "https://cdn.jsdelivr.net"))
    }

    static func dismantleUIView(_ v: WKWebView, coordinator: Coordinator) {
        v.configuration.userContentController.removeScriptMessageHandler(forName: "size")
    }

    private var escaped: String {
        source.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private var html: String {
        let dark = scheme == .dark
        let fg = dark ? "#f2f2f7" : "#1c1c1e"
        let report = "function report(){window.webkit.messageHandlers.size.postMessage(document.getElementById('c').getBoundingClientRect().height)}"
        switch mode {
        case .math:
            return """
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
            <style>body{margin:0;background:transparent;color:\(fg);font:17px -apple-system}#c{padding:6px 0;overflow-x:auto}</style></head>
            <body><div id="c">\(escaped)</div>
            <script>\(report)</script>
            <script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js" onload="try{katex.render(document.getElementById('c').textContent,document.getElementById('c'),{displayMode:true,throwOnError:false})}catch(e){};setTimeout(report,50)" onerror="report()"></script>
            <script>setTimeout(report,400)</script></body></html>
            """
        case .mermaid:
            return """
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <style>body{margin:0;background:transparent;color:\(fg);font:15px -apple-system}#c{padding:6px 0}#c svg{max-width:100%;height:auto}</style></head>
            <body><div id="c"><pre class="mermaid">\(escaped)</pre></div>
            <script>\(report)</script>
            <script src="https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.min.js" onload="mermaid.initialize({startOnLoad:false,theme:'\(dark ? "dark" : "default")'});mermaid.run().then(()=>setTimeout(report,50)).catch(()=>report())" onerror="report()"></script>
            <script>setTimeout(report,600)</script></body></html>
            """
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var height: Binding<CGFloat>
        var loaded = ""
        init(height: Binding<CGFloat>) { self.height = height }

        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
            if let h = message.body as? Double, h > 0 {
                let new = CGFloat(h) + 4
                DispatchQueue.main.async { if abs(self.height.wrappedValue - new) > 1 { self.height.wrappedValue = new } }
            }
        }

        // Links inside a diagram open in Safari, never inside the block.
        func webView(_ w: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

/// An equation or diagram block: rendered, and tap "Edit" for the source.
struct RenderedSourceBlock: View {
    @Binding var block: NoteBlock
    let mode: RichRenderView.Mode
    @State private var height: CGFloat = 60
    @State private var editingSource = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editingSource {
                TextField(mode == .math ? "LaTeX, e.g. E = mc^2 or \\frac{a}{b}" : "Mermaid, e.g. graph TD; A-->B", text: $block.text, axis: .vertical)
                    .font(.system(.callout, design: .monospaced))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            if !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                RichRenderView(mode: mode, source: block.text, height: $height)
                    .frame(height: height)
                    .allowsHitTesting(mode == .mermaid)
            }
            HStack {
                Text(mode == .math ? "Equation" : "Diagram").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                Spacer()
                Button(editingSource ? "Done" : "Edit") { editingSource.toggle() }.font(.caption)
            }
        }
        .padding(10)
        .background(DS.Palette.elevated.opacity(0.6), in: .rect(cornerRadius: 8))
    }
}

// MARK: - Comments (synced with the page)

struct NoteComment: Codable, Identifiable, Hashable {
    var id = UUID()
    var blockId: UUID?          // nil = about the whole page
    var text: String
    var by: String
    var at: Date = Date()
    var resolved: Bool = false
}

@MainActor
enum NoteComments {
    static let key = "comments"
    static func all(_ n: Note) -> [NoteComment] {
        guard let s = n.props[key], let d = s.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([NoteComment].self, from: d)) ?? []
    }
    static func save(_ list: [NoteComment], to n: Note) {
        if list.isEmpty { n.props[key] = nil; return }
        if let d = try? JSONEncoder().encode(list) { n.props[key] = String(data: d, encoding: .utf8) }
        n.updatedAt = Date()
    }
    static func open(_ n: Note, block: UUID) -> Int { all(n).filter { $0.blockId == block && !$0.resolved }.count }
    static var me: String {
        let name = KeelAccount.shared.name
        return name.isEmpty ? "Me" : name
    }
}

struct CommentsSheet: View {
    let note: Note
    var blockId: UUID?           // nil = every comment on the page
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var comments: [NoteComment] = []
    @State private var showResolved = false

    private var quoted: String? {
        guard let id = blockId, let b = note.blocks.first(where: { $0.id == id }) else { return nil }
        let t = RichText.plain(b.text)
        return t.isEmpty ? nil : t
    }

    var body: some View {
        NavigationStack {
            List {
                if let q = quoted {
                    Section { Text(q).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(3) }
                }
                let shown = comments.filter { (blockId == nil || $0.blockId == blockId) && (showResolved || !$0.resolved) }
                if shown.isEmpty { Text("No comments yet.").foregroundStyle(DS.Palette.inkSoft) }
                ForEach(shown) { c in
                    VStack(alignment: .leading, spacing: 3) {
                        if blockId == nil, let bid = c.blockId, let b = note.blocks.first(where: { $0.id == bid }) {
                            Text("On “\(RichText.plain(b.text).prefix(60))”").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Text(c.text).strikethrough(c.resolved)
                        Text("\(c.by) · \(c.at.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { update { $0.removeAll { $0.id == c.id } } }
                        Button(c.resolved ? "Reopen" : "Resolve") { update { l in if let i = l.firstIndex(where: { $0.id == c.id }) { l[i].resolved.toggle() } } }
                            .tint(.green)
                    }
                }
                Section {
                    HStack {
                        TextField(blockId == nil ? "Comment on this page" : "Add a comment", text: $draft, axis: .vertical)
                        Button("Send") {
                            let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !t.isEmpty else { return }
                            update { $0.append(NoteComment(blockId: blockId, text: t, by: NoteComments.me)) }
                            draft = ""
                            Haptics.tap()
                        }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } footer: { Text("Comments sync with the page to your other devices. Swipe a comment to resolve or delete it.") }
            }
            .navigationTitle("Comments").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Toggle("Resolved", isOn: $showResolved).toggleStyle(.button).font(.caption) }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { comments = NoteComments.all(note) }
        }
        .presentationDetents([.medium, .large])
    }

    private func update(_ change: (inout [NoteComment]) -> Void) {
        var l = NoteComments.all(note)
        change(&l)
        NoteComments.save(l, to: note)
        comments = l
    }
}

struct CommentTarget: Identifiable { let id = UUID(); let blockId: UUID? }

// MARK: - Find & replace

struct FindReplaceSheet: View {
    @Bindable var note: Note
    var jump: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var find = ""
    @State private var replace = ""
    @State private var matchCase = false

    private var options: String.CompareOptions { matchCase ? [] : [.caseInsensitive] }
    private var hits: [UUID] {
        guard !find.isEmpty else { return [] }
        return note.blocks.filter { $0.text.range(of: find, options: options) != nil || ($0.body ?? "").range(of: find, options: options) != nil }.map(\.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Find", text: $find).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Replace with", text: $replace).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("Match case", isOn: $matchCase)
                } footer: {
                    Text(find.isEmpty ? "Searches every block on this page." : "\(hits.count) block\(hits.count == 1 ? "" : "s") match.")
                }
                if !hits.isEmpty {
                    Section("Matches") {
                        ForEach(hits, id: \.self) { id in
                            if let b = note.blocks.first(where: { $0.id == id }) {
                                Button { dismiss(); jump(id) } label: { Text(RichText.plain(b.text)).lineLimit(2) }
                            }
                        }
                    }
                    Section {
                        Button("Replace all") {
                            for i in note.blocks.indices {
                                note.blocks[i].text = note.blocks[i].text.replacingOccurrences(of: find, with: replace, options: options)
                                if let body = note.blocks[i].body { note.blocks[i].body = body.replacingOccurrences(of: find, with: replace, options: options) }
                            }
                            note.title = note.title.replacingOccurrences(of: find, with: replace, options: options)
                            Haptics.success()
                            dismiss()
                        }
                    } footer: { Text("Version history keeps the page as it was, so you can undo.") }
                }
            }
            .navigationTitle("Find & replace").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { NoteHistory.snapshot(note) }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Quick switcher (⌘O)

struct QuickOpenView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var query = ""
    @FocusState private var focused: Bool

    private var results: [Note] {
        let pool = notes.filter { !$0.isTemplate }
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(pool.prefix(20)) }
        return pool.compactMap { n -> (Note, Int)? in
            let t = n.title.lowercased()
            if t == q { return (n, 0) }
            if t.hasPrefix(q) { return (n, 1) }
            if t.contains(q) { return (n, 2) }
            if Self.fuzzy(q, t) { return (n, 3) }
            if (n.folder ?? "").lowercased().contains(q) { return (n, 4) }
            return nil
        }
        .sorted { $0.1 < $1.1 }.prefix(30).map(\.0)
    }

    /// Letters in order, gaps allowed: "mtg nt" finds "Meeting notes".
    static func fuzzy(_ q: String, _ t: String) -> Bool {
        var it = t.makeIterator()
        for c in q where c != " " {
            var found = false
            while let x = it.next() { if x == c { found = true; break } }
            if !found { return false }
        }
        return true
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { n in
                    Button { open(n) } label: {
                        HStack {
                            Text(n.icon ?? (n.isDatabase ? "🗃️" : "📄"))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(n.title.isEmpty ? "Untitled" : n.title).foregroundStyle(DS.Palette.ink)
                                if let f = n.folder { Text(f.replacingOccurrences(of: "/", with: " › ")).font(.caption2).foregroundStyle(DS.Palette.inkSoft) }
                            }
                        }
                    }
                }
                if !query.trimmingCharacters(in: .whitespaces).isEmpty && !results.contains(where: { $0.title.caseInsensitiveCompare(query) == .orderedSame }) {
                    Button { let n = Note(title: query); ctx.insert(n); open(n) } label: { Label("Create “\(query)”", systemImage: "plus") }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Jump to a page")
            .searchFocused($focused)
            .onSubmit(of: .search) { if let first = results.first { open(first) } }
            .navigationTitle("Open").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { focused = true }
        }
    }

    private func open(_ n: Note) {
        dismiss()
        AppRouter.shared.openNoteId = n.id
    }
}

// MARK: - Unlinked mentions

struct UnlinkedMentions: View {
    let note: Note
    let notes: [Note]

    var body: some View {
        let title = note.title.trimmingCharacters(in: .whitespaces)
        let texts = LinkIndex.texts(notes)
        let lowTitle = title.lowercased(), url = RichText.pageURL(note.id)
        let hits: [Note] = title.count < 3 ? [] : notes.filter { other in
            guard other.id != note.id, !other.isLocked, !other.isTemplate, let low = texts.lower[other.id], low.contains(lowTitle) else { return false }
            return !low.contains("[[\(lowTitle)]]") && !(texts.raw[other.id] ?? "").contains(url)
        }
        if !hits.isEmpty {
            Text("MENTIONED IN").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).padding(.top, DS.Space.s)
            ForEach(hits.prefix(10)) { other in
                HStack {
                    NavigationLink { NoteEditor(note: other) } label: { Label(other.title.isEmpty ? "Untitled" : other.title, systemImage: "text.magnifyingglass") }
                    Spacer()
                    Button("Link") { link(in: other, title: title) }.font(DS.Font.caption).buttonStyle(.bordered)
                }
            }
        }
    }

    /// Turns the first plain mention into a [[link]].
    private func link(in other: Note, title: String) {
        for i in other.blocks.indices {
            if let r = other.blocks[i].text.range(of: title, options: [.caseInsensitive]) {
                let original = String(other.blocks[i].text[r])
                other.blocks[i].text.replaceSubrange(r, with: "[[\(original)]]")
                other.updatedAt = Date()
                Haptics.success()
                return
            }
        }
    }
}

// MARK: - Markdown folder (your notes as plain files you own)

/// Keeps a Markdown copy of every page in a folder you choose (iCloud Drive, On My iPhone, Dropbox…), in the same
/// folders as in Keel. Obsidian and any Markdown app can open that folder. Updated when you leave Keel.
@MainActor
enum MarkdownMirror {
    static let bookmarkKey = "mirror.bookmark", lastKey = "mirror.last", nameKey = "mirror.folderName"

    static var isOn: Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil }
    static var folderName: String { UserDefaults.standard.string(forKey: nameKey) ?? "" }
    static var last: Date? { UserDefaults.standard.object(forKey: lastKey) as? Date }

    static func choose(_ url: URL) -> Bool {
        guard url.startAccessingSecurityScopedResource() else { return false }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else { return false }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: nameKey)
        UserDefaults.standard.removeObject(forKey: lastKey)      // write everything the first time
        return true
    }

    static func turnOff() {
        for k in [bookmarkKey, lastKey, nameKey] { UserDefaults.standard.removeObject(forKey: k) }
    }

    private static func folderURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    /// Writes pages changed since the last run. Returns how many files were written.
    @discardableResult
    static func sync(ctx: ModelContext, everything: Bool = false) -> Int {
        guard let root = folderURL(), root.startAccessingSecurityScopedResource() else { return 0 }
        defer { root.stopAccessingSecurityScopedResource() }
        let since = everything ? .distantPast : (last ?? .distantPast)
        let notes = ((try? ctx.fetch(FetchDescriptor<Note>())) ?? []).filter { !$0.isLocked && !$0.isTemplate && $0.updatedAt > since }
        func safe(_ s: String) -> String {
            let t = s.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-").trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? "Untitled" : String(t.prefix(80))
        }
        let fm = FileManager.default
        var written = 0
        let coordinator = NSFileCoordinator()
        for n in notes {
            var dir = root
            for part in (n.folder ?? "").split(separator: "/") { dir.appendPathComponent(safe(String(part)), isDirectory: true) }
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            // One file per page; a short id keeps two pages with the same title apart.
            let name = "\(safe(n.title)).md"
            var file = dir.appendingPathComponent(name)
            if let existing = try? String(contentsOf: file, encoding: .utf8), !existing.contains("keel-id: \(n.id.uuidString)") {
                file = dir.appendingPathComponent("\(safe(n.title)) \(n.id.uuidString.prefix(4)).md")
            }
            let text = "---\nkeel-id: \(n.id.uuidString)\nupdated: \(ISO8601DateFormatter().string(from: n.updatedAt))\n---\n\n" + NoteExport.markdown(n)
            var err: NSError?
            coordinator.coordinate(writingItemAt: file, options: .forReplacing, error: &err) { url in
                if (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil { written += 1 }
            }
        }
        UserDefaults.standard.set(Date(), forKey: lastKey)
        return written
    }
}

struct MarkdownMirrorSection: View {
    @Environment(\.modelContext) private var ctx
    @State private var on = MarkdownMirror.isOn
    @State private var picking = false
    @State private var message: String?

    var body: some View {
        Section {
            if on {
                LabeledContent("Folder", value: MarkdownMirror.folderName)
                if let d = MarkdownMirror.last { LabeledContent("Last updated", value: d.formatted(.relative(presentation: .named))) }
                Button("Update now", systemImage: "arrow.triangle.2.circlepath") {
                    let n = MarkdownMirror.sync(ctx: ctx, everything: true)
                    message = "Wrote \(n) page\(n == 1 ? "" : "s")."
                }
                Button("Choose another folder", systemImage: "folder") { picking = true }
                Button("Stop keeping a copy", role: .destructive) { MarkdownMirror.turnOff(); on = false }
            } else {
                Button("Choose a folder…", systemImage: "folder.badge.plus") { picking = true }
            }
            if let message { Text(message).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft) }
        } header: { Text("Markdown copy of your notes") } footer: {
            Text("Keel keeps every page as a plain Markdown file in a folder you pick (iCloud Drive works well), in the same folders as in Keel, and updates it whenever you leave the app. Obsidian or any Markdown app can open that folder. Locked pages are never copied.")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result, MarkdownMirror.choose(url) {
                on = true
                let n = MarkdownMirror.sync(ctx: ctx, everything: true)
                message = "Copied \(n) page\(n == 1 ? "" : "s") to \(url.lastPathComponent)."
            } else if case .success = result {
                message = "Keel couldn't use that folder. Try one in iCloud Drive or On My iPhone."
            }
        }
    }
}

// MARK: - Database formulas and relations

/// A small, safe formula language for database properties:
/// numbers, + − × ÷, parentheses, {Property name}, and days({Date}) for days from today.
@MainActor
enum DBFormula {
    static func evaluate(_ expr: String, row: Note, schema: [DBProperty]) -> String {
        var s = expr
        // days({Date}) → days from today
        while let r = s.range(of: #"days\(\{([^}]+)\}\)"#, options: .regularExpression) {
            let name = String(s[r]).replacingOccurrences(of: "days({", with: "").replacingOccurrences(of: "})", with: "")
            var value = "0"
            if let p = schema.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
               let d = NotesDatabase.date(row.props[p.id] ?? "") {
                let cal = Calendar.current
                value = String(cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d)).day ?? 0)
            }
            s.replaceSubrange(r, with: value)
        }
        // {Name} → the property's number (checkbox = 1/0, multi-select/relation = count)
        while let r = s.range(of: #"\{([^}]+)\}"#, options: .regularExpression) {
            let name = String(s[r].dropFirst().dropLast())
            var value = "0"
            if let p = schema.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                let raw = row.props[p.id] ?? ""
                switch p.kind {
                case .checkbox: value = raw == "1" ? "1" : "0"
                case .multiSelect, .relation: value = String(raw.split(separator: ",").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count)
                default: value = Double(raw.replacingOccurrences(of: ",", with: "")).map { String($0) } ?? "0"
                }
            }
            s.replaceSubrange(r, with: value)
        }
        var p = Parser(Array(s.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/").replacingOccurrences(of: "−", with: "-")))
        guard let v = p.parse(), v.isFinite else { return "" }
        return v.rounded() == v && abs(v) < 1e15 ? String(Int(v)) : String(format: "%.2f", v)
    }

    private struct Parser {
        var c: [Character]; var i = 0
        init(_ c: [Character]) { self.c = c }
        mutating func parse() -> Double? { let v = expr(); skip(); return i == c.count ? v : nil }
        mutating func skip() { while i < c.count, c[i] == " " { i += 1 } }
        mutating func expr() -> Double? {
            guard var v = term() else { return nil }
            while true {
                skip()
                guard i < c.count, c[i] == "+" || c[i] == "-" else { return v }
                let op = c[i]; i += 1
                guard let r = term() else { return nil }
                v = op == "+" ? v + r : v - r
            }
        }
        mutating func term() -> Double? {
            guard var v = factor() else { return nil }
            while true {
                skip()
                guard i < c.count, c[i] == "*" || c[i] == "/" else { return v }
                let op = c[i]; i += 1
                guard let r = factor() else { return nil }
                v = op == "*" ? v * r : (r == 0 ? .nan : v / r)
            }
        }
        mutating func factor() -> Double? {
            skip()
            guard i < c.count else { return nil }
            if c[i] == "-" { i += 1; return factor().map { -$0 } }
            if c[i] == "(" {
                i += 1
                let v = expr(); skip()
                guard i < c.count, c[i] == ")" else { return nil }
                i += 1; return v
            }
            var s = ""
            while i < c.count, c[i].isNumber || c[i] == "." { s.append(c[i]); i += 1 }
            return Double(s)
        }
    }
}

/// Relation values: row ids from another database, comma-separated.
@MainActor
enum DBRelation {
    static func ids(_ raw: String) -> [UUID] { raw.split(separator: ",").compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespaces)) } }
    static func titles(_ raw: String, ctx: ModelContext?) -> [String] {
        let ids = ids(raw)
        guard !ids.isEmpty, let ctx else { return [] }
        let found = (try? ctx.fetch(FetchDescriptor<Note>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
        return ids.compactMap { id in found.first { $0.id == id }.map { $0.title.isEmpty ? "Untitled" : $0.title } }
    }
}

struct RelationPicker: View {
    let property: DBProperty
    @Bindable var row: Note
    @Environment(\.dismiss) private var dismiss
    @Query private var notes: [Note]
    @State private var search = ""

    private var targetId: UUID? { property.options.first.flatMap(UUID.init(uuidString:)) }
    private var selected: [UUID] { DBRelation.ids(row.props[property.id] ?? "") }

    var body: some View {
        NavigationStack {
            List {
                let candidates = notes.filter { $0.parentId == targetId && !$0.isTemplate && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }
                    .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
                if targetId == nil { Text("Pick which database this links to in the database's Properties.").foregroundStyle(DS.Palette.inkSoft) }
                ForEach(candidates) { n in
                    Button { toggle(n.id) } label: {
                        HStack {
                            Text(n.icon ?? "📄"); Text(n.title.isEmpty ? "Untitled" : n.title).foregroundStyle(DS.Palette.ink)
                            Spacer()
                            if selected.contains(n.id) { Image(systemName: "checkmark").foregroundStyle(DS.Palette.accent) }
                        }
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle(property.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func toggle(_ id: UUID) {
        var s = selected
        if let i = s.firstIndex(of: id) { s.remove(at: i) } else { s.append(id) }
        row.props[property.id] = s.isEmpty ? nil : s.map(\.uuidString).joined(separator: ",")
        Haptics.tap()
    }
}

struct RelationCell: View {
    let property: DBProperty
    @Bindable var row: Note
    @Environment(\.modelContext) private var ctx
    @State private var picking = false
    var body: some View {
        let titles = DBRelation.titles(row.props[property.id] ?? "", ctx: ctx)
        Button { picking = true } label: {
            Text(titles.isEmpty ? "Empty" : titles.joined(separator: ", ")).font(DS.Font.caption).lineLimit(1)
                .foregroundStyle(titles.isEmpty ? DS.Palette.inkSoft : DS.Palette.accent)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $picking) { RelationPicker(property: property, row: row) }
    }
}

// MARK: - Pickers used by "/" commands

struct PagePickerSheet: View {
    let title: String
    var databasesOnly = false
    var exclude: UUID?
    var pick: (Note) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                let list = notes.filter { $0.id != exclude && !$0.isTemplate && (!databasesOnly || $0.isDatabase) && !$0.isLocked
                    && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }
                if list.isEmpty { Text(databasesOnly ? "No databases yet. Make one from ⊕ → Database on any page." : "No pages found.").foregroundStyle(DS.Palette.inkSoft) }
                ForEach(list.prefix(60)) { n in
                    Button { pick(n); dismiss() } label: {
                        HStack { Text(n.icon ?? (n.isDatabase ? "🗃️" : "📄")); Text(n.title.isEmpty ? "Untitled" : n.title).foregroundStyle(DS.Palette.ink) }
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct BlockPickTarget: Identifiable { let id: UUID; let databasesOnly: Bool }

// MARK: - Smart paste: whatever you paste becomes the right blocks, evenly spaced

@MainActor
enum SmartPaste {
    /// What's on the clipboard, as blocks. Rich text from web pages and apps (HTML) keeps its headings, lists and links.
    static func fromPasteboard() -> [NoteBlock] {
        let pb = UIPasteboard.general
        if let data = pb.data(forPasteboardType: "public.html"), let html = String(data: data, encoding: .utf8), html.count > 20 {
            let b = blocks(from: HTMLImport.toMarkdown(html), markdown: true)
            if !b.isEmpty { return b }
        }
        if let s = pb.string { return blocks(from: s) }
        if let u = pb.url { return [NoteBlock(kind: .bookmark, text: "", refId: u.absoluteString)] }
        return []
    }

    /// Plain text → blocks: a link, a table (tabs or CSV, e.g. from a spreadsheet), code, or Markdown and paragraphs.
    static func blocks(from raw: String, markdown: Bool = false) -> [NoteBlock] {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let lines = text.components(separatedBy: "\n")
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // One link → a bookmark card.
        if nonEmpty.count == 1, !text.contains(" "), let u = URL(string: text), ["http", "https"].contains(u.scheme ?? "") {
            return [NoteBlock(kind: .bookmark, text: "", refId: text)]
        }
        // Spreadsheet cells (tab-separated) or CSV → a table.
        if !markdown, nonEmpty.count >= 2 {
            let tabs = nonEmpty.map { $0.components(separatedBy: "\t").count }
            if let first = tabs.first, first >= 2, tabs.allSatisfy({ $0 == first }) {
                var b = NoteBlock(kind: .table, text: "")
                b.rows = nonEmpty.map { $0.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) } }
                return [b]
            }
            let rows = ReadingImport.parseCSV(nonEmpty.joined(separator: "\n"))
            if let first = rows.first?.count, first >= 2, rows.count >= 2, rows.allSatisfy({ $0.count == first }),
               rows.joined().allSatisfy({ $0.count < 60 }) {          // short cells: data, not sentences with commas
                var b = NoteBlock(kind: .table, text: "")
                b.rows = rows.map { $0.map { $0.trimmingCharacters(in: .whitespaces) } }
                return [b]
            }
        }
        // Code: many lines ending in ; { } or starting with typical keywords.
        if !markdown, nonEmpty.count >= 3, !text.contains("```") {
            let codeish = nonEmpty.filter { l in
                let t = l.trimmingCharacters(in: .whitespaces)
                return t.hasSuffix(";") || t.hasSuffix("{") || t == "}" || ["func ", "let ", "var ", "const ", "def ", "import ", "return ", "if (", "class ", "#include"].contains { t.hasPrefix($0) }
            }.count
            if Double(codeish) / Double(nonEmpty.count) > 0.5 {
                var b = NoteBlock(kind: .code, text: text)
                b.lang = ""
                return [b]
            }
        }
        // Markdown (or plain paragraphs, which Markdown reads too).
        let looksMarkdown = markdown || lines.contains { l in
            let t = l.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("#") || t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("> ") || t.hasPrefix("|") || t.hasPrefix("```")
                || t.range(of: #"^\d+[.)] "#, options: .regularExpression) != nil || t.hasPrefix("[ ]") || t.hasPrefix("- [")
                || t.hasPrefix("• ") || t.hasPrefix("◦ ")
        }
        let source = looksMarkdown ? text.replacingOccurrences(of: "• ", with: "- ").replacingOccurrences(of: "◦ ", with: "    - ") : rejoin(text)
        let r = MarkdownImport.parse(source, dir: "")
        var out = r.blocks
        if let t = r.title, !t.isEmpty, !out.contains(where: { $0.text == t }) { out.insert(NoteBlock(kind: .heading, text: t), at: 0) }
        return tidy(out.isEmpty ? [NoteBlock(kind: .text, text: text)] : out)
    }

    /// Joins lines that were hard-wrapped mid-sentence (emails, PDFs) back into paragraphs; blank lines stay as breaks.
    static func rejoin(_ text: String) -> String {
        let paras = text.components(separatedBy: "\n\n")
        return paras.map { p in
            let ls = p.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            var out = ""
            for l in ls {
                if out.isEmpty { out = l; continue }
                let endsSentence = out.last.map { ".!?:;\"”)".contains($0) } ?? true
                let startsLower = l.first.map { $0.isLowercase } ?? false
                out += (!endsSentence || startsLower) ? " " + l : "\n\n" + l
            }
            return out
        }.joined(separator: "\n\n")
    }

    /// Even spacing: every paragraph is its own block and the page spaces blocks evenly, so blank lines from the
    /// clipboard are dropped instead of becoming uneven gaps. Extra spaces are trimmed too.
    static func tidy(_ blocks: [NoteBlock]) -> [NoteBlock] {
        blocks.compactMap { raw in
            var b = raw
            b.text = b.text.trimmingCharacters(in: .whitespaces)
            let empty = b.text.isEmpty && [.text, .bullet, .numbered, .quote, .todo].contains(b.kind)
            return empty ? nil : b
        }
    }
}
