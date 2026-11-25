import SwiftUI
import SwiftData
import HealthKit
import Charts

// MARK: - Stress right now (0–3)
//
// Your heart rate over the last 20 minutes against your resting rate, nudged by your latest HRV against your normal.
// 0 calm · 1 a little · 2 moderate · 3 high. A Breathe session is one tap away when it's up.

struct StressNowCard: View {
    let rhr: Double?
    let hrvNormal: Double?
    @State private var score: Double?
    @State private var at: Date?
    @State private var moving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Stress now", systemImage: "waveform.path.ecg").font(DS.Font.headline).foregroundStyle(color)
                Spacer()
                if let at { Text(at.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(DS.Palette.inkSoft) }
            }
            if let s = score {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", s)).font(.system(size: 40, weight: .light)).monospacedDigit()
                    Text("of 3 · \(word(s))").font(.subheadline.weight(.medium)).foregroundStyle(color)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(LinearGradient(colors: [.green.opacity(0.5), .yellow.opacity(0.6), .orange.opacity(0.7), .red.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                        Circle().fill(.white).frame(width: 14, height: 14).shadow(radius: 1.5)
                            .offset(x: max(0, min(g.size.width - 14, g.size.width * CGFloat(s / 3) - 7)))
                    }
                }
                .frame(height: 14)
                Text(moving ? "You've been moving, so some of this is effort, not stress." :
                        s >= 1.5 ? "Your body is revved up. Two minutes of slow breathing brings it down." : "Nicely settled.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                if s >= 1 {
                    NavigationLink { LazyView(BreatheView()) } label: { Label("Breathe for 2 minutes", systemImage: "wind").font(DS.Font.caption.weight(.semibold)) }
                }
            } else {
                Text("Wear your Apple Watch: Keel reads your heart over the last 20 minutes.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
        }
        .bodyCard()
        .task { await load() }
    }

    private var color: Color { guard let s = score else { return .gray }; return s < 1 ? DS.Palette.calm : s < 2 ? .orange : .red }
    private func word(_ s: Double) -> String { s < 0.75 ? "calm" : s < 1.5 ? "a little" : s < 2.25 ? "moderate" : "high" }

    private func load() async {
        guard BodyHealth.available, let rhr, rhr > 30 else { return }
        let now = Date()
        let hr = await Self.samples(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()), since: now.addingTimeInterval(-20 * 60))
        guard !hr.isEmpty else { return }
        let avg = hr.map(\.1).reduce(0, +) / Double(hr.count)
        moving = (hr.map(\.1).max() ?? 0) > rhr * 1.6
        var s = (avg - rhr) / max(8, rhr * 0.18)
        if let normal = hrvNormal, normal > 5,
           let latest = await Self.samples(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), since: now.addingTimeInterval(-6 * 3600)).last?.1 {
            s += max(-0.5, min(1, (normal - latest) / normal * 2))          // HRV well below your normal adds to it
        }
        score = max(0, min(3, s))
        at = hr.last?.0
    }

    static func samples(_ id: HKQuantityTypeIdentifier, unit: HKUnit, since: Date) async -> [(Date, Double)] {
        await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: since, end: Date()),
                                  limit: 300, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, r, _ in
                cont.resume(returning: (r as? [HKQuantitySample] ?? []).map { ($0.startDate, $0.quantity.doubleValue(for: unit)) })
            }
            BodyHealth.store.execute(q)
        }
    }

    static func sumToday(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let start = Calendar.current.startOfDay(for: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: HKQuantityType(id), quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: Date()),
                                      options: .cumulativeSum) { _, s, _ in cont.resume(returning: s?.sumQuantity()?.doubleValue(for: unit)) }
            BodyHealth.store.execute(q)
        }
    }
}

// MARK: - Sleep planner

/// Pick when you want to be up; Keel works out when to wind down and be asleep, from the sleep you need tonight
/// (your base, yesterday's Swell and any sleep debt), and can set the wake alarm.
struct SleepPlannerCard: View {
    let days: [BodyDay]
    @AppStorage("sleep.planner.wake") private var wakeMin = -1
    @AppStorage(BodyPrefs.needKey) private var base = 8.0
    @AppStorage(SmartWake.key) private var alarmOn = false

