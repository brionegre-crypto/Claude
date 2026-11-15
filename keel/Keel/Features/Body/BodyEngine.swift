import Foundation
import HealthKit
import UserNotifications
import WidgetKit

// MARK: - Body: Tide (how recovered you are), Swell (how hard your body worked), Anchor (how well you slept)
//
// Everything is worked out on this iPhone from Apple Health (Apple Watch data makes it much better).
// Nothing leaves the device. Scores are compared with YOUR normal (the last 30 days), not population averages.

struct BodyWorkout: Codable, Hashable, Identifiable {
    var id: Date { start }
    var name: String
    var start: Date
    var minutes: Int
    var kcal: Int?
    var swell: Int
}

struct BodyDay: Codable, Hashable, Identifiable {
    var day: Date                       // the calendar day you woke up on
    var id: Date { day }
    // Vitals
    var hrv: Double?                    // ms, overnight
    var rhr: Double?                    // resting heart rate, bpm
    var resp: Double?                   // breaths per minute, overnight
    var spo2: Double?                   // %, overnight
    var temp: Double?                   // °C, sleeping wrist temperature change from your baseline (Apple's value)
    var vo2: Double?                    // ml/kg/min, latest
    // Sleep (minutes)
    var asleep: Double = 0
    var inBed: Double = 0
    var deep: Double = 0
    var rem: Double = 0
    var core: Double = 0
    var awake: Double = 0
    var bedtime: Date?
    var wake: Date?
    // Effort
    var trimp: Double = 0
    var swell: Int = 0
    var stress: [Int?] = []             // 8 AM … 10 PM, one per hour: 0 calm, 1 some, 2 high, nil no data
    var workouts: [BodyWorkout] = []
    // Scores (filled in by BodyMath.score)
    var tide: Int?
    var anchor: Int?
    var need: Double?                   // hours of sleep you needed
    var tideNotes: [String] = []
    var calibrating = true

    var hasSleep: Bool { asleep >= 60 }
}

// MARK: - Raw samples (read in one go, then split into days)

struct BodyRaw {
    struct Q { var start: Date; var end: Date; var value: Double }
    struct S { var start: Date; var end: Date; var value: Int; var source: String }
    struct W { var start: Date; var end: Date; var name: String; var kcal: Double? }
    var hr: [Q] = [], hrv: [Q] = [], rhr: [Q] = [], resp: [Q] = [], spo2: [Q] = [], temp: [Q] = [], vo2: [Q] = []
    var sleep: [S] = []
    var workouts: [W] = []
}

