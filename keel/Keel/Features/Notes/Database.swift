import SwiftUI
import SwiftData

/// Databases: a page whose sub-pages are rows with properties, shown as a table, board, calendar,
/// gallery or list, with sorting and filtering.
@MainActor
enum NotesDatabase {
    static let views: [(id: String, title: String, icon: String)] = [
        ("table", "Table", "tablecells"), ("board", "Board", "rectangle.split.3x1"), ("calendar", "Calendar", "calendar"),
        ("gallery", "Gallery", "square.grid.2x2"), ("list", "List", "list.bullet"),
    ]

    @discardableResult
    static func create(title: String, parent: Note?, ctx: ModelContext) -> Note {
        let db = Note(title: title, blocks: [])
        db.isDatabase = true
        db.icon = "🗃️"
        db.parentId = parent?.id
        db.schema = [
            DBProperty(name: "Status", kind: .status, options: ["Not started", "In progress", "Done"]),
            DBProperty(name: "Date", kind: .date),
            DBProperty(name: "Tags", kind: .multiSelect, options: []),
        ]
        db.dbGroupBy = db.schema.first?.id
        ctx.insert(db)
        return db
    }

    static func rows(of db: Note, in notes: [Note]) -> [Note] {
        var rows = notes.filter { $0.parentId == db.id && !$0.isTemplate }
        if let p = db.dbFilterProp, let v = db.dbFilterValue, !v.isEmpty {
            rows = rows.filter { ($0.props[p] ?? "").lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains(v.lowercased()) }
        }
        let asc = db.dbSortAscending
        switch db.dbSortBy {
        case nil, "created": rows.sort { asc ? $0.createdAt < $1.createdAt : $0.createdAt > $1.createdAt }
        case "title": rows.sort { asc ? $0.title.localizedCompare($1.title) == .orderedAscending : $0.title.localizedCompare($1.title) == .orderedDescending }
        case let pid?:
            let kind = db.schema.first { $0.id == pid }?.kind
            rows.sort { a, b in
                let x = a.props[pid] ?? "", y = b.props[pid] ?? ""
                if x.isEmpty != y.isEmpty { return !x.isEmpty }          // blanks last
                if kind == .number { return asc ? (Double(x) ?? 0) < (Double(y) ?? 0) : (Double(x) ?? 0) > (Double(y) ?? 0) }
                return asc ? x < y : x > y
            }
        }
        return rows
    }

    static func newRow(in db: Note, ctx: ModelContext, preset: [String: String] = [:]) -> Note {
        let r = Note(title: "")
        r.parentId = db.id
        r.props = preset
        ctx.insert(r)
        return r
    }

    static let dateFormat: Date.ISO8601FormatStyle = .iso8601.year().month().day()
    static func date(_ s: String?) -> Date? { s.flatMap { try? Date($0, strategy: dateFormat) } }
    static func string(_ d: Date) -> String { d.formatted(dateFormat) }
}

struct DatabaseView: View {
    @Bindable var db: Note
    var open: (Note) -> Void                     // the page editor pushes the row (destinations can't live inside a List row)
    @Environment(\.modelContext) private var ctx
    @Query private var notes: [Note]
    @State private var editingSchema = false
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!

