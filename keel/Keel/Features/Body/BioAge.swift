import SwiftUI
import Charts
import HealthKit

// MARK: - Biological age: how old your body acts, from fitness, heart, sleep, activity, weight, blood pressure and lab results

struct BioFactor: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let value: String
    let years: Double          // + older, − younger
    let tip: String
}

struct BioAgeResult: Hashable, Codable {
    let age: Double             // your real age
    let bioAge: Double
    let factors: [BioFactor]
    let confidence: Int         // 0–100: how much data went in
}

struct BioAgeInputs: Codable {
    var age: Double
    var female = false
    var vo2: Double?
    var rhr: Double?
    var hrv: Double?
    var sleepHours: Double?
    var steps: Double?
    var bmi: Double?
    var systolic: Double?
    var a1c: Double?
    var ldl: Double?
    var crp: Double?
}

enum BioAge {
    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }

    /// A transparent, research-informed estimate (not a medical test): each factor adds or takes off years.
    static func estimate(_ x: BioAgeInputs) -> BioAgeResult {
        var f: [BioFactor] = []
        var weight = 0.0
        if let v = x.vo2 {
            let expected = (x.female ? 40 : 45) - 0.3 * max(0, x.age - 25)
            let y = clamp((expected - v) * 0.4, -6, 6)
            f.append(BioFactor(id: "vo2", name: "Cardio fitness (VO₂ max)", value: String(format: "%.1f", v), years: y,
                               tip: "Two or three sessions a week that get you properly out of breath raise VO₂ max fastest."))
            weight += 30
        }
        if let v = x.rhr {
            f.append(BioFactor(id: "rhr", name: "Resting heart rate", value: "\(Int(v)) bpm", years: clamp((v - 60) * 0.15, -3, 4),
                               tip: "Regular easy cardio, good sleep and less alcohol lower resting heart rate."))
            weight += 15
        }
        if let v = x.hrv {
            let expected = max(20, 62 - 0.6 * max(0, x.age - 25))
            f.append(BioFactor(id: "hrv", name: "Heart rate variability", value: "\(Int(v)) ms", years: clamp((expected - v) * 0.08, -3, 3),
                               tip: "A regular bedtime, stress breaks and fewer late drinks lift HRV."))
            weight += 15
        }
        if let v = x.sleepHours {
            let off = abs(7.5 - v)
            f.append(BioFactor(id: "sleep", name: "Sleep", value: String(format: "%.1f h", v), years: off <= 0.5 ? -0.5 : clamp(off, 0, 3),
                               tip: "7–8 hours on a steady schedule is the target."))
            weight += 10
        }
        if let v = x.steps {
            let y: Double = v < 5000 ? 2 : v < 7500 ? 1 : v >= 10000 ? -1 : 0
            f.append(BioFactor(id: "steps", name: "Daily steps", value: Int(v).formatted(), years: y, tip: "Every extra 1,000 steps a day helps, up to about 10,000."))
            weight += 10
        }
        if let v = x.bmi {
            let y: Double = v < 18.5 ? 1 : v < 25 ? 0 : v < 30 ? 1 : 3
            f.append(BioFactor(id: "bmi", name: "Body mass index", value: String(format: "%.1f", v), years: y, tip: "Strength training and protein at each meal help body composition."))
            weight += 8
        }
        if let v = x.systolic {
            let y: Double = v >= 140 ? 3 : v >= 130 ? 1.5 : v < 120 ? -0.5 : 0.5
            f.append(BioFactor(id: "bp", name: "Blood pressure (top number)", value: "\(Int(v))", years: y, tip: "Less salt, more movement and good sleep bring blood pressure down."))
            weight += 6
        }
        if let v = x.a1c {
            f.append(BioFactor(id: "a1c", name: "HbA1c (blood sugar)", value: String(format: "%.1f%%", v), years: v >= 6.5 ? 3 : v >= 5.7 ? 1.5 : -0.5,
                               tip: "Walking after meals and fewer refined carbs lower blood sugar."))
            weight += 3
        }
        if let v = x.ldl {
            f.append(BioFactor(id: "ldl", name: "LDL cholesterol", value: "\(Int(v))", years: v >= 160 ? 1.5 : v >= 130 ? 0.5 : -0.3, tip: "Fibre, oily fish and less saturated fat help LDL."))
            weight += 2
        }
        if let v = x.crp {
            f.append(BioFactor(id: "crp", name: "Inflammation (CRP)", value: String(format: "%.1f", v), years: v > 3 ? 1.5 : v < 1 ? -0.5 : 0, tip: "Sleep, movement and a mostly whole-food diet calm inflammation."))
            weight += 1
        }
        let total = clamp(f.reduce(0) { $0 + $1.years }, -15, 15)
        return BioAgeResult(age: x.age, bioAge: max(18, x.age + total), factors: f.sorted { $0.years > $1.years }, confidence: Int(min(100, weight)))
    }

    @MainActor static var lastInputs: BioAgeInputs?

    // Weekly history (one number per week, recorded on the first look each Monday or later).
    struct Snapshot: Codable, Hashable { var week: String; var bioAge: Double; var age: Double }
    static let historyKey = "body.bioage.history"
    static var history: [Snapshot] { get { LocalLog.load(historyKey) } set { LocalLog.save(Array(newValue.suffix(104)), historyKey) } }
    static func weekKey(_ d: Date = Date()) -> String {
        let c = Calendar(identifier: .iso8601).dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
        return "\(c.yearForWeekOfYear ?? 0)-W\(c.weekOfYear ?? 0)"
    }

    // The last answer, kept on this device so the card and page show it instantly; a fresh one is worked out
    // quietly behind it, at most every 20 minutes.
    private struct Cache: Codable { var at: Date; var result: BioAgeResult; var inputs: BioAgeInputs }
    private static let cacheKey = "body.bioage.cache"
    @MainActor private static var memo: Cache? = {
        UserDefaults.standard.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
    }()
    @MainActor private static var inFlight: Task<BioAgeResult?, Never>?

    /// The last result, straight away (no Apple Health reads).
    @MainActor static var cached: BioAgeResult? {
        if lastInputs == nil { lastInputs = memo?.inputs }
        return memo?.result
    }

    /// The cached answer when it's recent, otherwise a fresh one. Callers at the same moment share one read.
    @MainActor static func current(force: Bool = false) async -> BioAgeResult? {
        if !force, let m = memo, Date().timeIntervalSince(m.at) < 20 * 60 { lastInputs = lastInputs ?? m.inputs; return m.result }
        if let t = inFlight { return await t.value }
        let t = Task { @MainActor in await compute() }
        inFlight = t
        let r = await t.value
        inFlight = nil
        if let r, let x = lastInputs {
            memo = Cache(at: Date(), result: r, inputs: x)
            if let d = try? JSONEncoder().encode(memo) { UserDefaults.standard.set(d, forKey: cacheKey) }
        }
        return r ?? memo?.result
    }

    /// Gathers everything from Apple Health, Keel's 30-day body history and your lab results.
    /// The Apple Health reads run side by side, and only the few samples the estimate needs are fetched.
    @MainActor private static func compute() async -> BioAgeResult? {
        guard BodyHealth.available else { return nil }
        try? await BodyHealth.store.requestAuthorization(toShare: [], read: [HKCharacteristicType(.biologicalSex), HKCharacteristicType(.dateOfBirth)])
        guard let dob = try? BodyHealth.store.dateOfBirthComponents(), let birth = Calendar.current.date(from: dob) else { return nil }
        let age = Date().timeIntervalSince(birth) / (365.25 * 86_400)
        let days = BodyEngine.shared.days.suffix(30)
        func avg(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
        var x = BioAgeInputs(age: age)
        x.female = (try? BodyHealth.store.biologicalSex().biologicalSex) == .female
        x.vo2 = days.compactMap(\.vo2).last
        x.rhr = avg(days.compactMap(\.rhr))
        x.hrv = avg(days.compactMap(\.hrv))
        x.sleepHours = avg(days.filter(\.hasSleep).map { $0.asleep / 60 })
        async let extraQ = HealthExtras.ageInputs()
        async let weightQ = HealthExtras.latestWeightKg()
        let extra = await extraQ
        let weight = await weightQ
        x.steps = extra.steps
        x.systolic = extra.systolic
        if let w = weight, let h = extra.heightM, h > 1 { x.bmi = w / (h * h) }
        let labs = Biomarkers.latest()
        x.a1c = labs["a1c"]?.value
        x.ldl = labs["ldl"]?.value
        x.crp = labs["crp"]?.value
        let r = estimate(x)
        lastInputs = x
        var h = history
        if !h.contains(where: { $0.week == weekKey() }), r.confidence >= 30 {
            h.append(Snapshot(week: weekKey(), bioAge: r.bioAge, age: r.age)); history = h
        }
        return r
    }
}

