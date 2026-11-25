import SwiftUI
import SwiftData
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

// MARK: - Task extras, kept in the task's hidden tags (so they sync with the task and nothing about storage changes)
//
// ~start:2026-12-01      start date: hidden from your lists until then (Things-style "When")
// ~wontdo                closed without doing it (TickTick "Won't do"); doesn't count as done in stats or goals
// ~heading:Phase 1       a heading inside its list or project
// ~remind:1440           an extra reminder, minutes before (several allowed)
// ~f:Status=In review    a custom field value

extension TaskMeta {
    nonisolated static let startPrefix = "~start:", wontDoTag = "~wontdo", headingPrefix = "~heading:", remindPrefix = "~remind:", fieldPrefix = "~f:"

    // Start date
    nonisolated static func startDate(_ t: TaskItem) -> Date? {
        t.tags.first { $0.hasPrefix(startPrefix) }.flatMap { ISO8601DateFormatter.dateOnly.date(from: String($0.dropFirst(startPrefix.count))) }
    }
    nonisolated static func setStart(_ t: TaskItem, _ d: Date?) {
        t.tags.removeAll { $0.hasPrefix(startPrefix) }
        if let d { t.tags.append(startPrefix + ISO8601DateFormatter.dateOnly.string(from: d)) }
        t.updatedAt = Date()
    }
    /// Starts later than today: kept out of Today, Inbox and your lists until then (shown in Upcoming).
    nonisolated static func isDeferred(_ t: TaskItem, now: Date = Date()) -> Bool {
        guard let s = startDate(t) else { return false }
        return s > Calendar.current.startOfDay(for: now)
    }

    // Won't do
    nonisolated static func isWontDo(_ t: TaskItem) -> Bool { t.tags.contains(wontDoTag) }
    @MainActor static func setWontDo(_ t: TaskItem, _ on: Bool) {
        t.tags.removeAll { $0 == wontDoTag }
        if on {
            t.tags.append(wontDoTag)
            t.isDone = true
            t.completedAt = Date()
            TaskAlerts.cancel(t)
            TaskActivity.log(t, "Marked won't do")
        } else {
            t.isDone = false
            t.completedAt = nil
            TaskActivity.log(t, "Reopened")
        }
        t.updatedAt = Date()
    }

    // Heading
    nonisolated static func heading(_ t: TaskItem) -> String? { t.tags.first { $0.hasPrefix(headingPrefix) }.map { String($0.dropFirst(headingPrefix.count)) } }
    nonisolated static func setHeading(_ t: TaskItem, _ h: String?) {
        t.tags.removeAll { $0.hasPrefix(headingPrefix) }
        if let h, !h.trimmingCharacters(in: .whitespaces).isEmpty { t.tags.append(headingPrefix + h.trimmingCharacters(in: .whitespaces)) }
        t.updatedAt = Date()
    }

    // Extra reminders
    nonisolated static func extraReminders(_ t: TaskItem) -> [Int] {
        t.tags.filter { $0.hasPrefix(remindPrefix) }.compactMap { Int($0.dropFirst(remindPrefix.count)) }.sorted()
    }
    nonisolated static func setExtraReminders(_ t: TaskItem, _ minutes: [Int]) {
        t.tags.removeAll { $0.hasPrefix(remindPrefix) }
        t.tags += Set(minutes).sorted().map { remindPrefix + String($0) }
        t.updatedAt = Date()
    }

    // Custom fields
    nonisolated static func field(_ t: TaskItem, _ name: String) -> String? {
        let p = fieldPrefix + name + "="
        return t.tags.first { $0.hasPrefix(p) }.map { String($0.dropFirst(p.count)) }
    }
    nonisolated static func setField(_ t: TaskItem, _ name: String, _ value: String?) {
        let p = fieldPrefix + name + "="
        t.tags.removeAll { $0.hasPrefix(p) }
        if let value, !value.isEmpty { t.tags.append(p + value) }
        t.updatedAt = Date()
    }
}


