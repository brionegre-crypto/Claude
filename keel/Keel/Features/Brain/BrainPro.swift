import SwiftUI
import SwiftData
import CryptoKit
import Security
import Charts
import QuickLook

// MARK: - Canvas: anything as a card

struct CanvasRefTarget: Identifiable { let ref: String; var id: String { ref } }

struct CanvasAnythingPicker: View {
    var pick: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var tasks: [TaskItem]
    @Query(InboxView.recentMail) private var mail: [EmailMessage]
    @Query(sort: \Person.name) private var people: [Person]
    @Query private var files: [NoteAttachment]
    @State private var search = ""

    static func icon(_ ref: String) -> String {
        switch ref.split(separator: ":").first ?? "" { case "task": "checklist"; case "mail": "envelope"; case "person": "person.fill"; case "pdf": "doc.richtext"; default: "square" }
    }
    static func color(_ ref: String) -> String {
        switch ref.split(separator: ":").first ?? "" { case "task": "green"; case "mail": "blue"; case "person": "pink"; default: "purple" }
    }
    private func ok(_ s: String) -> Bool { search.isEmpty || s.localizedCaseInsensitiveContains(search) }

    var body: some View {
        NavigationStack {
            List {
                Section("Tasks") { ForEach(tasks.filter { ok($0.title) }.prefix(15)) { t in Button(t.title) { pick("task:\(t.id.uuidString)", t.title) } } }
                Section("People") { ForEach(people.filter { ok($0.name) }.prefix(15)) { p in Button(p.name) { pick("person:\(p.id.uuidString)", p.name) } } }
                Section("Email") { ForEach(mail.filter { ok($0.subject) || ok($0.fromName) }.prefix(15)) { e in Button(e.subject) { pick("mail:\(e.id)", e.subject) } } }
                Section("PDFs") {
                    ForEach(files.filter { $0.kind == "pdf" && ok($0.recognizedText) }.prefix(15)) { a in
                        let name = String(a.recognizedText.split(separator: "\n").first ?? "PDF")
                        Button(name) { pick("pdf:\(a.id.uuidString)", name) }
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle("Add to canvas").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct CanvasRefSheet: View {
    let target: CanvasRefTarget
    @Environment(\.modelContext) private var ctx
    var body: some View {
        let parts = target.ref.split(separator: ":", maxSplits: 1).map(String.init)
        let kind = parts.first ?? "", id = parts.count > 1 ? parts[1] : ""
        NavigationStack {
            switch kind {
            case "mail":
                if let e = try? ctx.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { $0.id == id })).first { EmailDetailView(email: e) } else { missing }
            case "person":
                if let u = UUID(uuidString: id), let p = try? ctx.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.id == u })).first { PersonPageView(person: p) } else { missing }
            case "task":
                if let u = UUID(uuidString: id), let t = try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == u })).first {
                    Form { Text(t.title).font(DS.Font.headline); if let d = t.dueDate { LabeledContent("Due", value: d.formatted()) }; if !t.notes.isEmpty { Text(t.notes) }
                        Button(t.isDone ? "Mark not done" : "Mark done") { TaskActions.setDone(t, !t.isDone) } }
                } else { missing }
            case "pdf":
                if let r = pdf(id) { PDFReaderView(attachment: r.0, note: r.1) } else { missing }
            default: missing
            }
        }
    }
    private var missing: some View { ContentUnavailableView("Not found", systemImage: "questionmark.square.dashed") }
    private func pdf(_ id: String) -> (NoteAttachment, Note)? {
        guard let u = UUID(uuidString: id), let a = try? ctx.fetch(FetchDescriptor<NoteAttachment>(predicate: #Predicate { $0.id == u })).first else { return nil }
        let nid = a.noteId
        guard let n = try? ctx.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == nid })).first else { return nil }
        return (a, n)
    }
}

// MARK: - Page look: width, zen mode, word count

enum PageLook {
    static let widthKey = "page.width"      // comfortable | wide | full
    static func maxWidth(_ raw: String) -> CGFloat { raw == "full" ? .infinity : raw == "wide" ? 1_040 : 760 }
}

struct PageStats: View {
    let note: Note
    var body: some View {
        let words = note.plainText.split { $0.isWhitespace || $0.isNewline }.count
        Text("\(words) words · \(max(1, Int((Double(words) / 230).rounded(.up)))) min read")
            .font(.caption2).foregroundStyle(DS.Palette.inkSoft)
            .accessibilityLabel("\(words) words, about \(max(1, words / 230)) minutes to read")
    }
}

// MARK: - Richer blocks: columns, button, progress, chart, file

extension SpecialBlock {
    static let columns = "keel-columns", button = "keel-button", progress = "keel-progress", chart = "keel-chart", file = "keel-file"
    static let moreCommands: [SlashCommand] = [
        .init(id: "columns", title: "Columns", subtitle: "Two or three columns side by side", icon: "rectangle.split.3x1", keywords: ["columns", "side by side", "layout"], kind: .code),
        .init(id: "button", title: "Button", subtitle: "One tap: add a task, open a link or a template", icon: "button.programmable", keywords: ["button", "action"], kind: .code),
        .init(id: "progress", title: "Progress bar", subtitle: "How many to-dos on this page are done", icon: "chart.bar.fill", keywords: ["progress", "percent", "done"], kind: .code),
        .init(id: "chart", title: "Database chart", subtitle: "Count a database's rows by a property", icon: "chart.pie.fill", keywords: ["chart", "graph", "database", "pie", "bar"], kind: .code),
        .init(id: "file", title: "File", subtitle: "Attach any file", icon: "paperclip", keywords: ["file", "attachment", "upload"], kind: .code),
        .init(id: "aiblock", title: "AI block", subtitle: "A live AI answer that refreshes itself, e.g. a page summary", icon: "sparkles.rectangle.stack", keywords: ["ai", "live", "summary", "auto", "smart"], kind: .code),
    ]
    static let aiblock = "keel-aiblock"     // text = instruction, body = last answer, refId = model
    static let moreLangs = ["columns": columns, "button": button, "progress": progress, "chart": chart, "file": file, "aiblock": aiblock]
}

