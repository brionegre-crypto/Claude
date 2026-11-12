import SwiftUI
import SwiftData
import VisionKit
import PhotosUI

/// Your workspace: favorites, a tree of pages and databases, folders and templates.
struct NotesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    private var notes: [Note] { allNotes.filter { !$0.isTemplate } }
    private var templates: [Note] { allNotes.filter(\.isTemplate) }
    @State private var search = ""
    @AppStorage("notes.folder") private var folderFilter = ""
    @State private var newFolderFor: Note?
    @State private var newFolderName = ""
    @State private var opened: Note?
    private var folders: [String] { Array(Set(notes.compactMap(\.folder))).sorted() }

    private var ids: Set<UUID> { Set(notes.map(\.id)) }
    /// Top-level pages: no parent (or a parent that no longer exists), in the folder you're viewing.
    private var roots: [Note] {
        let all = ids
        let base = notes.filter { $0.parentId == nil || !all.contains($0.parentId!) }
        let inFolder = folderFilter.isEmpty || !folders.contains(folderFilter) ? base : base.filter { $0.folder == folderFilter }
        return inFolder.sorted { ($0.sortIndex, $1.updatedAt) < ($1.sortIndex, $0.updatedAt) }
    }
    private var results: [Note] {
        notes.filter { $0.title.localizedCaseInsensitiveContains(search) || (!$0.isLocked && $0.plainText.localizedCaseInsensitiveContains(search)) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !folders.isEmpty && search.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            folderChip("All", "")
                            ForEach(folders, id: \.self) { folderChip($0, $0) }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                if !search.isEmpty {
                    Section("Results") { ForEach(results) { row($0, showSnippet: true) } }
                } else {
                    let favorites = notes.filter(\.isPinned)
                    if !favorites.isEmpty { Section("Favorites") { ForEach(favorites) { row($0, showSnippet: false) } } }
                    Section("Pages") {
                        if roots.isEmpty {
                            Button { newPage() } label: { Label("Create your first page", systemImage: "plus") }
                        }
                        ForEach(roots) { PageTreeNode(note: $0, all: notes, depth: 0, row: { row($0, showSnippet: false) }) }
                    }
                    if !templates.isEmpty {
                        Section {
                            ForEach(templates) { row($0, showSnippet: false) }.onDelete { idx in idx.map { templates[$0] }.forEach(ctx.delete) }
                        } header: { Text("Templates") } footer: { Text("Use {{date}} in a template to fill in today's date.") }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search pages")
            .navigationDestination(item: $opened) { NoteEditor(note: $0) }
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
                    Button("New page", systemImage: "doc") { newPage() }
                    Button("New database", systemImage: "tablecells") { opened = NotesDatabase.create(title: "Untitled database", parent: nil, ctx: ctx) }
                    if !templates.isEmpty {
                        Menu("From template", systemImage: "doc.on.doc") {
                            ForEach(templates) { t in Button(t.title) { create(fromTemplate: t) } }
                        }
                    }
                    Divider()
                    Button("Meeting notes for next event", systemImage: "person.2") { createMeetingNote() }
                    NavigationLink { MeetingRecorderView() } label: { Label("Record a meeting", systemImage: "mic") }
                    Button("Today's note", systemImage: "calendar") { opened = DailyNote.today(ctx) }
                    Button("Daily journal", systemImage: "book") { create(Note(title: Date().formatted(date: .complete, time: .omitted), blocks: [
                        .init(kind: .heading, text: "Wins"), .init(kind: .bullet, text: ""),
                        .init(kind: .heading, text: "On my mind"), .init(kind: .bullet, text: ""),
                    ])) }
                } label: { Image(systemName: "square.and.pencil") }
            }
        }
    }

    private func newPage() { create(Note(title: "")) }

    @ViewBuilder
    private func row(_ n: Note, showSnippet: Bool) -> some View {
        Button { opened = n } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(n.icon ?? (n.isDatabase ? "🗃️" : "📄"))
                    Text(n.title.isEmpty ? "Untitled" : n.title).font(DS.Font.body).foregroundStyle(DS.Palette.ink).lineLimit(1)
                    if n.isLocked { Image(systemName: "lock.fill").font(.caption).foregroundStyle(DS.Palette.inkSoft) }
                }
                if showSnippet && !n.isLocked {
                    Text(n.aiSummary ?? n.plainText).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(n.isPinned ? "Remove from Favorites" : "Add to Favorites", systemImage: n.isPinned ? "star.slash" : "star") { n.isPinned.toggle() }
            Button("Add page inside", systemImage: "doc.badge.plus") {
                let c = Note(title: ""); c.parentId = n.id; ctx.insert(c); opened = c
            }
            Menu("Move to Folder", systemImage: "folder") {
                Button("No folder") { n.folder = nil }
                ForEach(folders, id: \.self) { f in Button(f) { n.folder = f } }
                Button("New folder…", systemImage: "folder.badge.plus") { newFolderName = ""; newFolderFor = n }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { deletePage(n) }
        }
        .swipeActions { Button("Delete", role: .destructive) { deletePage(n) } }
    }

    /// Deleting a page keeps what's inside it: sub-pages move up a level (database rows go with the database).
    private func deletePage(_ n: Note) {
        for child in notes where child.parentId == n.id {
            if n.isDatabase { ctx.delete(child) } else { child.parentId = n.parentId }
        }
        ctx.delete(n)
        Haptics.tap()
    }

    private func create(_ n: Note) {
        if !folderFilter.isEmpty && n.folder == nil { n.folder = folderFilter }     // new notes land in the folder you're viewing
        ctx.insert(n); Haptics.tap()
        opened = n
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

/// One page in the tree, with its sub-pages folded underneath. Database rows stay inside their database.
struct PageTreeNode<Row: View>: View {
    let note: Note
    let all: [Note]
    let depth: Int
    let row: (Note) -> Row
    @State private var expanded = false

    private var children: [Note] {
        note.isDatabase || depth > 6 ? [] : all.filter { $0.parentId == note.id }.sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }

    var body: some View {
        if children.isEmpty {
            row(note)
        } else {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(children) { PageTreeNode(note: $0, all: all, depth: depth + 1, row: row) }
            } label: { row(note) }
        }
    }
}
