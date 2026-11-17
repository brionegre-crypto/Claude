import Foundation
import SwiftData
import EventKit
import UserNotifications

/// Keeps the Keel backend's Claude connector (MCP) in step with the phone:
/// uploads a small snapshot after each sync and applies actions Claude queued.
/// This is how Claude (and Claude Duet, once it supports custom connectors) works with Keel.
@MainActor
enum ClaudeBridge {
    private static var base: URL? { KeelServer.baseURL }

    private static func request(_ path: String, method: String, body: Data? = nil) -> URLRequest? {
        guard let base, let token = KeychainStore.read("keel.session") else { return nil }
        var r = URLRequest(url: base.appendingPathComponent(path))
        r.httpMethod = method
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = body
        return r
    }

    static func uploadSnapshot(ctx: ModelContext) async {
        guard !AIRouter.shared.privateMode else { return }   // private mode: nothing leaves the phone
        let tasks = (try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? []
        let notes = ((try? ctx.fetch(FetchDescriptor<Note>())) ?? []).filter { !$0.isLocked }
        let promises = ((try? ctx.fetch(FetchDescriptor<Commitment>())) ?? []).filter { $0.status == .open }
        let energy = EnergyLevel(rawValue: UserDefaults.standard.integer(forKey: "energy")) ?? .medium
        let snapshot: [String: Any] = [
            "today": [
                "nextThing": ADHDCoach.nextThing(tasks: tasks, energy: energy)?.title ?? "",
                "events": CalendarService.shared.todaysEvents().map { "\($0.startDate.formatted(date: .omitted, time: .shortened)) \($0.title ?? "")" },
            ] as [String: Any],
            "tasks": tasks.prefix(200).map { t in [
                "title": t.title, "list": t.listName, "due": t.dueDate?.ISO8601Format() ?? "",
                "energy": t.energy.label, "steps": t.microSteps.map(\.text),
            ] as [String: Any] },
            "promises": promises.prefix(100).map { [
                "promise": $0.promise, "to": $0.displayName, "quote": $0.quote,
                "due": $0.dueDate?.ISO8601Format() ?? "", "overdue": $0.isOverdue,
            ] as [String: Any] },
            "notes": notes.filter { !$0.isTemplate }.sorted { $0.updatedAt > $1.updatedAt }.prefix(800)
                .map { ["title": $0.title, "folder": $0.folder ?? "", "text": String($0.plainText.prefix(2_500))] },
            "calendar": upcomingEvents(),
            "emails": recentEmails(ctx: ctx),
            "body": bodySummary(),
            "meds": medsToday(ctx: ctx),
            "people": people(ctx: ctx),
            "top3": top3(),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: snapshot),
              let req = request("snapshot", method: "POST", body: data) else { return }
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: Extra context for the connector (read-only copies; nothing here can change your data)

    private static func upcomingEvents() -> [[String: Any]] {
        let now = Date()
        return CalendarService.shared.events(from: Calendar.current.startOfDay(for: now), to: now.addingTimeInterval(7 * 86_400)).prefix(150).map { e in [
            "title": e.title ?? "", "start": e.startDate.ISO8601Format(), "end": e.endDate.ISO8601Format(), "allDay": e.isAllDay,
            "location": e.location ?? "", "calendar": e.calendar?.title ?? "",
            "with": (e.attendees ?? []).filter { !$0.isCurrentUser }.map { $0.name ?? $0.url.absoluteString.replacingOccurrences(of: "mailto:", with: "") },
        ] as [String: Any] }
    }

    private static func recentEmails(ctx: ModelContext) -> [[String: Any]] {
        var d = FetchDescriptor<EmailMessage>(predicate: #Predicate { !$0.isArchived }, sortBy: [SortDescriptor(\.receivedAt, order: .reverse)])
        d.fetchLimit = 150
        return ((try? ctx.fetch(d)) ?? []).map { m in [
            "id": m.id, "from": m.fromName.isEmpty ? m.from : "\(m.fromName) <\(m.from)>", "subject": m.subject,
            "summary": m.aiSummary ?? String(m.snippet.prefix(300)), "received": m.receivedAt.ISO8601Format(),
            "unread": !m.isRead, "category": m.category.map { "\($0)" } ?? "", "priority": (m.priorityScore * 100).rounded() / 100,
        ] as [String: Any] }
    }

    private static func bodySummary() -> [String: Any] {
        guard let b = BodyScores.today() else { return [:] }
        return ["recovery_tide": b.tide.map { $0 as Any } ?? NSNull(), "effort_swell": b.swell, "sleep_anchor": b.anchor.map { $0 as Any } ?? NSNull(),
                "advice": BodyEngine.advice(b.tide)]
    }

    private static func medsToday(ctx: ModelContext) -> [[String: Any]] {
        let meds = ((try? ctx.fetch(FetchDescriptor<Medication>())) ?? []).filter(\.isActive)
        let doses = (try? ctx.fetch(FetchDescriptor<MedDose>())) ?? []
        return meds.map { m in [
            "name": m.name, "dose": m.dose,
            "times": m.times.sorted().map { slot in [
                "time": MedEngine.timeLabel(slot),
                "taken": MedEngine.taken(m, slot: slot, doses: doses).map { $0.takenAt.formatted(date: .omitted, time: .shortened) } ?? "not yet",
            ] },
            "pillsLeft": m.pillsLeft.map { $0 as Any } ?? NSNull(),
        ] as [String: Any] }
    }

    private static func people(ctx: ModelContext) -> [[String: Any]] {
        ((try? ctx.fetch(FetchDescriptor<Person>())) ?? []).prefix(300).map { p in [
            "name": p.name, "email": p.email, "hasPhone": !p.phone.isEmpty,
            "lastInTouch": p.lastContact?.ISO8601Format() ?? "", "dueToReachOut": p.isDue,
        ] as [String: Any] }
    }

    private static func top3() -> [String: Any] {
        guard let t = Kit.load(KitTop3.key, as: KitTop3Day.self).first(where: { $0.day == Kit.dayKey() }) else { return [:] }
        return ["items": t.items, "done": t.done]
    }

    static func applyQueuedActions(ctx: ModelContext) async {
        guard let req = request("actions", method: "GET"),
              let (data, _) = try? await URLSession.shared.data(for: req),
              let actions = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        for a in actions {
            let args = a["args"] as? [String: Any] ?? [:]
            switch a["type"] as? String {
            case "add_task":
                // The server's queue can be read twice within a minute; never add the same task twice.
                let title = args["title"] as? String ?? "From Claude"
                let existing = (try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone && $0.title == title }))) ?? []
                guard existing.isEmpty else { continue }
                let t = TaskItem(title: args["title"] as? String ?? "From Claude",
                                 dueDate: (args["due"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) })
                t.listName = args["list"] as? String ?? "Inbox"
                ctx.insert(t)
                try? CalendarService.shared.push(t)
            case "complete_task":
                let q = (args["title"] as? String ?? "").lowercased()
                let open = (try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? []
                if let t = open.first(where: { $0.title.lowercased() == q }) ?? open.first(where: { $0.title.lowercased().contains(q) && !q.isEmpty }) {
                    TaskActions.setDone(t, true)
                }
            case "create_note":
                let title = args["title"] as? String ?? "From Claude"
                let text = args["text"] as? String ?? ""
                let existing = (try? ctx.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.title == title }))) ?? []
                guard !existing.contains(where: { $0.plainText == text }) else { continue }
                ctx.insert(Note(title: title, blocks: SmartPaste.blocks(from: text)))
            case "append_to_note":
                let title = (args["title"] as? String ?? "").lowercased()
                let text = args["text"] as? String ?? ""
                let all = ((try? ctx.fetch(FetchDescriptor<Note>())) ?? []).filter { !$0.isLocked && !$0.isTemplate }
                if let n = all.first(where: { $0.title.lowercased() == title }) ?? all.first(where: { $0.title.lowercased().contains(title) && !title.isEmpty }),
                   !n.plainText.hasSuffix(text) {
                    n.blocks += SmartPaste.blocks(from: text); n.updatedAt = Date()
                }
            case "draft_email":
                // Never sent automatically: it waits as a draft you open, check and send.
                var drafts = UserDefaults.standard.array(forKey: "claude.drafts") as? [[String: String]] ?? []
                drafts.append(["to": args["to"] as? String ?? "", "subject": args["subject"] as? String ?? "", "body": args["body"] as? String ?? ""])
                UserDefaults.standard.set(Array(drafts.suffix(20)), forKey: "claude.drafts")
                notify("Claude drafted an email", "To \(args["to"] as? String ?? "someone"): \(args["subject"] as? String ?? ""). Open Keel to check and send it.")
            case "draft_text":
                var texts = UserDefaults.standard.array(forKey: "claude.texts") as? [[String: String]] ?? []
                texts.append(["to": args["to"] as? String ?? "", "body": args["message"] as? String ?? ""])
                UserDefaults.standard.set(Array(texts.suffix(20)), forKey: "claude.texts")
                notify("Claude drafted a text", "To \(args["to"] as? String ?? "someone"). Open Keel to check and send it.")
            case "add_event":
                guard let title = args["title"] as? String,
                      let start = (args["start"] as? String).flatMap({ ISO8601DateFormatter().date(from: $0) }) else { continue }
                let minutes = args["minutes"] as? Int ?? 60
                let store = CalendarService.shared.store
                let dupes = CalendarService.shared.events(from: start.addingTimeInterval(-60), to: start.addingTimeInterval(60)).filter { $0.title == title }
                guard dupes.isEmpty, CalendarService.shared.hasCalendarAccess else { continue }
                let e = EKEvent(eventStore: store)
                e.title = title; e.startDate = start; e.endDate = start.addingTimeInterval(Double(minutes * 60))
                e.calendar = store.defaultCalendarForNewEvents
                try? store.save(e, span: .thisEvent); CalendarService.shared.invalidateEvents()
            case "log_medication":
                let q = (args["name"] as? String ?? "").lowercased()
                let meds = ((try? ctx.fetch(FetchDescriptor<Medication>())) ?? []).filter(\.isActive)
                if let m = meds.first(where: { $0.name.lowercased() == q }) ?? meds.first(where: { $0.name.lowercased().contains(q) && !q.isEmpty }) {
                    let doses = (try? ctx.fetch(FetchDescriptor<MedDose>())) ?? []
                    let open = MedLog.openSlots(m, on: Date(), doses: doses)
                    MedLog.log(m, slot: MedLog.bestSlot(open, at: Date()), at: Date(), ctx: ctx)
                }
            case "add_to_top3":
                let thing = args["text"] as? String ?? ""
                var all = Kit.load(KitTop3.key, as: KitTop3Day.self)
                var today = all.first { $0.day == Kit.dayKey() } ?? KitTop3Day(day: Kit.dayKey(), items: ["", "", ""], done: [false, false, false])
                if !thing.isEmpty, !today.items.contains(thing), let i = today.items.firstIndex(where: { $0.isEmpty }) {
                    today.items[i] = thing
                    all.removeAll { $0.day == today.day }; all.append(today)
                    Kit.save(Array(all.suffix(120)), KitTop3.key)
                }
            case "log_drink":
                if let p = Drinks.presets.first(where: { $0.kind == (args["kind"] as? String ?? "water") }) { Drinks.add(p) }
            case "save_idea":
                let idea = args["text"] as? String ?? ""
                let ideas = Kit.load(KitIdeaVaultView.key, as: KitIdea.self)
                if !idea.isEmpty, !ideas.contains(where: { $0.text == idea }) { Kit.save([KitIdea(text: idea)] + ideas, KitIdeaVaultView.key) }
            case "start_focus":
                // Never start blocking apps silently — ask the user with a notification instead.
                UserDefaults.standard.set(args["minutes"] as? Int ?? 25, forKey: "claude.suggestedFocus")
            default: break
            }
        }
    }

    private static func notify(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        c.userInfo = ["deeplink": "com.keel.app://claude-drafts"]
        UNUserNotificationCenter.current().addKeel(UNNotificationRequest(identifier: "claude.draft.\(UUID().uuidString)", content: c, trigger: nil))
    }

    /// Opens the next draft Claude left (email first, then texts). Called when Keel comes to the front.
    static func openPendingDrafts() {
        let d = UserDefaults.standard
        if var drafts = d.array(forKey: "claude.drafts") as? [[String: String]], !drafts.isEmpty {
            let x = drafts.removeFirst(); d.set(drafts, forKey: "claude.drafts")
            MailRouter.shared.pending = ComposeDraft(to: x["to"] ?? "", subject: x["subject"] ?? "", body: x["body"] ?? "")
            return
        }
        if var texts = d.array(forKey: "claude.texts") as? [[String: String]], !texts.isEmpty {
            let x = texts.removeFirst(); d.set(texts, forKey: "claude.texts")
            let to = x["to"] ?? ""
            let people = (try? KeelStore.container.mainContext.fetch(FetchDescriptor<Person>())) ?? []
            if let p = people.first(where: { $0.name.caseInsensitiveCompare(to) == .orderedSame || $0.email.caseInsensitiveCompare(to) == .orderedSame }) {
                AppleMessages.compose(person: p, body: x["body"] ?? "")
            } else {
                AppleMessages.compose(TextDraft(recipients: to.isEmpty ? [] : [to], body: x["body"] ?? ""))
            }
        }
    }
}
