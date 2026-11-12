import SwiftUI
import SwiftData

/// Build a saved filter: priority, tags, lists, due window, energy.
struct SmartListEditor: View {
    var list: SmartList?
    let allLists: [String]
    let allTags: [String]
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var tasks: [TaskItem]
    @State private var name = ""
    @State private var icon = "line.3.horizontal.decrease.circle"
    @State private var priorities: Set<Int> = []
    @State private var tags: Set<String> = []
    @State private var lists: Set<String> = []
    @State private var due: Int = -1                 // -1 any, 0 today, 7 week, 30 month
    @State private var includeNoDate = true
    @State private var energy: Int = 0               // 0 any

    private let icons = ["line.3.horizontal.decrease.circle", "star", "flame", "briefcase", "house", "cart", "heart", "bolt", "book", "person.2"]

    private var preview: SmartList {
        let s = SmartList(name: name)
        s.priorities = Array(priorities); s.tags = Array(tags); s.lists = Array(lists)
        s.dueWithinDays = due < 0 ? nil : due; s.includeNoDate = includeNoDate; s.energy = energy == 0 ? nil : energy
        return s
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Work this week", text: $name)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(icons, id: \.self) { i in
                                Button { icon = i } label: {
                                    Image(systemName: i).frame(width: 34, height: 34)
                                        .background(icon == i ? DS.Palette.accent.opacity(0.2) : .clear, in: Circle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                Section("Priority") {
                    ForEach([3, 2, 1, 0], id: \.self) { p in
                        Toggle(["None", "Low", "Medium", "High"][p], isOn: binding($priorities, p))
                    }
                }
                Section("Due") {
                    Picker("Due", selection: $due) {
                        Text("Any time").tag(-1); Text("Today or overdue").tag(0); Text("Within 7 days").tag(7); Text("Within 30 days").tag(30)
                    }
                    Toggle("Include tasks with no date", isOn: $includeNoDate)
                }
                Section("Energy") {
                    Picker("Energy", selection: $energy) {
                        Text("Any").tag(0)
                        ForEach(EnergyLevel.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                }
                if !allTags.isEmpty {
                    Section("Any of these tags") { ForEach(allTags, id: \.self) { Toggle("#\($0)", isOn: binding($tags, $0)) } }
                }
                Section("Any of these lists") { ForEach(allLists, id: \.self) { Toggle($0, isOn: binding($lists, $0)) } }
                Section { Text("\(tasks.filter { preview.matches($0) }.count) tasks match right now").foregroundStyle(DS.Palette.inkSoft) }
            }
            .navigationTitle(list == nil ? "New Smart List" : "Edit Smart List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .onAppear {
                guard let l = list else { return }
                name = l.name; icon = l.icon; priorities = Set(l.priorities); tags = Set(l.tags); lists = Set(l.lists)
                due = l.dueWithinDays ?? -1; includeNoDate = l.includeNoDate; energy = l.energy ?? 0
            }
        }
    }

    private func binding<T: Hashable>(_ set: Binding<Set<T>>, _ v: T) -> Binding<Bool> {
        Binding(get: { set.wrappedValue.contains(v) }, set: { on in if on { set.wrappedValue.insert(v) } else { set.wrappedValue.remove(v) } })
    }

    private func save() {
        let s = list ?? SmartList(name: name)
        if list == nil { ctx.insert(s) }
        s.name = name; s.icon = icon; s.priorities = Array(priorities).sorted(); s.tags = Array(tags).sorted(); s.lists = Array(lists).sorted()
        s.dueWithinDays = due < 0 ? nil : due; s.includeNoDate = includeNoDate; s.energy = energy == 0 ? nil : energy
        Haptics.success()
        dismiss()
    }
}

/// Rename, merge and remove tags across every task.
struct TagsManagerView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var tasks: [TaskItem]
    @State private var renaming: String?
    @State private var newName = ""

    private var counts: [(tag: String, count: Int)] {
        Dictionary(tasks.flatMap(\.tags).map { ($0, 1) }, uniquingKeysWith: +).map { ($0.key, $0.value) }.sorted { $0.tag < $1.tag }
    }

    var body: some View {
        List {
            if counts.isEmpty {
                ContentUnavailableView("No tags yet", systemImage: "number", description: Text("Add #tags when you type a task, like “Call bank #money”."))
            }
            Section { } footer: { Text("Renaming a tag to one that already exists merges them.") }
            ForEach(counts, id: \.tag) { c in
                HStack {
                    Text("#\(c.tag)")
                    Spacer()
                    Text("\(c.count)").foregroundStyle(DS.Palette.inkSoft)
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { remove(c.tag) }
                    Button("Rename") { newName = c.tag; renaming = c.tag }.tint(DS.Palette.accent)
                }
            }
        }
        .navigationTitle("Tags")
        .alert("Rename #\(renaming ?? "")", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("New name", text: $newName).textInputAutocapitalization(.never)
            Button("Rename") { if let old = renaming { rename(old, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func rename(_ old: String, to raw: String) {
        let new = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "").replacingOccurrences(of: " ", with: "-")
        guard !new.isEmpty, new != old else { return }
        for t in tasks where t.tags.contains(old) {
            var tags = t.tags.filter { $0 != old }
            if !tags.contains(new) { tags.append(new) }
            t.tags = tags; t.updatedAt = Date()
        }
        Haptics.success()
    }

    private func remove(_ tag: String) {
        for t in tasks where t.tags.contains(tag) { t.tags.removeAll { $0 == tag }; t.updatedAt = Date() }
    }
}
