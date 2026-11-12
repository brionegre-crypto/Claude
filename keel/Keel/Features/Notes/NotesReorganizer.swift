import SwiftUI
import SwiftData
import FoundationModels

/// Folder paths: "Workspace/Folder". A folder with no "/" is a plain folder (no workspace).
enum NotePath {
    static func workspace(_ path: String) -> String? {
        let parts = path.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let w = parts[0].trimmingCharacters(in: .whitespaces)
        return w.isEmpty ? nil : w
    }
    static func leaf(_ path: String) -> String {
        let parts = path.split(separator: "/", maxSplits: 1)
        return (parts.last.map(String.init) ?? path).trimmingCharacters(in: .whitespaces)
    }
    static func make(_ workspace: String?, _ folder: String) -> String {
        let f = folder.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        guard let w = workspace?.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces), !w.isEmpty else { return f }
        return f.isEmpty ? w : "\(w)/\(f)"
    }

    /// Emoji for each workspace, remembered on this iPhone.
    static let iconsKey = "notes.workspaceIcons"
    static var icons: [String: String] {
        get { (UserDefaults.standard.dictionary(forKey: iconsKey) as? [String: String]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: iconsKey) }
    }
    static func icon(for workspace: String) -> String {
        if let e = icons[workspace] { return e }
        let w = workspace.lowercased()
        let map: [(String, String)] = [("work", "💼"), ("job", "💼"), ("business", "🏢"), ("personal", "🏡"), ("home", "🏡"), ("family", "👨‍👩‍👧"),
                                       ("faith", "🙏"), ("church", "⛪️"), ("bible", "📖"), ("health", "💪"), ("fitness", "🏋️"), ("money", "💰"),
                                       ("finance", "💰"), ("school", "🎓"), ("learning", "📚"), ("study", "📚"), ("creative", "🎨"), ("ideas", "💡"),
                                       ("projects", "🚀"), ("travel", "✈️"), ("food", "🍽️"), ("archive", "🗄️"), ("side", "🛠️")]
        return map.first { w.contains($0.0) }?.1 ?? "🗂️"
    }
}

/// Reorganizes the whole Notes section: designs workspaces with subject folders, then places every page.
/// Claude (when connected) reads everything in one pass; otherwise Apple Intelligence does it on the iPhone,
/// and without either, Keel groups by common subjects. Nothing moves until you approve, and it can be undone.
@MainActor
enum NotesReorganizer {
    struct Workspace: Identifiable, Hashable {
        var id = UUID()
        var name: String
        var icon: String
        var folders: [String]
    }
    struct Move: Identifiable, Hashable {
        let id: UUID                 // note id
        let title: String
        let from: String?
        var to: String               // "Workspace/Folder"
        var include = true
    }
    struct Plan {
        var workspaces: [Workspace]
        var moves: [Move]
        var engine: String
    }

    static let undoKey = "notes.reorg.undo"
    static var canUndo: Bool { UserDefaults.standard.data(forKey: undoKey) != nil }

    /// Pages that can be moved: top-level, not templates, not locked.
    static func candidates(_ notes: [Note], includeFiled: Bool) -> [Note] {
        let ids = Set(notes.map(\.id))
        return notes.filter { n in
            !n.isTemplate && !n.isLocked && (n.parentId == nil || !ids.contains(n.parentId!)) && (includeFiled || n.folder == nil)
        }
    }

    static func plan(for pages: [Note], existingFolders: [String], progress: @escaping (String, Double) -> Void) async -> Plan {
        if AIRouter.shared.cloudEnabled, let p = await cloudPlan(pages, existing: existingFolders, progress: progress) { return p }
        if AIRouter.shared.onDeviceAvailable, let p = await onDevicePlan(pages, existing: existingFolders, progress: progress) { return p }
        return basicPlan(pages)
    }

    // MARK: Claude

    private static func listing(_ pages: [Note], snippet: Int) -> String {
        pages.enumerated().map { i, n in
            let body = n.plainText.replacingOccurrences(of: "\n", with: " ").prefix(snippet)
            return "\(i). \(n.title.isEmpty ? "Untitled" : n.title)\(n.isDatabase ? " [database]" : "") — \(body)"
        }.joined(separator: "\n")
    }

    private static let designBrief = """
    Organize this person's notes like a well-kept Notion workspace. Create 2 to 6 workspaces for the big areas of their life \
    (for example Work, Personal, Faith, Health, Money, School, Side projects) and inside each, 2 to 8 folders for specific subjects \
    or projects. Use short, clear names (1 to 3 words) and one emoji per workspace. Reuse their existing folder names when they fit. \
    Put every note in exactly one workspace and folder. Don't make a folder for a single note unless it clearly stands alone.
    """

