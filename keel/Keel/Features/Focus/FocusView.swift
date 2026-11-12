import SwiftUI
import SwiftData
import FamilyControls
import UserNotifications

/// Deep work with escalating Shutdown, a visual time ring, optional body-double mode,
/// and the end-of-day Shutdown Ritual.
struct FocusView: View {
    var preselected: TaskItem? = nil
    var bodyDouble: Bool = false

    @Environment(\.modelContext) private var ctx
    @Environment(ShutdownManager.self) private var shutdown
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var tasks: [TaskItem]
    @State private var minutes: Int = { let m = UserDefaults.standard.integer(forKey: "focus.defaultMinutes"); return m > 0 ? m : 25 }()
    @State private var level: ShutdownManager.Level = .soft
    @State private var showPicker = false
    @State private var showRitual = false
    @State private var confirmQuit = false
    @State private var coolDownLeft = 0
    @State private var now = Date()
    @AppStorage("focus.rounds") private var roundsOn = false
    @State private var round = 1
    @State private var breakEndsAt: Date?
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
            VStack(spacing: DS.Space.l) {
                if let session = shutdown.active { running(session) }
                else if let end = breakEndsAt { breakView(end) }
                else { setup }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(colors: [DS.Palette.focus.opacity(shutdown.active == nil ? 0.05 : 0.22), .clear],
                               startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            )
            .navigationTitle(shutdown.active == nil ? "Focus" : "")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showRitual = true } label: { Label("Shutdown ritual", systemImage: "moon.stars") }
                }
            }
            .sheet(isPresented: $showRitual) { ShutdownRitualView() }
            .familyActivityPicker(isPresented: $showPicker, selection: Binding(get: { shutdown.selection }, set: { shutdown.selection = $0 }))
            .onReceive(tick) { now = $0; if coolDownLeft > 0 { coolDownLeft -= 1 } }
    }

    private var setup: some View {
        VStack(spacing: DS.Space.l) {
            FocusStatsStrip()
            Toggle(isOn: $roundsOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Focus rounds").font(DS.Font.headline)
                    Text("Short breaks between rounds, a longer one every 4th").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
            }
            .tint(DS.Palette.focus)
            if let t = preselected {
                Text(t.title).font(DS.Font.title).multilineTextAlignment(.center)
                if bodyDouble { Label("Body-double mode: Keel checks in with you every 10 min", systemImage: "person.2.wave.2").font(DS.Font.caption) }
            }
            Text("\(minutes)").font(DS.Font.timer)
            Text("minutes").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            HStack {
                ForEach([15, 25, 50, 90], id: \.self) { m in
                    Button("\(m)") { withAnimation(DS.spring) { minutes = m }; Haptics.tap() }
                        .buttonStyle(.bordered).tint(minutes == m ? DS.Palette.focus : .gray)
                }
            }
            VStack(spacing: DS.Space.s) {
                ForEach(ShutdownManager.Level.allCases) { l in
                    Button { level = l; Haptics.tap() } label: {
                        HStack {
                            Image(systemName: level == l ? "largecircle.fill.circle" : "circle")
                            VStack(alignment: .leading) { Text(l.title).font(DS.Font.headline); Text(l.detail).font(DS.Font.caption) }
                            Spacer()
                        }
                        .padding(DS.Space.m)
                        .background(level == l ? DS.Palette.focus.opacity(0.1) : DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.chip))
                    }.buttonStyle(.plain)
                }
                if level != .soft {
                    if let reason = shutdown.blockingUnavailableReason {
                        Label(reason, systemImage: "info.circle")
                            .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    } else {
                        Button("Choose apps to block") {
                            Task {
                                if !shutdown.isAuthorized { await shutdown.authorize() }
                                if shutdown.isAuthorized { showPicker = true }
                            }
                        }.font(DS.Font.caption)
                    }
                }
            }
            Button {
                // Without Screen Time permission, Shield/Locked still run as Soft focus plus the cool-down.
                withAnimation(DS.spring) { ctx.insert(shutdown.start(minutes: minutes, level: level, task: preselected)) }
            } label: {
                Text("Begin").font(DS.Font.headline).frame(maxWidth: .infinity).padding(.vertical, DS.Space.m)
                    .background(DS.Palette.focus, in: Capsule()).foregroundStyle(.white)
            }
        }
    }

    private func running(_ s: FocusSession) -> some View {
        let total = Double(s.plannedMinutes * 60)
        let left = max(0, (shutdown.endsAt ?? now).timeIntervalSince(now))
        return VStack(spacing: DS.Space.xl) {
            if let t = tasks.first(where: { $0.id == s.taskId }) {
                Text(t.title).font(DS.Font.title).multilineTextAlignment(.center)
                if let step = t.microSteps.first(where: { !$0.done }) { Text("Now: \(step.text)").font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft) }
            }
            ZStack {
                TimeRing(progress: left / total).frame(width: 260, height: 260)
                Text(Duration.seconds(left).formatted(.time(pattern: .minuteSecond))).font(DS.Font.timer)
            }
            if left == 0 {
                Button("I'm done — log it") { finish(early: false) }.buttonStyle(.borderedProminent).tint(DS.Palette.calm)
            } else if shutdown.level == .locked {
                Button(coolDownLeft > 0 ? "Breathe… \(coolDownLeft)s" : (confirmQuit ? "End anyway" : "End early")) {
                    if confirmQuit && coolDownLeft == 0 { finish(early: true) } else if !confirmQuit { confirmQuit = true; coolDownLeft = 60 }
                }.disabled(coolDownLeft > 0)
            } else {
                Button("End early") { finish(early: true) }.foregroundStyle(DS.Palette.inkSoft)
            }
        }
    }

    private func finish(early: Bool) {
        if let s = shutdown.active, let t = tasks.first(where: { $0.id == s.taskId }) {
            ADHDCoach.recordActual(t, minutes: Int(Date().timeIntervalSince(s.startedAt) / 60))
        }
        shutdown.end(early: early)
        confirmQuit = false
        early ? Haptics.tap() : Haptics.milestone()
        if roundsOn && !early {
            let breakMinutes = round % 4 == 0 ? 15 : 5
            breakEndsAt = Date().addingTimeInterval(Double(breakMinutes * 60))
            scheduleBreakEnd(minutes: breakMinutes)
        } else if early {
            round = 1
        }
    }

    private func breakView(_ end: Date) -> some View {
        let left = max(0, end.timeIntervalSince(now))
        let total = Double((round % 4 == 0 ? 15 : 5) * 60)
        return VStack(spacing: DS.Space.xl) {
            Text(round % 4 == 0 ? "Long break" : "Break").font(DS.Font.title)
            Text("Round \(round) done. Stand up, water, look out a window.").font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
                .multilineTextAlignment(.center)
            ZStack {
                TimeRing(progress: left / total, color: DS.Palette.calm).frame(width: 220, height: 220)
                Text(Duration.seconds(left).formatted(.time(pattern: .minuteSecond))).font(DS.Font.timer)
            }
            Button {
                breakEndsAt = nil
                round += 1
                ctx.insert(shutdown.start(minutes: minutes, level: level, task: preselected))
            } label: {
                Text(left > 0 ? "Skip break · start round \(round + 1)" : "Start round \(round + 1)")
                    .font(DS.Font.headline).frame(maxWidth: .infinity).padding(.vertical, DS.Space.m)
                    .background(DS.Palette.focus, in: Capsule()).foregroundStyle(.white)
            }
            Button("Done for now") { breakEndsAt = nil; round = 1 }.foregroundStyle(DS.Palette.inkSoft)
        }
    }

    private func scheduleBreakEnd(minutes: Int) {
        let c = UNMutableNotificationContent()
        c.title = "Break's over"
        c.body = "Ready for round \(round + 1)? Open Keel to start."
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "focus.break", content: c,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: Double(minutes * 60), repeats: false)))
    }
}

