import SwiftUI
import Charts
import HealthKit

// MARK: - Energy bank: your energy through the day, charged by sleep, drained by effort and stress, with a forecast to bedtime

struct EnergyPoint: Identifiable, Hashable { let at: Date; let level: Double; let forecast: Bool; var id: Date { at } }

enum EnergyBank {
    /// Hour-by-hour energy (0–100) from when you woke until bedtime. Past hours use what really happened; later hours are a forecast.
    static func timeline(_ d: BodyDay?, bedtime: Date, now: Date = Date()) -> [EnergyPoint] {
        guard let d else { return [] }
        let cal = Calendar.current
        let wake = d.wake ?? cal.date(bySettingHour: 7, minute: 0, second: 0, of: now) ?? now
        var level = charge(d)
        var out: [EnergyPoint] = [EnergyPoint(at: wake, level: level, forecast: false)]
        var t = wake
        let end = max(bedtime, now.addingTimeInterval(3600))
        while t < end {
            let next = t.addingTimeInterval(3600)
            let future = next > now
            level -= drain(d, from: t, to: next, future: future)
            level = min(100, max(0, level))
            out.append(EnergyPoint(at: next, level: level, forecast: future))
            t = next
        }
        return out
    }

    /// Morning charge: recovery does most of it, sleep the rest.
    static func charge(_ d: BodyDay) -> Double {
        let tide = Double(d.tide ?? 60), anchor = Double(d.anchor ?? 60)
        return min(100, max(15, 10 + tide * 0.6 + anchor * 0.3))
    }

    /// How much one hour costs: just being awake, plus stress, plus effort from workouts.
    static func drain(_ d: BodyDay, from: Date, to: Date, future: Bool) -> Double {
        var cost = 2.6
        let hour = Calendar.current.component(.hour, from: from)
        if future {
            cost += 0.8                                                 // a typical hour's stress
        } else if (8...22).contains(hour), d.stress.indices.contains(hour - 8), let s = d.stress[hour - 8] {
            cost += s == 2 ? 4 : s == 1 ? 1.5 : -0.6                    // a calm hour recharges a little
        }
        for w in d.workouts {
            let wEnd = w.start.addingTimeInterval(Double(w.minutes * 60))
            let overlap = min(to, wEnd).timeIntervalSince(max(from, w.start))
            if overlap > 0, w.minutes > 0 { cost += Double(w.swell) * 0.4 * overlap / Double(w.minutes * 60) }
        }
        return cost
    }
}

struct EnergyBankCard: View {
    let day: BodyDay?
    let days: [BodyDay]
    var body: some View {
        let bed = BodyMath.tonight(days, base: BodyPrefs.sleepNeed).bedtime
        let points = EnergyBank.timeline(day, bedtime: bed)
        if let day, !points.isEmpty {
            let now = points.last { !$0.forecast } ?? points[0]
            let atBed = points.last ?? now
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Energy bank", systemImage: "bolt.batteryblock.fill").font(DS.Font.headline).foregroundStyle(.green)
                    Spacer()
                    Text("\(Int(now.level))").font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit().contentTransition(.numericText())
                    Text("/ 100").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                Chart {
                    ForEach(points.filter { !$0.forecast }) { p in
                        AreaMark(x: .value("Time", p.at), y: .value("Energy", p.level))
                            .foregroundStyle(LinearGradient(colors: [.green.opacity(0.45), .green.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Time", p.at), y: .value("Energy", p.level), series: .value("Kind", "Today"))
                            .foregroundStyle(.green).interpolationMethod(.monotone)
                    }
                    ForEach(points.filter { $0.forecast || $0.at == now.at }) { p in
                        LineMark(x: .value("Time", p.at), y: .value("Energy", p.level), series: .value("Kind", "Forecast"))
                            .foregroundStyle(.green.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4])).interpolationMethod(.monotone)
                    }
                    RuleMark(x: .value("Now", Date())).foregroundStyle(DS.Palette.inkSoft.opacity(0.4))
                }
                .chartYScale(domain: 0...100)
                .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 4)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour()) } }
                .frame(height: 130)
                Text(advice(now: now.level, bed: atBed.level, charge: EnergyBank.charge(day)))
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            .bodyCard()
        }
    }

    private func advice(now: Double, bed: Double, charge: Double) -> String {
        let start = "Sleep charged you to \(Int(charge)). "
        if now >= 60 { return start + "Plenty left: a good time for your hardest task or a workout." }
        if now >= 35 { return start + "Steady. Mix focused work with breaks; you'll reach bedtime around \(Int(bed))." }
        return start + "Running low. Short tasks, a walk outside, and an early night will refill it."
    }
}