    private static func cloudPlan(_ pages: [Note], existing: [String], progress: @escaping (String, Double) -> Void) async -> Plan? {
        progress("Claude is reading your notes…", 0.2)
        let batch = Array(pages.prefix(600))
        let user = "EXISTING FOLDERS: \(existing.isEmpty ? "none" : existing.joined(separator: ", "))\n\nNOTES:\n" + listing(batch, snippet: batch.count > 300 ? 60 : 140)
        guard let r = try? await AIRouter.shared.cloud.reorganize(system: designBrief, user: user) else { return nil }
        progress("Building your workspaces…", 0.9)
        var spaces = r.workspaces.map { Workspace(name: clean($0.name), icon: $0.emoji.isEmpty ? NotePath.icon(for: $0.name) : $0.emoji, folders: $0.folders.map(clean)) }
        var moves: [Move] = []
        for a in r.assignments where a.index >= 0 && a.index < batch.count {
            let n = batch[a.index]
            moves.append(Move(id: n.id, title: n.title.isEmpty ? "Untitled" : n.title, from: n.folder, to: NotePath.make(clean(a.workspace), clean(a.folder))))
        }
        ensureListed(&spaces, moves: moves)
        return Plan(workspaces: spaces, moves: moves, engine: "Claude")
    }

    // MARK: Apple Intelligence

    @Generable
    struct WorkspaceOut {
        @Guide(description: "Workspace name, 1 to 3 words, like Work, Personal, Faith, Health") var name: String
        @Guide(description: "One emoji for the workspace") var emoji: String
        @Guide(description: "Folder names inside it for specific subjects or projects, 1 to 3 words each", .maximumCount(7)) var folders: [String]
    }
    @Generable
    struct TaxonomyOut {
        @Guide(description: "2 to 6 workspaces covering all the notes", .maximumCount(6)) var workspaces: [WorkspaceOut]
    }
    @Generable
    struct PlaceOut {
        @Guide(description: "The best location for the note, copied exactly from the list, in the form Workspace/Folder") var path: String
    }

    private static func onDevicePlan(_ pages: [Note], existing: [String], progress: @escaping (String, Double) -> Void) async -> Plan? {
        progress("Apple Intelligence is designing your workspaces…", 0.05)
        let titles = pages.prefix(120).map { String(($0.title.isEmpty ? String($0.plainText.prefix(40)) : $0.title).prefix(45)) }
        let session = LanguageModelSession(instructions: designBrief)
        let prompt = "Existing folders: \(existing.prefix(20).joined(separator: ", "))\nNote titles:\n" + titles.map { "- \($0)" }.joined(separator: "\n")
        guard let tax = try? await session.respond(to: prompt, generating: TaxonomyOut.self).content, !tax.workspaces.isEmpty else { return nil }
        var spaces = tax.workspaces.map { Workspace(name: clean($0.name), icon: $0.emoji.isEmpty ? NotePath.icon(for: $0.name) : $0.emoji,
                                                    folders: $0.folders.map(clean).filter { !$0.isEmpty }) }
        spaces = spaces.filter { !$0.name.isEmpty }
        let paths = spaces.flatMap { w in w.folders.isEmpty ? [w.name] : w.folders.map { NotePath.make(w.name, $0) } }
        guard !paths.isEmpty else { return nil }
        let pathList = paths.joined(separator: "\n")
        var moves: [Move] = []
        for (i, n) in pages.enumerated() {
            if i % 3 == 0 { progress("Placing \(i + 1) of \(pages.count)…", 0.15 + 0.8 * Double(i) / Double(max(1, pages.count))) }
            let s = LanguageModelSession(instructions: "Pick where this note belongs. Choose one location from this list, exactly as written:\n" + pathList)
            let text = "Title: \(n.title)\n\(n.plainText.prefix(500))"
            var dest = (try? await s.respond(to: text, generating: PlaceOut.self).content.path).flatMap { closest($0, in: paths) }
            if dest == nil { dest = wordMatch(n, paths: paths) }
            moves.append(Move(id: n.id, title: n.title.isEmpty ? "Untitled" : n.title, from: n.folder, to: dest ?? paths[0]))
        }
        ensureListed(&spaces, moves: moves)
        return Plan(workspaces: spaces, moves: moves, engine: "Apple Intelligence")
    }

