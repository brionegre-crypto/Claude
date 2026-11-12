import Foundation
import SwiftData
import WidgetKit
import Observation
import EventKit
import CoreGraphics

/// Writes the widget snapshot and asks WidgetKit to refresh. Cheap, so it runs after sync,
/// when Keel goes to the background, and after task changes.
@MainActor
enum WidgetSync {
    static func update(_ ctx: ModelContext) {
        let cal = Calendar.current
        let now = Date()
        let endOfDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        let all = (try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []
        let open = all.filter { !$0.isDone }
        let dueToday = open.filter { ($0.dueDate ?? .distantFuture) < endOfDay }
        let doneToday = all.filter { ($0.completedAt.map { cal.isDateInToday($0) } ?? false) || ($0.lastCompletedOccurrence.map { cal.isDateInToday($0) } ?? false) }
        let energy = EnergyLevel(rawValue: UserDefaults.standard.integer(forKey: "energy")) ?? .medium
        let next = ADHDCoach.nextThing(tasks: open, energy: energy)

        let events = CalendarService.shared.events(from: now, to: now.addingTimeInterval(36 * 3600))
            .filter { !$0.isAllDay }
            .prefix(6)
            .map { WidgetSnapshot.Event(title: $0.title ?? "Event", start: $0.startDate, end: $0.endDate, colorHex: hex($0.calendar.cgColor)) }

        WidgetSnapshot(
            nextThing: next?.title,
            nextThingStep: next?.microSteps.first { !$0.done }?.text,
            events: Array(events),
            tasks: dueToday.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }.prefix(6)
                .map { WidgetSnapshot.TaskLine(title: $0.title, due: $0.dueDate, priority: $0.priority.rawValue) },
            tasksLeftToday: dueToday.count,
            tasksDoneToday: doneToday.count
        ).save()
        WidgetCenter.shared.reloadAllTimelines()
        WatchBridge.shared.push(ctx)          // keep Apple Watch in step
    }

    private static func hex(_ color: CGColor?) -> String {
        guard let c = color?.components, c.count >= 3 else { return "#5B8DEF" }
        return String(format: "#%02X%02X%02X", Int(c[0] * 255), Int(c[1] * 255), Int(c[2] * 255))
    }
}

/// Lets widgets and links open a specific tab (com.keel.app://tasks, …/calendar, …/focus).
@MainActor @Observable
final class AppRouter {
    static let shared = AppRouter()
    var tab: RootView.Tab = .today
    var showFocus = false
    var showCapture = false

    func handle(_ url: URL) -> Bool {
        guard url.scheme == "com.keel.app" else { return false }
        switch url.host {
        case "today": tab = .today
        case "inbox": tab = .inbox
        case "calendar": tab = .calendar
        case "tasks": tab = .tasks
        case "notes": tab = .notes
        case "focus": showFocus = true
        case "capture": showCapture = true
        default: return false
        }
        return true
    }
}
