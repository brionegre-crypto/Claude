import SwiftUI
import SwiftData
import Charts
import HealthKit

// MARK: - Build my workout: today's strength session, from what's fresh, how recovered you are and your cycle

enum TrainingGoal: String, CaseIterable, Identifiable {
    case strength, muscle, general
    var id: String { rawValue }
    var label: String { switch self { case .strength: "Get stronger"; case .muscle: "Build muscle"; case .general: "Stay fit" } }
    var reps: Int { switch self { case .strength: 5; case .muscle: 10; case .general: 12 } }
}

enum TrainingKit: String, CaseIterable, Identifiable {
    case gym, dumbbells, bodyweight
    var id: String { rawValue }
    var label: String { switch self { case .gym: "Full gym"; case .dumbbells: "Dumbbells at home"; case .bodyweight: "No equipment" } }
    var allows: Set<String> {
        switch self {
        case .gym: ["Barbell", "Dumbbell", "Cable", "Machine", "Bodyweight", "Kettlebell", "Trap bar", "Band", "Other", "Plate"]
        case .dumbbells: ["Dumbbell", "Bodyweight", "Band", "Kettlebell"]
        case .bodyweight: ["Bodyweight", "Band"]
        }
    }
}

/// Where you are in your cycle and what that tends to mean for training.
enum CyclePhase {
    static func advice(day: Int, length: Int) -> String? {
        guard length >= 20 else { return nil }
        if day <= 5 { return "Cycle day \(day): period days. Lighter sessions are fine; go by how you feel." }
        if day <= length / 2 - 2 { return "Cycle day \(day): follicular phase. Often the best time for heavy lifts and personal records." }
        if day <= length / 2 + 2 { return "Cycle day \(day): around ovulation. Strength is usually high; warm up well." }
        return "Cycle day \(day): luteal phase. Heart rate runs higher and effort feels harder; moderate weights and more rest help."
    }
}

@MainActor
enum WorkoutBuilder {
    static let goalKey = "strength.goal", kitKey = "strength.kit"

    struct Plan { let name: String; let session: StrengthSession; let why: [String] }

    /// Picks the freshest, least-trained muscles, then compound moves first, with sets scaled to recovery.
    static func build(tide: Int?, goal: TrainingGoal, kit: TrainingKit, fatigue: [Muscle: Double], weekSets: [Muscle: Double], cycle: String? = nil) -> Plan {
        var why: [String] = []
        let t = tide ?? 60
        if t < 34 {
            let s = StrengthSession(name: "Recovery mobility", exercises: [("cat-cow", 60), ("worlds-greatest-stretch", 45), ("glute-bridge", 12), ("dead-bug", 12), ("90/90-hip-switch", 45), ("childs-pose", 60)].map {
                LoggedExercise(exerciseId: $0.0, sets: [LiftSet(reps: $0.1, weight: 0), LiftSet(reps: $0.1, weight: 0)])
            })
            return Plan(name: "Recovery mobility", session: s, why: ["Your Tide is low (\(t)%), so today is light movement to help you recover, not a hard session."])
        }
        let sets = t >= 67 ? 4 : 3
        why.append(t >= 67 ? "High tide (\(t)%): a full session, \(sets) sets each." : "Steady tide (\(t)%): a normal session, \(sets) sets each.")
        // Muscles that are fresh enough, most in need of work first.
        let ready = Muscle.allCases.filter { (fatigue[$0] ?? 0) < 0.35 }
        let ranked = ready.sorted { (weekSets[$0] ?? 0) < (weekSets[$1] ?? 0) }
        let tired = Muscle.allCases.filter { (fatigue[$0] ?? 0) >= 0.35 }
        if !tired.isEmpty { why.append("Resting \(tired.prefix(3).map { $0.name.lowercased() }.joined(separator: ", ")): still recovering.") }
        let targets = Array(ranked.prefix(4))
        if !targets.isEmpty { why.append("Focus: \(targets.map { $0.name.lowercased() }.joined(separator: ", ")), the fresh muscles with the fewest sets this week.") }
        if let cycle { why.append(cycle) }
        var picked: [Exercise] = []
        let pool = ExerciseLibrary.all.filter { kit.allows.contains($0.equipment) && $0.isLoad }
        for m in targets {
            // Prefer moves that hit this muscle first and don't load a tired one.
            let options = pool.filter { $0.primary.first == m && !$0.primary.contains(where: { tired.contains($0) }) && !picked.contains($0) }
                .sorted { ($0.primary.count + $0.secondary.count) > ($1.primary.count + $1.secondary.count) }
            if let best = options.first(where: { StrengthStore.last($0.id) != nil }) ?? options.first { picked.append(best) }
            if picked.count >= 5 { break }
        }
        if picked.count < 3, let core = pool.first(where: { $0.id == "plank" }), !picked.contains(core) { picked.append(core) }
        let session = StrengthSession(name: "Today's workout", exercises: picked.map { ex in
            let sug = StrengthStore.suggestion(ex.id, targetReps: goal.reps)
            let reps = ex.id == "plank" || ex.id == "side-plank" ? 30 : (sug?.reps ?? goal.reps)
            let w = (t < 50 ? 0.9 : 1.0) * (sug?.weight ?? 0)
            return LoggedExercise(exerciseId: ex.id, sets: (0..<sets).map { _ in LiftSet(reps: reps, weight: (w / StrengthStore.increment).rounded() * StrengthStore.increment) })
        })
        if t < 50 { why.append("Weights are about 10% lighter than last time to match your recovery.") }
        return Plan(name: "Today's workout", session: session, why: why)
    }
}

