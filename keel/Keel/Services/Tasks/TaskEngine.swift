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
        done ? Haptics.success() : Haptics.tap()          // feedback first, with the finger still on the glass
        if done { Automations.taskCompleted(t, ctx: t.modelContext) }
        var rolledTo: Date?
        if done, let rule = t.recurrence {
            let current = t.dueDate ?? Calendar.current.startOfDay(for: Date())
            // "After done": count from today, keeping the original time of day.
            var base = current
            if rule.fromCompletion == true {
                let cal = Calendar.current
                let time = cal.dateComponents([.hour, .minute], from: current)
                base = cal.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: Date()) ?? Date()
            }
            if let next = rule.next(after: base) {
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
        // Reminders sync writes to EventKit, which is slow: do it just after this frame instead of during the tap.
        Task { @MainActor in try? CalendarService.shared.push(t) }
        TaskAlerts.schedule(t)
        if done, t.isDone, let ctx = t.modelContext { notifyUnblocked(by: t, ctx: ctx) }
        if done, t.isDone { Handoff.shared.taskDone(t, ctx: t.modelContext) }      // suggest the next thing
        if let ctx = t.modelContext { WidgetSync.update(ctx) }
        return rolledTo
    }

    /// Finishing a task frees anything waiting on it: clear the link and say so.
    static func notifyUnblocked(by t: TaskItem, ctx: ModelContext) {
        let id = t.id
        let waiting = (try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.blockedById == id }))) ?? []
        guard !waiting.isEmpty else { return }
        for w in waiting { w.blockedById = nil }
        UndoCenter.shared.notify(waiting.count == 1 ? "Unblocked: \(waiting[0].title)" : "\(waiting.count) tasks unblocked")
    }

    /// True while the task it depends on is still open.
    static func isBlocked(_ t: TaskItem, in all: [TaskItem]) -> Bool {
        guard let b = t.blockedById else { return false }
        return all.contains { $0.id == b && !$0.isDone }
    }

    /// A copy with the same details (not done, not linked to the original reminder).
    static func duplicate(_ t: TaskItem, ctx: ModelContext) {
        let c = TaskItem(title: t.title, dueDate: t.dueDate, priority: t.priority)
        c.notes = t.notes; c.listName = t.listName; c.tags = t.tags; c.estimatedMinutes = t.estimatedMinutes
        c.microSteps = t.microSteps.map { MicroStep(text: $0.text, minutes: $0.minutes) }
        c.recurrence = t.recurrence; c.alertOffsetMinutes = t.alertOffsetMinutes; c.goalId = t.goalId
        c.projectId = t.projectId; c.energy = t.energy
        c.locationName = t.locationName; c.latitude = t.latitude; c.longitude = t.longitude; c.remindOnArrive = t.remindOnArrive
        ctx.insert(c)
        try? CalendarService.shared.push(c)
        TaskAlerts.schedule(c)
        Haptics.success()
        UndoCenter.shared.offer("Duplicated “\(t.title)”") { [ctx] in
            TaskAlerts.cancel(c); CalendarService.shared.removeReminder(for: c); ctx.delete(c)
        }
    }

    static func delete(_ t: TaskItem, ctx: ModelContext) {
        // Keep enough to bring it back if you tap Undo.
        let title = t.title, notes = t.notes, due = t.dueDate, priority = t.priority, list = t.listName
        let tags = t.tags, steps = t.microSteps, rule = t.recurrence, alert = t.alertOffsetMinutes, goal = t.goalId
        TaskAlerts.cancel(t)
        CalendarService.shared.removeReminder(for: t)
        ctx.delete(t)
        UndoCenter.shared.offer("Deleted “\(title)”") {
            let r = TaskItem(title: title, dueDate: due, priority: priority)
            r.notes = notes; r.listName = list; r.tags = tags; r.microSteps = steps
            r.recurrence = rule; r.alertOffsetMinutes = alert; r.goalId = goal
            ctx.insert(r)
            try? CalendarService.shared.push(r)
            TaskAlerts.schedule(r)
        }
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
        let med = UNNotificationCategory(identifier: MedEngine.category,
                                         actions: [UNNotificationAction(identifier: MedEngine.takenAction, title: "Taken ✓", options: [])],
                                         intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([task, habit, promise, med, MeetingAutopilot.categoryDefinition])
    }

    static func schedule(_ t: TaskItem) {
        cancel(t)
        guard !t.isDone, let due = t.dueDate, let offset = t.alertOffsetMinutes else { return }
        // Date-only tasks alert at 9am on the day (minus the offset).
        let base = t.hasDueTime ? due : (Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: due) ?? due)
        let fire = base.addingTimeInterval(-Double(offset * 60))
        guard fire > Date() else { return }
        if TaskAlarms.wanted(t) && t.hasDueTime {
            Task { await TaskAlarms.schedule(t, at: fire) }     // full-screen alarm instead of a banner
        } else {
            add(t, at: fire, id: id(t))
        }
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
        KeelAlerts.urgent(c, relevance: t.priority == .high ? 1 : 0.8)
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }

    static func cancel(_ t: TaskItem) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id(t)])
        TaskAlarms.cancel(t)
    }

    /// iOS keeps at most 64 pending alerts per app, so schedule the soonest ones.
    static func rescheduleAll(_ tasks: [TaskItem]) {
        let upcoming = tasks.filter { !$0.isDone && $0.alertOffsetMinutes != nil && $0.dueDate != nil }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        for t in upcoming.prefix(40) { schedule(t) }
    }
}

