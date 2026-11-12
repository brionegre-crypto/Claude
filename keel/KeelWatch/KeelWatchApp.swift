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

    func park(_ text: String) {
        WKInterfaceDevice.current().play(.click)
        send(.parkThought(text))
    }

    func moveTomorrow(_ task: WatchPayload.TaskRow) {
        payload.tasks.removeAll { $0.id == task.id }
        WKInterfaceDevice.current().play(.click)
        send(.moveTaskTomorrow(task.id))
    }

    func setEnergy(_ level: Int) {
        payload.energy = level
        WKInterfaceDevice.current().play(.click)
        send(.setEnergy(level))
    }

    func checkIn(_ mood: Int) {
        payload.checkedInMood = mood
        WKInterfaceDevice.current().play(.success)
        send(.checkIn(mood))
    }

    func resolve(_ s: WatchPayload.SuggestionRow, accept: Bool) {
        payload.suggestions?.removeAll { $0.id == s.id }
        WKInterfaceDevice.current().play(accept ? .success : .click)
        send(accept ? .acceptSuggestion(s.id) : .dismissSuggestion(s.id))
    }

    func takeMed(_ m: WatchPayload.MedRow) {
        if let i = payload.meds?.firstIndex(of: m) { payload.meds?[i].takenAt = Date() }
        WKInterfaceDevice.current().play(.success)
        send(.takeMed(m.id, m.slot))
    }

    func archive(_ mail: WatchPayload.MailRow) {
        payload.mail?.removeAll { $0.id == mail.id }
        WKInterfaceDevice.current().play(.success)
        send(.archiveMail(mail.id))
    }

    func contacted(_ person: WatchPayload.PersonRow) {
        payload.people?.removeAll { $0.id == person.id }
        send(.loggedContact(person.id))
    }

    func carryOver() {
        payload.tasks = []
        WKInterfaceDevice.current().play(.success)
        send(.carryOverToday)
    }

    /// Ask Keel: the iPhone answers with Apple Intelligence (needs the iPhone nearby).
    func ask(_ question: String) async -> String {
        guard WCSession.default.isReachable else { return "Your iPhone needs to be nearby to answer." }
        return await withCheckedContinuation { cont in
            WCSession.default.sendMessage(["ask": question], replyHandler: { reply in
                cont.resume(returning: reply["answer"] as? String ?? "No answer.")
            }, errorHandler: { _ in
                cont.resume(returning: "Couldn't reach your iPhone.")
            })
        }
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

// MARK: - Screens

struct WatchRoot: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                NowCard()
                    .listRowBackground(Color.clear)

                if let s = store.payload.suggestions, !s.isEmpty {
                    link("Keel prepared \(s.count)", "sparkles", accent, nil) { SuggestionsPage() }
                }

                if store.payload.checkedInMood == nil { CheckInRow() }

                Section {
                    link("Today", "checklist", accent, "\(store.payload.tasks.count)") { TasksPage() }
                    link("Calendar", "calendar", .red, store.payload.events.first(where: { $0.end > Date() }).map { $0.start.formatted(date: .omitted, time: .shortened) }) { AgendaPage() }
                    link("Inbox", "tray.fill", .blue, (store.payload.mail?.count ?? 0) > 0 ? "\(store.payload.mail!.count)" : nil) { InboxPage() }
                    link("Habits", "link", .purple, "\(store.payload.habits.filter(\.doneToday).count)/\(store.payload.habits.count)") { HabitsPage() }
                    link("Focus", "moon.zzz.fill", .indigo, nil) { FocusPage() }
                }
                Section {
                    link("Ask Keel", "sparkles", .cyan, nil) { AskPage() }
                    link("Capture", "plus.circle.fill", calm, nil) { AddPage() }
                    link("Breathe", "lungs.fill", .mint, nil) { BreathePage() }
                    if let d = store.payload.dopamine, !d.isEmpty { link("Need a boost?", "dice.fill", .orange, nil) { BoostPage(items: d) } }
                }
                if store.payload.calm != true {
                    Section {
                        if let p = store.payload.people, !p.isEmpty { link("Keep in touch", "person.2.fill", .pink, "\(p.count)") { PeoplePage() } }
                        if let p = store.payload.promises, !p.isEmpty { link("Promises", "hand.raised.fill", .orange, "\(p.count)") { ListPage(title: "Promises", items: p) } }
                        if let f = store.payload.followUps, !f.isEmpty { link("Awaiting reply", "bubble.left.and.exclamationmark.bubble.right", .teal, "\(f.count)") { ListPage(title: "Awaiting reply", items: f) } }
                        if let c = store.payload.countdowns, !c.isEmpty { link("Countdowns", "hourglass", .yellow, nil) { CountdownsPage() } }
                        if let p = store.payload.projects, !p.isEmpty { link("Projects", "folder.fill", .blue, "\(p.count)") { ProjectsPage() } }
                        if let m = store.payload.meds, !m.isEmpty {
                            link("Meds", "pills.fill", .mint, "\(m.filter { $0.takenAt != nil }.count)/\(m.count)") { MedsPage() }
                        }
                        if let s = store.payload.momentum { link("Momentum", "trophy.fill", .orange, "\(s)") { MomentumPage() } }
                        if let d = store.payload.deliveries, !d.isEmpty { link("Deliveries", "shippingbox.fill", .brown, "\(d.count)") { DeliveriesPage() } }
                        if let m = store.payload.subscriptionsMonthly {
                            HStack {
                                Image(systemName: "creditcard.fill").foregroundStyle(.green).frame(width: 22)
                                Text("Subscriptions")
                                Spacer()
                                Text(m).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        if let m = store.payload.moodWeek, !m.isEmpty { link("Mood", "face.smiling", .yellow, nil) { MoodPage() } }
                        if let z = store.payload.worldClock, !z.isEmpty { link("World clock", "globe", .teal, nil) { WorldClockPage(zones: z) } }
                        link("Day in review", "moon.stars.fill", .indigo, nil) { DayReviewPage() }
                    }
                }
            }
            .navigationTitle("Keel")
        }
    }

    private func link<D: View>(_ title: String, _ icon: String, _ color: Color, _ badge: String?, @ViewBuilder _ dest: () -> D) -> some View {
        NavigationLink { dest() } label: {
            HStack {
                Image(systemName: icon).foregroundStyle(color).frame(width: 22)
                Text(title)
                Spacer()
                if let badge { Text(badge).font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }
}

/// Top of the home screen: focus countdown, or your one thing and energy.
struct NowCard: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let end = store.payload.focusEndsAt, end > Date() {
                Label("Focusing", systemImage: "moon.zzz.fill").font(.caption).foregroundStyle(accent)
                Text(timerInterval: Date()...end, countsDown: true)
                    .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
            } else {
                if let w = store.payload.weather {
                    HStack(spacing: 4) {
                        Image(systemName: w.symbol).symbolRenderingMode(.multicolor)
                        Text("\(w.temperature) · H \(w.high) L \(w.low)")
                        if let r = w.rainFrom { Text("☔︎ \(r.formatted(date: .omitted, time: .shortened))") }
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
                if let trip = store.payload.nextTrip {
                    Label(trip, systemImage: "airplane").font(.caption2).foregroundStyle(accent).lineLimit(2)
                }
                if let b = store.payload.briefing, Calendar.current.component(.hour, from: Date()) < 11 {
                    Text(b).font(.caption2).foregroundStyle(.secondary).lineLimit(4)
                }
                Text("JUST ONE THING").font(.caption2.weight(.bold)).foregroundStyle(accent)
                Text(store.payload.nextThing ?? "Nothing urgent").font(.headline).lineLimit(3)
                if let step = store.payload.nextThingStep { Text("Start: \(step)").font(.caption2).foregroundStyle(.secondary) }
                HStack(spacing: 4) {
                    ForEach([(1, "battery.25"), (2, "battery.50"), (3, "battery.100.bolt")], id: \.0) { level, icon in
                        Button { store.setEnergy(level) } label: {
                            Image(systemName: icon).font(.caption)
                                .foregroundStyle(store.payload.energy == level ? accent : .secondary)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}

struct CheckInRow: View {
    @Environment(WatchStore.self) private var store
    private let faces = ["😞", "😕", "😐", "🙂", "😄"]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("How are you?").font(.caption)
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { m in
                    Button(faces[m - 1]) { store.checkIn(m) }.buttonStyle(.plain).frame(maxWidth: .infinity)
                }
            }
            .font(.title3)
        }
    }
}

struct TasksPage: View {
    @Environment(WatchStore.self) private var store
    var body: some View {
        List {
            if store.payload.tasks.isEmpty { Text("All done for today 🎉").foregroundStyle(.secondary) }
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
                .swipeActions {
                    Button { store.moveTomorrow(t) } label: { Label("Tomorrow", systemImage: "sunrise") }.tint(.orange)
                }
            }
        }
        .navigationTitle("Today")
    }
}

struct AgendaPage: View {
    @Environment(WatchStore.self) private var store
    var body: some View {
        List {
            let upcoming = store.payload.events.filter { $0.end > Date() }
            if upcoming.isEmpty { Text("Nothing else today").foregroundStyle(.secondary) }
            ForEach(upcoming, id: \.self) { e in
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.title).font(.headline).lineLimit(2)
                    Text("\(e.start.formatted(date: .omitted, time: .shortened)) – \(e.end.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                    if e.start > Date() { Text(e.start, style: .relative).font(.caption2).foregroundStyle(accent) }
                }
            }
        }
        .navigationTitle("Calendar")
    }
}

struct InboxPage: View {
    @Environment(WatchStore.self) private var store
    var body: some View {
        List {
            let mail = store.payload.mail ?? []
            if let n = store.payload.unreadCount, n > 0 {
                Text("\(n) unread · \(mail.count) need you").font(.caption2).foregroundStyle(.secondary).listRowBackground(Color.clear)
            }
            if mail.isEmpty { Text("Nothing important waiting").foregroundStyle(.secondary) }
            ForEach(mail) { m in
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.from).font(.headline).lineLimit(1)
                    Text(m.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                }
                .swipeActions {
                    Button { store.archive(m) } label: { Label("Done", systemImage: "checkmark") }.tint(calm)
                }
            }
        }
        .navigationTitle("Inbox")
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
                        Image(systemName: h.doneToday ? "checkmark.circle.fill" : h.icon).foregroundStyle(h.doneToday ? calm : accent)
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

struct FocusPage: View {
    @Environment(WatchStore.self) private var store
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let end = store.payload.focusEndsAt, end > Date() {
                    Text(timerInterval: Date()...end, countsDown: true)
                        .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                    Button("End focus", role: .destructive) { store.endFocus() }
                    ParkPage()
                } else {
                    ForEach([15, 25, 50, 90], id: \.self) { m in
                        Button("\(m) minutes") { store.startFocus(m) }.tint(accent)
                    }
                }
                if let mins = store.payload.focusMinutesWeek {
                    Text("This week: \(mins / 60)h \(mins % 60)m focused").font(.caption2).foregroundStyle(.secondary)
                }
                if let days = store.payload.focusDays, days.contains(where: { $0 > 0 }) {
                    let top = max(1, days.max() ?? 1)
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(Array(days.enumerated()), id: \.offset) { i, m in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(i == days.count - 1 ? accent : accent.opacity(0.5))
                                .frame(height: max(2, CGFloat(m) / CGFloat(top) * 36))
                        }
                    }
                    .frame(height: 38)
                }
            }
        }
        .navigationTitle("Focus")
    }
}

