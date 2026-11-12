import SwiftUI
import WatchConnectivity
import WatchKit
import WidgetKit

@main
struct KeelWatchApp: App {
    @State private var store = WatchStore.shared
    var body: some Scene {
        WindowGroup {
            WatchRoot().environment(store)
        }
    }
}

private let accent = Color(red: 0.36, green: 0.42, blue: 0.98)
private let calm = Color(red: 0.27, green: 0.70, blue: 0.62)

/// Watch side of the iPhone link. Shows the last snapshot instantly, updates optimistically on taps.
@MainActor @Observable
final class WatchStore: NSObject, WCSessionDelegate {
    static let shared = WatchStore()
    var payload = WatchPayload()

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "payload"), let p = WatchCoding.decode(WatchPayload.self, data) { payload = p }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func send(_ action: WatchAction) {
        guard let data = WatchCoding.encode(action) else { return }
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(["action": data], replyHandler: nil) { _ in session.transferUserInfo(["action": data]) }
        } else {
            session.transferUserInfo(["action": data])          // delivered when the iPhone is next available
        }
    }

    func complete(_ task: WatchPayload.TaskRow) {
        payload.tasks.removeAll { $0.id == task.id }
        WKInterfaceDevice.current().play(.success)
        send(.completeTask(task.id))
    }

    func complete(_ habit: WatchPayload.HabitRow) {
        if let i = payload.habits.firstIndex(where: { $0.id == habit.id }) { payload.habits[i].doneToday = true }
        WKInterfaceDevice.current().play(.success)
        send(.completeHabit(habit.id))
    }

    func startFocus(_ minutes: Int) {
        payload.focusEndsAt = Date().addingTimeInterval(Double(minutes * 60))
        WKInterfaceDevice.current().play(.start)
        send(.startFocus(minutes))
    }

    func endFocus() {
        payload.focusEndsAt = nil
        WKInterfaceDevice.current().play(.stop)
        send(.endFocus)
    }

    func add(_ text: String) {
        WKInterfaceDevice.current().play(.click)
        send(.addTask(text))
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in self.apply(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(applicationContext) }
    }

    private func apply(_ context: [String: Any]) {
        guard let data = context["payload"] as? Data, let p = WatchCoding.decode(WatchPayload.self, data) else { return }
        payload = p
        UserDefaults.standard.set(data, forKey: "payload")
        // Share with the watch-face complications and refresh them.
        UserDefaults(suiteName: "group.com.briangreenejr.keel")?.set(data, forKey: "watch.payload")
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct WatchRoot: View {
    var body: some View {
        TabView {
            NowPage()
            TasksPage()
            HabitsPage()
            AddPage()
        }
        .tabViewStyle(.verticalPage)
    }
}

struct NowPage: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let end = store.payload.focusEndsAt, end > Date() {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Focusing", systemImage: "moon.zzz.fill").font(.caption).foregroundStyle(accent)
                        Text(timerInterval: Date()...end, countsDown: true)
                            .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                        Button("End focus", role: .destructive) { store.endFocus() }
                    }
                } else {
                    Text("JUST ONE THING").font(.caption2.weight(.bold)).foregroundStyle(accent)
                    Text(store.payload.nextThing ?? "Nothing urgent").font(.headline)
                    if let step = store.payload.nextThingStep {
                        Text("Start: \(step)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let e = store.payload.events.first(where: { $0.end > Date() }) {
                        Divider()
                        Text(e.title).font(.caption.weight(.semibold))
                        Text(e.start, style: .relative).font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack {
                        ForEach([15, 25, 50], id: \.self) { m in
                            Button("\(m)") { store.startFocus(m) }.tint(accent)
                        }
                    }
                    .font(.caption)
                    Text("Start focus (min)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Keel")
    }
}

struct TasksPage: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        List {
            if store.payload.tasks.isEmpty {
                Text("All done for today 🎉").foregroundStyle(.secondary)
            }
            ForEach(store.payload.tasks) { t in
                Button { store.complete(t) } label: {
                    HStack {
                        Image(systemName: "circle").foregroundStyle(t.priority >= 3 ? .red : t.priority == 2 ? .orange : accent)
                        VStack(alignment: .leading) {
                            Text(t.title).lineLimit(2)
                            if let d = t.due, t.hasTime { Text(d, style: .time).font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Today")
    }
}

struct HabitsPage: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        List {
            if store.payload.habits.isEmpty { Text("No habit stacks yet").foregroundStyle(.secondary) }
            ForEach(store.payload.habits) { h in
                Button { if !h.doneToday { store.complete(h) } } label: {
                    HStack {
                        Image(systemName: h.doneToday ? "checkmark.circle.fill" : h.icon)
                            .foregroundStyle(h.doneToday ? calm : accent)
                        VStack(alignment: .leading) {
                            Text(h.name).strikethrough(h.doneToday)
                            Text(h.stack).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Habits")
    }
}

struct AddPage: View {
    @Environment(WatchStore.self) private var store
    @State private var text = ""
    @State private var added = false

    var body: some View {
        VStack(spacing: 10) {
            TextField("Add a task…", text: $text)    // dictation or Scribble
                .onSubmit(add)
            Button("Add", action: add).tint(accent).disabled(text.isEmpty)
            if added { Label("Added", systemImage: "checkmark.circle.fill").foregroundStyle(calm).font(.caption) }
            Text("Try “Call mom tomorrow 5pm”").font(.caption2).foregroundStyle(.secondary)
        }
        .navigationTitle("Capture")
    }

    private func add() {
        guard !text.isEmpty else { return }
        store.add(text)
        text = ""
        added = true
    }
}
