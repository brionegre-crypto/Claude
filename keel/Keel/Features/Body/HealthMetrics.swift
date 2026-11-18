import SwiftUI
import HealthKit
import Charts

// MARK: - Every Apple Health metric, in one place
//
// Body's scores use a handful of measurements. This screen shows everything else Apple Health keeps: heart,
// activity, body measurements, vital signs, walking and mobility, running form, hearing and nutrition. Each has
// its latest value, a 30-day chart, how it's trending, and a plain-language note on what it means.
// Pin the ones you care about to the top. Metrics with no data are hidden unless you ask to see them.

struct HealthMetric: Identifiable, Hashable {
    enum Agg { case sum, average, latest }
    let id: String
    let name: String
    let category: String
    let type: HKQuantityTypeIdentifier
    let agg: Agg
    let unit: () -> HKUnit
    let unitLabel: () -> String
    var scale: Double = 1             // e.g. fractions shown as percent
    var decimals = 0
    var higherIsBetter: Bool? = nil
    let about: String

    static func == (a: HealthMetric, b: HealthMetric) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    func format(_ v: Double) -> String {
        (v * scale).formatted(.number.precision(.fractionLength(decimals)))
    }
}

enum HealthMetricCatalog {
    private static var metric: Bool { Locale.current.measurementSystem == .metric }
    private static var us: Bool { Locale.current.measurementSystem == .us }
    private static let bpm = { HKUnit.count().unitDivided(by: .minute()) }
    private static let kcal = { HKUnit.kilocalorie() }
    private static func distance() -> HKUnit { metric ? .meterUnit(with: .kilo) : .mile() }
    private static func distanceLabel() -> String { metric ? "km" : "mi" }
    private static func mass() -> HKUnit { metric ? .gramUnit(with: .kilo) : .pound() }
    private static func massLabel() -> String { metric ? "kg" : "lb" }

    static let categories = ["Heart", "Activity", "Body", "Vitals", "Walking & mobility", "Running", "Hearing", "Nutrition"]