// MARK: - Comments & activity (kept on this device, per task)

struct TaskActivityEntry: Codable, Hashable, Identifiable {
    var id = UUID()
    var at = Date()
    var text: String
    var isComment = false
}

@MainActor
enum TaskActivity {
    private static let key = "task.activity"
    private static var cache: [String: [TaskActivityEntry]]? = nil

    private static var all: [String: [TaskActivityEntry]] {
        get {
            if let c = cache { return c }
            let v: [String: [TaskActivityEntry]] = (UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([String: [TaskActivityEntry]].self, from: $0) }) ?? [:]
            cache = v; return v
        }
        set { cache = newValue; UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    static func entries(_ t: TaskItem) -> [TaskActivityEntry] { (all[t.id.uuidString] ?? []).sorted { $0.at > $1.at } }

    static func log(_ t: TaskItem, _ text: String, comment: Bool = false) {
        var a = all
        var list = a[t.id.uuidString] ?? []
        list.append(TaskActivityEntry(text: text, isComment: comment))
        a[t.id.uuidString] = Array(list.suffix(80))
        // Keep the store small: at most 1,500 tasks' histories.
        if a.count > 1_500, let oldest = a.min(by: { ($0.value.last?.at ?? .distantPast) < ($1.value.last?.at ?? .distantPast) })?.key { a[oldest] = nil }
        all = a
    }
}

// MARK: - Attachments (photos and files, kept on this device)

enum TaskFiles {
    static func folder(_ t: TaskItem) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TaskFiles", isDirectory: true).appendingPathComponent(t.id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    static func list(_ t: TaskItem) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder(t), includingPropertiesForKeys: [.creationDateKey])) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    static func add(_ data: Data, name: String, to t: TaskItem) {
        let safe = name.replacingOccurrences(of: "/", with: "-")
        try? data.write(to: folder(t).appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(safe)"))
    }
    static func remove(_ url: URL) { try? FileManager.default.removeItem(at: url) }
}

/// The extra sections in a task's detail page: start date, reminders, heading, fields, attachments, comments & activity.
struct TaskExtrasSections: View {
    @Bindable var task: TaskItem
    @State private var comment = ""
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var files: [URL] = []
    @State private var preview: URL?
    @State private var tick = 0

    var body: some View {
        let _ = tick
        Section {
            let start = TaskMeta.startDate(task)
            Toggle("Start date", isOn: Binding(get: { start != nil }, set: { TaskMeta.setStart(task, $0 ? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) : nil); tick += 1 }))
            if let s = start {
                DatePicker("Starts", selection: Binding(get: { s }, set: { TaskMeta.setStart(task, Calendar.current.startOfDay(for: $0)); tick += 1 }), displayedComponents: .date)
            }
        } footer: { Text("Hidden from your lists until it starts, then it shows up on its own. See what's coming in Upcoming.") }

        Section {
            let extra = TaskMeta.extraReminders(task)
            ForEach(extra, id: \.self) { m in
                HStack {
                    Label(Self.label(m), systemImage: "bell.badge")
                    Spacer()
                    Button { TaskMeta.setExtraReminders(task, extra.filter { $0 != m }); TaskAlerts.schedule(task); tick += 1 } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                        .buttonStyle(.plain)
                }
            }
            Menu {
                ForEach([5, 15, 30, 60, 120, 1_440, 2_880, 10_080], id: \.self) { m in
                    Button(Self.label(m)) { TaskMeta.setExtraReminders(task, extra + [m]); TaskAlerts.schedule(task); tick += 1 }
                }
            } label: { Label("Add another reminder", systemImage: "bell.and.waves.left.and.right") }
                .disabled(task.dueDate == nil)
        } header: { Text("More reminders") } footer: { Text(task.dueDate == nil ? "Give the task a date first." : "On top of the main alert, for the big ones.") }

        Section("Heading") {
            TextField("e.g. Phase 1, Groceries, Before the trip", text: Binding(get: { TaskMeta.heading(task) ?? "" }, set: { TaskMeta.setHeading(task, $0) }))
        }

