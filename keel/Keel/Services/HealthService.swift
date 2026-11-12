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
            try await store.requestAuthorization(toShare: [], read: [HKCategoryType(.sleepAnalysis)])
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

    static func energy(forSleep hours: Double) -> EnergyLevel {
        hours < 6 ? .low : hours < 7.5 ? .medium : .high
    }
}
