import SwiftUI
import SwiftData
import PhotosUI
import PDFKit
import UniformTypeIdentifiers
import FoundationModels

// MARK: - Paperwork vault

/// Notes → Vault: receipts, warranties, IDs, insurance cards, medical and school forms. Keel reads each one,
/// files it under Vault/<kind>, and reminds you before it expires or a return window closes.
@MainActor
enum PaperworkVault {
    static let workspace = "Vault"
    static let kindKey = "vault.kind", expiresKey = "vault.expires", returnKey = "vault.returnBy", amountKey = "vault.amount"

    struct Kind { let id: String; let title: String; let icon: String; let words: [String] }
    static let kinds: [Kind] = [
        Kind(id: "receipt", title: "Receipts", icon: "receipt", words: ["receipt", "total", "subtotal", "order #", "paid", "visa", "mastercard", "change due"]),
        Kind(id: "warranty", title: "Warranties", icon: "checkmark.shield", words: ["warranty", "guarantee", "serial number", "model number", "coverage"]),
        Kind(id: "id", title: "IDs", icon: "person.text.rectangle", words: ["passport", "driver license", "driver's license", "identification", "date of birth", "dob"]),
        Kind(id: "insurance", title: "Insurance", icon: "cross.case", words: ["insurance", "member id", "policy", "group number", "copay", "plan"]),
        Kind(id: "medical", title: "Medical", icon: "stethoscope", words: ["prescription", "patient", "diagnosis", "clinic", "rx", "lab results"]),
        Kind(id: "school", title: "School", icon: "graduationcap", words: ["school", "student", "teacher", "permission slip", "field trip", "report card", "grade"]),
        Kind(id: "bill", title: "Bills", icon: "doc.text", words: ["invoice", "amount due", "statement", "due date", "account number"]),
        Kind(id: "contract", title: "Contracts", icon: "signature", words: ["agreement", "contract", "lease", "terms", "signature"]),
        Kind(id: "other", title: "Other", icon: "tray.full", words: []),
    ]

    @Generable
    struct Read {
        @Guide(description: "One of: receipt, warranty, id, insurance, medical, school, bill, contract, other") var kind: String
        @Guide(description: "A short title, e.g. 'Best Buy receipt: blender', 'Passport', 'Blue Cross card'") var title: String
        @Guide(description: "Expiry date as YYYY-MM-DD, or empty") var expires: String
        @Guide(description: "Last day to return or exchange as YYYY-MM-DD, or empty") var returnBy: String
        @Guide(description: "Total amount with currency symbol, or empty") var amount: String
        @Guide(description: "One sentence on what this document is") var summary: String
    }

    static func kindTitle(_ id: String) -> String { kinds.first { $0.id == id }?.title ?? "Other" }

    /// Files one document: pages (images) and/or text already read from a PDF.
    static func file(images: [UIImage], pdfText: String = "", pdfData: Data? = nil, ctx: ModelContext) async -> Note {
        var text = pdfText
        for img in images { text += "\n" + (await NoteMedia.recognizeText(img)) }
        let r = await read(text)
        let note = Note(title: r.title, blocks: [])
        note.icon = "🗂️"
        note.folder = NotePath.make(workspace, kindTitle(r.kind))
        note.props[kindKey] = r.kind
        if let d = parse(r.expires) { note.props[expiresKey] = ISO8601DateFormatter.dateOnly.string(from: d) }
        if let d = parse(r.returnBy) { note.props[returnKey] = ISO8601DateFormatter.dateOnly.string(from: d) }
        if !r.amount.isEmpty { note.props[amountKey] = r.amount }
        var summary = NoteBlock(kind: .callout, text: r.summary); summary.icon = "🗂️"
        note.blocks = [summary]
        var facts: [String] = []
        if let e = note.props[expiresKey] { facts.append("Expires \(e)") }
        if let rb = note.props[returnKey] { facts.append("Return by \(rb)") }
        if !r.amount.isEmpty { facts.append("Amount \(r.amount)") }
        if !facts.isEmpty { note.blocks.append(NoteBlock(kind: .text, text: facts.joined(separator: " · "))) }
        ctx.insert(note)
        for img in images {
            if let jpg = NoteMedia.jpeg(img) { NoteMedia.add(jpg, kind: "scan", to: note, ctx: ctx, text: "") }
        }
        if let pdfData { NoteMedia.add(pdfData, kind: "file", to: note, ctx: ctx, text: "") }
        let body = NoteBlock(kind: .toggle, text: "Text found in the document")
        var b = body; b.body = String(text.prefix(20_000)); b.collapsed = true
        note.blocks.append(b)
        remind(note, ctx: ctx)
        try? ctx.save()
        return note
    }

