import Foundation
import UserNotifications

/// Gentle movement breaks during your work hours: stand, water, eyes, breathe.
/// Skipped while a focus session runs, so they never break deep work.
@MainActor
enum BreakReminders {
    static let onKey = "breaks.on", everyKey = "breaks.every", startKey = "breaks.start", endKey = "breaks.end", weekendsKey = "breaks.weekends"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: onKey) }
    static var every: Int { UserDefaults.standard.object(forKey: everyKey) as? Int ?? 60 }
    static var startMinute: Int { UserDefaults.standard.object(forKey: startKey) as? Int ?? 540 }    // 9:00
    static var endMinute: Int { UserDefaults.standard.object(forKey: endKey) as? Int ?? 1050 }       // 17:30

    static let prompts: [(String, String)] = [
        ("Stand up and stretch", "Thirty seconds. Reach up, roll your shoulders."),
        ("Water break 💧", "Have a few sips. Your focus will thank you."),
        ("Rest your eyes", "Look at something 20 feet away for 20 seconds."),
        ("Three slow breaths", "In for 4, out for 6. Then back to it."),
        ("Walk it out", "A lap of the room resets your brain."),
    ]

    /// Schedules today's remaining breaks (called at launch, after sync and when focus ends).
    static func schedule(skipUntil: Date? = nil) {
        Task {
            let center = UNUserNotificationCenter.current()
            let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("break.") }
            center.removePendingNotificationRequests(withIdentifiers: old)
            guard isOn else { return }
            let cal = Calendar.current
            let now = Date()
            let weekday = cal.component(.weekday, from: now)
            if !UserDefaults.standard.bool(forKey: weekendsKey) && (weekday == 1 || weekday == 7) { return }
            if ShutdownManager.shared.active != nil && skipUntil == nil { return }
            let day = cal.startOfDay(for: now)
            var minute = startMinute + every
            var i = 0
            while minute < endMinute {
                defer { minute += every; i += 1 }
                guard let fire = cal.date(byAdding: .minute, value: minute, to: day), fire > now, fire > (skipUntil ?? .distantPast) else { continue }
                let p = prompts[i % prompts.count]
                let c = UNMutableNotificationContent()
                c.title = p.0; c.body = p.1
                c.interruptionLevel = .passive          // shows quietly, no sound, never breaks through Focus
                try? await center.add(UNNotificationRequest(identifier: "break.\(minute)", content: c,
                    trigger: UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)))
            }
        }
    }

    static func pause() {
        Task {
            let center = UNUserNotificationCenter.current()
            let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("break.") }
            center.removePendingNotificationRequests(withIdentifiers: old)
        }
    }
}