    static let all: [HealthMetric] = [
        // Heart
        .init(id: "hr", name: "Heart rate", category: "Heart", type: .heartRate, agg: .average, unit: bpm, unitLabel: { "bpm" },
              about: "Your average heart rate across the day. It rises with activity, stress, caffeine and illness."),
        .init(id: "rhr", name: "Resting heart rate", category: "Heart", type: .restingHeartRate, agg: .average, unit: bpm, unitLabel: { "bpm" }, higherIsBetter: false,
              about: "Your heart rate at rest. Lower usually means better fitness; a jump of 5+ bpm can mean poor sleep, stress or getting sick."),
        .init(id: "walkhr", name: "Walking heart rate", category: "Heart", type: .walkingHeartRateAverage, agg: .average, unit: bpm, unitLabel: { "bpm" }, higherIsBetter: false,
              about: "Your average heart rate while walking. It drops as your fitness improves."),
        .init(id: "hrv", name: "Heart rate variability", category: "Heart", type: .heartRateVariabilitySDNN, agg: .average, unit: { .secondUnit(with: .milli) }, unitLabel: { "ms" }, higherIsBetter: true,
              about: "The small variation between heartbeats. Higher generally means your body is recovered and relaxed; compare with your own normal, not other people's."),
        .init(id: "hrrec", name: "Heart rate recovery", category: "Heart", type: .heartRateRecoveryOneMinute, agg: .average, unit: bpm, unitLabel: { "bpm" }, higherIsBetter: true,
              about: "How much your heart rate drops in the minute after hard exercise. A bigger drop is a sign of good fitness."),
        .init(id: "vo2", name: "Cardio fitness (VO₂ max)", category: "Heart", type: .vo2Max, agg: .latest, unit: { HKUnit(from: "ml/kg*min") }, unitLabel: { "ml/kg/min" }, decimals: 1, higherIsBetter: true,
              about: "How well your body uses oxygen during exercise, estimated from outdoor walks, runs and hikes. One of the strongest signs of long-term health."),
        .init(id: "afib", name: "AFib history", category: "Heart", type: .atrialFibrillationBurden, agg: .latest, unit: { .percent() }, unitLabel: { "%" }, scale: 100, higherIsBetter: false,
              about: "If you've turned on AFib History, the share of time your Apple Watch saw signs of atrial fibrillation. Talk to your doctor about any reading."),
        // Activity
        .init(id: "steps", name: "Steps", category: "Activity", type: .stepCount, agg: .sum, unit: { .count() }, unitLabel: { "steps" }, higherIsBetter: true,
              about: "Steps each day. Around 7,000–10,000 a day is linked with better health, but any increase helps."),
        .init(id: "dist", name: "Walking + running distance", category: "Activity", type: .distanceWalkingRunning, agg: .sum, unit: distance, unitLabel: distanceLabel, decimals: 1, higherIsBetter: true,
              about: "How far you walked and ran each day."),
        .init(id: "flights", name: "Flights climbed", category: "Activity", type: .flightsClimbed, agg: .sum, unit: { .count() }, unitLabel: { "floors" }, higherIsBetter: true,
              about: "Floors climbed (about 3 m / 10 ft each). Stairs are great everyday exercise."),
        .init(id: "active", name: "Active energy", category: "Activity", type: .activeEnergyBurned, agg: .sum, unit: kcal, unitLabel: { "kcal" }, higherIsBetter: true,
              about: "Calories burned by moving, on top of what your body uses at rest."),
        .init(id: "resting", name: "Resting energy", category: "Activity", type: .basalEnergyBurned, agg: .sum, unit: kcal, unitLabel: { "kcal" },
              about: "Calories your body uses just to keep running: breathing, thinking, keeping warm."),
        .init(id: "exercise", name: "Exercise minutes", category: "Activity", type: .appleExerciseTime, agg: .sum, unit: { .minute() }, unitLabel: { "min" }, higherIsBetter: true,
              about: "Minutes of brisk activity or more. 150 a week is the usual guideline."),
        .init(id: "stand", name: "Stand minutes", category: "Activity", type: .appleStandTime, agg: .sum, unit: { .minute() }, unitLabel: { "min" }, higherIsBetter: true,
              about: "Minutes you stood and moved. Breaking up sitting matters even if you exercise."),
        .init(id: "effort", name: "Physical effort", category: "Activity", type: .physicalEffort, agg: .average, unit: { HKUnit.kilocalorie().unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .hour())) }, unitLabel: { "MET" }, decimals: 1,
              about: "How intense your activity was, in METs: 1 is sitting still, 3–6 is moderate, above 6 is vigorous."),
        .init(id: "daylight", name: "Time in daylight", category: "Activity", type: .timeInDaylight, agg: .sum, unit: { .minute() }, unitLabel: { "min" }, higherIsBetter: true,
              about: "Time outdoors in daylight. Morning light helps your sleep and mood."),
        .init(id: "cycle", name: "Cycling distance", category: "Activity", type: .distanceCycling, agg: .sum, unit: distance, unitLabel: distanceLabel, decimals: 1,
              about: "How far you cycled each day."),
        .init(id: "swim", name: "Swimming distance", category: "Activity", type: .distanceSwimming, agg: .sum, unit: { metric ? .meter() : .yard() }, unitLabel: { metric ? "m" : "yd" },
              about: "How far you swam each day."),
        // Body
        .init(id: "weight", name: "Weight", category: "Body", type: .bodyMass, agg: .latest, unit: mass, unitLabel: massLabel, decimals: 1,
              about: "Your latest weight. Day-to-day changes are mostly water; look at the weekly trend."),
        .init(id: "bmi", name: "Body mass index", category: "Body", type: .bodyMassIndex, agg: .latest, unit: { .count() }, unitLabel: { "BMI" }, decimals: 1,
              about: "Weight relative to height. A rough guide only: it can't tell muscle from fat."),
        .init(id: "fat", name: "Body fat", category: "Body", type: .bodyFatPercentage, agg: .latest, unit: { .percent() }, unitLabel: { "%" }, scale: 100, decimals: 1,
              about: "The share of your weight that's fat, from a smart scale or other app."),
        .init(id: "lean", name: "Lean body mass", category: "Body", type: .leanBodyMass, agg: .latest, unit: mass, unitLabel: massLabel, decimals: 1, higherIsBetter: true,
              about: "Everything that isn't fat: muscle, bone, organs and water. Strength training helps keep it up."),
        .init(id: "waist", name: "Waist", category: "Body", type: .waistCircumference, agg: .latest, unit: { metric ? .meterUnit(with: .centi) : .inch() }, unitLabel: { metric ? "cm" : "in" }, decimals: 1,
              about: "Waist measurement, a simple sign of belly fat that tracks heart health."),
        .init(id: "height", name: "Height", category: "Body", type: .height, agg: .latest, unit: { metric ? .meterUnit(with: .centi) : .inch() }, unitLabel: { metric ? "cm" : "in" },
              about: "Your height, used for BMI and calorie estimates."),
        // Vitals
        .init(id: "resp", name: "Respiratory rate", category: "Vitals", type: .respiratoryRate, agg: .average, unit: bpm, unitLabel: { "breaths/min" }, decimals: 1,
              about: "Breaths per minute while you sleep. It's usually steady; a rise can be an early sign of illness."),
        .init(id: "spo2", name: "Blood oxygen", category: "Vitals", type: .oxygenSaturation, agg: .average, unit: { .percent() }, unitLabel: { "%" }, scale: 100, higherIsBetter: true,
              about: "How much oxygen your blood carries. 95–100% is typical."),
        .init(id: "temp", name: "Body temperature", category: "Vitals", type: .bodyTemperature, agg: .latest, unit: { us ? .degreeFahrenheit() : .degreeCelsius() }, unitLabel: { us ? "°F" : "°C" }, decimals: 1,
              about: "Temperatures you've logged or measured."),
        .init(id: "wristtemp", name: "Sleeping wrist temperature", category: "Vitals", type: .appleSleepingWristTemperature, agg: .latest, unit: { us ? .degreeFahrenheit() : .degreeCelsius() }, unitLabel: { us ? "°F" : "°C" }, decimals: 2,
              about: "Your wrist temperature overnight. Changes from your normal can follow illness, alcohol or your cycle."),
        .init(id: "sys", name: "Blood pressure (systolic)", category: "Vitals", type: .bloodPressureSystolic, agg: .latest, unit: { .millimeterOfMercury() }, unitLabel: { "mmHg" }, higherIsBetter: false,
              about: "The top number: pressure when your heart beats. Under 120 is considered normal."),
        .init(id: "dia", name: "Blood pressure (diastolic)", category: "Vitals", type: .bloodPressureDiastolic, agg: .latest, unit: { .millimeterOfMercury() }, unitLabel: { "mmHg" }, higherIsBetter: false,
              about: "The bottom number: pressure between beats. Under 80 is considered normal."),
        .init(id: "glucose", name: "Blood glucose", category: "Vitals", type: .bloodGlucose, agg: .latest,
              unit: { us ? HKUnit(from: "mg/dL") : HKUnit.moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose).unitDivided(by: .liter()) },
              unitLabel: { us ? "mg/dL" : "mmol/L" }, decimals: 1,
              about: "Blood sugar from a meter or glucose monitor."),
        .init(id: "breathing", name: "Breathing disturbances", category: "Vitals", type: .appleSleepingBreathingDisturbances, agg: .average, unit: { .count() }, unitLabel: { "per hour" }, decimals: 1, higherIsBetter: false,
              about: "Interruptions to normal breathing while you sleep, from your Apple Watch. Consistently high readings are worth raising with a doctor."),
        // Walking & mobility
        .init(id: "wspeed", name: "Walking speed", category: "Walking & mobility", type: .walkingSpeed, agg: .average,
              unit: { metric ? HKUnit.meterUnit(with: .kilo).unitDivided(by: .hour()) : HKUnit.mile().unitDivided(by: .hour()) }, unitLabel: { metric ? "km/h" : "mph" }, decimals: 1, higherIsBetter: true,
              about: "How fast you usually walk. A steady pace is one of the best signs of mobility as you age."),
        .init(id: "wstep", name: "Step length", category: "Walking & mobility", type: .walkingStepLength, agg: .average, unit: { metric ? .meterUnit(with: .centi) : .inch() }, unitLabel: { metric ? "cm" : "in" },
              about: "The distance of each step while walking."),
        .init(id: "wdouble", name: "Double support time", category: "Walking & mobility", type: .walkingDoubleSupportPercentage, agg: .average, unit: { .percent() }, unitLabel: { "%" }, scale: 100, decimals: 1, higherIsBetter: false,
              about: "The share of each step with both feet on the ground. It rises when balance is less sure."),
        .init(id: "wasym", name: "Walking asymmetry", category: "Walking & mobility", type: .walkingAsymmetryPercentage, agg: .average, unit: { .percent() }, unitLabel: { "%" }, scale: 100, decimals: 1, higherIsBetter: false,
              about: "How uneven your steps are between left and right. A rise can follow an injury."),
        .init(id: "steady", name: "Walking steadiness", category: "Walking & mobility", type: .appleWalkingSteadiness, agg: .latest, unit: { .percent() }, unitLabel: { "%" }, scale: 100, higherIsBetter: true,
              about: "Your iPhone's estimate of how steady you are on your feet over time."),
        .init(id: "sixmin", name: "Six-minute walk", category: "Walking & mobility", type: .sixMinuteWalkTestDistance, agg: .latest, unit: { metric ? .meter() : .yard() }, unitLabel: { metric ? "m" : "yd" }, higherIsBetter: true,
              about: "How far you could walk in six minutes, estimated from your everyday walking. A standard measure of fitness."),
        .init(id: "stairup", name: "Stair speed: up", category: "Walking & mobility", type: .stairAscentSpeed, agg: .average, unit: { HKUnit.meter().unitDivided(by: .second()) }, unitLabel: { "m/s" }, decimals: 2, higherIsBetter: true,
              about: "How quickly you climb stairs."),
        .init(id: "stairdown", name: "Stair speed: down", category: "Walking & mobility", type: .stairDescentSpeed, agg: .average, unit: { HKUnit.meter().unitDivided(by: .second()) }, unitLabel: { "m/s" }, decimals: 2, higherIsBetter: true,
              about: "How quickly you go down stairs."),
        // Running
        .init(id: "rspeed", name: "Running speed", category: "Running", type: .runningSpeed, agg: .average,
              unit: { metric ? HKUnit.meterUnit(with: .kilo).unitDivided(by: .hour()) : HKUnit.mile().unitDivided(by: .hour()) }, unitLabel: { metric ? "km/h" : "mph" }, decimals: 1, higherIsBetter: true,
              about: "Your average speed while running."),
        .init(id: "rpower", name: "Running power", category: "Running", type: .runningPower, agg: .average, unit: { .watt() }, unitLabel: { "W" },
              about: "How much power you put out while running, from your Apple Watch."),
        .init(id: "rstride", name: "Stride length", category: "Running", type: .runningStrideLength, agg: .average, unit: { .meter() }, unitLabel: { "m" }, decimals: 2,
              about: "The distance covered by each running stride."),
        .init(id: "rvert", name: "Vertical oscillation", category: "Running", type: .runningVerticalOscillation, agg: .average, unit: { .meterUnit(with: .centi) }, unitLabel: { "cm" }, decimals: 1, higherIsBetter: false,
              about: "How much you bounce up and down while running. Less bounce usually means more efficient running."),
        .init(id: "rground", name: "Ground contact time", category: "Running", type: .runningGroundContactTime, agg: .average, unit: { .secondUnit(with: .milli) }, unitLabel: { "ms" }, higherIsBetter: false,
              about: "How long each foot stays on the ground per step. Shorter is generally more efficient."),
        // Hearing
        .init(id: "envaudio", name: "Environmental sound", category: "Hearing", type: .environmentalAudioExposure, agg: .average, unit: { .decibelAWeightedSoundPressureLevel() }, unitLabel: { "dB" }, higherIsBetter: false,
              about: "How loud your surroundings were. Long periods above 80 dB can affect hearing over time."),
        .init(id: "headphone", name: "Headphone audio", category: "Hearing", type: .headphoneAudioExposure, agg: .average, unit: { .decibelAWeightedSoundPressureLevel() }, unitLabel: { "dB" }, higherIsBetter: false,
              about: "How loud your headphones were. Keeping under 80 dB protects your hearing."),
        // Nutrition
        .init(id: "water", name: "Water", category: "Nutrition", type: .dietaryWater, agg: .sum, unit: { metric ? .literUnit(with: .milli) : .fluidOunceUS() }, unitLabel: { metric ? "mL" : "fl oz" }, higherIsBetter: true,
              about: "Water you logged, here or in another app."),
        .init(id: "eaten", name: "Calories eaten", category: "Nutrition", type: .dietaryEnergyConsumed, agg: .sum, unit: kcal, unitLabel: { "kcal" },
              about: "Energy from food you logged."),
        .init(id: "protein", name: "Protein", category: "Nutrition", type: .dietaryProtein, agg: .sum, unit: { .gram() }, unitLabel: { "g" }, higherIsBetter: true,
              about: "Protein you logged. It helps you keep and build muscle."),
        .init(id: "caffeine", name: "Caffeine", category: "Nutrition", type: .dietaryCaffeine, agg: .sum, unit: { .gramUnit(with: .milli) }, unitLabel: { "mg" }, higherIsBetter: false,
              about: "Caffeine you logged. Most adults do well under 400 mg a day, and none after mid-afternoon helps sleep."),
    ]

    static var readTypes: Set<HKObjectType> { Set(all.map { HKQuantityType($0.type) }) }
}

