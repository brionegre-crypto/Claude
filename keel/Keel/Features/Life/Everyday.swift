import SwiftUI
import SwiftData
import EventKit
import Charts
import UserNotifications

// MARK: - Visual timer (for time blindness)

/// A coloured disc that shrinks as time passes, so you can see how much is left at a glance.
struct VisualTimerView: View {
    @State private var minutes = 15.0
    @State private var endsAt: Date?
    @State private var pausedLeft: TimeInterval?
    var body: some View {
        VStack(spacing: 24) {
            TimelineView(.animation(minimumInterval: 1, paused: endsAt == nil)) { ctx in
                let total = minutes * 60
                let left = endsAt.map { max(0, $0.timeIntervalSince(ctx.date)) } ?? pausedLeft ?? total
                ZStack {
                    Circle().fill(Color.primary.opacity(0.06))
                    PieSlice(fraction: left / max(1, total)).fill(Color.red.gradient)
                    Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 2)
                    Text(String(format: "%d:%02d", Int(left) / 60, Int(left) % 60)).font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                        .padding(10).background(.ultraThinMaterial, in: Capsule())
                }
                .frame(width: 260, height: 260)
                .onChange(of: left <= 0) { _, done in if done && endsAt != nil { endsAt = nil; pausedLeft = nil; Haptics.milestone() } }
            }
            if endsAt == nil && pausedLeft == nil {
                Slider(value: $minutes, in: 1...90, step: 1) { Text("Minutes") }
                Text("\(Int(minutes)) minutes").font(.headline)
            }
            HStack(spacing: 16) {
                Button(endsAt == nil ? (pausedLeft == nil ? "Start" : "Resume") : "Pause") { toggle() }.buttonStyle(.borderedProminent).tint(.red)
                if endsAt != nil || pausedLeft != nil { Button("Reset") { reset() }.buttonStyle(.bordered) }
            }
            Text("Watching time drain away makes it real. Keel also alerts you when it's done.").font(.caption).foregroundStyle(DS.Palette.inkSoft).multilineTextAlignment(.center)
        }
        .padding()
        .navigationTitle("Visual timer")
    }

    private func toggle() {
        let center = UNUserNotificationCenter.current()
        if let e = endsAt {
            pausedLeft = e.timeIntervalSinceNow; endsAt = nil
            center.removePendingNotificationRequests(withIdentifiers: ["visual.timer"])
        } else {
            let left = pausedLeft ?? minutes * 60
            endsAt = Date().addingTimeInterval(left); pausedLeft = nil
            let c = UNMutableNotificationContent(); c.title = "Time's up"; c.body = "Your \(Int(minutes))-minute timer finished."; c.sound = .default
            center.add(UNNotificationRequest(identifier: "visual.timer", content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, left), repeats: false)))
            Haptics.start()
        }
    }
    private func reset() {
        endsAt = nil; pausedLeft = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["visual.timer"])
    }
}

