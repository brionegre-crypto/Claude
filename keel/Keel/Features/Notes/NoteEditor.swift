import UniformTypeIdentifiers
import SwiftUI
import SwiftData
import PhotosUI
#if !targetEnvironment(macCatalyst)
import VisionKit
#endif

/// A page: cover, icon, title and blocks. Type "/" for any block, "@" to mention a page, person or date,
/// and markdown shortcuts ("- ", "[] ", "# ", "> ") as you type. Return starts the next block.
struct NoteEditor: View {
    @Environment(\.modelContext) private var ctx
    @Bindable var note: Note
    /// Open scrolled to this line (from a line link, supertag collection or search).
    var focusBlock: UUID? = nil
    @Query private var allNotes: [Note]
    @Query(sort: \Person.name) private var people: [Person]

    @FocusState private var focused: UUID?
    @State private var editing: UUID?
    @State private var showHistory = false
    @State private var publishedURL: URL?
    @State private var publishError: String?
    @State private var selection: TextSelection?
    @State private var slashFor: UUID?
    @State private var slashQuery = ""
    @State private var mentionFor: UUID?
    @State private var mentionQuery = ""
    @State private var reordering = false
    @State private var openPage: Note?

    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var imageTarget: UUID?
    @State private var coverItem: PhotosPickerItem?
    @State private var showSketch = false
    @State private var showScanner = false
    @State private var scanning = false
    @State private var showIcons = false

    @State private var unlocked = false
    @State private var exportURL: URL?
    @State private var asking = false
    @State private var question = ""
    @State private var answer: String?
    @State private var aiWorking = false
    @State private var movingPage = false
    @State private var recording = false
    @State private var commentTarget: CommentTarget?
    @State private var showFindReplace = false
    @State private var showOutline = false
    @State private var pickBlock: BlockPickTarget?
    @State private var scrollTarget: UUID?
    @State private var zoomRoot: UUID?              // outliner: show one line and what's under it
    @State private var supertagDefs: [SupertagDef] = []
    @State private var openAt: UUID?
    @State private var importingPDF = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismissPage
    @State private var importingFile = false
    @State private var fileTarget: UUID?
    @State private var zen = false
    @State private var showLocalGraph = false
    @State private var personSheet: Person?
    @State private var aiWrite: AIWriteRequest?
    @AppStorage(PageLook.widthKey) private var pageWidth = "comfortable"
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var multiWindow

    var body: some View {
        editorBody.savePoint { SavePoints.note(note, focusedBlock: focused ?? editing) }
    }