/// Daily values for a metric (newest last), read from Apple Health and kept for a few minutes.
@MainActor @Observable
final class HealthMetricStore {
    static let shared = HealthMetricStore()
    struct Series { var days: [(date: Date, value: Double)]; var latest: Double? }
    private(set) var series: [String: Series] = [:]
    private(set) var loadedAt: Date?
    private(set) var loading = false
    private let store = HKHealthStore()
    static let askedKey = "health.metrics.asked.v1"

    func load(days: Int = 90, force: Bool = false) async {
        guard HKHealthStore.isHealthDataAvailable(), !loading else { return }
        if !force, let at = loadedAt, Date().timeIntervalSince(at) < 300 { return }
        loading = true
        defer { loading = false }
        if !UserDefaults.standard.bool(forKey: Self.askedKey) {
            // Asks only for the measurements Keel hasn't asked about before.
            _ = try? await store.requestAuthorization(toShare: [], read: HealthMetricCatalog.readTypes)
            UserDefaults.standard.set(true, forKey: Self.askedKey)
        }
        let cal = Calendar.current
        let end = Date()
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: end)) ?? end
        var out: [String: Series] = [:]
        await withTaskGroup(of: (String, Series?).self) { group in
            for m in HealthMetricCatalog.all {
                let unit = m.unit()
                group.addTask { [store] in (m.id, await Self.read(m, unit: unit, from: start, to: end, store: store)) }
            }
            for await (id, s) in group { if let s { out[id] = s } }
        }
        series = out
        loadedAt = Date()
    }

    nonisolated private static func read(_ m: HealthMetric, unit: HKUnit, from start: Date, to end: Date, store: HKHealthStore) async -> Series? {
        let type = HKQuantityType(m.type)
        let options: HKStatisticsOptions = m.agg == .sum ? .cumulativeSum : m.agg == .average ? .discreteAverage : .mostRecent
        let q = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: options, anchorDate: Calendar.current.startOfDay(for: end), intervalComponents: DateComponents(day: 1))
        guard let collection = try? await q.result(for: store) else { return nil }
        var days: [(date: Date, value: Double)] = []
        collection.enumerateStatistics(from: start, to: end) { s, _ in
            let qty: HKQuantity? = switch m.agg {
            case .sum: s.sumQuantity()
            case .average: s.averageQuantity()
            case .latest: s.mostRecentQuantity()
            }
            if let qty, qty.is(compatibleWith: unit) { days.append((date: s.startDate, value: qty.doubleValue(for: unit))) }
        }
        guard !days.isEmpty else { return nil }
        return Series(days: days, latest: days.last?.value)
    }
}