struct BioAgeCard: View {
    @State private var result: BioAgeResult? = BioAge.cached
    @State private var loaded = BioAge.cached != nil

    var body: some View {
        NavigationLink { LazyView(BioAgeView()) } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.purple.opacity(0.15)).frame(width: 60, height: 60)
                    Text(result.map { String(format: "%.0f", $0.bioAge) } ?? "–").font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(.purple)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Biological age").font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                    if let r = result {
                        let diff = r.bioAge - r.age
                        Text(abs(diff) < 0.5 ? "Right on your real age" : String(format: "%.1f years %@ than your real age", abs(diff), diff < 0 ? "younger" : "older"))
                            .font(DS.Font.caption).foregroundStyle(diff <= 0 ? DS.Palette.calm : .orange)
                    } else {
                        Text(loaded ? "Needs your birthday in Apple Health (Health → your picture → Health Details)." : "Working it out…")
                            .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            .bodyCard()
        }
        .buttonStyle(.plain)
        .task { result = await BioAge.current(); loaded = true }
    }
}

struct BioAgeView: View {
    @State private var result: BioAgeResult? = BioAge.cached
    @State private var loaded = BioAge.cached != nil

    var body: some View {
        List {
            Section {
                KitIntro(icon: "hourglass.circle.fill", color: .purple, text: "Biological age estimates how old your body acts, not how many birthdays you've had. It weighs cardio fitness most, then heart rate, heart rate variability, sleep, steps, weight, blood pressure and any lab results you've added. It updates as your data changes and saves one reading a week.")
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            if let r = result {
                Section {
                    HStack {
                        KitStat(value: String(format: "%.1f", r.bioAge), label: "biological age", color: .purple)
                        KitStat(value: String(format: "%.1f", r.age), label: "real age", color: DS.Palette.inkSoft)
                    }
                    Label("Confidence \(r.confidence)%: \(r.confidence >= 70 ? "plenty of data" : r.confidence >= 40 ? "some data missing" : "add more data for a firmer estimate")",
                          systemImage: "checkmark.shield").font(.caption)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                Section("What's moving it") {
                    ForEach(r.factors) { f in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(f.name)
                                Spacer()
                                Text(f.value).foregroundStyle(DS.Palette.inkSoft)
                                Text(String(format: "%+.1f y", f.years)).monospacedDigit().font(.callout.weight(.semibold))
                                    .foregroundStyle(f.years > 0.2 ? .orange : f.years < -0.2 ? DS.Palette.calm : DS.Palette.inkSoft)
                                    .frame(width: 64, alignment: .trailing)
                            }
                            if f.years > 0.2 { Text(f.tip).font(.caption).foregroundStyle(DS.Palette.inkSoft) }
                        }
                    }
                }
                if let best = r.factors.first(where: { $0.years > 0.2 }) {
                    Section("Biggest win") { Text("\(best.name): \(best.tip)").font(.callout) }
                }
                if let inputs = BioAge.lastInputs { BioAgeWhatIf(base: inputs) }
                if let pace = BioAge.pace() {
                    Section("Pace of aging") {
                        Text(String(format: "You're aging about %.2f years per year", pace)).font(.headline)
                            .foregroundStyle(pace <= 1 ? DS.Palette.calm : .orange)
                        Text(pace < 1 ? "Slower than the calendar: your habits are working." : "Faster than the calendar lately. The biggest win above is the place to start.")
                            .font(.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
                let h = BioAge.history
                if h.count >= 2 {
                    Section("By week") {
                        Chart(Array(h.enumerated()), id: \.offset) { i, s in
                            LineMark(x: .value("Week", i), y: .value("Bio age", s.bioAge)).foregroundStyle(.purple).interpolationMethod(.catmullRom)
                            LineMark(x: .value("Week", i), y: .value("Real age", s.age), series: .value("S", "real")).foregroundStyle(.gray.opacity(0.5))
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartXAxis(.hidden)
                        .frame(height: 160)
                    }
                }
                Section { NavigationLink { LazyView(HealthRecordsView()) } label: { Label("Add lab results for a sharper estimate", systemImage: "cross.vial") } }
            } else {
                Section { Text(loaded ? "Keel needs your birthday from Apple Health, and a few days of Apple Watch data." : "Working it out…").foregroundStyle(DS.Palette.inkSoft) }
            }
            Section { Text("An estimate for everyday wellbeing, not a medical test.").font(.caption).foregroundStyle(DS.Palette.inkSoft) }
        }
        .navigationTitle("Biological age")
        .refreshable { result = await BioAge.current(force: true) }
        .task { result = await BioAge.current(); loaded = true }
    }
}