struct ColumnsBlockView: View {
    @Binding var block: NoteBlock
    private var parts: [String] {
        let p = block.text.components(separatedBy: "\n|||\n")
        return p.count >= 2 ? p : ["", ""]
    }
    var body: some View {
        let cols = parts
        VStack(alignment: .trailing, spacing: 4) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(cols.indices, id: \.self) { i in
                    TextField("Column \(i + 1)", text: Binding(get: { i < parts.count ? parts[i] : "" }, set: { v in
                        var p = parts; if i < p.count { p[i] = v }; block.text = p.joined(separator: "\n|||\n")
                    }), axis: .vertical)
                    .padding(8).frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(DS.Palette.elevated.opacity(0.6), in: .rect(cornerRadius: 8))
                }
            }
            Menu {
                Button("Two columns") { var p = parts; while p.count > 2 { let last = p.removeLast(); p[p.count - 1] += "\n" + last }; block.text = p.joined(separator: "\n|||\n") }
                Button("Three columns") { var p = parts; while p.count < 3 { p.append("") }; block.text = p.joined(separator: "\n|||\n") }
            } label: { Image(systemName: "rectangle.split.3x1").font(.caption) }
        }
    }
}

/// "label | task: Call the bank" / "label | url: https://…" / "label | template: Weekly review"
struct ButtonBlockView: View {
    @Binding var block: NoteBlock
    @Environment(\.modelContext) private var ctx
    @Environment(\.openURL) private var openURL
    @State private var editing = false
    var body: some View {
        let parts = block.text.components(separatedBy: " | ")
        let label = parts.first.flatMap { $0.isEmpty ? nil : $0 } ?? "Button"
        HStack {
            Button(label) { run(parts.count > 1 ? parts[1] : "") }.buttonStyle(.borderedProminent).tint(DS.Palette.accent)
            Button { editing = true } label: { Image(systemName: "slider.horizontal.3") }.buttonStyle(.borderless).foregroundStyle(DS.Palette.inkSoft)
        }
        .alert("Button", isPresented: $editing) {
            TextField("Label | task: … / url: … / template: …", text: $block.text)
            Button("Done", role: .cancel) {}
        } message: { Text("Write the label, a |, then what it does: task: Call the bank · url: https://… · template: Weekly review") }
    }
    private func run(_ action: String) {
        let a = action.trimmingCharacters(in: .whitespaces)
        if a.lowercased().hasPrefix("task:") { _ = QuickAdd.create(String(a.dropFirst(5)).trimmingCharacters(in: .whitespaces), in: ctx); UndoCenter.shared.notify("Added to Tasks") }
        else if a.lowercased().hasPrefix("url:"), let u = URL(string: String(a.dropFirst(4)).trimmingCharacters(in: .whitespaces)) { openURL(u) }
        else if a.lowercased().hasPrefix("template:") {
            let name = String(a.dropFirst(9)).trimmingCharacters(in: .whitespaces)
            if let t = try? ctx.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.isTemplate && $0.title == name })).first {
                let n = SmartTemplates.instantiate(t, ctx: ctx); AppRouter.shared.openNoteId = n.id
            }
        }
        Haptics.success()
    }
}

struct ProgressBlockView: View {
    let note: Note
    var body: some View {
        let todos = note.blocks.filter { $0.kind == .todo }
        let done = todos.filter(\.checked).count
        let frac = todos.isEmpty ? 0 : Double(done) / Double(todos.count)
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: frac).tint(DS.Palette.calm)
            Text(todos.isEmpty ? "Add to-dos on this page to track progress" : "\(done) of \(todos.count) done · \(Int(frac * 100))%")
                .font(.caption).foregroundStyle(DS.Palette.inkSoft)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ChartBlockView: View {
    let dbId: String?
    @Query private var notes: [Note]
    var choose: () -> Void
    var body: some View {
        if let id = dbId.flatMap(UUID.init(uuidString:)), let db = notes.first(where: { $0.id == id && $0.isDatabase }),
           let prop = db.schema.first(where: { [.select, .status, .multiSelect, .checkbox].contains($0.kind) }) {
            let rows = NotesDatabase.rows(of: db, in: notes)
            let counts = Dictionary(grouping: rows.flatMap { r -> [String] in
                let v = r.props[prop.id] ?? ""
                if prop.kind == .checkbox { return [v == "1" ? "Done" : "Not done"] }
                let vals = v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                return vals.isEmpty ? ["Empty"] : vals
            }, by: { $0 }).map { ChartCount(key: $0.key, count: $0.value.count) }.sorted { $0.count > $1.count }
            VStack(alignment: .leading, spacing: 6) {
                Text("\(db.title) by \(prop.name)").font(DS.Font.caption.weight(.semibold))
                Chart(counts) { c in
                    BarMark(x: .value("Count", c.count), y: .value(prop.name, c.key)).foregroundStyle(PropertyValueEditor.tint(c.key))
                }
                .frame(height: CGFloat(max(2, counts.count)) * 28)
            }
        } else {
            Button(action: choose) { Label("Choose a database to chart (it needs a select, status or checkbox property)", systemImage: "chart.bar") }
        }
    }
}

struct FileBlockView: View {
    let attachmentId: String?
    @Query private var attachments: [NoteAttachment]
    @State private var preview: URL?
    var body: some View {
        if let id = attachmentId.flatMap(UUID.init(uuidString:)), let a = attachments.first(where: { $0.id == id }) {
            let name = String(a.recognizedText.split(separator: "\n").first ?? "File")
            Button {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try? a.data.write(to: url); preview = url
            } label: {
                Label("\(name) · \(ByteCountFormatter.string(fromByteCount: Int64(a.data.count), countStyle: .file))", systemImage: "doc.fill")
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(DS.Palette.elevated, in: .rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .quickLookPreview($preview)
        } else {
            Label("File not found", systemImage: "doc.questionmark").foregroundStyle(DS.Palette.inkSoft)
        }
    }
}

// MARK: - Smart templates: {{date}}, {{weekday}}, {{time}}, {{title}}, and ones that make themselves on a schedule

@MainActor
enum SmartTemplates {
    static func fill(_ s: String, title: String) -> String {
        let now = Date()
        return s.replacingOccurrences(of: "{{date}}", with: now.formatted(date: .long, time: .omitted))
            .replacingOccurrences(of: "{{weekday}}", with: now.formatted(.dateTime.weekday(.wide)))
            .replacingOccurrences(of: "{{time}}", with: now.formatted(date: .omitted, time: .shortened))
            .replacingOccurrences(of: "{{week}}", with: "week \(Calendar.current.component(.weekOfYear, from: now))")
            .replacingOccurrences(of: "{{title}}", with: title)
    }

    @discardableResult
    static func instantiate(_ t: Note, ctx: ModelContext) -> Note {
        let title = fill(t.title, title: t.title)
        let n = Note(title: title, blocks: t.blocks.map { b in var c = b; c.id = UUID(); c.checked = false; c.text = fill(b.text, title: title); return c })
        n.icon = t.icon
        n.folder = t.props["template.folder"] ?? t.folder
        ctx.insert(n)
        try? ctx.save()
        return n
    }

    /// Templates set to repeat ("weekly:6" = every Friday, "daily") make their page by themselves.
    static func runScheduled(ctx: ModelContext) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for t in (try? ctx.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.isTemplate }))) ?? [] {
            guard let rule = t.props["template.schedule"], !rule.isEmpty else { continue }
            let last = t.props["template.last"].flatMap(Double.init).map { Date(timeIntervalSince1970: $0) } ?? .distantPast
            guard last < today else { continue }
            let due = rule == "daily" || (rule.hasPrefix("weekly:") && Int(rule.dropFirst(7)) == cal.component(.weekday, from: Date()))
                || (rule == "monthly" && cal.component(.day, from: Date()) == 1)
            guard due else { continue }
            instantiate(t, ctx: ctx)
            t.props["template.last"] = String(Date().timeIntervalSince1970)
        }
    }
}