/// Reads Apple Health. Kept off the main thread so screens never wait on it.
enum BodyHealth {
    static let store = HKHealthStore()
    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    static var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = [
            HKQuantityType(.heartRate), HKQuantityType(.heartRateVariabilitySDNN), HKQuantityType(.restingHeartRate),
            HKQuantityType(.respiratoryRate), HKQuantityType(.oxygenSaturation), HKQuantityType(.vo2Max),
            HKQuantityType(.activeEnergyBurned), HKCategoryType(.sleepAnalysis), HKObjectType.workoutType(),
            HKCharacteristicType(.dateOfBirth),
        ]
        s.insert(HKQuantityType(.appleSleepingWristTemperature))
        s.formUnion(HealthExtras.readTypes)        // steps, daylight, mindful minutes, weight, cycle
        return s
    }

    static func requestAccess() async -> Bool {
        guard available else { return false }
        do { try await store.requestAuthorization(toShare: [], read: readTypes); return true } catch { return false }
    }

    /// Your highest heart rate: from your birthday if Health has it, otherwise a typical adult value.
    static func maxHR() -> Double {
        let custom = UserDefaults.standard.integer(forKey: BodyPrefs.maxHRKey)
        if custom > 120 { return Double(custom) }
        if let dob = try? store.dateOfBirthComponents(), let y = dob.year {
            let age = Double(Calendar.current.component(.year, from: Date()) - y)
            if age > 10 && age < 100 { return 208 - 0.7 * age }
        }
        return 185
    }

    private static func quantities(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ p: NSPredicate) async -> [BodyRaw.Q] {
        let d = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(id), predicate: p)],
                                        sortDescriptors: [SortDescriptor(\.startDate)])
        return ((try? await d.result(for: store)) ?? []).map { BodyRaw.Q(start: $0.startDate, end: $0.endDate, value: $0.quantity.doubleValue(for: unit)) }
    }

    static func read(from start: Date, to end: Date) async -> BodyRaw {
        let p = HKQuery.predicateForSamples(withStart: start, end: end)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        var r = BodyRaw()
        async let hr = quantities(.heartRate, bpm, p)
        async let hrv = quantities(.heartRateVariabilitySDNN, .secondUnit(with: .milli), p)
        async let rhr = quantities(.restingHeartRate, bpm, p)
        async let resp = quantities(.respiratoryRate, bpm, p)
        async let spo2 = quantities(.oxygenSaturation, .percent(), p)
        async let temp = quantities(.appleSleepingWristTemperature, .degreeCelsius(), p)
        async let vo2 = quantities(.vo2Max, HKUnit(from: "ml/kg*min"), HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-120 * 86_400), end: end))
        r.hr = await hr; r.hrv = await hrv; r.rhr = await rhr; r.resp = await resp; r.spo2 = await spo2; r.temp = await temp; r.vo2 = await vo2
        let sd = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: p)], sortDescriptors: [SortDescriptor(\.startDate)])
        r.sleep = ((try? await sd.result(for: store)) ?? []).map { .init(start: $0.startDate, end: $0.endDate, value: $0.value, source: $0.sourceRevision.source.bundleIdentifier) }
        let wd = HKSampleQueryDescriptor(predicates: [.workout(p)], sortDescriptors: [SortDescriptor(\.startDate)])
        r.workouts = ((try? await wd.result(for: store)) ?? []).map { w in
            let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            return .init(start: w.startDate, end: w.endDate, name: BodyMath.workoutName(w.workoutActivityType.rawValue), kcal: kcal)
        }
        return r
    }
}

enum BodyPrefs {
    static let needKey = "body.sleepNeed"           // hours, default 8
    static let maxHRKey = "body.maxHR"              // 0 = automatic
    static let morningKey = "body.morningAlert"     // default on
    static let windDownKey = "body.windDown"        // default on
    static let journalKey = "body.journal"          // [yyyy-MM-dd: [tag]]
    static var sleepNeed: Double { let v = UserDefaults.standard.double(forKey: needKey); return v >= 5 ? v : 8 }
    static var morningOn: Bool { UserDefaults.standard.object(forKey: morningKey) as? Bool ?? true }
    static var windDownOn: Bool { UserDefaults.standard.object(forKey: windDownKey) as? Bool ?? true }
}

// MARK: - The math (pure, so it can be tested)

