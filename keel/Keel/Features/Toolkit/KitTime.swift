import SwiftUI
import SwiftData
import UserNotifications

// MARK: - Time & focus tools

// 1. Time estimator: guess, then time it, and learn how far off your guesses run.

struct KitEstimate: Codable, Identifiable, Hashable {
    var id = UUID()
    var what: String
    var guess: Int          // minutes
    var actual: Int         // minutes
    var date = Date()
}

enum KitEstimator {
    static let key = "kit.estimates"
    /// How much longer things really take than you guess (1.0 = spot on). Nil until there are 3 timed tasks.
    static func multiplier(_ list: [KitEstimate]) -> Double? {
        let usable = list.filter { $0.guess > 0 && $0.actual > 0 }.suffix(30)
        guard usable.count >= 3 else { return nil }
        return usable.map { Double($0.actual) / Double($0.guess) }.reduce(0, +) / Double(usable.count)
    }
}

struct KitEstimatorView: View {
    @State private var list: [KitEstimate] = []
    @State private var what = ""
    @State private var guess = 15
    @State private var startedAt: Date?

    var body: some View {
        List {
            Section { KitIntro(icon: "hourglass", color: .orange, text: "Time blindness trainer. Guess how long something will take, then time it. After a few, Keel tells you how far off your guesses usually are, so you can plan with real numbers.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            if let m = KitEstimator.multiplier(list) {
                Section {
                    Text(m > 1.15 ? "Things take you about \(m.formatted(.number.precision(.fractionLength(1))))× as long as you guess. Try multiplying your guesses by that."
                         : m < 0.85 ? "You finish faster than you guess (\(m.formatted(.number.precision(.fractionLength(1))))×). You can plan a little tighter."
                         : "Your guesses are spot on. Nice.")
                }
            }
            Section("Time something") {
                if let startedAt {
                    TimelineView(.periodic(from: startedAt, by: 1)) { tl in
                        let secs = Int(tl.date.timeIntervalSince(startedAt))
                        VStack(spacing: 8) {
                            Text(what).font(.headline)
                            Text(Kit.clock(secs)).font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text("You guessed \(Kit.minutes(guess))").font(.caption).foregroundStyle(secs > guess * 60 ? .orange : DS.Palette.inkSoft)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    Button("Done", systemImage: "checkmark.circle.fill") { finish() }.buttonStyle(.borderedProminent)
                    Button("Cancel", role: .destructive) { self.startedAt = nil }
                } else {
                    TextField("What are you about to do?", text: $what)
                    Stepper("My guess: \(Kit.minutes(guess))", value: $guess, in: 1...480, step: guess < 30 ? 1 : 5)
                    Button("Start timing", systemImage: "play.fill") { startedAt = Date(); Haptics.start() }
                        .disabled(what.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section("History") {
                ForEach(list.reversed()) { e in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(e.what)
                            Text(e.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        Text("\(e.guess) → \(e.actual) min").font(.caption.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(e.actual > e.guess ? .orange : DS.Palette.calm)
                    }
                }
            }
        }
        .navigationTitle("Time estimator")
        .onAppear { list = Kit.load(KitEstimator.key) }
    }

    private func finish() {
        guard let s = startedAt else { return }
        list.append(KitEstimate(what: what, guess: guess, actual: max(1, Int((Date().timeIntervalSince(s) / 60).rounded()))))
        Kit.save(list, KitEstimator.key)
        startedAt = nil; what = ""
        Haptics.success()
    }
}

// 2. Timebox list: a run of small tasks, each with its own few minutes.

struct KitBox: Codable, Identifiable, Hashable { var id = UUID(); var title: String; var minutes: Int; var done = false }

struct KitTimeboxView: View {
    static let key = "kit.timebox"
    @State private var boxes: [KitBox] = []
    @State private var title = ""
    @State private var minutes = 10
    @State private var current: UUID?
    @State private var endsAt: Date?

    var body: some View {
        List {
            Section { KitIntro(icon: "list.bullet.indent", color: .indigo, text: "Timebox list. Write a few small things and give each a few minutes. Press Start and Keel runs through them one at a time, with a gentle ping when each one's time is up. Finishing early is a win.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            if let id = current, let box = boxes.first(where: { $0.id == id }), let endsAt {
                Section("Now") {
                    TimelineView(.periodic(from: .now, by: 1)) { tl in
                        let left = Int(endsAt.timeIntervalSince(tl.date))
                        VStack(spacing: 10) {
                            Text(box.title).font(.title3.weight(.semibold))
                            KitRing(fraction: Double(max(0, left)) / Double(box.minutes * 60), text: left >= 0 ? Kit.clock(left) : "+" + Kit.clock(-left),
                                    color: left >= 0 ? .indigo : .orange, size: 170)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    HStack {
                        Button("+5 min") { self.endsAt = endsAt.addingTimeInterval(300); schedulePing() }.buttonStyle(.bordered)
                        Spacer()
                        Button("Done, next", systemImage: "checkmark") { complete(id) }.buttonStyle(.borderedProminent).tint(.indigo)
                    }
                }
            }
            Section("Add") {
                TextField("Small thing to do", text: $title).onSubmit(add)
                Stepper("\(minutes) min", value: $minutes, in: 1...120)
                Button("Add to the list", action: add).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Section {
                ForEach(boxes) { b in
                    HStack {
                        Image(systemName: b.done ? "checkmark.circle.fill" : b.id == current ? "play.circle.fill" : "circle")
                            .foregroundStyle(b.done ? DS.Palette.calm : .indigo)
                        Text(b.title).strikethrough(b.done)
                        Spacer()
                        Text("\(b.minutes) min").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
                .onMove { boxes.move(fromOffsets: $0, toOffset: $1); save() }
                .onDelete { boxes.remove(atOffsets: $0); save() }
            } header: {
                let left = boxes.filter { !$0.done }.reduce(0) { $0 + $1.minutes }
                Text(left > 0 ? "\(Kit.minutes(left)) left · done around \(Date().addingTimeInterval(Double(left * 60)).formatted(date: .omitted, time: .shortened))" : "List")
            }
            if current == nil, boxes.contains(where: { !$0.done }) {
                Button("Start", systemImage: "play.fill") { startNext() }.buttonStyle(.borderedProminent).tint(.indigo)
            }
            if boxes.contains(where: \.done) {
                Button("Clear finished") { boxes.removeAll(where: \.done); save() }
            }
        }
        .navigationTitle("Timebox list")
        .toolbar { EditButton() }
        .onAppear { boxes = Kit.load(Self.key) }
        .onDisappear { Kit.cancel(["kit.timebox.ping"]) }
    }

    private func add() {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        boxes.append(KitBox(title: t, minutes: minutes)); save(); title = ""
    }
    private func save() { Kit.save(boxes, Self.key) }
    private func startNext() {
        guard let next = boxes.first(where: { !$0.done }) else { current = nil; endsAt = nil; return }
        current = next.id
        endsAt = Date().addingTimeInterval(Double(next.minutes * 60))
        schedulePing()
        Haptics.start()
    }
    private func schedulePing() {
        guard let endsAt, let b = boxes.first(where: { $0.id == current }) else { return }
        Kit.cancel(["kit.timebox.ping"])
        Kit.notify("kit.timebox.ping", title: "Time's up: \(b.title)", body: "Done? Tap Done, next. Need more? Add 5 minutes.", at: endsAt)
    }
    private func complete(_ id: UUID) {
        if let i = boxes.firstIndex(where: { $0.id == id }) { boxes[i].done = true }
        save(); Haptics.success()
        Kit.cancel(["kit.timebox.ping"])
        startNext()
    }
}

// 3. Transition timer: warnings before you need to switch to the next thing.

struct KitTransitionView: View {
    @AppStorage("kitlocal.transition.what") private var what = ""
    @AppStorage("kitlocal.transition.at") private var at: Double = 0
    @State private var pick = Date().addingTimeInterval(1800)

    var body: some View {
        List {
            Section { KitIntro(icon: "arrow.triangle.turn.up.right.diamond.fill", color: .teal, text: "Transition timer. Switching tasks is hard when you're absorbed. Tell Keel what's next and when, and it warns you 10, 5 and 1 minute before, so the change never comes as a shock.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            if at > Date().timeIntervalSince1970 {
                Section("Coming up") {
                    TimelineView(.periodic(from: .now, by: 1)) { tl in
                        let left = Int(Date(timeIntervalSince1970: at).timeIntervalSince(tl.date))
                        VStack(spacing: 6) {
                            Text(what).font(.title3.weight(.semibold))
                            Text("in \(Kit.clock(left))").font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(left < 300 ? .orange : .teal)
                            Text(left < 60 ? "Time to wrap up and switch." : left < 300 ? "Start finishing what you're doing." : "Keep going. Keel will warn you.")
                                .font(.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    Button("Cancel", role: .destructive) { cancel() }
                }
            } else {
                Section("Next thing") {
                    TextField("What's next? (leave for school, call, cook)", text: $what)
                    DatePicker("At", selection: $pick, in: Date()..., displayedComponents: [.hourAndMinute])
                    Button("Warn me", systemImage: "bell.badge") { start() }.disabled(what.isEmpty)
                }
            }
        }
        .navigationTitle("Transition timer")
    }

    private func start() {
        at = pick.timeIntervalSince1970
        for m in [10, 5, 1] {
            Kit.notify("kit.transition.\(m)", title: "\(what) in \(m) min", body: m == 1 ? "Wrap up now." : "Start finishing what you're doing.", at: pick.addingTimeInterval(Double(-m * 60)))
        }
        Kit.notify("kit.transition.0", title: "Time for: \(what)", body: "Switch now. You've got this.", at: pick)
        Haptics.success()
    }
    private func cancel() {
        Kit.cancel(["kit.transition.10", "kit.transition.5", "kit.transition.1", "kit.transition.0"])
        at = 0
    }
}

// 4. Time chimes: a gentle ping every so often, so time doesn't disappear.

struct KitChimesView: View {
    @AppStorage("kit.chimes.on") private var on = false
    @AppStorage("kit.chimes.every") private var every = 30
    @AppStorage("kit.chimes.from") private var from = 9
    @AppStorage("kit.chimes.to") private var to = 18

    var body: some View {
        Form {
            Section { KitIntro(icon: "bell.and.waves.left.and.right.fill", color: .purple, text: "Time chimes. A quiet notification every 15, 30 or 60 minutes during the hours you choose, telling you the time. It breaks hyperfocus gently and keeps time from slipping away.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Toggle("Chimes on", isOn: $on)
            Picker("Every", selection: $every) { Text("15 min").tag(15); Text("30 min").tag(30); Text("Hour").tag(60) }
            Stepper("From \(hour(from))", value: $from, in: 0...22)
            Stepper("Until \(hour(to))", value: $to, in: (from + 1)...23)
        }
        .navigationTitle("Time chimes")
        .onChange(of: on) { KitChimes.apply() }
        .onChange(of: every) { KitChimes.apply() }
        .onChange(of: from) { KitChimes.apply() }
        .onChange(of: to) { KitChimes.apply() }
    }
    private func hour(_ h: Int) -> String { h == 0 ? "12 AM" : h < 12 ? "\(h) AM" : h == 12 ? "12 PM" : "\(h - 12) PM" }
}

enum KitChimes {
    /// The times of day (minutes after midnight) a chime goes off.
    static func slots(every: Int, from: Int, to: Int) -> [Int] {
        guard every > 0, to > from else { return [] }
        return Array(stride(from: from * 60 + every, through: to * 60, by: every))
    }

    static func apply() {
        let d = UserDefaults.standard
        Kit.cancel(prefix: "kit.chime.")
        guard d.bool(forKey: "kit.chimes.on") else { return }
        let every = max(15, d.integer(forKey: "kit.chimes.every"))
        let from = d.object(forKey: "kit.chimes.from") as? Int ?? 9, to = d.object(forKey: "kit.chimes.to") as? Int ?? 18
        let center = UNUserNotificationCenter.current()
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            for m in slots(every: every, from: from, to: to).prefix(50) {
                let c = UNMutableNotificationContent()
                var comps = DateComponents(); comps.hour = m / 60; comps.minute = m % 60
                let label = Calendar.current.date(from: comps).map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
                c.title = "It's \(label)"
                c.body = "Still on what you meant to be doing?"
                c.sound = .default
                c.interruptionLevel = .passive
                try? await center.addKeel(UNNotificationRequest(identifier: "kit.chime.\(m)", content: c,
                                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
            }
        }
    }
}

// 5. Phone down: put the phone down for a while; leaving Keel ends the run (locking the screen is fine).

struct KitPhoneDownView: View {
    @AppStorage("kit.phonedown.total") private var totalMinutes = 0
    @AppStorage("kit.phonedown.days") private var daysRaw = ""
    @State private var minutes = 25
    @State private var endsAt: Date?
    @State private var locking = false
    @State private var result: String?
    @Environment(\.scenePhase) private var phase

    var body: some View {
        VStack(spacing: DS.Space.l) {
            KitIntro(icon: "iphone.slash", color: .green, text: "Phone down. Pick a time and put the phone face down. If you leave Keel for another app, the run ends. Locking the screen is fine. Each finished run grows your streak.")
            if let endsAt {
                TimelineView(.periodic(from: .now, by: 1)) { tl in
                    let left = Int(endsAt.timeIntervalSince(tl.date))
                    KitRing(fraction: Double(max(0, left)) / Double(minutes * 60), text: Kit.clock(left), color: .green)
                        .onChange(of: left <= 0) { if left <= 0 { finish(success: true) } }
                }
                Button("Give up", role: .destructive) { finish(success: false) }
            } else {
                Image(systemName: "leaf.fill").font(.system(size: 64)).foregroundStyle(.green.gradient)
                Stepper("\(minutes) minutes", value: $minutes, in: 5...180, step: 5).padding(.horizontal)
                Button { start() } label: { Label("Put it down", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.green).padding(.horizontal)
                if let result { Text(result).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft) }
            }
            HStack {
                KitStat(value: "\(Kit.streak(days))", label: "day streak", color: .green)
                KitStat(value: Kit.minutes(totalMinutes), label: "phone-free so far", color: .green)
            }
            Spacer()
        }
        .padding(DS.Space.m)
        .navigationTitle("Phone down")
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in locking = true }
        .onChange(of: phase) { _, p in
            if p == .active { locking = false }
            if p == .background, endsAt != nil, !locking { finish(success: false) }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var days: Set<String> { Set(daysRaw.split(separator: ",").map(String.init)) }

    private func start() {
        endsAt = Date().addingTimeInterval(Double(minutes * 60)); result = nil
        Kit.notify("kit.phonedown", title: "Phone-down run finished", body: "\(minutes) minutes. Nicely done.", at: endsAt!)
        Haptics.start()
    }
    private func finish(success: Bool) {
        guard endsAt != nil else { return }
        endsAt = nil
        Kit.cancel(["kit.phonedown"])
        if success {
            totalMinutes += minutes
            var d = days; d.insert(Kit.dayKey()); daysRaw = d.sorted().suffix(400).joined(separator: ",")
            result = "Done: \(minutes) phone-free minutes."
            Haptics.success()
        } else {
            result = "That run ended early. Try a shorter one next time."
        }
    }
}

// 6. Several named timers at once (laundry, oven, parking…).

struct KitTimer: Codable, Identifiable, Hashable { var id = UUID(); var name: String; var endsAt: Date; var minutes: Int }

struct KitMultiTimersView: View {
    static let key = "kitlocal.timers"
    @State private var timers: [KitTimer] = []
    @State private var name = ""
    @State private var minutes = 10

    var body: some View {
        List {
            Section { KitIntro(icon: "timer", color: .orange, text: "Timers. Run as many named timers as you like at once: laundry, oven, tea, a call back. Each one notifies you when it's done, even if Keel is closed.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section("New timer") {
                TextField("Name (laundry, oven…)", text: $name)
                Stepper("\(minutes) min", value: $minutes, in: 1...600)
                HStack {
                    ForEach([5, 10, 25, 45], id: \.self) { m in Button("\(m)m") { minutes = m }.buttonStyle(.bordered).controlSize(.small) }
                }
                Button("Start", systemImage: "play.fill") { add() }
            }
            Section("Running") {
                if timers.isEmpty { Text("No timers running.").foregroundStyle(DS.Palette.inkSoft) }
                TimelineView(.periodic(from: .now, by: 1)) { tl in
                    VStack(spacing: 10) {
                        ForEach(timers.sorted { $0.endsAt < $1.endsAt }) { t in
                            let left = Int(t.endsAt.timeIntervalSince(tl.date))
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(t.name).font(.headline)
                                    ProgressView(value: Double(max(0, left)), total: Double(t.minutes * 60)).tint(left <= 0 ? .green : .orange)
                                }
                                Text(left > 0 ? Kit.clock(left) : "Done").font(.title3.weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(left > 0 ? DS.Palette.ink : .green).frame(width: 90, alignment: .trailing)
                                Button { remove(t) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(DS.Palette.inkSoft) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Timers")
        .onAppear { timers = Kit.load(Self.key, as: KitTimer.self).filter { $0.endsAt > Date().addingTimeInterval(-3600) } }
    }

    private func add() {
        let t = KitTimer(name: name.isEmpty ? "Timer" : name, endsAt: Date().addingTimeInterval(Double(minutes * 60)), minutes: minutes)
        timers.append(t); Kit.save(timers, Self.key)
        Kit.notify("kit.timer.\(t.id)", title: "\(t.name) is done", body: "Your \(minutes)-minute timer finished.", at: t.endsAt)
        name = ""; Haptics.start()
    }
    private func remove(_ t: KitTimer) {
        timers.removeAll { $0.id == t.id }; Kit.save(timers, Self.key)
        Kit.cancel(["kit.timer.\(t.id)"])
    }
}

// 7. How much workday is left.

struct KitWorkdayView: View {
    @AppStorage("kit.workday.start") private var start = 9 * 60
    @AppStorage("kit.workday.end") private var end = 17 * 60

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tl in
            let c = Calendar.current.dateComponents([.hour, .minute], from: tl.date)
            let now = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            let total = max(1, end - start)
            let done = min(max(0, now - start), total)
            let left = total - done
            List {
                Section { KitIntro(icon: "sunset.fill", color: .orange, text: "Workday left. See at a glance how much of your working day is gone and what's left, in hours and in 25-minute focus blocks.") }
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(now < start ? "Your day starts at \(label(start))." : left == 0 ? "Your workday is over. Rest counts too." : "\(Kit.minutes(left)) left")
                            .font(.title2.weight(.bold))
                        ProgressView(value: Double(done), total: Double(total)).tint(.orange).scaleEffect(y: 2)
                        if left > 0, now >= start {
                            Text("About \(left / 30) focus blocks of 25 minutes with breaks.").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section("My hours") {
                    Stepper("Start \(label(start))", value: $start, in: 0...(end - 30), step: 15)
                    Stepper("End \(label(end))", value: $end, in: (start + 30)...(24 * 60 - 15), step: 15)
                }
            }
        }
        .navigationTitle("Workday left")
    }
    private func label(_ m: Int) -> String {
        var c = DateComponents(); c.hour = m / 60; c.minute = m % 60
        return Calendar.current.date(from: c)?.formatted(date: .omitted, time: .shortened) ?? ""
    }
}

// 8. Writing sprint: a timer and a word goal.

struct KitSprintView: View {
    @AppStorage("kitlocal.sprint.text") private var text = ""
    @AppStorage("kit.sprint.best") private var best = 0
    @State private var goal = 300
    @State private var minutes = 15
    @State private var endsAt: Date?
    @State private var startWords = 0

    var body: some View {
        VStack(spacing: 12) {
            if let endsAt {
                TimelineView(.periodic(from: .now, by: 1)) { tl in
                    let left = Int(endsAt.timeIntervalSince(tl.date))
                    let written = KitWords.count(text) - startWords
                    HStack {
                        Label(left > 0 ? Kit.clock(left) : "Time!", systemImage: "timer").monospacedDigit()
                        Spacer()
                        Text("\(written) / \(goal) words").monospacedDigit().foregroundStyle(written >= goal ? .green : DS.Palette.ink)
                    }
                    .font(.headline)
                    .onChange(of: left <= 0) { if left <= 0 { stop() } }
                }
                ProgressView(value: Double(min(goal, max(0, KitWords.count(text) - startWords))), total: Double(goal)).tint(.green)
            } else {
                KitIntro(icon: "pencil.line", color: .green, text: "Writing sprint. Set a word goal and a timer, then write without stopping to fix anything. Your text stays here until you clear it; use Share to send it anywhere.")
                HStack {
                    Stepper("\(goal) words", value: $goal, in: 50...5000, step: 50)
                    Stepper("\(minutes) min", value: $minutes, in: 5...120, step: 5)
                }
                .font(.caption)
                Button { startWords = KitWords.count(text); endsAt = Date().addingTimeInterval(Double(minutes * 60)); Haptics.start() } label: {
                    Label("Start sprint", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.green)
                if best > 0 { Text("Best sprint: \(best) words").font(.caption).foregroundStyle(DS.Palette.inkSoft) }
            }
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background { PremiumSurface(radius: 16) }
        }
        .padding(DS.Space.m)
        .navigationTitle("Writing sprint")
        .toolbar {
            ShareLink(item: text)
            Menu { Button("Clear text", role: .destructive) { text = "" } } label: { Image(systemName: "ellipsis.circle") }
        }
    }
    private func stop() {
        guard endsAt != nil else { return }
        endsAt = nil
        best = max(best, KitWords.count(text) - startWords)
        Haptics.success()
    }
}

enum KitWords {
    static func count(_ s: String) -> Int { s.split { $0.isWhitespace || $0.isNewline }.count }
}

// 9. Morning pages: three pages (about 750 words) of free writing, one file per day on this device.

enum KitPages {
    static var folder: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MorningPages", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func url(_ day: String) -> URL { folder.appendingPathComponent(day + ".txt") }
    static func read(_ day: String) -> String { (try? String(contentsOf: url(day), encoding: .utf8)) ?? "" }
    static func write(_ day: String, _ text: String) { try? text.write(to: url(day), atomically: true, encoding: .utf8) }
    static var daysWritten: Set<String> {
        Set(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".txt") }.map { String($0.dropLast(4)) }
            .filter { KitWords.count(read($0)) >= 750 })
    }
}

struct KitMorningPagesView: View {
    @State private var text = ""
    @State private var streak = 0
    @State private var saveTask: Task<Void, Never>?
    private let today = Kit.dayKey()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let words = KitWords.count(text)
            HStack {
                Text("\(words) / 750 words").font(.headline).monospacedDigit().foregroundStyle(words >= 750 ? .green : DS.Palette.ink)
                Spacer()
                Label("\(streak) day streak", systemImage: "flame.fill").font(.caption.weight(.semibold)).foregroundStyle(.orange)
            }
            ProgressView(value: Double(min(750, words)), total: 750).tint(.green)
            if text.isEmpty {
                Text("Morning pages: write three pages, about 750 words, of whatever's in your head, first thing. No editing, no rereading. It clears the noise so the day starts calmer. Pages stay private on this device.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background { PremiumSurface(radius: 16) }
        }
        .padding(DS.Space.m)
        .navigationTitle("Morning pages")
        .onAppear { text = KitPages.read(today); streak = Kit.streak(KitPages.daysWritten) }
        .onChange(of: text) {
            saveTask?.cancel()
            let snapshot = text
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                KitPages.write(today, snapshot)
                if KitWords.count(snapshot) >= 750 { streak = Kit.streak(KitPages.daysWritten) }
            }
        }
        .onDisappear { KitPages.write(today, text) }
    }
}

// 10. Task roulette: can't choose? Let Keel pick one of your open tasks.

struct KitRouletteView: View {
    @Query(filter: #Predicate<TaskItem> { !$0.isDone && !$0.isSomeday && !$0.isWaitingOn }) private var tasks: [TaskItem]
    @State private var maxMinutes = 0          // 0 = any
    @State private var lowEnergy = false
    @State private var picked: TaskItem?
    @State private var spinning = false

    var body: some View {
        List {
            Section { KitIntro(icon: "dice.fill", color: .pink, text: "Task roulette. When choosing is the hard part, let Keel pick one of your open tasks at random. Narrow it to quick or low-energy ones if you like. Notice your gut reaction: relief or dread tells you something too.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section {
                Picker("Time", selection: $maxMinutes) { Text("Any length").tag(0); Text("≤ 15 min").tag(15); Text("≤ 30 min").tag(30); Text("≤ 60 min").tag(60) }
                Toggle("Only low-energy tasks", isOn: $lowEnergy)
                Text("\(pool.count) task\(pool.count == 1 ? "" : "s") to pick from").font(.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            Section {
                Button { spin() } label: { Label(spinning ? "Picking…" : "Pick for me", systemImage: "dice").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.pink).disabled(pool.isEmpty || spinning)
                if let picked {
                    VStack(spacing: 8) {
                        Text(picked.title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                        if let m = picked.estimatedMinutes { Text("About \(m) min").font(.caption).foregroundStyle(DS.Palette.inkSoft) }
                        HStack {
                            Button("Done", systemImage: "checkmark") { TaskActions.setDone(picked, true); self.picked = nil }
                                .buttonStyle(.borderedProminent).tint(DS.Palette.calm)
                            Button("Start focus", systemImage: "scope") { AppRouter.shared.showFocus = true }.buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .transition(.scale.combined(with: .opacity))
                    .id(picked.id)
                }
            }
        }
        .navigationTitle("Task roulette")
    }

    private var pool: [TaskItem] {
        tasks.filter { t in
            (maxMinutes == 0 || (t.estimatedMinutes ?? 30) <= maxMinutes) && (!lowEnergy || t.energy == .low)
        }
    }

    private func spin() {
        spinning = true
        Task {
            for i in 0..<8 {
                withAnimation(.snappy(duration: 0.12)) { picked = pool.randomElement() }
                Haptics.tap()
                try? await Task.sleep(for: .milliseconds(70 + i * 25))
            }
            spinning = false
            Haptics.success()
        }
    }
}

// 47. Tomorrow's first step: leave a breadcrumb for the morning.

struct KitFirstStepView: View {
    @AppStorage("kit.firststep.text") private var step = ""
    @AppStorage("kit.firststep.hour") private var hour = 8
    @AppStorage("kit.firststep.minute") private var minute = 30
    @State private var draft = ""

    var body: some View {
        Form {
            Section { KitIntro(icon: "shoeprints.fill", color: .brown, text: "Tomorrow's first step. Before you stop for the day, write the very first, tiny action for tomorrow (\"open the report and read the last paragraph\"). Keel shows it to you in the morning, so starting is easy.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            if !step.isEmpty {
                Section("Your first step") {
                    Text(step).font(.title3.weight(.semibold))
                    Button("Done, clear it", systemImage: "checkmark") { step = ""; Kit.cancel(["kit.firststep"]); Haptics.success() }
                }
            }
            Section("Set it") {
                TextField("The very first tiny action", text: $draft, axis: .vertical)
                Stepper("Remind me at \(String(format: "%d:%02d", hour, minute))", onIncrement: { bump(15) }, onDecrement: { bump(-15) })
                Button("Save for tomorrow", systemImage: "moon.zzz") { save() }.disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("Tomorrow's first step")
    }

    private func bump(_ d: Int) {
        let t = (hour * 60 + minute + d + 1440) % 1440
        hour = t / 60; minute = t % 60
    }
    private func save() {
        step = draft.trimmingCharacters(in: .whitespaces); draft = ""
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: cal.component(.hour, from: Date()) < hour ? 0 : 1, to: Date()) ?? Date()
        if let at = cal.date(bySettingHour: hour, minute: minute, second: 0, of: tomorrow) {
            Kit.notify("kit.firststep", title: "Your first step today", body: step, at: at)
        }
        Haptics.success()
    }
}

// 48. Meeting timer: an agenda where each item gets its own few minutes.

struct KitAgendaItem: Codable, Identifiable, Hashable { var id = UUID(); var title: String; var minutes: Int }

struct KitMeetingTimerView: View {
    static let key = "kit.meeting.agenda"
    @State private var items: [KitAgendaItem] = []
    @State private var title = ""
    @State private var minutes = 5
    @State private var index: Int?
    @State private var itemStart = Date()
    @State private var meetingStart = Date()

    var body: some View {
        List {
            Section { KitIntro(icon: "person.3.sequence.fill", color: .blue, text: "Meeting timer. List the agenda with a few minutes for each item. During the meeting Keel shows the current item, its time left, and whether you're running over overall, so meetings end on time.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            if let i = index, items.indices.contains(i) {
                Section("Now") {
                    TimelineView(.periodic(from: .now, by: 1)) { tl in
                        let left = items[i].minutes * 60 - Int(tl.date.timeIntervalSince(itemStart))
                        let planned = items.prefix(i + 1).reduce(0) { $0 + $1.minutes } * 60
                        let drift = Int(tl.date.timeIntervalSince(meetingStart)) - planned + max(0, left)
                        VStack(spacing: 6) {
                            Text(items[i].title).font(.title3.weight(.semibold))
                            Text(left >= 0 ? Kit.clock(left) : "+" + Kit.clock(-left)).font(.system(size: 44, weight: .semibold, design: .rounded))
                                .monospacedDigit().foregroundStyle(left >= 0 ? DS.Palette.ink : .orange)
                            Text(drift > 60 ? "Running \(drift / 60) min over" : drift < -60 ? "\(-drift / 60) min ahead" : "On time")
                                .font(.caption.weight(.semibold)).foregroundStyle(drift > 60 ? .orange : DS.Palette.calm)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    Button(i + 1 < items.count ? "Next: \(items[i + 1].title)" : "End meeting", systemImage: "forward.fill") {
                        if i + 1 < items.count { index = i + 1; itemStart = Date(); Haptics.tap() } else { index = nil; Haptics.success() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Section {
                ForEach(items) { a in
                    HStack { Text(a.title); Spacer(); Text("\(a.minutes) min").foregroundStyle(DS.Palette.inkSoft) }
                }
                .onMove { items.move(fromOffsets: $0, toOffset: $1); Kit.save(items, Self.key) }
                .onDelete { items.remove(atOffsets: $0); Kit.save(items, Self.key) }
                HStack {
                    TextField("Agenda item", text: $title)
                    Stepper("\(minutes)m", value: $minutes, in: 1...90).fixedSize()
                    Button("Add") {
                        guard !title.isEmpty else { return }
                        items.append(KitAgendaItem(title: title, minutes: minutes)); Kit.save(items, Self.key); title = ""
                    }
                }
            } header: { Text("Agenda · \(Kit.minutes(items.reduce(0) { $0 + $1.minutes }))") }
            if index == nil, !items.isEmpty {
                Button("Start meeting", systemImage: "play.fill") { index = 0; itemStart = Date(); meetingStart = Date(); Haptics.start() }
            }
        }
        .navigationTitle("Meeting timer")
        .toolbar { EditButton() }
        .onAppear { items = Kit.load(Self.key) }
    }
}

// 49. Decide for me: weigh a few options, or let chance break the tie.

struct KitOption: Codable, Identifiable, Hashable { var id = UUID(); var name: String; var score = 5 }

struct KitDecideView: View {
    @State private var options: [KitOption] = []
    @State private var name = ""
    @State private var verdict: String?

    var body: some View {
        List {
            Section { KitIntro(icon: "arrow.triangle.branch", color: .purple, text: "Decide for me. Add the options and rate how much you want each, 1 to 10. Keel picks the highest, or, if it's close, lets chance decide. The trick: notice whether you feel relieved or disappointed. That's your real answer.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section("Options") {
                ForEach($options) { $o in
                    VStack(alignment: .leading) {
                        Text(o.name)
                        Stepper("How much I want it: \(o.score)", value: $o.score, in: 1...10).font(.caption)
                    }
                }
                .onDelete { options.remove(atOffsets: $0) }
                HStack {
                    TextField("Add an option", text: $name).onSubmit(add)
                    Button("Add", action: add).disabled(name.isEmpty)
                }
            }
            Section {
                Button("Decide", systemImage: "sparkles") { decide() }.disabled(options.count < 2)
                Button("Just flip a coin", systemImage: "circle.lefthalf.filled") {
                    verdict = Bool.random() ? "Heads" : "Tails"; Haptics.tap()
                }
                if let verdict {
                    Text(verdict).font(.title2.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .navigationTitle("Decide for me")
    }
    private func add() {
        guard !name.isEmpty else { return }
        options.append(KitOption(name: name)); name = ""
    }
    private func decide() {
        let top = options.map(\.score).max() ?? 0
        let best = options.filter { $0.score >= top - 1 }
        withAnimation(.spring) {
            verdict = best.count == 1 ? "Go with: \(best[0].name)" : "Too close to call. Chance says: \(best.randomElement()?.name ?? "")"
        }
        Haptics.success()
    }
}

// 50. What fits: you've got some minutes before the next thing; here's what fits in them.

struct KitWhatFitsView: View {
    @Query(filter: #Predicate<TaskItem> { !$0.isDone && !$0.isSomeday }) private var tasks: [TaskItem]
    @State private var minutes = 20.0

    var body: some View {
        let m = Int(minutes)
        let fits = tasks.filter { ($0.estimatedMinutes ?? 0) > 0 && ($0.estimatedMinutes ?? 0) <= m }
            .sorted { ($0.estimatedMinutes ?? 0) > ($1.estimatedMinutes ?? 0) }
        let next = CalendarService.shared.todaysEvents().first { $0.startDate > Date() && !$0.isAllDay }
        List {
            Section { KitIntro(icon: "square.stack.3d.down.forward.fill", color: .mint, text: "What fits. Got a gap before your next thing? Say how long, and Keel lists the tasks that fit, biggest first, so the time doesn't get lost to scrolling. Tasks need a time estimate to show here.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section {
                VStack(alignment: .leading) {
                    Text("I have \(Kit.minutes(m))").font(.headline)
                    Slider(value: $minutes, in: 5...180, step: 5)
                }
                if let next {
                    let gap = Int(next.startDate.timeIntervalSinceNow / 60)
                    Button("Until \(next.title ?? "my next event") (\(Kit.minutes(gap)))") { minutes = Double(min(180, max(5, gap - gap % 5))) }
                        .font(.caption)
                }
            }
            Section("\(fits.count) fit") {
                if fits.isEmpty { Text("Nothing with a time estimate fits. Add estimates to tasks to use this.").foregroundStyle(DS.Palette.inkSoft) }
                ForEach(fits) { t in
                    HStack {
                        Button { TaskActions.setDone(t, true) } label: { Image(systemName: "circle") }.buttonStyle(.plain)
                        Text(t.title)
                        Spacer()
                        Text("\(t.estimatedMinutes ?? 0) min").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
            }
        }
        .navigationTitle("What fits")
    }
}