struct TemplateScheduleMenu: View {
    @Bindable var template: Note
    var body: some View {
        Menu {
            Button("Never") { template.props["template.schedule"] = nil }
            Button("Every day") { template.props["template.schedule"] = "daily" }
            ForEach(1...7, id: \.self) { d in Button("Every \(Calendar.current.weekdaySymbols[d - 1])") { template.props["template.schedule"] = "weekly:\(d)" } }
            Button("1st of every month") { template.props["template.schedule"] = "monthly" }
        } label: { Label("Repeat this template", systemImage: "repeat") }
    }
}

// MARK: - Starter second brain: PARA structure, templates, reorganize, link repair

@MainActor
enum StarterSetup {
    static let areas = ["Projects", "Areas", "Resources", "Archive"]

    static let templates: [(title: String, icon: String, folder: String, blocks: [NoteBlock])] = [
        ("Book · {{title}}", "📚", "Resources/Books", [NoteBlock(kind: .text, text: "#book"), NoteBlock(kind: .heading2, text: "Why I'm reading it"), NoteBlock(kind: .bullet, text: ""),
                                                   NoteBlock(kind: .heading2, text: "Big ideas"), NoteBlock(kind: .bullet, text: ""), NoteBlock(kind: .heading2, text: "Quotes"), NoteBlock(kind: .quote, text: ""),
                                                   NoteBlock(kind: .heading2, text: "What I'll do differently"), NoteBlock(kind: .todo, text: "")]),
        ("Person · {{title}}", "👤", "Areas/People", [NoteBlock(kind: .text, text: "#person"), NoteBlock(kind: .heading2, text: "About them"), NoteBlock(kind: .bullet, text: ""),
                                                    NoteBlock(kind: .heading2, text: "Things to remember"), NoteBlock(kind: .bullet, text: ""), NoteBlock(kind: .heading2, text: "Next time we talk"), NoteBlock(kind: .todo, text: "")]),
        ("Meeting · {{date}}", "🗓️", "Areas/Meetings", [NoteBlock(kind: .text, text: "#meeting"), NoteBlock(kind: .heading2, text: "Agenda"), NoteBlock(kind: .bullet, text: ""),
                                                       NoteBlock(kind: .heading2, text: "Notes"), NoteBlock(kind: .bullet, text: ""), NoteBlock(kind: .heading2, text: "Decisions"), NoteBlock(kind: .bullet, text: ""),
                                                       NoteBlock(kind: .heading2, text: "Action items"), NoteBlock(kind: .todo, text: "")]),
        ("Weekly review · {{week}}", "🔁", "Areas/Reviews", [NoteBlock(kind: .heading2, text: "Wins"), NoteBlock(kind: .bullet, text: ""), NoteBlock(kind: .heading2, text: "What didn't go to plan"),
                                                          NoteBlock(kind: .bullet, text: ""), NoteBlock(kind: .heading2, text: "Clear the decks"), NoteBlock(kind: .todo, text: "Empty the capture inbox"),
                                                          NoteBlock(kind: .todo, text: "Review projects"), NoteBlock(kind: .todo, text: "Look at next week's calendar"),
                                                          NoteBlock(kind: .heading2, text: "Next week's three priorities"), NoteBlock(kind: .numbered, text: "")]),
        ("Project · {{title}}", "🚀", "Projects", [NoteBlock(kind: .text, text: "#project"), NoteBlock(kind: .heading2, text: "Goal"), NoteBlock(kind: .text, text: ""),
                                                  NoteBlock(kind: .code, text: "Progress"), NoteBlock(kind: .heading2, text: "Next steps"), NoteBlock(kind: .todo, text: ""),
                                                  NoteBlock(kind: .heading2, text: "Notes & links"), NoteBlock(kind: .bullet, text: "")]),
    ]

