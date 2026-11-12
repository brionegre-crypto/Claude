import SwiftUI
import SwiftData
import PhotosUI
import VisionKit

/// A page: cover, icon, title and blocks. Type "/" for any block, "@" to mention a page, person or date,
/// and markdown shortcuts ("- ", "[] ", "# ", "> ") as you type. Return starts the next block.
struct NoteEditor: View {
    @Environment(\.modelContext) private var ctx
    @Bindable var note: Note
    @Query private var allNotes: [Note]
    @Query(sort: \Person.name) private var people: [Person]

    @FocusState private var focused: UUID?
    @State private var editing: UUID?
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

    var body: some View {
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
        } else {
            page
        }
    }

    // MARK: Page

    private var page: some View {
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
                ForEach($note.blocks) { $b in row($b) }
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
        .environment(\.editMode, .constant(reordering ? .active : .inactive))
        .scrollDismissesKeyboard(.interactively)
        .environment(\.openURL, OpenURLAction { url in
            if let id = RichText.pageId(from: url), let target = allNotes.first(where: { $0.id == id }) {
                openPage = target
                return .handled
            }
            return .systemAction
        })
        .navigationDestination(item: $openPage) { NoteEditor(note: $0) }
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
        .sheet(isPresented: $showSketch) { SketchSheet { NoteMedia.add($0, kind: "sketch", to: note, ctx: ctx) } }
        .sheet(isPresented: $showIcons) { IconPicker(icon: $note.icon) }
        .sheet(isPresented: $movingPage) { MovePageSheet(note: note) }
        .sheet(item: Binding(get: { exportURL.map(ExportFile.init) }, set: { if $0 == nil { exportURL = nil } })) { f in
            ShareSheet(url: f.url).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $asking) { askSheet }
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
                        } label: { Image(systemName: "photo").padding(8).background(.ultraThinMaterial, in: Circle()) }
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
            NoteLinksSection(note: note)
        }
    }

    // MARK: Blocks

    @ViewBuilder
    private func row(_ b: Binding<NoteBlock>) -> some View {
        let blk = b.wrappedValue
        let colors = BlockColor.parse(blk.color)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                prefix(b)
                content(b)
            }
            .foregroundStyle(colors.text ?? DS.Palette.ink)
            .padding(.vertical, blk.kind == .callout || colors.background != nil ? 8 : 2)
            .padding(.horizontal, blk.kind == .callout || colors.background != nil ? 10 : 0)
            .background(blk.kind == .callout ? (colors.background ?? DS.Palette.elevated) : (colors.background ?? .clear), in: .rect(cornerRadius: 8))
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
        case .bullet: Text("•").font(DS.Font.body)
        case .numbered: Text("\(number(for: b.wrappedValue.id)).").font(DS.Font.body).monospacedDigit()
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
                if !(blk.collapsed ?? false) {
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

    private func number(for id: UUID) -> Int {
        guard let i = note.blocks.firstIndex(where: { $0.id == id }) else { return 1 }
        var n = 1, j = i - 1
        while j >= 0 && note.blocks[j].kind == .numbered { n += 1; j -= 1 }
        return n
    }

    private func beginEdit(_ id: UUID) {
        editing = id
        slashFor = nil; mentionFor = nil
        Task { @MainActor in focused = id }
    }

    // MARK: Typing: shortcuts, "/", "@" and Return

    private func handleTyping(_ b: Binding<NoteBlock>, old: String, new: String) {
        let id = b.wrappedValue.id
        // Return → next block (lists continue; an empty list item ends the list).
        if new.contains("\n") {
            let parts = new.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            let before = String(parts.first ?? ""), after = parts.count > 1 ? String(parts[1]) : ""
            let kind = b.wrappedValue.kind
            if before.isEmpty && [.bullet, .todo, .numbered].contains(kind) {
                b.wrappedValue.kind = .text
                b.wrappedValue.text = after
                return
            }
            b.wrappedValue.text = before
            let next: BlockKind = [.bullet, .todo, .numbered].contains(kind) ? kind : .text
            insertBlock(after: id, kind: next, text: after)
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

    private func insertBlock(after id: UUID, kind: BlockKind, text: String) {
        let nb = NoteBlock(kind: kind, text: text)
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
                mentionRow("👤", p.name) { finishMention(b, with: "**@\(p.name)**") }
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
            ForEach(SlashCommand.all.filter { ![.page, .image, .table, .bookmark, .divider].contains($0.kind) }) { cmd in
                Button(cmd.title, systemImage: cmd.icon) { b.wrappedValue.kind = cmd.kind; if cmd.kind == .callout && b.wrappedValue.icon == nil { b.wrappedValue.icon = "💡" } }
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
        Button("Make it a task", systemImage: "checklist") {
            let title = b.wrappedValue.text.replacingOccurrences(of: #"[*_=`]"#, with: "", options: .regularExpression)
            guard !title.isEmpty else { return }
            let t = QuickAdd.create(title, in: ctx); t.sourceNoteId = note.id
            UndoCenter.shared.notify("Added “\(t.title)” to Tasks")
        }
        Button("Improve writing", systemImage: "sparkles") {
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

    private func move(_ id: UUID, by delta: Int) {
        guard let i = note.blocks.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard note.blocks.indices.contains(j) else { return }
        note.blocks.swapAt(i, j)
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
                if VNDocumentCameraViewController.isSupported {
                    Button("Scan document", systemImage: "doc.viewfinder") { showScanner = true }
                }
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
                Button("Continue writing", systemImage: "text.append") { Task { await continueWriting() } }
                Button("Summarize", systemImage: "text.line.first.and.arrowtriangle.forward") { Task { await summarize() } }
                Button("Ask this page", systemImage: "questionmark.bubble") { answer = nil; question = ""; asking = true }
                Button("Turn to-dos into tasks", systemImage: "checklist") { extractTasks() }
            } label: { Image(systemName: "sparkles") }
            .disabled(note.isLocked)
            Menu {
                Button(reordering ? "Done reordering" : "Reorder blocks", systemImage: "arrow.up.arrow.down") { withAnimation { reordering.toggle() } }
                Button("Move to…", systemImage: "folder") { movingPage = true }
                Button(note.isLocked ? "Remove lock" : "Lock page", systemImage: note.isLocked ? "lock.open" : "lock") { toggleLock() }
                Button("Save as template", systemImage: "doc.on.doc") {
                    let t = Note(title: note.title, blocks: note.blocks.map { var b = $0; b.id = UUID(); b.checked = false; return b })
                    t.isTemplate = true; t.icon = note.icon
                    ctx.insert(t)
                    UndoCenter.shared.notify("Saved “\(note.title)” as a template")
                }
                Divider()
                Button("Export as Markdown", systemImage: "doc.plaintext") { exportURL = NoteExport.markdownFile(note) }
                Button("Export as PDF", systemImage: "doc.richtext") { exportURL = NoteExport.pdfFile(note) }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        ToolbarItemGroup(placement: .keyboard) {
            if let id = focused, let i = note.blocks.firstIndex(where: { $0.id == id }) {
                Button { RichText.wrap(&note.blocks[i].text, selection: selection, left: "**", right: "**") } label: { Image(systemName: "bold") }
                Button { RichText.wrap(&note.blocks[i].text, selection: selection, left: "*", right: "*") } label: { Image(systemName: "italic") }
                Button { RichText.wrap(&note.blocks[i].text, selection: selection, left: "==", right: "==") } label: { Image(systemName: "highlighter") }
                Button { RichText.wrap(&note.blocks[i].text, selection: selection, left: "`", right: "`") } label: { Image(systemName: "chevron.left.forwardslash.chevron.right") }
                Button { RichText.wrap(&note.blocks[i].text, selection: selection, left: "[", right: "](https://)") } label: { Image(systemName: "link") }
                Button { note.blocks[i].text += (note.blocks[i].text.isEmpty || note.blocks[i].text.hasSuffix(" ") ? "@" : " @") } label: { Image(systemName: "at") }
                Button { if note.blocks[i].text.isEmpty { note.blocks[i].text = "/" } else { insertBlock(after: id, kind: .text, text: "/") } } label: { Image(systemName: "plus.square") }
            }
            Spacer()
            Button("Done") { focused = nil; editing = nil; slashFor = nil; mentionFor = nil }
        }
    }

    // MARK: AI

    private var pageText: String { "Title: \(note.title)\n" + note.plainText }

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
        if await AppLock.authenticate("Open “\(note.title)”") { withAnimation { unlocked = true } }
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
