import SwiftUI
import UserNotifications

/// Routines are kept on this iPhone (and copied to Apple Watch).
@MainActor
enum RoutineStore {
    static let key = "routines.v1"

    static var all: [Routine] {
        get {
            if let d = UserDefaults.standard.data(forKey: key), let r = try? JSONDecoder().decode([Routine].self, from: d) { return r }
            return defaults
        }
        set {
            if let d = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(d, forKey: key) }
        }
    }

    static let defaults: [Routine] = [
        Routine(name: "Morning", icon: "sunrise.fill", steps: [
            .init(title: "Water and meds", minutes: 2), .init(title: "Shower", minutes: 10),
            .init(title: "Get dressed", minutes: 5), .init(title: "Breakfast", minutes: 10),
            .init(title: "Brush teeth", minutes: 3), .init(title: "Look at today's plan", minutes: 3, optional: true),
        ]),
        Routine(name: "Leaving the house", icon: "door.left.hand.open", steps: [
            .init(title: "Shoes and jacket", minutes: 3), .init(title: "Keys, wallet, phone", minutes: 1),
            .init(title: "Bag packed?", minutes: 2), .init(title: "Lights and stove off", minutes: 1),
        ], finishBy: 8 * 60 + 30),
        Routine(name: "Evening wind-down", icon: "moon.stars.fill", steps: [
            .init(title: "Tidy one surface", minutes: 5, optional: true), .init(title: "Set out tomorrow's clothes", minutes: 3),
            .init(title: "Phone on charger, away from bed", minutes: 1), .init(title: "Brush teeth", minutes: 3),
            .init(title: "Read or stretch", minutes: 15, optional: true),
        ]),
    ]
}

struct RoutinesView: View {
    @State private var routines = RoutineStore.all
    @State private var editing: Routine?
    @State private var playing: Routine?

