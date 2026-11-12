import Foundation
import EventKit
import FoundationModels

/// Reads an email for a meeting, appointment or plan and prepares a calendar event you can review.
@MainActor
enum EmailToEvent {
    @Generable
    struct Found {
        @Guide(description: "Short event title, e.g. 'Coffee with Sam', 'Dentist appointment'")
        var title: String
        @Guide(description: "Start as YYYY-MM-DDTHH:mm in local time; date only (YYYY-MM-DD) if no time is given")
        var start: String
        @Guide(description: "End as YYYY-MM-DDTHH:mm, or empty if not stated")
        var end: String
        @Guide(description: "Place, address or video link, or empty")
        var location: String
    }

    static func event(from e: EmailMessage) async -> EKEvent {
        let store = CalendarService.shared.store
        let ev = EKEvent(eventStore: store)
        ev.calendar = store.defaultCalendarForNewEvents
        ev.title = e.subject.replacingOccurrences(of: #"(?i)^(re|fwd?):\s*"#, with: "", options: .regularExpression)
        ev.notes = "From \(e.fromName.isEmpty ? e.from : e.fromName): \(e.aiSummary ?? e.snippet)"
        var start: Date?, end: Date?
        if AIRouter.shared.onDeviceAvailable {
            let session = LanguageModelSession(instructions: "Find the event being arranged in this email. Resolve relative dates against when it was sent: \(e.receivedAt.formatted(.iso8601.year().month().day())), a \(e.receivedAt.formatted(.dateTime.weekday(.wide))).")
            if let f = try? await session.respond(to: "Subject: \(e.subject)\n\(e.bodyPlain.prefix(3_000))", generating: Found.self).content {
                if !f.title.isEmpty { ev.title = f.title }
                if !f.location.isEmpty { ev.location = f.location }
                start = parse(f.start); end = parse(f.end)
                ev.isAllDay = f.start.count == 10
            }
        }
        if start == nil, let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let text = e.subject + "\n" + e.bodyPlain.prefix(3_000)
            start = det.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.date).first { $0 > Date().addingTimeInterval(-3600) }
        }
        ev.startDate = start ?? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!)!
        ev.endDate = end.flatMap { $0 > ev.startDate ? $0 : nil } ?? ev.startDate.addingTimeInterval(ev.isAllDay ? 86_400 : 3600)
        return ev
    }

    private static func parse(_ s: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current
        for fmt in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