        let fields = TaskFieldDefs.fields(for: task.listName)
        if !fields.isEmpty {
            Section("Fields") {
                ForEach(fields) { f in TaskFieldRow(task: task, def: f) }
            }
        }

        Section {
            ForEach(files, id: \.self) { u in
                HStack {
                    Image(systemName: ["jpg", "jpeg", "png", "heic"].contains(u.pathExtension.lowercased()) ? "photo" : "doc")
                    Text(String(u.lastPathComponent.drop { $0 != "-" }.dropFirst())).lineLimit(1)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { preview = u }
                .swipeActions { Button("Remove", role: .destructive) { TaskFiles.remove(u); files = TaskFiles.list(task) } }
            }
            PhotosPicker(selection: $photo, matching: .images) { Label("Add a photo", systemImage: "photo.badge.plus") }
            Button { importing = true } label: { Label("Add a file", systemImage: "paperclip") }
        } header: { Text("Attachments") }
        .onChange(of: photo) {
            guard let photo else { return }
            Task {
                if let d = try? await photo.loadTransferable(type: Data.self) {
                    TaskFiles.add(d, name: "photo.jpg", to: task); TaskActivity.log(task, "Added a photo"); files = TaskFiles.list(task)
                }
                self.photo = nil
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { r in
            guard case .success(let url) = r else { return }
            let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if let d = try? Data(contentsOf: url) { TaskFiles.add(d, name: url.lastPathComponent, to: task); TaskActivity.log(task, "Attached \(url.lastPathComponent)"); files = TaskFiles.list(task) }
        }
        .quickLookPreview($preview, in: files)
        .onAppear { files = TaskFiles.list(task) }

        Section {
            HStack {
                TextField("Add a comment", text: $comment, axis: .vertical)
                Button("Post") { TaskActivity.log(task, comment.trimmingCharacters(in: .whitespacesAndNewlines), comment: true); comment = ""; tick += 1 }
                    .disabled(comment.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(TaskActivity.entries(task).prefix(30)) { e in
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.text).font(e.isComment ? .body : .caption).foregroundStyle(e.isComment ? DS.Palette.ink : DS.Palette.inkSoft)
                    Text(e.at.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                }
            }
            Text("Created \(task.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
        } header: { Text("Comments & activity") }

        Section {
            Button(TaskMeta.isWontDo(task) ? "Reopen task" : "Won't do", systemImage: TaskMeta.isWontDo(task) ? "arrow.uturn.backward" : "xmark.circle") {
                TaskMeta.setWontDo(task, !TaskMeta.isWontDo(task)); tick += 1; Haptics.tap()
            }
            .tint(.orange)
        } footer: { Text("Closes the task without counting it as done, so your stats and goals stay honest.") }
    }

    static func label(_ m: Int) -> String {
        m < 60 ? "\(m) minutes before" : m < 1_440 ? "\(m / 60) hour\(m / 60 == 1 ? "" : "s") before" : m < 10_080 ? "\(m / 1_440) day\(m / 1_440 == 1 ? "" : "s") before" : "1 week before"
    }
}

// MARK: - Custom fields (per list or project)

struct TaskFieldDef: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Identifiable { case text, number, choice, date, person; var id: String { rawValue } }
    var id = UUID()
    var name: String
    var kind: Kind
    var options: [String] = []
}

@MainActor
enum TaskFieldDefs {
    private static let key = "task.fieldDefs"
    static var all: [String: [TaskFieldDef]] {
        get { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([String: [TaskFieldDef]].self, from: $0) } ?? [:] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }
    static func fields(for list: String) -> [TaskFieldDef] { all[list] ?? [] }
    static func set(_ list: String, _ defs: [TaskFieldDef]) { var a = all; a[list] = defs; all = a }
}

struct TaskFieldRow: View {
    @Bindable var task: TaskItem
    let def: TaskFieldDef
    var body: some View {
        let v = TaskMeta.field(task, def.name)
        switch def.kind {
        case .choice:
            Picker(def.name, selection: Binding(get: { v ?? "" }, set: { TaskMeta.setField(task, def.name, $0) })) {
                Text("—").tag("")
                ForEach(def.options, id: \.self) { Text($0).tag($0) }
            }
        case .date:
            let d = v.flatMap { ISO8601DateFormatter.dateOnly.date(from: $0) }
            DatePicker(def.name, selection: Binding(get: { d ?? Date() }, set: { TaskMeta.setField(task, def.name, ISO8601DateFormatter.dateOnly.string(from: $0)) }), displayedComponents: .date)
        case .number:
            TextField(def.name, text: Binding(get: { v ?? "" }, set: { TaskMeta.setField(task, def.name, $0.filter { $0.isNumber || $0 == "." || $0 == "-" }) }))
                .keyboardType(.decimalPad)
        case .text, .person:
            TextField(def.name, text: Binding(get: { v ?? "" }, set: { TaskMeta.setField(task, def.name, $0) }))
        }
    }
}

struct TaskFieldsEditor: View {
    let list: String
    @State private var defs: [TaskFieldDef] = []
    @State private var name = ""
    @State private var kind: TaskFieldDef.Kind = .choice
    @State private var options = ""

    var body: some View {
        Form {
            Section {
                ForEach(defs) { d in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.name)
                        Text(d.kind.rawValue.capitalized + (d.options.isEmpty ? "" : " · " + d.options.joined(separator: ", "))).font(.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
                .onDelete { defs.remove(atOffsets: $0); TaskFieldDefs.set(list, defs) }
            } header: { Text("Fields in \(list)") } footer: { Text("Every task in this list gets these fields (like Status, Owner, Budget). Board columns can follow a choice field.") }
            Section("New field") {
                TextField("Name (e.g. Status, Owner, Budget)", text: $name)
                Picker("Type", selection: $kind) {
                    Text("Choice").tag(TaskFieldDef.Kind.choice); Text("Text").tag(TaskFieldDef.Kind.text)
                    Text("Number").tag(TaskFieldDef.Kind.number); Text("Date").tag(TaskFieldDef.Kind.date); Text("Person").tag(TaskFieldDef.Kind.person)
                }
                if kind == .choice { TextField("Choices, separated by commas", text: $options) }
                Button("Add field") {
                    let opts = options.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    defs.append(TaskFieldDef(name: name.trimmingCharacters(in: .whitespaces), kind: kind, options: kind == .choice ? opts : []))
                    TaskFieldDefs.set(list, defs); name = ""; options = ""
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("Fields")
        .onAppear { defs = TaskFieldDefs.fields(for: list) }
    }
}

// MARK: - Board columns (your own, per list)

@MainActor
enum BoardColumns {
    private static let key = "board.columns"
    static let standard = ["To do", "Doing", "Done"]
    static func columns(for list: String?) -> [String] {
        guard let list else { return standard }
        let all = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
        let c = all[list] ?? standard
        return c.count >= 2 ? c : standard
    }
    static func set(_ list: String, _ cols: [String]) {
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
        all[list] = cols
        UserDefaults.standard.set(all, forKey: key)
    }
    /// The stage stored on a task for a column (the first column is "todo", the middle "doing" by default).
    static func stage(_ column: String, in cols: [String]) -> String {
        if column == cols.first { return "todo" }
        if cols == standard && column == "Doing" { return "doing" }
        return column
    }
}

struct BoardColumnsEditor: View {
    let list: String
    @State private var cols: [String] = []
    @State private var new = ""
    var body: some View {
        Form {
            Section {
                ForEach(cols, id: \.self) { Text($0) }
                    .onMove { cols.move(fromOffsets: $0, toOffset: $1); BoardColumns.set(list, cols) }
                    .onDelete { if cols.count > 2 { cols.remove(atOffsets: $0); BoardColumns.set(list, cols) } }
                HStack {
                    TextField("New column (e.g. Review)", text: $new)
                    Button("Add") { cols.insert(new.trimmingCharacters(in: .whitespaces), at: max(0, cols.count - 1)); BoardColumns.set(list, cols); new = "" }
                        .disabled(new.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: { Text("Columns in \(list)") } footer: { Text("The last column means done. Drag to reorder; swipe to remove.") }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Board columns")
        .onAppear { cols = BoardColumns.columns(for: list) }
    }
}

// MARK: - Filter queries for smart lists ("today & #work", "overdue | p1", "!no date & @Home")

enum TaskFilterQuery {
    private static let key = "smart.queries"
    static func text(for id: UUID) -> String? {
        let q = (UserDefaults.standard.dictionary(forKey: key) as? [String: String])?[id.uuidString]
        return (q?.isEmpty ?? true) ? nil : q
    }
    static func set(_ q: String, for id: UUID) {
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        all[id.uuidString] = q.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(all, forKey: key)
    }

    static let help = "today · tomorrow · overdue · 7 days · no date · p1 p2 p3 · #tag · @List · pinned · waiting · someday · evening · has:alert · has:steps · started. Combine with & (and), | (or), ! (not) and ( )."

    /// Does the task match the query? Unknown words match the title, so "call & p1" works.
    static func matches(_ query: String, _ t: TaskItem, now: Date = Date()) -> Bool {
        var tokens = tokenize(query)
        var i = 0
        func peek() -> String? { i < tokens.count ? tokens[i] : nil }
        func next() -> String? { defer { i += 1 }; return peek() }
        func orExpr() -> Bool { var v = andExpr(); while peek() == "|" { _ = next(); let r = andExpr(); v = v || r }; return v }
        func andExpr() -> Bool { var v = unary(); while let p = peek(), p != "|", p != ")" { if p == "&" { _ = next() }; let r = unary(); v = v && r }; return v }
        func unary() -> Bool {
            if peek() == "!" { _ = next(); return !unary() }
            if peek() == "(" { _ = next(); let v = orExpr(); if peek() == ")" { _ = next() }; return v }
            guard let w = next() else { return true }
            return term(w, t, now)
        }
        if tokens.isEmpty { tokens = [] }
        return orExpr()
    }

    private static func tokenize(_ q: String) -> [String] {
        // Multi-word terms first, so "no date" and "7 days" stay whole.
        var s = " " + q.lowercased() + " "
        for (phrase, token) in [("no date", "nodate"), ("next 7 days", "7days"), ("7 days", "7days"), ("this week", "7days"), ("has:alert", "hasalert"), ("has:steps", "hassteps")] {
            s = s.replacingOccurrences(of: phrase, with: token)
        }
        var out: [String] = []
        var cur = ""
        for ch in s {
            if "&|!()".contains(ch) { if !cur.isEmpty { out.append(cur); cur = "" }; out.append(String(ch)) }
            else if ch == " " { if !cur.isEmpty { out.append(cur); cur = "" } }
            else { cur.append(ch) }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    private static func term(_ w: String, _ t: TaskItem, _ now: Date) -> Bool {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: start)!
        switch w {
        case "today": return (t.dueDate.map { $0 < tomorrow }) == true
        case "tomorrow": return (t.dueDate.map { cal.isDate($0, inSameDayAs: tomorrow) }) == true
        case "overdue": return (t.dueDate.map { $0 < (t.hasDueTime ? now : start) }) == true
        case "7days": return (t.dueDate.map { $0 < cal.date(byAdding: .day, value: 7, to: tomorrow)! }) == true
        case "nodate": return t.dueDate == nil
        case "p1": return t.priority == .high
        case "p2": return t.priority == .medium
        case "p3": return t.priority == .low
        case "p4": return t.priority == .none
        case "pinned": return t.isPinned
        case "waiting": return t.isWaitingOn
        case "someday": return t.isSomeday
        case "evening": return t.tags.contains("~evening")
        case "hasalert": return t.alertOffsetMinutes != nil || !TaskMeta.extraReminders(t).isEmpty
        case "hassteps": return !t.microSteps.isEmpty
        case "started": return !TaskMeta.isDeferred(t, now: now)
        default:
            if w.hasPrefix("#") { return t.tags.contains { $0.lowercased() == String(w.dropFirst()) } }
            if w.hasPrefix("@") { return t.listName.lowercased() == String(w.dropFirst()) }
            if w.hasPrefix("energy:") { return "\(t.energy)".lowercased() == String(w.dropFirst(7)) }
            return t.title.lowercased().contains(w)
        }
    }
}

// MARK: - Timeline (Gantt) for a list or project

struct TaskTimelineView: View {
    let title: String
    let tasks: [TaskItem]
    @State private var dayWidth: CGFloat = 34
    private let cal = Calendar.current

    var body: some View {
        let items = tasks.filter { !$0.isDone && ($0.dueDate != nil || TaskMeta.startDate($0) != nil) }
            .sorted { span($0).start < span($1).start }
        let first = cal.startOfDay(for: min(Date(), items.map { span($0).start }.min() ?? Date()))
        let last = max(cal.date(byAdding: .day, value: 14, to: first)!, items.map { span($0).end }.max() ?? first)
        let days = max(14, (cal.dateComponents([.day], from: first, to: last).day ?? 14) + 2)
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: 140)
                    ForEach(0..<days, id: \.self) { i in
                        let d = cal.date(byAdding: .day, value: i, to: first)!
                        Text(d.formatted(.dateTime.day())).font(.caption2.weight(cal.isDateInToday(d) ? .bold : .regular))
                            .foregroundStyle(cal.isDateInToday(d) ? DS.Palette.accent : DS.Palette.inkSoft)
                            .frame(width: dayWidth)
                    }
                }
                ForEach(items) { t in
                    let s = span(t)
                    let offset = CGFloat(cal.dateComponents([.day], from: first, to: cal.startOfDay(for: s.start)).day ?? 0)
                    let length = CGFloat(max(1, (cal.dateComponents([.day], from: cal.startOfDay(for: s.start), to: cal.startOfDay(for: s.end)).day ?? 0) + 1))
                    HStack(spacing: 0) {
                        Text(t.title).font(.caption).lineLimit(1).frame(width: 140, alignment: .leading)
                        ZStack(alignment: .leading) {
                            Color.clear.frame(width: CGFloat(days) * dayWidth, height: 24)
                            TimelineBar(task: t, width: length * dayWidth, dayWidth: dayWidth)
                                .offset(x: offset * dayWidth)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(title + " · Timeline")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Days wide") { dayWidth = 44 }
                    Button("Compact") { dayWidth = 24 }
                } label: { Image(systemName: "arrow.left.and.right") }
            }
        }
        .overlay { if items.isEmpty { ContentUnavailableView("Nothing scheduled", systemImage: "chart.bar.xaxis", description: Text("Give tasks a start date or a due date to see them here.")) } }
    }

    private func span(_ t: TaskItem) -> (start: Date, end: Date) {
        let end = t.dueDate ?? TaskMeta.startDate(t) ?? Date()
        let start = TaskMeta.startDate(t) ?? end
        return (min(start, end), max(start, end))
    }
}

/// One bar; drag it sideways to move the task (start and due move together).
private struct TimelineBar: View {
    @Bindable var task: TaskItem
    let width: CGFloat
    let dayWidth: CGFloat
    @State private var drag: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill((task.priority == .none ? DS.Palette.accent : task.priority.color).gradient)
            .frame(width: max(dayWidth * 0.8, width - 4), height: 20)
            .offset(x: drag)
            .gesture(DragGesture()
                .onChanged { drag = $0.translation.width }
                .onEnded { v in
                    let days = Int((v.translation.width / dayWidth).rounded())
                    drag = 0
                    guard days != 0 else { return }
                    let cal = Calendar.current
                    task.dueDate = task.dueDate.flatMap { cal.date(byAdding: .day, value: days, to: $0) }
                    if let s = TaskMeta.startDate(task) { TaskMeta.setStart(task, cal.date(byAdding: .day, value: days, to: s)) }
                    task.updatedAt = Date()
                    try? CalendarService.shared.push(task)
                    TaskAlerts.schedule(task)
                    Haptics.tap()
                })
            .accessibilityLabel("\(task.title), drag to move")
    }
}

// MARK: - Dashboard for a list or project

struct TaskDashboardView: View {
    let title: String
    let tasks: [TaskItem]

    var body: some View {
        let cal = Calendar.current
        let now = Date()
        let open = tasks.filter { !$0.isDone }
        let done = tasks.filter { $0.isDone && !TaskMeta.isWontDo($0) }
        let wont = tasks.filter(TaskMeta.isWontDo)
        let overdue = open.filter { ($0.dueDate ?? .distantFuture) < cal.startOfDay(for: now) }
        let pct = tasks.isEmpty ? 0 : Double(done.count) / Double(max(1, done.count + open.count))
        let next7 = (0..<7).map { i -> (Date, Int) in
            let d = cal.date(byAdding: .day, value: i, to: cal.startOfDay(for: now))!
            return (d, open.filter { $0.dueDate.map { cal.isDate($0, inSameDayAs: d) } == true }.count)
        }
        let people = Dictionary(grouping: open.compactMap { t in (TaskMeta.field(t, "Owner") ?? TaskMeta.field(t, "Person") ?? TaskMeta.field(t, "Assignee")).map { ($0, t) } }, by: \.0)
        let columns = Dictionary(grouping: open, by: { $0.stage == "todo" ? "To do" : $0.stage == "doing" ? "Doing" : $0.stage })
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 18) {
                    ZStack {
                        Circle().stroke(DS.Palette.accent.opacity(0.15), lineWidth: 12)
                        Circle().trim(from: 0, to: pct).stroke(DS.Palette.accent.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
                        Text("\(Int(pct * 100))%").font(.title2.weight(.semibold)).monospacedDigit()
                    }
                    .frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 6) {
                        stat("Open", open.count, DS.Palette.ink)
                        stat("Done", done.count, DS.Palette.calm)
                        stat("Overdue", overdue.count, overdue.isEmpty ? DS.Palette.inkSoft : .orange)
                        stat("Won't do", wont.count, DS.Palette.inkSoft)
                    }
                }
                .bodyCard()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Due this week").font(DS.Font.headline)
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(next7, id: \.0) { d, n in
                            VStack(spacing: 4) {
                                Text("\(n)").font(.caption2).monospacedDigit()
                                RoundedRectangle(cornerRadius: 4).fill(DS.Palette.accent.opacity(n == 0 ? 0.15 : 0.8)).frame(height: CGFloat(6 + n * 14))
                                Text(d.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 120, alignment: .bottom)
                }
                .bodyCard()
                if !people.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Workload by person").font(DS.Font.headline)
                        ForEach(people.keys.sorted(), id: \.self) { p in
                            HStack { Text(p); Spacer(); Text("\(people[p]?.count ?? 0) open").foregroundStyle(DS.Palette.inkSoft) }
                        }
                    }
                    .bodyCard()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("By column").font(DS.Font.headline)
                    ForEach(columns.keys.sorted(), id: \.self) { c in
                        HStack { Text(c); Spacer(); Text("\(columns[c]?.count ?? 0)").foregroundStyle(DS.Palette.inkSoft) }
                    }
                    Text("By priority").font(DS.Font.headline).padding(.top, 6)
                    ForEach(TaskPriority.allCases.reversed(), id: \.self) { p in
                        let n = open.filter { $0.priority == p }.count
                        if n > 0 { HStack { Label(p.label, systemImage: "flag.fill").foregroundStyle(p.color); Spacer(); Text("\(n)").foregroundStyle(DS.Palette.inkSoft) } }
                    }
                }
                .bodyCard()
            }
            .padding(DS.Space.m)
        }
        .navigationTitle(title + " · Dashboard")
        .premiumBackground(DS.Palette.accent)
    }

    private func stat(_ t: String, _ n: Int, _ c: Color) -> some View {
        HStack { Text(t).font(.subheadline).foregroundStyle(DS.Palette.inkSoft); Spacer(); Text("\(n)").font(.headline).monospacedDigit().foregroundStyle(c) }
    }
}

// MARK: - Daily and weekly goals, with a streak

@MainActor
enum TaskGoals {
    static let dailyKey = "task.goal.daily", weeklyKey = "task.goal.weekly", onKey = "task.goal.on"
    static var daily: Int { let v = UserDefaults.standard.integer(forKey: dailyKey); return v > 0 ? v : 5 }
    static var weekly: Int { let v = UserDefaults.standard.integer(forKey: weeklyKey); return v > 0 ? v : 25 }

    /// Days in a row (ending yesterday, plus today once it's reached) that hit the daily goal.
    static func streak(_ done: [TaskItem]) -> Int {
        let cal = Calendar.current
        var counts: [Date: Int] = [:]
        for t in done where !TaskMeta.isWontDo(t) { if let c = t.completedAt { counts[cal.startOfDay(for: c), default: 0] += 1 } }
        var day = cal.startOfDay(for: Date())
        var n = (counts[day] ?? 0) >= daily ? 1 : 0
        day = cal.date(byAdding: .day, value: -1, to: day)!
        while (counts[day] ?? 0) >= daily, n < 999 { n += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }
        return n
    }
}

struct TaskGoalsCard: View {
    let done: [TaskItem]
    @AppStorage(TaskGoals.dailyKey) private var dailyRaw = 0
    @AppStorage(TaskGoals.weeklyKey) private var weeklyRaw = 0
    @AppStorage(TaskGoals.onKey) private var on = true

    var body: some View {
        if on {
            let cal = Calendar.current
            let real = done.filter { !TaskMeta.isWontDo($0) }
            let today = real.filter { $0.completedAt.map { cal.isDateInToday($0) } ?? false }.count
            let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
            let week = real.filter { ($0.completedAt ?? .distantPast) >= weekStart }.count
            let streak = TaskGoals.streak(real)
            HStack(spacing: 16) {
                ring(today, TaskGoals.daily, "Today")
                ring(week, TaskGoals.weekly, "Week")
                VStack(alignment: .leading, spacing: 2) {
                    Label("\(streak)-day streak", systemImage: "flame.fill").font(.subheadline.weight(.semibold)).foregroundStyle(streak > 0 ? .orange : DS.Palette.inkSoft)
                    Menu {
                        Picker("Daily goal", selection: Binding(get: { TaskGoals.daily }, set: { dailyRaw = $0 })) {
                            ForEach([3, 5, 8, 10, 15], id: \.self) { Text("\($0) a day").tag($0) }
                        }
                        Picker("Weekly goal", selection: Binding(get: { TaskGoals.weekly }, set: { weeklyRaw = $0 })) {
                            ForEach([15, 25, 40, 60], id: \.self) { Text("\($0) a week").tag($0) }
                        }
                        Button("Hide goals") { on = false }
                    } label: { Text("Goals").font(.caption).foregroundStyle(DS.Palette.accent) }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }

    private func ring(_ n: Int, _ goal: Int, _ title: String) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().stroke(DS.Palette.calm.opacity(0.15), lineWidth: 5)
                Circle().trim(from: 0, to: min(1, CGFloat(n) / CGFloat(max(1, goal)))).stroke(DS.Palette.calm, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                Text("\(n)").font(.caption.weight(.semibold)).monospacedDigit()
            }
            .frame(width: 40, height: 40)
            Text("\(title) · \(goal)").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
        }
    }
}