    /// A task a week before a return window closes or a document expires (a month before for IDs).
    static func remind(_ n: Note, ctx: ModelContext) {
        let cal = Calendar.current
        if let s = n.props[returnKey], let d = parse(s), let due = cal.date(byAdding: .day, value: -3, to: d), due > Date() {
            let t = TaskItem(title: "Return window closes: \(n.title)", dueDate: due, priority: .medium)
            t.sourceNoteId = n.id; ctx.insert(t)
        }
        if let s = n.props[expiresKey], let d = parse(s) {
            let lead = n.props[kindKey] == "id" ? -45 : -14
            if let due = cal.date(byAdding: .day, value: lead, to: d), due > Date() {
                let t = TaskItem(title: "Renew: \(n.title) (expires \(d.formatted(date: .abbreviated, time: .omitted)))", dueDate: due, priority: .medium)
                t.sourceNoteId = n.id; ctx.insert(t)
            }
        }
    }

    static func read(_ text: String) async -> Read {
        if case .available = SystemLanguageModel.default.availability, text.count > 20 {
            let s = LanguageModelSession(instructions: "You file personal paperwork. Today is \(Date().formatted(.iso8601.year().month().day())). Read the document text.")
            if let r = try? await s.respond(to: String(text.prefix(4_000)), generating: Read.self).content { return r }
        }
        let low = text.lowercased()
        let kind = kinds.max { a, b in a.words.filter { low.contains($0) }.count < b.words.filter { low.contains($0) }.count }?.id ?? "other"
        let first = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { $0.count > 3 } ?? "Document"
        return Read(kind: kind, title: String(first.prefix(60)), expires: "", returnBy: "", amount: "", summary: "\(kindTitle(kind).dropLast()) filed \(Date().formatted(date: .abbreviated, time: .omitted)).")
    }

    static func parse(_ s: String) -> Date? { s.count >= 10 ? ISO8601DateFormatter.dateOnly.date(from: String(s.prefix(10))) : nil }

    static func pdfText(_ data: Data) -> String {
        guard let doc = PDFDocument(data: data) else { return "" }
        return (0..<min(doc.pageCount, 20)).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
    }
}