// MARK: - Screens

struct HealthMetricsView: View {
    @State private var data = HealthMetricStore.shared
    @AppStorage("health.metrics.pinned") private var pinnedRaw = "steps,rhr,hrv,vo2"
    @AppStorage("health.metrics.showEmpty") private var showEmpty = false
    @AppStorage("health.metrics.hidden") private var hiddenRaw = ""
    @State private var search = ""

    private var pinned: [String] { pinnedRaw.split(separator: ",").map(String.init) }
    private var hidden: Set<String> { Set(hiddenRaw.split(separator: ",").map(String.init)) }

    private func visible(_ m: HealthMetric) -> Bool {
        (showEmpty || data.series[m.id] != nil) && (search.isEmpty || m.name.localizedCaseInsensitiveContains(search) || m.category.localizedCaseInsensitiveContains(search))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                KitIntro(icon: "heart.text.clipboard", color: .red, text: "Everything Apple Health measures, in one place: heart, activity, body, vital signs, walking, running, hearing and nutrition. Each shows today's value, your 30-day trend and what it means. Long-press any metric to pin it to the top.")
                let pins = pinned.compactMap { id in HealthMetricCatalog.all.first { $0.id == id } }.filter(visible)
                if !pins.isEmpty { section("Pinned", pins) }
                ForEach(HealthMetricCatalog.categories.filter { !hidden.contains($0) }, id: \.self) { cat in
                    let ms = HealthMetricCatalog.all.filter { $0.category == cat && !pinned.contains($0.id) && visible($0) }
                    if !ms.isEmpty { section(cat, ms) }
                }
                if data.series.isEmpty && !data.loading {
                    ContentUnavailableView("No Health data yet", systemImage: "heart.slash",
                                           description: Text("Allow Keel to read Health data (Settings → Health → Data Access & Devices → Keel), or wear your Apple Watch for a day."))
                }
                if data.loading { ProgressView().frame(maxWidth: .infinity) }
            }
            .padding(DS.Space.m)
        }
        .premiumBackground(.red)
        .navigationTitle("Health metrics")
        .searchable(text: $search, prompt: "Search metrics")
        .refreshable { await data.load(force: true) }
        .task { await data.load() }
        .toolbar {
            Menu {
                Toggle("Show metrics with no data", isOn: $showEmpty)
                Section("Categories") {
                    ForEach(HealthMetricCatalog.categories, id: \.self) { c in
                        Toggle(c, isOn: Binding(get: { !hidden.contains(c) }, set: { on in
                            var h = hidden
                            if on { h.remove(c) } else { h.insert(c) }
                            hiddenRaw = h.sorted().joined(separator: ",")
                        }))
                    }
                }
            } label: { Image(systemName: "slider.horizontal.3") }
            .accessibilityLabel("Customize metrics")
        }
    }

    private func section(_ title: String, _ ms: [HealthMetric]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(DS.Font.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                ForEach(ms) { m in
                    NavigationLink { HealthMetricDetail(metric: m) } label: { HealthMetricCard(metric: m, series: data.series[m.id]) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(pinned.contains(m.id) ? "Unpin" : "Pin to top", systemImage: pinned.contains(m.id) ? "pin.slash" : "pin") {
                                var p = pinned
                                if let i = p.firstIndex(of: m.id) { p.remove(at: i) } else { p.append(m.id) }
                                pinnedRaw = p.joined(separator: ",")
                            }
                        }
                }
            }
        }
    }
}

