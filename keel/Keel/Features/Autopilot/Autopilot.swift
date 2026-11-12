import Foundation
import SwiftData
import UserNotifications

/// Autopilot: Keel's chief of staff. After every sync it looks across email, calendar, tasks, promises
/// and bills, and prepares concrete actions (reply drafts written, day rebalanced, focus time found).
/// Nothing happens until you tap. Dismissed suggestions never come back.
@MainActor
enum Autopilot {
    static var isOn: Bool { UserDefaults.standard.object(forKey: "autopilot.on") as? Bool ?? true }

    static func pending(ctx: ModelContext) -> [Suggestion] {
        ((try? ctx.fetch(FetchDescriptor<Suggestion>(predicate: #Predicate { $0.status == "pending" }, sortBy: [SortDescriptor(\.createdAt)]))) ?? [])
    }

    // MARK: Prepare

    static func refresh(ctx: ModelContext) async {
        guard isOn else { return }
        let existing = (try? ctx.fetch(FetchDescriptor<Suggestion>())) ?? []
        var known = Set(existing.map(\.key))
        // Old pending ones expire after 3 days so the list never becomes another backlog.
        for s in existing where s.status == "pending" && s.createdAt < Date().addingTimeInterval(-3 * 86_400) { s.status = "dismissed" }
        let before = pending(ctx: ctx).count
        func add(_ s: Suggestion) { guard known.insert(s.key).inserted else { return }; ctx.insert(s) }

        let cal = Calendar.current
        let now = Date()
        let startToday = cal.startOfDay(for: now)
        let endToday = cal.date(byAdding: .day, value: 1, to: startToday)!
        let tasks = (try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []
        let open = tasks.filter { !$0.isDone && !$0.isSomeday }
        let mail = (try? ctx.fetch(FetchDescriptor<EmailMessage>(sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]))) ?? []
        let accounts = Set(((try? ctx.fetch(FetchDescriptor<MailAccount>())) ?? []).map { $0.address.lowercased() })

        // 1. Replies you owe, with a draft already written (at most 3 drafts per run: AI time is precious).
        var drafts = 0
        let owed = mail.filter {
            !$0.isArchived && $0.category == .important && !accounts.contains($0.from.lowercased()) && !MailNoise.isAutomated($0)
                && $0.receivedAt < now.addingTimeInterval(-20 * 3600) && $0.receivedAt > now.addingTimeInterval(-5 * 86_400)
                && !["noreply", "no-reply", "notifications"].contains(where: $0.from.lowercased().contains)
        }.sorted { $0.priorityScore > $1.priorityScore }
        for e in owed.prefix(5) where !known.contains("reply:\(e.id)") && drafts < 3 {
            drafts += 1
            let draft = await AIRouter.shared.draftReply(to: e, intent: "Reply helpfully to what they asked. If something needs a decision I haven't made, say I'll confirm by tomorrow.") ?? ""
            guard !draft.isEmpty else { continue }
            let who = e.fromName.isEmpty ? e.from : e.fromName
            let s = Suggestion(key: "reply:\(e.id)", kind: "reply", title: "Reply to \(who)",
                               detail: "“\(e.subject)” has waited \(Int(now.timeIntervalSince(e.receivedAt) / 86_400) + 1) days. A reply is drafted.", acceptLabel: "Send reply")
            s.refId = e.id; s.payload = draft
            add(s)
        }

        // 2. Inbox noise: unread newsletters and promotions older than 2 days.
        let noise = mail.filter { !$0.isArchived && !$0.isRead && [TriageCategory.newsletters, .promotions].contains($0.category ?? .important) && $0.receivedAt < now.addingTimeInterval(-2 * 86_400) }
        if noise.count >= 8 {
            let s = Suggestion(key: "declutter:\(startToday.timeIntervalSince1970)", kind: "declutter", title: "Clear \(noise.count) old newsletters and promotions",
                               detail: "Unread for 2+ days from \(Set(noise.map { $0.fromName.isEmpty ? $0.from : $0.fromName }).count) senders. They'll stay in Archive.", acceptLabel: "Archive all")
            s.payload = noise.map(\.id).joined(separator: "\n")
            add(s)
        }

        // 3. Overbooked today: more planned than free time. Move the lowest-priority flexible tasks.
        let today = open.filter { ($0.dueDate ?? .distantFuture) < endToday && $0.dueDate.map { $0 >= startToday } ?? false && !$0.hasDueTime }
        let planned = today.reduce(0) { $0 + ADHDCoach.calibratedMinutes($1) }
        let free = Int(CalendarService.shared.freeSlots(minMinutes: 15, from: now, until: 18).reduce(0) { $0 + $1.duration } / 60)
        if cal.component(.hour, from: now) < 16, planned > free + 30 {
            var over = planned - free
            var move: [TaskItem] = []
            for t in today.sorted(by: { $0.priority.rawValue < $1.priority.rawValue }) where over > 0 && t.priority != .high {
                move.append(t); over -= ADHDCoach.calibratedMinutes(t)
            }
            if !move.isEmpty {
                let s = Suggestion(key: "overload:\(startToday.timeIntervalSince1970)", kind: "overload", title: "Today is overbooked by \(hm(planned - free))",
                                   detail: "Move \(move.count) lower-priority task\(move.count == 1 ? "" : "s") to tomorrow: \(move.prefix(3).map(\.title).joined(separator: ", "))\(move.count > 3 ? "…" : "").", acceptLabel: "Move to tomorrow")
                s.payload = move.map(\.id.uuidString).joined(separator: "\n")
                add(s)
            }
        }

        // 4. Deep work for big deadlines: due within 3 days, 60+ minutes, nothing on the calendar yet.
        for t in open.filter({ $0.scheduledBlockStart == nil && ADHDCoach.calibratedMinutes($0) >= 60 && ($0.dueDate.map { $0 < now.addingTimeInterval(3 * 86_400) } ?? false) }).prefix(2) {
            let minutes = min(ADHDCoach.calibratedMinutes(t), 120)
            var slot: DateInterval?
            for offset in 0...2 {
                let day = cal.date(byAdding: .day, value: offset, to: startToday)!
                let from = offset == 0 ? now : cal.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
                if let s = CalendarService.shared.freeSlots(minMinutes: minutes, from: from, until: 18).first { slot = s; break }
            }
            guard let slot else { continue }
            let s = Suggestion(key: "focus:\(t.id)", kind: "focus", title: "Protect time for “\(t.title)”",
                               detail: "Due \(t.dueDate!.formatted(.dateTime.weekday(.wide))). Block \(hm(minutes)) on \(slot.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())).",
                               acceptLabel: "Block it")
            s.refId = t.id.uuidString; s.payload = "\(slot.start.timeIntervalSince1970)|\(minutes)"
            add(s)
        }

        // 5. Tasks that keep slipping: offer tiny steps instead of another reschedule.
        for t in open.filter({ $0.timesRescheduled >= 3 && $0.microSteps.isEmpty }).prefix(2) {
            let s = Suggestion(key: "stale:\(t.id):\(t.timesRescheduled)", kind: "stale", title: "“\(t.title)” keeps slipping",
                               detail: "Moved \(t.timesRescheduled) times. Usually that means it's too big or unclear. Keel can split it into 5-minute steps.",
                               acceptLabel: "Break it down")
            s.refId = t.id.uuidString
            add(s)
        }

        // 6. Promises due within a day that aren't tasks yet.
        let promises = ((try? ctx.fetch(FetchDescriptor<Commitment>())) ?? []).filter { $0.status == .open && $0.effectiveDue < now.addingTimeInterval(86_400) }
        for p in promises.prefix(3) where !open.contains(where: { $0.title == p.promise }) {
            let s = Suggestion(key: "promise:\(p.id)", kind: "promise", title: "You promised \(p.displayName): \(p.promise)",
                               detail: "Due \(p.effectiveDue.formatted(.relative(presentation: .named))). From your email “\(p.subject)”.", acceptLabel: "Add to today")
            s.payload = p.promise
            add(s)
        }

        // 7. Bills due within 3 days.
        for b in ((try? ctx.fetch(FetchDescriptor<Subscription>())) ?? []).filter({ !$0.isHidden && $0.kind == "bill" && ($0.nextDate.map { $0 > now && $0 < now.addingTimeInterval(3 * 86_400) } ?? false) }) {
            let amount = String(format: "%@%.2f", b.currency, b.amount)
            let s = Suggestion(key: "bill:\(b.id):\(b.nextDate!.timeIntervalSince1970)", kind: "bill", title: "Pay \(b.name) (\(amount))",
                               detail: "Due \(b.nextDate!.formatted(.dateTime.weekday(.wide).month().day())).", acceptLabel: "Make a task")
            s.payload = "Pay \(b.name) bill \(amount)"; s.refId = String(b.nextDate!.timeIntervalSince1970)
            add(s)
        }

        // 8. Tomorrow's meetings with people, and nothing written yet.
        let tomorrow = cal.date(byAdding: .day, value: 1, to: startToday)!
        let notes = (try? ctx.fetch(FetchDescriptor<Note>())) ?? []
        for e in CalendarService.shared.events(from: tomorrow, to: cal.date(byAdding: .day, value: 1, to: tomorrow)!)
            .filter({ !$0.isAllDay && ($0.attendees?.count ?? 0) > 1 }).prefix(3)
            where !notes.contains(where: { $0.linkedEventId == e.eventIdentifier }) {
            let s = Suggestion(key: "prep:\(e.calendarItemIdentifier)", kind: "prep", title: "Prep for “\(e.title ?? "meeting")”",
                               detail: "Tomorrow at \(e.startDate.formatted(date: .omitted, time: .shortened)) with \((e.attendees ?? []).compactMap(\.name).prefix(3).joined(separator: ", ")). Start a notes page with an agenda.",
                               acceptLabel: "Create notes")
            s.refId = e.eventIdentifier; s.payload = "\(e.title ?? "Meeting")|\(e.startDate.timeIntervalSince1970)"
            add(s)
        }

        try? ctx.save()
        let after = pending(ctx: ctx).count
        if after >= 3 && after > before { await notify(after) }
    }

    /// At most one nudge a day, never between 9 PM and 8 AM.
    private static func notify(_ count: Int) async {
        let hour = Calendar.current.component(.hour, from: Date())
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        guard hour >= 8, hour < 21, UserDefaults.standard.double(forKey: "autopilot.notified") != today else { return }
        UserDefaults.standard.set(today, forKey: "autopilot.notified")
        let c = UNMutableNotificationContent()
        c.title = "Keel prepared \(count) things for you"
        c.body = "Replies drafted, your day balanced and more. Each one is a single tap."
        c.userInfo = ["deeplink": "com.keel.app://autopilot"]
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "autopilot", content: c, trigger: nil))
    }

    // MARK: Approve

    @discardableResult
    static func accept(_ s: Suggestion, ctx: ModelContext) async -> String {
        s.status = "accepted"
        defer { try? ctx.save(); WidgetSync.update(ctx) }
        let cal = Calendar.current
        switch s.kind {
        case "reply":
            guard let id = s.refId, let e = try? ctx.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { $0.id == id })).first,
                  let a = try? ctx.fetch(FetchDescriptor<MailAccount>()).first(where: { $0.id == e.accountId }) else { return "Couldn't find that email." }
            do {
                try await MailProviderFactory.make(for: a).send(to: e.from, subject: ComposeDraft.prefixed("Re:", e.subject), body: s.payload, inReplyTo: e.replyContext)
                e.isRead = true
                return "Reply sent to \(e.fromName.isEmpty ? e.from : e.fromName)."
            } catch {
                s.status = "pending"
                return "Couldn't send: \(error.localizedDescription)"
            }
        case "declutter":
            let ids = Set(s.payload.split(separator: "\n").map(String.init))
            let items = ((try? ctx.fetch(FetchDescriptor<EmailMessage>())) ?? []).filter { ids.contains($0.id) }
            let accounts = (try? ctx.fetch(FetchDescriptor<MailAccount>())) ?? []
            for m in items { m.isArchived = true }
            Task {
                for m in items {
                    if let a = accounts.first(where: { $0.id == m.accountId }) { try? await MailProviderFactory.make(for: a).archive(m.providerMessageId) }
                }
            }
            return "Archived \(items.count) emails."
        case "overload":
            let ids = Set(s.payload.split(separator: "\n").compactMap { UUID(uuidString: String($0)) })
            let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
            let items = ((try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []).filter { ids.contains($0.id) }
            items.forEach { TaskActions.reschedule($0, to: tomorrow) }
            return "Moved \(items.count) to tomorrow. Today fits now."
        case "focus":
            let parts = s.payload.split(separator: "|")
            guard let t = task(s.refId, ctx), parts.count == 2, let ts = Double(parts[0]), let mins = Int(parts[1]) else { return "Couldn't find that task." }
            do {
                try CalendarService.shared.timeBlock(t, start: Date(timeIntervalSince1970: ts), minutes: mins)
                return "Blocked \(hm(mins)) for “\(t.title)”."
            } catch { s.status = "pending"; return "Couldn't add to Calendar: \(error.localizedDescription)" }
        case "stale":
            guard let t = task(s.refId, ctx) else { return "Couldn't find that task." }
            t.microSteps = await AIRouter.shared.breakDown(t.title, minutesAvailable: 30)
            t.timesRescheduled = 0
            return "Split “\(t.title)” into \(t.microSteps.count) small steps."
        case "promise", "bill":
            let billDue: Date? = s.refId.flatMap({ Double($0) }).map({ Date(timeIntervalSince1970: $0) })
            let due: Date? = s.kind == "bill" ? billDue : cal.startOfDay(for: Date())
            _ = QuickAdd.create(s.payload, in: ctx, defaultDue: due)
            return "Added to your tasks."
        case "prep":
            let parts = s.payload.split(separator: "|", maxSplits: 1)
            let title = parts.first.map(String.init) ?? "Meeting"
            let when = parts.count > 1 ? Double(parts[1]).map { Date(timeIntervalSince1970: $0) } : nil
            let n = Note(title: title, blocks: [
                .init(kind: .text, text: when?.formatted(date: .complete, time: .shortened) ?? ""),
                .init(kind: .heading, text: "Goal of this meeting"), .init(kind: .bullet, text: ""),
                .init(kind: .heading, text: "Agenda"), .init(kind: .bullet, text: ""),
                .init(kind: .heading, text: "Action items"), .init(kind: .todo, text: ""),
            ])
            n.linkedEventId = s.refId
            ctx.insert(n)
            return "Notes page ready for “\(title)”."
        default:
            return "Done."
        }
    }

    static func dismiss(_ s: Suggestion) { s.status = "dismissed" }

    private static func task(_ id: String?, _ ctx: ModelContext) -> TaskItem? {
        guard let id, let uuid = UUID(uuidString: id) else { return nil }
        return try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == uuid })).first
    }

    static func hm(_ m: Int) -> String { m >= 60 ? "\(m / 60)h\(m % 60 == 0 ? "" : " \(m % 60)m")" : "\(m)m" }
}
