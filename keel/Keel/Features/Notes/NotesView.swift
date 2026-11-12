import SwiftUI
import SwiftData
import VisionKit
import PhotosUI

/// Notion-style block notes. Meeting notes auto-link to the calendar event; any line can become a task.
struct NotesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    private var notes: [Note] { allNotes.filter { !$0.isTemplate } }
    private var templates: [Note] { allNotes.filter(\.isTemplate) }
    @State private var search = ""
    @AppStorage("notes.folder") private var folderFilter = ""
    @State private var newFolderFor: Note?
    @State private var newFolderName = ""
    private var folders: [String] { Array(Set(notes.compactMap(\.folder))).sorted() }

    private var filtered: [Note] {
        let inFolder = folderFilter.isEmpty || !folders.contains(folderFilter) ? notes : notes.filter { $0.folder == folderFilter }
        return search.isEmpty ? inFolder : inFolder.filter { $0.title.localizedCaseInsensitiveContains(search) || (!$0.isLocked && $0.plainText.localizedCaseInsensitiveContains(search)) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !folders.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            folderChip("All", "")
                            ForEach(folders, id: \.self) { folderChip($0, $0) }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                let pinned = filtered.filter(\.isPinned)
                if !pinned.isEmpty { Section("Pinned") { ForEach(pinned) { row($0) } } }
                Section("All notes") { ForEach(filtered.filter { !$0.isPinned }) { row($0) }.onDelete(perform: delete) }
                if !templates.isEmpty && search.isEmpty {
                    Section {
                        ForEach(templates) { row($0) }.onDelete { idx in idx.map { templates[$0] }.forEach(ctx.delete) }
                    } header: { Text("Templates") } footer: { Text("Use {{date}} in a template to fill in today's date.") }
                }
            }
            .searchable(text: $search, prompt: "Search notes")
            .alert("New folder", isPresented: Binding(get: { newFolderFor != nil }, set: { if !$0 { newFolderFor = nil } })) {
                TextField("Name", text: $newFolderName)
                Button("Create") {
                    let name = newFolderName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { newFolderFor?.folder = name; folderFilter = name }
                    newFolderFor = nil
                }
                Button("Cancel", role: .cancel) { newFolderFor = nil }
            }
            .navigationTitle("Notes")
            .toolbar {
                Menu {
                    Button("Blank page") { create(Note(title: "Untitled")) }
                    if !templates.isEmpty {
                        Menu("From template", systemImage: "doc.on.doc") {
                            ForEach(templates) { t in Button(t.title) { create(fromTemplate: t) } }
                        }
                    }
                    Button("Meeting notes for next event") { createMeetingNote() }
                    NavigationLink { MeetingRecorderView() } label: { Label("Record a meeting", systemImage: "mic") }
                    NavigationLink { NoteEditor(note: DailyNote.today(ctx)) } label: { Label("Today's note", systemImage: "calendar") }
                    Button("Daily journal") { create(Note(title: Date().formatted(date: .complete, time: .omitted), blocks: [
                        .init(kind: .heading, text: "Wins"), .init(kind: .bullet, text: ""),
                        .init(kind: .heading, text: "On my mind"), .init(kind: .bullet, text: ""),
                    ])) }
                } label: { Image(systemName: "square.and.pencil") }
            }
        }
    }

    private func row(_ n: Note) -> some View {
        NavigationLink { NoteEditor(note: n) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if n.isLocked { Image(systemName: "lock.fill").font(.caption).foregroundStyle(DS.Palette.inkSoft) }
                    Text(n.title).font(DS.Font.headline)
                }
                Text(n.isLocked ? "Locked" : (n.aiSummary ?? n.plainText)).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
            }
        }
        .contextMenu {
            Menu("Move to Folder", systemImage: "folder") {
                Button("No folder") { n.folder = nil }
                ForEach(folders, id: \.self) { f in Button(f) { n.folder = f } }
                Button("New folder…", systemImage: "folder.badge.plus") { newFolderName = ""; newFolderFor = n }
            }
            Button(n.isPinned ? "Unpin" : "Pin", systemImage: "pin") { n.isPinned.toggle() }
        }
    }

    private func create(_ n: Note) {
        if !folderFilter.isEmpty && n.folder == nil { n.folder = folderFilter }     // new notes land in the folder you're viewing
        ctx.insert(n); Haptics.tap()
    }

    private func folderChip(_ title: String, _ value: String) -> some View {
        Button { withAnimation { folderFilter = value }; Haptics.tap() } label: {
            Chip(text: title, color: folderFilter == value ? DS.Palette.accent : .gray, icon: value.isEmpty ? "tray.full" : "folder")
        }
        .buttonStyle(.plain)
    }

    /// A fresh copy of a template, with {{date}} filled in.
    private func create(fromTemplate t: Note) {
        let today = Date().formatted(date: .long, time: .omitted)
        let blocks = t.blocks.map { b -> NoteBlock in
            var c = NoteBlock(kind: b.kind, text: b.text.replacingOccurrences(of: "{{date}}", with: today))
            c.checked = false; c.refId = b.refId
            return c
        }
        create(Note(title: t.title.replacingOccurrences(of: "{{date}}", with: today), blocks: blocks))
    }
    private func delete(_ idx: IndexSet) { idx.map { filtered.filter { !$0.isPinned }[$0] }.forEach(ctx.delete) }

    private func createMeetingNote() {
        guard let e = CalendarService.shared.todaysEvents().first(where: { $0.endDate > Date() }) else { return create(Note(title: "Meeting")) }
        let attendees = (e.attendees ?? []).compactMap(\.name).joined(separator: ", ")
        let n = Note(title: e.title ?? "Meeting", blocks: [
            .init(kind: .text, text: "\(e.startDate.formatted()) · \(attendees)"),
            .init(kind: .heading, text: "Notes"), .init(kind: .bullet, text: ""),
            .init(kind: .heading, text: "Action items"), .init(kind: .todo, text: ""),
        ])
        n.linkedEventId = e.eventIdentifier
        create(n)
    }
}