    // MARK: Without AI

    private static let subjects: [(String, String, [String])] = [
        ("Work", "Meetings", ["meeting", "agenda", "standup", "1:1", "minutes", "attendees"]),
        ("Work", "Projects", ["project", "client", "deadline", "proposal", "roadmap", "launch"]),
        ("Work", "Ideas", ["idea", "brainstorm", "what if", "someday"]),
        ("Personal", "Journal", ["journal", "today i", "grateful", "mood", "dear diary"]),
        ("Personal", "Health", ["doctor", "medication", "symptom", "workout", "diet", "sleep", "therapy"]),
        ("Personal", "Money", ["budget", "invoice", "payment", "bill", "expense", "tax", "bank"]),
        ("Personal", "Recipes", ["recipe", "ingredients", "tbsp", "teaspoon", "oven", "bake"]),
        ("Personal", "Travel", ["flight", "hotel", "trip", "itinerary", "packing"]),
        ("Faith", "Bible study", ["bible", "scripture", "verse", "psalm", "prayer", "sermon", "church", "god", "jesus"]),
        ("Learning", "Courses", ["lecture", "class", "course", "chapter", "homework", "exam", "notes on"]),
    ]

    private static func basicPlan(_ pages: [Note]) -> Plan {
        var moves: [Move] = []
        for n in pages {
            let t = (n.title + " " + String(n.plainText.prefix(1500))).lowercased()
            let best = subjects.map { s in (s, s.2.filter { t.contains($0) }.count) }.max { $0.1 < $1.1 }
            let path: String
            if n.linkedEventId != nil { path = "Work/Meetings" }
            else if let b = best, b.1 >= 1 { path = NotePath.make(b.0.0, b.0.1) }
            else { path = n.folder.map { NotePath.make("Personal", NotePath.leaf($0)) } ?? "Personal/Notes" }
            moves.append(Move(id: n.id, title: n.title.isEmpty ? "Untitled" : n.title, from: n.folder, to: path))
        }
        var spaces: [Workspace] = []
        ensureListed(&spaces, moves: moves)
        return Plan(workspaces: spaces, moves: moves, engine: "Keel's subject matching")
    }

    // MARK: Helpers

    private static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'.#*-")))
            .replacingOccurrences(of: "/", with: "-")
    }

    /// Matches what the model wrote to a real path (exact, then by folder name).
    private static func closest(_ raw: String, in paths: [String]) -> String? {
        let r = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'."))).lowercased()
        if let p = paths.first(where: { $0.lowercased() == r }) { return p }
        let leaf = NotePath.leaf(r)
        return paths.first { NotePath.leaf($0).lowercased() == leaf }
    }

    private static func wordMatch(_ n: Note, paths: [String]) -> String? {
        let words = Set((n.title + " " + String(n.plainText.prefix(800))).lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count > 3 })
        return paths.max { a, b in
            Set(a.lowercased().split { !$0.isLetter }.map(String.init)).intersection(words).count <
            Set(b.lowercased().split { !$0.isLetter }.map(String.init)).intersection(words).count
        }
    }

    /// Every destination appears in the workspace list (the model sometimes invents one while placing).
    private static func ensureListed(_ spaces: inout [Workspace], moves: [Move]) {
        for m in moves {
            let w = NotePath.workspace(m.to) ?? m.to
            let f = NotePath.workspace(m.to) == nil ? "" : NotePath.leaf(m.to)
            if let i = spaces.firstIndex(where: { $0.name.caseInsensitiveCompare(w) == .orderedSame }) {
                if !f.isEmpty && !spaces[i].folders.contains(where: { $0.caseInsensitiveCompare(f) == .orderedSame }) { spaces[i].folders.append(f) }
            } else {
                spaces.append(Workspace(name: w, icon: NotePath.icon(for: w), folders: f.isEmpty ? [] : [f]))
            }
        }
        // Drop empty folders the model proposed but used for nothing.
        let used = Set(moves.map { $0.to.lowercased() })
        for i in spaces.indices {
            spaces[i].folders = spaces[i].folders.filter { used.contains(NotePath.make(spaces[i].name, $0).lowercased()) }
        }
        spaces = spaces.filter { w in moves.contains { (NotePath.workspace($0.to) ?? $0.to).caseInsensitiveCompare(w.name) == .orderedSame } }
    }

    // MARK: Apply & undo

    static func apply(_ plan: Plan, notes: [Note], ctx: ModelContext) {
        let byId = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var undo: [String: String] = [:]
        for m in plan.moves where m.include {
            guard let n = byId[m.id] else { continue }
            undo[n.id.uuidString] = n.folder ?? ""
            n.folder = m.to
        }
        if let d = try? JSONEncoder().encode(undo) { UserDefaults.standard.set(d, forKey: undoKey) }
        var icons = NotePath.icons
        for w in plan.workspaces { icons[w.name] = w.icon }
        NotePath.icons = icons
        try? ctx.save()
    }

    static func undo(ctx: ModelContext) {
        guard let d = UserDefaults.standard.data(forKey: undoKey), let map = try? JSONDecoder().decode([String: String].self, from: d) else { return }
        for n in (try? ctx.fetch(FetchDescriptor<Note>())) ?? [] {
            if let old = map[n.id.uuidString] { n.folder = old.isEmpty ? nil : old }
        }
        UserDefaults.standard.removeObject(forKey: undoKey)
        try? ctx.save()
    }
}