struct PieSlice: Shape {
    var fraction: Double
    var animatableData: Double { get { fraction } set { fraction = newValue } }
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        p.move(to: c)
        p.addArc(center: c, radius: min(r.width, r.height) / 2, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * max(0, min(1, fraction))), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - Quick wins: tasks that take 10 minutes or less

struct QuickWinsView: View {
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }, animation: .snappy) private var open: [TaskItem]
    var body: some View {
        let quick = open.filter { !$0.isDeleted && ($0.estimatedMinutes ?? 99) <= 10 && !$0.isWaitingOn }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        List {
            Section {
                if quick.isEmpty { Text("No quick tasks right now. Give a task an estimate of 10 minutes or less and it shows up here.").foregroundStyle(DS.Palette.inkSoft) }
                ForEach(quick) { t in
                    HStack {
                        Button { TaskActions.setDone(t, true) } label: { Image(systemName: "circle").font(.title3) }.buttonStyle(.plain).accessibilityLabel("Done: \(t.title)")
                        Text(t.title)
                        Spacer()
                        Text("\(t.estimatedMinutes ?? 0) min").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
            } footer: { Text("Got a few minutes between things? Knock one out: small wins build momentum.") }
        }
        .navigationTitle("Quick wins")
    }
}

// MARK: - Protect focus mornings

/// Holds a focus block on your calendar on weekday mornings (only where you're free), two weeks ahead.
@MainActor
enum ProtectMornings {
    static let onKey = "protect.on", startKey = "protect.start", endKey = "protect.end"
    static let marker = "keel-protect"
    static var on: Bool { UserDefaults.standard.bool(forKey: onKey) }

    static func refresh() {
        let svc = CalendarService.shared
        let cal = Calendar.current
        let now = Date()
        let horizon = cal.date(byAdding: .day, value: 14, to: now) ?? now
        let existing = svc.events(from: now, to: horizon).filter { $0.notes == marker }
        guard on else { for e in existing { try? svc.delete(e) }; return }
        let startH = UserDefaults.standard.object(forKey: startKey) as? Int ?? 9
        let endH = UserDefaults.standard.object(forKey: endKey) as? Int ?? 11
        for i in 0..<14 {
            guard let day = cal.date(byAdding: .day, value: i, to: cal.startOfDay(for: now)) else { continue }
            let wd = cal.component(.weekday, from: day)
            guard wd != 1, wd != 7,
                  let s = cal.date(bySettingHour: startH, minute: 0, second: 0, of: day),
                  let e = cal.date(bySettingHour: endH, minute: 0, second: 0, of: day), s > now else { continue }
            if existing.contains(where: { cal.isDate($0.startDate, inSameDayAs: day) }) { continue }
            let busy = svc.events(from: s, to: e).contains { !$0.isAllDay }
            if busy { continue }
            let ev = EKEvent(eventStore: svc.store)
            ev.calendar = svc.store.defaultCalendarForNewEvents
            ev.title = "Focus time"
            ev.startDate = s; ev.endDate = e
            ev.notes = marker
            ev.availability = .busy
            try? svc.store.save(ev, span: .thisEvent)
        }
        svc.invalidateEvents()
    }
}

struct ProtectMorningsView: View {
    @AppStorage(ProtectMornings.onKey) private var on = false
    @AppStorage(ProtectMornings.startKey) private var start = 9
    @AppStorage(ProtectMornings.endKey) private var end = 11
    var body: some View {
        Form {
            Toggle("Protect focus mornings", isOn: $on).onChange(of: on) { ProtectMornings.refresh() }
            Picker("From", selection: $start) { ForEach(6..<12, id: \.self) { Text(hour($0)).tag($0) } }.onChange(of: start) { if on { ProtectMornings.refresh() } }
            Picker("Until", selection: $end) { ForEach(8..<14, id: \.self) { Text(hour($0)).tag($0) } }.onChange(of: end) { if on { ProtectMornings.refresh() } }
            Section { } footer: { Text("Keel puts a “Focus time” block on your calendar on weekday mornings for the next two weeks, only where you're free, so others see you as busy. Turn it off to remove them.") }
        }
        .navigationTitle("Protect focus mornings")
    }
    private func hour(_ h: Int) -> String { (Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date()).formatted(date: .omitted, time: .shortened) }
}

// MARK: - Energy check-ins through the day

struct EnergyCheck: Codable, Hashable { var at: Date; var level: Int }

enum EnergyChecks {
    static let key = "energy.checks"
    static var all: [EnergyCheck] { get { LocalLog.load(key) } set { LocalLog.save(Array(newValue.suffix(600)), key) } }
    /// Your average energy at each hour of the day (last 3 weeks).
    static func byHour(_ checks: [EnergyCheck]) -> [(hour: Int, avg: Double)] {
        let recent = checks.filter { $0.at > Date().addingTimeInterval(-21 * 86_400) }
        return Dictionary(grouping: recent) { Calendar.current.component(.hour, from: $0.at) }
            .map { (hour: $0.key, avg: Double($0.value.reduce(0) { $0 + $1.level }) / Double($0.value.count)) }
            .sorted { $0.hour < $1.hour }
    }
}

struct EnergyCheckCard: View {
    @State private var checks = EnergyChecks.all
    var body: some View {
        let curve = EnergyChecks.byHour(checks)
        VStack(alignment: .leading, spacing: 8) {
            Label("Energy right now", systemImage: "bolt.heart.fill").font(DS.Font.headline).foregroundStyle(.orange)
            HStack {
                ForEach(1...5, id: \.self) { l in
                    Button { checks.append(EnergyCheck(at: Date(), level: l)); EnergyChecks.all = checks; Haptics.tap() } label: {
                        Text(["🪫", "😴", "😐", "🙂", "⚡️"][l - 1]).font(.title2).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Energy \(l) of 5")
                }
            }
            if curve.count >= 4 {
                Chart(curve, id: \.hour) { p in
                    BarMark(x: .value("Hour", p.hour), y: .value("Energy", p.avg)).foregroundStyle(Color.orange.gradient)
                }
                .chartYScale(domain: 0...5)
                .frame(height: 90)
                if let best = curve.max(by: { $0.avg < $1.avg }) {
                    Text("You usually feel best around \((Calendar.current.date(bySettingHour: best.hour, minute: 0, second: 0, of: Date()) ?? Date()).formatted(date: .omitted, time: .shortened)). Save hard work for then.")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
            } else {
                Text("Tap how you feel a few times a day. After a week Keel shows when your energy peaks.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
        }
        .bodyCard()
    }
}

// MARK: - Intention for today

enum Intention {
    static let key = "intention.days"          // [yyyy-MM-dd: "text|done"]
    static var all: [String: String] {
        get { (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    static var today: (text: String, done: Bool?) {
        guard let v = all[BodyMath.dayKey(Date())] else { return ("", nil) }
        let p = v.components(separatedBy: "|")
        return (p.first ?? "", p.count > 1 ? (p[1] == "yes" ? true : p[1] == "no" ? false : nil) : nil)
    }
    static func set(_ text: String, done: Bool?) {
        var a = all
        a[BodyMath.dayKey(Date())] = text + "|" + (done.map { $0 ? "yes" : "no" } ?? "")
        all = a
    }
}

struct IntentionCard: View {
    @State private var text = Intention.today.text
    @State private var done = Intention.today.done
    @FocusState private var focused: Bool
    var body: some View {
        let evening = Calendar.current.component(.hour, from: Date()) >= 17
        VStack(alignment: .leading, spacing: 8) {
            Label("Today's intention", systemImage: "scope").font(DS.Font.headline).foregroundStyle(DS.Palette.accent)
            if evening && !text.isEmpty {
                Text("“\(text)”").font(DS.Font.body)
                if let done {
                    Text(done ? "You did it. 🎉" : "Not today, and that's OK. Tomorrow's a new one.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                } else {
                    HStack {
                        Button("I did it") { done = true; Intention.set(text, done: true); Haptics.done() }.buttonStyle(.borderedProminent)
                        Button("Not today") { done = false; Intention.set(text, done: false) }.buttonStyle(.bordered)
                    }
                    .font(DS.Font.caption)
                }
            } else {
                TextField("Today, I want to…", text: $text, axis: .vertical)
                    .focused($focused)
                    .onSubmit { Intention.set(text, done: nil) }
                    .onChange(of: focused) { _, f in if !f { Intention.set(text, done: done) } }
                Text("One thing that would make today feel good. Keel asks how it went this evening.").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
            }
        }
        .padding(DS.Space.m)
        .background { PremiumSurface() }
    }
}
