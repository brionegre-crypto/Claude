import SwiftUI
import HealthKit
import Charts
import UserNotifications

// MARK: - Extra Apple Health reads (today's activity, weight, cycle, heart-rate zones)

struct HealthExtras {
    var steps = 0
    var daylightMinutes = 0
    var mindfulMinutes = 0
    var zoneMinutes: [Int] = [0, 0, 0, 0, 0]       // zones 1–5 today
    var weight: [(Date, Double)] = []              // kg, last 90 days
    var periodDays: [Date] = []                    // days with menstrual flow, last 120 days

    static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.stepCount), HKQuantityType(.timeInDaylight), HKCategoryType(.mindfulSession),
        HKQuantityType(.bodyMass), HKCategoryType(.menstrualFlow),
    ]

    static func load() async -> HealthExtras {
        guard BodyHealth.available else { return HealthExtras() }
        let store = BodyHealth.store
        let cal = Calendar.current
        let today = HKQuery.predicateForSamples(withStart: cal.startOfDay(for: Date()), end: Date())
        var x = HealthExtras()
        func sum(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit) async -> Double {
            let q = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: HKQuantityType(id), predicate: today), options: .cumulativeSum)
            return (try? await q.result(for: store))?.sumQuantity()?.doubleValue(for: unit) ?? 0
        }
        x.steps = Int(await sum(.stepCount, .count()))
        x.daylightMinutes = Int(await sum(.timeInDaylight, .minute()))
        let mind = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.mindfulSession), predicate: today)], sortDescriptors: [])
        x.mindfulMinutes = Int(((try? await mind.result(for: store)) ?? []).reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 60)
        // Minutes in each heart-rate zone today.
        let hr = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(.heartRate), predicate: today)], sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = (try? await hr.result(for: store)) ?? []
        let maxHR = BodyHealth.maxHR(), bpm = HKUnit.count().unitDivided(by: .minute())
        for (i, s) in samples.enumerated() {
            let next = i + 1 < samples.count ? samples[i + 1].startDate : s.startDate.addingTimeInterval(60)
            let minutes = min(10, next.timeIntervalSince(s.startDate) / 60)
            let pct = s.quantity.doubleValue(for: bpm) / maxHR
            let zone = pct >= 0.9 ? 4 : pct >= 0.8 ? 3 : pct >= 0.7 ? 2 : pct >= 0.6 ? 1 : pct >= 0.5 ? 0 : -1
            if zone >= 0 { x.zoneMinutes[zone] += Int(minutes.rounded()) }
        }
        let ninety = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-90 * 86_400), end: Date())
        let w = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(.bodyMass), predicate: ninety)], sortDescriptors: [SortDescriptor(\.startDate)])
        x.weight = ((try? await w.result(for: store)) ?? []).map { ($0.startDate, $0.quantity.doubleValue(for: .gramUnit(with: .kilo))) }
        let flowPred = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-120 * 86_400), end: Date())
        let flow = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.menstrualFlow), predicate: flowPred)], sortDescriptors: [SortDescriptor(\.startDate)])
        let none = 5          // "no flow" in Apple Health's menstrual flow values
        x.periodDays = Array(Set(((try? await flow.result(for: store)) ?? []).filter { $0.value != none }.map { cal.startOfDay(for: $0.startDate) })).sorted()
        return x
    }
}

// MARK: - Pure insights (tested)

extension BodyMath {
    /// Caffeine still in your body (mg), with a 5-hour half-life.
    static func caffeineNow(_ drinks: [Drink], at t: Date = Date()) -> Double {
        drinks.filter { $0.at <= t && $0.caffeine > 0 }.reduce(0) { $0 + Double($1.caffeine) * pow(0.5, t.timeIntervalSince($1.at) / 3600 / 5) }
    }

    /// Hours short of your need over the last 7 nights.
    static func sleepDebt(_ days: [BodyDay], base: Double) -> Double {
        days.suffix(7).filter(\.hasSleep).reduce(0) { $0 + max(0, (($1.need ?? base) - $1.asleep / 60)) }
    }