struct AskPage: View {
    @Environment(WatchStore.self) private var store
    @State private var question = ""
    @State private var answer: String?
    @State private var thinking = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Ask Keel…", text: $question).onSubmit { Task { await ask() } }
                if thinking { ProgressView() }
                if let answer { Text(answer).font(.body) }
                if answer == nil && !thinking {
                    ForEach(["What's next?", "Did I take my meds?", "Where's my package?", "When's my next trip?", "How was my week?"], id: \.self) { q in
                        Button(q) { question = q; Task { await ask() } }.font(.caption2)
                    }
                    Text("Or tap above and speak.").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Ask Keel")
    }
    private func ask() async {
        guard !question.isEmpty else { return }
        thinking = true
        answer = await store.ask(question)
        thinking = false
        WKInterfaceDevice.current().play(.notification)
    }
}

struct PeoplePage: View {
    @Environment(WatchStore.self) private var store
    var body: some View {
        List {
            ForEach(store.payload.people ?? []) { p in
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.name).font(.headline)
                    if let last = p.lastContact { Text("Last: \(last.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(.secondary) }
                    let digits = p.phone.filter { $0.isNumber || $0 == "+" }
                    HStack {
                        if !digits.isEmpty {
                            Button { open("tel:\(digits)", p) } label: { Image(systemName: "phone.fill") }.tint(calm)
                            Button { open("sms:\(digits)", p) } label: { Image(systemName: "message.fill") }.tint(accent)
                        }
                        Button { store.contacted(p) } label: { Image(systemName: "checkmark") }
                    }
                }
            }
        }
        .navigationTitle("Keep in touch")
    }
    private func open(_ s: String, _ p: WatchPayload.PersonRow) {
        if let url = URL(string: s) { WKApplication.shared().openSystemURL(url) }
        store.contacted(p)
    }
}