struct HealthMetricCard: View {
    let metric: HealthMetric
    let series: HealthMetricStore.Series?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(metric.name).font(.caption.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
            if let s = series, let v = s.latest {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(metric.format(v)).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(DS.Palette.ink)
                    Text(metric.unitLabel()).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                }
                trend(s)
                Chart(s.days.suffix(30), id: \.date) { d in
                    LineMark(x: .value("Day", d.date), y: .value("Value", d.value * metric.scale))
                        .interpolationMethod(.catmullRom).foregroundStyle(.red.opacity(0.75))
                }
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .frame(height: 34)
            } else {
                Text("No data").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                Spacer(minLength: 34)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.elevated, in: .rect(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder private func trend(_ s: HealthMetricStore.Series) -> some View {
        if let t = HealthMetricTrend.weekOverWeek(s) {
            let good = metric.higherIsBetter.map { $0 == (t > 0) }
            Label("\(t > 0 ? "+" : "")\(Int((t * 100).rounded()))% vs last week", systemImage: t > 0 ? "arrow.up.right" : t < 0 ? "arrow.down.right" : "arrow.right")
                .font(.caption2)
                .foregroundStyle(abs(t) < 0.02 ? DS.Palette.inkSoft : good == nil ? DS.Palette.inkSoft : good! ? .green : .orange)
        }
    }
}

enum HealthMetricTrend {
    /// Last 7 days' average against the 7 before (nil without enough data).
    static func weekOverWeek(_ s: HealthMetricStore.Series) -> Double? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let w1 = cal.date(byAdding: .day, value: -7, to: today), let w2 = cal.date(byAdding: .day, value: -14, to: today) else { return nil }
        let recent = s.days.filter { $0.date >= w1 }.map(\.value)
        let before = s.days.filter { $0.date >= w2 && $0.date < w1 }.map(\.value)
        guard recent.count >= 2, before.count >= 2 else { return nil }
        let a = recent.reduce(0, +) / Double(recent.count), b = before.reduce(0, +) / Double(before.count)
        guard b != 0 else { return nil }
        return (a - b) / abs(b)
    }
}

struct HealthMetricDetail: View {
    let metric: HealthMetric
    @State private var data = HealthMetricStore.shared
    @State private var range = 30

