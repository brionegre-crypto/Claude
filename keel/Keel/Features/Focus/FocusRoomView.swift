import SwiftUI
import SwiftData
import UserNotifications

/// Body doubling: a calm companion "works alongside you", with ambient sound, a "just 5 minutes" starter,
/// and gentle check-ins. If you drift, it helps you restart with one tiny step. Check-ins also reach
/// Apple Watch as a tap on the wrist when the phone is locked.
struct FocusRoomView: View {
    var task: TaskItem? = nil

    @Environment(\.modelContext) private var ctx
    @Environment(ShutdownManager.self) private var shutdown
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var allOpen: [TaskItem]
    private var open: [TaskItem] { allOpen.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) } }
    @AppStorage("room.companion") private var companionRaw = Companion.calm.rawValue
    @AppStorage("room.checkEvery") private var checkEvery = 10
    @AppStorage("focus.sound") private var sound = "off"
    @State private var chosen: TaskItem?
    @State private var intention = ""
    @State private var nextCheck: Date?
    @State private var showCheckIn = false
    @State private var drifted = false
    @State private var starter = false            // "just 5 minutes" session
    @State private var askKeepGoing = false
    @State private var messageIndex = 0
    @State private var now = Date()
    @State private var drifts = 0
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    enum Companion: String, CaseIterable, Identifiable {
        case calm, cheerful, quiet
        var id: String { rawValue }
        var name: String { switch self { case .calm: "Sol"; case .cheerful: "Pip"; case .quiet: "Wren" } }
        var label: String { switch self { case .calm: "Calm"; case .cheerful: "Cheerful"; case .quiet: "Quiet" } }
        var color: Color { switch self { case .calm: DS.Palette.focus; case .cheerful: .orange; case .quiet: .teal } }
        var lines: [String] {
            switch self {
            case .calm: ["I'm right here, working too.", "Just the next small step.", "No rush. Steady is fast enough.",
                         "If your mind wanders, that's fine. Come back.", "You're doing the thing. That's the hard part."]
            case .cheerful: ["We've got this!", "Look at you go.", "One more little bit, then another.",
                             "Momentum is building!", "Future you is going to be so pleased."]
            case .quiet: ["…", "Still here.", "Working.", "Keep going.", "…"]
            }
        }
    }

    private var companion: Companion { Companion(rawValue: companionRaw) ?? .calm }
    private var focusTitle: String { chosen?.title ?? (intention.isEmpty ? "Your work" : intention) }

    var body: some View {
        VStack(spacing: DS.Space.l) {
            if let s = shutdown.active {
                running(s)
            } else {
                setup
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [companion.color.opacity(shutdown.active == nil ? 0.06 : 0.2), .clear],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .navigationTitle("Focus Room")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if chosen == nil { chosen = task } }
        .onReceive(tick) { t in
            now = t
            guard shutdown.active != nil else { return }
            if let n = nextCheck, t >= n, !showCheckIn { showCheckIn = true; Haptics.tap() }
            if Int(t.timeIntervalSince1970) % 180 == 0 { withAnimation { messageIndex += 1 } }
            if let end = shutdown.endsAt, t >= end, !askKeepGoing { askKeepGoing = true; Haptics.milestone() }
        }
        .sheet(isPresented: $showCheckIn) { checkInSheet.presentationDetents([.medium]) }
        .confirmationDialog(starter ? "Nice start. Keep going?" : "Time's up. Keep going?", isPresented: $askKeepGoing, titleVisibility: .visible) {
            Button("10 more minutes") { extend(10) }
            Button("25 more minutes") { extend(25) }
            Button("I'm done", role: .cancel) { finish() }
        } message: { Text(starter ? "Starting was the hardest part, and you did it." : "You stayed with it. That counts.") }
    }

    // MARK: Setup

    private var setup: some View {
        ScrollView {
            VStack(spacing: DS.Space.l) {
                CompanionBubble(companion: companion, active: false)
                    .frame(height: 150)
                Text("\(companion.name) will work alongside you").font(DS.Font.headline)
                Text("Like studying next to a friend: someone's there, nobody's judging.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("What are you working on?").font(DS.Font.headline)
                    Menu {
                        Button("Something else") { chosen = nil }
                        ForEach(open.prefix(15)) { t in Button(t.title) { chosen = t } }
                    } label: {
                        HStack {
                            Text(chosen?.title ?? "Choose a task").lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .padding(DS.Space.m)
                        .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.chip))
                    }
                    if chosen == nil {
                        TextField("Or type it, e.g. “reply to Sam”", text: $intention).textFieldStyle(.roundedBorder)
                    }
                }

                Picker("Companion", selection: $companionRaw) {
                    ForEach(Companion.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)

                HStack {
                    Picker(selection: $sound) {
                        ForEach(FocusSound.Kind.allCases) { Text($0.label).tag($0.rawValue) }
                    } label: { Label("Sound", systemImage: "waveform") }
                    Spacer()
                    Picker(selection: $checkEvery) {
                        Text("Check in every 5 min").tag(5); Text("Every 10 min").tag(10)
                        Text("Every 15 min").tag(15); Text("No check-ins").tag(0)
                    } label: { Label("Check-ins", systemImage: "hand.wave") }
                }
                .font(DS.Font.caption)

                Button { begin(minutes: 5, starter: true) } label: {
                    VStack(spacing: 2) {
                        Text("Just 5 minutes").font(DS.Font.headline)
                        Text("The easiest way to start").font(.caption2).opacity(0.85)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, DS.Space.m)
                    .background(companion.color, in: Capsule()).foregroundStyle(.white)
                }
                HStack {
                    ForEach([15, 25, 50], id: \.self) { m in
                        Button("\(m) min") { begin(minutes: m, starter: false) }.buttonStyle(.bordered).tint(companion.color)
                    }
                }
                if let s = statsLine { Text(s).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft) }
            }
        }
    }

    private var statsLine: String? {
        let n = UserDefaults.standard.integer(forKey: "room.sessions")
        guard n > 0 else { return nil }
        return "\(n) session\(n == 1 ? "" : "s") in the Focus Room so far."
    }

    // MARK: Running

    private func running(_ s: FocusSession) -> some View {
        let total = Double(s.plannedMinutes * 60)
        let left = max(0, (shutdown.endsAt ?? now).timeIntervalSince(now))
        let lines = companion.lines
        return VStack(spacing: DS.Space.l) {
            CompanionBubble(companion: companion, active: true).frame(height: 190)
            Text(lines[messageIndex % lines.count])
                .font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
                .contentTransition(.opacity).id(messageIndex)
            VStack(spacing: 4) {
                Text(focusTitle).font(DS.Font.title).multilineTextAlignment(.center)
                if let step = chosen?.microSteps.first(where: { !$0.done }) {
                    Text("Now: \(step.text)").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
            }
            ZStack {
                TimeRing(progress: total > 0 ? left / total : 0, color: companion.color, lineWidth: 10).frame(width: 150, height: 150)
                Text(Duration.seconds(left).formatted(.time(pattern: .minuteSecond))).font(DS.Font.headline.monospacedDigit())
            }
            ParkingLotField()
            HStack(spacing: DS.Space.m) {
                Button { drifted = true; showCheckIn = true } label: { Label("I drifted", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(.bordered)
                Button("End") { finish() }.buttonStyle(.bordered).tint(.gray)
            }
        }
    }

    private var checkInSheet: some View {
        VStack(spacing: DS.Space.l) {
            Image(systemName: drifted ? "arrow.uturn.backward.circle.fill" : "hand.wave.fill")
                .font(.system(size: 44)).foregroundStyle(companion.color)
            Text(drifted ? "No problem. Let's restart small." : "\(companion.name) here. Still with me?").font(DS.Font.title)
                .multilineTextAlignment(.center)
            if drifted {
                Text("Just do this next: \(restartStep)")
                    .font(DS.Font.body).multilineTextAlignment(.center)
                    .padding().background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.card))
                Button("OK, I'm back") { backOnTrack() }.buttonStyle(.borderedProminent).tint(companion.color)
            } else {
                HStack {
                    Button("Yes, on it") { Haptics.success(); scheduleNextCheck(); showCheckIn = false }
                        .buttonStyle(.borderedProminent).tint(companion.color)
                    Button("I drifted") { drifted = true; drifts += 1; Haptics.tap() }.buttonStyle(.bordered)
                }
            }
        }
        .padding()
    }

    private var restartStep: String {
        if let step = chosen?.microSteps.first(where: { !$0.done }) { return step.text }
        return "spend 2 minutes on “\(focusTitle)”. Open it and do the first tiny thing."
    }

    // MARK: Actions

    private func begin(minutes: Int, starter: Bool) {
        self.starter = starter
        drifts = 0
        ctx.insert(shutdown.start(minutes: minutes, level: .soft, task: chosen))
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "room.sessions") + 1, forKey: "room.sessions")
        scheduleNextCheck()
        scheduleCheckInNotifications(minutes: minutes)
        Haptics.success()
    }

    private func extend(_ minutes: Int) {
        shutdown.end(early: false)
        starter = false
        ctx.insert(shutdown.start(minutes: minutes, level: .soft, task: chosen))
        scheduleNextCheck()
        scheduleCheckInNotifications(minutes: minutes)
    }

    private func finish() {
        if let s = shutdown.active, let t = chosen {
            ADHDCoach.recordActual(t, minutes: Int(Date().timeIntervalSince(s.startedAt) / 60))
        }
        if shutdown.active != nil { shutdown.end(early: (shutdown.endsAt ?? Date()) > Date()) }
        nextCheck = nil
        cancelCheckInNotifications()
        Haptics.milestone()
    }

    private func backOnTrack() {
        drifted = false
        showCheckIn = false
        scheduleNextCheck()
        Haptics.success()
    }

    private func scheduleNextCheck() {
        nextCheck = checkEvery > 0 ? Date().addingTimeInterval(Double(checkEvery * 60)) : nil
    }

    /// While the phone is locked, check-ins arrive as notifications (and a tap on Apple Watch).
    private func scheduleCheckInNotifications(minutes: Int) {
        cancelCheckInNotifications()
        guard checkEvery > 0 else { return }
        let center = UNUserNotificationCenter.current()
        var at = checkEvery
        var i = 0
        while at < minutes && i < 12 {
            let c = UNMutableNotificationContent()
            c.title = "\(companion.name): still with me?"
            c.body = "Still on “\(focusTitle)”? If you drifted, come back for just 2 minutes."
            c.sound = .default
            c.threadIdentifier = "focusroom"
            c.userInfo = ["deeplink": "com.keel.app://focus"]
            center.add(UNNotificationRequest(identifier: "room.checkin.\(i)", content: c,
                                             trigger: UNTimeIntervalNotificationTrigger(timeInterval: Double(at * 60), repeats: false)))
            at += checkEvery; i += 1
        }
    }

    private func cancelCheckInNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: (0..<12).map { "room.checkin.\($0)" })
    }
}

/// The companion: a soft, slowly breathing presence. Nothing to read, just company.
struct CompanionBubble: View {
    let companion: FocusRoomView.Companion
    let active: Bool
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(companion.color.opacity(0.12 - Double(i) * 0.03))
                    .scaleEffect(breathe ? 1.0 + Double(i) * 0.18 : 0.85 + Double(i) * 0.12)
            }
            Circle().fill(companion.color.gradient).frame(width: 84, height: 84)
                .overlay(Image(systemName: active ? "person.fill" : "person").font(.system(size: 34)).foregroundStyle(.white))
                .shadow(color: companion.color.opacity(0.4), radius: 16)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: active ? 4 : 5).repeatForever(autoreverses: true)) { breathe = true }
        }
        .accessibilityElement()
        .accessibilityLabel("\(companion.name), your focus companion\(active ? ", working with you" : "")")
    }
}