struct CountdownsPage: View {
    @Environment(WatchStore.self) private var store
    var body: some View {
        List {
            ForEach(store.payload.countdowns ?? [], id: \.self) { c in
                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: c.date)).day ?? 0
                HStack {
                    Text(c.emoji)
                    Text(c.title).lineLimit(2)
                    Spacer()
                    Text(days == 0 ? "Today" : "\(days)d").font(.headline).foregroundStyle(accent)
                }
            }
        }
        .navigationTitle("Countdowns")
    }
}

struct ListPage: View {
    let title: String
    let items: [String]
    var body: some View {
        List { ForEach(items, id: \.self) { Text($0).font(.caption) } }.navigationTitle(title)
    }
}

struct DayReviewPage: View {
    @Environment(WatchStore.self) private var store
    @State private var carried = false
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("\(store.payload.doneToday ?? 0)").font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(calm)
                Text("done today").font(.caption).foregroundStyle(.secondary)
                if !store.payload.tasks.isEmpty {
                    Button(carried ? "Moved to tomorrow" : "Move \(store.payload.tasks.count) left to tomorrow") {
                        store.carryOver(); carried = true
                    }
                    .disabled(carried)
                }
                Text("Work is done. You're allowed to rest.").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .navigationTitle("Day in review")
    }
}