    /// "Social jet lag": how far your weekend sleep midpoint drifts from your weekday one (hours).
    static func socialJetLag(_ days: [BodyDay]) -> Double? {
        let cal = Calendar.current
        func mid(_ d: BodyDay) -> Double? {
            guard let b = d.bedtime, let w = d.wake else { return nil }
            let m = b.addingTimeInterval(w.timeIntervalSince(b) / 2)
            let c = cal.dateComponents([.hour, .minute], from: m)
            var h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
            if h > 12 { h -= 24 }
            return h
        }
        let recent = days.suffix(28)
        let weekend = recent.filter { [1, 7].contains(cal.component(.weekday, from: $0.day)) }.compactMap(mid)
        let weekday = recent.filter { ![1, 7].contains(cal.component(.weekday, from: $0.day)) }.compactMap(mid)
        guard weekend.count >= 2, weekday.count >= 4 else { return nil }
        return abs(weekend.reduce(0, +) / Double(weekend.count) - weekday.reduce(0, +) / Double(weekday.count))
    }

    /// Rough "energy left today" (0–100): your Tide, minus what today's effort and stress used up.
    static func energyLeft(_ day: BodyDay?, now: Date = Date()) -> Int? {
        guard let d = day, let tide = d.tide else { return nil }
        let stressHours = d.stress.compactMap { $0 }.filter { $0 == 2 }.count
        let awake = d.wake.map { max(0, now.timeIntervalSince($0) / 3600) } ?? 8
        let left = Double(tide) - Double(d.swell) * 0.35 - Double(stressHours) * 4 - max(0, awake - 8) * 2.5
        return Int(min(100, max(0, left)).rounded())
    }

    /// Days in a row (ending yesterday or today) where the test holds.
    static func streak(_ days: [BodyDay], _ test: (BodyDay) -> Bool) -> Int {
        var n = 0
        for d in days.reversed() {
            if test(d) { n += 1 } else if Calendar.current.isDateInToday(d.day) { continue } else { break }
        }
        return n
    }

    /// Cycle day and the next expected period from the days Health has, or nil without enough data.
    static func cycle(periodDays: [Date], now: Date = Date()) -> (day: Int, next: Date, length: Int)? {
        let cal = Calendar.current
        var starts: [Date] = []
        for d in periodDays.sorted() where starts.last.map({ cal.dateComponents([.day], from: $0, to: d).day ?? 0 > 10 }) ?? true { starts.append(d) }
        guard let last = starts.last else { return nil }
        let gaps = zip(starts, starts.dropFirst()).map { cal.dateComponents([.day], from: $0, to: $1).day ?? 28 }.filter { (20...45).contains($0) }
        let length = gaps.isEmpty ? 28 : gaps.reduce(0, +) / gaps.count
        let day = (cal.dateComponents([.day], from: last, to: cal.startOfDay(for: now)).day ?? 0) + 1
        let next = cal.date(byAdding: .day, value: length, to: last) ?? now
        return (day, next, length)
    }
}

// MARK: - Cards

struct ActivityTodayCard: View {
    let x: HealthExtras
    @AppStorage("body.stepGoal") private var stepGoal = 8_000
    @AppStorage("body.daylightGoal") private var daylightGoal = 30
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Today", systemImage: "figure.walk").font(DS.Font.headline).foregroundStyle(.green)
            HStack(spacing: 0) {
                ScoreRing(title: "Steps", value: x.steps, max: stepGoal, color: .green, size: 70).frame(maxWidth: .infinity)
                ScoreRing(title: "Daylight", value: x.daylightMinutes, max: daylightGoal, color: .yellow, suffix: "min", size: 70).frame(maxWidth: .infinity)
                ScoreRing(title: "Mindful", value: x.mindfulMinutes, max: 10, color: .teal, suffix: "min", size: 70).frame(maxWidth: .infinity)
            }
            Text(x.daylightMinutes < daylightGoal && Calendar.current.component(.hour, from: Date()) < 16
                 ? "Daylight early in the day helps you sleep tonight. A 10-minute walk outside counts."
                 : "\(x.steps.formatted()) of \(stepGoal.formatted()) steps.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
        }
        .bodyCard()
    }
}

struct ZonesCard: View {
    let minutes: [Int]
    private let colors: [Color] = [.gray, .blue, .green, .orange, .red]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Heart-rate zones today", systemImage: "heart.circle.fill").font(DS.Font.headline).foregroundStyle(.red)
            Chart(Array(minutes.enumerated()), id: \.offset) { i, m in
                BarMark(x: .value("Minutes", m), y: .value("Zone", "Zone \(i + 1)")).foregroundStyle(colors[i].gradient)
            }
            .frame(height: 120)
            Text("Zones 1–2 build your base; 3 is steady effort; 4–5 are hard. Most training time belongs in 1–2.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
        }
        .bodyCard()
    }
}