struct BuildWorkoutCard: View {
    let tide: Int?
    var extras: HealthExtras? = nil
    @AppStorage(WorkoutBuilder.goalKey) private var goalRaw = TrainingGoal.general.rawValue
    @AppStorage(WorkoutBuilder.kitKey) private var kitRaw = TrainingKit.gym.rawValue
    @State private var active: StrengthSession?

    var body: some View {
        let cycle = extras.flatMap { BodyMath.cycle(periodDays: $0.periodDays) }.flatMap { CyclePhase.advice(day: $0.day, length: $0.length) }
        let plan = WorkoutBuilder.build(tide: tide, goal: TrainingGoal(rawValue: goalRaw) ?? .general, kit: TrainingKit(rawValue: kitRaw) ?? .gym,
                                        fatigue: StrengthStore.fatigue(), weekSets: StrengthStore.setsPerMuscle(), cycle: cycle)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Build my workout", systemImage: "wand.and.stars").font(DS.Font.headline).foregroundStyle(BodyStyle.swell)
                Spacer()
                Menu {
                    Picker("Goal", selection: $goalRaw) { ForEach(TrainingGoal.allCases) { Text($0.label).tag($0.rawValue) } }
                    Picker("Equipment", selection: $kitRaw) { ForEach(TrainingKit.allCases) { Text($0.label).tag($0.rawValue) } }
                } label: { Image(systemName: "slider.horizontal.3") }
            }
            Text(plan.session.exercises.compactMap { ExerciseLibrary.exercise($0.exerciseId)?.name }.joined(separator: " · "))
                .font(.callout.weight(.semibold))
            ForEach(plan.why, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(DS.Palette.inkSoft) }
            Button { active = plan.session; Haptics.start() } label: { Label("Start it", systemImage: "play.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).tint(BodyStyle.swell)
        }
        .bodyCard()
        .fullScreenCover(item: $active) { s in
            NavigationStack {
                ActiveWorkoutView(session: s) { finished in
                    if let finished, finished.setCount > 0 { StrengthStore.sessions = StrengthStore.sessions + [finished]; StrengthHealth.save(finished) }
                    active = nil
                }
            }
        }
    }
}

// MARK: - Coach notes: plateaus and when to take an easier week

