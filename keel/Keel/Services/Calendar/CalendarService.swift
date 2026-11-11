import Foundation
import EventKit
import UIKit

/// TickTick-style sync: EventKit sees EVERY calendar the user has on the device —
/// iCloud, Google, Outlook/Exchange, Yahoo, subscribed (.ics) — plus all Apple Reminders lists.
/// Two-way: Keel tasks ⇄ Apple Reminders, Keel time-blocks → a "Keel" calendar.
@MainActor
final class CalendarService {
    static let shared = CalendarService()
    let store = EKEventStore()
    private(set) var hasCalendarAccess = false
    private(set) var hasReminderAccess = false

    func requestAccess() async {
        hasCalendarAccess = (try? await store.requestFullAccessToEvents()) ?? false
        hasReminderAccess = (try? await store.requestFullAccessToReminders()) ?? false
    }

    // MARK: Calendars

    var allCalendars: [EKCalendar] { store.calendars(for: .event) }

    /// Calendars grouped by account (iCloud / Gmail / Exchange …) for the settings screen.
    var calendarsBySource: [(source: String, calendars: [EKCalendar])] {
        Dictionary(grouping: allCalendars, by: { $0.source.title })
            .map { ($0.key, $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.source < $1.source }
    }

    func events(from start: Date, to end: Date, calendars: [EKCalendar]? = nil) -> [EKEvent] {
        guard hasCalendarAccess else { return [] }
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: pred).sorted { $0.startDate < $1.startDate }
    }

    func todaysEvents() -> [EKEvent] {
        let start = Calendar.current.startOfDay(for: Date())
        return events(from: start, to: start.addingTimeInterval(86_400))
    }

    /// Free gaps between events today, for AI planning and "what can I do in 25 min?"
    func freeSlots(minMinutes: Int = 15, from: Date = Date(), until endHour: Int = 18) -> [DateInterval] {
        let end = Calendar.current.date(bySettingHour: endHour, minute: 0, second: 0, of: from) ?? from
        guard end > from else { return [] }
        var cursor = from
        var gaps: [DateInterval] = []
        for e in events(from: from, to: end) where !e.isAllDay {
            if e.startDate.timeIntervalSince(cursor) >= Double(minMinutes * 60) {
                gaps.append(DateInterval(start: cursor, end: e.startDate))
            }
            cursor = max(cursor, e.endDate)
        }
        if end.timeIntervalSince(cursor) >= Double(minMinutes * 60) { gaps.append(DateInterval(start: cursor, end: end)) }
        return gaps
    }

    /// A dedicated "Keel" calendar for focus blocks so they show up in every calendar app (and Claude Duet).
    func keelCalendar() throws -> EKCalendar {
        if let c = allCalendars.first(where: { $0.title == "Keel" }) { return c }
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = "Keel"
        cal.cgColor = UIColor.systemIndigo.cgColor
        cal.source = store.defaultCalendarForNewEvents?.source ?? store.sources.first { $0.sourceType == .local }
        try store.saveCalendar(cal, commit: true)
        return cal
    }

    func timeBlock(_ task: TaskItem, start: Date, minutes: Int) throws {
        let e = EKEvent(eventStore: store)
        e.calendar = try keelCalendar()
        e.title = "◆ \(task.title)"
        e.startDate = start
        e.endDate = start.addingTimeInterval(Double(minutes * 60))
        e.notes = "keel-task:\(task.id.uuidString)"
        try store.save(e, span: .thisEvent)
        task.scheduledBlockStart = start
    }

    // MARK: Reminders (two-way)

    var reminderLists: [EKCalendar] { store.calendars(for: .reminder) }

    func fetchReminders() async -> [EKReminder] {
        guard hasReminderAccess else { return [] }
        let pred = store.predicateForReminders(in: nil)
        return await withCheckedContinuation { cont in
            store.fetchReminders(matching: pred) { cont.resume(returning: $0 ?? []) }
        }
    }

    /// Pull Apple Reminders → Keel tasks, and push Keel task changes → Reminders.
    /// Conflict rule: most recently modified side wins.
    func syncReminders(tasks: [TaskItem], insert: (TaskItem) -> Void) async {
        let reminders = await fetchReminders()
        let byId = Dictionary(uniqueKeysWithValues: tasks.compactMap { t in t.ekReminderId.map { ($0, t) } })

        for r in reminders {
            if let t = byId[r.calendarItemIdentifier] {
                let rModified = r.lastModifiedDate ?? .distantPast
                if rModified > t.updatedAt {        // Reminders side newer → update Keel
                    t.title = r.title ?? t.title
                    t.isDone = r.isCompleted
                    t.dueDate = r.dueDateComponents?.date
                    t.listName = r.calendar.title
                    t.updatedAt = rModified
                } else {                            // Keel side newer → push
                    try? push(t)
                }
            } else if !r.isCompleted {
                let t = TaskItem(title: r.title ?? "Untitled", dueDate: r.dueDateComponents?.date,
                                 priority: Self.priority(fromEK: r.priority))
                t.ekReminderId = r.calendarItemIdentifier
                t.listName = r.calendar.title
                t.notes = r.notes ?? ""
                insert(t)
            }
        }
        // Keel-only tasks → create reminders
        for t in tasks where t.ekReminderId == nil && !t.isDone { try? push(t) }
    }

    func push(_ t: TaskItem) throws {
        let r: EKReminder
        if let id = t.ekReminderId, let existing = store.calendarItem(withIdentifier: id) as? EKReminder {
            r = existing
        } else {
            r = EKReminder(eventStore: store)
            r.calendar = reminderLists.first { $0.title == t.listName } ?? store.defaultCalendarForNewReminders()
        }
        r.title = t.title
        r.notes = t.notes
        r.isCompleted = t.isDone
        r.priority = [0, 9, 5, 1][t.priority.rawValue]
        r.dueDateComponents = t.dueDate.map { Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
        try store.save(r, commit: true)
        t.ekReminderId = r.calendarItemIdentifier
    }

    private static func priority(fromEK p: Int) -> TaskPriority {
        switch p { case 1...4: .high; case 5: .medium; case 6...9: .low; default: .none }
    }
}