    @ViewBuilder private var editorBody: some View {
        if note.isLocked && !unlocked {
            ContentUnavailableView {
                Label("This note is locked", systemImage: "lock.fill")
            } description: {
                Text(note.title)
            } actions: {
                Button("Unlock with \(AppLock.biometryName)") { Task { await unlockNote() } }
                    .buttonStyle(.borderedProminent).tint(DS.Palette.accent)
            }
            .task { await unlockNote() }
            .onAppear { NoteHistory.snapshot(note) }       // the page as it was before this visit, for Version history
            .sheet(isPresented: $showHistory) { NoteHistoryView(note: note) }
            .sheet(item: Binding(get: { publishedURL.map { PublishedLink(url: $0) } }, set: { if $0 == nil { publishedURL = nil } })) { link in
                PublishedSheet(url: link.url)
            }
            .alert("Couldn't publish", isPresented: Binding(get: { publishError != nil }, set: { if !$0 { publishError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(publishError ?? "") }
        } else {
            page
        }
    }

    // MARK: Page

    private var page: some View {
        ScrollViewReader { proxy in pageList.onChange(of: scrollTarget) { _, id in
            guard let id else { return }
            withAnimation(DS.spring) { proxy.scrollTo(id, anchor: .top) }
            scrollTarget = nil
        } }
        .sheet(item: $commentTarget) { CommentsSheet(note: note, blockId: $0.blockId) }
        .fileImporter(isPresented: $importingPDF, allowedContentTypes: [.pdf]) { r in
            if case .success(let url) = r { PDFImport.add(url, to: note, ctx: ctx) }
        }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.item]) { r in
            guard case .success(let url) = r, let target = fileTarget else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let i = note.blocks.firstIndex(where: { $0.id == target }) else { return }
            let a = NoteAttachment(noteId: note.id, data: data, kind: "file")
            a.recognizedText = url.lastPathComponent
            ctx.insert(a)
            note.blocks[i].refId = a.id.uuidString
        }
        .sheet(isPresented: $showLocalGraph) { LocalGraphView(note: note) }
        .confirmationDialog("Delete “\(note.title.isEmpty ? "Untitled" : note.title)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete page", role: .destructive) {
                // Pages inside move up a level; the page waits in Recently deleted for 30 days.
                let n = note
                for child in allNotes where child.parentId == n.id { if n.isDatabase { NoteTrash.delete(child, ctx: ctx) } else { child.parentId = n.parentId } }
                dismissPage()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    NoteTrash.delete(n, ctx: ctx)
                    UndoCenter.shared.notify("Moved to Recently deleted")
                    Haptics.tap()
                }
            }
        } message: { Text("It stays in Recently deleted for 30 days, so you can bring it back.") }
        .sheet(item: $personSheet) { p in NavigationStack { PersonPageView(person: p) } }
        .sheet(item: $aiWrite) { r in
            AIWriteSheet(request: r, pageTitle: note.title, pageText: note.plainText) { text, replace in applyAI(r, text: text, replace: replace) }
        }
        .toolbar(zen ? .hidden : .automatic, for: .navigationBar)
        .statusBarHidden(zen)
        .overlay(alignment: .topTrailing) {
            if zen {
                Button { withAnimation(DS.spring) { zen = false } } label: { Image(systemName: "arrow.down.right.and.arrow.up.left").padding(10).background(.ultraThinMaterial, in: Circle()) }
                    .padding().accessibilityLabel("Leave focus mode")
            }
        }
        .onDisappear { if note.isLocked { PageCrypto.encrypt(note) } }       // locked pages are stored encrypted whenever they're closed
        .sheet(isPresented: $showFindReplace) { FindReplaceSheet(note: note) { scrollTarget = $0 } }
        .background {
            Group {
                Button("Find in Page") { showFindReplace = true }.keyboardShortcut("f", modifiers: [.command, .option])
                Button("Outline") { showOutline = true }.keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Comments") { commentTarget = CommentTarget(blockId: nil) }.keyboardShortcut("m", modifiers: [.command, .shift])
            }
            .hidden()
        }
        .sheet(isPresented: $showOutline) { OutlineSheet(note: note) { id in scrollTarget = id } }
        .sheet(item: $pickBlock) { t in
            PagePickerSheet(title: t.databasesOnly ? "Choose a database" : "Embed a page", databasesOnly: t.databasesOnly, exclude: note.id) { picked in
                if let i = note.blocks.firstIndex(where: { $0.id == t.id }) { note.blocks[i].refId = picked.id.uuidString }
            }
        }
    }

    private var pageList: some View {
        List {
            header
                .buttonStyle(.borderless)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
            if note.isDatabase {
                DatabaseView(db: note, open: { openPage = $0 })
                    .buttonStyle(.borderless)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
            } else {
                let hidden = hiddenBlocks
                let zoomed = zoomSet
                if zoomRoot != nil {
                    Button { withAnimation(DS.spring) { zoomRoot = nil } } label: { Label("Back to the whole page", systemImage: "arrow.up.left") }
                        .font(DS.Font.caption).buttonStyle(.borderless).listRowSeparator(.hidden)
                }
                ForEach($note.blocks) { $b in
                    if !hidden.contains(b.id) && (zoomed == nil || zoomed!.contains(b.id)) { row($b) }      // folded or zoomed out
                }
                    .onMove { note.blocks.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { note.blocks.remove(atOffsets: $0) }
                Button { appendBlock(.text) } label: {
                    Label("Add a block", systemImage: "plus").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                footer
                    .buttonStyle(.borderless)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .frame(maxWidth: PageLook.maxWidth(pageWidth))
        .frame(maxWidth: .infinity)
        .environment(\.editMode, .constant(reordering ? .active : .inactive))
        .scrollDismissesKeyboard(.interactively)
        .environment(\.openURL, OpenURLAction { url in
            if let id = RichText.pageId(from: url), let target = allNotes.first(where: { $0.id == id }) {
                openPage = target
                return .handled
            }
            if url.scheme == "com.keel.app", url.host == "person", let id = url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:)),
               let p = people.first(where: { $0.id == id }) {
                personSheet = p
                return .handled
            }
            if let link = BlockLinks.parse(url) {
                let (nid, bid) = link
                if nid == note.id { scrollTarget = bid } else if let target = allNotes.first(where: { $0.id == nid }) { openAt = bid; openPage = target }
                return .handled
            }
            return .systemAction
        })
        .navigationDestination(item: $openPage) { NoteEditor(note: $0, focusBlock: openAt) }
        .task {
            supertagDefs = Supertags.all(ctx)
            if let focusBlock { try? await Task.sleep(for: .milliseconds(350)); scrollTarget = focusBlock }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .onChange(of: note.blocks) { note.updatedAt = Date() }
        .onChange(of: note.title) { note.updatedAt = Date() }
        .onChange(of: photoItem) { _, item in Task { await insertPhoto(item) } }
        .onChange(of: coverItem) { _, item in
            Task {
                if let d = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                    note.cover = img.jpegData(compressionQuality: 0.75)
                }
                coverItem = nil
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .sheet(isPresented: $showSketch) {
            SketchSheet { data in
                // Handwriting is read on the device so search finds it.
                Task {
                    var text = ""
                    if let img = UIImage(data: data) { text = await NoteMedia.recognizeText(img) }
                    NoteMedia.add(data, kind: "sketch", to: note, ctx: ctx, text: text)
                }
            }
        }
        .sheet(isPresented: $showIcons) { IconPicker(icon: $note.icon) }
        .sheet(isPresented: $movingPage) { MovePageSheet(note: note) }
        .sheet(isPresented: $recording) {
            NavigationStack {
                MeetingRecorderView(target: note)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { recording = false } } }
            }
        }
        .sheet(item: Binding(get: { exportURL.map(ExportFile.init) }, set: { if $0 == nil { exportURL = nil } })) { f in
            ShareSheet(url: f.url).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $asking) { askSheet }
        #if !targetEnvironment(macCatalyst)
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScanner { pages in
                Task {
                    scanning = true
                    for p in pages {
                        let text = await NoteMedia.recognizeText(p)
                        if let jpg = NoteMedia.jpeg(p) { NoteMedia.add(jpg, kind: "scan", to: note, ctx: ctx, text: text) }
                    }
                    scanning = false
                }
            }
            .ignoresSafeArea()
        }
        #endif
        .overlay { if scanning || aiWorking { ProgressView(scanning ? "Reading the scan…" : "Thinking…").padding().background(.regularMaterial, in: .rect(cornerRadius: 12)) } }
    }

    private var parent: Note? { note.parentId.flatMap { pid in allNotes.first { $0.id == pid } } }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            if let data = note.cover, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill().frame(height: 150).frame(maxWidth: .infinity).clipped()
                    .overlay(alignment: .bottomTrailing) {
                        Menu {
                            PhotosPicker(selection: $coverItem, matching: .images) { Label("Change cover", systemImage: "photo") }
                            Button("Remove cover", systemImage: "trash", role: .destructive) { note.cover = nil }
                        } label: { Image(systemName: "photo").padding(8).background(.ultraThinMaterial, in: Circle()) }.accessibilityLabel("Change cover")
                        .padding(8)
                    }
            }
            VStack(alignment: .leading, spacing: 6) {
                if let p = parent {
                    Button { openPage = p } label: {
                        Label(p.title.isEmpty ? "Untitled" : p.title, systemImage: "chevron.left").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                    .buttonStyle(.plain)
                }
                if let icon = note.icon {
                    Button { showIcons = true } label: { Text(icon).font(.system(size: 52)) }.buttonStyle(.plain)
                }
                HStack(spacing: DS.Space.m) {
                    if note.icon == nil {
                        Button { showIcons = true } label: { Label("Add icon", systemImage: "face.smiling") }
                    }
                    if note.cover == nil {
                        PhotosPicker(selection: $coverItem, matching: .images) { Label("Add cover", systemImage: "photo") }
                    }
                }
                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).buttonStyle(.plain)
                TextField("Untitled", text: $note.title, axis: .vertical).font(DS.Font.hero)
                if let db = parent, db.isDatabase {
                    DatabaseRowProperties(row: note, db: db).padding(.top, 4)
                    Divider()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, note.cover == nil ? 8 : 0)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            let children = allNotes.filter { $0.parentId == note.id && !$0.isTemplate }
                .filter { child in !note.blocks.contains { $0.kind == .page && $0.refId == child.id.uuidString } }
                .sorted { $0.sortIndex < $1.sortIndex }
            if !children.isEmpty {
                Text("PAGES INSIDE").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).padding(.top, DS.Space.m)
                ForEach(children) { c in
                    Button { openPage = c } label: { Label(c.title.isEmpty ? "Untitled" : c.title, systemImage: "doc.text") }
                        .buttonStyle(.plain)
                }
            }
            PageStats(note: note).padding(.top, DS.Space.s)
            NoteLinksSection(note: note)
            RelatedSection(note: note, allNotes: allNotes, open: { openPage = $0 })
            ConnectedStrip(key: "note:" + note.id.uuidString).padding(.top, DS.Space.s)
        }
    }

    // MARK: Blocks

    @ViewBuilder
    private func row(_ b: Binding<NoteBlock>) -> some View {
        let blk = b.wrappedValue
        let colors = BlockColor.parse(blk.color)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if blk.kind != .toggle && hasChildren(blk) {
                    Button { withAnimation(DS.spring) { b.wrappedValue.collapsed = !(blk.collapsed ?? false) } } label: {
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(DS.Palette.inkSoft)
                            .rotationEffect(.degrees((blk.collapsed ?? false) ? 0 : 90))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel((blk.collapsed ?? false) ? "Unfold" : "Fold")
                }
                prefix(b)
                content(b)
            }
            .padding(.leading, CGFloat(min(blk.indent ?? 0, 8)) * 24)
            .foregroundStyle(colors.text ?? DS.Palette.ink)
            .padding(.vertical, blk.kind == .callout || colors.background != nil ? 8 : 2)
            .padding(.top, [.heading, .heading2, .heading3].contains(blk.kind) && note.blocks.first?.id != blk.id ? (blk.kind == .heading ? 14 : 8) : 0)   // room above headings
            .padding(.horizontal, blk.kind == .callout || colors.background != nil ? 10 : 0)
            .background(blk.kind == .callout ? (colors.background ?? DS.Palette.elevated) : (colors.background ?? .clear), in: .rect(cornerRadius: 8))
            let n = NoteComments.open(note, block: blk.id)
            if n > 0 {
                Button { commentTarget = CommentTarget(blockId: blk.id) } label: {
                    Label("\(n) comment\(n == 1 ? "" : "s")", systemImage: "text.bubble.fill").font(.caption2)
                }
                .buttonStyle(.plain).foregroundStyle(.orange)
                .padding(.leading, CGFloat(min(blk.indent ?? 0, 8)) * 24)
            }
            if !supertagDefs.isEmpty && blk.text.contains("#") {
                SupertagChips(note: note, block: blk, defs: supertagDefs)
                    .padding(.leading, CGFloat(min(blk.indent ?? 0, 8)) * 24 + 4)
            }
            if slashFor == blk.id { slashMenu(b) }
            if mentionFor == blk.id { mentionMenu(b) }
        }
        .buttonStyle(.borderless)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
        .contextMenu { blockMenu(b) }
    }

    @ViewBuilder
    private func prefix(_ b: Binding<NoteBlock>) -> some View {
        switch b.wrappedValue.kind {
        case .todo: CompletionCheck(isDone: b.checked)
        case .bullet: Text(["•", "◦", "▪︎"][(b.wrappedValue.indent ?? 0) % 3]).font(DS.Font.body)
        case .numbered: Text(numberLabel(for: b.wrappedValue)).font(DS.Font.body).monospacedDigit()
        case .toggle:
            Button { withAnimation(DS.spring) { b.wrappedValue.collapsed = !(b.wrappedValue.collapsed ?? false) } } label: {
                Image(systemName: "chevron.right").rotationEffect(.degrees((b.wrappedValue.collapsed ?? false) ? 0 : 90))
            }
            .buttonStyle(.plain)
        case .callout:
            Text(b.wrappedValue.icon ?? "💡")
        case .quote:
            Rectangle().fill(DS.Palette.ink).frame(width: 3, height: 22)
        default: EmptyView()
        }
    }

    @ViewBuilder
    private func content(_ b: Binding<NoteBlock>) -> some View {
        let blk = b.wrappedValue
        switch blk.kind {
        case .divider:
            Divider().frame(maxWidth: .infinity).padding(.vertical, 6)
        case .image:
            if blk.refId == nil {
                Button { imageTarget = blk.id; showPhotoPicker = true } label: { Label("Choose an image", systemImage: "photo.badge.plus") }
            } else {
                ImageBlockView(attachmentId: blk.refId)
            }
        case .table:
            TableBlockView(rows: b.rows)
        case .page:
            let target = blk.refId.flatMap(UUID.init(uuidString:)).flatMap { id in allNotes.first { $0.id == id } }
            Button { if let target { openPage = target } } label: {
                HStack {
                    Text(target?.icon ?? "📄")
                    Text(target.map { $0.title.isEmpty ? "Untitled" : $0.title } ?? "Missing page").underline()
                }
            }
            .buttonStyle(.plain)
        case .bookmark:
            if let s = blk.refId, let url = URL(string: s) {
                Link(destination: url) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(blk.text.isEmpty ? (url.host() ?? s) : blk.text).font(DS.Font.headline).lineLimit(2)
                        Text(url.host() ?? s).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                }
            } else {
                TextField("Paste a link and press return", text: b.text)
                    .keyboardType(.URL).textInputAutocapitalization(.never)
                    .onSubmit {
                        let raw = b.wrappedValue.text.trimmingCharacters(in: .whitespaces)
                        let url = raw.hasPrefix("http") ? raw : "https://" + raw
                        b.wrappedValue.refId = url
                        b.wrappedValue.text = ""
                    }
            }
        case .code where SpecialBlock.kind(blk) != nil:
            specialBlock(b)
        case .code:
            VStack(alignment: .leading, spacing: 4) {
                TextField("Code", text: b.text, axis: .vertical)
                    .font(.system(.callout, design: .monospaced))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focused, equals: blk.id)
                TextField("language", text: Binding(get: { blk.lang ?? "" }, set: { b.wrappedValue.lang = $0 }))
                    .font(.caption2).foregroundStyle(DS.Palette.inkSoft).textInputAutocapitalization(.never)
            }
            .padding(10)
            .background(DS.Palette.elevated, in: .rect(cornerRadius: 8))
        case .toggle:
            VStack(alignment: .leading, spacing: 4) {
                editableText(b, font: DS.Font.body)
                if !(blk.collapsed ?? false) && (blk.body != nil || !hasChildren(blk)) {
                    TextField("Empty toggle. Write inside it.", text: Binding(get: { blk.body ?? "" }, set: { b.wrappedValue.body = $0 }), axis: .vertical)
                        .font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
                }
            }
        case .heading: editableText(b, font: .system(.title, design: .default).weight(.bold))
        case .heading2: editableText(b, font: .system(.title2).weight(.semibold))
        case .heading3: editableText(b, font: .system(.title3).weight(.semibold))
        case .quote: editableText(b, font: DS.Font.body.italic())
        case .todo:
            editableText(b, font: DS.Font.body)
                .strikethrough(blk.checked)
                .opacity(blk.checked ? 0.5 : 1)
        default:
            editableText(b, font: DS.Font.body)
        }
    }

    /// Embeds, linked databases, table of contents, equations and diagrams.
    @ViewBuilder
    private func specialBlock(_ b: Binding<NoteBlock>) -> some View {
        let blk = b.wrappedValue
        switch SpecialBlock.kind(blk) ?? "" {
        case SpecialBlock.embed:
            EmbeddedPageView(pageId: blk.refId, allNotes: allNotes, open: { openPage = $0 },
                             choose: { pickBlock = BlockPickTarget(id: blk.id, databasesOnly: false) })
        case SpecialBlock.dbview:
            if let id = blk.refId.flatMap(UUID.init(uuidString:)), let db = allNotes.first(where: { $0.id == id && $0.isDatabase }) {
                VStack(alignment: .leading, spacing: 4) {
                    Button { openPage = db } label: { Label(db.title.isEmpty ? "Untitled database" : db.title, systemImage: "tablecells") .font(DS.Font.headline) }
                        .buttonStyle(.plain)
                    DatabaseView(db: db, open: { openPage = $0 })
                }
            } else {
                Button { pickBlock = BlockPickTarget(id: blk.id, databasesOnly: true) } label: { Label("Choose a database to show here", systemImage: "tablecells.badge.ellipsis") }
            }
        case SpecialBlock.columns: ColumnsBlockView(block: b)
        case SpecialBlock.button: ButtonBlockView(block: b)
        case SpecialBlock.progress: ProgressBlockView(note: note)
        case SpecialBlock.chart: ChartBlockView(dbId: blk.refId) { pickBlock = BlockPickTarget(id: blk.id, databasesOnly: true) }
        case SpecialBlock.file: FileBlockView(attachmentId: blk.refId)
        case SpecialBlock.aiblock:
            AIBlockView(block: b, pageTitle: note.title, pageText: note.plainText)
        case "keel-audio":
            AudioBlockView(attachmentId: blk.refId)
        case "keel-pdf":
            PDFBlockView(attachmentId: blk.refId, note: note)
        case SpecialBlock.blockref:
            BlockRefView(ref: blk.refId, allNotes: allNotes) { n, bid in
                if n.id == note.id { scrollTarget = bid } else { openAt = bid; openPage = n }
            }
        case SpecialBlock.toc:
            TableOfContentsView(note: note) { scrollTarget = $0 }
        case SpecialBlock.math:
            RenderedSourceBlock(block: b, mode: .math)
        case SpecialBlock.mermaid:
            RenderedSourceBlock(block: b, mode: .mermaid)
        default:
            Text(blk.text).font(.system(.callout, design: .monospaced))
        }
    }

    /// Rendered rich text until you tap it; then the raw text for editing.
    @ViewBuilder
    private func editableText(_ b: Binding<NoteBlock>, font: Font) -> some View {
        let blk = b.wrappedValue
        if editing == blk.id {
            TextField(placeholder(blk.kind), text: b.text, selection: $selection, axis: .vertical)
                .font(font)
                .focused($focused, equals: blk.id)
                .onChange(of: blk.text) { old, new in handleTyping(b, old: old, new: new) }
                .onAppear { focused = blk.id }
        } else {
            Group {
                if blk.text.isEmpty {
                    Text(note.blocks.count == 1 ? "Start writing, or type / for blocks" : " ").foregroundStyle(DS.Palette.inkSoft.opacity(0.6))
                } else {
                    Text(RichText.render(blk.text))
                }
            }
            .font(font)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { beginEdit(blk.id) })
        }
    }

    private func placeholder(_ kind: BlockKind) -> String {
        switch kind {
        case .heading, .heading2, .heading3: "Heading"
        case .todo: "To-do"
        case .bullet, .numbered: "List"
        case .quote: "Quote"
        case .callout: "Callout"
        case .toggle: "Toggle"
        default: "Type / for blocks, @ to mention"
        }
    }

    /// Position in its list at its own level; deeper items in between don't break the count.
    private func number(for id: UUID) -> Int {
        guard let i = note.blocks.firstIndex(where: { $0.id == id }) else { return 1 }
        let level = note.blocks[i].indent ?? 0
        var n = 1, j = i - 1
        while j >= 0 {
            let b = note.blocks[j], l = b.indent ?? 0
            if l > level { j -= 1; continue }
            guard l == level, b.kind == .numbered else { break }
            n += 1; j -= 1
        }
        return n
    }

    /// 1. 2. 3. at the top level, then a. b. c., then i. ii. iii., like the apps you import from.
    private func numberLabel(for b: NoteBlock) -> String {
        let n = number(for: b.id)
        switch (b.indent ?? 0) % 3 {
        case 1:
            var s = "", x = n
            repeat { x -= 1; s = String(UnicodeScalar(97 + x % 26)!) + s; x /= 26 } while x > 0
            return s + "."
        case 2:
            let numerals = [(10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")]
            var x = n, s = ""
            for (v, r) in numerals { while x >= v { s += r; x -= v } }
            return s + "."
        default: return "\(n)."
        }
    }

    /// Blocks hidden inside closed toggles (anything indented deeper right after one).
    private var hiddenBlocks: Set<UUID> {
        var hidden = Set<UUID>()
        var closedAt: Int?
        for b in note.blocks {
            let l = b.indent ?? 0
            if let c = closedAt {
                if l > c { hidden.insert(b.id); continue }
                closedAt = nil
            }
            if (b.collapsed ?? false) { closedAt = l }          // toggles, and any folded line in the outliner
        }
        return hidden
    }

    private func hasChildren(_ b: NoteBlock) -> Bool {
        guard let i = note.blocks.firstIndex(where: { $0.id == b.id }), i + 1 < note.blocks.count else { return false }
        return (note.blocks[i + 1].indent ?? 0) > (b.indent ?? 0)
    }

    private func setIndent(_ i: Int, by delta: Int) {
        let current = note.blocks[i].indent ?? 0
        // Can't indent deeper than one level under the block above.
        let maxLevel = i > 0 ? (note.blocks[i - 1].indent ?? 0) + 1 : 0
        let next = max(0, min(maxLevel, current + delta))
        note.blocks[i].indent = next == 0 ? nil : next
        Haptics.tap()
    }

    private func beginEdit(_ id: UUID) {
        editing = id
        slashFor = nil; mentionFor = nil
        Task { @MainActor in focused = id }
    }

    // MARK: Typing: shortcuts, "/", "@" and Return

    private func handleTyping(_ b: Binding<NoteBlock>, old: String, new: String) {
        let id = b.wrappedValue.id
        // A paste with several lines: turn it into proper blocks (headings, lists, tables, links) instead of one long line.
        if new.count - old.count > 1, b.wrappedValue.kind != .code {
            let prefix = new.commonPrefix(with: old)
            let suffixLen = zip(old.reversed(), new.reversed()).prefix { $0 == $1 }.count
            let start = new.index(new.startIndex, offsetBy: prefix.count)
            let end = new.index(new.endIndex, offsetBy: -min(suffixLen, new.count - prefix.count))
            let inserted = start <= end ? String(new[start..<end]) : ""
            if inserted.contains("\n") {
                pasteBlocks(SmartPaste.blocks(from: inserted), into: b, keeping: prefix + String(old.suffix(suffixLen)))
                return
            }
        }
        // Return → next block (lists continue; an empty list item ends the list).
        if new.contains("\n") {
            let parts = new.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            let before = String(parts.first ?? ""), after = parts.count > 1 ? String(parts[1]) : ""
            let kind = b.wrappedValue.kind
            if before.isEmpty && [.bullet, .todo, .numbered].contains(kind) {
                if let level = b.wrappedValue.indent, level > 0 {
                    b.wrappedValue.indent = level == 1 ? nil : level - 1
                    b.wrappedValue.text = after
                    return
                }
                b.wrappedValue.kind = .text
                b.wrappedValue.text = after
                return
            }
            b.wrappedValue.text = before
            // "remind me to call mom friday 5pm" → a real reminder, linked back to this page.
            if let task = NoteReminders.capture(before, in: note, ctx: ctx) {
                b.wrappedValue.text = "⏰ \(task.title)" + (task.dueDate.map { " · " + $0.formatted(date: .abbreviated, time: task.hasDueTime ? .shortened : .omitted) } ?? "")
                UndoCenter.shared.notify("Reminder set: \(task.title)")
            }
            let next: BlockKind = [.bullet, .todo, .numbered].contains(kind) ? kind : .text
            // Inside a toggle, the next line goes inside it too.
            let level = kind == .toggle ? (b.wrappedValue.indent ?? 0) + 1 : b.wrappedValue.indent
            insertBlock(after: id, kind: next, text: after, indent: level)
            return
        }
        // Space on an empty line: Ask AI (like Notion). Turn off in Settings → AI & Privacy.
        if old.isEmpty, new == " ", b.wrappedValue.kind == .text, !note.isLocked,
           UserDefaults.standard.object(forKey: AIWriter.spaceKey) as? Bool ?? true {
            b.wrappedValue.text = ""
            aiWrite = AIWriteRequest(mode: .ask, blockId: id)
            return
        }
        // Markdown shortcuts at the start of a block.
        if b.wrappedValue.kind == .text {
            let shortcuts: [(String, BlockKind)] = [("- ", .bullet), ("* ", .bullet), ("[] ", .todo), ("[ ] ", .todo), ("1. ", .numbered),
                                                    ("### ", .heading3), ("## ", .heading2), ("# ", .heading), ("> ", .quote), ("``` ", .code), ("---", .divider)]
            for (s, kind) in shortcuts where new.hasPrefix(s) && !old.hasPrefix(s) {
                b.wrappedValue.kind = kind
                b.wrappedValue.text = String(new.dropFirst(s.count))
                if kind == .divider { insertBlock(after: id, kind: .text, text: "") }
                return
            }
        }
        // "/" menu
        if new.hasPrefix("/") { slashFor = id; slashQuery = String(new.dropFirst()) } else if slashFor == id { slashFor = nil }
        // "@" mentions: the word being typed starts with @
        if let at = new.lastIndex(of: "@") {
            let word = new[new.index(after: at)...]
            let startsWord = at == new.startIndex || new[new.index(before: at)] == " "
            if startsWord && !word.contains(" ") && word.count <= 24 { mentionFor = id; mentionQuery = String(word) }
            else if mentionFor == id { mentionFor = nil }
        } else if mentionFor == id { mentionFor = nil }
    }

    /// Puts pasted blocks in place of (or after) the block you were typing in.
    private func pasteBlocks(_ pasted: [NoteBlock], into b: Binding<NoteBlock>, keeping: String) {
        guard !pasted.isEmpty, let i = note.blocks.firstIndex(where: { $0.id == b.wrappedValue.id }) else { return }
        let kept = keeping.trimmingCharacters(in: .whitespaces)
        var list = pasted
        if kept.isEmpty {
            list[0].id = note.blocks[i].id
            note.blocks[i] = list[0]
            note.blocks.insert(contentsOf: list.dropFirst(), at: i + 1)
        } else {
            note.blocks[i].text = kept
            note.blocks.insert(contentsOf: list, at: i + 1)
        }
        editing = nil; focused = nil
        UndoCenter.shared.notify("Pasted \(pasted.count) block\(pasted.count == 1 ? "" : "s")")
        Haptics.tap()
    }

    private func pasteFromClipboard() {
        let pasted = SmartPaste.fromPasteboard()
        guard !pasted.isEmpty else { UndoCenter.shared.notify("Nothing to paste"); return }
        if let id = focused ?? editing, let i = note.blocks.firstIndex(where: { $0.id == id }) {
            if note.blocks[i].text.isEmpty && note.blocks[i].kind == .text {
                var list = pasted; list[0].id = note.blocks[i].id
                note.blocks[i] = list[0]; note.blocks.insert(contentsOf: list.dropFirst(), at: i + 1)
            } else {
                note.blocks.insert(contentsOf: pasted, at: i + 1)
            }
        } else {
            if let last = note.blocks.last, last.kind == .text, last.text.isEmpty { note.blocks.removeLast() }
            note.blocks += pasted
        }
        editing = nil; focused = nil
        UndoCenter.shared.notify("Pasted \(pasted.count) block\(pasted.count == 1 ? "" : "s")")
        Haptics.tap()
    }

    private func insertBlock(after id: UUID, kind: BlockKind, text: String, indent: Int? = nil) {
        var nb = NoteBlock(kind: kind, text: text)
        nb.indent = (indent ?? 0) > 0 ? indent : nil
        if let i = note.blocks.firstIndex(where: { $0.id == id }) { note.blocks.insert(nb, at: i + 1) } else { note.blocks.append(nb) }
        beginEdit(nb.id)
    }

    private func appendBlock(_ kind: BlockKind) {
        if let last = note.blocks.last, last.kind == .text, last.text.isEmpty { beginEdit(last.id); return }
        let nb = NoteBlock(kind: kind, text: "")
        note.blocks.append(nb)
        beginEdit(nb.id)
    }

    private func slashMenu(_ b: Binding<NoteBlock>) -> some View {
        let matches = SlashCommand.matching(slashQuery)
        return VStack(alignment: .leading, spacing: 0) {
            if matches.isEmpty { Text("No blocks match “\(slashQuery)”").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).padding(8) }
            ForEach(matches.prefix(8)) { cmd in
                Button { apply(cmd, to: b) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: cmd.icon).frame(width: 28, height: 28).background(DS.Palette.elevated, in: .rect(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(cmd.title).font(DS.Font.body)
                            Text(cmd.subtitle).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 5).padding(.horizontal, 8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))
    }

    private func apply(_ cmd: SlashCommand, to b: Binding<NoteBlock>) {
        slashFor = nil
        b.wrappedValue.text = ""
        if cmd.id == "ai" {                        // Ask AI: the answer is written right here
            editing = nil
            aiWrite = AIWriteRequest(mode: .ask, blockId: b.wrappedValue.id)
            return
        }
        if cmd.id == "aiblock" {
            b.wrappedValue.kind = .code
            b.wrappedValue.lang = SpecialBlock.aiblock
            editing = nil
            insertBlock(after: b.wrappedValue.id, kind: .text, text: "")
            Haptics.tap()
            return
        }
        if cmd.id == "meeting" {                   // AI meeting notes go straight into this page
            editing = nil
            recording = true
            return
        }
        if let lang = SpecialBlock.lang(for: cmd.id) {
            b.wrappedValue.kind = .code
            b.wrappedValue.lang = lang
            editing = nil
            if cmd.id == "embed" || cmd.id == "dbview" { pickBlock = BlockPickTarget(id: b.wrappedValue.id, databasesOnly: cmd.id == "dbview") }
            if cmd.id == "toc" { insertBlock(after: b.wrappedValue.id, kind: .text, text: "") }
            if cmd.id == "blockref" { b.wrappedValue.refId = BlockLinks.clipboard }
            if cmd.id == "chart" { pickBlock = BlockPickTarget(id: b.wrappedValue.id, databasesOnly: true) }
            if cmd.id == "columns" { b.wrappedValue.text = "\n|||\n" }
            if cmd.id == "button" { b.wrappedValue.text = "Add a task | task: " }
            if cmd.id == "file" { fileTarget = b.wrappedValue.id; importingFile = true }
            Haptics.tap()
            return
        }
        switch cmd.kind {
        case .page:
            let sub = Note(title: "")
            sub.parentId = note.id
            sub.sortIndex = Date().timeIntervalSince1970
            ctx.insert(sub)
            b.wrappedValue.kind = .page
            b.wrappedValue.refId = sub.id.uuidString
            editing = nil
            openPage = sub
        case .image:
            b.wrappedValue.kind = .image
            imageTarget = b.wrappedValue.id
            editing = nil
            showPhotoPicker = true
        case .table:
            b.wrappedValue.kind = .table
            b.wrappedValue.rows = [["Column 1", "Column 2", "Column 3"], ["", "", ""], ["", "", ""]]
            editing = nil
        case .divider:
            b.wrappedValue.kind = .divider
            insertBlock(after: b.wrappedValue.id, kind: .text, text: "")
        case .callout:
            b.wrappedValue.kind = .callout
            if b.wrappedValue.icon == nil { b.wrappedValue.icon = "💡" }
        case .toggle:
            b.wrappedValue.kind = .toggle
            b.wrappedValue.collapsed = false
        case .bookmark:
            b.wrappedValue.kind = .bookmark
            editing = nil
        default:
            b.wrappedValue.kind = cmd.kind
        }
        Haptics.tap()
    }

    private func mentionMenu(_ b: Binding<NoteBlock>) -> some View {
        let q = mentionQuery.lowercased()
        let pages = allNotes.filter { $0.id != note.id && !$0.isTemplate && !$0.title.isEmpty && (q.isEmpty || $0.title.lowercased().contains(q)) }
            .sorted { $0.updatedAt > $1.updatedAt }.prefix(5)
        let persons = people.filter { q.isEmpty || $0.name.lowercased().contains(q) }.prefix(3)
        let cal = Calendar.current
        let dates: [(String, Date)] = [("Today", Date()), ("Tomorrow", cal.date(byAdding: .day, value: 1, to: Date())!),
                                       ("Next week", cal.date(byAdding: .day, value: 7, to: Date())!)]
            .filter { q.isEmpty || $0.0.lowercased().hasPrefix(q) }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(pages)) { p in
                mentionRow(p.icon ?? "📄", p.title) { finishMention(b, with: "[\(p.title)](\(RichText.pageURL(p.id)))") }
            }
            ForEach(Array(persons)) { p in
                mentionRow("👤", p.name) { finishMention(b, with: "[@\(p.name)](com.keel.app://person/\(p.id.uuidString))") }
            }
            ForEach(dates, id: \.0) { d in
                mentionRow("📅", "\(d.0) · \(d.1.formatted(date: .abbreviated, time: .omitted))") {
                    finishMention(b, with: "**\(d.1.formatted(date: .abbreviated, time: .omitted))**")
                }
            }
            if !q.isEmpty {
                mentionRow("➕", "New page “\(mentionQuery)”") {
                    let p = Note(title: mentionQuery); p.parentId = note.id; ctx.insert(p)
                    finishMention(b, with: "[\(p.title)](\(RichText.pageURL(p.id)))")
                }
            }
        }
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))
    }

    private func mentionRow(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(icon); Text(title).lineLimit(1); Spacer() }.padding(.vertical, 6).padding(.horizontal, 10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func finishMention(_ b: Binding<NoteBlock>, with insertion: String) {
        var t = b.wrappedValue.text
        if let at = t.lastIndex(of: "@") { t.replaceSubrange(at..., with: insertion + " ") }
        b.wrappedValue.text = t
        mentionFor = nil
        Haptics.tap()
    }

    @ViewBuilder
    private func blockMenu(_ b: Binding<NoteBlock>) -> some View {
        Menu("Turn into", systemImage: "arrow.triangle.2.circlepath") {
            ForEach(SlashCommand.all.filter { ![.page, .image, .table, .bookmark, .divider].contains($0.kind) && $0.id != "meeting" && $0.id != "ai" && !SpecialBlock.commandIds.contains($0.id) }) { cmd in
                Button(cmd.title, systemImage: cmd.icon) { b.wrappedValue.kind = cmd.kind; if cmd.kind == .code && SpecialBlock.kind(b.wrappedValue) != nil { b.wrappedValue.lang = nil }; if cmd.kind == .callout && b.wrappedValue.icon == nil { b.wrappedValue.icon = "💡" } }
            }
        }
        Menu("Color", systemImage: "paintpalette") {
            Button("Default") { b.wrappedValue.color = nil }
            ForEach(BlockColor.allCases, id: \.self) { c in Button(c.rawValue.capitalized) { b.wrappedValue.color = c.rawValue } }
            Divider()
            ForEach(BlockColor.allCases, id: \.self) { c in Button("\(c.rawValue.capitalized) background") { b.wrappedValue.color = "bg:" + c.rawValue } }
        }
        if b.wrappedValue.kind == .callout {
            Menu("Callout icon", systemImage: "face.smiling") {
                ForEach(["💡", "⚠️", "✅", "❗", "📌", "🔥", "🧠", "❤️"], id: \.self) { e in Button(e) { b.wrappedValue.icon = e } }
            }
        }
        Button("Comment", systemImage: "text.bubble") { commentTarget = CommentTarget(blockId: b.wrappedValue.id) }
        Menu("Link to this line", systemImage: "link") {
            Button("Copy line link", systemImage: "link") {
                let t = RichText.plain(b.wrappedValue.text)
                UIPasteboard.general.string = "[\(t.isEmpty ? "line" : String(t.prefix(60)))](\(BlockLinks.url(note: note.id, block: b.wrappedValue.id)))"
                UndoCenter.shared.notify("Line link copied. Paste it anywhere.")
            }
            Button("Copy line embed", systemImage: "text.quote") {
                BlockLinks.clipboard = "\(note.id.uuidString)/\(b.wrappedValue.id.uuidString)"
                UndoCenter.shared.notify("Copied. Type /line embed on any page.")
            }
        }
        if hasChildren(b.wrappedValue) || zoomRoot != nil {
            Button(zoomRoot == b.wrappedValue.id ? "Zoom out" : "Zoom in", systemImage: "arrow.up.left.and.arrow.down.right") {
                withAnimation(DS.spring) { zoomRoot = zoomRoot == b.wrappedValue.id ? nil : b.wrappedValue.id }
            }
        }
        Button("Make it a task", systemImage: "checklist") {
            let title = b.wrappedValue.text.replacingOccurrences(of: #"[*_=`]"#, with: "", options: .regularExpression)
            guard !title.isEmpty else { return }
            let t = QuickAdd.create(title, in: ctx); t.sourceNoteId = note.id
            UndoCenter.shared.notify("Added “\(t.title)” to Tasks")
        }
        Menu("Edit with AI", systemImage: "sparkles") {
            ForEach(AIAction.edits) { a in
                Button(a.title, systemImage: a.icon) { aiWrite = AIWriteRequest(mode: .edit, blockId: b.wrappedValue.id, source: b.wrappedValue.text, preset: a) }
            }
            Button("Tell AI what to change…", systemImage: "text.cursor") { aiWrite = AIWriteRequest(mode: .edit, blockId: b.wrappedValue.id, source: b.wrappedValue.text) }
        }
        .disabled(b.wrappedValue.text.isEmpty || note.isLocked)
        Button("Quick improve", systemImage: "wand.and.stars") {
            let original = b.wrappedValue.text
            Task {
                aiWorking = true
                if let better = await AIRouter.shared.write("Rewrite this to be clearer and more concise. Keep the meaning and any markdown. Reply with only the rewritten text.\n\(original)") {
                    b.wrappedValue.text = better.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                aiWorking = false
            }
        }
        .disabled(b.wrappedValue.text.isEmpty || note.isLocked)
        Divider()
        Button("Duplicate", systemImage: "plus.square.on.square") {
            var copy = b.wrappedValue; copy.id = UUID()
            if let i = note.blocks.firstIndex(where: { $0.id == b.wrappedValue.id }) { note.blocks.insert(copy, at: i + 1) }
        }
        Button("Move up", systemImage: "arrow.up") { move(b.wrappedValue.id, by: -1) }
        Button("Move down", systemImage: "arrow.down") { move(b.wrappedValue.id, by: 1) }
        Button("Delete", systemImage: "trash", role: .destructive) {
            let id = b.wrappedValue.id
            note.blocks.removeAll { $0.id == id }
        }
    }

    /// Moves a line with everything under it (outliner-style), past the neighbouring branch at the same level.
    private func move(_ id: UUID, by delta: Int) {
        guard let i = note.blocks.firstIndex(where: { $0.id == id }) else { return }
        let level = note.blocks[i].indent ?? 0
        func branchEnd(_ start: Int) -> Int {
            let l = note.blocks[start].indent ?? 0
            var e = start + 1
            while e < note.blocks.count, (note.blocks[e].indent ?? 0) > l { e += 1 }
            return e
        }
        let end = branchEnd(i)
        let branch = Array(note.blocks[i..<end])
        if delta < 0 {
            var p = i - 1
            while p >= 0, (note.blocks[p].indent ?? 0) > level { p -= 1 }
            guard p >= 0 else { return }
            note.blocks.removeSubrange(i..<end)
            note.blocks.insert(contentsOf: branch, at: p)
        } else {
            guard end < note.blocks.count else { return }
            let nextEnd = branchEnd(end)
            note.blocks.removeSubrange(i..<end)
            note.blocks.insert(contentsOf: branch, at: nextEnd - branch.count)
        }
        Haptics.tap()
    }

    /// The zoomed line and everything under it.
    private var zoomSet: Set<UUID>? {
        guard let root = zoomRoot, let i = note.blocks.firstIndex(where: { $0.id == root }) else { return nil }
        let l = note.blocks[i].indent ?? 0
        var ids: Set<UUID> = [root]
        var j = i + 1
        while j < note.blocks.count, (note.blocks[j].indent ?? 0) > l { ids.insert(note.blocks[j].id); j += 1 }
        return ids
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { note.isPinned.toggle(); Haptics.tap() } label: { Image(systemName: note.isPinned ? "star.fill" : "star") }
                .accessibilityLabel(note.isPinned ? "Remove from favorites" : "Add to favorites")
            Menu {
                Button("Photo", systemImage: "photo") { imageTarget = nil; showPhotoPicker = true }
                Button("Sketch", systemImage: "pencil.tip") { showSketch = true }
                #if !targetEnvironment(macCatalyst)
                if VNDocumentCameraViewController.isSupported {
                    Button("Scan document", systemImage: "doc.viewfinder") { showScanner = true }
                }
                #endif
                Button("AI meeting notes", systemImage: "waveform.badge.mic") { recording = true }
                Button("PDF to read and highlight", systemImage: "doc.richtext") { importingPDF = true }
                Button("Paste with formatting", systemImage: "doc.on.clipboard") { pasteFromClipboard() }
                Divider()
                Button("Sub-page", systemImage: "doc.badge.plus") {
                    let nb = NoteBlock(kind: .text, text: "")
                    note.blocks.append(nb)
                    if let last = $note.blocks.last { apply(SlashCommand.all.first { $0.kind == .page }!, to: last) }
                }
                Button("Database", systemImage: "tablecells.badge.ellipsis") {
                    let db = NotesDatabase.create(title: "Untitled database", parent: note, ctx: ctx)
                    note.blocks.append(NoteBlock(kind: .page, text: "", refId: db.id.uuidString))
                    openPage = db
                }
            } label: { Image(systemName: "plus.circle") }
            .accessibilityLabel("Insert")
            Menu {
                Button("Ask AI…", systemImage: "sparkles") { aiWrite = AIWriteRequest(mode: .ask, blockId: note.blocks.last?.id) }
                Menu("Page actions", systemImage: "doc.text.magnifyingglass") {
                    ForEach(AIAction.page) { a in
                        Button(a.title, systemImage: a.icon) { aiWrite = AIWriteRequest(mode: .page, blockId: note.blocks.last?.id, preset: a) }
                    }
                }
                Button("Add a live AI block", systemImage: "sparkles.rectangle.stack") {
                    var nb = NoteBlock(kind: .code, text: "")
                    nb.lang = SpecialBlock.aiblock
                    note.blocks.append(nb)
                    scrollTarget = nb.id
                }
                Divider()
                Button("Continue writing", systemImage: "text.append") { Task { await continueWriting() } }
                Button("Summarize", systemImage: "text.line.first.and.arrowtriangle.forward") { Task { await summarize() } }
                Button("Ask this page", systemImage: "questionmark.bubble") { answer = nil; question = ""; asking = true }
                Button("Turn to-dos into tasks", systemImage: "checklist") { extractTasks() }
                ForEach(Extensions.commands) { c in
                    Button(c.name, systemImage: c.icon) { Task { aiWorking = true; await Extensions.run(c, on: note); aiWorking = false } }
                }
                Button("Make flashcards", systemImage: "rectangle.on.rectangle.angled") {
                    Task { aiWorking = true; let n = await Flashcards.generate(for: note); aiWorking = false; UndoCenter.shared.notify(n == 0 ? "Couldn't make cards from this page" : "Added \(n) flashcards") }
                }
            } label: { Image(systemName: "sparkles") }.accessibilityLabel("AI tools")
            .disabled(note.isLocked)
            Menu {
                Button("Outline", systemImage: "list.bullet.indent") { showOutline = true }
                Button("Local graph", systemImage: "point.3.filled.connected.trianglepath.dotted") { showLocalGraph = true }
                Button("Focus mode", systemImage: "arrow.up.left.and.arrow.down.right") { withAnimation(DS.spring) { zen = true } }
                Picker("Page width", selection: $pageWidth) {
                    Text("Comfortable").tag("comfortable"); Text("Wide").tag("wide"); Text("Full width").tag("full")
                }
                if multiWindow {
                    Button("Open side by side", systemImage: "rectangle.split.2x1") { openWindow(id: "note", value: note.id) }
                }
                if note.isTemplate { TemplateScheduleMenu(template: note) }
                Button("Find & replace", systemImage: "magnifyingglass") { showFindReplace = true }
                Button("Comments", systemImage: "text.bubble") { commentTarget = CommentTarget(blockId: nil) }
                Button(reordering ? "Done reordering" : "Reorder blocks", systemImage: "arrow.up.arrow.down") { withAnimation { reordering.toggle() } }
                Button("Move to…", systemImage: "folder") { movingPage = true }
                Button(note.isLocked ? "Remove lock" : "Lock page", systemImage: note.isLocked ? "lock.open" : "lock") { toggleLock() }
                Button("Version history", systemImage: "clock.arrow.circlepath") { showHistory = true }
                Button(NotePublisher.url(note) == nil ? "Publish to web" : "Update web page", systemImage: "globe") {
                    Task {
                        do { publishedURL = try await NotePublisher.publish(note) } catch { publishError = error.localizedDescription }
                    }
                }
                if NotePublisher.url(note) != nil {
                    Button("Unpublish", systemImage: "eye.slash") { Task { try? await NotePublisher.unpublish(note) } }
                }
                Button("Save as template", systemImage: "doc.on.doc") {
                    let t = Note(title: note.title, blocks: note.blocks.map { var b = $0; b.id = UUID(); b.checked = false; return b })
                    t.isTemplate = true; t.icon = note.icon
                    ctx.insert(t)
                    UndoCenter.shared.notify("Saved “\(note.title)” as a template")
                }
                Divider()
                Button("Export as Markdown", systemImage: "doc.plaintext") { exportURL = NoteExport.markdownFile(note) }
                Button("Export as PDF", systemImage: "doc.richtext") { exportURL = NoteExport.pdfFile(note) }
                Divider()
                Button("Delete page", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("More")
        }
        ToolbarItemGroup(placement: .keyboard) {
            if let id = focused, let i = note.blocks.firstIndex(where: { $0.id == id }) {
                Button { RichText.wrap(&note.blocks[i].text, selection: selection, left: "**", right: "**") } label: { Image(systemName: "bold") }.accessibilityLabel("Bold")
                Button { RichText.wrap(&note.blocks[i].text, selection: selection, left: "*", right: "*") } label: { Image(systemName: "italic") }.accessibilityLabel("Italic")
                Button { RichText.wrap(&note.blocks[i].text, selection: selection, left: "==", right: "==") } label: { Image(systemName: "highlighter") }.accessibilityLabel("Highlight")
                Button { RichText.wrap(&note.blocks[i].text, selection: selection, left: "`", right: "`") } label: { Image(systemName: "chevron.left.forwardslash.chevron.right") }.accessibilityLabel("Code")
                Button { RichText.wrap(&note.blocks[i].text, selection: selection, left: "[", right: "](https://)") } label: { Image(systemName: "link") }.accessibilityLabel("Add link")
                Button { note.blocks[i].text += (note.blocks[i].text.isEmpty || note.blocks[i].text.hasSuffix(" ") ? "@" : " @") } label: { Image(systemName: "at") }.accessibilityLabel("Mention")
                Button { if note.blocks[i].text.isEmpty { note.blocks[i].text = "/" } else { insertBlock(after: id, kind: .text, text: "/") } } label: { Image(systemName: "plus.square") }.accessibilityLabel("Insert block")
                Button { setIndent(i, by: -1) } label: { Image(systemName: "decrease.indent") }.accessibilityLabel("Outdent")
                    .disabled((note.blocks[i].indent ?? 0) == 0)
                Button { setIndent(i, by: 1) } label: { Image(systemName: "increase.indent") }.accessibilityLabel("Indent")
                Button { pasteFromClipboard() } label: { Image(systemName: "doc.on.clipboard") }.accessibilityLabel("Paste with formatting")
                Menu {
                    Button("Ask AI…", systemImage: "sparkles") { aiWrite = AIWriteRequest(mode: .ask, blockId: id) }
                    Divider()
                    ForEach(AIAction.edits) { a in
                        Button(a.title, systemImage: a.icon) { editWithAI(i, preset: a) }
                    }
                    Button("Tell AI what to change…", systemImage: "text.cursor") { editWithAI(i, preset: nil) }
                } label: { Image(systemName: "sparkles") }
                .accessibilityLabel("AI")
                .disabled(note.isLocked)
            }
            Spacer()
            Button("Done") { focused = nil; editing = nil; slashFor = nil; mentionFor = nil }
        }
    }

    // MARK: AI

    private var pageText: String { "Title: \(note.title)\n" + note.plainText }

    /// The selected words (or the whole line) go to AI to rewrite.
    private func editWithAI(_ i: Int, preset: AIAction?) {
        let text = note.blocks[i].text
        var range: Range<String.Index>?
        if case .selection(let r)? = selection?.indices, !r.isEmpty, r.lowerBound >= text.startIndex, r.upperBound <= text.endIndex { range = r }
        let source = range.map { String(text[$0]) } ?? text
        guard !source.trimmingCharacters(in: .whitespaces).isEmpty else {
            aiWrite = AIWriteRequest(mode: .ask, blockId: note.blocks[i].id); return
        }
        aiWrite = AIWriteRequest(mode: .edit, blockId: note.blocks[i].id, source: source, preset: preset, range: range)
    }

    /// Puts AI's answer into the page.
    private func applyAI(_ r: AIWriteRequest, text: String, replace: Bool) {
        guard !text.isEmpty else { return }
        NoteHistory.snapshot(note)                 // so any AI change can be undone from Version history
        let idx = r.blockId.flatMap { id in note.blocks.firstIndex { $0.id == id } }
        let newBlocks = SmartPaste.blocks(from: text, markdown: true)
        switch r.mode {
        case .edit where replace:
            guard let i = idx else { return }
            let current = note.blocks[i].text
            if let range = r.range, range.upperBound <= current.endIndex, String(current[range]) == r.source {
                note.blocks[i].text.replaceSubrange(range, with: text.replacingOccurrences(of: "\n", with: " "))
            } else if newBlocks.count > 1 {
                var first = newBlocks; first[0].indent = note.blocks[i].indent
                note.blocks.replaceSubrange(i...i, with: first)
            } else {
                note.blocks[i].text = newBlocks.first?.text ?? text
            }
        case .page where r.preset?.id == "title":
            note.title = text.components(separatedBy: "\n").first?.trimmingCharacters(in: CharacterSet(charactersIn: "\"'# ")) ?? note.title
        case .page where r.preset?.id == "tldr":
            var c = NoteBlock(kind: .callout, text: "**TL;DR** " + text.replacingOccurrences(of: "\n", with: " "))
            c.icon = "✨"
            note.blocks.insert(c, at: 0)
        case .page where r.preset?.id == "actions" && text.lowercased().hasPrefix("none"):
            UndoCenter.shared.notify("No action items on this page")
        case .page where r.preset?.id == "outline":
            note.blocks = newBlocks
            UndoCenter.shared.notify("Restructured. The old version is in Version history.")
        default:
            var add = newBlocks
            if r.mode == .page, let p = r.preset, p.id != "continue" { add.insert(NoteBlock(kind: .heading3, text: p.title.replacingOccurrences(of: " page", with: "")), at: 0) }
            // An empty line you asked from gets replaced; otherwise it goes just below.
            if let i = idx, note.blocks[i].kind == .text, note.blocks[i].text.trimmingCharacters(in: .whitespaces).isEmpty {
                note.blocks.replaceSubrange(i...i, with: add)
            } else if let i = idx {
                note.blocks.insert(contentsOf: add, at: i + 1)
            } else {
                note.blocks.append(contentsOf: add)
            }
        }
    }

    private func continueWriting() async {
        aiWorking = true; defer { aiWorking = false }
        guard let more = await AIRouter.shared.write("Continue this page naturally with one or two short paragraphs in the same voice. Reply with only the new text.\n\n\(pageText.suffix(4_000))") else { return }
        for para in more.components(separatedBy: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }) {
            note.blocks.append(NoteBlock(kind: .text, text: para))
        }
    }

    private func summarize() async {
        aiWorking = true; defer { aiWorking = false }
        guard let s = await AIRouter.shared.summarize(note.plainText) else { return }
        note.aiSummary = s
        var c = NoteBlock(kind: .callout, text: s.replacingOccurrences(of: "\n", with: " "))
        c.icon = "✨"
        note.blocks.insert(c, at: 0)
    }

    private var askSheet: some View {
        NavigationStack {
            Form {
                Section { TextField("What do you want to know?", text: $question, axis: .vertical) }
                Section {
                    Button(aiWorking ? "Thinking…" : "Ask") {
                        Task {
                            aiWorking = true
                            answer = await AIRouter.shared.write("Answer the question using only this page. If the page doesn't say, say so briefly.\n\nPAGE:\n\(pageText.prefix(8_000))\n\nQUESTION: \(question)")
                            aiWorking = false
                        }
                    }
                    .disabled(question.isEmpty || aiWorking)
                }
                if let answer { Section("Answer") { Text(answer) } }
            }
            .navigationTitle("Ask this page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { asking = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func extractTasks() {
        var n = 0
        for b in note.blocks where b.kind == .todo && !b.checked && !b.text.isEmpty {
            let t = TaskItem(title: b.text)
            t.sourceNoteId = note.id
            ctx.insert(t); n += 1
        }
        Haptics.success()
        UndoCenter.shared.notify(n == 0 ? "No open to-dos on this page" : "Added \(n) task\(n == 1 ? "" : "s")")
    }

    // MARK: Media, lock

    private func insertPhoto(_ item: PhotosPickerItem?) async {
        defer { photoItem = nil; imageTarget = nil }
        guard let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data), let jpg = NoteMedia.jpeg(img) else { return }
        if let target = imageTarget, let i = note.blocks.firstIndex(where: { $0.id == target }) {
            let a = NoteAttachment(noteId: note.id, data: jpg, kind: "photo")
            ctx.insert(a)
            note.blocks[i].refId = a.id.uuidString
        } else {
            NoteMedia.add(jpg, kind: "photo", to: note, ctx: ctx)
        }
    }

    private func unlockNote() async {
        if await AppLock.authenticate("Open “\(note.title)”") { PageCrypto.decrypt(note); withAnimation { unlocked = true } }
    }

    private func toggleLock() {
        Task {
            if note.isLocked {
                if await AppLock.authenticate("Remove the lock from this page") { note.isLocked = false }
            } else {
                note.isLocked = true; note.aiSummary = nil; unlocked = true
                Haptics.success()
            }
            SpotlightIndex.refresh(ctx)
        }
    }
}

/// Page emoji picker.
struct IconPicker: View {
    @Binding var icon: String?
    @Environment(\.dismiss) private var dismiss
    @State private var custom = ""
    private let emojis = ["📄", "📝", "📌", "📚", "🧠", "💡", "✅", "🎯", "🚀", "🏠", "💼", "💰", "❤️", "🏃", "🍎", "✈️",
                          "🎨", "🎵", "📷", "🛒", "🧘", "🌱", "⭐️", "🔥", "📅", "🗂️", "🧪", "🛠️", "👶", "🐶", "☕️", "🎓"]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                    ForEach(emojis, id: \.self) { e in
                        Button { icon = e; dismiss() } label: { Text(e).font(.system(size: 30)) }
                    }
                }
                .padding()
                HStack {
                    TextField("Or type any emoji", text: $custom).textFieldStyle(.roundedBorder)
                    Button("Use") { if let f = custom.first { icon = String(f); dismiss() } }.disabled(custom.isEmpty)
                }
                .padding(.horizontal)
            }
            .navigationTitle("Page icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Remove") { icon = nil; dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Move a page under another page (or to the top level).
struct MovePageSheet: View {
    let note: Note
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Note.title) private var notes: [Note]

    /// A page can't move inside itself or its own sub-pages.
    private func isDescendant(_ candidate: Note) -> Bool {
        var cursor: UUID? = candidate.id
        var guardCount = 0
        while let c = cursor, guardCount < 50 {
            if c == note.id { return true }
            cursor = notes.first { $0.id == c }?.parentId
            guardCount += 1
        }
        return false
    }

    var body: some View {
        NavigationStack {
            List {
                Button { note.parentId = nil; dismiss() } label: { Label("Top level", systemImage: "house") }
                ForEach(notes.filter { !$0.isTemplate && !isDescendant($0) && !$0.title.isEmpty }) { n in
                    Button { note.parentId = n.id; dismiss() } label: {
                        HStack { Text(n.icon ?? (n.isDatabase ? "🗃️" : "📄")); Text(n.title); Spacer(); if note.parentId == n.id { Image(systemName: "checkmark") } }
                    }
                }
            }
            .navigationTitle("Move to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct PublishedLink: Identifiable { let url: URL; var id: String { url.absoluteString } }

/// After publishing: the link, ready to copy or share.
private struct PublishedSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.m) {
                Image(systemName: "globe").font(.system(size: 44)).foregroundStyle(DS.Palette.accent)
                Text("Published").font(DS.Font.title)
                Text("Anyone with this link can read the page. Edit the page and choose Update web page to refresh it, or Unpublish to take it down.")
                    .font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft).multilineTextAlignment(.center)
                Text(url.absoluteString).font(.callout.monospaced()).textSelection(.enabled).multilineTextAlignment(.center)
                ShareLink(item: url) { Label("Share link", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                Button("Copy link") { UIPasteboard.general.url = url; Haptics.tap() }
            }
            .padding()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
