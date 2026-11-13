import AppIntents
import SwiftData
import EventKit

// Siri & Shortcuts. Everything here also works in the Shortcuts app, Spotlight and the Action button.

// MARK: - Task entity (lets Siri refer to your tasks by name: "Complete Gym in Keel")

struct TaskEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Task"
    static let defaultQuery = TaskEntityQuery()
    let id: UUID
    let title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct TaskEntityQuery: EntityStringQuery {
    @MainActor private func open() -> [TaskItem] {
        ((try? KeelStore.container.mainContext.fetch(FetchDescriptor<TaskItem>())) ?? []).filter { !$0.isDone }
    }

    func entities(for identifiers: [UUID]) async throws -> [TaskEntity] {
        await MainActor.run { open().filter { identifiers.contains($0.id) }.map { TaskEntity(id: $0.id, title: $0.title) } }
    }

    func entities(matching string: String) async throws -> [TaskEntity] {
        await MainActor.run {
            open().filter { $0.title.localizedCaseInsensitiveContains(string) }.map { TaskEntity(id: $0.id, title: $0.title) }
        }
    }

    func suggestedEntities() async throws -> [TaskEntity] {
        await MainActor.run {
            open().sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
                .prefix(15).map { TaskEntity(id: $0.id, title: $0.title) }
        }
    }
}

// MARK: - Intents

struct AskKeelIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Keel"
    static let description: IntentDescription = "Ask Keel's on-device AI about your day, or tell it to do something."
    @Parameter(title: "Question", requestValueDialog: "What do you want to ask Keel?") var question: String

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await KeelAssistant.shared.ask(question)
        return .result(dialog: "\(answer)")
    }
}

struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Keel Task"
    @Parameter(title: "Task") var task: TaskEntity

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = KeelStore.container.mainContext
        let id = task.id
        guard let t = try ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first else {
            return .result(dialog: "I couldn't find that task.")
        }
        let next = TaskActions.setDone(t, true)
        try ctx.save()
        if let next { return .result(dialog: "Done. “\(t.title)” repeats on \(next.formatted(date: .abbreviated, time: .omitted)).") }
        return .result(dialog: "Done: “\(t.title)”. Nice work.")
    }
}

struct TodayAgendaIntent: AppIntent {
    static let title: LocalizedStringResource = "What's on Today"
    static let description: IntentDescription = "Hear today's events, tasks and anything important."

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        await CalendarService.shared.requestAccess()
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        let events = CalendarService.shared.events(from: Date(), to: end).filter { !$0.isAllDay }
        let tasks = ((try? KeelStore.container.mainContext.fetch(FetchDescriptor<TaskItem>())) ?? [])
            .filter { !$0.isDone && ($0.dueDate.map { $0 < end } ?? false) }
        var parts: [String] = []
        if let e = events.first {
            parts.append("Next up: \(e.title ?? "an event") at \(e.startDate.formatted(date: .omitted, time: .shortened))")
            if events.count > 1 { parts.append("then \(events.count - 1) more event\(events.count == 2 ? "" : "s")") }
        } else {
            parts.append("No more events today")
        }
        parts.append(tasks.isEmpty ? "and no tasks due" : "and \(tasks.count) task\(tasks.count == 1 ? "" : "s") due, starting with \(tasks.first!.title)")
        return .result(dialog: "\(parts.joined(separator: ", ")).")
    }
}

struct NextEventIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Event"

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        await CalendarService.shared.requestAccess()
        let next = CalendarService.shared.events(from: Date(), to: Date().addingTimeInterval(7 * 86_400)).first { !$0.isAllDay }
        guard let e = next else { return .result(dialog: "Nothing on your calendar this week.") }
        let when = e.startDate.formatted(.relative(presentation: .named))
        return .result(dialog: "\(e.title ?? "Your next event") \(when), at \(e.startDate.formatted(date: .omitted, time: .shortened)).")
    }
}

struct InboxSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Keel Inbox"

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let mail = ((try? KeelStore.container.mainContext.fetch(FetchDescriptor<EmailMessage>())) ?? [])
            .filter { !$0.isRead && !$0.isArchived && ($0.category == .important || $0.category == .actionable) }
            .sorted { $0.priorityScore > $1.priorityScore }
        guard !mail.isEmpty else { return .result(dialog: "Nothing important waiting. Inbox is calm.") }
        let names = mail.prefix(3).map { $0.fromName.isEmpty ? $0.from : $0.fromName }
        return .result(dialog: "\(mail.count) email\(mail.count == 1 ? "" : "s") need you, from \(names.joined(separator: ", ")).")
    }
}

struct EndFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "End Keel Focus"

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard ShutdownManager.shared.active != nil else { return .result(dialog: "You're not in a focus session.") }
        ShutdownManager.shared.end(early: true)
        return .result(dialog: "Focus ended. Take a breath.")
    }
}

