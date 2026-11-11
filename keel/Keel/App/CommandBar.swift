import SwiftUI
import SwiftData
import AppIntents

/// Superhuman-style command bar: type anything — a task, a search, "focus 25", "reset day".
struct CommandBar: View {
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var ctx
    @Query private var tasks: [TaskItem]
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Image(systemName: "command").foregroundStyle(DS.Palette.accent)
                TextField("Add a task, search, or “focus 25”…", text: $text)
                    .focused($focused).onSubmit(run)
            }
            Text("Enter = add as task · “focus N” · “reset day” · “dump”")
                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
        }
        .padding(DS.Space.m)
        .glassEffect(.regular, in: .rect(cornerRadius: DS.Radius.card))
        .padding()
        .onAppear { focused = true }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func run() {
        let t = text.lowercased()
        if t.hasPrefix("focus"), let m = Int(t.filter(\.isNumber)) {
            ctx.insert(ShutdownManager.shared.start(minutes: m, level: .soft, task: nil))
        } else if t == "reset day" {
            ADHDCoach.resetDay(tasks: tasks)
        } else if !text.isEmpty {
            let p = NaturalDate.parse(text)
            ctx.insert(TaskItem(title: p.title, dueDate: p.date))
        }
        Haptics.success()
        text = ""; isPresented = false
    }
}

// MARK: - Siri / Shortcuts / Apple Intelligence (App Intents)

struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Keel Task"
    static let description: IntentDescription = "Capture a task into Keel."
    @Parameter(title: "Task") var text: String

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = KeelStore.container
        let p = NaturalDate.parse(text)
        let t = TaskItem(title: p.title, dueDate: p.date)
        container.mainContext.insert(t)
        try container.mainContext.save()
        try? CalendarService.shared.push(t)
        return .result(dialog: "Added “\(p.title)”.")
    }
}

struct StartFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Keel Focus"
    static let openAppWhenRun = true
    @Parameter(title: "Minutes", default: 25) var minutes: Int

    @MainActor func perform() async throws -> some IntentResult {
        _ = ShutdownManager.shared.start(minutes: minutes, level: .soft, task: nil)
        return .result()
    }
}

struct WhatNowIntent: AppIntent {
    static let title: LocalizedStringResource = "What Should I Do Now?"
    static let description: IntentDescription = "Keel picks your single best next action."

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = KeelStore.container
        let tasks = try container.mainContext.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))
        let energy = EnergyLevel(rawValue: UserDefaults.standard.integer(forKey: "energy")) ?? .medium
        guard let t = ADHDCoach.nextThing(tasks: tasks, energy: energy) else { return .result(dialog: "Nothing urgent. Take a breath.") }
        let first = t.microSteps.first { !$0.done }?.text
        return .result(dialog: "\(t.title).\(first.map { " Start by: \($0)." } ?? "")")
    }
}

struct KeelShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddTaskIntent(), phrases: ["Add a task in \(.applicationName)", "Capture in \(.applicationName)"],
                    shortTitle: "Add Task", systemImageName: "plus.circle")
        AppShortcut(intent: StartFocusIntent(), phrases: ["Start focus in \(.applicationName)", "Shut down distractions with \(.applicationName)"],
                    shortTitle: "Focus", systemImageName: "moon.zzz")
        AppShortcut(intent: WhatNowIntent(), phrases: ["What should I do now in \(.applicationName)", "Ask \(.applicationName) what's next"],
                    shortTitle: "What Now?", systemImageName: "scope")
    }
}
