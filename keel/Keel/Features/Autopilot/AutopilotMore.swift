import Foundation
import SwiftData
import EventKit

/// More things Autopilot prepares beyond replies: mass unsubscribe, calendar clashes to fix,
/// tasks hiding in your email, and repeating tasks that would work better as habits.
@MainActor
extension Autopilot {
    static func moreSuggestions(ctx: ModelContext, mail: [EmailMessage], open: [TaskItem], add: (Suggestion) -> Void) async {
        let cal = Calendar.current
        let now = Date()

        // A. Mass unsubscribe: newsletters and promos you almost never open.
        let leave = UnsubscribeSuggestions.candidates(mail).filter(\.oneTap)
        if leave.count >= 3 {
            let week = cal.component(.weekOfYear, from: now)
            let s = Suggestion(key: "unsub:\(week)", kind: "unsubscribe", title: "Unsubscribe from \(leave.count) senders you never read",
                               detail: leave.prefix(4).map(\.name).joined(separator: ", ") + (leave.count > 4 ? " and \(leave.count - 4) more" : "") + ". Their old mail gets archived too.",
                               acceptLabel: "Unsubscribe all")
            s.payload = leave.map(\.sender).joined(separator: "\n")
            add(s)
        }

        // B. Calendar clashes in the next two days: move your own event (no other guests) to the next free time that day.
        let events = CalendarService.shared.events(from: now, to: now.addingTimeInterval(2 * 86_400)).filter { !$0.isAllDay }
        var proposed = 0
        for (i, a) in events.enumerated() where proposed < 2 {
            for b in events[(i + 1)...] where b.startDate < a.endDate && a.startDate < b.endDate {
                // The one to move: yours alone, editable, and not the meeting with other people.
                let movable = [a, b].first { ($0.attendees?.isEmpty ?? true) && $0.calendar.allowsContentModifications }
                guard let mv = movable else { continue }
                let other: EKEvent = mv === a ? b : a
                let minutes = Int(mv.endDate.timeIntervalSince(mv.startDate) / 60)
                guard let slot = CalendarService.shared.freeSlots(minMinutes: max(15, minutes), from: other.endDate, until: 20).first else { continue }
                let s = Suggestion(key: "resched:\(mv.calendarItemIdentifier):\(Int(mv.startDate.timeIntervalSince1970))", kind: "reschedule",
                                   title: "Move “\(mv.title ?? "event")”: it clashes with “\(other.title ?? "another event")”",
                                   detail: "\(mv.startDate.formatted(.dateTime.weekday(.abbreviated).hour().minute())) → \(slot.start.formatted(.dateTime.hour().minute())), the next free \(minutes)-minute gap.",
                                   acceptLabel: "Move it")
                s.refId = mv.eventIdentifier
                s.payload = String(slot.start.timeIntervalSince1970)
                add(s)
                proposed += 1
                break
            }
        }

        // C. Tasks hiding in email: something you were asked to do, not on your list yet.
        let linked = Set(open.compactMap(\.sourceEmailId))
        let asks = mail.filter {
            !$0.isArchived && ($0.category == .actionable || $0.category == .important) && $0.extractedTaskTitle != nil
                && $0.receivedAt > now.addingTimeInterval(-7 * 86_400) && !linked.contains($0.id) && !MailNoise.isAutomated($0)
        }
        for e in asks.prefix(3) {
            let title = e.extractedTaskTitle ?? e.subject
            let due = e.extractedDueDate
            let s = Suggestion(key: "addtask:\(e.id)", kind: "addtask", title: "Add task: \(title)",
                               detail: "From \(e.fromName.isEmpty ? e.from : e.fromName)" + (due.map { " · due \($0.formatted(.dateTime.weekday(.wide).month().day()))" } ?? "") + ".",
                               acceptLabel: "Add task")
            s.refId = e.id
            s.payload = title + "|" + (due.map { String($0.timeIntervalSince1970) } ?? "")
            add(s)
        }

        // D. Repeating tasks that would work better as habits (streaks and grace days instead of "overdue").
        let stacks = (try? ctx.fetch(FetchDescriptor<HabitStack>())) ?? []
        let habits = (try? ctx.fetch(FetchDescriptor<Habit>())) ?? []
        let haveNames = Set((stacks.map(\.name) + habits.map(\.name)).map { $0.lowercased() })
        let done = ((try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isDone }))) ?? [])
            .filter { ($0.completedAt ?? .distantPast) > now.addingTimeInterval(-30 * 86_400) }
        let repeatedTitles = Dictionary(grouping: done, by: { $0.title.lowercased().trimmingCharacters(in: .whitespaces) }).filter { $0.value.count >= 3 }.map(\.key)
        var habitIdeas: [(title: String, task: TaskItem?)] = open
            .filter { t in t.recurrence.map { $0.frequency == .daily || $0.frequency == .weekly } ?? false }
            .map { (title: $0.title, task: Optional($0)) }
        let fromHistory: [(title: String, task: TaskItem?)] = repeatedTitles
            .filter { title in !habitIdeas.contains { $0.title.lowercased() == title } }
            .map { (title: $0.capitalized, task: nil) }
        habitIdeas += fromHistory
        for idea in habitIdeas.prefix(2) where !haveNames.contains(idea.title.lowercased()) {
            let recipe = matchingRecipe(idea.title)
            let s: Suggestion
            if let r = recipe, !haveNames.contains(r.name.lowercased()) {
                s = Suggestion(key: "habit:\(idea.title.lowercased())", kind: "habit", title: "Swap “\(idea.title)” for the “\(r.name)” habit stack",
                               detail: "From the habit library: " + r.steps.map { $0.0 }.joined(separator: " → ") + ". Streaks and grace days instead of an overdue task.",
                               acceptLabel: "Make it a habit")
                s.payload = "recipe:" + r.name
            } else {
                s = Suggestion(key: "habit:\(idea.title.lowercased())", kind: "habit", title: "Make “\(idea.title)” a habit",
                               detail: "You do this over and over. As a habit it gets a streak and grace days, and never shows up as overdue.",
                               acceptLabel: "Make it a habit")
                s.payload = "single:" + idea.title
            }
            s.refId = idea.task?.id.uuidString
            add(s)
        }
    }

    /// A habit-library stack that already includes something like this task.
    static func matchingRecipe(_ title: String) -> HabitLibraryView.Recipe? {
        let words = Set(title.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count > 3 })
        guard !words.isEmpty else { return nil }
        return HabitLibraryView.recipes.first { r in
            r.steps.contains { step in !words.isDisjoint(with: Set(step.0.lowercased().split { !$0.isLetter }.map(String.init))) }
        }
    }

    /// Approving the kinds above. Returns nil for kinds this file doesn't handle.
    static func acceptMore(_ s: Suggestion, ctx: ModelContext) async -> String? {
        switch s.kind {
        case "unsubscribe":
            let senders = Set(s.payload.split(separator: "\n").map(String.init))
            let mail = (try? ctx.fetch(FetchDescriptor<EmailMessage>())) ?? []
            let accounts = (try? ctx.fetch(FetchDescriptor<MailAccount>())) ?? []
            var left = 0, archived = 0
            for c in UnsubscribeSuggestions.candidates(mail) where senders.contains(c.sender) {
                let provider = accounts.first { $0.id == c.latest.accountId }.map { MailProviderFactory.make(for: $0) }
                if case .done = await Unsubscribe.run(c.latest, provider: provider, ctx: ctx, allowWebPage: false) {
                    left += 1
                    UnsubscribeSuggestions.markDone(c.sender)
                    for m in mail where m.from.lowercased() == c.sender && !m.isArchived {
                        m.isArchived = true; archived += 1
                        if let p = provider { Task { try? await p.archive(m.providerMessageId) } }
                    }
                }
            }
            return left == 0 ? "Those senders need their own web page; open Inbox → Clean Up Inbox." : "Unsubscribed from \(left) and archived \(archived) emails."

        case "reschedule":
            guard let id = s.refId, let ev = CalendarService.shared.store.event(withIdentifier: id), let ts = Double(s.payload) else { return "That event changed already." }
            do {
                try CalendarService.shared.move(ev, to: Date(timeIntervalSince1970: ts))
                return "Moved “\(ev.title ?? "event")” to \(Date(timeIntervalSince1970: ts).formatted(date: .omitted, time: .shortened))."
            } catch { s.status = "pending"; return "Couldn't move it: \(error.localizedDescription)" }

        case "addtask":
            let parts = s.payload.components(separatedBy: "|")
            let t = TaskItem(title: parts.first ?? "Task", dueDate: parts.count > 1 ? Double(parts[1]).map { Date(timeIntervalSince1970: $0) } : nil)
            t.sourceEmailId = s.refId
            ctx.insert(t)
            TaskAlerts.schedule(t)
            return "Added “\(t.title)” to your tasks."

        case "habit":
            let task: TaskItem? = s.refId.flatMap(UUID.init(uuidString:)).flatMap { id in
                try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first
            }
            let name: String
            if s.payload.hasPrefix("recipe:"), let r = HabitLibraryView.recipes.first(where: { "recipe:" + $0.name == s.payload }) {
                let stack = HabitStack(name: r.name, anchor: r.anchor)
                ctx.insert(stack)
                for (i, step) in r.steps.enumerated() {
                    let h = Habit(name: step.0, icon: step.1, minutes: step.2)
                    h.stackId = stack.id; h.orderInStack = i
                    ctx.insert(h)
                }
                name = r.name
            } else {
                let title = String(s.payload.dropFirst("single:".count))
                let anchor: StackAnchor = task.flatMap { t in
                    t.hasDueTime ? t.dueDate.map { StackAnchor.time(hour: Calendar.current.component(.hour, from: $0), minute: Calendar.current.component(.minute, from: $0)) } : nil
                } ?? StackAnchor.manual(label: "every day")
                let stack = HabitStack(name: title, anchor: anchor)
                ctx.insert(stack)
                let h = Habit(name: title, icon: "repeat", minutes: 5)
                h.stackId = stack.id
                ctx.insert(h)
                name = title
            }
            if let t = task {                       // the repeating task is replaced by the habit
                TaskAlerts.cancel(t)
                ctx.delete(t)
            }
            return "“\(name)” is now a habit\(task == nil ? "" : ", and the repeating task is gone")."

        default:
            return nil
        }
    }
}
