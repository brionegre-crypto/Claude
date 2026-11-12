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

        let payload = WatchPayload(
            nextThing: next?.title, nextThingStep: next?.microSteps.first { !$0.done }?.text,
            tasks: dueToday.prefix(20).map { .init(id: $0.id, title: $0.title, due: $0.dueDate, hasTime: $0.hasDueTime, priority: $0.priority.rawValue) },
            habits: habitRows, events: Array(events), focusEndsAt: ShutdownManager.shared.endsAt)
        if let data = WatchCoding.encode(payload) {
            try? WCSession.default.updateApplicationContext(["payload": data])
        }
    }

    @MainActor
    private func handle(_ data: Data) {
        guard let action = WatchCoding.decode(WatchAction.self, data) else { return }
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

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message["action"] as? Data else { return }
        Task { @MainActor in self.handle(data) }
    }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["action"] as? Data else { return }
        Task { @MainActor in self.handle(data) }
    }
}