    var body: some View {
        let plan = BodyMath.tonight(days, base: base)
        let cal = Calendar.current
        let planned = cal.dateComponents([.hour, .minute], from: plan.wake)
        let wakeMinutes = wakeMin >= 0 ? wakeMin : (planned.hour ?? 7) * 60 + (planned.minute ?? 0)
        let wake = cal.date(bySettingHour: wakeMinutes / 60, minute: wakeMinutes % 60, second: 0, of: plan.wake) ?? plan.wake
        let asleep = wake.addingTimeInterval(-plan.need * 3600)
        let lightsOut = asleep.addingTimeInterval(-15 * 60)
        let windDown = lightsOut.addingTimeInterval(-45 * 60)
        VStack(alignment: .leading, spacing: 10) {
            Label("Sleep planner", systemImage: "bed.double.fill").font(DS.Font.headline).foregroundStyle(BodyStyle.anchor)
            DatePicker("Up by", selection: Binding(get: { wake }, set: { let c = cal.dateComponents([.hour, .minute], from: $0); wakeMin = (c.hour ?? 7) * 60 + (c.minute ?? 0) }),
                       displayedComponents: .hourAndMinute)
            HStack(spacing: 0) {
                step("Wind down", windDown, "moon.haze")
                step("Lights out", lightsOut, "lightbulb.slash")
                step("Up", wake, "sun.max")
            }
            Text(String(format: "You need about %.1f h tonight (your base, yesterday's Swell and any sleep debt).", plan.need))
                .font(.caption2).foregroundStyle(DS.Palette.inkSoft)
            Toggle("Wake me at \(wake.formatted(date: .omitted, time: .shortened))", isOn: $alarmOn)
                .font(DS.Font.caption)
                .onChange(of: alarmOn) { Task { if alarmOn { await SmartWake.schedule(at: wake) } else { SmartWake.cancel() } } }
            Text("For a smart alarm that wakes you in light sleep, open Keel on your Apple Watch → Smart alarm.")
                .font(.caption2).foregroundStyle(DS.Palette.inkSoft)
        }
        .bodyCard()
    }