struct AddPage: View {
    @Environment(WatchStore.self) private var store
    @State private var text = ""
    @State private var added = false
    @State private var dump = ""
    @State private var dumped = false
    @State private var event = ""
    @State private var eventSent = false

    var body: some View {
        ScrollView { VStack(spacing: 10) {
            TextField("Add a task…", text: $text).onSubmit(add)    // dictation or Scribble
            Button("Add", action: add).tint(accent).disabled(text.isEmpty)
            if added { Label("Added", systemImage: "checkmark.circle.fill").foregroundStyle(calm).font(.caption) }
            Text("Try “Call mom tomorrow 5pm”").font(.caption2).foregroundStyle(.secondary)
            Divider()
            TextField("New event…", text: $event).onSubmit(sendEvent)
            if eventSent { Label("Added to Calendar", systemImage: "calendar.badge.checkmark").foregroundStyle(calm).font(.caption) }
            Text("Try “Lunch with Sam Friday 1pm”").font(.caption2).foregroundStyle(.secondary)
            Divider()
            TextField("Brain dump…", text: $dump).onSubmit(sendDump)
            if dumped { Label("Sorting on iPhone", systemImage: "brain.head.profile").foregroundStyle(calm).font(.caption) }
            Text("Ramble everything. Keel splits it into tasks, events and notes.").font(.caption2).foregroundStyle(.secondary)
        } }
        .navigationTitle("Capture")
    }