    /// Folder pages for Projects/Areas/Resources/Archive and the templates (only what's missing).
    static func install(ctx: ModelContext) {
        let all = (try? ctx.fetch(FetchDescriptor<Note>())) ?? []
        for (title, icon, folder, blocks) in templates where !all.contains(where: { $0.isTemplate && $0.title == title }) {
            var bs = blocks
            if let i = bs.firstIndex(where: { $0.kind == .code && $0.text == "Progress" }) { bs[i].lang = SpecialBlock.progress }
            let t = Note(title: title, blocks: bs)
            t.isTemplate = true; t.icon = icon; t.props["template.folder"] = folder
            ctx.insert(t)
        }
        if let weekly = all.first(where: { $0.isTemplate && $0.title.hasPrefix("Weekly review") }), weekly.props["template.schedule"] == nil {
            weekly.props["template.schedule"] = "weekly:6"
        }
        try? ctx.save()
    }

    struct Move: Identifiable { let id: UUID; let title: String; let from: String?; var to: String; var include = true }

    /// AI decides Projects (active, with an end), Areas (ongoing), Resources (reference) or Archive (done or untouched for months).
    static func plan(_ notes: [Note], progress: @escaping (Int, Int) -> Void) async -> [Move] {
        let pages = notes.filter { n in !n.isTemplate && !n.isLocked && n.parentId == nil && !areas.contains(where: { a in (n.folder ?? "").hasPrefix(a) }) }
        var out: [Move] = []
        for start in stride(from: 0, to: pages.count, by: 10) {
            progress(start, pages.count)
            let batch = Array(pages[start..<min(start + 10, pages.count)])
            let list = batch.enumerated().map { i, n in
                "\(i + 1). \(n.title.isEmpty ? "Untitled" : n.title) [folder: \(n.folder ?? "none"); last edited \(Int(Date().timeIntervalSince(n.updatedAt) / 86_400)) days ago]: \(n.plainText.prefix(160))"
            }.joined(separator: "\n")
            let prompt = """
            Sort each page into PARA. Projects = active work with a goal or end date. Areas = ongoing responsibilities (health, money, home, a job, people). \
            Resources = reference and interests. Archive = finished or untouched for 6+ months. Add one short subfolder name (e.g. Projects/Kitchen remodel, Areas/Health, Resources/Recipes).
            Reply with one line per page: number|Folder/Subfolder

            \(list)
            """
            let reply = await AIRouter.shared.write(prompt) ?? ""
            for line in reply.split(separator: "\n") {
                let p = line.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard p.count == 2, let i = Int(p[0].filter(\.isNumber)), (1...batch.count).contains(i) else { continue }
                var dest = p[1].trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                if !areas.contains(where: { dest.hasPrefix($0) }) { dest = "Resources/" + dest }
                let n = batch[i - 1]
                out.append(Move(id: n.id, title: n.title.isEmpty ? "Untitled" : n.title, from: n.folder, to: dest))
            }
            // Pages the AI skipped: a simple rule.
            for n in batch where !out.contains(where: { $0.id == n.id }) {
                let stale = Date().timeIntervalSince(n.updatedAt) > 180 * 86_400
                out.append(Move(id: n.id, title: n.title.isEmpty ? "Untitled" : n.title, from: n.folder, to: stale ? "Archive" : "Resources" + (n.folder.map { "/" + NotePath.leaf($0) } ?? "")))
            }
        }
        progress(pages.count, pages.count)
        return out
    }

    struct LinkFix: Identifiable { let id = UUID(); let noteId: UUID; let page: String; let broken: String; let fix: String? }

    /// [[links]] that point nowhere, with the closest real page title when there is one.
    static func brokenLinks(_ notes: [Note]) -> [LinkFix] {
        let titles = notes.filter { !$0.isTemplate }.map(\.title).filter { !$0.isEmpty }
        let lower = Set(titles.map { $0.lowercased() })
        var out: [LinkFix] = []
        for n in notes where !n.isTemplate && !n.isLocked {
            for t in NoteLinksSection.linkTitles(in: n.plainText) where !lower.contains(t.lowercased()) {
                let best = titles.min { distance($0.lowercased(), t.lowercased()) < distance($1.lowercased(), t.lowercased()) }
                let ok = best.map { distance($0.lowercased(), t.lowercased()) <= max(2, t.count / 4) } ?? false
                out.append(LinkFix(noteId: n.id, page: n.title, broken: t, fix: ok ? best : nil))
            }
        }
        return out
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }; guard !b.isEmpty else { return a.count }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var prev = row[0]; row[0] = i
            for j in 1...b.count {
                let tmp = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] == b[j - 1] ? 0 : 1))
                prev = tmp
            }
        }
        return row[b.count]
    }

    static func repair(_ f: LinkFix, notes: [Note]) {
        guard let fix = f.fix, let n = notes.first(where: { $0.id == f.noteId }) else { return }
        for i in n.blocks.indices { n.blocks[i].text = n.blocks[i].text.replacingOccurrences(of: "[[\(f.broken)]]", with: "[[\(fix)]]") }
        n.updatedAt = Date()
    }
}

