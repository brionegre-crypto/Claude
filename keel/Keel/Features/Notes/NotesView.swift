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

    enum SortMode: String, CaseIterable { case manual = "Manual", recent = "Recently edited", alpha = "A to Z" }
    @AppStorage("notes.sort") private var sortRaw = SortMode.manual.rawValue
    private var sortMode: SortMode { SortMode(rawValue: sortRaw) ?? .manual }
    private var sortedRoots: [Note] {
        switch sortMode {
        case .manual: roots
        case .recent: roots.sorted { $0.updatedAt > $1.updatedAt }
        case .alpha: roots.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }
    private var recent: [Note] { Array(notes.filter { !$0.title.isEmpty || !$0.plainText.isEmpty }.prefix(8)) }
    private var editedToday: Int { notes.filter { Calendar.current.isDateInToday($0.updatedAt) }.count }

    var body: some View {
        NavigationStack {
            List {
                if !search.isEmpty {
                    searchResults
                } else if notes.isEmpty {
                    emptyState
                } else {
                    Section {
                        quickActions
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                    }
                    if recent.count >= 2 {
                        Section {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: DS.Space.m) {
                                    ForEach(recent) { n in NoteCard(note: n) { opened = n } }
                                }
                                .scrollTargetLayout()
                                .padding(.horizontal, 20).padding(.vertical, 4)
                            }
                            .scrollTargetBehavior(.viewAligned)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        } header: { sectionHeader("Jump back in", editedToday > 0 ? "\(editedToday) edited today" : nil) }
                    }
                    let favorites = notes.filter(\.isPinned)
                    if !favorites.isEmpty {
                        Section { ForEach(favorites) { row($0, showSnippet: false) } } header: { sectionHeader("Favorites", nil) }
                    }
                    Section {
                        let folderList = folders
                        if !folderList.isEmpty {
                            let counts = Dictionary(notes.compactMap { n in n.folder.map { ($0, 1) } }, uniquingKeysWith: +)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    folderChip("All", "", count: notes.filter { $0.parentId == nil }.count)
                                    ForEach(folderList, id: \.self) { f in folderChip(f, f, count: counts[f] ?? 0) }
                                }
                                .padding(.vertical, 2)
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                        ForEach(sortedRoots) { root in PageTreeNode(note: root, all: notes, depth: 0, row: { page in row(page, showSnippet: false) }) }
                        Button { newPage() } label: {
                            Label("New page", systemImage: "plus").font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
                        }
                    } header: {
                        HStack {
                            sectionHeader(folderFilter.isEmpty || !folders.contains(folderFilter) ? "All pages" : folderFilter, nil)
                            Spacer()
                            Menu {
                                Picker("Sort", selection: $sortRaw) {
                                    ForEach(SortMode.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                                }
                            } label: {
                                Label(sortMode.rawValue, systemImage: "arrow.up.arrow.down").font(DS.Font.caption).labelStyle(.titleAndIcon)
                            }
                            .textCase(nil)
                            .accessibilityLabel("Sort pages")
                        }
                    }
                    if !templates.isEmpty {
                        Section {
                            DisclosureGroup {
                                ForEach(templates) { row($0, showSnippet: false) }.onDelete { idx in idx.map { templates[$0] }.forEach(ctx.delete) }
                            } label: {
                                Label("Templates · \(templates.count)", systemImage: "doc.on.doc").font(DS.Font.body)
                            }
                        } footer: { Text("Use {{date}} in a template to fill in today's date.") }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $search, prompt: "Search titles and text")
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
                ToolbarItem(placement: .topBarLeading) {
                    Button { showBrain = true } label: { Image(systemName: "brain.head.profile") }
                        .accessibilityLabel("Brain map of your notes")
                }
                ToolbarItem(placement: .topBarTrailing) {
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
                        Button("Today's note", systemImage: "calendar") { opened = DailyNote.today(ctx) }
                        Button("Daily journal", systemImage: "book") { createJournalPage() }
                        Divider()
                        Button("Organize my notes…", systemImage: "wand.and.stars") { showOrganize = true }
                        Button("Import from another app…", systemImage: "square.and.arrow.down") { showImport = true }
                    } label: { Image(systemName: "square.and.pencil") } primaryAction: { newPage() }
                    .accessibilityLabel("New page. Hold for more")
                }
            }
            .navigationDestination(isPresented: $recording) { MeetingRecorderView() }
            .navigationDestination(isPresented: $showBrain) { BrainMapView() }
            .navigationDestination(isPresented: $showImport) { ImportView() }
            .sheet(isPresented: $showOrganize) { OrganizeNotesView() }
            .task { await NotesOrganizer.autoFile(ctx: ctx) }
        }
    }

    @State private var recording = false
    @State private var showBrain = false
    @State private var showImport = false
    @State private var showOrganize = false

    // MARK: Pieces

    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s) {
                QuickTile(title: "New page", icon: "square.and.pencil", color: DS.Palette.accent) { newPage() }
                QuickTile(title: "Today", icon: "calendar", color: .orange) { opened = DailyNote.today(ctx) }
                QuickTile(title: "Record", icon: "waveform.badge.mic", color: .red) { recording = true }
                QuickTile(title: "Meeting", icon: "person.2.fill", color: .teal) { createMeetingNote() }
                QuickTile(title: "Journal", icon: "book.fill", color: .pink) { createJournalPage() }
                QuickTile(title: "Brain map", icon: "brain.head.profile.fill", color: .pink) { showBrain = true }
                QuickTile(title: "Organize", icon: "wand.and.stars", color: .indigo) { showOrganize = true }
                QuickTile(title: "Database", icon: "tablecells.fill", color: .purple) {
                    opened = NotesDatabase.create(title: "Untitled database", parent: nil, ctx: ctx)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Space.l) {
            Image(systemName: "square.text.square.fill").font(.system(size: 56)).foregroundStyle(DS.Palette.accent.gradient)
            VStack(spacing: 6) {
                Text("Your workspace").font(DS.Font.title)
                Text("Pages, checklists, tables and meeting notes. Type / in a page to add anything.")
                    .font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft).multilineTextAlignment(.center)
            }
            quickActions
            Button { showImport = true } label: { Label("Bring notes from another app", systemImage: "square.and.arrow.down") }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity).padding(.vertical, DS.Space.xl)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    @ViewBuilder private var searchResults: some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: search).listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(results) { row($0, showSnippet: true) }
            } header: { sectionHeader("\(results.count) result\(results.count == 1 ? "" : "s")", nil) }
        }
    }

    private func sectionHeader(_ title: String, _ trailing: String?) -> some View {
        HStack {
            Text(title).font(DS.Font.headline).foregroundStyle(DS.Palette.ink).textCase(nil)
            if let trailing { Spacer(); Text(trailing).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).textCase(nil) }
        }
    }

    private func createJournalPage() {
        create(Note(title: Date().formatted(date: .complete, time: .omitted), blocks: [
            .init(kind: .heading, text: "Wins"), .init(kind: .bullet, text: ""),
            .init(kind: .heading, text: "On my mind"), .init(kind: .bullet, text: ""),
        ]))
    }

    private func newPage() { create(Note(title: "")) }

    @ViewBuilder
    private func row(_ n: Note, showSnippet: Bool) -> some View {
        let children = notes.filter { $0.parentId == n.id }.count
        Button { opened = n } label: {
            HStack(spacing: DS.Space.m) {
                Text(n.icon ?? (n.isDatabase ? "🗃️" : "📄"))
                    .font(.system(size: 18))
                    .frame(width: 34, height: 34)
                    .background((n.isDatabase ? Color.purple : DS.Palette.accent).opacity(0.1), in: .rect(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(n.title.isEmpty ? "Untitled" : n.title).font(DS.Font.body.weight(.medium))
                            .foregroundStyle(n.title.isEmpty ? DS.Palette.inkSoft : DS.Palette.ink).lineLimit(1)
                        if n.isLocked { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(DS.Palette.inkSoft) }
                        if n.isPinned && !showSnippet { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                    }
                    if showSnippet && !n.isLocked {
                        Text(n.aiSummary ?? n.plainText).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                    }
                    Text(subtitle(n, children: children)).font(.caption2).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
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
        .swipeActions(edge: .leading) {
            Button { n.isPinned.toggle(); Haptics.tap() } label: {
                Label(n.isPinned ? "Unfavorite" : "Favorite", systemImage: n.isPinned ? "star.slash" : "star.fill")
            }
            .tint(.yellow)
        }
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

    private func subtitle(_ n: Note, children: Int) -> String {
        var parts = ["Edited " + n.updatedAt.formatted(.relative(presentation: .named))]
        if n.isDatabase { parts.append("\(children) row\(children == 1 ? "" : "s")") }
        else if children > 0 { parts.append("\(children) page\(children == 1 ? "" : "s") inside") }
        if let f = n.folder, folderFilter.isEmpty { parts.append(f) }
        return parts.joined(separator: " · ")
    }

    private func folderChip(_ title: String, _ value: String, count: Int) -> some View {
        let on = folderFilter == value || (value.isEmpty && !folders.contains(folderFilter))
        return Button { withAnimation(DS.spring) { folderFilter = value }; Haptics.tap() } label: {
            HStack(spacing: 5) {
                Image(systemName: value.isEmpty ? "tray.full" : "folder.fill").font(.caption)
                Text(title).font(DS.Font.caption.weight(.medium))
                Text("\(count)").font(.caption2.monospacedDigit()).opacity(0.7)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(on ? DS.Palette.accent : DS.Palette.elevated, in: Capsule())
            .foregroundStyle(on ? Color.white : DS.Palette.ink)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
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
                ForEach(children) { child in PageTreeNode(note: child, all: all, depth: depth + 1, row: row) }
            } label: { row(note) }
        }
    }
}

/// A big, friendly create button at the top of Notes.
private struct QuickTile: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38).background(color.gradient, in: .rect(cornerRadius: 11))
                Text(title).font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.ink)
            }
            .frame(width: 92, alignment: .leading)
            .padding(12)
            .background(DS.Palette.elevated, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// "Jump back in": a recent page as a card, with its cover, icon and first lines.
private struct NoteCard: View {
    let note: Note
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    if let data = note.cover, let img = UIImage(data: data) {
                        Image(uiImage: img).resizable().scaledToFill().frame(width: 200, height: 70).clipped()
                    } else {
                        LinearGradient(colors: [DS.Palette.accent.opacity(0.25), DS.Palette.accent.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .frame(width: 200, height: 70)
                    }
                    Text(note.icon ?? (note.isDatabase ? "🗃️" : "📄")).font(.system(size: 26))
                        .padding(.leading, 12).offset(y: 14)
                }
                .frame(width: 200, height: 70)
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title.isEmpty ? "Untitled" : note.title).font(DS.Font.headline).foregroundStyle(DS.Palette.ink).lineLimit(1)
                    Text(note.isLocked ? "Locked" : (note.aiSummary ?? note.plainText).trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(3, reservesSpace: true)
                    Text(note.updatedAt.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                }
                .padding(.horizontal, 12).padding(.top, 18).padding(.bottom, 12)
                .frame(width: 200, alignment: .leading)
            }
            .background(DS.Palette.elevated, in: .rect(cornerRadius: 18))
            .clipShape(.rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(DS.Palette.inkSoft.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the page")
    }
}
