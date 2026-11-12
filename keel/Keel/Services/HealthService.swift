import Foundation
import HealthKit

/// Reads last night's sleep (with permission) to suggest today's energy level. Read-only; nothing is written to Health.
@MainActor
final class HealthService {
    static let shared = HealthService()
    private let store = HKHealthStore()

    var isAuthorizedHint: Bool { UserDefaults.standard.bool(forKey: "health.connected") }

    func requestAccess() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: [
                HKCategoryType(.sleepAnalysis), HKQuantityType(.stepCount), HKQuantityType(.appleExerciseTime),
                HKCategoryType(.mindfulSession), HKObjectType.workoutType(),
            ])
            UserDefaults.standard.set(true, forKey: "health.connected")
        } catch {}
    }

    /// Hours asleep since 6 PM yesterday. With several sources (Watch + iPhone), uses the one that recorded most.
    func lastNightSleepHours() async -> Double? {
        guard isAuthorizedHint, HKHealthStore.isHealthDataAvailable() else { return nil }
        let cal = Calendar.current
        let start = cal.date(bySettingHour: 18, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -1, to: Date())!)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let descriptor = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
                                                 sortDescriptors: [])
        guard let samples = try? await descriptor.result(for: store), !samples.isEmpty else { return nil }
        let asleep = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        var bySource: [String: TimeInterval] = [:]
        for s in samples where asleep.contains(s.value) {
            bySource[s.sourceRevision.source.bundleIdentifier, default: 0] += s.endDate.timeIntervalSince(s.startDate)
        }
        guard let best = bySource.values.max(), best > 0 else { return nil }
        return best / 3600
    }

    private var todayPredicate: NSPredicate {
        HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: Date()), end: Date())
    }

    func todaySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        guard isAuthorizedHint, HKHealthStore.isHealthDataAvailable() else { return 0 }
        let q = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: HKQuantityType(id), predicate: todayPredicate), options: .cumulativeSum)
        return (try? await q.result(for: store))?.sumQuantity()?.doubleValue(for: unit) ?? 0
    }

    func todaySteps() async -> Int { Int(await todaySum(.stepCount, unit: .count())) }

    /// Exercise ring minutes, or workout minutes if that's higher (e.g. no Apple Watch).
    func todayExerciseMinutes() async -> Int {
        let ring = await todaySum(.appleExerciseTime, unit: .minute())
        guard isAuthorizedHint else { return Int(ring) }
        let d = HKSampleQueryDescriptor(predicates: [.workout(todayPredicate)], sortDescriptors: [])
        let workouts = ((try? await d.result(for: store)) ?? []).reduce(0) { $0 + $1.duration } / 60
        return Int(max(ring, workouts))
    }

    func todayMindfulMinutes() async -> Int {
        guard isAuthorizedHint else { return 0 }
        let d = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.mindfulSession), predicate: todayPredicate)], sortDescriptors: [])
        return Int(((try? await d.result(for: store)) ?? []).reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 60)
    }

    static func energy(forSleep hours: Double) -> EnergyLevel {
        hours < 6 ? .low : hours < 7.5 ? .medium : .high
    }
}
