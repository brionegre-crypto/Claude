import Foundation
import SwiftData
import EventKit
import FoundationModels

/// Finds flights, hotels, rental cars, trains, restaurant bookings and tickets in confirmation emails.
/// Apple Intelligence reads the details on-device; a simpler pattern match is used without it.
@MainActor
enum TripScanner {
    private static let triggers = ["confirmation", "itinerary", "booking", "reservation", "e-ticket", "boarding pass", "your trip", "your flight", "check-in", "your stay", "rental", "tickets for"]

    static func looksLikeReservation(_ e: EmailMessage) -> Bool {
        let s = (e.subject + " " + e.snippet).lowercased()
        guard triggers.contains(where: { s.contains($0) }) else { return false }
        return !["order confirmation", "subscription", "newsletter", "password", "verify", "sign in", "receipt for your payment"].contains { s.contains($0) }
    }

    @Generable
    struct Found {
        @Guide(description: "flight, hotel, car, train, restaurant or event")
        var kind: String
        @Guide(description: "Short title, e.g. 'UA 1234 SFO → JFK', 'Hilton Midtown', 'Hertz pickup', 'Dinner at Nopa'")
        var title: String
        @Guide(description: "Confirmation or booking code, or empty")
        var confirmation: String
        @Guide(description: "Start (departure, check-in, pickup, reservation time) as YYYY-MM-DDTHH:mm in local time")
        var start: String
        @Guide(description: "End (arrival, check-out, return) as YYYY-MM-DDTHH:mm, or empty")
        var end: String
        @Guide(description: "City, airport or address, or empty")
        var location: String
        @Guide(description: "Useful extras: terminal, seat, room, address; or empty")
        var detail: String
    }

    @Generable
    struct Scan {
        @Guide(description: "Each separate booking in the email (a round trip is two flights). Empty if this isn't a booking confirmation.", .maximumCount(6))
        var items: [Found]
    }

    static func scan(_ emails: [EmailMessage], ctx: ModelContext, aiBudget: Int = 25) async {
        let existing = Set(((try? ctx.fetch(FetchDescriptor<Reservation>())) ?? []).compactMap(\.sourceEmailId))
        var budget = aiBudget
        for e in emails where looksLikeReservation(e) && !existing.contains(e.id) {
            var found: [Reservation] = []
            if AIRouter.shared.onDeviceAvailable, budget > 0 {
                budget -= 1
                let session = LanguageModelSession(instructions: "Extract travel and booking reservations from a confirmation email. Never invent details. The email arrived \(e.receivedAt.formatted(.iso8601.year().month().day())).")
                if let r = try? await session.respond(to: "Subject: \(e.subject)\n\(e.bodyPlain.prefix(3_500))", generating: Scan.self).content {
                    found = r.items.compactMap { f in
                        guard let start = parseDate(f.start) else { return nil }
                        let res = Reservation(kind: f.kind.lowercased(), title: f.title, start: start)
                        res.end = parseDate(f.end); res.confirmation = f.confirmation; res.location = f.location; res.detail = f.detail
                        return res
                    }
                }
            } else if let r = heuristic(e) {
                found = [r]
            }
            for r in found where r.start > Date().addingTimeInterval(-2 * 86_400) {
                r.sourceEmailId = e.id
                ctx.insert(r)
            }
        }
        try? ctx.save()
    }

    static func backfillIfNeeded(ctx: ModelContext) async {
        guard !UserDefaults.standard.bool(forKey: "trips.backfilled") else { return }
        UserDefaults.standard.set(true, forKey: "trips.backfilled")
        let since = Date().addingTimeInterval(-120 * 86_400)
        let mail = ((try? ctx.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { $0.receivedAt > since }))) ?? [])
        await scan(mail, ctx: ctx, aiBudget: 40)
    }

    private static func parseDate(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current
        for fmt in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    private static func heuristic(_ e: EmailMessage) -> Reservation? {
        let text = e.subject + "\n" + e.bodyPlain.prefix(3_000)
        let l = text.lowercased()
        let kind = l.contains("flight") || l.contains("boarding") ? "flight" : l.contains("hotel") || l.contains("check-in") || l.contains("your stay") ? "hotel"
            : l.contains("rental") || l.contains("pick-up") ? "car" : l.contains("train") || l.contains("rail") ? "train"
            : l.contains("table for") || l.contains("restaurant") ? "restaurant" : "event"
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let dates = det.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.date).filter { $0 > e.receivedAt.addingTimeInterval(-86_400) }
        guard let start = dates.first else { return nil }
        let r = Reservation(kind: kind, title: e.subject.replacingOccurrences(of: #"(?i)^(fwd?:|re:)\s*"#, with: "", options: .regularExpression), start: start)
        if dates.count > 1, let end = dates.dropFirst().first(where: { $0 > start }) { r.end = end }
        if let m = text.range(of: #"(?i)(confirmation|booking|record locator|reservation)\s*(number|code|#)?[:\s]+([A-Z0-9]{5,10})"#, options: .regularExpression) {
            r.confirmation = String(text[m]).components(separatedBy: CharacterSet(charactersIn: ": #")).last ?? ""
        }
        return r
    }

    /// Adds a reservation to the default calendar (once).
    static func addToCalendar(_ r: Reservation) throws {
        let store = CalendarService.shared.store
        let e = EKEvent(eventStore: store)
        e.title = r.title
        e.calendar = store.defaultCalendarForNewEvents
        e.startDate = r.start
        let isAllDay = r.kind == "hotel" || Calendar.current.dateComponents([.hour, .minute], from: r.start) == DateComponents(hour: 0, minute: 0)
        e.isAllDay = isAllDay
        e.endDate = r.end ?? r.start.addingTimeInterval(r.kind == "flight" ? 3 * 3600 : 3600)
        e.location = r.location.isEmpty ? nil : r.location
        e.notes = [r.confirmation.isEmpty ? nil : "Confirmation: \(r.confirmation)", r.detail.isEmpty ? nil : r.detail, "Added by Keel"].compactMap { $0 }.joined(separator: "\n")
        if r.kind == "flight" { e.addAlarm(EKAlarm(relativeOffset: -3 * 3600)) }
        try store.save(e, span: .thisEvent)
        r.calendarEventId = e.eventIdentifier
    }
}
