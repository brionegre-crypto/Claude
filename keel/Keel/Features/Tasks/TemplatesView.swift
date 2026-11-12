import SwiftUI
import SwiftData

/// Reusable checklists: packing list, weekly reset, client onboarding… Apply one to create all its tasks.
struct TemplatesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \TaskTemplate.name) private var templates: [TaskTemplate]
    @State private var editing: TaskTemplate?
    @State private var showNew = false
    @State private var applied: String?

    var body: some View {
        List {
            if let applied {
                Label(applied, systemImage: "checkmark.circle.fill").foregroundStyle(DS.Palette.calm).font(DS.Font.caption)
                    .listRowBackground(Color.clear)
            }
            ForEach(templates) { t in
                HStack(spacing: DS.Space.m) {
                    Image(systemName: t.icon).foregroundStyle(DS.Palette.accent).frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name).font(DS.Font.headline)
                        Text("\(t.items.count) item\(t.items.count == 1 ? "" : "s")\(t.listName.isEmpty ? "" : " · \(t.listName)")")
                            .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                    Spacer()
                    Button("Use") { apply(t) }.buttonStyle(.borderedProminent).tint(DS.Palette.accent).font(DS.Font.caption)
                }
                .contentShape(Rectangle())
                .onTapGesture { editing = t }
                .swipeActions { Button(role: .destructive) { ctx.delete(t) } label: { Label("Delete", systemImage: "trash") } }
            }
        }
        .navigationTitle("Templates")
        .toolbar { Button { showNew = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showNew) { TemplateEditor(template: nil) }
        .sheet(item: $editing) { TemplateEditor(template: $0) }
        .onAppear { if templates.isEmpty { seed() } }
    }

    private func apply(_ t: TaskTemplate) {
        for line in t.items where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            QuickAdd.create(line, in: ctx, defaultList: t.listName.isEmpty ? nil : t.listName)
        }
        Haptics.success()
        withAnimation { applied = "Added \(t.items.count) tasks from “\(t.name)”" }
    }

    private func seed() {
        let starters: [(String, String, [String])] = [
            ("Weekly reset", "arrow.triangle.2.circlepath", ["Clear inbox to zero", "Review calendar for next week", "Do the weekly review", "Plan meals", "Tidy desk for 10 minutes", "Laundry"]),
            ("Packing list", "suitcase", ["Phone charger", "Headphones", "Toothbrush", "Meds", "ID / passport", "Clothes for each day", "Check-in for flight"]),
            ("Morning launch", "sunrise", ["Take meds", "Water", "Check today's one thing", "10 minutes outside"]),
            ("New project kickoff", "flag", ["Write the goal in one sentence", "List what done looks like", "Book a kickoff meeting", "Break the first milestone into tasks"]),
        ]
        for (name, icon, items) in starters {
            let t = TaskTemplate(name: name, items: items)
            t.icon = icon
            ctx.insert(t)
        }
    }
}

struct TemplateEditor: View {
    let template: TaskTemplate?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var text = ""
    @State private var list = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Template name", text: $name)
                TextField("List (optional)", text: $list)
                Section {
                    TextEditor(text: $text).frame(minHeight: 200)
                } header: { Text("Tasks, one per line") } footer: {
                    Text("Quick-add works here too: “Pack charger !high”, “Call venue tomorrow 10am”.")
                }
            }
            .navigationTitle(template == nil ? "New Template" : "Edit Template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let items = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        if let t = template {
                            t.name = name; t.items = items; t.listName = list
                        } else {
                            let t = TaskTemplate(name: name, items: items); t.listName = list
                            ctx.insert(t)
                        }
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .onAppear {
                if let t = template { name = t.name; text = t.items.joined(separator: "\n"); list = t.listName }
            }
        }
    }
}

/// Saves the tasks currently in a list as a reusable template.
@MainActor
enum TemplateSaver {
    static func save(listName: String, tasks: [TaskItem], ctx: ModelContext) {
        let t = TaskTemplate(name: listName, items: tasks.filter { $0.listName == listName }.map(\.title))
        t.listName = listName
        ctx.insert(t)
        Haptics.success()
    }
}