struct StarterSetupView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var notes: [Note]
    @State private var moves: [StarterSetup.Move] = []
    @State private var fixes: [StarterSetup.LinkFix] = []
    struct Suggestion: Identifiable { let id: String; let a: UUID; let b: UUID; let aTitle: String; let bTitle: String }
    @State private var suggestions: [Suggestion] = []
    @State private var working = false
    @State private var progress = (0, 0)
    @State private var done: String?

    var body: some View {
        List {
            Section {
                Button("Add the structure and templates", systemImage: "square.grid.2x2") {
                    StarterSetup.install(ctx: ctx); done = "Added Projects, Areas, Resources and Archive templates (book, person, meeting, weekly review, project). The weekly review makes itself every Friday."
                    Haptics.success()
                }
            } header: { Text("1 · Structure") } footer: {
                Text("Projects: things with a finish line. Areas: ongoing parts of life. Resources: reference and interests. Archive: done or dormant.")
            }
            Section {
                Button(working ? "Thinking… \(progress.0) of \(progress.1)" : (moves.isEmpty ? "Plan where every page goes" : "Plan again"), systemImage: "sparkles") {
                    Task { working = true; moves = await StarterSetup.plan(Array(notes)) { a, b in progress = (a, b) }; working = false }
                }
                .disabled(working)
                ForEach($moves) { $m in
                    Toggle(isOn: $m.include) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.title).lineLimit(1)
                            Text("\(m.from ?? "No folder") → \(m.to)").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                }
                if !moves.isEmpty {
                    Button("Move \(moves.filter(\.include).count) pages", systemImage: "checkmark") { applyMoves() }.buttonStyle(.borderedProminent)
                }
            } header: { Text("2 · Reorganize what you have") } footer: { Text("Review it first: switch off any page you want to leave where it is. Links keep working; pages are linked by their own ID, not their folder.") }
            Section {
                Button("Check every link", systemImage: "link.badge.plus") { scanLinks() }
                ForEach(fixes) { f in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("“\(f.page)” links to [[\(f.broken)]]").font(.callout)
                        if let fix = f.fix {
                            Button("Point it to “\(fix)”") { StarterSetup.repair(f, notes: notes); fixes.removeAll { $0.id == f.id } }.font(.caption)
                        } else {
                            Button("Create that page") { ctx.insert(Note(title: f.broken)); fixes.removeAll { $0.id == f.id } }.font(.caption)
                        }
                    }
                }
                ForEach(suggestions) { s in
                    HStack {
                        Text("Link “\(s.aTitle)” ↔ “\(s.bTitle)”").font(.callout).lineLimit(2)
                        Spacer()
                        Button("Link") { link(s); suggestions.removeAll { $0.id == s.id } }.buttonStyle(.bordered)
                    }
                }
            } header: { Text("3 · Links") } footer: { Text("Fixes links that point nowhere, links each project to its area, and suggests links between pages about the same thing.") }
            if let done { Section { Text(done).foregroundStyle(DS.Palette.calm) } }
        }
        .navigationTitle("Second-brain setup")
    }

    private func applyMoves() {
        var n = 0
        for m in moves where m.include { if let note = notes.first(where: { $0.id == m.id }) { NoteHistory.snapshot(note); note.folder = m.to; n += 1 } }
        try? ctx.save()
        moves = []
        done = "Moved \(n) pages."
        Haptics.success()
    }

    private func scanLinks() {
        fixes = StarterSetup.brokenLinks(Array(notes))
        BrainIndex.shared.refresh(ctx: ctx, force: true)
        var seen = Set<String>(), out: [Suggestion] = []
        for n in notes.filter({ !$0.isTemplate && !$0.isLocked }).prefix(200) {
            for h in BrainIndex.shared.related(to: "note:\(n.id.uuidString)", kinds: ["note"], limit: 2, minScore: 0.78) {
                guard let other = notes.first(where: { $0.id.uuidString == h.id }) else { continue }
                let key = [n.id.uuidString, other.id.uuidString].sorted().joined()
                guard !seen.contains(key), !n.plainText.contains(RichText.pageURL(other.id)) else { continue }
                seen.insert(key); out.append(Suggestion(id: key, a: n.id, b: other.id, aTitle: n.title, bTitle: other.title))
            }
        }
        suggestions = Array(out.prefix(20))
        done = fixes.isEmpty && suggestions.isEmpty ? "All links look good." : nil
    }

    private func link(_ s: Suggestion) {
        guard let a = notes.first(where: { $0.id == s.a }), let b = notes.first(where: { $0.id == s.b }) else { return }
        a.blocks.append(NoteBlock(kind: .bullet, text: "Related: [\(b.title)](\(RichText.pageURL(b.id)))"))
        b.blocks.append(NoteBlock(kind: .bullet, text: "Related: [\(a.title)](\(RichText.pageURL(a.id)))"))
        Haptics.tap()
    }
}

// MARK: - Brain health

struct DupGroup: Identifiable { let notes: [Note]; var id: UUID { notes[0].id } }
struct GraphNode: Identifiable { let note: Note; let color: Color; var id: UUID { note.id } }
struct ChartCount: Identifiable { let key: String; let count: Int; var id: String { key } }

struct BrainHealthView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var notes: [Note]

    var body: some View {
        let pages = notes.filter { !$0.isTemplate && !$0.isLocked }
        let dupes = Dictionary(grouping: pages.filter { !$0.title.isEmpty }, by: { $0.title.lowercased().trimmingCharacters(in: .whitespaces) }).values.filter { $0.count > 1 }
        let empty = pages.filter { $0.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.isDatabase && $0.createdAt < Date().addingTimeInterval(-86_400) }
        let texts = LinkIndex.texts(Array(notes))
        let orphans = pages.filter { n in
            n.updatedAt < Date().addingTimeInterval(-30 * 86_400) && n.parentId == nil && n.folder == nil &&
            NoteLinksSection.linkTitles(in: n.plainText).isEmpty &&
            !texts.lower.values.contains { $0.contains("[[\(n.title.lowercased())]]") }
        }.prefix(20)
        let broken = StarterSetup.brokenLinks(Array(notes))
        List {
            Section {
                LabeledContent("Pages", value: "\(pages.count)")
                LabeledContent("Indexed for meaning", value: "\(BrainIndex.shared.count)")
            }
            if !dupes.isEmpty {
                Section("Possible duplicates") {
                    ForEach(dupes.prefix(15).map { DupGroup(notes: $0) }) { g in
                        HStack {
                            Text("\(g.notes[0].title) ×\(g.notes.count)")
                            Spacer()
                            Button("Merge") { merge(g.notes) }.buttonStyle(.bordered)
                        }
                    }
                }
            }
            if !broken.isEmpty {
                Section("Broken links") { ForEach(broken.prefix(20)) { f in Text("“\(f.page)” → [[\(f.broken)]]").font(.callout) }
                    NavigationLink("Fix them") { StarterSetupView() } }
            }
            if !empty.isEmpty {
                Section("Empty pages") {
                    ForEach(empty.prefix(20)) { n in Text(n.title.isEmpty ? "Untitled" : n.title) }
                    Button("Move all \(empty.count) to Recently deleted", role: .destructive) { for n in empty { NoteTrash.delete(n, ctx: ctx) } }
                }
            }
            if !orphans.isEmpty {
                Section { ForEach(Array(orphans)) { n in NavigationLink { NoteEditor(note: n) } label: { Text(n.title.isEmpty ? "Untitled" : n.title) } } }
                header: { Text("Forgotten pages") } footer: { Text("Not linked anywhere, not in a folder, untouched for a month. File them, link them, or let them go.") }
            }
            if dupes.isEmpty && broken.isEmpty && empty.isEmpty && orphans.isEmpty {
                Section { Label("Your second brain is in great shape.", systemImage: "checkmark.seal.fill").foregroundStyle(DS.Palette.calm) }
            }
        }
        .navigationTitle("Brain health")
    }

    /// Keeps the oldest page, adds the others' content to it, and moves them to Recently deleted.
    private func merge(_ group: [Note]) {
        let sorted = group.sorted { $0.createdAt < $1.createdAt }
        guard let keep = sorted.first else { return }
        for n in sorted.dropFirst() {
            keep.blocks.append(NoteBlock(kind: .divider, text: ""))
            keep.blocks += n.blocks
            for c in notes where c.parentId == n.id { c.parentId = keep.id }
            NoteTrash.delete(n, ctx: ctx)
        }
        keep.updatedAt = Date()
        Haptics.success()
    }
}