struct CaffeineCurveCard: View {
    var body: some View {
        let drinks = Drinks.all.filter { $0.at > Date().addingTimeInterval(-36 * 3600) }
        let cal = Calendar.current
        let start = cal.date(bySettingHour: 6, minute: 0, second: 0, of: Date()) ?? Date()
        let points = stride(from: 0, through: 18 * 2, by: 1).map { i -> (Date, Double) in
            let t = start.addingTimeInterval(Double(i) * 1800); return (t, BodyMath.caffeineNow(drinks, at: t))
        }
        let now = BodyMath.caffeineNow(drinks)
        let lowAt = points.first { $0.0 > Date() && $0.1 < 50 }?.0
        VStack(alignment: .leading, spacing: 8) {
            Label("Caffeine in your body", systemImage: "waveform.path.ecg").font(DS.Font.headline).foregroundStyle(.brown)
            Chart(points, id: \.0) { p in
                AreaMark(x: .value("Time", p.0), y: .value("mg", p.1)).foregroundStyle(Color.brown.opacity(0.3).gradient)
                LineMark(x: .value("Time", p.0), y: .value("mg", p.1)).foregroundStyle(.brown)
            }
            .frame(height: 110)
            Text(now < 50 ? "About \(Int(now)) mg now: low enough not to bother your sleep."
                 : "About \(Int(now)) mg now" + (lowAt.map { ", below 50 mg (sleep-friendly) around \($0.formatted(date: .omitted, time: .shortened))." } ?? "."))
                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
        }
        .bodyCard()
    }
}