    private func step(_ t: String, _ d: Date, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(BodyStyle.anchor)
            Text(d.formatted(date: .omitted, time: .shortened)).font(.subheadline.weight(.semibold)).monospacedDigit()
            Text(t).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Recovery-aware day: book a workout, or lighten the load

struct RecoveryPlanCard: View {
    let tide: Int?
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var open: [TaskItem]
    @State private var booked: Date?

    var body: some View {
        let t = tide ?? 50
        VStack(alignment: .leading, spacing: 10) {
            Label(t >= 60 ? "A good day to train" : t >= 34 ? "Train, don't strain" : "Go light today",
                  systemImage: t >= 60 ? "figure.run" : t >= 34 ? "figure.walk" : "leaf.fill")
                .font(DS.Font.headline).foregroundStyle(t >= 60 ? BodyStyle.swell : t >= 34 ? .orange : DS.Palette.calm)
            if t >= 34 {
                if let slot = Self.slot() {
                    Text("You're free \(slot.start.formatted(date: .omitted, time: .shortened))–\(slot.end.formatted(date: .omitted, time: .shortened)). \(t >= 60 ? "Your Tide can take a hard session." : "Keep it moderate.")")
                        .font(DS.Font.caption)
                    Button { book(slot.start, minutes: t >= 60 ? 60 : 40) } label: {
                        Label(booked != nil ? "Booked" : "Book a \(t >= 60 ? 60 : 40)-minute workout", systemImage: booked != nil ? "checkmark.circle.fill" : "calendar.badge.plus")
                    }
                    .buttonStyle(.borderedProminent).tint(BodyStyle.swell).disabled(booked != nil)
                } else {
                    Text("No free 45 minutes left on your calendar today. A 10-minute walk still counts.").font(DS.Font.caption)
                }
            } else {
                let light = lightenable
                Text("Your body is asking for recovery. \(light.isEmpty ? "Nothing optional is due today." : "\(light.count) optional task\(light.count == 1 ? "" : "s") could move to tomorrow.")")
                    .font(DS.Font.caption)
                if !light.isEmpty {
                    Button { lighten(light) } label: { Label("Move them to tomorrow", systemImage: "arrow.turn.down.right") }
                        .buttonStyle(.bordered).tint(DS.Palette.calm)
                }
            }
        }
        .bodyCard()
    }

    /// Low-priority tasks due today (no set time): the ones safe to move on a recovery day.
    private var lightenable: [TaskItem] {
        let cal = Calendar.current
        return open.filter { t in
            guard let d = t.dueDate, cal.isDateInToday(d), !t.hasDueTime else { return false }
            return t.priority == .none || t.priority == .low
        }
    }

    private func lighten(_ tasks: [TaskItem]) {
        let cal = Calendar.current
        for t in tasks { t.dueDate = t.dueDate.flatMap { cal.date(byAdding: .day, value: 1, to: $0) } }
        try? ctx.save()
        Haptics.success()
        UndoCenter.shared.notify("Moved \(tasks.count) to tomorrow")
    }

    static func slot() -> DateInterval? {
        CalendarService.shared.freeSlots(minMinutes: 45, from: Date(), until: 21).first { $0.start > Date().addingTimeInterval(10 * 60) }
    }

    private func book(_ start: Date, minutes: Int) {
        let task = TaskItem(title: "Workout", dueDate: start, priority: .medium)
        task.estimatedMinutes = minutes
        task.listName = "Health"
        ctx.insert(task)
        try? CalendarService.shared.push(task)
        try? ctx.save()
        booked = start
        Haptics.success()
    }
}

// MARK: - Pace of Aging

/// How fast your body is aging compared with the calendar: biological age change per year of time, from your weekly
/// history. Under 1.0× means you're aging slower than the calendar.
struct PaceOfAgingCard: View {
    var body: some View {
        let h = BioAge.history
        VStack(alignment: .leading, spacing: 10) {
            Label("Pace of Aging", systemImage: "speedometer").font(DS.Font.headline).foregroundStyle(.purple)
            if let pace = Self.pace(h) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f×", pace)).font(.system(size: 40, weight: .light)).monospacedDigit()
                    Text(pace < 0.95 ? "slower than the calendar" : pace > 1.05 ? "faster than the calendar" : "in step with the calendar")
                        .font(.subheadline.weight(.medium)).foregroundStyle(pace < 0.95 ? DS.Palette.calm : pace > 1.05 ? .orange : DS.Palette.inkSoft)
                }
                Chart(Array(h.suffix(26).enumerated()), id: \.offset) { i, s in
                    LineMark(x: .value("Week", i), y: .value("Biological age", s.bioAge)).interpolationMethod(.catmullRom).foregroundStyle(.purple)
                }
                .chartXAxis(.hidden)
                .frame(height: 90)
                Text("Sleep, fitness (VO₂ max), resting heart rate and HRV move it most. Weeks of better habits slow it down.")
                    .font(.caption2).foregroundStyle(DS.Palette.inkSoft)
            } else {
                Text("Needs about 8 weeks of biological age history. Keel records one each week; check back soon.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
        }
        .bodyCard()
    }

    /// Slope of biological age over the last 6 months, in years per year.
    static func pace(_ h: [BioAge.Snapshot]) -> Double? {
        let pts = Array(h.suffix(26))
        guard pts.count >= 8 else { return nil }
        let n = Double(pts.count)
        let xs = (0..<pts.count).map { Double($0) / 52 }                   // years
        let ys = pts.map(\.bioAge)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let num = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let den = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard den > 0 else { return nil }
        return max(0, min(3, 1 + num / den))                               // 1 year per year, plus the trend
    }
}

// MARK: - Cycle coaching

struct CycleCoachCard: View {
    let x: HealthExtras
    var body: some View {
        if let c = BodyMath.cycle(periodDays: x.periodDays) {
            let p = Self.phase(day: c.day, length: c.length)
            VStack(alignment: .leading, spacing: 6) {
                Label("\(p.name) phase · day \(c.day)", systemImage: "circle.dotted.circle").font(DS.Font.headline).foregroundStyle(.pink)
                Text(p.train).font(DS.Font.caption)
                Text(p.sleep).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            .bodyCard()
        }
    }

    static func phase(day: Int, length: Int) -> (name: String, train: String, sleep: String) {
        let ovulation = max(10, length - 14)
        if day <= 5 { return ("Menstrual", "Lighter training is fine if you feel low; iron-rich food helps.", "Extra sleep and warmth help with cramps.") }
        if day < ovulation - 1 { return ("Follicular", "Energy usually rises: a great time for harder strength and interval sessions.", "Recovery tends to be quicker this week.") }
        if day <= ovulation + 1 { return ("Ovulation", "Strength often peaks. Warm up well: joints can be looser.", "Sleep as usual.") }
        return ("Luteal", "Resting heart rate and temperature rise, so Tide can dip. Steady cardio and moderate lifting suit this phase.",
                "A cooler room and a regular bedtime help as temperature rises.")
    }
}

// MARK: - Muscle radar

/// Which parts of you you've trained lately (strength sets and workouts, fading over 3 days), as one shape.
struct MuscleRadarCard: View {
    let days: [BodyDay]
    private static let groups: [(String, [String])] = [
        ("Chest", ["f.chest"]), ("Back", ["b.upperback", "b.lats", "b.lowerback"]), ("Shoulders", ["f.shoulderL", "f.shoulderR", "b.shoulderL", "b.shoulderR"]),
        ("Arms", ["f.armL", "f.armR", "b.armL", "b.armR", "f.forearmL", "f.forearmR"]), ("Core", ["f.abs", "f.hips"]),
        ("Legs", ["f.quadL", "f.quadR", "b.hamL", "b.hamR", "b.calfL", "b.calfR"]), ("Glutes", ["b.glutes"]),
    ]

    var body: some View {
        let load = BodyMapData.load(days: days)
        let values = Self.groups.map { g in min(1, g.1.map { load[$0] ?? 0 }.max() ?? 0) }
        VStack(alignment: .leading, spacing: 10) {
            Label("Muscle balance", systemImage: "hexagon").font(DS.Font.headline).foregroundStyle(BodyStyle.swell)
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = min(size.width, size.height) / 2 - 22
                let n = Self.groups.count
                func pt(_ i: Int, _ f: Double) -> CGPoint {
                    let a = Double(i) / Double(n) * 2 * .pi - .pi / 2
                    return CGPoint(x: c.x + cos(a) * r * f, y: c.y + sin(a) * r * f)
                }
                for ring in [0.33, 0.66, 1.0] {
                    var p = Path(); p.move(to: pt(0, ring)); for i in 1..<n { p.addLine(to: pt(i, ring)) }; p.closeSubpath()
                    ctx.stroke(p, with: .color(.secondary.opacity(0.25)), lineWidth: 0.6)
                }
                for i in 0..<n { var p = Path(); p.move(to: c); p.addLine(to: pt(i, 1)); ctx.stroke(p, with: .color(.secondary.opacity(0.2)), lineWidth: 0.6) }
                var shape = Path(); shape.move(to: pt(0, max(0.04, values[0])))
                for i in 1..<n { shape.addLine(to: pt(i, max(0.04, values[i]))) }
                shape.closeSubpath()
                ctx.fill(shape, with: .color(BodyStyle.swell.opacity(0.28)))
                ctx.stroke(shape, with: .color(BodyStyle.swell), lineWidth: 2)
                for i in 0..<n {
                    let p = pt(i, 1.18)
                    ctx.draw(Text(Self.groups[i].0).font(.caption2.weight(.semibold)).foregroundStyle(.secondary), at: p)
                }
            }
            .frame(height: 220)
            let low = zip(Self.groups.map(\.0), values).filter { $0.1 < 0.1 }.map(\.0)
            Text(low.isEmpty ? "Nicely balanced over the last few days." : "Not trained lately: \(low.joined(separator: ", ")).")
                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
        }
        .bodyCard()
    }
}

// MARK: - Training plan (AI)

struct TrainingPlanView: View {
    @Environment(\.modelContext) private var ctx
    @AppStorage("train.plan.text") private var planText = ""
    @AppStorage("train.plan.goal") private var goal = "Get stronger"
    @AppStorage("train.plan.days") private var daysPerWeek = 3
    @AppStorage("train.plan.minutes") private var minutes = 45
    @AppStorage("train.plan.hour") private var hour = 18
    @State private var working = false
    @State private var added = false

    private let goals = ["Get stronger", "Build endurance", "Lose fat", "Feel better overall", "Train for a 5K"]

    var body: some View {
        Form {
            Section {
                Picker("Goal", selection: $goal) { ForEach(goals, id: \.self) { Text($0) } }
                Stepper("\(daysPerWeek) days a week", value: $daysPerWeek, in: 2...6)
                Stepper("\(minutes) minutes", value: $minutes, in: 20...90, step: 5)
                Stepper("At \(hour > 12 ? hour - 12 : hour) \(hour >= 12 ? "PM" : "AM")", value: $hour, in: 5...21)
                Button { Task { await make() } } label: { Label(working ? "Building your plan…" : (planText.isEmpty ? "Build my week" : "Build a new week"), systemImage: "sparkles") }
                    .disabled(working)
            } footer: { Text("Keel shapes the week around your Tide: harder days when you're recovered, easier ones when you're not.") }
            if !planText.isEmpty {
                Section("This week") {
                    ForEach(planText.split(separator: "\n").map(String.init), id: \.self) { Text($0).font(.subheadline) }
                }
                Section {
                    Button { addToCalendar() } label: { Label(added ? "Added to your calendar" : "Add workouts to my calendar", systemImage: added ? "checkmark.circle.fill" : "calendar.badge.plus") }
                        .disabled(added)
                }
            }
        }
        .navigationTitle("Training plan")
    }

    private func make() async {
        working = true; defer { working = false }
        let tide = BodyEngine.shared.today?.tide.map { "\($0)%" } ?? "unknown"
        let prompt = """
        Make a 7-day training plan. Goal: \(goal). \(daysPerWeek) workout days of about \(minutes) minutes; the other days are rest or a walk.
        Today's recovery is \(tide). Reply with exactly 7 lines, one per day starting today, like "Mon: Strength · squats 4x8, rows 3x10, push-ups 3x12".
        Keep each line under 90 characters. No extra text.
        """
        if let out = await AIRouter.shared.write(prompt) {
            let lines = out.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.contains(":") }
            if lines.count >= 5 { planText = lines.prefix(7).joined(separator: "\n"); added = false; return }
        }
        planText = Self.template(goal: goal, days: daysPerWeek, minutes: minutes)
        added = false
    }

    static func template(goal: String, days: Int, minutes: Int) -> String {
        let cal = Calendar.current
        let names = (0..<7).map { (cal.date(byAdding: .day, value: $0, to: Date()) ?? Date()).formatted(.dateTime.weekday(.abbreviated)) }
        let work = goal == "Build endurance" || goal == "Train for a 5K"
            ? ["Easy run \(minutes) min", "Intervals: 6 × 2 min hard, 2 min easy", "Long easy run", "Tempo run 20 min", "Easy run + strides", "Long walk"]
            : ["Strength · squats 4×8, rows 3×10, push-ups 3×12", "Cardio · \(minutes) min zone 2", "Strength · deadlifts 4×6, presses 3×10, lunges 3×10",
               "Intervals · 8 × 30 s hard", "Strength · full body circuit", "Long walk or hike"]
        // Workout days spread evenly through the week, rest days between.
        let on = Set((0..<days).map { Int(Double($0) * 7 / Double(days)) })
        var w = 0
        var lines: [String] = []
        for (i, n) in names.enumerated() {
            if on.contains(i) { lines.append("\(n): \(work[w % work.count])"); w += 1 } else { lines.append("\(n): Rest · easy walk") }
        }
        return lines.joined(separator: "\n")
    }

    private func addToCalendar() {
        let cal = Calendar.current
        for (i, line) in planText.split(separator: "\n").enumerated() where !line.lowercased().contains("rest") {
            guard let day = cal.date(byAdding: .day, value: i, to: cal.startOfDay(for: Date())),
                  let start = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day), start > Date() else { continue }
            let title = line.split(separator: ":", maxSplits: 1).last.map { String($0).trimmingCharacters(in: .whitespaces) } ?? "Workout"
            let t = TaskItem(title: String(title.prefix(80)), dueDate: start, priority: .medium)
            t.estimatedMinutes = minutes
            t.listName = "Health"
            ctx.insert(t)
            try? CalendarService.shared.push(t)
        }
        try? ctx.save()
        added = true
        Haptics.success()
    }
}