struct VaultView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var scanning = false
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var working = false
    @State private var opened: Note?

    private var docs: [Note] { notes.filter { $0.props[PaperworkVault.kindKey] != nil } }
    private var soon: [Note] {
        let horizon = Date().addingTimeInterval(45 * 86_400)
        return docs.filter { n in
            [n.props[PaperworkVault.expiresKey], n.props[PaperworkVault.returnKey]].compactMap { $0 }.compactMap(PaperworkVault.parse).contains { $0 > Date() && $0 < horizon }
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    #if !targetEnvironment(macCatalyst)
                    vaultButton("Scan", "doc.viewfinder") { scanning = true }
                    #endif
                    PhotosPicker(selection: $photo, matching: .images) { tile("Photo", "photo") }.buttonStyle(.plain)
                    vaultButton("File", "doc.badge.plus") { importing = true }
                }
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                if working { ProgressView("Reading the document…") }
            } footer: {
                Text("Keel reads each document on your iPhone, files it by type, and adds a reminder before it expires or a return window closes.")
            }
            if !soon.isEmpty {
                Section("Coming up") { ForEach(soon) { row($0) } }
            }
            ForEach(PaperworkVault.kinds, id: \.id) { k in
                let items = docs.filter { $0.props[PaperworkVault.kindKey] == k.id }
                if !items.isEmpty {
                    Section { ForEach(items) { row($0) } } header: { Label(k.title, systemImage: k.icon) }
                }
            }
            if docs.isEmpty && !working {
                ContentUnavailableView("Your vault is empty", systemImage: "archivebox", description: Text("Scan a receipt, warranty, ID or school form to start."))
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Paperwork vault")
        .navigationDestination(item: $opened) { NoteEditor(note: $0) }
        #if !targetEnvironment(macCatalyst)
        .fullScreenCover(isPresented: $scanning) {
            DocumentScanner { pages in Task { await add(images: pages) } }.ignoresSafeArea()
        }
        #endif
        .onChange(of: photo) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) { await add(images: [img]) }
                photo = nil
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image]) { result in
            guard case .success(let url) = result else { return }
            Task {
                let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { return }
                if let img = UIImage(data: data) { await add(images: [img]) }
                else { await add(images: [], pdf: data) }
            }
        }
    }

    private func add(images: [UIImage], pdf: Data? = nil) async {
        working = true; defer { working = false }
        let n = await PaperworkVault.file(images: images, pdfText: pdf.map(PaperworkVault.pdfText) ?? "", pdfData: pdf, ctx: ctx)
        Haptics.success()
        opened = n
    }

    private func row(_ n: Note) -> some View {
        Button { opened = n } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(n.title.isEmpty ? "Document" : n.title).foregroundStyle(DS.Palette.ink)
                let bits = [n.props[PaperworkVault.amountKey], n.props[PaperworkVault.expiresKey].map { "expires \($0)" }, n.props[PaperworkVault.returnKey].map { "return by \($0)" }].compactMap { $0 }
                if !bits.isEmpty { Text(bits.joined(separator: " · ")).font(.caption2).foregroundStyle(DS.Palette.inkSoft) }
            }
        }
    }

    private func vaultButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { tile(title, icon) }.buttonStyle(.plain)
    }

    private func tile(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3.weight(.semibold))
            Text(title).font(DS.Font.caption.weight(.semibold))
        }
        .foregroundStyle(DS.Palette.accent)
        .frame(maxWidth: .infinity, minHeight: 70)
        .background(DS.Palette.elevated, in: .rect(cornerRadius: 16))
    }
}

// MARK: - Version history

/// Earlier versions of every page, saved on this device each time you open it (last 40 per page).
@MainActor
enum NoteHistory {
    struct Version: Codable, Identifiable {
        var id: Double { at }
        var at: Double
        var title: String
        var blocks: [NoteBlock]
    }

    private static func dir(_ id: UUID) -> URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NoteHistory/\(id.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func versions(_ n: Note) -> [Version] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir(n.id), includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { try? JSONDecoder().decode(Version.self, from: Data(contentsOf: $0)) }.sorted { $0.at > $1.at }
    }

    /// Saves the page as it is now, unless nothing changed since the last saved version.
    static func snapshot(_ n: Note) {
        guard !n.isLocked else { return }
        let all = versions(n)
        if let last = all.first, last.title == n.title, last.blocks == n.blocks { return }
        let v = Version(at: Date().timeIntervalSince1970, title: n.title, blocks: n.blocks)
        if let data = try? JSONEncoder().encode(v) {
            try? data.write(to: dir(n.id).appendingPathComponent("\(Int(v.at)).json"))
        }
        for old in all.dropFirst(39) { try? FileManager.default.removeItem(at: dir(n.id).appendingPathComponent("\(Int(old.at)).json")) }
    }

    static func restore(_ v: Version, into n: Note) {
        snapshot(n)                       // keep what's there now, so restoring can be undone
        n.title = v.title
        n.blocks = v.blocks
        n.updatedAt = Date()
    }
}

struct NoteHistoryView: View {
    @Bindable var note: Note
    @Environment(\.dismiss) private var dismiss
    @State private var versions: [NoteHistory.Version] = []
    @State private var preview: NoteHistory.Version?

    var body: some View {
        NavigationStack {
            List {
                if versions.isEmpty {
                    ContentUnavailableView("No earlier versions yet", systemImage: "clock.arrow.circlepath", description: Text("Keel saves a version each time you open this page."))
                }
                ForEach(versions) { v in
                    Button { preview = v } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Date(timeIntervalSince1970: v.at).formatted(date: .abbreviated, time: .shortened)).foregroundStyle(DS.Palette.ink)
                            Text(v.blocks.map { RichText.plain($0.text) }.filter { !$0.isEmpty }.prefix(2).joined(separator: " · "))
                                .font(.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                        }
                    }
                }
            }
            .navigationTitle("Version history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { versions = NoteHistory.versions(note) }
            .sheet(item: $preview) { v in
                NavigationStack {
                    List {
                        Text(v.title).font(DS.Font.title)
                        ForEach(v.blocks) { b in Text(RichText.plain(b.kind == .todo ? (b.checked ? "☑ " : "☐ ") + b.text : b.text)) }
                    }
                    .navigationTitle(Date(timeIntervalSince1970: v.at).formatted(date: .abbreviated, time: .shortened))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Restore") { NoteHistory.restore(v, into: note); Haptics.success(); preview = nil; dismiss() }
                        }
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { preview = nil } }
                    }
                }
            }
        }
    }
}