struct SleepDebtCard: View {
    let days: [BodyDay]
    let base: Double
    var body: some View {
        let debt = BodyMath.sleepDebt(days, base: base)
        let lag = BodyMath.socialJetLag(days)
        let sleptWell = BodyMath.streak(days) { $0.asleep >= 420 }
        VStack(alignment: .leading, spacing: 8) {
            Label("Sleep debt & rhythm", systemImage: "bed.double.fill").font(DS.Font.headline).foregroundStyle(BodyStyle.anchor)
            Chart(Array(days.suffix(7))) { d in
                BarMark(x: .value("Night", d.day, unit: .day), y: .value("Hours", d.asleep / 60)).foregroundStyle(BodyStyle.anchor.gradient)
                RuleMark(y: .value("Need", d.need ?? base)).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .frame(height: 110)
            Text(debt < 0.5 ? "No real sleep debt this week." : String(format: "%.1f hours short this week. An earlier night or two pays it back.", debt))
                .font(DS.Font.caption)
            if let lag {
                Text(lag < 1 ? "Your weekend sleep keeps to your weekday rhythm. Good for energy on Mondays."
                     : String(format: "Weekend sleep shifts by %.1f hours (\"social jet lag\"), which can make Mondays heavy.", lag))
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            if sleptWell >= 2 { Text("🔥 \(sleptWell) nights in a row with 7+ hours.").font(DS.Font.caption) }
        }
        .bodyCard()
    }
}

/// Low Tide in the early afternoon with a free half hour: a short nap.
struct NapAdvisorCard: View {
    let tide: Int?
    var body: some View {
        let hour = Calendar.current.component(.hour, from: Date())
        if let t = tide, t < 50, (12...15).contains(hour),
           let slot = CalendarService.shared.freeSlots(minMinutes: 30, from: Date(), until: 16).first {
            VStack(alignment: .leading, spacing: 6) {
                Label("A short nap could help", systemImage: "powersleep").font(DS.Font.headline).foregroundStyle(BodyStyle.anchor)
                Text("Your Tide is low and you're free at \(slot.start.formatted(date: .omitted, time: .shortened)). Twenty minutes, before 4 PM, won't hurt tonight's sleep.")
                    .font(DS.Font.caption)
            }
            .bodyCard()
        }
    }
}

struct EnergyLeftCard: View {
    let day: BodyDay?
    var body: some View {
        if let left = BodyMath.energyLeft(day) {
            HStack(spacing: 14) {
                Gauge(value: Double(left), in: 0...100) { Image(systemName: "bolt.fill") } currentValueLabel: { Text("\(left)") }
                    .gaugeStyle(.accessoryCircular).tint(Gradient(colors: [.red, .orange, .green]))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Energy left today").font(DS.Font.headline)
                    Text(left >= 60 ? "Plenty in the tank." : left >= 30 ? "Pace yourself; save the hard stuff for tomorrow if you can." : "Running low. Wind down early tonight.")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
            }
            .bodyCard()
        }
    }
}

struct BodyTrendsView: View {
    @State private var engine = BodyEngine.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                trend("Heart rate variability", "ms", engine.days.compactMap { d in d.hrv.map { (d.day, $0) } }, .purple, higherIsBetter: true)
                trend("Resting heart rate", "bpm", engine.days.compactMap { d in d.rhr.map { (d.day, $0) } }, .red, higherIsBetter: false)
                trend("Sleep", "h", engine.days.filter(\.hasSleep).map { ($0.day, $0.asleep / 60) }, BodyStyle.anchor, higherIsBetter: true)
            }
            .padding()
        }
        .navigationTitle("90-day trends")
    }

    private func trend(_ title: String, _ unit: String, _ pts: [(Date, Double)], _ c: Color, higherIsBetter: Bool) -> some View {
        let v = pts.map(\.1)
        let m = v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count)
        let sd = v.count < 2 ? 0 : sqrt(v.reduce(0) { $0 + pow($1 - m, 2) } / Double(v.count - 1))
        let firstHalf = v.prefix(v.count / 2), secondHalf = v.suffix(v.count / 2)
        let change = (secondHalf.isEmpty || firstHalf.isEmpty) ? 0 : secondHalf.reduce(0, +) / Double(secondHalf.count) - firstHalf.reduce(0, +) / Double(firstHalf.count)
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(DS.Font.headline)
            if pts.count < 5 { Text("Not enough data yet.").font(.caption).foregroundStyle(DS.Palette.inkSoft) } else {
                Chart {
                    RuleMark(y: .value("Low", m - sd)).foregroundStyle(c.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    RuleMark(y: .value("High", m + sd)).foregroundStyle(c.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    ForEach(pts, id: \.0) { p in LineMark(x: .value("Day", p.0), y: .value(unit, p.1)).foregroundStyle(c) }
                }
                .frame(height: 140)
                Text(String(format: "Average %.1f %@. Dashed lines: your normal range. ", m, unit)
                     + (abs(change) < sd / 3 ? "Steady lately." : (change > 0) == higherIsBetter ? "Trending better." : "Trending worse; look at sleep and stress."))
                    .font(.caption).foregroundStyle(DS.Palette.inkSoft)
            }
        }
    }
}

struct WorkoutHistoryView: View {
    @State private var engine = BodyEngine.shared
    @AppStorage("body.activeDaysGoal") private var goal = 4
    var body: some View {
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let activeThisWeek = engine.days.filter { $0.day >= weekStart && (!$0.workouts.isEmpty || $0.swell >= 40) }.count
        let workouts = engine.days.suffix(30).flatMap(\.workouts).sorted { $0.start > $1.start }
        List {
            Section {
                HStack {
                    Text("Active days this week")
                    Spacer()
                    Text("\(activeThisWeek) of \(goal)").font(.headline).foregroundStyle(activeThisWeek >= goal ? .green : DS.Palette.ink)
                }
                Stepper("Weekly goal: \(goal) days", value: $goal, in: 1...7)
            } footer: { Text("An active day is one with a workout or a Swell of 40 or more.") }
            Section("Last 30 days") {
                if workouts.isEmpty { Text("No workouts recorded in Apple Health.").foregroundStyle(DS.Palette.inkSoft) }
                ForEach(workouts) { w in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(w.name)
                            Text("\(w.start.formatted(date: .abbreviated, time: .shortened)) · \(w.minutes) min" + (w.kcal.map { " · \($0) kcal" } ?? "")).font(.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        Text("Swell \(w.swell)").font(.caption.weight(.semibold)).foregroundStyle(BodyStyle.swell)
                    }
                }
            }
        }
        .navigationTitle("Workouts")
    }
}