    private var rows: [Note] { NotesDatabase.rows(of: db, in: notes) }
    private var groupProp: DBProperty? {
        db.schema.first { $0.id == db.dbGroupBy && ($0.kind == .select || $0.kind == .status) }
            ?? db.schema.first { $0.kind == .status || $0.kind == .select }
    }
    private var dateProp: DBProperty? { db.schema.first { $0.kind == .date } }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            controls
            switch db.dbView {
            case "board": board
            case "calendar": calendar
            case "gallery": gallery
            case "list": list
            default: table
            }
            Button { open(NotesDatabase.newRow(in: db, ctx: ctx)) } label: { Label("New", systemImage: "plus") }
                .font(DS.Font.caption).buttonStyle(.bordered)
        }
        .padding(.vertical, DS.Space.s)
        .sheet(isPresented: $editingSchema) { SchemaEditor(db: db) }
    }

    // MARK: Controls

    private var controls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NotesDatabase.views, id: \.id) { v in
                    Button { withAnimation { db.dbView = v.id } } label: {
                        Label(v.title, systemImage: v.icon).font(DS.Font.caption)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(db.dbView == v.id ? DS.Palette.accent.opacity(0.18) : DS.Palette.elevated, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Menu {
                    Picker("Sort by", selection: Binding(get: { db.dbSortBy ?? "created" }, set: { db.dbSortBy = $0 })) {
                        Text("Created").tag("created"); Text("Name").tag("title")
                        ForEach(db.schema) { Text($0.name).tag($0.id) }
                    }
                    Toggle("Ascending", isOn: $db.dbSortAscending)
                } label: { Image(systemName: "arrow.up.arrow.down").padding(6) }
                Menu {
                    Button("No filter") { db.dbFilterProp = nil; db.dbFilterValue = nil }
                    ForEach(db.schema.filter { [.select, .status, .multiSelect].contains($0.kind) }) { p in
                        Menu(p.name) {
                            ForEach(p.options, id: \.self) { o in Button(o) { db.dbFilterProp = p.id; db.dbFilterValue = o } }
                        }
                    }
                } label: {
                    Image(systemName: db.dbFilterValue == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill").padding(6)
                }
                if db.dbView == "board" {
                    Menu {
                        ForEach(db.schema.filter { $0.kind == .select || $0.kind == .status }) { p in Button(p.name) { db.dbGroupBy = p.id } }
                    } label: { Label("Group", systemImage: "square.split.2x1").font(DS.Font.caption) }
                }
                Button { editingSchema = true } label: { Label("Properties", systemImage: "slider.horizontal.3").font(DS.Font.caption) }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Views

    private var table: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    headerCell("Name", width: 180)
                    ForEach(db.schema) { headerCell($0.name, width: 150) }
                }
                ForEach(rows) { r in
                    GridRow {
                        Button { open(r) } label: {
                            HStack(spacing: 6) {
                                Text(r.icon ?? "📄")
                                Text(r.title.isEmpty ? "Untitled" : r.title).lineLimit(1).foregroundStyle(DS.Palette.ink)
                            }
                            .padding(8).frame(width: 180, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .overlay(Rectangle().stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
                        ForEach(db.schema) { p in
                            PropertyValueEditor(property: p, row: r, compact: true)
                                .padding(.horizontal, 6).frame(width: 150, height: 38, alignment: .leading)
                                .overlay(Rectangle().stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
                        }
                    }
                }
            }
        }
    }

    private func headerCell(_ title: String, width: CGFloat) -> some View {
        Text(title).font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft)
            .padding(8).frame(width: width, alignment: .leading)
            .background(DS.Palette.elevated)
            .overlay(Rectangle().stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
    }

    private var board: some View {
        let p = groupProp
        let columns = (p?.options ?? []) + ["No \(p?.name ?? "status")"]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(columns, id: \.self) { col in
                    let isNone = col == columns.last
                    let items = rows.filter { r in
                        let v = p.flatMap { r.props[$0.id] } ?? ""
                        return isNone ? v.isEmpty || !(p?.options.contains(v) ?? false) : v == col
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(col).font(DS.Font.caption.weight(.semibold))
                            Text("\(items.count)").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        ForEach(items) { r in card(r).draggable(r.id.uuidString) }
                        Button {
                            var preset: [String: String] = [:]
                            if let p, !isNone { preset[p.id] = col }
                            open(NotesDatabase.newRow(in: db, ctx: ctx, preset: preset))
                        } label: { Label("New", systemImage: "plus").font(DS.Font.caption) }
                        .buttonStyle(.plain).foregroundStyle(DS.Palette.inkSoft)
                    }
                    .padding(10)
                    .frame(width: 220, alignment: .topLeading)
                    .background(DS.Palette.elevated.opacity(0.6), in: .rect(cornerRadius: 12))
                    .dropDestination(for: String.self) { ids, _ in
                        guard let p else { return false }
                        for id in ids { notes.first { $0.id.uuidString == id }?.props[p.id] = isNone ? nil : col }
                        Haptics.tap()
                        return true
                    }
                }
            }
        }
    }

    private func card(_ r: Note) -> some View {
        Button { open(r) } label: {
            VStack(alignment: .leading, spacing: 4) {
                if let data = r.cover, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFill().frame(height: 70).clipped().clipShape(.rect(cornerRadius: 6))
                }
                Text("\(r.icon.map { $0 + " " } ?? "")\(r.title.isEmpty ? "Untitled" : r.title)").font(DS.Font.body).foregroundStyle(DS.Palette.ink).lineLimit(2)
                ForEach(db.schema.filter { $0.id != groupProp?.id && !(r.props[$0.id] ?? "").isEmpty }.prefix(2)) { p in
                    Text(PropertyValueEditor.display(p, r.props[p.id] ?? "")).font(.caption2).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                }
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.canvas, in: .rect(cornerRadius: 8))
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    private var gallery: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(rows) { r in
                Button { open(r) } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Group {
                            if let data = r.cover, let img = UIImage(data: data) {
                                Image(uiImage: img).resizable().scaledToFill()
                            } else {
                                Text(r.icon ?? "📄").font(.system(size: 36)).frame(maxWidth: .infinity, maxHeight: .infinity).background(DS.Palette.elevated)
                            }
                        }
                        .frame(height: 100).clipped()
                        Text(r.title.isEmpty ? "Untitled" : r.title).font(DS.Font.body).foregroundStyle(DS.Palette.ink).lineLimit(2).padding(8)
                    }
                    .background(DS.Palette.canvas)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { r in
                Button { open(r) } label: {
                    HStack {
                        Text(r.icon ?? "📄")
                        Text(r.title.isEmpty ? "Untitled" : r.title).foregroundStyle(DS.Palette.ink)
                        Spacer()
                        ForEach(db.schema.filter { !(r.props[$0.id] ?? "").isEmpty }.prefix(2)) { p in
                            Text(PropertyValueEditor.display(p, r.props[p.id] ?? "")).font(.caption2).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }

    private var calendar: some View {
        let cal = Calendar.current
        let days = cal.range(of: .day, in: .month, for: month)!.count
        let lead = (cal.component(.weekday, from: month) - cal.firstWeekday + 7) % 7
        return VStack(spacing: 6) {
            HStack {
                Button { month = cal.date(byAdding: .month, value: -1, to: month)! } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year())).font(DS.Font.headline)
                Spacer()
                Button { month = cal.date(byAdding: .month, value: 1, to: month)! } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.plain)
            if let dp = dateProp {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                    ForEach(0..<(lead + days), id: \.self) { i in
                        if i < lead {
                            Color.clear.frame(height: 64)
                        } else {
                            let day = cal.date(byAdding: .day, value: i - lead, to: month)!
                            let items = rows.filter { NotesDatabase.date($0.props[dp.id]).map { cal.isDate($0, inSameDayAs: day) } ?? false }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(i - lead + 1)").font(.caption2).foregroundStyle(cal.isDateInToday(day) ? DS.Palette.accent : DS.Palette.inkSoft)
                                ForEach(items.prefix(2)) { r in
                                    Text(r.title.isEmpty ? "Untitled" : r.title).font(.system(size: 9)).lineLimit(1)
                                        .padding(2).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(DS.Palette.accent.opacity(0.15), in: .rect(cornerRadius: 3))
                                        .onTapGesture { open(r) }
                                }
                                if items.count > 2 { Text("+\(items.count - 2)").font(.system(size: 9)).foregroundStyle(DS.Palette.inkSoft) }
                                Spacer(minLength: 0)
                            }
                            .padding(3).frame(height: 64, alignment: .topLeading)
                            .background(DS.Palette.elevated.opacity(0.5), in: .rect(cornerRadius: 4))
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { open(NotesDatabase.newRow(in: db, ctx: ctx, preset: [dp.id: NotesDatabase.string(day)])) }
                        }
                    }
                }
                Text("Double-tap a day to add a page on that date.").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
            } else {
                Text("Add a Date property to see pages on a calendar.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
        }
    }
}

/// Edits one property value on a row.
struct PropertyValueEditor: View {
    let property: DBProperty
    @Bindable var row: Note
    var compact = false

    private var value: Binding<String> {
        Binding(get: { row.props[property.id] ?? "" }, set: { row.props[property.id] = $0.isEmpty ? nil : $0 })
    }

    static func display(_ p: DBProperty, _ v: String) -> String {
        switch p.kind {
        case .checkbox: return v == "1" ? "☑︎ \(p.name)" : ""
        case .date: return NotesDatabase.date(v)?.formatted(date: .abbreviated, time: .omitted) ?? v
        default: return v
        }
    }

    var body: some View {
        switch property.kind {
        case .checkbox:
            Toggle("", isOn: Binding(get: { value.wrappedValue == "1" }, set: { value.wrappedValue = $0 ? "1" : "" })).labelsHidden()
        case .date:
            if let d = NotesDatabase.date(value.wrappedValue) {
                DatePicker("", selection: Binding(get: { d }, set: { value.wrappedValue = NotesDatabase.string($0) }), displayedComponents: .date)
                    .labelsHidden()
                    .contextMenu { Button("Clear date", role: .destructive) { value.wrappedValue = "" } }
            } else {
                Button("Add date") { value.wrappedValue = NotesDatabase.string(Date()) }.font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
        case .select, .status:
            Menu {
                Button("None") { value.wrappedValue = "" }
                ForEach(property.options, id: \.self) { o in Button(o) { value.wrappedValue = o } }
            } label: {
                Text(value.wrappedValue.isEmpty ? "Empty" : value.wrappedValue)
                    .font(DS.Font.caption).lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(value.wrappedValue.isEmpty ? Color.clear : Self.tint(value.wrappedValue).opacity(0.2), in: Capsule())
                    .foregroundStyle(value.wrappedValue.isEmpty ? DS.Palette.inkSoft : DS.Palette.ink)
            }
        case .multiSelect:
            Menu {
                ForEach(property.options, id: \.self) { o in
                    let on = selectedTags.contains(o)
                    Button { toggleTag(o) } label: { if on { Label(o, systemImage: "checkmark") } else { Text(o) } }
                }
            } label: {
                Text(value.wrappedValue.isEmpty ? "Empty" : value.wrappedValue).font(DS.Font.caption).lineLimit(1)
                    .foregroundStyle(value.wrappedValue.isEmpty ? DS.Palette.inkSoft : DS.Palette.ink)
            }
        case .number:
            TextField("Empty", text: value).keyboardType(.decimalPad).font(DS.Font.caption)
        case .url:
            TextField("Empty", text: value).keyboardType(.URL).textInputAutocapitalization(.never).font(DS.Font.caption)
        default:
            TextField("Empty", text: value).font(DS.Font.caption)
        }
    }

    private var selectedTags: [String] {
        (row.props[property.id] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private func toggleTag(_ o: String) {
        var t = selectedTags
        if let i = t.firstIndex(of: o) { t.remove(at: i) } else { t.append(o) }
        value.wrappedValue = t.joined(separator: ", ")
    }

    static func tint(_ s: String) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .yellow, .red]
        let lower = s.lowercased()
        if lower.contains("done") || lower.contains("complete") { return .green }
        if lower.contains("progress") || lower.contains("doing") { return .blue }
        if lower.contains("not started") || lower.contains("todo") || lower.contains("to do") { return .gray }
        return palette[abs(s.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % palette.count]
    }
}

/// The properties panel at the top of a database row's page.
struct DatabaseRowProperties: View {
    @Bindable var row: Note
    let db: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(db.schema) { p in
                HStack {
                    Label(p.name, systemImage: icon(p.kind)).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).frame(width: 120, alignment: .leading)
                    PropertyValueEditor(property: p, row: row)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func icon(_ k: DBProperty.Kind) -> String {
        switch k {
        case .text: "text.alignleft"; case .number: "number"; case .select: "chevron.down.circle"; case .multiSelect: "list.bullet"
        case .status: "circle.dotted"; case .date: "calendar"; case .checkbox: "checkmark.square"; case .url: "link"; case .person: "person"
        }
    }
}

/// Add, rename, retype and delete properties, and manage select options.
struct SchemaEditor: View {
    @Bindable var db: Note
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var newKind: DBProperty.Kind = .text

    var body: some View {
        NavigationStack {
            List {
                ForEach($db.schema) { $p in
                    Section {
                        TextField("Name", text: $p.name).font(DS.Font.headline)
                        Picker("Type", selection: $p.kind) {
                            ForEach(DBProperty.Kind.allCases, id: \.self) { Text(label($0)).tag($0) }
                        }
                        if [.select, .status, .multiSelect].contains(p.kind) {
                            ForEach(p.options.indices, id: \.self) { i in
                                TextField("Option", text: Binding(get: { i < p.options.count ? p.options[i] : "" }, set: { if i < p.options.count { p.options[i] = $0 } }))
                            }
                            .onDelete { p.options.remove(atOffsets: $0) }
                            Button("Add option") { p.options.append("Option \(p.options.count + 1)") }
                        }
                    }
                }
                .onDelete { db.schema.remove(atOffsets: $0) }
                Section("New property") {
                    TextField("Name", text: $newName)
                    Picker("Type", selection: $newKind) { ForEach(DBProperty.Kind.allCases, id: \.self) { Text(label($0)).tag($0) } }
                    Button("Add property") {
                        db.schema.append(DBProperty(name: newName, kind: newKind,
                                                    options: newKind == .status ? ["Not started", "In progress", "Done"] : []))
                        newName = ""
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Properties")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func label(_ k: DBProperty.Kind) -> String {
        switch k {
        case .text: "Text"; case .number: "Number"; case .select: "Select"; case .multiSelect: "Multi-select"
        case .status: "Status"; case .date: "Date"; case .checkbox: "Checkbox"; case .url: "URL"; case .person: "Person"
        }
    }
}