// MARK: - Monthly report

struct MonthlyBodyReportView: View {
    @State private var engine = BodyEngine.shared

    var body: some View {
        let days = engine.days
        let rows: [BodyMetric] = [.tide, .swell, .anchor, .hrv, .rhr, .sleep, .vo2]
        let workouts = days.suffix(30).reduce(0) { $0 + $1.workouts.count }
        let before = days.dropLast(30).suffix(30).reduce(0) { $0 + $1.workouts.count }
        let best = days.suffix(30).filter { $0.tide != nil }.max { ($0.tide ?? 0) < ($1.tide ?? 0) }
        let impact = BodyMath.habitImpact(journal: engine.journal, days: days)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Last 30 days vs the 30 before").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                VStack(spacing: 10) {
                    ForEach(rows) { m in
                        let now = BodyDash.average(m, days: days, count: 30)
                        let prev = BodyDash.average(m, days: days, count: 30, endingDaysAgo: 30)
                        HStack {
                            Image(systemName: m.icon).foregroundStyle(m.color).frame(width: 22)
                            Text(m.short).font(.subheadline)
                            Spacer()
                            Text(now.map(m.format) ?? "–").font(.subheadline.weight(.semibold)).monospacedDigit()
                            if let now, let prev, abs(now - prev) >= m.noticeable {
                                let up = now > prev
                                let good = m.higherIsBetter.map { $0 == up }
                                Image(systemName: up ? "arrow.up.right" : "arrow.down.right").font(.caption.weight(.bold))
                                    .foregroundStyle(good == nil ? DS.Palette.inkSoft : good! ? DS.Palette.calm : .orange)
                            }
                        }
                    }
                }
                .bodyCard()
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(workouts) workouts (\(workouts >= before ? "+" : "")\(workouts - before) vs the month before)", systemImage: "figure.run")
                    if let b = best { Label("Best day: \(b.day.formatted(.dateTime.weekday(.wide).month().day())) · Tide \(b.tide ?? 0)%", systemImage: "star.fill") }
                    if let top = impact.first { Label("Biggest lever: \(top.tag) (\(top.delta > 0 ? "+" : "")\(top.delta)% Tide)", systemImage: "lightbulb.fill") }
                    if let pace = PaceOfAgingCard.pace(BioAge.history) { Label(String(format: "Pace of Aging %.1f×", pace), systemImage: "speedometer") }
                }
                .font(.subheadline)
                .bodyCard()
                ShareLink(item: summary(rows: rows, days: days, workouts: workouts)) { Label("Share my month", systemImage: "square.and.arrow.up") }
            }
            .padding(DS.Space.m)
        }
        .navigationTitle("Monthly report")
        .premiumBackground(BodyStyle.tide)
    }

    private func summary(rows: [BodyMetric], days: [BodyDay], workouts: Int) -> String {
        (["My month in Keel"] + rows.compactMap { m in BodyDash.average(m, days: days, count: 30).map { "\(m.short): \(m.format($0))" } } + ["Workouts: \(workouts)"])
            .joined(separator: "\n")
    }
}