struct WeightView: View {
    let x: HealthExtras
    var body: some View {
        List {
            if x.weight.isEmpty {
                Text("No weight in Apple Health yet. Add it in the Health app, or from a smart scale that syncs with Health.").foregroundStyle(DS.Palette.inkSoft)
            } else {
                Section {
                    Chart(x.weight, id: \.0) { p in LineMark(x: .value("Day", p.0), y: .value("kg", p.1)).foregroundStyle(.blue) }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 180)
                    if let f = x.weight.first?.1, let l = x.weight.last?.1 {
                        Text(String(format: "%.1f kg now · %@%.1f kg over %d days", l, l - f >= 0 ? "+" : "", l - f,
                                    Calendar.current.dateComponents([.day], from: x.weight.first!.0, to: x.weight.last!.0).day ?? 0))
                    }
                }
            }
        }
        .navigationTitle("Weight")
    }
}

struct CycleCard: View {
    let x: HealthExtras
    var body: some View {
        if let c = BodyMath.cycle(periodDays: x.periodDays) {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: c.next).day ?? 0
            VStack(alignment: .leading, spacing: 6) {
                Label("Cycle", systemImage: "circle.dotted.circle").font(DS.Font.headline).foregroundStyle(.pink)
                Text("Day \(c.day) of about \(c.length). " + (days > 0 ? "Next period expected in \(days) days." : "Period expected around now."))
                    .font(DS.Font.caption)
                Text("Resting heart rate and temperature often rise in the days before a period, which can lower Tide a little. That's normal.")
                    .font(.caption2).foregroundStyle(DS.Palette.inkSoft)
            }
            .bodyCard()
        }
    }
}

// MARK: - Sleep sounds with a timer

struct SleepSoundsView: View {
    @AppStorage("sleep.sound") private var sound = "rain"
    @State private var minutes = 30
    @State private var endsAt: Date?
    @State private var stopper: Task<Void, Never>?
    var body: some View {
        Form {
            Picker("Sound", selection: $sound) { ForEach(FocusSound.Kind.allCases.filter { $0 != .off }) { Text($0.label).tag($0.rawValue) } }
            Picker("Stop after", selection: $minutes) { ForEach([15, 30, 45, 60, 90], id: \.self) { Text("\($0) min").tag($0) } }
            Section {
                if let e = endsAt {
                    Text("Playing until \(e.formatted(date: .omitted, time: .shortened))")
                    Button("Stop now", role: .destructive) { stop() }
                } else {
                    Button("Play", systemImage: "play.fill") { play() }
                }
            } footer: { Text("Keeps playing with the screen locked, then fades out on its own.") }
        }
        .navigationTitle("Sleep sounds")
    }
    private func play() {
        FocusSound.shared.play(FocusSound.Kind(rawValue: sound) ?? .rain)
        endsAt = Date().addingTimeInterval(Double(minutes * 60))
        stopper?.cancel()
        stopper = Task { @MainActor in try? await Task.sleep(for: .seconds(Double(minutes * 60))); if !Task.isCancelled { stop() } }
    }
    private func stop() { stopper?.cancel(); FocusSound.shared.stop(); endsAt = nil }
}

// MARK: - Weekly body report (Sunday evening)

@MainActor
enum WeeklyBodyReport {
    static func schedule(days: [BodyDay]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["body.weekly"])
        let week = days.suffix(7)
        let tides = week.compactMap(\.tide), sleeps = week.filter(\.hasSleep).map { $0.asleep / 60 }
        guard tides.count >= 3 else { return }
        let best = week.filter { $0.tide != nil }.max { ($0.tide ?? 0) < ($1.tide ?? 0) }
        let c = UNMutableNotificationContent()
        c.title = "Your week in Body"
        c.body = String(format: "Tide averaged %d%%, sleep %.1f h, %d active days.", tides.reduce(0, +) / tides.count,
                        sleeps.isEmpty ? 0 : sleeps.reduce(0, +) / Double(sleeps.count), week.filter { !$0.workouts.isEmpty || $0.swell >= 40 }.count)
            + (best.map { " Best day: \($0.day.formatted(.dateTime.weekday(.wide)))." } ?? "")
        c.userInfo = ["deeplink": "com.keel.app://tool/body"]
        var comps = DateComponents(); comps.weekday = 1; comps.hour = 18; comps.minute = 30
        center.add(UNNotificationRequest(identifier: "body.weekly", content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }
}

extension View {
    /// The Body screen's card look.
    func bodyCard() -> some View {
        padding(DS.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { PremiumSurface() }
    }
}