// MARK: - Local graph (the brain map itself stays exactly as it is)

struct LocalGraphView: View {
    let note: Note
    @Query private var notes: [Note]
    @Environment(\.dismiss) private var dismiss
    @State private var showRelated = true
    @State private var open: Note?

    var body: some View {
        let texts = LinkIndex.texts(Array(notes))
        let out = NoteLinksSection.linkTitles(in: note.plainText).compactMap { t in notes.first { $0.title.caseInsensitiveCompare(t) == .orderedSame } }
            + notes.filter { n in (texts.raw[note.id] ?? "").contains(RichText.pageURL(n.id)) }
        let back = notes.filter { n in n.id != note.id && ((texts.raw[n.id] ?? "").contains(RichText.pageURL(note.id)) || (texts.lower[n.id] ?? "").contains("[[\(note.title.lowercased())]]")) }
        let rel = showRelated ? BrainIndex.shared.related(to: "note:\(note.id.uuidString)", kinds: ["note"], limit: 6).compactMap { h in notes.first { $0.id.uuidString == h.id } } : []
        var seen = Set<UUID>([note.id])
        let nodes: [GraphNode] = (out.map { GraphNode(note: $0, color: .blue) } + back.map { GraphNode(note: $0, color: .green) } + rel.map { GraphNode(note: $0, color: .purple) })
            .filter { seen.insert($0.note.id).inserted }
        NavigationStack {
            GeometryReader { geo in
                let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let r = min(geo.size.width, geo.size.height) * 0.36
                ZStack {
                    ForEach(nodes) { node in
                        let i = nodes.firstIndex { $0.id == node.id } ?? 0
                        let a = Double(i) / Double(max(1, nodes.count)) * 2 * .pi
                        let p = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                        Path { $0.move(to: c); $0.addLine(to: p) }.stroke(node.color.opacity(0.4), lineWidth: 1.5)
                        Button { open = node.note } label: {
                            Text(node.note.title.isEmpty ? "Untitled" : node.note.title).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                                .padding(8).frame(width: 110).background(node.color.opacity(0.15), in: .rect(cornerRadius: 10))
                        }
                        .buttonStyle(.plain).position(p)
                    }
                    Text(note.title.isEmpty ? "Untitled" : note.title).font(DS.Font.headline).padding(12)
                        .background(DS.Palette.accent.opacity(0.2), in: .rect(cornerRadius: 14)).position(c)
                }
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: 14) {
                    Label("Links", systemImage: "circle.fill").foregroundStyle(.blue)
                    Label("Linked from", systemImage: "circle.fill").foregroundStyle(.green)
                    Toggle(isOn: $showRelated) { Label("Related", systemImage: "circle.fill").foregroundStyle(.purple) }.toggleStyle(.button)
                }
                .font(.caption2).padding(10).background(.bar, in: Capsule()).padding()
            }
            .navigationTitle("Local graph").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(item: $open) { NoteEditor(note: $0) }
        }
    }
}

// MARK: - Two-way Markdown vault

extension MarkdownMirror {
    static let pullKey = "mirror.pulled"

    /// Brings in edits made to the Markdown files (in Obsidian or any app) and new .md files. A page changed in both
    /// places keeps both: the file's version becomes a "conflicted copy" next to it.
    static func pull(ctx: ModelContext) -> Int {
        guard isOn, let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return 0 }
        var stale = false
        guard let root = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
              root.startAccessingSecurityScopedResource() else { return 0 }
        defer { root.stopAccessingSecurityScopedResource() }
        let since = UserDefaults.standard.object(forKey: pullKey) as? Date ?? (last ?? .distantPast)
        let notes = (try? ctx.fetch(FetchDescriptor<Note>())) ?? []
        var changed = 0
        let fm = FileManager.default
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return 0 }
        for case let url as URL in e where url.pathExtension.lowercased() == "md" {
            guard let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, mod > since.addingTimeInterval(2),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let parsed = MarkdownImport.parse(text, dir: "")
            let idLine = parsed.frontMatter.first { $0.0 == "keel-id" }?.1
            let rel = url.deletingLastPathComponent().path.replacingOccurrences(of: root.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            var blocks = parsed.blocks
            if let first = blocks.first, first.kind == .heading { blocks.removeFirst() }      // the title line Keel writes
            if let id = idLine.flatMap(UUID.init(uuidString:)), let n = notes.first(where: { $0.id == id }) {
                guard RichText.plain(NoteExport.markdown(n)) != RichText.plain(text.components(separatedBy: "---\n\n").last ?? text) else { continue }
                if n.updatedAt > since {
                    let copy = Note(title: n.title + " (conflicted copy)", blocks: blocks); copy.folder = n.folder; ctx.insert(copy)
                } else {
                    NoteHistory.snapshot(n)
                    n.blocks = blocks
                    n.updatedAt = Date()
                }
                changed += 1
            } else if idLine == nil {
                let title = parsed.title ?? url.deletingPathExtension().lastPathComponent
                guard !notes.contains(where: { $0.title == title && ($0.folder ?? "") == rel }) else { continue }
                let n = Note(title: title, blocks: blocks)
                n.folder = rel.isEmpty ? nil : rel
                ctx.insert(n)
                changed += 1
            }
        }
        UserDefaults.standard.set(Date(), forKey: pullKey)
        try? ctx.save()
        return changed
    }
}