/// Cal Newport-style end-of-day shutdown, automated: close every loop so your brain can let go.
struct ShutdownRitualView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var open: [TaskItem]
    @Query(filter: #Predicate<EmailMessage> { !$0.isArchived }) private var inbox: [EmailMessage]
    @State private var step = 0
    @State private var win = ""

    private let steps = ["Capture", "Inbox", "Tomorrow", "Win", "Done"]

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.l) {
                ProgressView(value: Double(step), total: Double(steps.count - 1)).tint(DS.Palette.focus)
                Group {
                    switch step {
                    case 0: card("Anything still in your head?", "Dump it now so it's not keeping you up.") { BrainDumpView() }
                    case 1: card("\(inbox.filter { $0.category == .important }.count) emails need replies",
                                 "Keel will draft them overnight. Nothing goes out without you.") { EmptyView() }
                    case 2: card("Tomorrow's first thing", "Moved \(open.filter { ($0.dueDate ?? .distantFuture) < Date() }.count) unfinished tasks to tomorrow. No guilt.") { EmptyView() }
                            .onAppear { ADHDCoach.resetDay(tasks: open) }
                    case 3: card("One win from today?", "Even small. Especially small.") { TextField("I…", text: $win).textFieldStyle(.roundedBorder) }
                    default:
                        VStack(spacing: DS.Space.m) {
                            Image(systemName: "moon.stars.fill").font(.system(size: 64)).foregroundStyle(DS.Palette.focus).symbolEffect(.pulse)
                            Text("Shutdown complete").font(DS.Font.hero)
                            Text("Work is closed. You're allowed to rest.").foregroundStyle(DS.Palette.inkSoft)
                        }.onAppear { Haptics.milestone() }
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                Spacer()
                Button(step == steps.count - 1 ? "Close" : "Next") {
                    if step == steps.count - 1 { dismiss() } else { withAnimation(DS.spring) { step += 1 } }
                }.buttonStyle(.borderedProminent).tint(DS.Palette.focus)
            }
            .padding()
            .navigationTitle(steps[step])
        }
    }

    private func card<C: View>(_ title: String, _ subtitle: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text(title).font(DS.Font.title)
            Text(subtitle).foregroundStyle(DS.Palette.inkSoft)
            content()
        }
    }
}