enum StrengthCoach {
    /// Lifts where your best hasn't improved in your last 3 sessions, compared with the sessions before.
    @MainActor static func plateaus(in list: [StrengthSession]? = nil) -> [String] {
        let sessions = (list ?? StrengthStore.sessions).sorted { $0.start < $1.start }
        var byExercise: [String: [Double]] = [:]
        for s in sessions where s.start > Date().addingTimeInterval(-56 * 86_400) {
            for e in s.exercises {
                if let best = e.sets.filter({ $0.done && !$0.warmup }).map(StrengthStore.e1RM).max() { byExercise[e.exerciseId, default: []].append(best) }
            }
        }
        return byExercise.compactMap { id, bests in
            guard bests.count >= 5, let name = ExerciseLibrary.exercise(id)?.name else { return nil }
            let recent = bests.suffix(3).max() ?? 0, before = bests.dropLast(3).max() ?? 0
            return recent <= before ? "\(name) has stalled for 3 sessions. Try a different rep range for 2–3 weeks, or swap in a similar move." : nil
        }
    }

    /// An easier week when load is spiking or recovery has sagged for days.
    @MainActor static func deload(days: [BodyDay], sessions: [StrengthSession]) -> String? {
        if let r = CardioLoad.ratio(days, strength: sessions), r > 1.5 {
            return "Your training load jumped (\(String(format: "%.1f", r))× your usual). Take an easier week: same exercises, about half the sets."
        }
        let tides = days.suffix(5).compactMap(\.tide)
        if tides.count == 5, tides.allSatisfy({ $0 < 45 }), sessions.filter({ $0.start > Date().addingTimeInterval(-7 * 86_400) }).count >= 3 {
            return "Recovery has been low for 5 days while you kept training. A lighter week now will make the next one stronger."
        }
        return nil
    }
}

// MARK: - Plates and warm-ups

enum PlateMath {
    static func bar(_ unit: String) -> Double { unit == "kg" ? 20 : 45 }
    static func plates(_ unit: String) -> [Double] { unit == "kg" ? [25, 20, 15, 10, 5, 2.5, 1.25] : [45, 35, 25, 10, 5, 2.5] }

    /// Plates for one side of the bar, biggest first. Nil if it can't be made exactly.
    static func perSide(total: Double, unit: String) -> [Double]? {
        var left = (total - bar(unit)) / 2
        guard left >= 0 else { return nil }
        var out: [Double] = []
        for p in plates(unit) {
            while left >= p - 0.001 { out.append(p); left -= p }
        }
        return left < 0.01 ? out : nil
    }

    /// 3 warm-up sets building to the working weight: 40% × 10, 60% × 5, 80% × 3 (never below the bar).
    static func warmups(to working: Double, unit: String, step: Double) -> [LiftSet] {
        guard working > bar(unit) else { return [] }
        return [(0.4, 10), (0.6, 5), (0.8, 3)].map { pct, reps in
            let w = max(bar(unit), (working * pct / step).rounded() * step)
            return LiftSet(reps: reps, weight: w, warmup: true)
        }
    }
}

struct PlateCalculatorView: View {
    @State var weight: Double
    let unit: String
    var body: some View {
        Form {
            Section {
                Stepper(value: $weight, in: 0...600, step: unit == "kg" ? 2.5 : 5) { Text("\(weight.formatted()) \(unit)").font(.title3.weight(.semibold)).monospacedDigit() }
            }
            Section("Each side of a \(PlateMath.bar(unit).formatted()) \(unit) bar") {
                if let p = PlateMath.perSide(total: weight, unit: unit) {
                    if p.isEmpty { Text("Just the bar.") }
                    HStack(spacing: 4) {
                        ForEach(Array(p.enumerated()), id: \.offset) { _, plate in
                            RoundedRectangle(cornerRadius: 3).fill(BodyStyle.swell.opacity(0.3 + plate / 60))
                                .frame(width: 14, height: 30 + plate * 2.2)
                        }
                    }
                    Text(p.map { $0.formatted() }.joined(separator: " + ")).monospacedDigit()
                } else {
                    Text("Can't be made exactly with standard plates.").foregroundStyle(DS.Palette.inkSoft)
                }
            }
            Section("Warm-up") {
                ForEach(PlateMath.warmups(to: weight, unit: unit, step: unit == "kg" ? 2.5 : 5)) { s in
                    Text("\(s.weight.formatted()) \(unit) × \(s.reps)").monospacedDigit()
                }
            }
        }
        .navigationTitle("Plates & warm-up")
    }
}

