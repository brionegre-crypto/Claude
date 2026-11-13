import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Supertags: #person, #book, #project… turn a line into an object with fields

struct SupertagDef: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String                 // lowercase, without #
    var icon: String
    var fields: [String]
}

/// Definitions live in a hidden page so they sync to every device with your notes.
@MainActor
enum Supertags {
    static let pageTitle = "⚙︎ Keel supertags"
    static let defaults: [SupertagDef] = [
        SupertagDef(name: "person", icon: "person.fill", fields: ["Email", "Phone", "Company", "Met"]),
        SupertagDef(name: "book", icon: "book.fill", fields: ["Author", "Status", "Rating"]),
        SupertagDef(name: "project", icon: "folder.fill", fields: ["Status", "Due", "Owner"]),
        SupertagDef(name: "meeting", icon: "person.2.fill", fields: ["Date", "People"]),
        SupertagDef(name: "idea", icon: "lightbulb.fill", fields: ["Status", "Area"]),
        SupertagDef(name: "article", icon: "doc.richtext", fields: ["URL", "Author"]),
        SupertagDef(name: "movie", icon: "film", fields: ["Status", "Rating"]),
        SupertagDef(name: "recipe", icon: "fork.knife", fields: ["Time", "Source"]),
    ]
    private static var cache: [SupertagDef]?

    private static func page(_ ctx: ModelContext) -> Note {
        let title = pageTitle
        if let p = try? ctx.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.isTemplate && $0.title == title })).first { return p }
        let p = Note(title: pageTitle, blocks: [])
        p.isTemplate = true
        ctx.insert(p)
        return p
    }

    static func all(_ ctx: ModelContext) -> [SupertagDef] {
        if let c = cache { return c }
        let p = page(ctx)
        let v = p.props["supertags"].flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode([SupertagDef].self, from: $0) } ?? defaults
        cache = v
        return v
    }
    static func save(_ defs: [SupertagDef], ctx: ModelContext) {
        cache = defs
        let p = page(ctx)
        p.props["supertags"] = (try? JSONEncoder().encode(defs)).flatMap { String(data: $0, encoding: .utf8) }
        p.updatedAt = Date()
    }

    /// The supertags used on a line.
    static func tags(in text: String, defs: [SupertagDef]) -> [SupertagDef] {
        let low = text.lowercased()
        return defs.filter { d in low.range(of: "#\(d.name)\\b", options: .regularExpression) != nil }
    }
    static func fieldKey(_ block: UUID, _ field: String) -> String { "st.\(block.uuidString).\(field)" }
    static func strip(_ text: String, _ d: SupertagDef) -> String {
        RichText.plain(text).replacingOccurrences(of: "#\(d.name)", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
    }

    struct Entry: Identifiable { let id: UUID; let note: Note; let block: NoteBlock }
    static func entries(_ d: SupertagDef, notes: [Note]) -> [Entry] {
        notes.filter { !$0.isTemplate && !$0.isLocked }.flatMap { n in
            n.blocks.filter { $0.text.lowercased().range(of: "#\(d.name)\\b", options: .regularExpression) != nil }.map { Entry(id: $0.id, note: n, block: $0) }
        }
    }
}

