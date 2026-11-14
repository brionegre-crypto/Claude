import SwiftUI
import SwiftData
#if !targetEnvironment(macCatalyst)
import VisionKit
#endif
import PhotosUI

/// Your workspace, Notion-style: a greeting, quick actions, Jump back in, Favorites, then a page tree of
/// workspaces → folders → pages (and pages inside pages), and templates.
struct NotesView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var multiWindow
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    private var notes: [Note] { allNotes.filter { !$0.isTemplate } }
    private var templates: [Note] { allNotes.filter { $0.isTemplate && $0.title != Supertags.pageTitle } }
    @State private var search = ""
    @State private var newFolderFor: Note?
    @State private var newFolderName = ""
    @State private var opened: Note?
    private var emptyFolders: [String] { emptyFoldersRaw.split(separator: "\n").map(String.init) }
    private var folders: [String] { Array(Set(notes.compactMap(\.folder) + emptyFolders)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }

    private var ids: Set<UUID> { Set(notes.map(\.id)) }
    private var results: [Note] {
        notes.filter { $0.title.localizedCaseInsensitiveContains(search) || (!$0.isLocked && $0.plainText.localizedCaseInsensitiveContains(search)) }
    }

    enum SortMode: String, CaseIterable { case manual = "Manual", recent = "Recently edited", alpha = "A to Z" }
    @AppStorage("notes.sort") private var sortRaw = SortMode.manual.rawValue
    private var sortMode: SortMode { SortMode(rawValue: sortRaw) ?? .manual }
    private var recent: [Note] { Array(notes.lazy.filter { !$0.title.isEmpty || $0.blocks.contains { !$0.text.isEmpty } }.prefix(8)) }
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
                        greeting
                            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 0, trailing: 20))
                            .listRowBackground(Color.clear)
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
                    let summaries = folderSummaries
                    let groups = workspaceGroups(summaries)
                    let unfiled = summaries.first { $0.name == nil }?.count ?? 0
                    if !groups.contains(where: { $0.name != nil }) && notes.count >= 6 {
                        Section { reorganizeBanner }
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    } else if unfiled >= 3 {
                        Section { organizeBanner(unfiled) }
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    }
                    Section { Waterline(label: "Below the waterline · your library") }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    // Notion-style page tree: workspaces → folders → pages (and pages inside pages). Tap a folder's name to open it.
                    ForEach(Array(groups.enumerated()), id: \.element.id) { i, g in
                        Section {
                            ForEach(g.folders) { f in
                                if let name = f.name {
                                    folderTreeRow(f)
                                    if expanded.contains("f:" + name) && !selectingFolders {
                                        ForEach(pages(in: name)) { n in pageTree(n, depth: 1) }
                                        if f.count == 0 {
                                            Text("Empty. Drag pages here or tap + New page inside the folder.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                                                .padding(.leading, 34)
                                        }
                                    }
                                } else {
                                    ForEach(pages(in: nil)) { n in pageTree(n, depth: 0) }
                                }
                            }
                            if !selectingFolders {
                                Button { newFolderName = ""; newFolderWorkspace = g.name; creatingFolder = true } label: {
                                    Label("New folder", systemImage: "folder.badge.plus").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                                }
                                .buttonStyle(.borderless)
                            }
                        } header: {
                            workspaceHeader(g, first: i == 0)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 10).fill(DS.Palette.accent.opacity(dropTarget == g.id ? 0.14 : 0)))
                                // Drop folders on a workspace's heading to move them into it (the whole selection, if selecting).
                                .dropDestination(for: String.self) { items, _ in
                                    moveFolders(items, to: g.name)
                                    return true
                                } isTargeted: { on in
                                    withAnimation(DS.spring) { dropTarget = on ? g.id : (dropTarget == g.id ? nil : dropTarget) }
                                }
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
            .navigationDestination(item: $opened) { NoteOrCanvas(note: $0) }
            .alert("New folder", isPresented: Binding(get: { newFolderFor != nil }, set: { if !$0 { newFolderFor = nil } })) {
                TextField("Name", text: $newFolderName)
                Button("Create") {
                    let name = newFolderName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { newFolderFor?.folder = name; removeEmptyMarker(name) }
                    newFolderFor = nil
                }
                Button("Cancel", role: .cancel) { newFolderFor = nil }
            }
            .navigationTitle("Notes")
            .keelSettingsButton()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showBrain = true } label: { Image(systemName: "brain.head.profile") }
                        .accessibilityLabel("Brain map of your notes")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }
                        .accessibilityLabel("Help with notes")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { AppRouter.shared.showQuickOpen = true } label: { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel("Jump to a page")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showReorganize = true } label: { Image(systemName: "sparkles.rectangle.stack") }
                        .accessibilityLabel("Reorganize everything into workspaces")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New page", systemImage: "doc") { newPage() }
                        Button("Ask my notes", systemImage: "text.bubble") { showAskNotes = true }
                        Button("Second-brain setup", systemImage: "square.grid.2x2") { showSetup = true }
                        Button("Brain health", systemImage: "stethoscope") { showHealth = true }
                        Button("Recently deleted", systemImage: "trash") { showTrash = true }
                        Button("New database", systemImage: "tablecells") { opened = NotesDatabase.create(title: "Untitled database", parent: nil, ctx: ctx) }
                        Button("New canvas", systemImage: "rectangle.on.rectangle.angled") { opened = KeelCanvas.create(ctx: ctx, folder: nil) }
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
                        Button("Paperwork vault", systemImage: "archivebox") { showVault = true }
                        Button("Tags & saved searches", systemImage: "number") { showTags = true }
                        Button("Reorganize everything…", systemImage: "sparkles.rectangle.stack") { showReorganize = true }
                        Button("Sort loose pages…", systemImage: "wand.and.stars") { showOrganize = true }
                        Button("Import from another app…", systemImage: "square.and.arrow.down") { showImport = true }
                    } label: { Image(systemName: "square.and.pencil") } primaryAction: { newPage() }
                    .accessibilityLabel("New page. Hold for more")
                }
            }
            .navigationDestination(isPresented: $recording) { MeetingRecorderView() }
            .navigationDestination(isPresented: $showBrain) { BrainHomeView() }      // the brain map, unchanged, on top of your second-brain home
            .navigationDestination(isPresented: $showImport) { ImportView() }
            .sheet(isPresented: $showOrganize) { OrganizeNotesView() }
            .navigationDestination(item: $openFolder) { ref in folderPage(ref).navigationTransition(.zoom(sourceID: "f" + ref.id, in: zoom)) }
            .alert("New folder", isPresented: $creatingFolder) {
                TextField("Name", text: $newFolderName)
                Button("Create") { addEmptyFolder(NotePath.make(newFolderWorkspace, newFolderName)) }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Rename folder", isPresented: Binding(get: { renamingFolder != nil }, set: { if !$0 { renamingFolder = nil } })) {
                TextField("Name", text: $newFolderName)
                Button("Rename") { if let old = renamingFolder { renameFolder(old, to: NotePath.make(NotePath.workspace(old), newFolderName)) }; renamingFolder = nil }
                Button("Cancel", role: .cancel) { renamingFolder = nil }
            }
            .alert("Rename workspace", isPresented: Binding(get: { renamingWorkspace != nil }, set: { if !$0 { renamingWorkspace = nil } })) {
                TextField("Name", text: $newFolderName)
                Button("Rename") { if let old = renamingWorkspace { renameWorkspace(old, to: newFolderName) }; renamingWorkspace = nil }
                Button("Cancel", role: .cancel) { renamingWorkspace = nil }
            }
            .sheet(isPresented: $showReorganize) { ReorganizeNotesView() }
            .safeAreaInset(edge: .bottom) {
                if selectingFolders {
                    HStack {
                        Text(selectedFolders.isEmpty ? "Tap folders, or drag one into a section" : "\(selectedFolders.count) selected")
                            .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        Spacer()
                        Menu {
                            ForEach(workspaceNames, id: \.self) { w in
                                Button("\(NotePath.icon(for: w)) \(w)") { moveFolders(Array(selectedFolders), to: w) }
                            }
                            Button("No workspace", systemImage: "folder") { moveFolders(Array(selectedFolders), to: nil) }
                            Divider()
                            Button("New workspace…", systemImage: "plus.rectangle.on.rectangle") { newFolderName = ""; namingWorkspaceForMove = true }
                        } label: {
                            Label("Move to…", systemImage: "arrow.right.doc.on.clipboard").font(DS.Font.headline)
                        }
                        .disabled(selectedFolders.isEmpty)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.bar)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .alert("New workspace", isPresented: $namingWorkspaceForMove) {
                TextField("Name, like Work or Faith", text: $newFolderName)
                Button("Move \(selectedFolders.count) here") { moveFolders(Array(selectedFolders), to: newFolderName) }
                Button("Cancel", role: .cancel) {}
            }
            .navigationDestination(isPresented: $showHelp) { HelpCenterView(area: .notes) }
            .navigationDestination(isPresented: $showVault) { VaultView() }
            .navigationDestination(isPresented: $showTags) { TagBrowserView() }
            .task { await NotesOrganizer.autoFile(ctx: ctx) }
            .navigationDestination(isPresented: $showAskNotes) { AskNotesView() }
            .navigationDestination(isPresented: $showSetup) { StarterSetupView() }
            .navigationDestination(isPresented: $showHealth) { BrainHealthView() }
            .navigationDestination(isPresented: $showTrash) { TrashView() }
        }
    }

    @State private var recording = false
    @State private var showBrain = false
    @State private var showImport = false
    @State private var showOrganize = false
    @State private var openFolder: FolderRef?
    @Namespace private var zoom          // folder cards grow into the folder
    @State private var renamingFolder: String?
    @State private var creatingFolder = false
    @State private var newFolderWorkspace: String?
    @State private var selectingFolders = false
    @State private var selectedFolders: Set<String> = []
    @State private var dropTarget: String?
    @State private var namingWorkspaceForMove = false
    @State private var renamingWorkspace: String?
    @State private var showReorganize = false
    @State private var showHelp = false
    @State private var showVault = false
    @State private var showTags = false
    @State private var showAskNotes = false
    @State private var showSetup = false
    @State private var showHealth = false
    @State private var showTrash = false
    @AppStorage("notes.emptyFolders") private var emptyFoldersRaw = ""      // folders you made that have no pages yet

    // MARK: Pieces

    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s) {
                QuickTile(title: "New page", icon: "square.and.pencil", color: DS.Palette.accent) { newPage() }
                QuickTile(title: "Today", icon: "calendar", color: .orange) { opened = DailyNote.today(ctx) }
                QuickTile(title: "Record", icon: "waveform.badge.mic", color: .red) { recording = true }
                QuickTile(title: "Capture", icon: "tray.and.arrow.down.fill", color: .blue) { AppRouter.shared.openTool = ToolRoute(id: "capture") }
                QuickTile(title: "Import", icon: "square.and.arrow.down.on.square.fill", color: .gray) { showImport = true }
                QuickTile(title: "Journal", icon: "book.fill", color: .pink) { createJournalPage() }
                QuickTile(title: "Second brain", icon: "brain.head.profile.fill", color: .pink) { showBrain = true }
                QuickTile(title: "Vault", icon: "archivebox.fill", color: .brown) { showVault = true }
                QuickTile(title: "Canvas", icon: "rectangle.on.rectangle.angled.fill", color: .teal) { opened = KeelCanvas.create(ctx: ctx, folder: nil) }
                QuickTile(title: "Reorganize", icon: "sparkles.rectangle.stack.fill", color: .indigo) { showReorganize = true }
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
            } header: {
                HStack {
                    sectionHeader("\(results.count) result\(results.count == 1 ? "" : "s")", nil)
                    Spacer()
                    Button(KeelTags.saved.contains(search) ? "Saved" : "Save search") {
                        if !KeelTags.saved.contains(search) { KeelTags.saved = [search] + KeelTags.saved; Haptics.tap() }
                    }
                    .font(DS.Font.caption).textCase(nil).buttonStyle(.borderless)
                }
            }
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
            if multiWindow {
                Button("Open in New Window", systemImage: "macwindow.badge.plus") { openWindow(id: "note", value: n.id) }
            }
            Button(n.isPinned ? "Remove from Favorites" : "Add to Favorites", systemImage: n.isPinned ? "star.slash" : "star") { n.isPinned.toggle() }
            Button("Add page inside", systemImage: "doc.badge.plus") {
                let c = Note(title: ""); c.parentId = n.id; ctx.insert(c); opened = c
            }
            Menu("Move to Folder", systemImage: "folder") {
                Button("No folder") { n.folder = nil }
                ForEach(folders, id: \.self) { f in Button(f.replacingOccurrences(of: "/", with: " › ")) { n.folder = f } }
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
        NoteTrash.delete(n, ctx: ctx)            // kept in Recently deleted for 30 days
        UndoCenter.shared.notify("Moved to Recently deleted")
        Haptics.tap()
    }

    private func create(_ n: Note) {
        ctx.insert(n); Haptics.tap()
        opened = n
    }

    private func subtitle(_ n: Note, children: Int) -> String {
        var parts = ["Edited " + n.updatedAt.formatted(.relative(presentation: .named))]
        if n.isDatabase { parts.append("\(children) row\(children == 1 ? "" : "s")") }
        else if children > 0 { parts.append("\(children) page\(children == 1 ? "" : "s") inside") }
        if let f = n.folder, openFolder == nil { parts.append(f.replacingOccurrences(of: "/", with: " › ")) }
        return parts.joined(separator: " · ")
    }

    // MARK: Folders

    private var folderSummaries: [FolderSummary] {
        let all = ids
        let tops = notes.filter { $0.parentId == nil || !all.contains($0.parentId!) }
        let grouped = Dictionary(grouping: tops, by: { $0.folder ?? "" })
        var out = folders.map { f -> FolderSummary in
            let pages = (grouped[f] ?? []).sorted { $0.updatedAt > $1.updatedAt }
            return FolderSummary(name: f, count: pages.count, updated: pages.first?.updatedAt, recent: pages.prefix(2).map { $0.title.isEmpty ? "Untitled" : $0.title })
        }
        let loose = (grouped[""] ?? []).sorted { $0.updatedAt > $1.updatedAt }
        if !loose.isEmpty || folders.isEmpty {
            out.append(FolderSummary(name: nil, count: loose.count, updated: loose.first?.updatedAt, recent: loose.prefix(2).map { $0.title.isEmpty ? "Untitled" : $0.title }))
        }
        return out
    }

    private func pages(in folder: String?) -> [Note] {
        let all = ids
        let base = notes.filter { ($0.parentId == nil || !all.contains($0.parentId!)) && $0.folder == folder }
        switch sortMode {
        case .manual: return base.sorted { ($0.sortIndex, $1.updatedAt) < ($1.sortIndex, $0.updatedAt) }
        case .recent: return base.sorted { $0.updatedAt > $1.updatedAt }
        case .alpha: return base.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    @ViewBuilder private func folderPage(_ ref: FolderRef) -> some View {
        let list = pages(in: ref.name)
        List {
            if ref.name == nil && list.count >= 2 {
                Section { organizeBanner(list.count) }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }
            Section {
                ForEach(list) { root in PageTreeNode(note: root, all: notes, depth: 0, row: { page in row(page, showSnippet: true) }) }
                Button {
                    let n = Note(title: "")
                    n.folder = ref.name
                    if let f = ref.name { removeEmptyMarker(f) }
                    create(n)
                } label: {
                    Label("New page", systemImage: "plus").font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
                }
            } header: {
                HStack {
                    sectionHeader("\(list.count) page\(list.count == 1 ? "" : "s")", nil)
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
        }
        .listStyle(.insetGrouped)
        .overlay {
            if list.isEmpty {
                ContentUnavailableView(ref.name == nil ? "Everything's filed" : "Empty folder", systemImage: "folder",
                                       description: Text(ref.name == nil ? "Pages without a folder show up here." : "Tap New page, or move pages here from their ⋯ menu."))
            }
        }
        .navigationTitle(ref.name.map(NotePath.leaf) ?? "Unfiled")
        .toolbar {
            if let name = ref.name {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Rename", systemImage: "pencil") { newFolderName = NotePath.leaf(name); renamingFolder = name }
                        Button("Remove Folder (Keeps Pages)", systemImage: "folder.badge.minus", role: .destructive) { removeFolder(name); openFolder = nil }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Folder options")
                }
            }
        }
    }

    // MARK: Workspaces

    struct WorkspaceGroup: Identifiable {
        let name: String?              // nil = folders that aren't in a workspace, plus Unfiled
        let folders: [FolderSummary]
        var id: String { name ?? "\u{0}plain" }
        var pages: Int { folders.reduce(0) { $0 + $1.count } }
    }

    private func workspaceGroups(_ summaries: [FolderSummary]) -> [WorkspaceGroup] {
        let grouped = Dictionary(grouping: summaries, by: { $0.name.flatMap(NotePath.workspace) ?? "" })
        var out = grouped.keys.filter { !$0.isEmpty }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { WorkspaceGroup(name: $0, folders: grouped[$0] ?? []) }
        let plain = (grouped[""] ?? []).sorted { a, b in a.name == nil ? false : b.name == nil ? true : (a.name ?? "") < (b.name ?? "") }
        if !plain.isEmpty || out.isEmpty { out.append(WorkspaceGroup(name: nil, folders: plain)) }
        return out
    }

    private func workspaceHeader(_ g: WorkspaceGroup, first: Bool = false) -> some View {
        HStack(spacing: 8) {
            if let name = g.name {
                Text(NotePath.icon(for: name)).font(.title3)
                Text(name).font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
            } else {
                Text(folders.contains(where: { NotePath.workspace($0) != nil }) ? "Other folders" : "Folders").font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
            }
            Spacer()
            Text("\(g.pages) page\(g.pages == 1 ? "" : "s")").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            if first {
                Button(selectingFolders ? "Done" : "Select") {
                    withAnimation(DS.spring) { selectingFolders.toggle(); selectedFolders = [] }
                }
                .font(DS.Font.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .accessibilityHint("Pick several folders to move together")
            }
            if let name = g.name {
                Menu {
                    Button("Rename Workspace", systemImage: "pencil") { newFolderName = name; renamingWorkspace = name }
                    Button("Remove Workspace (Keeps Folders)", systemImage: "rectangle.stack.badge.minus", role: .destructive) { removeWorkspace(name) }
                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(DS.Palette.inkSoft) }
                .accessibilityLabel("\(name) workspace options")
            }
        }
        .textCase(nil)
    }

    // MARK: Notion-style home

    /// Pages inside pages, worked out once per screen update (not once per row), so big libraries stay instant.
    private final class TreeMemo { var kids: [UUID: [Note]]?; var stamp = "" }
    private let treeMemo = TreeMemo()
    private var childMap: [UUID: [Note]] {
        let stamp = "\(allNotes.count)|\(allNotes.first?.updatedAt.timeIntervalSince1970 ?? 0)"
        if let k = treeMemo.kids, treeMemo.stamp == stamp { return k }
        let k = Dictionary(grouping: notes.filter { $0.parentId != nil }, by: { $0.parentId! })
            .mapValues { $0.sorted { ($0.sortIndex, $1.updatedAt) < ($1.sortIndex, $0.updatedAt) } }
        treeMemo.kids = k; treeMemo.stamp = stamp
        return k
    }

    @AppStorage("notes.tree.expanded") private var expandedRaw = ""
    private var expanded: Set<String> { Set(expandedRaw.split(separator: "\n").map(String.init)) }
    private func toggleExpanded(_ key: String) {
        var e = expanded
        if e.contains(key) { e.remove(key) } else { e.insert(key) }
        withAnimation(DS.spring) { expandedRaw = e.sorted().joined(separator: "\n") }
        Haptics.tap()
    }

    private var greeting: some View {
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
        let name = KeelAccount.shared.name.split(separator: " ").first.map(String.init) ?? ""
        return HorizonHeader(title: name.isEmpty ? part : "\(part), \(name)",
                             detail: "\(notes.count) page\(notes.count == 1 ? "" : "s")\(editedToday > 0 ? " · \(editedToday) edited today" : "")",
                             compact: true)
    }

    /// One folder in the tree: chevron to open it in place, name to go into it.
    private func folderTreeRow(_ f: FolderSummary) -> some View {
        let name = f.name ?? ""
        let open = expanded.contains("f:" + name)
        let picked = selectedFolders.contains(name)
        return HStack(spacing: 10) {
            if selectingFolders {
                Image(systemName: picked ? "checkmark.circle.fill" : "circle").foregroundStyle(picked ? DS.Palette.accent : DS.Palette.inkSoft)
            } else {
                Button { toggleExpanded("f:" + name) } label: {
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(DS.Palette.inkSoft)
                        .rotationEffect(.degrees(open ? 90 : 0)).frame(width: 18, height: 28)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(open ? "Collapse \(NotePath.leaf(name))" : "Expand \(NotePath.leaf(name))")
            }
            Image(systemName: f.style.icon).foregroundStyle(f.style.color).frame(width: 22)
            Text(NotePath.leaf(name)).font(DS.Font.body).foregroundStyle(DS.Palette.ink).lineLimit(1)
            Spacer()
            Text("\(f.count)").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).monospacedDigit()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selectingFolders {
                withAnimation(DS.spring) { if picked { selectedFolders.remove(name) } else { selectedFolders.insert(name) } }
                Haptics.tap()
            } else {
                openFolder = FolderRef(name: f.name); Haptics.tap()
            }
        }
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
        .modifier(FolderDrag(path: f.name, count: picked ? selectedFolders.count : 1))
        .matchedTransitionSource(id: "f" + f.id, in: zoom)
        .contextMenu {
            Button(open ? "Collapse" : "Expand", systemImage: open ? "chevron.up" : "chevron.down") { toggleExpanded("f:" + name) }
            Button("Rename", systemImage: "pencil") { newFolderName = NotePath.leaf(name); renamingFolder = name }
            Button("Remove Folder (Keeps Pages)", systemImage: "folder.badge.minus", role: .destructive) { removeFolder(name) }
        }
    }

    /// A page in the tree, with the pages inside it one tap away (databases open as tables instead).
    private func pageTree(_ n: Note, depth: Int) -> AnyView {
        let kids = n.isDatabase ? [] : (childMap[n.id] ?? [])
        let open = expanded.contains("p:" + n.id.uuidString)
        return AnyView(Group {
            HStack(spacing: 6) {
                if !kids.isEmpty {
                    Button { toggleExpanded("p:" + n.id.uuidString) } label: {
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(DS.Palette.inkSoft)
                            .rotationEffect(.degrees(open ? 90 : 0)).frame(width: 16, height: 26)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(open ? "Hide pages inside" : "Show pages inside")
                } else {
                    Color.clear.frame(width: 16, height: 1)
                }
                row(n, showSnippet: false)
            }
            .padding(.leading, CGFloat(depth) * 18)
            if open && depth < 6 {
                ForEach(kids) { k in pageTree(k, depth: depth + 1) }
            }
        })
    }

    private func folderCard(_ f: FolderSummary) -> some View {
        let picked = f.name.map { selectedFolders.contains($0) } ?? false
        return FolderCard(summary: f) {
            if selectingFolders {
                guard let name = f.name else { return }
                withAnimation(DS.spring) { if picked { selectedFolders.remove(name) } else { selectedFolders.insert(name) } }
                Haptics.tap()
            } else {
                openFolder = FolderRef(name: f.name); Haptics.tap()
            }
        }
            .overlay(alignment: .topLeading) {
                if selectingFolders && f.name != nil {
                    Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(picked ? DS.Palette.accent : DS.Palette.inkSoft)
                        .background(Circle().fill(DS.Palette.canvas).padding(2))
                        .offset(x: -6, y: -6)
                        .accessibilityHidden(true)
                }
            }
            .opacity(selectingFolders && f.name == nil ? 0.4 : 1)
            .accessibilityAddTraits(picked ? .isSelected : [])
            .modifier(FolderDrag(path: f.name, count: picked ? selectedFolders.count : 1))
            .matchedTransitionSource(id: "f" + f.id, in: zoom)
            .contextMenu {
                if let name = f.name {
                    Button("Rename", systemImage: "pencil") { newFolderName = NotePath.leaf(name); renamingFolder = name }
                    Button("Remove Folder (Keeps Pages)", systemImage: "folder.badge.minus", role: .destructive) { removeFolder(name) }
                } else if f.count > 0 {
                    Button("Sort into folders…", systemImage: "wand.and.stars") { showOrganize = true }
                }
            }
    }

    private var reorganizeBanner: some View {
        Button { showReorganize = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack.fill").font(.title3.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Color.indigo.gradient, in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Organize everything into workspaces").font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                    Text("Keel designs workspaces and folders for your notes. You approve.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var workspaceNames: [String] {
        Array(Set(folders.compactMap(NotePath.workspace))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Moves folders (and every page in them) into a workspace, or out of any workspace when `workspace` is nil.
    /// Dropping one folder from a selection moves the whole selection.
    private func moveFolders(_ dropped: [String], to workspace: String?) {
        var paths = Set(dropped.filter { !$0.isEmpty })
        if !paths.isDisjoint(with: selectedFolders) { paths.formUnion(selectedFolders) }
        let target = workspace?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        let ws = (target?.isEmpty ?? true) ? nil : target
        var moved = 0
        for old in paths {
            let new = NotePath.make(ws, NotePath.leaf(old))
            guard new != old else { continue }
            for n in allNotes where n.folder == old { n.folder = new }
            emptyFoldersRaw = emptyFolders.map { $0 == old ? new : $0 }.joined(separator: "\n")
            moved += 1
        }
        guard moved > 0 else { return }
        try? ctx.save()
        Haptics.success()
        withAnimation(DS.spring) { selectedFolders = []; selectingFolders = false; dropTarget = nil }
    }

    private func renameWorkspace(_ old: String, to raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !name.isEmpty, name != old else { return }
        for n in allNotes { if let f = n.folder, NotePath.workspace(f) == old { n.folder = NotePath.make(name, NotePath.leaf(f)) } }
        emptyFoldersRaw = emptyFolders.map { NotePath.workspace($0) == old ? NotePath.make(name, NotePath.leaf($0)) : $0 }.joined(separator: "\n")
        var icons = NotePath.icons
        if let e = icons.removeValue(forKey: old) { icons[name] = e }
        NotePath.icons = icons
        try? ctx.save()
        Haptics.tap()
    }

    /// The folders stay (without the workspace); no page is deleted.
    private func removeWorkspace(_ name: String) {
        for n in allNotes { if let f = n.folder, NotePath.workspace(f) == name { n.folder = NotePath.leaf(f) } }
        emptyFoldersRaw = emptyFolders.map { NotePath.workspace($0) == name ? NotePath.leaf($0) : $0 }.joined(separator: "\n")
        try? ctx.save()
        Haptics.tap()
    }

    private func organizeBanner(_ count: Int) -> some View {
        Button { showOrganize = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "wand.and.stars").font(.title3.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Color.indigo.gradient, in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sort \(count) loose page\(count == 1 ? "" : "s")").font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                    Text("Keel suggests a folder for each. You approve.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addEmptyFolder(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !folders.contains(name) else { return }
        emptyFoldersRaw = (emptyFolders + [name]).joined(separator: "\n")
        Haptics.tap()
    }

    private func removeEmptyMarker(_ name: String) {
        emptyFoldersRaw = emptyFolders.filter { $0 != name }.joined(separator: "\n")
    }

    private func renameFolder(_ old: String, to raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != old else { return }
        for n in allNotes where n.folder == old { n.folder = name }
        emptyFoldersRaw = emptyFolders.map { $0 == old ? name : $0 }.joined(separator: "\n")
        if openFolder?.name == old { openFolder = FolderRef(name: name) }
        try? ctx.save()
        Haptics.tap()
    }

    private func removeFolder(_ name: String) {
        for n in allNotes where n.folder == name { n.folder = nil }
        removeEmptyMarker(name)
        try? ctx.save()
        Haptics.tap()
    }

    /// A fresh copy of a template, with {{date}} filled in.
    private func create(fromTemplate t: Note) {
        // {{date}}, {{weekday}}, {{time}}, {{week}} and {{title}} are filled in; the page lands in the template's folder.
        let n = SmartTemplates.instantiate(t, ctx: ctx)
        Haptics.tap()
        AppRouter.shared.openNoteId = n.id
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
            .frame(minWidth: 92, alignment: .leading)
            .padding(12)
            .background(DS.Palette.elevated, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
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

struct FolderRef: Hashable, Identifiable {
    let name: String?             // nil = Unfiled
    var id: String { name ?? "\u{0}unfiled" }
}

struct FolderSummary: Identifiable {
    let name: String?
    let count: Int
    let updated: Date?
    let recent: [String]
    var id: String { name ?? "\u{0}unfiled" }

    /// An icon and colour that fit the folder's name, the same every time.
    var style: (icon: String, color: Color) {
        guard let n = name.map(NotePath.leaf)?.lowercased() else { return ("tray.fill", .gray) }
        let map: [(String, String, Color)] = [
            ("work", "briefcase.fill", .blue), ("job", "briefcase.fill", .blue), ("meeting", "person.2.fill", .teal),
            ("health", "heart.fill", .pink), ("food", "fork.knife", .green), ("recipe", "fork.knife", .orange), ("diet", "leaf.fill", .green),
            ("journal", "book.fill", .purple), ("diary", "book.fill", .purple), ("idea", "lightbulb.fill", .yellow),
            ("money", "dollarsign.circle.fill", .green), ("finance", "dollarsign.circle.fill", .green), ("bill", "creditcard.fill", .green),
            ("travel", "airplane", .cyan), ("trip", "airplane", .cyan), ("family", "house.fill", .orange), ("home", "house.fill", .orange),
            ("school", "graduationcap.fill", .indigo), ("class", "graduationcap.fill", .indigo), ("church", "book.closed.fill", .brown),
            ("bible", "book.closed.fill", .brown), ("faith", "book.closed.fill", .brown), ("project", "folder.fill.badge.gearshape", .indigo),
            ("read", "books.vertical.fill", .brown), ("book", "books.vertical.fill", .brown), ("personal", "person.fill", .mint),
        ]
        if let hit = map.first(where: { n.contains($0.0) }) { return (hit.1, hit.2) }
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .orange, .teal, .green, .mint, .cyan]
        let seed = n.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return ("folder.fill", palette[seed % palette.count])
    }
}

/// A folder on the Notes home: icon, name, page count and the latest pages inside.
private struct FolderCard: View {
    let summary: FolderSummary
    let open: () -> Void

    var body: some View {
        let style = summary.style
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: style.icon).font(.title3.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: 38, height: 38).background(style.color.gradient, in: .rect(cornerRadius: 11))
                    Spacer()
                    Text("\(summary.count)").font(DS.Font.headline.monospacedDigit()).foregroundStyle(DS.Palette.inkSoft)
                }
                Text(summary.name.map(NotePath.leaf) ?? "Unfiled").font(DS.Font.headline).foregroundStyle(DS.Palette.ink).lineLimit(1)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(summary.recent.enumerated()), id: \.offset) { item in
                        Text(item.element).font(.caption2).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                    }
                    if summary.recent.isEmpty { Text("Empty").font(.caption2).foregroundStyle(DS.Palette.inkSoft) }
                }
                .frame(minHeight: 30, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .padding(14)
            .background(DS.Palette.elevated, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(style.color.opacity(0.18)))
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(PressStyle()).hoverEffect(.lift)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.name.map(NotePath.leaf) ?? "Unfiled"), \(summary.count) pages")
        .accessibilityAddTraits(.isButton)
    }
}

private struct NewFolderCard: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "folder.badge.plus").font(.title2).foregroundStyle(DS.Palette.accent)
                Text("New folder").font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.ink)
            }
            .frame(maxWidth: .infinity, minHeight: 132)
            .background(RoundedRectangle(cornerRadius: 18).strokeBorder(DS.Palette.inkSoft.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(PressStyle()).hoverEffect(.lift)
    }
}

/// Press and hold a folder card to drag it into another section. The drag preview shows how many are moving.
private struct FolderDrag: ViewModifier {
    let path: String?
    let count: Int
    func body(content: Content) -> some View {
        if let path {
            content.draggable(path) {
                Label(count > 1 ? "\(count) folders" : NotePath.leaf(path), systemImage: count > 1 ? "folder.fill.badge.plus" : "folder.fill")
                    .font(DS.Font.headline)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
            }
        } else {
            content
        }
    }
}