// MARK: - Canvas whiteboard

/// A canvas is a page whose content is cards on an endless board, with arrows between them.
struct CanvasCard: Codable, Identifiable, Hashable {
    var id = UUID()
    var x: Double
    var y: Double
    var text: String
    var pageId: UUID?
    var color: String = "yellow"
}
struct CanvasLink: Codable, Hashable { var from: UUID; var to: UUID }
struct CanvasData: Codable { var cards: [CanvasCard] = []; var links: [CanvasLink] = [] }

@MainActor
enum KeelCanvas {
    static let flag = "canvas"
    static func isCanvas(_ n: Note) -> Bool { n.props[flag] == "1" }

    static func create(ctx: ModelContext, folder: String?) -> Note {
        let n = Note(title: "Untitled canvas", blocks: [])
        n.icon = "🧭"
        n.folder = folder
        n.props[flag] = "1"
        save(CanvasData(cards: [CanvasCard(x: 0, y: 0, text: "Start here")]), to: n)
        ctx.insert(n)
        return n
    }

    static func load(_ n: Note) -> CanvasData {
        guard let raw = n.blocks.first(where: { $0.kind == .code && $0.lang == "keel-canvas" })?.text,
              let d = try? JSONDecoder().decode(CanvasData.self, from: Data(raw.utf8)) else { return CanvasData() }
        return d
    }

    static func save(_ d: CanvasData, to n: Note) {
        guard let raw = try? String(data: JSONEncoder().encode(d), encoding: .utf8) else { return }
        var b = NoteBlock(kind: .code, text: raw); b.lang = "keel-canvas"
        // Card text also goes in plain blocks, so search, AI and the brain map can see it.
        n.blocks = [b] + d.cards.filter { !$0.text.isEmpty }.map { NoteBlock(kind: .bullet, text: $0.text) }
        n.updatedAt = Date()
    }
}

/// Opens a page in the right editor: canvases on the board, everything else in the page editor.
struct NoteOrCanvas: View {
    let note: Note
    var body: some View {
        if KeelCanvas.isCanvas(note) { CanvasBoardView(note: note) } else { NoteEditor(note: note) }
    }
}

struct CanvasBoardView: View {
    @Bindable var note: Note
    @Query private var allNotes: [Note]
    @State private var data = CanvasData()
    @State private var offset = CGSize.zero
    @State private var dragStart = CGSize.zero
    @State private var scale: CGFloat = 1
    @State private var scaleStart: CGFloat = 1
    @State private var selected: UUID?
    @State private var linking = false
    @State private var editing: CanvasCard?
    @State private var pickingPage = false
    @State private var openPage: Note?