/// How Keel's reminders reach you. Tasks and reminders are Time Sensitive by default: they pop up right away,
/// stay on the Lock Screen for an hour, and break through Focus modes that allow Time Sensitive alerts.
enum KeelAlerts {
    static let timeSensitiveKey = "alerts.timeSensitive"
    static var timeSensitiveOn: Bool { UserDefaults.standard.object(forKey: timeSensitiveKey) as? Bool ?? true }

    /// Marks a reminder as Time Sensitive (or a normal alert if you turned that off), with sound and a high ranking
    /// so it leads the notification summary instead of being bundled away.
    static func urgent(_ c: UNMutableNotificationContent, relevance: Double = 1) {
        c.interruptionLevel = timeSensitiveOn ? .timeSensitive : .active
        c.relevanceScore = relevance
        if c.sound == nil { c.sound = .default }
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
        let info = response.notification.request.content.userInfo
        if let link = info["deeplink"] as? String, let url = URL(string: link) {
            await MainActor.run { _ = AppRouter.shared.handle(url) }
            return
        }
        if info["meetingEventId"] != nil {
            let joinURL = info["joinURL"] as? String, eventId = info["meetingEventId"] as? String
            await MainActor.run {
                var copy: [AnyHashable: Any] = ["meetingEventId": eventId ?? ""]
                if let joinURL { copy["joinURL"] = joinURL }
                MeetingAutopilot.handle(action: action, info: copy)
            }
            return
        }
        if let medString = info["medId"] as? String, let medId = UUID(uuidString: medString), let slot = info["slot"] as? Int {
            guard action == MedEngine.takenAction else { return }
            await MainActor.run {
                let ctx = KeelStore.container.mainContext
                if let m = try? ctx.fetch(FetchDescriptor<Medication>(predicate: #Predicate { $0.id == medId })).first {
                    MedEngine.take(m, slot: slot, ctx: ctx)
                }
            }
            return
        }
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

    static func parse(_ raw: String) -> QuickAddResult {
        // "Remind me to…", "Don't forget to…": the task is what comes after.
        var input = raw
        for lead in ["remind me to ", "remind me ", "don't forget to ", "dont forget to ", "i need to ", "need to "] where input.lowercased().hasPrefix(lead) {
            input = String(input.dropFirst(lead.count)); break
        }
        // "every other week / Tuesday" → every 2.
        input = input.replacingOccurrences(of: #"\bevery other (day|week|month|year)\b"#, with: "every 2 $1", options: [.regularExpression, .caseInsensitive])
        var everyOtherWeek = false
        if input.range(of: #"\bevery other (sun|mon|tue|wed|thu|fri|sat)"#, options: [.regularExpression, .caseInsensitive]) != nil {
            input = input.replacingOccurrences(of: "every other", with: "every", options: .caseInsensitive)
            everyOtherWeek = true
        }
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
                r.recurrence = Recurrence(frequency: .weekly, interval: everyOtherWeek ? 2 : 1, weekdays: Array(Set(days)).sorted())
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
        if let list = r.list ?? defaultList ?? UserDefaults.standard.string(forKey: Prefs.defaultList) { t.listName = list }
        LocationPhrase.apply(to: t, ctx: ctx)              // "…when I leave work", "…when I get home"
        if t.hasDueTime {
            let alert = UserDefaults.standard.integer(forKey: Prefs.defaultAlert)   // unset = 0 = at time
            t.alertOffsetMinutes = alert < 0 ? nil : alert
        }
        ctx.insert(t)
        try? CalendarService.shared.push(t)
        TaskAlerts.schedule(t)
        return t
    }
}

// MARK: - Duplicate cleanup

/// Merges exact duplicates of open tasks: same title and same due time (or, without a date, the same reminder).
/// Keeps the copy linked to Apple Reminders (then the oldest) and removes the extra copy from Reminders too,
/// so it can't come back on the next sync.
@MainActor
enum TaskDedupe {
    static func key(_ t: TaskItem) -> String {
        let title = t.title.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if let d = t.dueDate { return title + "|" + String(Int(d.timeIntervalSince1970 / 60)) }
        return title + "|nodate|" + (t.ekReminderId ?? t.id.uuidString)
    }

    @discardableResult
    static func run(ctx: ModelContext) -> Int {
        let open = (try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? []
        guard open.count > 1 else { return 0 }
        let ordered = open.sorted { a, b in
            if (a.ekReminderId != nil) != (b.ekReminderId != nil) { return a.ekReminderId != nil }
            return a.createdAt < b.createdAt
        }
        var keep: [String: TaskItem] = [:]
        var removed = 0
        for t in ordered {
            let k = key(t)
            guard let kept = keep[k] else { keep[k] = t; continue }
            if kept.notes.isEmpty { kept.notes = t.notes }
            if kept.microSteps.isEmpty { kept.microSteps = t.microSteps }
            if kept.estimatedMinutes == nil { kept.estimatedMinutes = t.estimatedMinutes }
            if let id = t.ekReminderId, id != kept.ekReminderId { CalendarService.shared.removeReminder(id: id) }
            TaskAlerts.cancel(t)
            ctx.delete(t)
            removed += 1
        }
        if removed > 0 { try? ctx.save() }
        return removed
    }
}
