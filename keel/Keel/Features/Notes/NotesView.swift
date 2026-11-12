import SwiftUI
import SwiftData
import VisionKit
import PhotosUI

/// Notion-style block notes. Meeting notes auto-link to the calendar event; any line can become a task.
struct NotesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var search = ""

    private var filtered: [Note] {
        search.isEmpty ? notes : notes.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.plainText.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                let pinned = filtered.filter(\.isPinned)
                if !pinned.isEmpty { Section("Pinned") { ForEach(pinned) { row($0) } } }
                Section("All notes") { ForEach(filtered.filter { !$0.isPinned }) { row($0) }.onDelete(perform: delete) }
            }
            .searchable(text: $search, prompt: "Search notes")
            .navigationTitle("Notes")
            .toolbar {
                Menu {
                    Button("Blank page") { create(Note(title: "Untitled")) }
                    Button("Meeting notes for next event") { createMeetingNote() }
                    NavigationLink { MeetingRecorderView() } label: { Label("Record a meeting", systemImage: "mic") }
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
                Text(n.title).font(DS.Font.headline)
                Text(n.aiSummary ?? n.plainText).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
            }
        }
    }

    private func create(_ n: Note) { ctx.insert(n); Haptics.tap() }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                TextField("Title", text: $note.title, axis: .vertical).font(DS.Font.hero)
                ForEach($note.blocks) { $block in blockView($block) }
                Button { add(.text) } label: { Label("Add block", systemImage: "plus").font(DS.Font.caption) }
                    .foregroundStyle(DS.Palette.inkSoft)
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
                    Button("Turn to-dos into tasks", systemImage: "checklist") { extractTasks() }
                } label: { Image(systemName: "sparkles") }
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
            TextField("Type / for commands", text: block.text, axis: .vertical)
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