    private static let colors: [String: Color] = ["yellow": .yellow, "blue": .blue, "green": .green, "pink": .pink, "purple": .purple, "gray": .gray]

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2 + offset.width, y: geo.size.height / 2 + offset.height)
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .contentShape(Rectangle())
                    .gesture(DragGesture().onChanged { v in offset = CGSize(width: dragStart.width + v.translation.width, height: dragStart.height + v.translation.height) }
                        .onEnded { _ in dragStart = offset })
                    .simultaneousGesture(MagnifyGesture().onChanged { v in scale = min(2.5, max(0.4, scaleStart * v.magnification)) }.onEnded { _ in scaleStart = scale })
                    .onTapGesture { selected = nil; linking = false }
                Canvas { ctx, _ in
                    for l in data.links {
                        guard let a = data.cards.first(where: { $0.id == l.from }), let b = data.cards.first(where: { $0.id == l.to }) else { continue }
                        var p = Path()
                        p.move(to: point(a, center)); p.addLine(to: point(b, center))
                        ctx.stroke(p, with: .color(.secondary), lineWidth: 2)
                    }
                }
                .allowsHitTesting(false)
                ForEach(data.cards) { c in
                    card(c)
                        .position(point(c, center))
                        .gesture(DragGesture().onChanged { v in move(c.id, by: v.translation) }.onEnded { _ in commitMove(c.id) })
                        .onTapGesture { tap(c) }
                }
            }
            .clipped()
        }
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { addCard() } label: { Label("Card", systemImage: "note.text.badge.plus") }
                Button { pickingPage = true } label: { Label("Page", systemImage: "doc.badge.plus") }
                Button { linking.toggle() } label: { Label(linking ? "Pick a card" : "Connect", systemImage: "arrow.triangle.branch") }
                    .disabled(selected == nil)
                Button(role: .destructive) { deleteSelected() } label: { Label("Delete", systemImage: "trash") }.disabled(selected == nil)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { withAnimation(DS.spring) { offset = .zero; dragStart = .zero; scale = 1; scaleStart = 1 } } label: { Image(systemName: "scope") }
                    .accessibilityLabel("Back to center")
            }
        }
        .onAppear { data = KeelCanvas.load(note) }
        .sheet(item: $editing) { c in
            CardEditor(card: c) { updated in
                if let i = data.cards.firstIndex(where: { $0.id == updated.id }) { data.cards[i] = updated; persist() }
            }
        }
        .sheet(isPresented: $pickingPage) {
            NavigationStack {
                List(allNotes.filter { $0.id != note.id && !$0.isTemplate && !$0.title.isEmpty }) { n in
                    Button(n.title) {
                        data.cards.append(CanvasCard(x: Double(-offset.width / scale), y: Double(-offset.height / scale), text: n.title, pageId: n.id, color: "blue"))
                        persist(); pickingPage = false
                    }
                }
                .navigationTitle("Add a page").navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
        .navigationDestination(item: $openPage) { NoteEditor(note: $0) }
    }

    private func point(_ c: CanvasCard, _ center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + c.x * scale, y: center.y + c.y * scale)
    }

    private func card(_ c: CanvasCard) -> some View {
        let color = Self.colors[c.color] ?? .yellow
        return HStack(spacing: 6) {
            if c.pageId != nil { Image(systemName: "doc.text").font(.caption) }
            Text(c.text.isEmpty ? "Tap to write" : c.text).font(.callout).lineLimit(6)
        }
        .padding(10)
        .frame(width: 160 * scale > 90 ? 160 : 90)
        .background(color.opacity(0.22), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected == c.id ? DS.Palette.accent : color.opacity(0.5), lineWidth: selected == c.id ? 2.5 : 1))
        .scaleEffect(scale)
    }

    @State private var moveStart: [UUID: CGPoint] = [:]
    private func move(_ id: UUID, by t: CGSize) {
        guard let i = data.cards.firstIndex(where: { $0.id == id }) else { return }
        let start = moveStart[id] ?? CGPoint(x: data.cards[i].x, y: data.cards[i].y)
        moveStart[id] = start
        data.cards[i].x = start.x + t.width / scale
        data.cards[i].y = start.y + t.height / scale
    }
    private func commitMove(_ id: UUID) { moveStart[id] = nil; persist() }

    private func tap(_ c: CanvasCard) {
        if linking, let from = selected, from != c.id {
            data.links.append(CanvasLink(from: from, to: c.id)); linking = false; selected = c.id; persist(); Haptics.tap(); return
        }
        if selected == c.id {
            if let pid = c.pageId, let n = allNotes.first(where: { $0.id == pid }) { openPage = n } else { editing = c }
        } else {
            selected = c.id
        }
    }

    private func addCard() {
        let c = CanvasCard(x: Double(-offset.width / scale) + Double.random(in: -30...30), y: Double(-offset.height / scale) + Double.random(in: -30...30), text: "")
        data.cards.append(c); selected = c.id; editing = c; persist()
    }

    private func deleteSelected() {
        guard let id = selected else { return }
        data.cards.removeAll { $0.id == id }
        data.links.removeAll { $0.from == id || $0.to == id }
        selected = nil; persist()
    }

    private func persist() { KeelCanvas.save(data, to: note) }
}