    var body: some View {
        List {
            Section {
                ForEach(routines) { r in
                    HStack(spacing: DS.Space.m) {
                        Image(systemName: r.icon).font(.title2).foregroundStyle(DS.Palette.accent).frame(width: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).font(DS.Font.headline)
                            Text("\(r.steps.count) steps · \(r.totalMinutes) min" + (r.finishBy.map { " · done by \(Self.clock($0))" } ?? ""))
                                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        Button { playing = r } label: {
                            Image(systemName: "play.fill").padding(10).background(DS.Palette.accent, in: Circle()).foregroundStyle(.white)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Start \(r.name)")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editing = r }
                }
                .onDelete { routines.remove(atOffsets: $0); RoutineStore.all = routines }
                .onMove { routines.move(fromOffsets: $0, toOffset: $1); RoutineStore.all = routines }
            } footer: {
                Text("Each step has its own timer. Set a “done by” time and Keel warns you if you're running late, and suggests what to skip.")
            }
            Section {
                Button { editing = Routine(name: "", icon: "list.bullet", steps: [.init(title: "", minutes: 5)]) } label: {
                    Label("New Routine", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Routines")
        .toolbar { EditButton() }
        .sheet(item: $editing) { r in
            RoutineEditor(routine: r) { saved in
                if let i = routines.firstIndex(where: { $0.id == saved.id }) { routines[i] = saved } else { routines.append(saved) }
                RoutineStore.all = routines
            }
        }
        .fullScreenCover(item: $playing) { r in RoutinePlayer(routine: r) }
    }

    static func clock(_ minutes: Int) -> String {
        let d = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return d.formatted(date: .omitted, time: .shortened)
    }
}

struct RoutineEditor: View {
    @State var routine: Routine
    let save: (Routine) -> Void
    @Environment(\.dismiss) private var dismiss
    private let icons = ["sunrise.fill", "moon.stars.fill", "door.left.hand.open", "figure.walk", "fork.knife", "bed.double.fill",
                         "backpack.fill", "house.fill", "briefcase.fill", "dumbbell.fill", "list.bullet", "sparkles"]

    private var finishOn: Binding<Bool> {
        Binding(get: { routine.finishBy != nil }, set: { routine.finishBy = $0 ? 8 * 60 + 30 : nil })
    }
    private var finishTime: Binding<Date> {
        Binding(get: {
            let m = routine.finishBy ?? 510
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            routine.finishBy = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Morning", text: $routine.name)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(icons, id: \.self) { i in
                                Button { routine.icon = i } label: {
                                    Image(systemName: i).frame(width: 36, height: 36)
                                        .background(routine.icon == i ? DS.Palette.accent.opacity(0.2) : .clear, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(i)
                            }
                        }
                    }
                }
                Section {
                    Toggle("Finish By a Set Time", isOn: finishOn)
                    if routine.finishBy != nil {
                        DatePicker("Done by", selection: finishTime, displayedComponents: .hourAndMinute)
                    }
                } footer: { Text("Keel warns you while it's running if you're behind.") }
                Section {
                    ForEach($routine.steps) { $step in
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Step", text: $step.title)
                            HStack {
                                Stepper("\(step.minutes) min", value: $step.minutes, in: 1...120)
                                Toggle("Skippable", isOn: $step.optional).labelsHidden()
                                    .accessibilityLabel("Skippable when late")
                                Text("Skippable").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                            }
                        }
                    }
                    .onDelete { routine.steps.remove(atOffsets: $0) }
                    .onMove { routine.steps.move(fromOffsets: $0, toOffset: $1) }
                    Button { routine.steps.append(.init(title: "", minutes: 5)) } label: { Label("Add Step", systemImage: "plus") }
                } header: { Text("Steps · \(routine.totalMinutes) min total") }
            }
            .navigationTitle(routine.name.isEmpty ? "New Routine" : routine.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        routine.steps.removeAll { $0.title.trimmingCharacters(in: .whitespaces).isEmpty }
                        save(routine); dismiss()
                    }
                    .disabled(routine.name.isEmpty || routine.steps.allSatisfy { $0.title.isEmpty })
                }
            }
        }
    }
}

/// Plays a routine one step at a time: a big timer for this step, a bar for the whole routine,
/// and a gentle "running late" warning with what to skip.
struct RoutinePlayer: View {
    let routine: Routine
    @Environment(\.dismiss) private var dismiss
    @State private var steps: [Routine.Step] = []
    @State private var index = 0
    @State private var stepStarted = Date()
    @State private var extra = 0                // minutes added to this step
    @State private var now = Date()
    @State private var buzzed = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var current: Routine.Step? { index < steps.count ? steps[index] : nil }
    private var stepLength: Double { Double(((current?.minutes ?? 0) + extra) * 60) }
    private var left: Double { max(0, stepLength - now.timeIntervalSince(stepStarted)) }
    private var live: Routine { var r = routine; r.steps = steps; if index < r.steps.count { r.steps[index].minutes += extra }; return r }
    private var slack: Int? { live.slack(at: index, stepStarted: stepStarted, now: now) }

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.l) {
                HStack(spacing: 4) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { i, s in
                        Capsule().fill(i < index ? DS.Palette.calm : i == index ? DS.Palette.accent : DS.Palette.inkSoft.opacity(0.2))
                            .frame(maxWidth: .infinity).frame(height: 6)
                            .layoutPriority(Double(s.minutes))
                    }
                }
                .accessibilityElement().accessibilityLabel("Step \(min(index + 1, steps.count)) of \(steps.count)")

                if let late = slack, late > 0, current != nil {
                    lateBanner(late)
                } else if let spare = slack, current != nil {
                    Label("On track · \(-spare) min to spare", systemImage: "checkmark.circle").font(DS.Font.caption).foregroundStyle(DS.Palette.calm)
                }

