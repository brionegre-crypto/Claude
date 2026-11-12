import Foundation
import SwiftData
import UserNotifications

/// Medication reminders with a "Taken" button, a gentle nudge 30 minutes later if not logged,
/// and a clear answer to "did I already take it?".
@MainActor
enum MedEngine {
    static let category = "MED"
    static let takenAction = "MED_TAKEN"
    static let nagMinutes = 30

    static func timeLabel(_ minutes: Int) -> String {
        let d = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return d.formatted(date: .omitted, time: .shortened)
    }

    static func taken(_ m: Medication, slot: Int, on day: Date = Date(), doses: [MedDose]) -> MedDose? {
        let d = Calendar.current.startOfDay(for: day)
        return doses.first { $0.medicationId == m.id && $0.slot == slot && $0.day == d }
    }

    static func take(_ m: Medication, slot: Int, ctx: ModelContext) {
        let day = Calendar.current.startOfDay(for: Date())
        let all = (try? ctx.fetch(FetchDescriptor<MedDose>())) ?? []
        guard taken(m, slot: slot, doses: all) == nil else { return }
        ctx.insert(MedDose(medicationId: m.id, slot: slot, day: day))
        if let left = m.pillsLeft { m.pillsLeft = max(0, left - 1) }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [nagId(m, slot, day)])
        center.removeDeliveredNotifications(withIdentifiers: [mainId(m, slot), nagId(m, slot, day)])
        if let left = m.pillsLeft, left == m.refillAt {
            let c = UNMutableNotificationContent()
            c.title = "Time to refill \(m.name)"
            c.body = "\(left) left. Order a refill so you don't run out."
            center.add(UNNotificationRequest(identifier: "med.refill.\(m.id)", content: c, trigger: nil))
        }
        try? ctx.save()
        Haptics.success()
        WidgetSync.update(ctx)        // Lock Screen widget shows the next dose
    }

    static func undo(_ dose: MedDose, med: Medication?, ctx: ModelContext) {
        if let m = med, let left = m.pillsLeft { m.pillsLeft = left + 1 }
        ctx.delete(dose)
        try? ctx.save()
    }

    private static func mainId(_ m: Medication, _ slot: Int) -> String { "med.\(m.id).\(slot)" }
    private static func nagId(_ m: Medication, _ slot: Int, _ day: Date) -> String {
        "med.nag.\(m.id).\(slot).\(Int(day.timeIntervalSince1970))"
    }

    /// Daily repeating reminders, plus one-off nudges for today and tomorrow (refreshed every launch).
    static func scheduleAll(ctx: ModelContext) {
        let meds = (try? ctx.fetch(FetchDescriptor<Medication>())) ?? []
        let doses = (try? ctx.fetch(FetchDescriptor<MedDose>())) ?? []
        let cal = Calendar.current
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("med.") }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for m in meds where m.isActive && m.remind {
                for slot in m.times {
                    let c = UNMutableNotificationContent()
                    c.title = "💊 \(m.name)"
                    c.body = m.dose.isEmpty ? "Time to take it." : "Time to take \(m.dose)."
                    c.categoryIdentifier = category
                    c.sound = .default
                    c.interruptionLevel = .timeSensitive
                    c.userInfo = ["medId": m.id.uuidString, "slot": slot]
                    let comps = DateComponents(hour: slot / 60, minute: slot % 60)
                    try? await center.add(UNNotificationRequest(identifier: mainId(m, slot), content: c,
                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
                    for offset in 0...1 {
                        let day = cal.startOfDay(for: cal.date(byAdding: .day, value: offset, to: Date())!)
                        guard taken(m, slot: slot, on: day, doses: doses) == nil,
                              let fire = cal.date(byAdding: .minute, value: slot + nagMinutes, to: day), fire > Date() else { continue }
                        let n = UNMutableNotificationContent()
                        n.title = "Did you take \(m.name)?"
                        n.body = "Tap Taken if you did, so Keel can tell you later."
                        n.categoryIdentifier = category
                        n.userInfo = c.userInfo
                        try? await center.add(UNNotificationRequest(identifier: nagId(m, slot, day), content: n,
                            trigger: UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)))
                    }
                }
            }
        }
    }

    /// Plain-English answer for Siri, Ask Keel and the watch.
    static func statusSentence(ctx: ModelContext) -> String {
        let meds = ((try? ctx.fetch(FetchDescriptor<Medication>())) ?? []).filter(\.isActive)
        guard !meds.isEmpty else { return "You haven't added any medications in Keel." }
        let doses = (try? ctx.fetch(FetchDescriptor<MedDose>())) ?? []
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let nowMin = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        var parts: [String] = []
        for m in meds {
            for slot in m.times.sorted() {
                if let d = taken(m, slot: slot, doses: doses) {
                    parts.append("Yes, you took \(m.name) at \(d.takenAt.formatted(date: .omitted, time: .shortened)).")
                } else if slot <= nowMin {
                    parts.append("No, you haven't logged your \(timeLabel(slot)) \(m.name) yet.")
                }
            }
        }
        return parts.isEmpty ? "Nothing is due yet today." : parts.joined(separator: " ")
    }
}
