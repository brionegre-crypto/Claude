import Foundation
import UserNotifications

/// ADHD transition warnings: a heads-up a few minutes before each event so switching tasks isn't a jolt.
@MainActor
enum TransitionAlerts {
    static let onKey = "transitions.on", minutesKey = "transitions.minutes"
    static var isOn: Bool { UserDefaults.standard.object(forKey: onKey) as? Bool ?? true }
    static var minutes: Int { UserDefaults.standard.object(forKey: minutesKey) as? Int ?? 5 }

    static func refresh() async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("transition.") }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard isOn else { return }
        let now = Date()
        for e in CalendarService.shared.events(from: now, to: now.addingTimeInterval(12 * 3600)).filter({ !$0.isAllDay }).prefix(12) {
            // Events with a travel alert already get a "leave now" nudge.
            if LeaveBy.times[e.calendarItemIdentifier] != nil { continue }
            let fire = e.startDate.addingTimeInterval(-Double(minutes * 60))
            guard fire > now else { continue }
            let c = UNMutableNotificationContent()
            c.title = "In \(minutes) min: \(e.title ?? "your next event")"
            c.body = "Start wrapping up. Jot down where you left off so it's easy to come back."
            c.interruptionLevel = .timeSensitive
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            try? await center.add(UNNotificationRequest(identifier: "transition.\(e.calendarItemIdentifier)", content: c,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }
}