// MARK: - Cardio load: how much training you've done lately versus what you're used to

struct LoadPoint: Identifiable, Hashable { let day: Date; let load: Double; let fitness: Double; let fatigue: Double; var id: Date { day } }

@MainActor
enum CardioLoad {
    /// Daily load = heart-rate effort (TRIMP) plus strength work. Fitness is a 42-day average, fatigue a 7-day one.
    static func series(_ days: [BodyDay], strength: [StrengthSession] = []) -> [LoadPoint] {
        let cal = Calendar.current
        var fitness = 0.0, fatigue = 0.0
        var out: [LoadPoint] = []
        for d in days {
            let lift = strength.filter { cal.isDate($0.start, inSameDayAs: d.day) }.reduce(0.0) { $0 + Double(StrengthStore.strain($1)) * 1.2 }
            let load = d.trimp + lift
            fitness += (load - fitness) / 42
            fatigue += (load - fatigue) / 7
            out.append(LoadPoint(day: d.day, load: load, fitness: fitness, fatigue: fatigue))
        }
        return out
    }

    /// Acute (7-day) ÷ chronic (28-day) load. About 0.8–1.3 builds fitness safely.
    static func ratio(_ days: [BodyDay], strength: [StrengthSession] = []) -> Double? {
        let s = series(days, strength: strength)
        guard s.count >= 14 else { return nil }
        let acute = s.suffix(7).map(\.load).reduce(0, +) / 7
        let chronic = s.suffix(28).map(\.load).reduce(0, +) / Double(min(28, s.count))
        return chronic > 1 ? acute / chronic : nil
    }

    static func status(_ r: Double?) -> (String, Color) {
        guard let r else { return ("Learning your normal", .gray) }
        if r < 0.8 { return ("Easing off: losing a little fitness", .blue) }
        if r <= 1.3 { return ("Building well", .green) }
        if r <= 1.5 { return ("Pushing hard: watch recovery", .orange) }
        return ("Too much too soon: injury risk is up", .red)
    }
}

struct CardioLoadCard: View {
    let days: [BodyDay]
    var body: some View {
        let strength = StrengthStore.sessions
        let series = Array(CardioLoad.series(days, strength: strength).suffix(42))
        let r = CardioLoad.ratio(days, strength: strength)
        let (label, color) = CardioLoad.status(r)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Training load", systemImage: "chart.line.uptrend.xyaxis").font(DS.Font.headline).foregroundStyle(BodyStyle.swell)
                Spacer()
                if let r { Text(String(format: "%.2f", r)).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(color) }
            }
            Text(label).font(.callout.weight(.semibold)).foregroundStyle(color)
            if series.count >= 7 {
                Chart(series) { p in
                    BarMark(x: .value("Day", p.day, unit: .day), y: .value("Load", p.load)).foregroundStyle(BodyStyle.swell.opacity(0.35))
                    LineMark(x: .value("Day", p.day, unit: .day), y: .value("Fitness", p.fitness), series: .value("Line", "Fitness"))
                        .foregroundStyle(.blue).interpolationMethod(.monotone)
                    LineMark(x: .value("Day", p.day, unit: .day), y: .value("Fatigue", p.fatigue), series: .value("Line", "Fatigue"))
                        .foregroundStyle(.orange).interpolationMethod(.monotone)
                }
                .frame(height: 150)
            }
            Text("Bars are each day's load (heart-rate effort plus strength). Blue is fitness (6 weeks), orange is fatigue (1 week). Fitness rising while fatigue stays near it is the sweet spot.")
                .font(.caption2).foregroundStyle(DS.Palette.inkSoft)
        }
        .bodyCard()
    }
}

// MARK: - Cardio charts: heart-rate recovery and VO₂ max