struct NoteEditor: View {
    @Environment(\.modelContext) private var ctx
    @Bindable var note: Note
    @FocusState private var focused: UUID?
    @State private var photoItem: PhotosPickerItem?
    @State private var showSketch = false
    @State private var showScanner = false
    @State private var scanning = false
    @State private var unlocked = false
    @State private var exportURL: URL?

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
            editor
        }
    }

    private func unlockNote() async {
        if await AppLock.authenticate("Open “\(note.title)”") { withAnimation { unlocked = true } }
    }

    private func toggleLock() {
        Task {
            if note.isLocked {
                if await AppLock.authenticate("Remove the lock from this note") { note.isLocked = false }
            } else {
                note.isLocked = true; note.aiSummary = nil; unlocked = true
                Haptics.success()
            }
            SpotlightIndex.refresh(ctx)
        }
    }

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                TextField("Title", text: $note.title, axis: .vertical).font(DS.Font.hero)
                ForEach($note.blocks) { $block in blockView($block) }
                Button { add(.text) } label: { Label("Add block", systemImage: "plus").font(DS.Font.caption) }
                    .foregroundStyle(DS.Palette.inkSoft)
                NoteLinksSection(note: note)
            }
            .padding()
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { note.isPinned.toggle() } label: { Image(systemName: note.isPinned ? "pin.fill" : "pin") }
                Menu {
                    PhotosPicker(selection: $photoItem, matching: .images) { Label("Photo", systemImage: "photo") }
                    Button("Sketch", systemImage: "pencil.tip") { showSketch = true }
                    if VNDocumentCameraViewController.isSupported {
                        Button("Scan document", systemImage: "doc.viewfinder") { showScanner = true }
                    }
                } label: { Image(systemName: "paperclip") }
                .accessibilityLabel("Insert")
                Menu {
                    Button("Summarize", systemImage: "sparkles") { Task { note.aiSummary = await AIRouter.shared.summarize(note.plainText) } }
                        .disabled(note.isLocked)
                    Button("Turn to-dos into tasks", systemImage: "checklist") { extractTasks() }
                } label: { Image(systemName: "sparkles") }
                Menu {
                    Button(note.isLocked ? "Remove Lock" : "Lock Note", systemImage: note.isLocked ? "lock.open" : "lock") { toggleLock() }
                    Button("Save as Template", systemImage: "doc.on.doc") {
                        let t = Note(title: note.title, blocks: note.blocks.map { var b = $0; b.id = UUID(); b.checked = false; return b })
                        t.isTemplate = true
                        ctx.insert(t)
                        UndoCenter.shared.notify("Saved “\(note.title)” as a template")
                    }
                    Divider()
                    Button("Export as Markdown", systemImage: "doc.plaintext") { exportURL = NoteExport.markdownFile(note) }
                    Button("Export as PDF", systemImage: "doc.richtext") { exportURL = NoteExport.pdfFile(note) }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .onChange(of: note.blocks) { note.updatedAt = Date() }
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data), let jpg = NoteMedia.jpeg(img) {
                    NoteMedia.add(jpg, kind: "photo", to: note, ctx: ctx)
                }
                photoItem = nil
            }
        }
        .sheet(isPresented: $showSketch) { SketchSheet { NoteMedia.add($0, kind: "sketch", to: note, ctx: ctx) } }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScanner { pages in
                Task {
                    scanning = true
                    for page in pages {
                        let text = await NoteMedia.recognizeText(page)
                        if let jpg = NoteMedia.jpeg(page) { NoteMedia.add(jpg, kind: "scan", to: note, ctx: ctx, text: text) }
                    }
                    scanning = false
                }
            }
            .ignoresSafeArea()
        }
        .overlay { if scanning { ProgressView("Reading the scan…").padding().background(.regularMaterial, in: .rect(cornerRadius: 12)) } }
        .sheet(item: Binding(get: { exportURL.map(ExportFile.init) }, set: { if $0 == nil { exportURL = nil } })) { f in
            ShareSheet(url: f.url).presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder private func blockView(_ block: Binding<NoteBlock>) -> some View {
        switch block.wrappedValue.kind {
        case .heading:
            TextField("Heading", text: block.text).font(DS.Font.title).focused($focused, equals: block.wrappedValue.id)
        case .todo:
            HStack { CompletionCheck(isDone: block.checked); TextField("To-do", text: block.text) }
        case .bullet:
            HStack(alignment: .top) { Text("•"); TextField("", text: block.text, axis: .vertical) }
        case .quote:
            TextField("Quote", text: block.text, axis: .vertical).italic().padding(.leading, 10)
                .overlay(alignment: .leading) { Rectangle().fill(DS.Palette.accent).frame(width: 3) }
        case .divider:
            Divider()
        case .image:
            ImageBlockView(attachmentId: block.wrappedValue.refId)
        default:
            // Slash-commands: type "/todo", "/h", "/quote" at the start of a line to convert the block
            TextField("Type / for commands, [[ to link a note", text: block.text, axis: .vertical)
                .focused($focused, equals: block.wrappedValue.id)
                .onChange(of: block.wrappedValue.text) { _, new in slash(block, new) }
        }
    }

    private func slash(_ block: Binding<NoteBlock>, _ text: String) {
        let map: [String: BlockKind] = ["/todo ": .todo, "/h ": .heading, "/quote ": .quote, "/- ": .bullet, "/divider": .divider]
        for (cmd, kind) in map where text.hasPrefix(cmd) {
            block.wrappedValue.kind = kind
            block.wrappedValue.text = String(text.dropFirst(cmd.count))
        }
    }

    private func add(_ kind: BlockKind) {
        let b = NoteBlock(kind: kind, text: "")
        note.blocks.append(b)
        focused = b.id
    }

    private func extractTasks() {
        for b in note.blocks where b.kind == .todo && !b.checked && !b.text.isEmpty {
            let t = TaskItem(title: b.text)
            t.sourceNoteId = note.id
            ctx.insert(t)
        }
        Haptics.success()
    }
}