// MARK: - Journal impact report

struct JournalImpactView: View {
    @State private var engine = BodyEngine.shared
    var body: some View {
        let impact = BodyMath.habitImpact(journal: engine.journal, days: engine.days)
        List {
            Section {
                if impact.isEmpty {
                    Text("Log behaviors on the Journal page for a few weeks (each needs at least 3 days with and 3 without) to see what helps and what hurts.")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                ForEach(impact, id: \.tag) { i in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(i.tag)
                            Text("\(i.with) days with, \(i.without) without").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        Text("\(i.delta > 0 ? "+" : "")\(i.delta)%").font(.headline).monospacedDigit()
                            .foregroundStyle(i.delta > 0 ? DS.Palette.calm : i.delta < 0 ? .orange : DS.Palette.inkSoft)
                    }
                }
            } header: { Text("Effect on next morning's Tide") } footer: { Text("A pattern from your own data, not proof of cause.") }
        }
        .navigationTitle("What moves your Tide")
    }
}

// MARK: - Food: net energy, micronutrients, tell Keel what you ate, saved meals

struct NetEnergyCard: View {
    let eaten: Double
    @State private var burned: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Net energy", systemImage: "flame.fill").font(DS.Font.headline).foregroundStyle(.orange)
            if let b = burned {
                let net = eaten - b
                HStack(spacing: 0) {
                    stat("Eaten", eaten, .green); stat("Burned", b, .orange)
                    stat(net >= 0 ? "Surplus" : "Deficit", abs(net), net >= 0 ? .blue : DS.Palette.calm)
                }
                Text("Burned = resting + active energy from Apple Health so far today.").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
            } else {
                Text("Needs Apple Health energy data (your Apple Watch records it).").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
        }
        .bodyCard()
        .task {
            let a = await StressNowCard.sumToday(.activeEnergyBurned, unit: .kilocalorie()) ?? 0
            let r = await StressNowCard.sumToday(.basalEnergyBurned, unit: .kilocalorie()) ?? 0
            if a + r > 0 { burned = a + r }
        }
    }

    private func stat(_ t: String, _ v: Double, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(Int(v.rounded()))").font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(c)
            Text(t).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MicronutrientsCard: View {
    let keel: NutritionFacts
    @State private var health: [String: Double] = [:]

    private struct Nutrient { let id: String; let name: String; let type: HKQuantityTypeIdentifier; let unit: HKUnit; let goal: Double; let u: String }
    private static let list: [Nutrient] = [
        .init(id: "mg", name: "Magnesium", type: .dietaryMagnesium, unit: .gramUnit(with: .milli), goal: 400, u: "mg"),
        .init(id: "zn", name: "Zinc", type: .dietaryZinc, unit: .gramUnit(with: .milli), goal: 11, u: "mg"),
        .init(id: "fe", name: "Iron", type: .dietaryIron, unit: .gramUnit(with: .milli), goal: 8, u: "mg"),
        .init(id: "k", name: "Potassium", type: .dietaryPotassium, unit: .gramUnit(with: .milli), goal: 3400, u: "mg"),
        .init(id: "ca", name: "Calcium", type: .dietaryCalcium, unit: .gramUnit(with: .milli), goal: 1000, u: "mg"),
        .init(id: "d", name: "Vitamin D", type: .dietaryVitaminD, unit: .gramUnit(with: .micro), goal: 15, u: "µg"),
        .init(id: "c", name: "Vitamin C", type: .dietaryVitaminC, unit: .gramUnit(with: .milli), goal: 90, u: "mg"),
        .init(id: "b12", name: "Vitamin B12", type: .dietaryVitaminB12, unit: .gramUnit(with: .micro), goal: 2.4, u: "µg"),
        .init(id: "fol", name: "Folate", type: .dietaryFolate, unit: .gramUnit(with: .micro), goal: 400, u: "µg"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Vitamins & minerals", systemImage: "leaf.circle.fill").font(DS.Font.headline).foregroundStyle(DS.Palette.calm)
            ForEach(Self.list, id: \.id) { n in
                let v = value(n)
                HStack {
                    Text(n.name).font(.subheadline).frame(width: 100, alignment: .leading)
                    ProgressView(value: min(1, v / n.goal)).tint(v >= n.goal ? DS.Palette.calm : .orange)
                    Text("\(v < 10 ? String(format: "%.1f", v) : "\(Int(v))") \(n.u)").font(.caption).monospacedDigit().frame(width: 70, alignment: .trailing)
                }
            }
            Text("From what you log in Keel and food other apps save to Apple Health. Goals are typical adult amounts.")
                .font(.caption2).foregroundStyle(DS.Palette.inkSoft)
        }
        .bodyCard()
        .task {
            var out: [String: Double] = [:]
            for n in Self.list { if let v = await StressNowCard.sumToday(n.type, unit: n.unit) { out[n.id] = v } }
            health = out
        }
    }

    private func value(_ n: Nutrient) -> Double {
        let mine: Double = switch n.id { case "mg": keel.magnesiumMg ?? 0; case "zn": keel.zincMg ?? 0; case "fe": keel.ironMg ?? 0; default: 0 }
        return max(mine, health[n.id] ?? 0)
    }
}

/// "Two eggs, toast and coffee": typed like a message, logged in one go (checked against your diet).
struct TellKeelFoodBox: View {
    @Environment(\.modelContext) private var ctx
    @State private var text = ""
    @State private var working = false
    @State private var done: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill").foregroundStyle(.green)
                TextField("Tell Keel what you ate…", text: $text, axis: .vertical)
                    .lineLimit(1...3)
                    .submitLabel(.send)
                    .onSubmit { Task { await log() } }
                if working { ProgressView() } else if !text.isEmpty {
                    Button { Task { await log() } } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }.tint(.green)
                }
            }
            if let done { Label(done, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(DS.Palette.calm) }
        }
        .bodyCard()
    }

    private func log() async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !working else { return }
        working = true; defer { working = false }
        guard let est = await MealEstimator.estimate(t) else { done = "Couldn't work that out. Try Log food."; return }
        let verdict = DietChecker.check(name: est.name, ingredientsText: est.ingredients, facts: est.facts).verdict
        let h = Calendar.current.component(.hour, from: Date())
        let meal = h < 11 ? "breakfast" : h < 15 ? "lunch" : h < 21 ? "dinner" : "snack"
        _ = NutritionLog.logMeal(name: est.name, ingredients: est.ingredients, facts: est.facts, verdict: verdict, meal: meal, ctx: ctx)
        try? ctx.save()
        done = "Logged \(est.name) · \(Int(est.facts.calories ?? 0)) kcal"
        text = ""
        Haptics.success()
    }
}

