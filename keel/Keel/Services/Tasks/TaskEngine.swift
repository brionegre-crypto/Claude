import Foundation
import SwiftData
import UserNotifications

// MARK: - Completing tasks (repeating tasks roll forward, TickTick-style)

@MainActor
enum TaskActions {
    /// Marks a task done — or, for a repeating task, logs the completion and moves it to its next date.
    /// Returns the next due date when a repeating task rolled forward (for a "Next: …" toast).
    @discardableResult
    static func setDone(_ t: TaskItem, _ done: Bool) -> Date? {
        var rolledTo: Date?
        if done, let rule = t.recurrence {
            let current = t.dueDate ?? Calendar.current.startOfDay(for: Date())
            if let next = rule.next(after: current) {
                t.completionCount += 1
                t.lastCompletedOccurrence = current
                t.dueDate = next
                t.isDone = false
                for i in t.microSteps.indices { t.microSteps[i].done = false }
                rolledTo = next
            } else {                                   // repeat has ended: finish for good
                t.isDone = true
                t.completedAt = Date()
            }
        } else {
            t.isDone = done
            t.completedAt = done ? Date() : nil
        }
        t.updatedAt = Date()
        try? CalendarService.shared.push(t)
        TaskAlerts.schedule(t)
        done ? Haptics.success() : Haptics.tap()
        if let ctx = t.modelContext { WidgetSync.update(ctx) }
        return rolledTo
    }

    static func delete(_ t: TaskItem, ctx: ModelContext) {
        TaskAlerts.cancel(t)
        CalendarService.shared.removeReminder(for: t)
        ctx.delete(t)
    }

    static func reschedule(_ t: TaskItem, to day: Date) {
        let cal = Calendar.current
        if let due = t.dueDate, t.hasDueTime {
            let c = cal.dateComponents([.hour, .minute], from: due)
            t.dueDate = cal.date(bySettingHour: c.hour ?? 9, minute: c.minute ?? 0, second: 0, of: day)
        } else {
            t.dueDate = cal.startOfDay(for: day)
        }
        t.timesRescheduled += 1
        t.updatedAt = Date()
        try? CalendarService.shared.push(t)
        TaskAlerts.schedule(t)
    }
}

// MARK: - Keel's own task alerts (with Complete / Snooze buttons on the notification)

@MainActor
enum TaskAlerts {
    static let category = "TASK_ALERT"
    static let completeAction = "TASK_COMPLETE"
    static let snoozeAction = "TASK_SNOOZE"

    static let offsets: [(label: String, minutes: Int?)] = [
        ("None", nil), ("At time of task", 0), ("5 minutes before", 5), ("15 minutes before", 15),
        ("30 minutes before", 30), ("1 hour before", 60), ("1 day before", 1_440),
    ]

    static func id(_ t: TaskItem) -> String { "task.\(t.id.uuidString)" }

    static func registerCategories() {
        let complete = UNNotificationAction(identifier: completeAction, title: "Complete", options: [])
        let snooze = UNNotificationAction(identifier: snoozeAction, title: "Snooze 10 min", options: [])
        let task = UNNotificationCategory(identifier: category, actions: [complete, snooze], intentIdentifiers: [])
        let habit = UNNotificationCategory(identifier: "HABIT_STACK", actions: [], intentIdentifiers: [])
        let promise = UNNotificationCategory(identifier: "PROMISE", actions: [], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([task, habit, promise])
    }

    static func schedule(_ t: TaskItem) {
        cancel(t)
        guard !t.isDone, let due = t.dueDate, let offset = t.alertOffsetMinutes else { return }
        // Date-only tasks alert at 9am on the day (minus the offset).
        let base = t.hasDueTime ? due : (Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: due) ?? due)
        let fire = base.addingTimeInterval(-Double(offset * 60))
        guard fire > Date() else { return }
        add(t, at: fire, id: id(t))
    }

    static func snooze(_ t: TaskItem, minutes: Int = 10) {
        add(t, at: Date().addingTimeInterval(Double(minutes * 60)), id: id(t))
    }

    private static func add(_ t: TaskItem, at fire: Date, id: String) {
        let c = UNMutableNotificationContent()
        c.title = t.title
        var body = t.hasDueTime ? "Due \(t.dueDate?.formatted(date: .omitted, time: .shortened) ?? "")" : "Due today"
        if let step = t.microSteps.first(where: { !$0.done }) { body += " · Start with: \(step.text)" }
        c.body = body
        c.sound = .default
        c.categoryIdentifier = category
        c.userInfo = ["taskId": t.id.uuidString]
        if t.priority == .high { c.interruptionLevel = .timeSensitive }
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }

    static func cancel(_ t: TaskItem) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id(t)])
    }

    /// iOS keeps at most 64 pending alerts per app, so schedule the soonest ones.
    static func rescheduleAll(_ tasks: [TaskItem]) {
        let upcoming = tasks.filter { !$0.isDone && $0.alertOffsetMinutes != nil && $0.dueDate != nil }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        for t in upcoming.prefix(40) { schedule(t) }
    }
}

/// Shows alerts while Keel is open and handles the Complete / Snooze buttons.
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationHandler()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        guard let idString = response.notification.request.content.userInfo["taskId"] as? String,
              let id = UUID(uuidString: idString) else { return }
        await MainActor.run {
            let ctx = KeelStore.container.mainContext
            guard let task = try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first else { return }
            switch action {
            case TaskAlerts.completeAction: TaskActions.setDone(task, true)
            case TaskAlerts.snoozeAction: TaskAlerts.snooze(task)
            default: break
            }
            try? ctx.save()
        }
    }
}