    private func sendEvent() {
        guard !event.isEmpty else { return }
        store.send(.addEvent(event))
        WKInterfaceDevice.current().play(.success)
        event = ""
        eventSent = true
    }

    private func sendDump() {
        guard !dump.isEmpty else { return }
        store.send(.brainDump(dump))
        WKInterfaceDevice.current().play(.success)
        dump = ""
        dumped = true
    }

    private func add() {
        guard !text.isEmpty else { return }
        store.add(text)
        text = ""
        added = true
    }
}

struct ProjectsPage: View {
    @Environment(WatchStore.self) private var store
    var body: some View {
        List {
            ForEach(store.payload.projects ?? [], id: \.self) { p in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(p.emoji) \(p.name)").lineLimit(2)
                    ProgressView(value: p.total == 0 ? 0 : Double(p.done) / Double(p.total)).tint(calm)
                    Text("\(p.done)/\(p.total) done").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Projects")
    }
}

/// During focus on the watch: park a distracting thought without stopping.
struct ParkPage: View {
    @Environment(WatchStore.self) private var store
    @State private var text = ""
    @State private var parked = 0
    var body: some View {
        VStack(spacing: 4) {
            TextField("Park a thought…", text: $text).onSubmit {
                guard !text.isEmpty else { return }
                store.park(text); text = ""; parked += 1
            }
            if parked > 0 { Text("\(parked) parked for later").font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

/// The last 7 check-ins from the iPhone mood journal.
struct MoodPage: View {
    @Environment(WatchStore.self) private var store
    private let faces = ["😞", "😕", "😐", "🙂", "😄"]
    var body: some View {
        List {
            ForEach(store.payload.moodWeek ?? [], id: \.day) { d in
                HStack {
                    Text(faces[max(0, min(4, d.mood - 1))]).font(.title3)
                    Text(d.day.formatted(.dateTime.weekday(.abbreviated).day()))
                    Spacer()
                    if let e = d.energy { Image(systemName: ["battery.25", "battery.50", "battery.100"][max(0, min(2, e - 1))]).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("Mood")
    }
}

/// Today's doses: tap to log as taken (also clears the iPhone reminder).
struct MedsPage: View {
    @Environment(WatchStore.self) private var store
    var body: some View {
        List {
            ForEach(store.payload.meds ?? [], id: \.self) { m in
                Button { if m.takenAt == nil { store.takeMed(m) } } label: {
                    HStack {
                        Image(systemName: m.takenAt == nil ? "pills" : "checkmark.circle.fill")
                            .foregroundStyle(m.takenAt == nil ? accent : calm)
                        VStack(alignment: .leading) {
                            Text(m.name)
                            Text(m.takenAt.map { "Taken \($0.formatted(date: .omitted, time: .shortened))" } ?? "Due \(slotLabel(m.slot))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Meds")
    }
    private func slotLabel(_ s: Int) -> String {
        (Calendar.current.date(bySettingHour: s / 60, minute: s % 60, second: 0, of: Date()) ?? Date()).formatted(date: .omitted, time: .shortened)
    }
}

struct MomentumPage: View {
    @Environment(WatchStore.self) private var store
    var body: some View {
        ScrollView { VStack(spacing: 8) {
            Gauge(value: Double(store.payload.momentum ?? 0), in: 0...100) {
                Text("Momentum")
            } currentValueLabel: { Text("\(store.payload.momentum ?? 0)") }
                .gaugeStyle(.accessoryCircularCapacity).tint(accent).scaleEffect(1.4).padding()
            Text("Momentum only goes up today.").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let a = store.payload.achievementsUnlocked { Label("\(a) achievements", systemImage: "trophy.fill").font(.caption) }
            if let w = store.payload.weekDone { Label("\(w) done this week", systemImage: "checkmark.circle").font(.caption) }
            if let s = store.payload.doneStreak, s > 1 { Label("\(s)-day streak", systemImage: "flame.fill").font(.caption).foregroundStyle(.orange) }
        } }
        .navigationTitle("Momentum")
    }
}

struct DeliveriesPage: View {
    @Environment(WatchStore.self) private var store
    var body: some View {
        List {
            ForEach(store.payload.deliveries ?? [], id: \.self) { d in
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.title).font(.caption).lineLimit(2)
                    Text("\(d.carrier) · \(d.status)").font(.caption2).foregroundStyle(d.status.contains("today") || d.status.contains("Out") ? accent : .secondary)
                }
            }
        }
        .navigationTitle("Deliveries")
    }
}

struct WorldClockPage: View {
    let zones: [String]
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            List(zones, id: \.self) { id in
                if let z = TimeZone(identifier: id) {
                    HStack {
                        Text(id.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? id).font(.caption)
                        Spacer()
                        Text(ctx.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: z))).monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("World Clock")
    }
}

/// One minute of box breathing with a tap on the wrist at each change, for overwhelming moments.
struct BreathePage: View {
    @State private var expanded = false
    @State private var phase = "Ready"
    @State private var round = 0

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(calm.opacity(0.2))
                Circle().fill(calm.opacity(0.6)).scaleEffect(expanded ? 1 : 0.4)
                Text(phase).font(.headline)
            }
            .frame(width: 120, height: 120)
            Text(round > 0 ? "Round \(round) of 4" : "In 4 · hold 4 · out 4 · hold 4").font(.caption2).foregroundStyle(.secondary)
        }
        .navigationTitle("Breathe")
        .task {
            for r in 1...4 {
                round = r
                phase = "In"; WKInterfaceDevice.current().play(.start)
                withAnimation(.easeInOut(duration: 4)) { expanded = true }
                try? await Task.sleep(for: .seconds(4))
                phase = "Hold"; WKInterfaceDevice.current().play(.click)
                try? await Task.sleep(for: .seconds(4))
                phase = "Out"; WKInterfaceDevice.current().play(.stop)
                withAnimation(.easeInOut(duration: 4)) { expanded = false }
                try? await Task.sleep(for: .seconds(4))
                phase = "Hold"; WKInterfaceDevice.current().play(.click)
                try? await Task.sleep(for: .seconds(4))
                if Task.isCancelled { return }
            }
            phase = "Done"; WKInterfaceDevice.current().play(.success)
        }
    }
}

/// A random healthy boost from the iPhone dopamine menu.
struct BoostPage: View {
    let items: [String]
    @State private var pick: String?
    var body: some View {
        VStack(spacing: 10) {
            Text(pick ?? "Bored or stuck?").font(.headline).multilineTextAlignment(.center)
            Button(pick == nil ? "Pick one for me" : "Another") {
                pick = items.randomElement(); WKInterfaceDevice.current().play(.click)
            }
            .tint(accent)
        }
        .navigationTitle("Boost")
        .onAppear { pick = items.randomElement() }
    }
}

/// Autopilot on the wrist: approve or dismiss what Keel prepared.
struct SuggestionsPage: View {
    @Environment(WatchStore.self) private var store
    var body: some View {
        List {
            ForEach(store.payload.suggestions ?? []) { s in
                VStack(alignment: .leading, spacing: 6) {
                    Label(s.title, systemImage: s.icon).font(.caption.weight(.semibold))
                    Text(s.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(5)
                    HStack {
                        Button(s.accept) { store.resolve(s, accept: true) }.tint(accent)
                        Button { store.resolve(s, accept: false) } label: { Image(systemName: "xmark") }
                    }
                    .font(.caption2)
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Autopilot")
    }
}