enum BodyMath {
    static func dayKey(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Sleep belongs to the morning you woke up on (a session ending at 7 AM counts for that day).
    static func sleepDay(forEnd end: Date) -> Date {
        Calendar.current.startOfDay(for: end.addingTimeInterval(9 * 3600))
    }

    static func workoutName(_ raw: UInt) -> String {
        switch raw {
        case 37: "Run"; case 52: "Walk"; case 13: "Cycle"; case 46: "Swim"; case 50: "Strength"; case 20: "Functional strength"
        case 63: "HIIT"; case 57: "Yoga"; case 35: "Rowing"; case 16: "Elliptical"; case 24: "Hike"; case 66: "Pilates"
        case 6: "Basketball"; case 41: "Soccer"; case 48: "Tennis"; case 14: "Dance"; case 73: "Mixed cardio"; case 80: "Cooldown"
        default: "Workout"
        }
    }

    /// Heart-rate effort: minutes in each zone (share of your max), weighted 1–5, summed (a TRIMP-style count).
    static func trimp(_ hr: [BodyRaw.Q], maxHR: Double, from: Date, to: Date) -> Double {
        let samples = hr.filter { $0.start >= from && $0.start < to }
        var total = 0.0
        for (i, s) in samples.enumerated() {
            let next = i + 1 < samples.count ? samples[i + 1].start : s.start.addingTimeInterval(60)
            let minutes = min(10, max(0, next.timeIntervalSince(s.start) / 60))
            let pct = s.value / maxHR
            let w: Double = pct >= 0.9 ? 5 : pct >= 0.8 ? 4 : pct >= 0.7 ? 3 : pct >= 0.6 ? 2 : pct >= 0.5 ? 1 : 0
            total += w * minutes
        }
        return total
    }

    /// 0–100 that rises quickly at first and levels off: an easy day ≈ 20–35, a solid workout day ≈ 55–75, a race ≈ 90.
    static func swell(_ trimp: Double) -> Int { Int((100 * (1 - exp(-trimp / 180))).rounded()) }

    /// Splits raw samples into days, oldest first.
    static func days(from raw: BodyRaw, start: Date, end: Date, maxHR: Double) -> [BodyDay] {
        let cal = Calendar.current
        var out: [BodyDay] = []
        var d = cal.startOfDay(for: start)
        // Sleep: per morning, the source that recorded the most sleep (Watch beats phone).
        let asleepCodes: Set<Int> = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        var sleepBy: [Date: [String: [BodyRaw.S]]] = [:]
        for s in raw.sleep { sleepBy[sleepDay(forEnd: s.end), default: [:]][s.source, default: []].append(s) }

        while d < end {
            let next = cal.date(byAdding: .day, value: 1, to: d) ?? d.addingTimeInterval(86_400)
            var b = BodyDay(day: d)
            if let bySource = sleepBy[d] {
                let best = bySource.values.max { a, b in
                    a.filter { asleepCodes.contains($0.value) }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
                        < b.filter { asleepCodes.contains($0.value) }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
                } ?? []
                for s in best {
                    let m = s.end.timeIntervalSince(s.start) / 60
                    switch HKCategoryValueSleepAnalysis(rawValue: s.value) ?? .inBed {
                    case .asleepDeep: b.deep += m; b.asleep += m
                    case .asleepREM: b.rem += m; b.asleep += m
                    case .asleepCore: b.core += m; b.asleep += m
                    case .asleepUnspecified: b.asleep += m
                    case .awake: b.awake += m
                    default: break
                    }
                }
                let asleepSamples = best.filter { asleepCodes.contains($0.value) }
                b.bedtime = asleepSamples.map(\.start).min()
                b.wake = asleepSamples.map(\.end).max()
                if let bt = b.bedtime, let w = b.wake { b.inBed = max(b.asleep + b.awake, w.timeIntervalSince(bt) / 60) }
            }
            // Overnight vitals: during sleep if we know it, otherwise midnight to 9 AM.
            let nightFrom = b.bedtime ?? d, nightTo = b.wake ?? d.addingTimeInterval(9 * 3600)
            func night(_ q: [BodyRaw.Q]) -> Double? {
                let v = q.filter { $0.start >= nightFrom && $0.start <= nightTo }.map(\.value)
                return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
            }
            b.hrv = night(raw.hrv)
            b.resp = night(raw.resp)
            b.spo2 = night(raw.spo2).map { $0 * 100 }
            let t = raw.temp.filter { sleepDay(forEnd: $0.end) == d }.map(\.value)
            b.temp = t.isEmpty ? nil : t.reduce(0, +) / Double(t.count)
            let r = raw.rhr.filter { $0.start >= d && $0.start < next }.map(\.value)
            b.rhr = r.isEmpty ? nil : r.reduce(0, +) / Double(r.count)
            b.vo2 = raw.vo2.last { $0.start < next }?.value
            // Effort
            b.trimp = trimp(raw.hr, maxHR: maxHR, from: d, to: next)
            b.swell = swell(b.trimp)
            b.workouts = raw.workouts.filter { $0.start >= d && $0.start < next }.map { w in
                BodyWorkout(name: w.name, start: w.start, minutes: Int(w.end.timeIntervalSince(w.start) / 60),
                            kcal: w.kcal.map { Int($0) }, swell: swell(trimp(raw.hr, maxHR: maxHR, from: w.start, to: w.end)))
            }
            // Stress: heart rate above your resting level while you're not working out, hour by hour (8 AM–10 PM).
            if let rest = b.rhr ?? r.first {
                b.stress = (8...22).map { h -> Int? in
                    guard let hs = cal.date(bySettingHour: h, minute: 0, second: 0, of: d) else { return nil }
                    let he = hs.addingTimeInterval(3600)
                    let vals = raw.hr.filter { q in q.start >= hs && q.start < he && !raw.workouts.contains { q.start >= $0.start && q.start <= $0.end } }.map(\.value)
                    guard vals.count >= 2 else { return nil }
                    let arousal = (vals.reduce(0, +) / Double(vals.count) - rest) / max(20, maxHR - rest)
                    return arousal < 0.12 ? 0 : arousal < 0.25 ? 1 : 2
                }
            }
            out.append(b)
            d = next
        }
        return out
    }

    private static func meanSD(_ v: [Double]) -> (Double, Double) {
        let m = v.reduce(0, +) / Double(v.count)
        let sd = sqrt(v.reduce(0) { $0 + pow($1 - m, 2) } / Double(max(1, v.count - 1)))
        return (m, sd)
    }

    private static func clockMinutes(_ d: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        var m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        if m < 12 * 60 { m += 24 * 60 }          // after-midnight bedtimes sort after evening ones
        return m
    }

    /// Extra sleep you need after a hard day.
    static func effortExtra(_ swell: Int) -> Double { min(0.75, max(0, Double(swell - 40)) / 20 * 0.25) }

    /// Fills in Anchor, sleep need and Tide for every day, each compared with the 30 days before it.
    static func score(_ days: inout [BodyDay], base: Double) {
        for i in days.indices {
            let prior = Array(days[max(0, i - 30)..<i])
            var b = days[i]
            // Sleep need: your base, plus a little after a hard day, plus a third of recent sleep debt.
            let yesterdaySwell = i > 0 ? days[i - 1].swell : 0
            let debt = min(2, days[max(0, i - 3)..<i].filter(\.hasSleep).reduce(0) { $0 + max(0, base - $1.asleep / 60) })
            let need = base + effortExtra(yesterdaySwell) + debt / 3
            b.need = need
            if b.hasSleep {
                let duration = min(1, (b.asleep / 60) / need) * 55
                let eff = b.inBed > 0 ? b.asleep / b.inBed : 0.9
                let efficiency = min(1, max(0, (eff - 0.7) / 0.25)) * 15
                let staged = b.deep + b.rem + b.core > 0
                let restorative = staged ? min(1, ((b.deep + b.rem) / max(1, b.asleep)) / 0.40) * 15 : 10
                var consistency = 10.0
                let bedtimes = prior.suffix(7).compactMap(\.bedtime).map(clockMinutes)
                if bedtimes.count >= 3, let bt = b.bedtime {
                    let median = bedtimes.sorted()[bedtimes.count / 2]
                    consistency = (1 - min(1, abs(clockMinutes(bt) - median) / 90)) * 15
                } else { consistency = 12 }
                b.anchor = Int(min(100, max(1, duration + efficiency + restorative + consistency)).rounded())
            }
            // Tide: overnight HRV and resting heart rate against your own normal, plus how well you slept.
            var notes: [String] = []
            let hrvs = prior.compactMap(\.hrv).filter { $0 > 5 }
            let rhrs = prior.compactMap(\.rhr)
            b.calibrating = hrvs.count < 5
            var tide = 55.0
            var have = false
            if let h = b.hrv, h > 5, hrvs.count >= 5 {
                let (m, sd) = meanSD(hrvs.map { log($0) })
                let z = max(-2.5, min(2.5, (log(h) - m) / max(0.08, sd)))
                tide += 15 * z; have = true
                let pct = Int(((h / exp(m)) - 1) * 100)
                notes.append("Heart rate variability \(Int(h)) ms, " + (abs(pct) < 4 ? "right at your normal" : "\(abs(pct))% \(pct > 0 ? "above" : "below") your normal"))
            }
            if let r = b.rhr, rhrs.count >= 5 {
                let (m, sd) = meanSD(rhrs)
                let z = max(-2.5, min(2.5, (r - m) / max(2, sd)))
                tide -= 9 * z; have = true
                let diff = Int((r - m).rounded())
                notes.append("Resting heart rate \(Int(r)) bpm, " + (abs(diff) < 2 ? "normal for you" : "\(abs(diff)) \(diff > 0 ? "higher" : "lower") than usual"))
            }
            if let a = b.anchor {
                tide += 0.3 * Double(a - 70); have = true
                notes.append("Sleep score \(a)")
            }
            let resps = prior.compactMap(\.resp)
            if let rr = b.resp, resps.count >= 5 {
                let (m, sd) = meanSD(resps)
                if (rr - m) / max(0.4, sd) > 2 { tide -= 8; notes.append("Breathing faster than usual overnight") }
            }
            if let t = b.temp, t > 0.5 { tide -= 8; notes.append(String(format: "Wrist temperature +%.1f°C", t)) }
            if let o = b.spo2, o < 93 { notes.append(String(format: "Blood oxygen %.0f%%", o)) }
            b.tide = have ? Int(min(100, max(1, tide)).rounded()) : nil
            b.tideNotes = notes
            days[i] = b
        }
    }

    /// How much Swell suits today's Tide.
    static func swellTarget(_ tide: Int?) -> ClosedRange<Int> {
        guard let t = tide else { return 30...60 }
        return t >= 67 ? 60...80 : t >= 34 ? 40...60 : 15...35
    }

    /// Tonight: how much sleep you need and when to go to bed to wake at your usual time.
    static func tonight(_ days: [BodyDay], base: Double, now: Date = Date()) -> (need: Double, bedtime: Date, wake: Date) {
        let cal = Calendar.current
        let today = days.last { cal.isDate($0.day, inSameDayAs: now) }
        let recent = days.suffix(4).filter(\.hasSleep)
        let debt = min(2, recent.reduce(0) { $0 + max(0, base - $1.asleep / 60) })
        let need = base + effortExtra(today?.swell ?? 0) + debt / 3
        let wakes = days.suffix(7).compactMap(\.wake).map { d -> Int in let c = cal.dateComponents([.hour, .minute], from: d); return (c.hour ?? 7) * 60 + (c.minute ?? 0) }.sorted()
        let wakeMin = wakes.isEmpty ? 7 * 60 : wakes[wakes.count / 2]
        // After midnight (before 4 AM), "tonight" means the wake-up later this morning.
        let tomorrow = cal.component(.hour, from: now) < 4 ? cal.startOfDay(for: now) : (cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now)
        let wake = cal.date(byAdding: .minute, value: wakeMin, to: tomorrow) ?? tomorrow
        let bed = wake.addingTimeInterval(-(need * 3600) - 15 * 60)      // ~15 minutes to fall asleep
        return (need, bed, wake)
    }

    /// For each habit you've logged: average next-morning Tide with it minus without it (at least 3 of each).
    static func habitImpact(journal: [String: [String]], days: [BodyDay]) -> [(tag: String, delta: Int, with: Int, without: Int)] {
        let cal = Calendar.current
        var tideByDay: [String: Int] = [:]
        for d in days { if let t = d.tide { tideByDay[dayKey(d.day)] = t } }
        let loggedDays = journal.keys.sorted()
        let tags = Set(journal.values.flatMap { $0 })
        var out: [(String, Int, Int, Int)] = []
        for tag in tags {
            var yes: [Int] = [], no: [Int] = []
            for k in loggedDays {
                guard let d = parse(k), let next = cal.date(byAdding: .day, value: 1, to: d), let t = tideByDay[dayKey(next)] else { continue }
                if journal[k]?.contains(tag) == true { yes.append(t) } else { no.append(t) }
            }
            guard yes.count >= 3, no.count >= 3 else { continue }
            let delta = Double(yes.reduce(0, +)) / Double(yes.count) - Double(no.reduce(0, +)) / Double(no.count)
            out.append((tag, Int(delta.rounded()), yes.count, no.count))
        }
        return out.sorted { abs($0.1) > abs($1.1) }.map { (tag: $0.0, delta: $0.1, with: $0.2, without: $0.3) }
    }

    static func parse(_ key: String) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    /// Hours of the day you're usually calmest (from the last two weeks), best first.
    static func calmHours(_ days: [BodyDay]) -> [Int] {
        var sum = [Int: Double](), n = [Int: Int]()
        for d in days.suffix(14) {
            for (i, v) in d.stress.enumerated() { if let v { sum[i + 8, default: 0] += Double(v); n[i + 8, default: 0] += 1 } }
        }
        return n.filter { $0.value >= 5 && (9...19).contains($0.key) }
            .map { (h: $0.key, avg: sum[$0.key, default: 0] / Double($0.value)) }
            .sorted { $0.avg < $1.avg }.prefix(3).map(\.h)
    }
}

// MARK: - Engine (cache, refresh, alerts, sharing with widgets and Watch)

@MainActor @Observable
final class BodyEngine {
    static let shared = BodyEngine()
    private(set) var days: [BodyDay] = []
    private(set) var loading = false
    private(set) var lastError: String?

