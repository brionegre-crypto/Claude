import SwiftUI
import SwiftData

/// TickTick-style lists, synced two-way with Apple Reminders.
struct TasksView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @State private var newTitle = ""
    @State private var showDone = false

    private var lists: [String] { Array(Set(tasks.map(\.listName))).sorted() }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "plus.circle.fill").foregroundStyle(DS.Palette.accent)
                        TextField("Add a task — try “call mom tomorrow 5pm”", text: $newTitle)
                            .onSubmit(add)
                    }
                }
                ForEach(lists, id: \.self) { list in
                    let items = tasks.filter { $0.listName == list && ($0.isDone == showDone) && !$0.isWaitingOn }
                    if !items.isEmpty {
                        Section(list) {
                            ForEach(items) { t in
                                NavigationLink { TaskDetailView(task: t) } label: { TaskRow(task: t) }
                            }
                        }
                    }
                }
                let waiting = tasks.filter { $0.isWaitingOn && !$0.isDone }
                if !waiting.isEmpty {
                    Section("Waiting on others") { ForEach(waiting) { TaskRow(task: $0) } }
                }
            }
            .navigationTitle("Tasks")
            .toolbar { Toggle(isOn: $showDone) { Image(systemName: "checkmark.circle") }.toggleStyle(.button) }
            .refreshable { await SyncEngine.shared.syncAll() }
        }
    }

    private func add() {
        guard !newTitle.isEmpty else { return }
        let parsed = NaturalDate.parse(newTitle)
        let t = TaskItem(title: parsed.title, dueDate: parsed.date)
        ctx.insert(t)
        try? CalendarService.shared.push(t)      // appears in Apple Reminders immediately
        newTitle = ""
        Haptics.tap()
    }
}

struct TaskRow: View {
    @Bindable var task: TaskItem
    var body: some View {
        HStack(spacing: DS.Space.m) {
            CompletionCheck(isDone: Binding(get: { task.isDone }, set: {
                task.isDone = $0; task.completedAt = $0 ? Date() : nil; task.updatedAt = Date()
                try? CalendarService.shared.push(task)
            }))
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).strikethrough(task.isDone).foregroundStyle(task.isDone ? DS.Palette.inkSoft : DS.Palette.ink)
                HStack(spacing: 6) {
                    if let d = task.dueDate { Text(d, format: .dateTime.month().day().hour().minute()).font(DS.Font.caption) }
                    if !task.microSteps.isEmpty {
                        Text("\(task.microSteps.filter(\.done).count)/\(task.microSteps.count) steps").font(DS.Font.caption)
                    }
                    if task.sourceEmailId != nil { Image(systemName: "envelope").font(.caption2) }
                }.foregroundStyle(DS.Palette.inkSoft)
            }
            Spacer()
            Image(systemName: task.energy.icon).font(.caption).foregroundStyle(DS.Palette.inkSoft)
        }
    }
}

struct TaskDetailView: View {
    @Bindable var task: TaskItem
    @State private var breaking = false

    var body: some View {
        Form {
            TextField("Title", text: $task.title)
            Section("Plan") {
                DatePicker("Due", selection: Binding(get: { task.dueDate ?? Date() }, set: { task.dueDate = $0 }))
                Picker("Energy needed", selection: $task.energy) { ForEach(EnergyLevel.allCases) { Text($0.label).tag($0) } }
                Stepper("Estimate: \(task.estimatedMinutes ?? 25) min  (really ~\(ADHDCoach.calibratedMinutes(task)))",
                        value: Binding(get: { task.estimatedMinutes ?? 25 }, set: { task.estimatedMinutes = $0 }), in: 5...480, step: 5)
                Toggle("Waiting on someone else", isOn: $task.isWaitingOn)
                Button("Block time on my calendar") {
                    if let slot = CalendarService.shared.freeSlots(minMinutes: ADHDCoach.calibratedMinutes(task)).first {
                        try? CalendarService.shared.timeBlock(task, start: slot.start, minutes: ADHDCoach.calibratedMinutes(task))
                        Haptics.success()
                    }
                }
            }
            Section {
                ForEach($task.microSteps) { $step in
                    HStack { CompletionCheck(isDone: $step.done); Text(step.text); Spacer(); Text("\(step.minutes)m").font(DS.Font.caption) }
                }
                Button { Task { await breakDown() } } label: {
                    Label(breaking ? "Thinking…" : "Break into tiny steps", systemImage: "sparkles")
                }.disabled(breaking)
            } header: { Text("Tiny steps") } footer: { Text("Stuck? The first step is always small enough to start right now.") }
            Section("Notes") { TextEditor(text: $task.notes).frame(minHeight: 100) }
        }
        .navigationTitle("Task")
        .onDisappear { task.updatedAt = Date(); try? CalendarService.shared.push(task) }
    }

    private func breakDown() async {
        breaking = true; defer { breaking = false }
        if let steps = try? await AIRouter.shared.cloud.breakDown(task.title, minutesAvailable: task.estimatedMinutes) {
            withAnimation(DS.spring) { task.microSteps = steps }
        }
    }
}

/// Tiny natural-language date parser using NSDataDetector (on-device, free).
enum NaturalDate {
    static func parse(_ s: String) -> (title: String, date: Date?) {
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let m = det.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range, in: s) else { return (s, nil) }
        let title = s.replacingCharacters(in: r, with: "").trimmingCharacters(in: .whitespaces)
        return (title.isEmpty ? s : title, m.date)
    }
}