    var body: some View {
        let points = Array((data.series[metric.id]?.days ?? []).suffix(range))
        let values = points.map { $0.value * metric.scale }
        List {
            Section {
                Picker("Range", selection: $range) { Text("7 days").tag(7); Text("30 days").tag(30); Text("90 days").tag(90) }
                    .pickerStyle(.segmented)
                if points.isEmpty {
                    Text("No \(metric.name.lowercased()) in Apple Health for this period.").foregroundStyle(DS.Palette.inkSoft)
                } else {
                    Chart(points, id: \.date) { d in
                        if metric.agg == .sum {
                            BarMark(x: .value("Day", d.date, unit: .day), y: .value(metric.name, d.value * metric.scale)).foregroundStyle(.red.opacity(0.7))
                        } else {
                            LineMark(x: .value("Day", d.date), y: .value(metric.name, d.value * metric.scale)).interpolationMethod(.catmullRom).foregroundStyle(.red)
                            PointMark(x: .value("Day", d.date), y: .value(metric.name, d.value * metric.scale)).foregroundStyle(.red).symbolSize(14)
                        }
                    }
                    .frame(height: 200)
                }
            }
            if !values.isEmpty {
                Section("This period") {
                    LabeledContent("Average", value: "\(metric.format(values.reduce(0, +) / Double(values.count) / metric.scale)) \(metric.unitLabel())")
                    LabeledContent("Lowest", value: "\(metric.format((values.min() ?? 0) / metric.scale)) \(metric.unitLabel())")
                    LabeledContent("Highest", value: "\(metric.format((values.max() ?? 0) / metric.scale)) \(metric.unitLabel())")
                    if metric.agg == .sum { LabeledContent("Total", value: "\(metric.format(values.reduce(0, +) / metric.scale)) \(metric.unitLabel())") }
                }
            }
            Section("What it means") {
                Text(metric.about)
                if let g = MetricGuides.guide(MetricGuides.healthGuideId(metric.id)) {
                    NavigationLink { MetricGuideView(guide: g) } label: {
                        Label("How it's tracked, what's typical, how to improve it", systemImage: "book.pages")
                    }
                }
            }
        }
        .navigationTitle(metric.name)
        .task { await data.load() }
    }
}