struct SupertagChips: View {
    let note: Note
    let block: NoteBlock
    let defs: [SupertagDef]
    @State private var editing: SupertagDef?
    var body: some View {
        let tags = Supertags.tags(in: block.text, defs: defs)
        if !tags.isEmpty {
            HStack(spacing: 6) {
                ForEach(tags) { d in
                    Button { editing = d } label: {
                        let filled = d.fields.compactMap { f in note.props[Supertags.fieldKey(block.id, f)].map { "\(f): \($0)" } }
                        Label(filled.isEmpty ? d.name.capitalized : filled.prefix(2).joined(separator: " · "), systemImage: d.icon)
                            .font(.caption2.weight(.medium)).lineLimit(1)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(DS.Palette.accent.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(item: $editing) { SupertagFieldsSheet(note: note, blockId: block.id, def: $0) }
        }
    }
}

struct SupertagFieldsSheet: View {
    @Bindable var note: Note
    let blockId: UUID
    let def: SupertagDef
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                ForEach(def.fields, id: \.self) { f in
                    TextField(f, text: Binding(get: { note.props[Supertags.fieldKey(blockId, f)] ?? "" },
                                               set: { note.props[Supertags.fieldKey(blockId, f)] = $0.isEmpty ? nil : $0; note.updatedAt = Date() }))
                }
            }
            .navigationTitle("#\(def.name)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

/// Today → ⊞ → Supertags: every #person, #book, #project… across all your pages, as live collections.
struct SupertagsView: View {
    @Environment(\.modelContext) private var ctx
    @State private var defs: [SupertagDef] = []
    @State private var newName = ""
    @Query private var notes: [Note]

    var body: some View {
        List {
            Section {
                ForEach(defs) { d in
                    NavigationLink { SupertagCollectionView(def: d) } label: {
                        HStack {
                            Label("#\(d.name)", systemImage: d.icon)
                            Spacer()
                            Text("\(Supertags.entries(d, notes: notes).count)").foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                }
                .onDelete { defs.remove(atOffsets: $0); Supertags.save(defs, ctx: ctx) }
            } footer: { Text("Write #person, #book, #project… on any line in any page. It gets fields (tap the chip under the line) and shows up here.") }
            Section("New supertag") {
                HStack {
                    TextField("e.g. podcast", text: $newName).textInputAutocapitalization(.never)
                    Button("Add") {
                        let n = newName.lowercased().replacingOccurrences(of: "#", with: "").replacingOccurrences(of: " ", with: "-")
                        guard !n.isEmpty, !defs.contains(where: { $0.name == n }) else { return }
                        defs.append(SupertagDef(name: n, icon: "tag.fill", fields: ["Status", "Notes"]))
                        Supertags.save(defs, ctx: ctx); newName = ""
                    }
                }
            }
        }
        .navigationTitle("Supertags")
        .onAppear { defs = Supertags.all(ctx) }
    }
}

struct SupertagCollectionView: View {
    @State var def: SupertagDef
    @Environment(\.modelContext) private var ctx
    @Query private var notes: [Note]
    @State private var newField = ""

    var body: some View {
        List {
            let entries = Supertags.entries(def, notes: notes)
            if entries.isEmpty { Text("Nothing tagged #\(def.name) yet.").foregroundStyle(DS.Palette.inkSoft) }
            ForEach(entries) { e in
                NavigationLink { NoteEditor(note: e.note, focusBlock: e.block.id) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Supertags.strip(e.block.text, def)).font(DS.Font.headline)
                        let vals = def.fields.compactMap { f in e.note.props[Supertags.fieldKey(e.block.id, f)].map { "\(f): \($0)" } }
                        if !vals.isEmpty { Text(vals.joined(separator: " · ")).font(.caption).foregroundStyle(DS.Palette.inkSoft) }
                        Text("in \(e.note.title.isEmpty ? "Untitled" : e.note.title)").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
            }
            Section("Fields") {
                ForEach(def.fields, id: \.self) { Text($0) }
                    .onDelete { def.fields.remove(atOffsets: $0); persist() }
                HStack {
                    TextField("Add a field", text: $newField)
                    Button("Add") { guard !newField.isEmpty else { return }; def.fields.append(newField); newField = ""; persist() }
                }
            }
        }
        .navigationTitle("#\(def.name)")
    }
    private func persist() {
        var all = Supertags.all(ctx)
        if let i = all.firstIndex(where: { $0.id == def.id }) { all[i] = def }
        Supertags.save(all, ctx: ctx)
    }
}

// MARK: - Line links and line embeds (Logseq/Roam-style block references)

@MainActor
enum BlockLinks {
    static func url(note: UUID, block: UUID) -> String { "com.keel.app://block/\(note.uuidString)/\(block.uuidString)" }
    static func parse(_ url: URL) -> (UUID, UUID)? {
        guard url.scheme == "com.keel.app", url.host == "block" else { return nil }
        let p = url.pathComponents.filter { $0 != "/" }
        guard p.count == 2, let n = UUID(uuidString: p[0]), let b = UUID(uuidString: p[1]) else { return nil }
        return (n, b)
    }
    /// The last line you chose "Copy line embed" on, ready for /line embed.
    static var clipboard: String?
}

struct BlockRefView: View {
    let ref: String?                  // "noteId/blockId"
    let allNotes: [Note]
    var open: (Note, UUID) -> Void
    var body: some View {
        let parts = (ref ?? "").split(separator: "/").map(String.init)
        let note = parts.first.flatMap(UUID.init(uuidString:)).flatMap { id in allNotes.first { $0.id == id } }
        let bid = parts.count > 1 ? UUID(uuidString: parts[1]) : nil
        let block = note?.blocks.first { $0.id == bid }
        Button {
            if let note, let bid { open(note, bid) }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(block.map { RichText.render($0.text) } ?? AttributedString("Line not found. Hold any line → Copy line embed, then type /line embed."))
                    .foregroundStyle(DS.Palette.ink)
                if let note { Text("↗ \(note.title.isEmpty ? "Untitled" : note.title)").font(.caption2).foregroundStyle(DS.Palette.inkSoft) }
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) { Rectangle().fill(Color.orange.opacity(0.6)).frame(width: 2) }
            .background(Color.orange.opacity(0.06), in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Trash (30 days)

struct NoteSnapshot: Codable, Identifiable {
    var id: UUID
    var title: String
    var blocks: [NoteBlock]
    var folder: String?
    var icon: String?
    var parentId: UUID?
    var props: [String: String]
    var isDatabase: Bool
    var schema: [DBProperty]
    var dbView: String
    var isPinned: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(_ n: Note) {
        id = n.id; title = n.title; blocks = n.blocks; folder = n.folder; icon = n.icon; parentId = n.parentId; props = n.props
        isDatabase = n.isDatabase; schema = n.schema; dbView = n.dbView; isPinned = n.isPinned; createdAt = n.createdAt; updatedAt = n.updatedAt
    }

    func make() -> Note {
        let n = Note(title: title, blocks: blocks)
        n.id = id; n.folder = folder; n.icon = icon; n.parentId = parentId; n.props = props
        n.isDatabase = isDatabase; n.schema = schema; n.dbView = dbView; n.isPinned = isPinned
        n.createdAt = createdAt; n.updatedAt = Date()
        return n
    }
}

@MainActor
enum NoteTrash {
    static var folder: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Trash", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Keeps a copy for 30 days, then deletes the page.
    static func delete(_ n: Note, ctx: ModelContext) {
        var s = NoteSnapshot(n)
        s.deletedAt = Date()
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: folder.appendingPathComponent("\(n.id.uuidString).json"), options: .atomic) }
        ctx.delete(n)
    }

    static var items: [NoteSnapshot] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .compactMap { (try? Data(contentsOf: $0)).flatMap { try? JSONDecoder().decode(NoteSnapshot.self, from: $0) } }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    static func restore(_ s: NoteSnapshot, ctx: ModelContext) {
        ctx.insert(s.make())
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(s.id.uuidString).json"))
        try? ctx.save()
    }

    static func forget(_ s: NoteSnapshot) { try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(s.id.uuidString).json")) }

    static func purgeOld() {
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        for s in items where (s.deletedAt ?? .distantFuture) < cutoff { forget(s) }
    }
}

struct TrashView: View {
    @Environment(\.modelContext) private var ctx
    @State private var items = NoteTrash.items
    var body: some View {
        List {
            if items.isEmpty { Text("Nothing in the trash.").foregroundStyle(DS.Palette.inkSoft) }
            ForEach(items) { s in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(s.icon ?? "📄") \(s.title.isEmpty ? "Untitled" : s.title)")
                        if let d = s.deletedAt {
                            Text("Deleted \(d.formatted(.relative(presentation: .named))) · gone in \(max(0, 30 - Int(Date().timeIntervalSince(d) / 86_400))) days")
                                .font(.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                    Spacer()
                    Button("Restore") { NoteTrash.restore(s, ctx: ctx); items = NoteTrash.items; Haptics.success() }.buttonStyle(.bordered)
                }
                .swipeActions { Button("Delete now", role: .destructive) { NoteTrash.forget(s); items = NoteTrash.items } }
            }
        }
        .navigationTitle("Recently deleted")
    }
}

// MARK: - Daily backups with restore

struct TaskSnapshot: Codable {
    var id: UUID; var title: String; var notes: String; var dueDate: Date?; var isDone: Bool; var completedAt: Date?
    var priority: Int; var tags: [String]; var listName: String; var createdAt: Date; var recurrence: Recurrence?
}
struct PersonSnapshot: Codable { var id: UUID; var name: String; var email: String; var phone: String; var cadenceDays: Int; var lastContact: Date?; var notes: String }
struct BrainBackupFile: Codable { var made: Date; var notes: [NoteSnapshot]; var tasks: [TaskSnapshot]; var people: [PersonSnapshot] }

@MainActor
enum BrainBackup {
    static let lastKey = "backup.last"
    static var folder: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func backupIfDue(ctx: ModelContext) {
        let last = UserDefaults.standard.object(forKey: lastKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 20 * 3600 else { return }
        _ = make(ctx: ctx)
    }

    @discardableResult
    static func make(ctx: ModelContext) -> URL? {
        let notes = ((try? ctx.fetch(FetchDescriptor<Note>())) ?? []).map(NoteSnapshot.init)
        let tasks = ((try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []).map {
            TaskSnapshot(id: $0.id, title: $0.title, notes: $0.notes, dueDate: $0.dueDate, isDone: $0.isDone, completedAt: $0.completedAt,
                         priority: $0.priority.rawValue, tags: $0.tags, listName: $0.listName, createdAt: $0.createdAt, recurrence: $0.recurrence)
        }
        let people = ((try? ctx.fetch(FetchDescriptor<Person>())) ?? []).map {
            PersonSnapshot(id: $0.id, name: $0.name, email: $0.email, phone: $0.phone, cadenceDays: $0.cadenceDays, lastContact: $0.lastContact, notes: $0.notes)
        }
        let file = BrainBackupFile(made: Date(), notes: notes, tasks: tasks, people: people)
        let url = folder.appendingPathComponent("Keel backup \(Date().formatted(.iso8601.year().month().day())).keelbackup")
        guard let data = try? JSONEncoder().encode(file), (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        UserDefaults.standard.set(Date(), forKey: lastKey)
        // Keep the newest 7.
        for old in backups.dropFirst(7) { try? FileManager.default.removeItem(at: old) }
        return url
    }

    static var backups: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "keelbackup" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Brings back anything in the backup that's missing now. Never overwrites what you have.
    static func restoreMissing(from url: URL, ctx: ModelContext) -> (notes: Int, tasks: Int, people: Int) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let d = try? Data(contentsOf: url), let f = try? JSONDecoder().decode(BrainBackupFile.self, from: d) else { return (0, 0, 0) }
        let haveNotes = Set(((try? ctx.fetch(FetchDescriptor<Note>())) ?? []).map(\.id))
        let haveTasks = Set(((try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []).map(\.id))
        let havePeople = Set(((try? ctx.fetch(FetchDescriptor<Person>())) ?? []).map(\.id))
        var c = (0, 0, 0)
        for n in f.notes where !haveNotes.contains(n.id) { ctx.insert(n.make()); c.0 += 1 }
        for t in f.tasks where !haveTasks.contains(t.id) {
            let x = TaskItem(title: t.title, dueDate: t.dueDate, priority: TaskPriority(rawValue: t.priority) ?? .none)
            x.id = t.id; x.notes = t.notes; x.isDone = t.isDone; x.completedAt = t.completedAt; x.tags = t.tags; x.listName = t.listName
            x.createdAt = t.createdAt; x.recurrence = t.recurrence
            ctx.insert(x); c.1 += 1
        }
        for p in f.people where !havePeople.contains(p.id) {
            let x = Person(name: p.name)
            x.id = p.id; x.email = p.email; x.phone = p.phone; x.cadenceDays = p.cadenceDays; x.lastContact = p.lastContact; x.notes = p.notes
            ctx.insert(x); c.2 += 1
        }
        try? ctx.save()
        return c
    }
}

struct BackupsSection: View {
    @Environment(\.modelContext) private var ctx
    @State private var list = BrainBackup.backups
    @State private var message: String?
    @State private var picking = false

    var body: some View {
        Section {
            Button("Back up now", systemImage: "externaldrive.badge.plus") {
                if BrainBackup.make(ctx: ctx) != nil { list = BrainBackup.backups; message = "Backed up."; Haptics.success() }
            }
            ForEach(list, id: \.self) { url in
                HStack {
                    Text(url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "Keel backup ", with: "")).font(.callout)
                    Spacer()
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }.buttonStyle(.borderless)
                    Button("Restore") { report(BrainBackup.restoreMissing(from: url, ctx: ctx)) }.buttonStyle(.borderless)
                }
            }
            Button("Restore from a file…", systemImage: "doc.badge.arrow.up") { picking = true }
            NavigationLink { TrashView() } label: { Label("Recently deleted pages", systemImage: "trash") }
            if let message { Text(message).font(.caption).foregroundStyle(DS.Palette.inkSoft) }
        } header: { Text("Backups") } footer: {
            Text("Keel keeps a backup of your pages, tasks and people every day (the last 7). Save one to Files to keep it anywhere. Restoring only adds what's missing; it never overwrites.")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.data, .json]) { r in
            if case .success(let url) = r { report(BrainBackup.restoreMissing(from: url, ctx: ctx)) }
        }
    }

    private func report(_ c: (notes: Int, tasks: Int, people: Int)) {
        message = c.notes + c.tasks + c.people == 0 ? "Nothing was missing." : "Brought back \(c.notes) pages, \(c.tasks) tasks and \(c.people) people."
        Haptics.success()
    }
}