    var today: BodyDay? { days.last { Calendar.current.isDateInToday($0.day) } }
    var connected: Bool { UserDefaults.standard.bool(forKey: "body.connected") }

    private var cacheURL: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("body-days.json")
    }

    init() {
        if let data = try? Data(contentsOf: cacheURL), let d = try? JSONDecoder().decode([BodyDay].self, from: data) { days = d }
    }

    func connect() async {
        if await BodyHealth.requestAccess() {
            UserDefaults.standard.set(true, forKey: "body.connected")
            await refresh(force: true)
        }
    }

    /// Reads Health (60 days the first time, then just the last few) and recomputes the scores.
    func refresh(force: Bool = false) async {
        guard connected, BodyHealth.available, !loading, !KeelRuntime.isTesting else { return }
        guard force || Throttle.due("body.refresh", every: 15 * 60) else { return }
        loading = true
        defer { loading = false }
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        let firstTime = days.count < 20
        let start = cal.date(byAdding: .day, value: firstTime ? -60 : -3, to: cal.startOfDay(for: Date())) ?? Date()
        let base = BodyPrefs.sleepNeed
        // The heavy part (thousands of heart-rate samples) runs in the background.
        let fresh: [BodyDay] = await Task.detached(priority: .utility) {
            let maxHR = BodyHealth.maxHR()
            let raw = await BodyHealth.read(from: start.addingTimeInterval(-15 * 3600), to: end)
            return BodyMath.days(from: raw, start: start, end: end, maxHR: maxHR)
        }.value
        var byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { _, b in b })
        for d in fresh { byDay[d.day] = d }
        var all = byDay.values.sorted { $0.day < $1.day }.suffix(90).map { $0 }
        BodyMath.score(&all, base: base)
        days = all
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: cacheURL, options: .atomic) }
        share()
        BodyAlerts.checkAndNotify(all)
        scheduleWindDown()
        await SmartWake.schedule(at: BodyMath.tonight(all, base: base).wake)
        Drinks.scheduleWaterNudge()
        WeeklyBodyReport.schedule(days: all)
        await morningAlertIfDue()
    }

    /// The small summary widgets, the Watch and Focus Forecast read.
    func share() {
        let t = today
        let tn = BodyMath.tonight(days, base: BodyPrefs.sleepNeed)
        let target = BodyMath.swellTarget(t?.tide)
        BodyScores(day: Calendar.current.startOfDay(for: Date()), tide: t?.tide, swell: t?.swell ?? 0, anchor: t?.anchor,
                   asleepMinutes: t.map { Int($0.asleep) }, bedtime: tn.bedtime, calibrating: t?.calibrating ?? true,
                   swellLow: target.lowerBound, swellHigh: target.upperBound, calmHours: BodyMath.calmHours(days)).save()
        WidgetCenter.shared.reloadTimelines(ofKind: "KeelBody")
    }

    static func energy(forTide t: Int) -> EnergyLevel { t >= 67 ? .high : t >= 34 ? .medium : .low }

    static func advice(_ tide: Int?) -> String {
        guard let t = tide else { return "Wear your Apple Watch to bed to see how recovered you are." }
        if t >= 67 { return "High tide: a strong day. Put your hardest, most focused work first." }
        if t >= 34 { return "Steady tide: a normal day. Mix focused work with easier tasks and take breaks." }
        return "Low tide: your body is still recovering. Keep today light, move gently and protect tonight's sleep."
    }

    /// Once each morning after you wake: your scores, what kind of day to plan, and today's energy set for you.
    private func morningAlertIfDue() async {
        let cal = Calendar.current
        guard let t = today, let wake = t.wake, wake < Date(), cal.component(.hour, from: Date()) < 12 else { return }
        let key = BodyMath.dayKey(Date())
        let todayStr = Date().formatted(.iso8601.year().month().day())
        if let tide = t.tide, UserDefaults.standard.string(forKey: "energy.day") != todayStr {
            UserDefaults.standard.set(Self.energy(forTide: tide).rawValue, forKey: "energy")
        }
        guard BodyPrefs.morningOn, UserDefaults.standard.string(forKey: "body.alerted") != key else { return }
        UserDefaults.standard.set(key, forKey: "body.alerted")
        let c = UNMutableNotificationContent()
        c.title = t.tide.map { "Tide \($0)% · Anchor \(t.anchor ?? 0)" } ?? "Good morning"
        let target = BodyMath.swellTarget(t.tide)
        c.body = Self.advice(t.tide) + " Aim for Swell \(target.lowerBound)–\(target.upperBound)."
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        if let first = CalendarService.shared.events(from: Date(), to: end).first(where: { !$0.isAllDay }) {
            c.body += " First up: \(first.title ?? "a meeting") at \(first.startDate.formatted(date: .omitted, time: .shortened))."
        }
        c.userInfo = ["deeplink": "com.keel.app://tool/body"]
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "body.morning.\(key)", content: c, trigger: nil))
    }

    /// Tonight's wind-down reminder, 45 minutes before your recommended bedtime.
    func scheduleWindDown() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["body.winddown"])
        guard BodyPrefs.windDownOn, days.contains(where: \.hasSleep) else { return }
        let tn = BodyMath.tonight(days, base: BodyPrefs.sleepNeed)
        let at = tn.bedtime.addingTimeInterval(-45 * 60)
        guard at > Date() else { return }
        let c = UNMutableNotificationContent()
        c.title = "Time to wind down"
        c.body = String(format: "You need about %.1f hours tonight. Lights out by %@ to wake at %@.", tn.need,
                        tn.bedtime.formatted(date: .omitted, time: .shortened), tn.wake.formatted(date: .omitted, time: .shortened))
        c.sound = .default
        c.userInfo = ["deeplink": "com.keel.app://tool/body"]
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: at)
        center.add(UNNotificationRequest(identifier: "body.winddown", content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }

    // MARK: Habit journal

    static let journalTags = ["Caffeine after 2 PM", "Alcohol", "Screens in bed", "Late meal", "Took my meds", "Worked out",
                              "Stressful day", "Napped", "Meditated", "Read before bed", "Sugar late", "Drank enough water",
                              "Sick", "Traveled"]

    var journal: [String: [String]] {
        get { (UserDefaults.standard.dictionary(forKey: BodyPrefs.journalKey) as? [String: [String]]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: BodyPrefs.journalKey) }
    }
    func toggle(_ tag: String, on day: Date) {
        var j = journal
        let k = BodyMath.dayKey(day)
        var list = j[k] ?? []
        if let i = list.firstIndex(of: tag) { list.remove(at: i) } else { list.append(tag) }
        j[k] = list.isEmpty ? nil : list
        journal = j
    }
}