private struct CardEditor: View {
    @State var card: CanvasCard
    let onSave: (CanvasCard) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Write on the card", text: $card.text, axis: .vertical).lineLimit(3...10)
                Picker("Color", selection: $card.color) {
                    ForEach(["yellow", "blue", "green", "pink", "purple", "gray"], id: \.self) { Text($0.capitalized).tag($0) }
                }
            }
            .navigationTitle("Card").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { onSave(card); dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Tags & saved searches

/// #tags written anywhere in notes, plus task tags, in one browser.
@MainActor
enum KeelTags {
    static func tags(in text: String) -> [String] {
        guard text.contains("#") else { return [] }
        let re = try? NSRegularExpression(pattern: #"(?<![\w&/])#([A-Za-z][\w-]{1,30})"#)
        let ns = text as NSString
        return (re?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? []).map { ns.substring(with: $0.range(at: 1)).lowercased() }
    }

    static func noteTags(_ n: Note) -> Set<String> {
        guard !n.isLocked else { return [] }
        return Set(tags(in: n.title + "\n" + n.plainText))
    }

    static let savedKey = "notes.savedSearches"
    static var saved: [String] {
        get { UserDefaults.standard.stringArray(forKey: savedKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(20)), forKey: savedKey) }
    }
}

struct TagBrowserView: View {
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var tasks: [TaskItem]
    @State private var index: [String: [Note]] = [:]
    @State private var savedSearches = KeelTags.saved

    var body: some View {
        List {
            if !savedSearches.isEmpty {
                Section("Saved searches") {
                    ForEach(savedSearches, id: \.self) { q in
                        NavigationLink { SearchResultsList(query: q) } label: { Label(q, systemImage: "magnifyingglass") }
                    }
                    .onDelete { idx in savedSearches.remove(atOffsets: idx); KeelTags.saved = savedSearches }
                }
            }
            Section {
                if index.isEmpty && taskTags.isEmpty {
                    Text("Write #anything in a note, like #recipes or #ideas, and it shows up here.").foregroundStyle(DS.Palette.inkSoft)
                }
                ForEach(allTags, id: \.self) { tag in
                    NavigationLink { TagDetail(tag: tag, notes: index[tag] ?? [], tasks: tasks.filter { $0.tags.map { $0.lowercased() }.contains(tag) }) } label: {
                        HStack {
                            Label("#\(tag)", systemImage: "number")
                            Spacer()
                            Text("\((index[tag]?.count ?? 0) + tasks.filter { $0.tags.map { $0.lowercased() }.contains(tag) }.count)").foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                }
            } header: { Text("Tags") }
        }
        .navigationTitle("Tags & searches")
        .task {
            var idx: [String: [Note]] = [:]
            for n in notes where !n.isTemplate { for t in KeelTags.noteTags(n) { idx[t, default: []].append(n) } }
            index = idx
        }
    }

    private var taskTags: Set<String> { Set(tasks.flatMap { $0.tags.map { $0.lowercased() } }) }
    private var allTags: [String] { Array(Set(index.keys).union(taskTags)).sorted() }
}

private struct TagDetail: View {
    let tag: String
    let notes: [Note]
    let tasks: [TaskItem]
    var body: some View {
        List {
            if !notes.isEmpty {
                Section("Notes") { ForEach(notes) { n in NavigationLink(n.title.isEmpty ? "Untitled" : n.title) { NoteOrCanvas(note: n) } } }
            }
            if !tasks.isEmpty {
                Section("Tasks") { ForEach(tasks) { t in NavigationLink(t.title) { TaskDetailView(task: t) } } }
            }
        }
        .navigationTitle("#\(tag)")
    }
}

private struct SearchResultsList: View {
    let query: String
    @Query private var notes: [Note]
    var body: some View {
        let hits = notes.filter { !$0.isTemplate && ($0.title.localizedCaseInsensitiveContains(query) || (!$0.isLocked && $0.plainText.localizedCaseInsensitiveContains(query))) }
        List(hits) { n in NavigationLink(n.title.isEmpty ? "Untitled" : n.title) { NoteOrCanvas(note: n) } }
            .overlay { if hits.isEmpty { ContentUnavailableView.search(text: query) } }
            .navigationTitle(query)
    }
}
