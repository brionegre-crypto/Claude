import Foundation
import HealthKit
import SwiftData

/// Food you log in Keel goes to Apple Health as a meal (calories, protein, carbs, fat, fiber, sugar, sodium, caffeine),
/// and Keel reads back what other apps logged so the day's totals are complete. Opt-in, in Settings → Health & Nutrition.
@MainActor
enum NutritionHealth {
    static let syncKey = "nutrition.health.sync"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: syncKey) }
    private static let store = HKHealthStore()

    private static let map: [(WritableKeyPath<NutritionFacts, Double?>, HKQuantityTypeIdentifier, HKUnit)] = [
        (\.calories, .dietaryEnergyConsumed, .kilocalorie()),
        (\.protein, .dietaryProtein, .gram()),
        (\.carbs, .dietaryCarbohydrates, .gram()),
        (\.fat, .dietaryFatTotal, .gram()),
        (\.fiber, .dietaryFiber, .gram()),
        (\.sugar, .dietarySugar, .gram()),
        (\.sodiumMg, .dietarySodium, .gramUnit(with: .milli)),
        (\.caffeineMg, .dietaryCaffeine, .gramUnit(with: .milli)),
        (\.magnesiumMg, .dietaryMagnesium, .gramUnit(with: .milli)),
        (\.zincMg, .dietaryZinc, .gramUnit(with: .milli)),
        (\.ironMg, .dietaryIron, .gramUnit(with: .milli)),
    ]
    private static var types: Set<HKQuantityType> { Set(map.map { HKQuantityType($0.1) }) }

    /// Asks once for permission to save meals and read nutrition and weight.
    static func connect() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            var read: Set<HKObjectType> = Set(types.map { $0 as HKObjectType })
            read.insert(HKQuantityType(.bodyMass))
            try await store.requestAuthorization(toShare: Set(types.map { $0 as HKSampleType }), read: read)
            UserDefaults.standard.set(true, forKey: syncKey)
            return true
        } catch {
            return false
        }
    }

    /// Saves a logged food to Health as one meal. Tagged with the entry's id so it can be removed later.
    static func save(_ e: FoodEntry) async {
        guard isOn, HKHealthStore.isHealthDataAvailable() else { return }
        let meta: [String: Any] = [HKMetadataKeyFoodType: e.name, HKMetadataKeyExternalUUID: e.id.uuidString]
        var samples: Set<HKSample> = []
        for (path, id, unit) in map {
            guard let v = e.facts[keyPath: path], v > 0 else { continue }
            let type = HKQuantityType(id)
            guard store.authorizationStatus(for: type) == .sharingAuthorized else { continue }
            samples.insert(HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: v), start: e.date, end: e.date, metadata: meta))
        }
        guard !samples.isEmpty else { return }
        let meal = HKCorrelation(type: HKCorrelationType(.food), start: e.date, end: e.date, objects: samples, metadata: meta)
        do {
            try await store.save(meal)
            e.savedToHealth = true
        } catch {}
    }

    /// Removes a deleted entry's meal from Health.
    static func remove(_ entryId: UUID) async {
        guard isOn, HKHealthStore.isHealthDataAvailable() else { return }
        let p = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [entryId.uuidString])
        for t in types where store.authorizationStatus(for: t) == .sharingAuthorized {
            _ = try? await store.deleteObjects(of: t, predicate: p)
        }
    }

    /// Today's totals from every app in Health (Keel included).
    static func todayTotals() async -> NutritionFacts? {
        guard isOn, HKHealthStore.isHealthDataAvailable() else { return nil }
        let pred = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: Date()), end: Date())
        var f = NutritionFacts()
        for (path, id, unit) in map {
            let q = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: HKQuantityType(id), predicate: pred), options: .cumulativeSum)
            if let v = (try? await q.result(for: store))?.sumQuantity()?.doubleValue(for: unit), v > 0 { f[keyPath: path] = v }
        }
        f.servingLabel = "today, all apps"
        return f
    }

    /// Latest weight in kilograms, for a protein goal that fits you.
    static func weightKg() async -> Double? {
        guard isOn, HKHealthStore.isHealthDataAvailable() else { return nil }
        let d = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(.bodyMass))],
                                        sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 1)
        return (try? await d.result(for: store))?.first?.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }
}

/// Daily targets. Protein follows your weight when Health has it; added sugar has a ceiling, not a goal.
enum NutritionGoals {
    static let proteinKey = "nutrition.goal.protein", fiberKey = "nutrition.goal.fiber", sugarKey = "nutrition.goal.addedSugar"

    static func protein(weightKg: Double?) -> Double {
        let saved = UserDefaults.standard.double(forKey: proteinKey)
        if saved > 0 { return saved }
        if let w = weightKg { return (w * 1.6 / 5).rounded() * 5 }      // ~1.6 g per kg, rounded to 5 g
        return 120
    }
    static var fiber: Double { let v = UserDefaults.standard.double(forKey: fiberKey); return v > 0 ? v : 30 }
    static var addedSugarCap: Double { let v = UserDefaults.standard.double(forKey: sugarKey); return v > 0 ? v : 15 }
}

extension NutritionFacts {
    static func + (a: NutritionFacts, b: NutritionFacts) -> NutritionFacts {
        func s(_ x: Double?, _ y: Double?) -> Double? { x == nil && y == nil ? nil : (x ?? 0) + (y ?? 0) }
        return NutritionFacts(calories: s(a.calories, b.calories), protein: s(a.protein, b.protein), carbs: s(a.carbs, b.carbs),
                              fat: s(a.fat, b.fat), fiber: s(a.fiber, b.fiber), sugar: s(a.sugar, b.sugar), addedSugar: s(a.addedSugar, b.addedSugar),
                              sodiumMg: s(a.sodiumMg, b.sodiumMg), caffeineMg: s(a.caffeineMg, b.caffeineMg), magnesiumMg: s(a.magnesiumMg, b.magnesiumMg),
                              zincMg: s(a.zincMg, b.zincMg), ironMg: s(a.ironMg, b.ironMg), servingLabel: "total")
    }
}