// MARK: - Encryption for locked pages (end to end: the key never leaves your devices' iCloud Keychain)

@MainActor
enum PageCrypto {
    private static let account = "keel.page.key"

    /// One key, kept in iCloud Keychain so all your devices share it (Apple can't read iCloud Keychain).
    private static func key() -> SymmetricKey? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account,
                                kSecAttrSynchronizable as String: true, kSecReturnData as String: true]
        var out: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data { return SymmetricKey(data: d) }
        let k = SymmetricKey(size: .bits256)
        let data = k.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account,
                                  kSecAttrSynchronizable as String: true, kSecValueData as String: data,
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess ? k : nil
    }

    static func isEncrypted(_ n: Note) -> Bool { n.props["enc"] != nil }

    /// Seals the page's content; only a placeholder is left in the synced data.
    static func encrypt(_ n: Note) {
        guard n.isLocked, !isEncrypted(n), let k = key(), let plain = try? JSONEncoder().encode(n.blocks),
              let sealed = try? AES.GCM.seal(plain, using: k).combined else { return }
        n.props["enc"] = sealed.base64EncodedString()
        n.blocks = [NoteBlock(kind: .callout, text: "Encrypted. Unlock this page to read it.")]
        n.aiSummary = nil
    }

    static func decrypt(_ n: Note) {
        guard let s = n.props["enc"], let d = Data(base64Encoded: s), let k = key(),
              let box = try? AES.GCM.SealedBox(combined: d), let plain = try? AES.GCM.open(box, using: k),
              let blocks = try? JSONDecoder().decode([NoteBlock].self, from: plain) else { return }
        n.blocks = blocks
        n.props["enc"] = nil
    }
}

// MARK: - Extensions gallery: AI commands, automation recipes, supertag packs, template packs

struct KeelExtension: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case aiCommand, supertags, templates }
    var id: String
    var kind: Kind
    var name: String
    var blurb: String
    var icon: String
    var prompt: String = ""                     // aiCommand
    var supertags: [SupertagDef] = []           // supertags
    var templates: [String] = []                // template titles from the starter set
}

struct AICommand: Codable, Identifiable, Hashable { var id = UUID(); var name: String; var prompt: String; var icon: String = "sparkles" }

@MainActor
enum Extensions {
    static let commandsKey = "ext.aiCommands", installedKey = "ext.installed"
    static var commands: [AICommand] {
        get { UserDefaults.standard.data(forKey: commandsKey).flatMap { try? JSONDecoder().decode([AICommand].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: commandsKey) }
    }
    static var installed: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: installedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: installedKey) }
    }

    static let gallery: [KeelExtension] = [
        KeelExtension(id: "ai.tldr", kind: .aiCommand, name: "TL;DR at the top", blurb: "Adds a 2-line summary to the top of the page.", icon: "text.line.first.and.arrowtriangle.forward",
                      prompt: "Write a 2-line TL;DR of this page."),
        KeelExtension(id: "ai.questions", kind: .aiCommand, name: "Questions to think about", blurb: "Five sharp questions the page raises.", icon: "questionmark.circle",
                      prompt: "List 5 sharp, specific questions this page raises that I should think about. One per line."),
        KeelExtension(id: "ai.counter", kind: .aiCommand, name: "Devil's advocate", blurb: "The strongest case against what the page says.", icon: "exclamationmark.bubble",
                      prompt: "Make the strongest honest case against the main argument or plan on this page, in 4 to 6 bullet lines."),
        KeelExtension(id: "ai.eli5", kind: .aiCommand, name: "Explain it simply", blurb: "Rewrites the page so a 12-year-old gets it.", icon: "graduationcap",
                      prompt: "Explain this page simply, as if to a smart 12-year-old, in a short paragraph."),
        KeelExtension(id: "ai.actions", kind: .aiCommand, name: "Next actions", blurb: "Concrete next steps, as to-dos.", icon: "checklist",
                      prompt: "List the 3 to 6 concrete next actions this page implies, each starting with a verb. One per line."),
        KeelExtension(id: "st.reading", kind: .supertags, name: "Reading pack", blurb: "#podcast, #paper and #course with useful fields.", icon: "books.vertical",
                      supertags: [SupertagDef(name: "podcast", icon: "mic.fill", fields: ["Show", "Episode", "Status"]),
                                  SupertagDef(name: "paper", icon: "doc.text.fill", fields: ["Authors", "Year", "Status"]),
                                  SupertagDef(name: "course", icon: "graduationcap.fill", fields: ["Platform", "Progress", "Status"])]),
        KeelExtension(id: "st.life", kind: .supertags, name: "Life pack", blurb: "#trip, #gift, #restaurant and #habit-idea.", icon: "heart.fill",
                      supertags: [SupertagDef(name: "trip", icon: "airplane", fields: ["Dates", "Where", "Status"]),
                                  SupertagDef(name: "gift", icon: "gift.fill", fields: ["For", "Price", "Bought"]),
                                  SupertagDef(name: "restaurant", icon: "fork.knife", fields: ["Area", "Cuisine", "Rating"]),
                                  SupertagDef(name: "habit-idea", icon: "repeat", fields: ["Cue", "Reward"])]),
        KeelExtension(id: "tpl.starter", kind: .templates, name: "Second-brain templates", blurb: "Book, person, meeting, weekly review and project templates.", icon: "doc.on.doc",
                      templates: StarterSetup.templates.map { $0.title }),
    ]

    static func install(_ e: KeelExtension, ctx: ModelContext) {
        switch e.kind {
        case .aiCommand: if !commands.contains(where: { $0.name == e.name }) { commands.append(AICommand(name: e.name, prompt: e.prompt, icon: e.icon)) }
        case .supertags:
            var defs = Supertags.all(ctx)
            for d in e.supertags where !defs.contains(where: { $0.name == d.name }) { defs.append(d) }
            Supertags.save(defs, ctx: ctx)
        case .templates: StarterSetup.install(ctx: ctx)
        }
        installed.insert(e.id)
    }

    /// A shareable link for your own AI command.
    static func shareLink(_ c: AICommand) -> URL? {
        guard let d = try? JSONEncoder().encode(c) else { return nil }
        return URL(string: "com.keel.app://extension?c=\(d.base64EncodedString().addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")")
    }
    static func importLink(_ url: URL) -> Bool {
        guard let b = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "c" })?.value,
              let d = Data(base64Encoded: b), var c = try? JSONDecoder().decode(AICommand.self, from: d) else { return false }
        c.id = UUID()
        commands.append(c)
        UndoCenter.shared.notify("Added the “\(c.name)” AI command")
        return true
    }

    /// Runs an AI command on a page and adds the result under a heading.
    static func run(_ c: AICommand, on n: Note) async {
        guard let r = await AIRouter.shared.write("\(c.prompt)\n\nPAGE: \(n.title)\n\(n.plainText.prefix(6_000))") else { return }
        n.blocks.append(NoteBlock(kind: .heading3, text: c.name))
        n.blocks += r.components(separatedBy: "\n").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-•* ").union(.whitespaces)) }
            .filter { !$0.isEmpty }.map { NoteBlock(kind: c.name == "Next actions" ? .todo : .bullet, text: $0) }
        n.updatedAt = Date()
    }
}