// MARK: - Quick add: "Gym every Monday 7am !high #health ~Personal"

struct QuickAddResult {
    var title: String
    var dueDate: Date?
    var recurrence: Recurrence?
    var priority: TaskPriority = .none
    var tags: [String] = []
    var list: String?
}

enum QuickAdd {
    static let weekdayNames: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
        "sun": 1, "mon": 2, "tue": 3, "tues": 3, "wed": 4, "thu": 5, "thur": 5, "thurs": 5, "fri": 6, "sat": 7,
    ]

    static func parse(_ input: String) -> QuickAddResult {
        var words = input.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var r = QuickAddResult(title: input)

        // #tags, ~list, !priority
        r.tags = words.filter { $0.hasPrefix("#") && $0.count > 1 }.map { String($0.dropFirst()) }
        if let l = words.first(where: { $0.hasPrefix("~") && $0.count > 1 }) { r.list = String(l.dropFirst()) }
        if let p = words.first(where: { $0.hasPrefix("!") })?.lowercased() {
            r.priority = ["!high", "!h", "!!!", "!3"].contains(p) ? .high
                : ["!medium", "!med", "!m", "!!", "!2"].contains(p) ? .medium
                : ["!low", "!l", "!", "!1"].contains(p) ? .low : .none
        }
        words.removeAll { $0.hasPrefix("#") || $0.hasPrefix("~") || $0.hasPrefix("!") }
        var text = words.joined(separator: " ")

        // Repeat phrases (matched case-insensitively on `text` itself, so ranges stay valid for removal)
        let opts: String.CompareOptions = [.regularExpression, .caseInsensitive]
        let simple: [(String, Recurrence)] = [
            (#"\bevery weekday\b"#, .weekdaysOnly),
            (#"\b(every day|daily)\b"#, Recurrence(frequency: .daily)),
            (#"\b(every week|weekly)\b"#, Recurrence(frequency: .weekly)),
            (#"\b(every month|monthly)\b"#, Recurrence(frequency: .monthly)),
            (#"\b(every year|yearly|annually)\b"#, Recurrence(frequency: .yearly)),
        ]
        for (pattern, rule) in simple {
            if let range = text.range(of: pattern, options: opts) {
                r.recurrence = rule
                text.removeSubrange(range)
                break
            }
        }
        if r.recurrence == nil, let range = text.range(of: #"\bevery (\d+) (day|week|month|year)s?\b"#, options: opts) {
            let parts = text[range].lowercased().split(separator: " ")
            let n = Int(parts[1]) ?? 1
            let freq: Recurrence.Frequency = parts[2].hasPrefix("day") ? .daily : parts[2].hasPrefix("week") ? .weekly : parts[2].hasPrefix("month") ? .monthly : .yearly
            r.recurrence = Recurrence(frequency: freq, interval: n)
            text.removeSubrange(range)
        }
        if r.recurrence == nil,
           let range = text.range(of: #"\bevery ((sun|mon|tue|tues|wed|thu|thur|thurs|fri|sat)[a-z]*( and |, ?| )?)+"#, options: opts) {
            let days = text[range].lowercased().replacingOccurrences(of: "every", with: "")
                .replacingOccurrences(of: "and", with: " ")
                .split(whereSeparator: { " ,".contains($0) }).compactMap { weekdayNames[String($0)] }
            if !days.isEmpty {
                r.recurrence = Recurrence(frequency: .weekly, weekdays: Array(Set(days)).sorted())
                text.removeSubrange(range)
            }
        }

        // Dates and times ("tomorrow 5pm", "Friday", "Dec 3 at 9")
        let parsed = NaturalDate.parse(text.trimmingCharacters(in: .whitespaces))
        r.title = parsed.title.trimmingCharacters(in: .whitespaces)
        if r.title.isEmpty { r.title = input }
        r.dueDate = parsed.date

        // A repeating task with no date starts at its first occurrence (today if today matches).
        if let rule = r.recurrence {
            let cal = Calendar.current
            let timeSource = r.dueDate
            var start = cal.startOfDay(for: r.dueDate ?? Date())
            if let t = timeSource {
                let c = cal.dateComponents([.hour, .minute], from: t)
                start = cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: start) ?? start
            }
            if !rule.weekdays.isEmpty && !rule.weekdays.contains(cal.component(.weekday, from: start)) {
                start = rule.next(after: start) ?? start
            }
            r.dueDate = start
        }
        return r
    }

    /// Creates the task, mirrors it to Apple Reminders and schedules its alert.
    @MainActor @discardableResult
    static func create(_ input: String, in ctx: ModelContext, defaultList: String? = nil, defaultDue: Date? = nil) -> TaskItem {
        let r = parse(input)
        let t = TaskItem(title: r.title, dueDate: r.dueDate ?? defaultDue, priority: r.priority)
        t.recurrence = r.recurrence
        t.tags = r.tags
        if let list = r.list ?? defaultList { t.listName = list }
        if t.hasDueTime { t.alertOffsetMinutes = 0 }
        ctx.insert(t)
        try? CalendarService.shared.push(t)
        TaskAlerts.schedule(t)
        return t
    }
}
