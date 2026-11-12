import Foundation

/// "Here's when I'm free": your open slots over the next few workdays, as text to paste into an email.
@MainActor
enum Availability {
    static func text(days: Int = 5, minMinutes: Int = 30, startHour: Int = 9, endHour: Int = 17) -> String {
        let cal = Calendar.current
        var lines: [String] = []
        var day = cal.startOfDay(for: Date())
        var counted = 0
        while counted < days {
            defer { day = cal.date(byAdding: .day, value: 1, to: day)! }
            let weekday = cal.component(.weekday, from: day)
            guard weekday != 1 && weekday != 7 else { continue }
            counted += 1
            let open = cal.date(bySettingHour: startHour, minute: 0, second: 0, of: day)!
            let from = max(open, roundUp(Date()))
            let slots = CalendarService.shared.freeSlots(minMinutes: minMinutes, from: from, until: endHour).prefix(3)
            guard !slots.isEmpty else { continue }
            let times = slots.map { "\($0.start.formatted(date: .omitted, time: .shortened))–\($0.end.formatted(date: .omitted, time: .shortened))" }
            lines.append("• \(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())): \(times.joined(separator: ", "))")
        }
        guard !lines.isEmpty else { return "I'm fully booked for the next few days; could we look at the following week?" }
        let zone = TimeZone.current.abbreviation() ?? TimeZone.current.identifier
        return "Here are some times that work for me (\(zone)):\n" + lines.joined(separator: "\n") + "\n"
    }

    /// Next quarter hour, so "now" isn't offered as 2:07.
    private static func roundUp(_ d: Date) -> Date {
        let m = Calendar.current.component(.minute, from: d)
        return Calendar.current.date(byAdding: .minute, value: (15 - m % 15) % 15, to: d) ?? d
    }
}