struct ExtensionsView: View {
    @Environment(\.modelContext) private var ctx
    @State private var installed = Extensions.installed
    @State private var mine = Extensions.commands
    @State private var newName = ""
    @State private var newPrompt = ""

    var body: some View {
        List {
            Section {
                ForEach(Extensions.gallery) { e in
                    HStack(spacing: DS.Space.m) {
                        Image(systemName: e.icon).font(.title3).foregroundStyle(DS.Palette.accent).frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) { Text(e.name).font(DS.Font.headline); Text(e.blurb).font(.caption).foregroundStyle(DS.Palette.inkSoft) }
                        Spacer()
                        if installed.contains(e.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.Palette.calm) }
                        else { Button("Get") { Extensions.install(e, ctx: ctx); installed = Extensions.installed; mine = Extensions.commands; Haptics.success() }.buttonStyle(.bordered) }
                    }
                }
            } header: { Text("Gallery") } footer: { Text("AI commands appear in any page's ✨ menu. Supertag packs add new #types. Template packs add ready-made pages.") }
            Section {
                ForEach(mine) { c in
                    HStack {
                        Label(c.name, systemImage: c.icon)
                        Spacer()
                        if let url = Extensions.shareLink(c) { ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }.buttonStyle(.borderless) }
                    }
                }
                .onDelete { mine.remove(atOffsets: $0); Extensions.commands = mine }
                TextField("Name, e.g. Turn into a tweet", text: $newName)
                TextField("What should the AI do with the page?", text: $newPrompt, axis: .vertical)
                Button("Add my AI command") { Extensions.commands.append(AICommand(name: newName, prompt: newPrompt)); mine = Extensions.commands; newName = ""; newPrompt = "" }
                    .disabled(newName.isEmpty || newPrompt.count < 8)
            } header: { Text("My AI commands") } footer: { Text("Share one as a link; anyone with Keel can add it with a tap.") }
        }
        .navigationTitle("Extensions")
    }
}

// MARK: - Reading-list import: Pocket and Instapaper (CSV exports, with highlights where included)

@MainActor
enum ReadingImport {
    static func run(_ url: URL, ctx: ModelContext) -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        let rows = parseCSV(text)
        guard let header = rows.first?.map({ $0.lowercased() }) else { return 0 }
        let ui = header.firstIndex(of: "url") ?? 0
        let ti = header.firstIndex(of: "title")
        let hi = header.firstIndex { $0.contains("highlight") || $0 == "selection" }
        let have = Set(((try? ctx.fetch(FetchDescriptor<SavedLink>())) ?? []).map(\.url))
        var n = 0
        for r in rows.dropFirst() where r.count > ui {
            let u = r[ui].trimmingCharacters(in: .whitespaces)
            guard u.hasPrefix("http"), !have.contains(u) else { continue }
            let l = SavedLink(url: u, title: ti.flatMap { $0 < r.count ? r[$0] : nil } ?? "")
            ctx.insert(l)
            if let hi, hi < r.count, !r[hi].isEmpty {
                ReaderStore.setHighlights(l.id, r[hi].components(separatedBy: "\n").filter { !$0.isEmpty }.map { ReaderHighlight(text: $0) })
            }
            n += 1
        }
        try? ctx.save()
        return n
    }

    static func parseCSV(_ s: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var it = Array(s).makeIterator()
        var pending: Character?
        while let c = pending ?? it.next() {
            pending = nil
            if quoted {
                if c == "\"" { if let n = it.next() { if n == "\"" { field.append("\"") } else { quoted = false; pending = n } } else { quoted = false } }
                else { field.append(c) }
            } else {
                switch c {
                case "\"": quoted = true
                case ",": row.append(field); field = ""
                case "\n", "\r\n": row.append(field); rows.append(row); row = []; field = ""
                case "\r": break
                default: field.append(c)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
