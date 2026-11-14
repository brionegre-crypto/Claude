import Foundation
import EventKit
import CoreLocation
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
        // Screens ask for the same day many times while they redraw; reading EventKit each time made scrolling
        // and taps stutter. Cache briefly, and drop the cache whenever any calendar changes.
        let key = calendars == nil ? "\(start.timeIntervalSince1970)|\(end.timeIntervalSince1970)" : nil
        if let key, let hit = cache[key], Date().timeIntervalSince(hit.at) < 20 { return hit.events }
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let result = Self.mergeDuplicates(store.events(matching: pred)).sorted { $0.startDate < $1.startDate }
        if let key {
            if cache.count > 60 { cache.removeAll() }
            cache[key] = (Date(), result)
        }
        return result
    }

    private var cache: [String: (at: Date, events: [EKEvent])] = [:]
    private var changeObserver: NSObjectProtocol?

    /// Forget cached events (any calendar changed, here or in another app).
    func invalidateEvents() { cache.removeAll() }

    init() {
        changeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { CalendarService.shared.invalidateEvents() }
        }
    }

    /// The same event often lives in two calendars (an invite accepted in both Google and iCloud, a shared
    /// calendar plus your own copy). Show it once: same title, start and end. Keeps the copy you can edit.
    static func mergeDuplicates(_ events: [EKEvent]) -> [EKEvent] {
        var best: [String: EKEvent] = [:]
        var order: [String] = []
        for e in events {
            let title = (e.title ?? "").lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let key = "\(title)|\(Int(e.startDate.timeIntervalSince1970))|\(Int(e.endDate.timeIntervalSince1970))|\(e.isAllDay)"
            if let current = best[key] {
                let better = (e.calendar.allowsContentModifications && !current.calendar.allowsContentModifications)
                    || (e.calendar.type != .subscription && current.calendar.type == .subscription)
                if better { best[key] = e }
            } else {
                best[key] = e
                order.append(key)
            }
        }
        return order.compactMap { best[$0] }
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
        try store.save(e, span: .thisEvent); invalidateEvents()
        task.scheduledBlockStart = start
    }

    // MARK: Editing events (calendar tab)

    /// Drag-to-reschedule: keeps the event's length, moves only this occurrence of a repeating event.
    func move(_ event: EKEvent, to start: Date) throws {
        guard event.calendar.allowsContentModifications else { throw CalendarError.readOnly }
        let length = event.endDate.timeIntervalSince(event.startDate)
        event.startDate = start
        event.endDate = start.addingTimeInterval(length)
        try store.save(event, span: .thisEvent); invalidateEvents()
    }

    func delete(_ event: EKEvent) throws {
        guard event.calendar.allowsContentModifications else { throw CalendarError.readOnly }
        try store.remove(event, span: .thisEvent); invalidateEvents()
    }

    enum CalendarError: Error { case readOnly }

    // MARK: Reminders (two-way)

    var reminderLists: [EKCalendar] { store.calendars(for: .reminder) }

    func fetchReminders() async -> [EKReminder] {
        guard hasReminderAccess else { return [] }
        let pred = store.predicateForReminders(in: nil)
        return await withCheckedContinuation { cont in
            store.fetchReminders(matching: pred) { cont.resume(returning: $0 ?? []) }
        }
    }

    /// Two-way sync with Apple Reminders. Whichever side changed last wins; a reminder deleted in the
    /// Reminders app is removed from Keel; tasks made in Keel are created in Reminders.
    func syncReminders(tasks: [TaskItem], insert: (TaskItem) -> Void, delete: (TaskItem) -> Void) async {
        guard hasReminderAccess, RemindersBridge.isThisDevice else { return }
        let reminders = await fetchReminders()
        let byId = Dictionary(tasks.compactMap { t in t.ekReminderId.map { ($0, t) } }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        // A Keel task that lost its link (e.g. a sync was interrupted) is matched by title and time instead of copied again.
        func key(_ title: String, _ due: Date?) -> String {
            title.lowercased().trimmingCharacters(in: .whitespaces) + "|" + (due.map { String(Int($0.timeIntervalSince1970 / 60)) } ?? "-")
        }
        var unlinked: [String: TaskItem] = [:]
        for t in tasks where t.ekReminderId == nil && !t.isDone { unlinked[key(t.title, t.dueDate)] = t }

        for r in reminders {
            guard !seen.contains(r.calendarItemIdentifier) else { continue }
            seen.insert(r.calendarItemIdentifier)
            if let t = byId[r.calendarItemIdentifier] {
                let rModified = r.lastModifiedDate ?? .distantPast
                if rModified.timeIntervalSince(t.updatedAt) > 1 {          // changed in Reminders → update Keel
                    t.title = r.title ?? t.title
                    t.isDone = r.isCompleted
                    t.completedAt = r.completionDate
                    t.dueDate = Self.date(from: r.dueDateComponents)
                    t.listName = r.calendar.title
                    t.notes = r.notes ?? t.notes
                    t.priority = Self.priority(fromEK: r.priority)
                    t.recurrence = r.recurrenceRules?.first.flatMap(Recurrence.init(ek:))
                    t.updatedAt = rModified
                } else if t.updatedAt.timeIntervalSince(rModified) > 1 {   // changed in Keel → update Reminders
                    try? push(t)
                }
            } else if !r.isCompleted, let t = unlinked.removeValue(forKey: key(r.title ?? "Untitled", Self.date(from: r.dueDateComponents))) {
                t.ekReminderId = r.calendarItemIdentifier
                t.updatedAt = r.lastModifiedDate ?? Date()
            } else if !r.isCompleted {
                let t = TaskItem(title: r.title ?? "Untitled", dueDate: Self.date(from: r.dueDateComponents),
                                 priority: Self.priority(fromEK: r.priority))
                t.recurrence = r.recurrenceRules?.first.flatMap(Recurrence.init(ek:))
                t.ekReminderId = r.calendarItemIdentifier
                t.listName = r.calendar.title
                t.notes = r.notes ?? ""
                t.updatedAt = r.lastModifiedDate ?? Date()
                insert(t)
            }
        }
        // Deleted in Reminders → delete in Keel (double-checked so a failed fetch can never wipe tasks).
        for t in tasks {
            guard let id = t.ekReminderId, !seen.contains(id), store.calendarItem(withIdentifier: id) == nil else { continue }
            delete(t)
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
        if let list = reminderLists.first(where: { $0.title == t.listName }), list != r.calendar { r.calendar = list }
        r.title = t.title
        r.notes = t.notes
        r.isCompleted = t.isDone
        r.priority = [0, 9, 5, 1][t.priority.rawValue]
        // Date-only tasks stay date-only in Reminders (no "12:00 AM").
        let fields: Set<Calendar.Component> = t.hasDueTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
        r.dueDateComponents = t.dueDate.map { Calendar.current.dateComponents(fields, from: $0) }
        r.recurrenceRules = t.recurrence.map { [$0.ekRule] }
        // Location reminder → a Reminders location alarm (fires even when Keel is closed).
        r.alarms?.filter { $0.structuredLocation != nil }.forEach { r.removeAlarm($0) }
        if let name = t.locationName, let lat = t.latitude, let lon = t.longitude {
            let place = EKStructuredLocation(title: name)
            place.geoLocation = CLLocation(latitude: lat, longitude: lon)
            place.radius = 150
            let alarm = EKAlarm()
            alarm.structuredLocation = place
            alarm.proximity = t.remindOnArrive ? .enter : .leave
            r.addAlarm(alarm)
        }
        try store.save(r, commit: true)
        t.ekReminderId = r.calendarItemIdentifier
        t.updatedAt = r.lastModifiedDate ?? Date()     // both sides now agree, so the next sync leaves it alone
    }

    /// Removes one reminder by its id (used to clear an exact duplicate).
    func removeReminder(id: String) {
        guard let r = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        try? store.remove(r, commit: true)
    }

    func removeReminder(for t: TaskItem) {
        guard let id = t.ekReminderId, let r = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        try? store.remove(r, commit: true)
    }

    /// DateComponents.date is nil unless a calendar is attached, which EventKit doesn't guarantee.
    static func date(from comps: DateComponents?) -> Date? {
        guard let comps else { return nil }
        return Calendar.current.date(from: comps)
    }

    private static func priority(fromEK p: Int) -> TaskPriority {
        switch p { case 1...4: .high; case 5: .medium; case 6...9: .low; default: .none }
    }
}

// MARK: - Recurrence ⇄ EventKit

extension Recurrence {
    var ekRule: EKRecurrenceRule {
        let freq: EKRecurrenceFrequency = switch frequency { case .daily: .daily; case .weekly: .weekly; case .monthly: .monthly; case .yearly: .yearly }
        let days = weekdays.compactMap { EKWeekday(rawValue: $0) }.map { EKRecurrenceDayOfWeek($0) }
        return EKRecurrenceRule(recurrenceWith: freq, interval: max(interval, 1),
                                daysOfTheWeek: days.isEmpty ? nil : days, daysOfTheMonth: nil, monthsOfTheYear: nil,
                                weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil,
                                end: endDate.map { EKRecurrenceEnd(end: $0) })
    }

    init?(ek rule: EKRecurrenceRule) {
        let f: Frequency
        switch rule.frequency {
        case .daily: f = .daily
        case .weekly: f = .weekly
        case .monthly: f = .monthly
        case .yearly: f = .yearly
        @unknown default: return nil
        }
        self.init(frequency: f, interval: rule.interval,
                  weekdays: (rule.daysOfTheWeek ?? []).map { $0.dayOfTheWeek.rawValue },
                  endDate: rule.recurrenceEnd?.endDate)
    }
}


/// With iCloud sync, tasks already reach every device. Apple Reminders syncs through iCloud on its own too,
/// so only one device links the two (your iPhone by default); otherwise each device would copy them again.
@MainActor
enum RemindersBridge {
    static let key = "reminders.bridge"
    static var isThisDevice: Bool {
        get {
            if let v = UserDefaults.standard.object(forKey: key) as? Bool { return v }
            return UIDevice.current.userInterfaceIdiom == .phone
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