                Spacer()
                if let step = current {
                    Text("Step \(index + 1) of \(steps.count)").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    Text(step.title).font(DS.Font.hero).multilineTextAlignment(.center).minimumScaleFactor(0.6)
                    ZStack {
                        TimeRing(progress: stepLength > 0 ? left / stepLength : 0, color: left == 0 ? DS.Palette.warmth : DS.Palette.accent)
                            .frame(width: 230, height: 230)
                        VStack {
                            Text(Duration.seconds(left).formatted(.time(pattern: .minuteSecond))).font(DS.Font.timer)
                            if left == 0 { Text("Time's up, finish when you can").font(DS.Font.caption).foregroundStyle(DS.Palette.warmth) }
                        }
                    }
                    if index + 1 < steps.count {
                        Text("Next: \(steps[index + 1].title)").font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
                    }
                    Spacer()
                    Button { next() } label: {
                        Label(index + 1 == steps.count ? "Finish" : "Done, next step", systemImage: "checkmark")
                            .font(DS.Font.headline).frame(maxWidth: .infinity).padding(.vertical, DS.Space.m)
                            .background(DS.Palette.accent, in: Capsule()).foregroundStyle(.white)
                    }
                    HStack(spacing: DS.Space.l) {
                        Button("+1 min") { extra += 1; buzzed = false; scheduleStepEnd() }
                        Button("Skip") { next(skipped: true) }
                    }
                    .buttonStyle(.bordered)
                } else {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 72)).foregroundStyle(DS.Palette.calm)
                        .symbolEffect(.bounce, value: index)
                    Text("\(routine.name) done").font(DS.Font.hero)
                    if let f = routine.finishBy {
                        Text(Date() <= (Calendar.current.date(bySettingHour: f / 60, minute: f % 60, second: 0, of: Date()) ?? Date())
                             ? "And on time. Nicely done." : "You got through it. That's what counts.")
                            .foregroundStyle(DS.Palette.inkSoft)
                    }
                    Spacer()
                    Button("Close") { dismiss() }.buttonStyle(.borderedProminent).tint(DS.Palette.calm)
                }
            }
            .padding()
            .navigationTitle(routine.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Stop") { cancelStepEnd(); dismiss() } } }
        }
        .onAppear {
            steps = routine.steps
            stepStarted = Date()
            scheduleStepEnd()
            UIApplication.shared.isIdleTimerDisabled = true      // keep the screen on while you follow along
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false; cancelStepEnd() }
        .onReceive(tick) { t in
            now = t
            if current != nil, left == 0, !buzzed { buzzed = true; Haptics.milestone() }
        }
    }

    private func lateBanner(_ late: Int) -> some View {
        let skippable = steps.dropFirst(index + 1).filter(\.optional)
        return VStack(alignment: .leading, spacing: 6) {
            Label("Running \(late) min late", systemImage: "exclamationmark.triangle.fill").font(DS.Font.headline).foregroundStyle(.white)
            if let s = skippable.first {
                Button { steps.removeAll { $0.id == s.id }; Haptics.tap() } label: {
                    Text("Skip “\(s.title)” to save \(s.minutes) min").font(DS.Font.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5).background(.white.opacity(0.25), in: Capsule())
                }
                .foregroundStyle(.white)
            } else {
                Text("Keep it quick, nothing left to skip.").font(DS.Font.caption).foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(DS.Space.m).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.85), in: .rect(cornerRadius: DS.Radius.card))
    }

    private func next(skipped: Bool = false) {
        skipped ? Haptics.tap() : Haptics.success()
        withAnimation(DS.spring) { index += 1 }
        stepStarted = Date(); extra = 0; buzzed = false
        if current == nil { cancelStepEnd() } else { scheduleStepEnd() }
    }

    /// If you leave Keel, a notification says when this step's time is up.
    private func scheduleStepEnd() {
        cancelStepEnd()
        guard let step = current, left > 1 else { return }
        let c = UNMutableNotificationContent()
        c.title = "\(routine.name): time for the next step"
        c.body = index + 1 < steps.count ? "“\(step.title)” is up. Next: \(steps[index + 1].title)." : "Last step: “\(step.title)” is up."
        c.sound = .default
        c.interruptionLevel = .timeSensitive
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "routine.step", content: c,
                                                                     trigger: UNTimeIntervalNotificationTrigger(timeInterval: left, repeats: false)))
    }

    private func cancelStepEnd() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["routine.step"])
    }
}
