import SwiftUI
import SwiftData

/// Projects: a bigger outcome made of tasks, with milestones, a deadline and progress.
struct ProjectsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<Project> { !$0.isArchived }, sort: \Project.createdAt) private var projects: [Project]
    @Query private var tasks: [TaskItem]
    @State private var showNew = false

    var body: some View {
        List {
            if projects.isEmpty {
                ContentUnavailableView {
                    Label("No projects yet", systemImage: "folder")
                } description: {
                    Text("A project is anything with more than one step: a launch, a move, a trip.")
                } actions: {
                    Button("New project") { showNew = true }.buttonStyle(.borderedProminent).tint(DS.Palette.accent)
                }
                .listRowBackground(Color.clear)
            }
            ForEach(projects) { p in
                NavigationLink { ProjectDetailView(project: p) } label: { ProjectRow(project: p, tasks: tasks.filter { $0.projectId == p.id }) }
            }
        }
        .navigationTitle("Projects")
        .toolbar { Button { showNew = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showNew) { NewProjectSheet() }
    }
}

struct ProjectRow: View {
    let project: Project
    let tasks: [TaskItem]
    private var progress: Double { tasks.isEmpty ? 0 : Double(tasks.filter(\.isDone).count) / Double(tasks.count) }

    var body: some View {
        HStack(spacing: DS.Space.m) {
            Text(project.emoji).font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name).font(DS.Font.headline)
                ProgressView(value: progress).tint(DS.Palette.calm)
                HStack(spacing: 6) {
                    Text("\(tasks.filter(\.isDone).count)/\(tasks.count) done")
                    if let d = project.deadline {
                        Text("· due \(d.formatted(.dateTime.month(.abbreviated).day()))")
                            .foregroundStyle(d < Date() ? DS.Palette.warmth : DS.Palette.inkSoft)
                    }
                }
                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ProjectDetailView: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var allTasks: [TaskItem]
    @Query(filter: #Predicate<Goal> { !$0.isArchived }) private var goals: [Goal]
    @State private var newTask = ""
    @State private var newMilestone = ""
    @State private var board = false

    private var tasks: [TaskItem] { allTasks.filter { $0.projectId == project.id } }

    var body: some View {
        Group {
            if board {
                BoardView(tasks: tasks)
            } else {
                List {
                    Section {
                        HStack {
                            TextField("📁", text: $project.emoji).frame(width: 40).font(.title)
                            TextField("Project", text: $project.name).font(DS.Font.title)
                        }
                        Picker("Life area", selection: $project.area) { ForEach(LifeArea.allCases) { Label($0.title, systemImage: $0.icon).tag($0) } }
                        Picker("Goal", selection: $project.goalId) {
                            Text("None").tag(UUID?.none)
                            ForEach(goals) { g in Text("\(g.emoji) \(g.title)").tag(Optional(g.id)) }
                        }
                        Toggle("Deadline", isOn: Binding(get: { project.deadline != nil },
                                                         set: { project.deadline = $0 ? Calendar.current.date(byAdding: .month, value: 1, to: Date()) : nil }))
                        if project.deadline != nil {
                            DatePicker("Due", selection: Binding(get: { project.deadline ?? Date() }, set: { project.deadline = $0 }), displayedComponents: .date)
                        }
                    }

                    // Tasks grouped by milestone (tasks tagged with the milestone name), then the rest.
                    ForEach(project.milestones, id: \.self) { m in
                        let mt = tasks.filter { $0.tags.contains(m) }
                        Section {
                            ForEach(mt) { t in NavigationLink { TaskDetailView(task: t) } label: { TaskRow(task: t, showList: false) } }
                            addField(milestone: m)
                        } header: {
                            HStack { Text("◆ \(m)"); Spacer(); Text("\(mt.filter(\.isDone).count)/\(mt.count)") }
                        }
                    }
                    Section(project.milestones.isEmpty ? "Tasks" : "Other tasks") {
                        ForEach(tasks.filter { t in !project.milestones.contains(where: { t.tags.contains($0) }) }) { t in
                            NavigationLink { TaskDetailView(task: t) } label: { TaskRow(task: t, showList: false) }
                        }
                        addField(milestone: nil)
                    }
                    Section("Milestones") {
                        ForEach(project.milestones, id: \.self) { Text("◆ \($0)") }
                            .onDelete { project.milestones.remove(atOffsets: $0) }
                            .onMove { project.milestones.move(fromOffsets: $0, toOffset: $1) }
                        TextField("Add a milestone", text: $newMilestone).onSubmit {
                            guard !newMilestone.isEmpty else { return }
                            project.milestones.append(newMilestone); newMilestone = ""
                        }
                    }
                    Section("Notes") { TextField("What does done look like?", text: $project.notes, axis: .vertical).lineLimit(2...8) }
                    Section {
                        Button("Archive project") { project.isArchived = true; dismiss() }
                    }
                }
            }
        }
        .navigationTitle(project.name)
        .toolbar {
            Button { withAnimation { board.toggle() } } label: { Image(systemName: board ? "list.bullet" : "rectangle.split.3x1") }
                .accessibilityLabel(board ? "Show as list" : "Show as board")
        }
    }

    private func addField(milestone: String?) -> some View {
        AddTaskField(placeholder: milestone == nil ? "Add a task" : "Add to \(milestone!)") { text in
            let t = QuickAdd.create(text, in: ctx)
            t.projectId = project.id
            if let m = milestone { t.tags = Array(Set(t.tags + [m])) }
        }
    }
}

/// Inline "add a task" row.
struct AddTaskField: View {
    let placeholder: String
    var onAdd: (String) -> Void
    @State private var text = ""
    var body: some View {
        HStack {
            Image(systemName: "plus.circle.fill").foregroundStyle(DS.Palette.accent)
            TextField(placeholder, text: $text).onSubmit {
                guard !text.isEmpty else { return }
                onAdd(text); text = ""; Haptics.tap()
            }
        }
    }
}

struct NewProjectSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "📁"
    @State private var area: LifeArea = .work
    @State private var firstTasks = ""

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    TextField("📁", text: $emoji).frame(width: 40).font(.title)
                    TextField("e.g. Launch the newsletter", text: $name)
                }
                Picker("Life area", selection: $area) { ForEach(LifeArea.allCases) { Label($0.title, systemImage: $0.icon).tag($0) } }
                Section {
                    TextEditor(text: $firstTasks).frame(minHeight: 120)
                } header: { Text("First steps, one per line (optional)") }
            }
            .navigationTitle("New Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let p = Project(name: name)
                        p.emoji = emoji.isEmpty ? "📁" : String(emoji.prefix(2)); p.area = area
                        ctx.insert(p)
                        for line in firstTasks.split(whereSeparator: \.isNewline) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                            QuickAdd.create(String(line), in: ctx).projectId = p.id
                        }
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}