/// Meals you save, logged again in one tap; any meal can be copied to another day.
struct SavedMeal: Codable, Identifiable, Hashable {
    struct Item: Codable, Hashable { var name: String; var ingredients: String; var facts: NutritionFacts; var verdict: String }
    var id = UUID()
    var name: String
    var items: [Item]
    var kcal: Int { Int(items.reduce(0) { $0 + ($1.facts.calories ?? 0) }) }
}

@MainActor
enum SavedMeals {
    static let key = "food.savedMeals"
    static var all: [SavedMeal] {
        get { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([SavedMeal].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    static func save(_ name: String, entries: [FoodEntry]) {
        let items = entries.map { SavedMeal.Item(name: $0.name, ingredients: $0.name, facts: $0.facts, verdict: $0.verdictRaw) }
        guard !items.isEmpty else { return }
        all = all.filter { $0.name != name } + [SavedMeal(name: name, items: items)]
    }

    /// Logs the items again, as the given meal on the given day.
    static func log(_ items: [SavedMeal.Item], meal: String, on day: Date, ctx: ModelContext) {
        let cal = Calendar.current
        let now = Date()
        let at = cal.isDateInToday(day) ? now
            : cal.date(bySettingHour: cal.component(.hour, from: now), minute: cal.component(.minute, from: now), second: 0, of: day) ?? day
        for i in items {
            let e = NutritionLog.logMeal(name: i.name, ingredients: i.ingredients, facts: i.facts,
                                         verdict: DietVerdict(rawValue: i.verdict) ?? .unknown, meal: meal, ctx: ctx)
            e.date = at
        }
        try? ctx.save()
    }

    static func items(_ entries: [FoodEntry]) -> [SavedMeal.Item] {
        entries.map { SavedMeal.Item(name: $0.name, ingredients: $0.name, facts: $0.facts, verdict: $0.verdictRaw) }
    }
}