// MARK: - Save strength sessions to Apple Health

@MainActor
enum StrengthHealth {
    static let key = "strength.saveToHealth"
    static var on: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    static func save(_ s: StrengthSession) {
        guard on, BodyHealth.available, !KeelRuntime.isTesting else { return }
        let start = s.start, end = s.end ?? Date()
        Task {
            let store = BodyHealth.store
            try? await store.requestAuthorization(toShare: [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)], read: [])
            let config = HKWorkoutConfiguration()
            config.activityType = .traditionalStrengthTraining
            let b = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
            do {
                try await b.beginCollection(at: start)
                // About 5 kcal a minute for weight training, as a conservative estimate.
                let kcal = HKQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                                            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: max(1, end.timeIntervalSince(start) / 60) * 5),
                                            start: start, end: end)
                try await b.addSamples([kcal])
                try await b.endCollection(at: end)
                _ = try await b.finishWorkout()
            } catch {
                b.discardWorkout()
            }
        }
    }
}

// MARK: - Early warning: signs your body may be fighting something

@MainActor
enum BodyAlerts {
    /// Two or more of: resting heart rate up 5+, HRV down 20%+, breathing up 1+/min, wrist temperature up 0.5 °C+, versus your 30-day normal.
    static func illnessSignals(_ days: [BodyDay]) -> [String] {
        guard let t = days.last, Calendar.current.isDateInToday(t.day) else { return [] }
        let base = days.dropLast().suffix(30)
        func avg(_ v: [Double]) -> Double? { v.count >= 7 ? v.reduce(0, +) / Double(v.count) : nil }
        var out: [String] = []
        if let r = t.rhr, let b = avg(base.compactMap(\.rhr)), r - b >= 5 { out.append("resting heart rate is \(Int(r - b)) above normal") }
        if let h = t.hrv, let b = avg(base.compactMap(\.hrv)), h < b * 0.8 { out.append("HRV is \(Int((1 - h / b) * 100))% below normal") }
        if let r = t.resp, let b = avg(base.compactMap(\.resp)), r - b >= 1 { out.append(String(format: "breathing rate is up %.1f", r - b)) }
        if let tmp = t.temp, tmp >= 0.5 { out.append(String(format: "wrist temperature is up %.1f °C", tmp)) }
        return out.count >= 2 ? out : []
    }

    static func checkAndNotify(_ days: [BodyDay]) {
        let signals = illnessSignals(days)
        let key = "body.alerted.illness"
        guard !signals.isEmpty, UserDefaults.standard.string(forKey: key) != BodyMath.dayKey(Date()) else { return }
        UserDefaults.standard.set(BodyMath.dayKey(Date()), forKey: key)
        Kit.notify("body.illness", title: "Your body may be fighting something",
                   body: signals.joined(separator: ", ").prefix(1).uppercased() + signals.joined(separator: ", ").dropFirst() + ". Take it easy today and drink plenty.",
                   at: Date().addingTimeInterval(5))
    }
}