/// Notes → ✨ Reorganize. Shows the proposed workspaces and folders; edit, untick, then apply in one go.
struct ReorganizeNotesView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var notes: [Note]
    @State private var includeFiled = true
    @State private var plan: NotesReorganizer.Plan?
    @State private var working = false
    @State private var status = ""
    @State private var fraction = 0.0
    @State private var renaming: (kind: String, old: String)?
    @State private var newName = ""
    @State private var applied = false

    private var existingFolders: [String] { Array(Set(notes.compactMap(\.folder))).sorted() }
    private var allPaths: [String] {
        guard let plan else { return [] }
        return plan.workspaces.flatMap { w in w.folders.isEmpty ? [w.name] : w.folders.map { NotePath.make(w.name, $0) } }
    }

    var body: some View {
        NavigationStack {
            Group {
                if applied { doneView }
                else if let plan { review(plan) }
                else { intro }
            }
            .navigationTitle("Reorganize notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(applied ? "Done" : "Cancel") { dismiss() } }
                if let plan, !applied {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            NotesReorganizer.apply(plan, notes: notes, ctx: ctx)
                            Haptics.success()
                            withAnimation(DS.spring) { applied = true }
                        }
                        .disabled(!plan.moves.contains(where: \.include))
                    }
                }
            }
            .alert(renaming?.kind == "workspace" ? "Rename workspace" : "Rename folder",
                   isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Rename") { if let r = renaming { rename(r.kind, r.old, to: newName) }; renaming = nil }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }
    }

    // MARK: Screens

    private var intro: some View {
        let count = NotesReorganizer.candidates(notes, includeFiled: includeFiled).count
        return List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "square.grid.3x3.square").font(.largeTitle).foregroundStyle(DS.Palette.accent)
                    Text("A tidy workspace, built for you").font(DS.Font.title)
                    Text("Keel reads your pages and designs workspaces for the big areas of your life, with folders for each subject inside, then places every page. You review everything before anything moves.")
                        .font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
                }
                .padding(.vertical, 6)
            }
            Section {
                Toggle("Include pages already in folders", isOn: $includeFiled)
            } footer: {
                Text(includeFiled ? "Everything gets a place in the new structure. Your existing folder names are reused where they fit." : "Only pages without a folder are placed.")
            }
            Section {
                Button {
                    Task { await run() }
                } label: {
                    HStack {
                        Label(working ? status : "Reorganize \(count) page\(count == 1 ? "" : "s")", systemImage: "sparkles")
                        if working { Spacer(); ProgressView() }
                    }
                }
                .disabled(working || count == 0)
                if working { ProgressView(value: fraction).tint(DS.Palette.accent) }
            } footer: {
                Text(AIRouter.shared.cloudEnabled ? "Claude reads titles and the first lines of each page. Locked pages are never read or moved."
                     : AIRouter.shared.onDeviceAvailable ? "Apple Intelligence works on your iPhone; with lots of pages this takes a minute or two. Locked pages are never read or moved."
                     : "Keel groups pages by common subjects. Turn on Apple Intelligence or connect Claude for smarter workspaces.")
            }
            if NotesReorganizer.canUndo {
                Section {
                    Button("Undo last reorganize", systemImage: "arrow.uturn.backward", role: .destructive) {
                        NotesReorganizer.undo(ctx: ctx)
                        Haptics.tap()
                    }
                } footer: { Text("Puts every page back in the folder it was in before.") }
            }
        }
    }

    private func review(_ plan: NotesReorganizer.Plan) -> some View {
        List {
            Section {
                Label("\(plan.moves.filter(\.include).count) pages into \(plan.workspaces.count) workspaces · by \(plan.engine)", systemImage: "sparkles")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            } footer: { Text("Tap a name to rename it. Tap a page to move it, or untick it to leave it where it is.") }
            ForEach(plan.workspaces) { w in
                Section {
                    let folders = w.folders.isEmpty ? [""] : w.folders
                    ForEach(folders, id: \.self) { f in
                        let path = f.isEmpty ? w.name : NotePath.make(w.name, f)
                        let items = plan.moves.indices.filter { plan.moves[$0].to.caseInsensitiveCompare(path) == .orderedSame }
                        DisclosureGroup {
                            ForEach(items, id: \.self) { i in moveRow(i) }
                        } label: {
                            HStack {
                                Label(f.isEmpty ? w.name : f, systemImage: "folder.fill").foregroundStyle(DS.Palette.ink)
                                Spacer()
                                Text("\(items.count)").font(DS.Font.caption.monospacedDigit()).foregroundStyle(DS.Palette.inkSoft)
                            }
                            .contentShape(Rectangle())
                            .onLongPressGesture { if !f.isEmpty { newName = f; renaming = ("folder", path) } }
                        }
                    }
                } header: {
                    Button { newName = w.name; renaming = ("workspace", w.name) } label: {
                        HStack(spacing: 6) {
                            Text(w.icon)
                            Text(w.name).font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                            Image(systemName: "pencil").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                    .buttonStyle(.plain)
                    .textCase(nil)
                }
            }
        }
    }

    private func moveRow(_ i: Int) -> some View {
        let m = plan!.moves[i]
        return HStack {
            Button {
                plan?.moves[i].include.toggle()
            } label: {
                Image(systemName: m.include ? "checkmark.circle.fill" : "circle").foregroundStyle(m.include ? DS.Palette.accent : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(m.include ? "Will move" : "Stays where it is")
            VStack(alignment: .leading, spacing: 1) {
                Text(m.title).lineLimit(1)
                if let from = m.from { Text("from \(from)").font(.caption2).foregroundStyle(DS.Palette.inkSoft) }
            }
            Spacer()
            Menu {
                ForEach(allPaths, id: \.self) { p in Button(p.replacingOccurrences(of: "/", with: " › ")) { plan?.moves[i].to = p; plan?.moves[i].include = true } }
            } label: { Image(systemName: "arrow.turn.down.right").foregroundStyle(DS.Palette.inkSoft) }
            .buttonStyle(.borderless)
            .accessibilityLabel("Move to a different folder")
        }
    }

    private var doneView: some View {
        ContentUnavailableView {
            Label("All organized", systemImage: "checkmark.seal.fill")
        } description: {
            Text("Your notes now open on your workspaces. Changed your mind? Undo it from Reorganize at any time.")
        } actions: {
            Button("Undo", systemImage: "arrow.uturn.backward") {
                NotesReorganizer.undo(ctx: ctx)
                dismiss()
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: Actions

    private func run() async {
        working = true
        defer { working = false }
        let pages = NotesReorganizer.candidates(notes, includeFiled: includeFiled)
        let result = await NotesReorganizer.plan(for: pages, existingFolders: existingFolders) { s, f in
            Task { @MainActor in status = s; fraction = f }
        }
        withAnimation(DS.spring) { plan = result }
    }

    private func rename(_ kind: String, _ old: String, to raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !name.isEmpty, var p = plan else { return }
        if kind == "workspace" {
            guard let wi = p.workspaces.firstIndex(where: { $0.name == old }) else { return }
            p.workspaces[wi].name = name
            for i in p.moves.indices where (NotePath.workspace(p.moves[i].to) ?? p.moves[i].to) == old {
                let leaf = NotePath.workspace(p.moves[i].to) == nil ? "" : NotePath.leaf(p.moves[i].to)
                p.moves[i].to = leaf.isEmpty ? name : NotePath.make(name, leaf)
            }
        } else {
            let ws = NotePath.workspace(old)
            let leaf = NotePath.leaf(old)
            if let w = ws, let wi = p.workspaces.firstIndex(where: { $0.name == w }), let fi = p.workspaces[wi].folders.firstIndex(of: leaf) {
                p.workspaces[wi].folders[fi] = name
            }
            for i in p.moves.indices where p.moves[i].to == old { p.moves[i].to = NotePath.make(ws, name) }
        }
        plan = p
    }
}