struct CardioChartsView: View {
    @State private var engine = BodyEngine.shared
    @State private var hrr: [BodyPoint] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                CardioLoadCard(days: engine.days)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Heart-rate recovery", systemImage: "heart.circle.fill").font(DS.Font.headline).foregroundStyle(.pink)
                    if hrr.count >= 2 {
                        Chart(hrr) { p in
                            LineMark(x: .value("Day", p.day, unit: .day), y: .value("Drop", p.v)).foregroundStyle(.pink.gradient).interpolationMethod(.catmullRom)
                            PointMark(x: .value("Day", p.day, unit: .day), y: .value("Drop", p.v)).foregroundStyle(.pink)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 160)
                        Text("How many beats per minute your heart rate falls in the first minute after a workout. Bigger is fitter; above about 20 is good.")
                            .font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                    } else {
                        Text(loaded ? "Shows after a few Apple Watch workouts that end with a cooldown." : "Reading Apple Health…")
                            .font(.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
                .bodyCard()
                NavigationLink { LazyView(BodyMetricDetailView(metric: .vo2)) } label: {
                    BodyMetricTile(metric: .vo2, day: engine.today, days: engine.days)
                }
                .buttonStyle(.plain)
                NavigationLink { LazyView(BodyMetricDetailView(metric: .rhr)) } label: {
                    BodyMetricTile(metric: .rhr, day: engine.today, days: engine.days)
                }
                .buttonStyle(.plain)
            }
            .padding(DS.Space.m)
        }
        .background(DS.Palette.canvas)
        .navigationTitle("Cardio")
        .task {
            hrr = await HealthExtras.heartRateRecovery(days: 120)
            loaded = true
        }
    }
}

extension HealthExtras {
    static let cardioTypes: Set<HKObjectType> = [HKQuantityType(.heartRateRecoveryOneMinute), HKQuantityType(.height), HKQuantityType(.stepCount),
                                                 HKQuantityType(.bloodPressureSystolic), HKQuantityType(.bloodPressureDiastolic)]

    /// One-minute heart-rate recovery after workouts (beats per minute dropped).
    static func heartRateRecovery(days: Int) async -> [BodyPoint] {
        guard BodyHealth.available else { return [] }
        try? await BodyHealth.store.requestAuthorization(toShare: [], read: cardioTypes)
        let p = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-Double(days) * 86_400), end: Date())
        let d = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(.heartRateRecoveryOneMinute), predicate: p)],
                                        sortDescriptors: [SortDescriptor(\.startDate)])
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return ((try? await d.result(for: BodyHealth.store)) ?? []).map { BodyPoint(day: $0.startDate, v: $0.quantity.doubleValue(for: bpm)) }
    }

    /// Daily step averages over the last `days`, height (m) and the latest blood pressure, for Biological Age.
    static func ageInputs(days: Int = 30) async -> (steps: Double?, heightM: Double?, systolic: Double?) {
        guard BodyHealth.available else { return (nil, nil, nil) }
        try? await BodyHealth.store.requestAuthorization(toShare: [], read: cardioTypes)
        let start = Calendar.current.startOfDay(for: Date().addingTimeInterval(-Double(days) * 86_400))
        let p = HKQuery.predicateForSamples(withStart: start, end: Date())
        let stepsQ = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: HKQuantityType(.stepCount), predicate: p), options: .cumulativeSum)
        let total = (try? await stepsQ.result(for: BodyHealth.store))?.sumQuantity()?.doubleValue(for: .count())
        func latest(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit) async -> Double? {
            let q = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(id))], sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: 1)
            return (try? await q.result(for: BodyHealth.store))?.first?.quantity.doubleValue(for: unit)
        }
        let height = await latest(.height, .meter())
        var sys = await latest(.bloodPressureSystolic, .millimeterOfMercury())
        if sys == nil, let manual = BloodPressure.all.last { sys = Double(manual.systolic) }
        return (total.map { $0 / Double(days) }, height, sys)
    }
}

// MARK: - Muscle freshness

struct MuscleFreshnessView: View {
    @State private var engine = BodyEngine.shared

    var body: some View {
        let strength = StrengthStore.fatigue()
        let cardio = BodyMapData.cardioLoad(days: engine.days)
        List {
            Section {
                KitIntro(icon: "figure.stand", color: BodyStyle.swell, text: "Muscle freshness. How recovered each muscle is, from your strength sessions and your workouts. Fresh muscles are ready for hard work; tired ones do better with an easy day or a different body part.")
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section {
                ForEach(Muscle.allCases) { m in
                    let tired = max(strength[m] ?? 0, m.regions.map { cardio[$0] ?? 0 }.max() ?? 0)
                    let fresh = Int(((1 - tired) * 100).rounded())
                    HStack {
                        Text(m.name)
                        Spacer()
                        ProgressView(value: Double(fresh), total: 100).tint(fresh >= 80 ? .green : fresh >= 50 ? .yellow : .orange).frame(width: 110)
                        Text("\(fresh)%").monospacedDigit().font(.caption.weight(.semibold)).frame(width: 40, alignment: .trailing)
                    }
                }
            } footer: { Text("Fresh again after about 2–3 days of rest. Sore spots you log on the body map count too.") }
            Section { NavigationLink { LazyView(BodyMapView()) } label: { Label("See it on the body map", systemImage: "figure.stand") } }
        }
        .navigationTitle("Muscle freshness")
    }
}