struct IllnessWarningCard: View {
    let days: [BodyDay]
    var body: some View {
        let s = BodyAlerts.illnessSignals(days)
        if !s.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Your body may be fighting something", systemImage: "thermometer.medium").font(DS.Font.headline).foregroundStyle(.orange)
                Text("Overnight, " + s.joined(separator: ", ") + ". This often shows up a day or two before you feel ill, or after a hard day, alcohol or poor sleep.")
                    .font(DS.Font.caption)
                Text("Go easy today, drink plenty, and get to bed early. If you feel unwell, rest.").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
            }
            .bodyCard()
        }
    }
}

// MARK: - What drives your recovery (found automatically, no logging needed)

struct RecoveryDriver: Identifiable, Hashable { let id: String; let label: String; let delta: Int; let withDays: Int }

@MainActor
enum RecoveryDrivers {
    /// For each automatic signal on a day, the average next-morning Tide with it versus without it.
    static func compute(days: [BodyDay], food: [FoodEntry], strength: [StrengthSession], drinks: [Drink]) -> [RecoveryDriver] {
        let cal = Calendar.current
        guard days.count >= 10 else { return [] }
        let usualBed: Double = {
            let beds = days.compactMap(\.bedtime).map { Double(cal.component(.hour, from: $0) < 12 ? cal.component(.hour, from: $0) + 24 : cal.component(.hour, from: $0)) }
            return beds.isEmpty ? 23 : beds.reduce(0, +) / Double(beds.count)
        }()
        let tests: [(String, String, (BodyDay, BodyDay) -> Bool?)] = [
            ("lateWorkout", "Working out after 8 PM", { d, _ in d.workouts.contains { cal.component(.hour, from: $0.start) >= 20 } }),
            ("hardDay", "A hard day (Swell 60+)", { d, _ in d.swell >= 60 }),
            ("strength", "A strength session", { d, _ in strength.contains { cal.isDate($0.start, inSameDayAs: d.day) } }),
            ("lateMeal", "Eating after 9 PM", { d, _ in
                let todays = food.filter { cal.isDate($0.date, inSameDayAs: d.day) }
                return todays.isEmpty ? nil : todays.contains { cal.component(.hour, from: $0.date) >= 21 } }),
            ("lateCaffeine", "Caffeine after 2 PM", { d, _ in
                let todays = drinks.filter { cal.isDate($0.at, inSameDayAs: d.day) }
                return todays.isEmpty ? nil : todays.contains { $0.caffeine > 0 && cal.component(.hour, from: $0.at) >= 14 } }),
            ("stressful", "A stressful day (3+ high-stress hours)", { d, _ in d.stress.isEmpty ? nil : d.stress.compactMap { $0 }.filter { $0 == 2 }.count >= 3 }),
            ("lateBed", "Going to bed an hour later than usual", { _, n in
                guard let b = n.bedtime else { return nil }
                let h = Double(cal.component(.hour, from: b) < 12 ? cal.component(.hour, from: b) + 24 : cal.component(.hour, from: b))
                return h >= usualBed + 1 }),
            ("shortSleep", "Sleeping under 6½ hours", { _, n in n.hasSleep ? n.asleep < 390 : nil }),
            ("restDay", "A rest day (no workouts)", { d, _ in d.workouts.isEmpty && !strength.contains { cal.isDate($0.start, inSameDayAs: d.day) } }),
        ]
        var out: [RecoveryDriver] = []
        let pairs = zip(days.dropLast(), days.dropFirst()).filter { cal.dateComponents([.day], from: $0.0.day, to: $0.1.day).day == 1 && $0.1.tide != nil }
        for (id, label, test) in tests {
            var with: [Int] = [], without: [Int] = []
            for (d, next) in pairs {
                guard let tide = next.tide, let hit = test(d, next) else { continue }
                if hit { with.append(tide) } else { without.append(tide) }
            }
            guard with.count >= 3, without.count >= 3 else { continue }
            let delta = Double(with.reduce(0, +)) / Double(with.count) - Double(without.reduce(0, +)) / Double(without.count)
            if abs(delta) >= 3 { out.append(RecoveryDriver(id: id, label: label, delta: Int(delta.rounded()), withDays: with.count)) }
        }
        return out.sorted { abs($0.delta) > abs($1.delta) }
    }
}

