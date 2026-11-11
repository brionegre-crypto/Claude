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
            Text("Enter = add as task · “focus N” · “mail” · “reset day”")
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
        } else if t == "mail" || t == "compose" || t.hasPrefix("email ") {
            MailRouter.shared.pending = ComposeDraft(to: t.hasPrefix("email ") ? String(text.dropFirst(6)) : "")
        } else if t == "reset day" {
            ADHDCoach.resetDay(tasks: tasks)
        } else if !text.isEmpty {
            QuickAdd.create(text, in: ctx)      // understands repeats, !priority, #tags, ~list
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
        let ctx = KeelStore.container.mainContext
        let t = QuickAdd.create(text, in: ctx)
        try ctx.save()
        return .result(dialog: "Added “\(t.title)”\(t.recurrence.map { ", \($0.label.lowercased())" } ?? "").")
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

struct OpenPromisesIntent: AppIntent {
    static let title: LocalizedStringResource = "What Did I Promise?"
    static let description: IntentDescription = "Lists commitments you made in sent email that are still open."

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let all = try KeelStore.container.mainContext.fetch(FetchDescriptor<Commitment>(sortBy: [SortDescriptor(\.sentAt)]))
        let open = all.filter { $0.status == .open }.sorted { $0.effectiveDue < $1.effectiveDue }
        guard !open.isEmpty else { return .result(dialog: "No open promises. You're all caught up.") }
        let top = open.prefix(3).map { "\($0.promise) for \($0.displayName)" }.joined(separator: "; ")
        return .result(dialog: "You have \(open.count) open. Next: \(top).")
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
        AppShortcut(intent: OpenPromisesIntent(), phrases: ["What did I promise in \(.applicationName)", "Show my promises in \(.applicationName)"],
                    shortTitle: "Promises", systemImageName: "hand.raised.fingers.spread")
    }
}
