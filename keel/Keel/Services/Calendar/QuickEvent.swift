import Foundation
import EventKit

/// "Lunch with Sam Thursday 1pm for 90 min" → an event. Runs on-device.
enum QuickEvent {
    struct Parsed { var title: String; var start: Date; var minutes: Int; var allDay: Bool }

    static func parse(_ input: String) -> Parsed? {
        var text = input
        var minutes = 60
        // Duration: "for 90 min", "for 2 hours", "for 1.5h"
        if let r = text.range(of: #"\bfor\s+(\d+(?:\.\d+)?)\s*(m|min|mins|minutes|h|hr|hrs|hour|hours)\b"#, options: [.regularExpression, .caseInsensitive]) {
            let parts = text[r].lowercased().replacingOccurrences(of: "for", with: "").trimmingCharacters(in: .whitespaces)
            let number = Double(parts.prefix { $0.isNumber || $0 == "." }) ?? 1
            minutes = parts.contains("h") ? Int(number * 60) : Int(number)
            text.removeSubrange(r)
        }
        let (title, date) = NaturalDate.parse(text.trimmingCharacters(in: .whitespaces))
        guard let start = date else { return nil }
        let c = Calendar.current.dateComponents([.hour, .minute], from: start)
        let allDay = (c.hour ?? 0) == 0 && (c.minute ?? 0) == 0 && !input.lowercased().contains("midnight")
        let cleanTitle = title.replacingOccurrences(of: #"\s+(at|on)\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return Parsed(title: cleanTitle.isEmpty ? "Event" : cleanTitle, start: start, minutes: max(5, minutes), allDay: allDay)
    }

    @MainActor
    static func create(_ input: String) throws -> Parsed? {
        guard let p = parse(input) else { return nil }
        let store = CalendarService.shared.store
        let e = EKEvent(eventStore: store)
        e.title = p.title
        e.calendar = store.defaultCalendarForNewEvents
        e.isAllDay = p.allDay
        e.startDate = p.start
        e.endDate = p.allDay ? p.start.addingTimeInterval(86_400) : p.start.addingTimeInterval(Double(p.minutes * 60))
        try store.save(e, span: .thisEvent)
        return p
    }
}