struct RecoveryDriversCard: View {
    let days: [BodyDay]
    @Query(RecoveryDriversCard.recentFood) private var food: [FoodEntry]
    static var recentFood: FetchDescriptor<FoodEntry> {
        let since = Date().addingTimeInterval(-90 * 86_400)
        return FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.date >= since })
    }

    var body: some View {
        let drivers = RecoveryDrivers.compute(days: days, food: food, strength: StrengthStore.sessions, drinks: Drinks.all)
        VStack(alignment: .leading, spacing: 8) {
            Label("What drives your recovery", systemImage: "point.3.filled.connected.trianglepath.dotted").font(DS.Font.headline).foregroundStyle(BodyStyle.tide)
            if drivers.isEmpty {
                Text("Keel compares your next-morning Tide after different kinds of days: late workouts, caffeine after 2 PM, late meals, stressful days, late nights. It shows here once it has seen each a few times. Nothing to log.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            } else {
                ForEach(drivers.prefix(6)) { d in
                    HStack {
                        Text(d.label).font(.callout)
                        Spacer()
                        Text("\(d.delta > 0 ? "+" : "")\(d.delta)% Tide").font(.callout.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(d.delta > 0 ? DS.Palette.calm : .orange)
                    }
                }
                Text("Next-morning Tide on days with it, compared with days without. Found automatically from your data.").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
            }
        }
        .bodyCard()
    }
}

// MARK: - Body goals with a projected date

struct BodyGoal: Codable, Identifiable, Hashable {
    var id = UUID()
    var metric: String          // BodyMetric raw value
    var target: Double
    var created = Date()
}

@MainActor
enum BodyGoals {
    static let key = "body.goals"
    static var all: [BodyGoal] { get { LocalLog.load(key) } set { LocalLog.save(newValue, key) } }

    /// Least-squares trend per day over the last 30 days, and when the goal would be reached at that rate.
    static func projection(_ g: BodyGoal, days: [BodyDay], now: Date = Date()) -> (current: Double?, perWeek: Double?, eta: Date?) {
        guard let m = BodyMetric(rawValue: g.metric) else { return (nil, nil, nil) }
        let pts = days.suffix(30).compactMap { d in m.value(d).map { (x: d.day.timeIntervalSince(now) / 86_400, y: $0) } }
        guard let current = pts.last?.y else { return (nil, nil, nil) }
        guard pts.count >= 7 else { return (current, nil, nil) }
        let n = Double(pts.count)
        let mx = pts.map(\.x).reduce(0, +) / n, my = pts.map(\.y).reduce(0, +) / n
        let sxx = pts.reduce(0) { $0 + ($1.x - mx) * ($1.x - mx) }
        guard sxx > 0 else { return (current, nil, nil) }
        let slope = pts.reduce(0) { $0 + ($1.x - mx) * ($1.y - my) } / sxx
        let gap = g.target - current
        guard abs(gap) > 0.0001 else { return (current, slope * 7, now) }
        guard slope != 0, (gap > 0) == (slope > 0) else { return (current, slope * 7, nil) }
        let daysToGo = gap / slope
        return (current, slope * 7, daysToGo < 730 ? now.addingTimeInterval(daysToGo * 86_400) : nil)
    }
}

struct BodyGoalsCard: View {
    let days: [BodyDay]
    @State private var goals: [BodyGoal] = []
    @State private var adding = false
    @State private var metric = BodyMetric.vo2
    @State private var target = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Goals", systemImage: "target").font(DS.Font.headline).foregroundStyle(.indigo)
                Spacer()
                Button { adding = true } label: { Image(systemName: "plus.circle.fill") }.accessibilityLabel("Add goal")
            }
            if goals.isEmpty {
                Text("Set a target, like VO₂ max 45, resting heart rate 55 or 7½ hours of sleep, and Keel shows your trend and when you'll get there at this rate.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            ForEach(goals) { g in
                if let m = BodyMetric(rawValue: g.metric) {
                    let p = BodyGoals.projection(g, days: days)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(m.name).font(.callout.weight(.semibold))
                            Spacer()
                            Text("\(p.current.map(m.format) ?? "–") → \(m.format(g.target))").font(.caption).monospacedDigit()
                        }
                        Text(p.eta.map { "At this rate: around \($0.formatted(.dateTime.month(.abbreviated).day().year()))" }
                             ?? (p.perWeek == nil ? "Needs a week of data to see your trend." : "Not heading that way yet. Small, steady changes add up."))
                            .font(.caption2).foregroundStyle(p.eta == nil ? DS.Palette.inkSoft : DS.Palette.calm)
                    }
                    .contextMenu { Button("Remove goal", role: .destructive) { goals.removeAll { $0.id == g.id }; BodyGoals.all = goals } }
                }
            }
        }
        .bodyCard()
        .onAppear { goals = BodyGoals.all }
        .sheet(isPresented: $adding) {
            NavigationStack {
                Form {
                    Picker("Measure", selection: $metric) { ForEach(BodyMetric.allCases) { Text($0.name).tag($0) } }
                    TextField("Target (e.g. 45)", text: $target).keyboardType(.decimalPad)
                    if metric == .sleep { Text("Sleep is in hours, e.g. 7.5").font(.caption) }
                }
                .navigationTitle("New goal")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { adding = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            if let v = Double(target.replacingOccurrences(of: ",", with: ".")) {
                                goals.append(BodyGoal(metric: metric.rawValue, target: v)); BodyGoals.all = goals
                            }
                            target = ""; adding = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

// MARK: - Biological age: what-if and pace of aging

extension BioAge {
    /// Years of biological age per calendar year, from your weekly history (needs 8+ weeks).
    static func pace(_ h: [Snapshot] = history) -> Double? {
        guard h.count >= 8, let first = h.first, let last = h.last, last.age - first.age > 0.1 else { return nil }
        return (last.bioAge - first.bioAge) / (last.age - first.age) + 1
    }
}

struct BioAgeWhatIf: View {
    let base: BioAgeInputs
    @State private var vo2 = 0.0
    @State private var rhr = 0.0
    @State private var sleep = 0.0
    @State private var steps = 0.0

    var body: some View {
        var x = base
        if let v = x.vo2 { x.vo2 = v + vo2 }
        if let r = x.rhr { x.rhr = r + rhr }
        if let s = x.sleepHours { x.sleepHours = s + sleep }
        if let s = x.steps { x.steps = s + steps }
        let now = BioAge.estimate(base).bioAge
        let then = BioAge.estimate(x).bioAge
        return Section {
            if base.vo2 != nil { slider("Cardio fitness", value: $vo2, range: 0...10, step: 0.5, unit: "VO₂ max") }
            if base.rhr != nil { slider("Resting heart rate", value: $rhr, range: -10...0, step: 1, unit: "bpm") }
            if base.sleepHours != nil { slider("Sleep", value: $sleep, range: -1...2, step: 0.25, unit: "h") }
            if base.steps != nil { slider("Daily steps", value: $steps, range: 0...6000, step: 500, unit: "steps") }
            HStack {
                Text("Your biological age would be")
                Spacer()
                Text(String(format: "%.1f", then)).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(.purple)
                Text(String(format: "(%+.1f)", then - now)).font(.caption).monospacedDigit().foregroundStyle(then <= now ? DS.Palette.calm : .orange)
            }
        } header: { Text("What if…") } footer: { Text("Drag to see how much each change would move your biological age.") }
    }

    private func slider(_ name: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(name).font(.callout); Spacer(); Text(String(format: "%+g %@", value.wrappedValue, unit)).font(.caption).monospacedDigit() }
            Slider(value: value, in: range, step: step)
        }
    }
}
