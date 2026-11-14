import AppIntents
import SwiftData
import Foundation

// More Shortcuts actions: pages you can pick by name, and tasks you can filter and pass to other actions.

// MARK: - Pages

struct NoteEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Page"
    static let defaultQuery = NoteEntityQuery()
    let id: UUID
    let title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title.isEmpty ? "Untitled" : title)") }
}

struct NoteEntityQuery: EntityStringQuery {
    @MainActor private func pages() -> [Note] {
        ((try? KeelStore.container.mainContext.fetch(FetchDescriptor<Note>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? [])
            .filter { !$0.isTemplate }
    }
    func entities(for identifiers: [UUID]) async throws -> [NoteEntity] {
        await MainActor.run { pages().filter { identifiers.contains($0.id) }.map { NoteEntity(id: $0.id, title: $0.title) } }
    }
    func entities(matching string: String) async throws -> [NoteEntity] {
        await MainActor.run { pages().filter { $0.title.localizedCaseInsensitiveContains(string) }.prefix(30).map { NoteEntity(id: $0.id, title: $0.title) } }
    }
    func suggestedEntities() async throws -> [NoteEntity] {
        await MainActor.run { pages().prefix(15).map { NoteEntity(id: $0.id, title: $0.title) } }
    }
}

@MainActor private func findNote(_ e: NoteEntity) -> Note? {
    let id = e.id
    return try? KeelStore.container.mainContext.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })).first
}

struct OpenPageIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Keel Page"
    static let description: IntentDescription = "Opens a page in Keel."
    static let openAppWhenRun = true
    @Parameter(title: "Page") var page: NoteEntity

    @MainActor func perform() async throws -> some IntentResult {
        AppRouter.shared.openNoteId = page.id
        return .result()
    }
}

struct ReadPageIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Text of Keel Page"
    static let description: IntentDescription = "Gives the text of a page to the next action in your shortcut."
    @Parameter(title: "Page") var page: NoteEntity

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let n = findNote(page) else { return .result(value: "") }
        return .result(value: n.isLocked ? "This page is locked." : n.title + "\n\n" + n.plainText)
    }
}

struct AppendToPageIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Keel Page"
    static let description: IntentDescription = "Adds text to the end of a page (lists, tables and headings are kept)."
    @Parameter(title: "Page") var page: NoteEntity
    @Parameter(title: "Text") var text: String

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let n = findNote(page), !n.isLocked else { return .result(dialog: "I couldn't add to that page.") }
        n.blocks += SmartPaste.blocks(from: text)
        n.updatedAt = Date()
        try? KeelStore.container.mainContext.save()
        return .result(dialog: "Added to “\(n.title.isEmpty ? "Untitled" : n.title)”.")
    }
}

// MARK: - Tasks you can filter

enum TaskWindow: String, AppEnum {
    case today, overdue, thisWeek, noDate, all
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "When"
    static let caseDisplayRepresentations: [TaskWindow: DisplayRepresentation] = [
        .today: "Due today", .overdue: "Overdue", .thisWeek: "Due this week", .noDate: "No date", .all: "All open tasks",
    ]
}

struct FindTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Keel Tasks"
    static let description: IntentDescription = "Finds open tasks by when they're due, and optionally by list, to use in other actions."
    @Parameter(title: "When", default: .today) var window: TaskWindow
    @Parameter(title: "List") var list: String?

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[TaskEntity]> & ProvidesDialog {
        let cal = Calendar.current, now = Date()
        let startTomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let weekEnd = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: now)) ?? now
        let open = ((try? KeelStore.container.mainContext.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? [])
        let matched = open.filter { t in
            if let list, !list.isEmpty, t.listName.localizedCaseInsensitiveCompare(list) != .orderedSame { return false }
            switch window {
            case .today: return t.dueDate.map { $0 < startTomorrow } ?? false
            case .overdue: return t.dueDate.map { $0 < cal.startOfDay(for: now) } ?? false
            case .thisWeek: return t.dueDate.map { $0 < weekEnd } ?? false
            case .noDate: return t.dueDate == nil
            case .all: return true
            }
        }
        .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        let entities = matched.map { TaskEntity(id: $0.id, title: $0.title) }
        let spoken = matched.isEmpty ? "No tasks." : matched.prefix(5).map(\.title).joined(separator: ", ") + (matched.count > 5 ? ", and \(matched.count - 5) more." : ".")
        return .result(value: entities, dialog: "\(spoken)")
    }
}