struct AddEventIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Keel Event"
    @Parameter(title: "Title") var title: String
    @Parameter(title: "Starts") var start: Date
    @Parameter(title: "Minutes", default: 60) var minutes: Int

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        await CalendarService.shared.requestAccess()
        let store = CalendarService.shared.store
        let e = EKEvent(eventStore: store)
        e.title = title
        e.startDate = start
        e.endDate = start.addingTimeInterval(Double(minutes * 60))
        e.calendar = store.defaultCalendarForNewEvents
        try store.save(e, span: .thisEvent); CalendarService.shared.invalidateEvents()
        return .result(dialog: "Added “\(title)” on \(start.formatted(date: .abbreviated, time: .shortened)).")
    }
}

// MARK: - Bring in Apple Notes and Messages through Shortcuts (you approve access there)

/// "Save to Keel Notes": Shortcuts can pass Apple Notes, messages or any text here.
/// Used by the "Import Apple Notes" shortcut and message automations.
struct SaveNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Save to Keel Notes"
    static let description: IntentDescription = "Saves text as a Keel note. Use it in Shortcuts to bring in notes or messages from other apps."
    @Parameter(title: "Title") var noteTitle: String?
    @Parameter(title: "Text") var text: String

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = KeelStore.container.mainContext
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Imported note"
        let title = (noteTitle?.isEmpty == false ? noteTitle! : String(firstLine.prefix(60)))
        // Skip notes that were already imported (same title and text).
        let existing = (try? ctx.fetch(FetchDescriptor<Note>())) ?? []
        if existing.contains(where: { $0.title == title && $0.plainText == text }) {
            return .result(dialog: "Already in Keel.")
        }
        let note = Note(title: title, blocks: [NoteBlock(kind: .text, text: text)])
        ctx.insert(note)
        try ctx.save()
        return .result(dialog: "Saved “\(title)” to Keel.")
    }
}

/// "Add message to Keel": for a Shortcuts message automation. Turns a message into a task, with who sent it.
struct MessageToTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Message to Keel"
    static let description: IntentDescription = "Turns a message into a Keel task. Use it in a Shortcuts “Message” automation."
    @Parameter(title: "Message") var message: String
    @Parameter(title: "From") var sender: String?

    @MainActor func perform() async throws -> some IntentResult {
        let ctx = KeelStore.container.mainContext
        let t = QuickAdd.create(String(message.prefix(140)), in: ctx)
        t.notes = "From \(sender ?? "a message"):\n\(message)"
        t.tags = Array(Set(t.tags + ["message"]))
        try ctx.save()
        return .result()
    }
}

// MARK: - Medications

@MainActor
enum MedsLogger {
    /// Logs the earliest untaken dose due by now (+1h), optionally matching a name.
    static func logNext(name: String, ctx: ModelContext) -> String {
        let meds = ((try? ctx.fetch(FetchDescriptor<Medication>())) ?? []).filter(\.isActive)
            .filter { name.isEmpty || $0.name.lowercased().contains(name.lowercased()) }
        let doses = (try? ctx.fetch(FetchDescriptor<MedDose>())) ?? []
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let nowMin = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        let next = meds.flatMap { m in m.times.sorted().map { (m, $0) } }
            .filter { $0.1 <= nowMin + 60 && MedEngine.taken($0.0, slot: $0.1, doses: doses) == nil }
            .min { $0.1 < $1.1 }
        guard let pick = next else {
            return meds.isEmpty ? "I couldn't find that medication in Keel." : "Nothing is due right now. " + MedEngine.statusSentence(ctx: ctx)
        }
        let (m, slot) = pick
        MedEngine.take(m, slot: slot, ctx: ctx)
        return "Logged \(m.name) as taken at \(Date().formatted(date: .omitted, time: .shortened))."
    }
}

struct DidITakeMedsIntent: AppIntent {
    static let title: LocalizedStringResource = "Did I Take My Meds?"
    static let description: IntentDescription = "Hear whether you've logged today's medication."
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(MedEngine.statusSentence(ctx: KeelStore.container.mainContext))")
    }
}

struct LogMedsIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Medication Taken"
    static let description: IntentDescription = "Marks your next due dose as taken."
    @Parameter(title: "Medication", default: "") var name: String
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(MedsLogger.logNext(name: name, ctx: KeelStore.container.mainContext))")
    }
}

// MARK: - Brain dump and planning

struct BrainDumpIntent: AppIntent {
    static let title: LocalizedStringResource = "Brain Dump"
    static let description: IntentDescription = "Say everything on your mind. Keel sorts it into tasks, events, notes and worries."
    @Parameter(title: "What's on your mind?", requestValueDialog: "What's on your mind? Say it all.")
    var text: String

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = KeelStore.container.mainContext
        let items = await BrainDumpSorter.sort(text)
        let summary = BrainDumpSorter.save(items, ctx: ctx)
        WidgetSync.updateNow(ctx)
        return .result(dialog: "Got it. Added \(summary.isEmpty ? "nothing" : summary).")
    }
}

struct PlanMyDayIntent: AppIntent {
    static let title: LocalizedStringResource = "Plan My Day"
    static let description: IntentDescription = "Opens Keel's 3-minute planning ritual."
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        AppRouter.shared.showPlan = true
        return .result()
    }
}
