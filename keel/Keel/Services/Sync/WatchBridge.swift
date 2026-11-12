import Foundation
import SwiftData
import WatchConnectivity

/// iPhone side of the Apple Watch link: sends a snapshot of your day, applies taps made on the watch.
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    @MainActor
    func push(_ ctx: ModelContext) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled else { return }
        let cal = Calendar.current
        let endOfDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        let open = ((try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []).filter { !$0.isDone }
        let dueToday = open.filter { ($0.dueDate ?? .distantFuture) < endOfDay }
            .sorted { ($0.dueDate ?? .distantFuture, -$0.priority.rawValue) < ($1.dueDate ?? .distantFuture, -$1.priority.rawValue) }
        let energy = EnergyLevel(rawValue: UserDefaults.standard.integer(forKey: "energy")) ?? .medium
        let next = ADHDCoach.nextThing(tasks: open, energy: energy)

        let stacks = (try? ctx.fetch(FetchDescriptor<HabitStack>())) ?? []
        let habits = (try? ctx.fetch(FetchDescriptor<Habit>())) ?? []
        let today = cal.startOfDay(for: Date())
        let logs = ((try? ctx.fetch(FetchDescriptor<HabitLog>())) ?? []).filter { $0.day == today }
        let habitRows: [WatchPayload.HabitRow] = stacks.filter(\.isActive).flatMap { s in
            habits.filter { $0.stackId == s.id }.sorted { $0.orderInStack < $1.orderInStack }.map { h in
                WatchPayload.HabitRow(id: h.id, name: h.name, icon: h.icon, stack: s.name, doneToday: logs.contains { $0.habitId == h.id })
            }
        }

        let events = CalendarService.shared.events(from: Date(), to: endOfDay).filter { !$0.isAllDay }.prefix(5)
            .map { WatchPayload.EventRow(title: $0.title ?? "Event", start: $0.startDate, end: $0.endDate) }

        var payload = WatchPayload(
            nextThing: next?.title, nextThingStep: next?.microSteps.first { !$0.done }?.text,
            tasks: dueToday.prefix(20).map { .init(id: $0.id, title: $0.title, due: $0.dueDate, hasTime: $0.hasDueTime, priority: $0.priority.rawValue) },
            habits: habitRows, events: Array(events), focusEndsAt: ShutdownManager.shared.endsAt)

        // Everything else the watch shows
        payload.energy = energy.rawValue
        payload.checkedInMood = ((try? ctx.fetch(FetchDescriptor<CheckIn>())) ?? []).first { cal.isDateInToday($0.day) }?.mood
        payload.mail = ((try? ctx.fetch(FetchDescriptor<EmailMessage>(sortBy: [SortDescriptor(\.priorityScore, order: .reverse)]))) ?? [])
            .filter { !$0.isRead && !$0.isArchived && ($0.category == .important || $0.category == .actionable) }
            .prefix(8)
            .map { .init(id: $0.id, from: $0.fromName.isEmpty ? $0.from : $0.fromName, subject: $0.subject, summary: $0.aiSummary ?? $0.snippet) }
        payload.promises = ((try? ctx.fetch(FetchDescriptor<Commitment>())) ?? [])
            .filter { $0.status == .open && !$0.likelyKept && $0.effectiveDue < endOfDay }
            .map { "\($0.promise) · \($0.displayName)" }
        payload.followUps = ((try? ctx.fetch(FetchDescriptor<FollowUp>())) ?? []).filter(\.isDue)
            .map { $0.recipientName.isEmpty ? $0.recipient : $0.recipientName }
        payload.people = ((try? ctx.fetch(FetchDescriptor<Person>())) ?? []).filter(\.isDue)
            .map { .init(id: $0.id, name: $0.name, phone: $0.phone, lastContact: $0.lastContact) }
        payload.countdowns = ((try? ctx.fetch(FetchDescriptor<Countdown>(sortBy: [SortDescriptor(\.date)]))) ?? [])
            .filter { $0.daysLeft >= 0 }.prefix(6).map { .init(title: $0.title, emoji: $0.emoji, date: $0.date) }
        let allTasks = (try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []
        payload.doneToday = allTasks.filter { ($0.completedAt.map { cal.isDateInToday($0) } ?? false) || ($0.lastCompletedOccurrence.map { cal.isDateInToday($0) } ?? false) }.count
        payload.projects = ((try? ctx.fetch(FetchDescriptor<Project>())) ?? []).filter { !$0.isArchived }.map { p in
            let pt = allTasks.filter { $0.projectId == p.id }
            return .init(name: p.name, emoji: p.emoji, done: pt.filter(\.isDone).count, total: pt.count)
        }
        let weekStart = cal.date(byAdding: .day, value: -6, to: today)!
        payload.focusMinutesWeek = ((try? ctx.fetch(FetchDescriptor<FocusSession>())) ?? [])
            .filter { ($0.endedAt ?? .distantPast) >= weekStart }
            .reduce(0) { $0 + Int((($1.endedAt ?? $1.startedAt).timeIntervalSince($1.startedAt)) / 60) }
        let sessions = ((try? ctx.fetch(FetchDescriptor<FocusSession>())) ?? []).filter { $0.endedAt != nil }
        payload.focusDays = (0..<7).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -i, to: today)!
            return sessions.filter { cal.isDate($0.startedAt, inSameDayAs: d) }
                .reduce(0) { $0 + Int((($1.endedAt ?? $1.startedAt).timeIntervalSince($1.startedAt)) / 60) }
        }
        payload.moodWeek = ((try? ctx.fetch(FetchDescriptor<CheckIn>())) ?? [])
            .filter { $0.day >= weekStart }.sorted { $0.day < $1.day }
            .map { .init(day: $0.day, mood: $0.mood, energy: $0.energy) }
        let doses = (try? ctx.fetch(FetchDescriptor<MedDose>())) ?? []
        payload.meds = ((try? ctx.fetch(FetchDescriptor<Medication>())) ?? []).filter(\.isActive).flatMap { m in
            m.times.sorted().map { slot in
                WatchPayload.MedRow(id: m.id, name: m.name, slot: slot, takenAt: MedEngine.taken(m, slot: slot, doses: doses)?.takenAt)
            }
        }
        payload.momentum = Momentum.today(ctx: ctx).total
        payload.achievementsUnlocked = Momentum.achievements(ctx: ctx).filter(\.unlocked).count
        payload.scheduledMail = ((try? ctx.fetch(FetchDescriptor<ScheduledMail>())) ?? []).count
        payload.briefing = Briefing.latest
        payload.deliveries = ((try? ctx.fetch(FetchDescriptor<Delivery>())) ?? [])
            .filter { !$0.isArchived && $0.status != "delivered" }.prefix(6)
            .map { d in
                let label = d.status == "out" ? "Out for delivery" :
                    d.expected.map { Calendar.current.isDateInToday($0) ? "Arriving today" : "Arriving \($0.formatted(.dateTime.weekday(.abbreviated)))" } ?? "Shipped"
                return .init(title: d.title, carrier: d.carrier, status: label)
            }
        let subs = ((try? ctx.fetch(FetchDescriptor<Subscription>())) ?? []).filter { !$0.isHidden && $0.kind == "subscription" }
        if !subs.isEmpty {
            payload.subscriptionsMonthly = String(format: "%@%.0f/mo", subs[0].currency, subs.reduce(0) { $0 + $1.monthlyCost })
        }
        if let w = KeelWeather.shared.today {
            payload.weather = .init(temperature: w.temperature, symbol: w.symbol, condition: w.condition,
                                    high: w.high, low: w.low, rainFrom: w.rainStartsAt)
        }
        if let data = WatchCoding.encode(payload) {
            try? WCSession.default.updateApplicationContext(["payload": data])
        }
    }

    @MainActor
    private func handle(_ data: Data) {
        guard let action = WatchCoding.decode(WatchAction.self, data) else { return }
        apply(action)
    }

    /// Runs an action from Apple Watch or an interactive widget.
    @MainActor
    func apply(_ action: WatchAction) {
        let ctx = KeelStore.container.mainContext
        switch action {
        case .completeTask(let id):
            if let t = try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first {
                TaskActions.setDone(t, true)
            }
        case .addTask(let text):
            QuickAdd.create(text, in: ctx)
        case .completeHabit(let id):
            if let h = try? ctx.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })).first {
                let last = ((try? ctx.fetch(FetchDescriptor<HabitLog>())) ?? []).filter { $0.habitId == id }.map(\.day).max()
                HabitEngine.complete(h, lastCompletedDay: last, ctx: ctx)
            }
        case .startFocus(let minutes):
            ctx.insert(ShutdownManager.shared.start(minutes: minutes, level: .soft, task: nil))
        case .endFocus:
            ShutdownManager.shared.end(early: true)
        case .moveTaskTomorrow(let id):
            if let t = try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first {
                TaskActions.reschedule(t, to: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!)
            }
        case .setEnergy(let level):
            UserDefaults.standard.set(level, forKey: "energy")
            UserDefaults.standard.set(Date().formatted(.iso8601.year().month().day()), forKey: "energy.day")
        case .checkIn(let mood):
            let day = Calendar.current.startOfDay(for: Date())
            if ((try? ctx.fetch(FetchDescriptor<CheckIn>())) ?? []).first(where: { $0.day == day }) == nil {
                ctx.insert(CheckIn(day: day, mood: mood))
            }
        case .archiveMail(let id):
            if let e = try? ctx.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { $0.id == id })).first {
                e.isArchived = true
                if let a = ((try? ctx.fetch(FetchDescriptor<MailAccount>())) ?? []).first(where: { $0.id == e.accountId }) {
                    let pid = e.providerMessageId
                    Task { try? await MailProviderFactory.make(for: a).archive(pid) }
                }
            }
        case .loggedContact(let id):
            if let p = try? ctx.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.id == id })).first { p.lastContact = Date() }
        case .parkThought(let text):
            let t = TaskItem(title: text)
            t.fromParkingLot = true
            ctx.insert(t)
        case .brainDump(let text):
            Task { @MainActor in
                let items = await BrainDumpSorter.sort(text)
                BrainDumpSorter.save(items, ctx: ctx)
                WidgetSync.update(ctx)
            }
        case .takeMed(let id, let slot):
            if let m = try? ctx.fetch(FetchDescriptor<Medication>(predicate: #Predicate { $0.id == id })).first {
                MedEngine.take(m, slot: slot, ctx: ctx)
            }
        case .carryOverToday:
            let cal = Calendar.current
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
            for t in ((try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []) where !t.isDone && (t.dueDate ?? .distantFuture) < end {
                TaskActions.reschedule(t, to: end)
            }
        }
        try? ctx.save()
        push(ctx)
        WidgetSync.update(ctx)
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.push(KeelStore.container.mainContext) }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }

    /// "Ask Keel" from the watch: answered on the iPhone with Apple Intelligence, reply sent back.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if let question = message["ask"] as? String {
            Task { @MainActor in
                let answer = await KeelAssistant.shared.ask(question)
                replyHandler(["answer": answer])
            }
        } else if let data = message["action"] as? Data {
            Task { @MainActor in self.handle(data) }
            replyHandler([:])
        } else {
            replyHandler([:])
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message["action"] as? Data else { return }
        Task { @MainActor in self.handle(data) }
    }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["action"] as? Data else { return }
        Task { @MainActor in self.handle(data) }
    }
}
