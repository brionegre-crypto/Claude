import Foundation
import SwiftUI
import SwiftData
import EventKit
import FoundationModels

/// Finds appointments in your email (doctor, dentist, haircut, interview, car service, classes, school events,
/// anything with a date that was booked or confirmed) and offers to put them on your calendar with one tap.
/// Runs after every mail sync; you can also scan further back from Today → ⊞ → Appointments from email.
@MainActor
enum AppointmentFinder {
    static let scannedKey = "appointments.scanned"

    private static let words = ["appointment", "appt", "scheduled", "booking", "booked", "confirmation", "confirmed", "reservation",
                                "your visit", "consultation", "interview", "check-up", "checkup", "session", "reminder:", "upcoming",
                                "see you on", "is set for", "rescheduled", "invitation:", "you're registered", "you are registered",
                                "registration", "class on", "meeting request", "save the date", "pickup", "pick-up", "drop-off", "service on"]

    static func looksLikeAppointment(_ e: EmailMessage) -> Bool {
        guard e.category != .promotions, e.category != .newsletters else { return false }
        let text = (e.subject + " " + e.bodyPlain.prefix(1_500)).lowercased()
        return words.contains(where: text.contains)
    }

    struct Found {
        var title: String
        var start: Date
        var end: Date
        var allDay: Bool
        var location: String
    }

    /// Reads one email for the appointment's title, time and place.
    static func extract(_ e: EmailMessage) async -> Found? {
        if AIRouter.shared.onDeviceAvailable {
            let session = LanguageModelSession(instructions: """
            Find the appointment or event being booked or confirmed in this email. Resolve relative dates against when it was sent: \
            \(e.receivedAt.formatted(.iso8601.year().month().day())), a \(e.receivedAt.formatted(.dateTime.weekday(.wide))). \
            If there's no specific appointment, answer with an empty start.
            """)
            if let f = try? await session.respond(to: "From: \(e.fromName)\nSubject: \(e.subject)\n\(e.bodyPlain.prefix(3_000))", generating: EmailToEvent.Found.self).content,
               let start = parse(f.start) {
                let allDay = f.start.count == 10
                let end = parse(f.end).flatMap { $0 > start ? $0 : nil } ?? start.addingTimeInterval(allDay ? 86_400 : 3_600)
                return Found(title: f.title.isEmpty ? cleanSubject(e.subject) : f.title, start: start, end: end, allDay: allDay, location: f.location)
            }
            return nil
        }
        // Without Apple Intelligence: the first future date with a time.
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let text = e.subject + "\n" + e.bodyPlain.prefix(3_000)
        guard let m = det.matches(in: text, range: NSRange(text.startIndex..., in: text)).first(where: { ($0.date ?? .distantPast) > Date() }),
              let start = m.date else { return nil }
        return Found(title: cleanSubject(e.subject), start: start, end: start.addingTimeInterval(m.duration > 0 ? m.duration : 3_600), allDay: false, location: "")
    }

    /// Looks through recent mail and adds an “Add to Calendar” suggestion for each upcoming appointment not already on your calendar.
    @discardableResult
    static func scan(ctx: ModelContext, days: Int = 21, aiBudget: Int = 8) async -> Int {
        let since = Date().addingTimeInterval(-Double(days) * 86_400)
        var d = FetchDescriptor<EmailMessage>(predicate: #Predicate { $0.receivedAt > since }, sortBy: [SortDescriptor(\.receivedAt, order: .reverse)])
        d.fetchLimit = 600
        let mail = (try? ctx.fetch(d)) ?? []
        var scanned = Set(UserDefaults.standard.stringArray(forKey: scannedKey) ?? [])
        let keys = Set(((try? ctx.fetch(FetchDescriptor<Suggestion>())) ?? []).map(\.key))
        var budget = aiBudget
        var added = 0
        for e in mail where !scanned.contains(e.id) && looksLikeAppointment(e) {
            guard budget > 0 else { break }
            budget -= 1
            scanned.insert(e.id)
            guard !keys.contains("appt:\(e.id)"), let f = await extract(e), f.start > Date().addingTimeInterval(-3_600),
                  !alreadyOnCalendar(f) else { continue }
            let when = f.allDay ? f.start.formatted(.dateTime.weekday(.wide).month().day())
                                : f.start.formatted(.dateTime.weekday(.wide).month().day().hour().minute())
            let s = Suggestion(key: "appt:\(e.id)", kind: "appointment", title: "Add “\(f.title)” to your calendar",
                               detail: [when, f.location, "from \(e.fromName.isEmpty ? e.from : e.fromName)"].filter { !$0.isEmpty }.joined(separator: " · "),
                               acceptLabel: "Add to Calendar")
            s.refId = e.id
            s.payload = [f.title, String(f.start.timeIntervalSince1970), String(f.end.timeIntervalSince1970), f.allDay ? "1" : "0", f.location].joined(separator: "|")
            ctx.insert(s)
            added += 1
        }
        UserDefaults.standard.set(Array(Array(scanned).suffix(1_500)), forKey: scannedKey)
        try? ctx.save()
        return added
    }

    /// Something at about the same time with a similar title is already there.
    static func alreadyOnCalendar(_ f: Found) -> Bool {
        let words = Set(f.title.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count > 3 })
        return CalendarService.shared.events(from: f.start.addingTimeInterval(-2 * 3_600), to: f.start.addingTimeInterval(2 * 3_600)).contains { ev in
            let t = Set((ev.title ?? "").lowercased().split { !$0.isLetter }.map(String.init))
            return abs(ev.startDate.timeIntervalSince(f.start)) < 30 * 60 && (words.isEmpty || !words.isDisjoint(with: t))
        }
    }

    /// Puts an accepted appointment on your default calendar, with a reminder an hour before.
    static func addToCalendar(_ s: Suggestion) -> String {
        let p = s.payload.components(separatedBy: "|")
        guard p.count >= 5, let st = Double(p[1]), let en = Double(p[2]) else { return "Couldn't read that appointment." }
        guard CalendarService.shared.hasCalendarAccess else { return "Allow Calendar access for Keel in Settings first." }
        let store = CalendarService.shared.store
        let ev = EKEvent(eventStore: store)
        ev.calendar = store.defaultCalendarForNewEvents
        ev.title = p[0]
        ev.startDate = Date(timeIntervalSince1970: st)
        ev.endDate = Date(timeIntervalSince1970: en)
        ev.isAllDay = p[3] == "1"
        if !p[4].isEmpty { ev.location = p[4] }
        ev.notes = "Added by Keel from an email."
        if !ev.isAllDay { ev.addAlarm(EKAlarm(relativeOffset: -3_600)) }
        do {
            try store.save(ev, span: .thisEvent); CalendarService.shared.invalidateEvents()
            return "“\(p[0])” is on your calendar."
        } catch {
            s.status = "pending"
            return "Couldn't add it: \(error.localizedDescription)"
        }
    }

    private static func cleanSubject(_ s: String) -> String {
        s.replacingOccurrences(of: #"(?i)^(re|fwd?|reminder|confirmation|confirmed)[:\s-]+"#, with: "", options: .regularExpression)
    }

    private static func parse(_ s: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current
        for fmt in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: s.trimmingCharacters(in: .whitespaces)) { return d }
        }
        return nil
    }
}

/// Today → ⊞ → Appointments from email: what Keel found, and a deeper scan on demand.
struct AppointmentsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<Suggestion> { $0.kind == "appointment" }, sort: \Suggestion.createdAt, order: .reverse) private var found: [Suggestion]
    @State private var scanning = false
    @State private var message: String?

    private var pending: [Suggestion] { found.filter { $0.status == "pending" } }
    private var added: [Suggestion] { found.filter { $0.status == "accepted" } }

    var body: some View {
        List {
            Section {
                Button {
                    Task {
                        scanning = true
                        let n = await AppointmentFinder.scan(ctx: ctx, days: 60, aiBudget: 40)
                        scanning = false
                        message = n == 0 ? "No new appointments found." : "Found \(n) new appointment\(n == 1 ? "" : "s")."
                    }
                } label: {
                    HStack {
                        Label(scanning ? "Reading your email…" : "Scan the last 60 days", systemImage: "envelope.badge.shield.half.filled")
                        if scanning { Spacer(); ProgressView() }
                    }
                }
                .disabled(scanning)
                if let message { Text(message).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft) }
            } footer: {
                Text("Keel looks for appointments, bookings and confirmations: doctor, dentist, haircut, interviews, car service, classes and school events. New ones are found automatically after every sync. Travel goes to Trips.")
            }

            if !pending.isEmpty {
                Section("Not on your calendar yet") {
                    ForEach(pending) { s in row(s) }
                }
            }
            if !added.isEmpty {
                Section("Added") {
                    ForEach(added.prefix(20)) { s in
                        Label(s.title.replacingOccurrences(of: "Add “", with: "").replacingOccurrences(of: "” to your calendar", with: ""), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(DS.Palette.calm)
                    }
                }
            }
            if found.isEmpty && !scanning {
                ContentUnavailableView("No appointments yet", systemImage: "calendar.badge.clock", description: Text("Tap Scan to look through recent email."))
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Appointments from email")
    }

    private func row(_ s: Suggestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(s.title.replacingOccurrences(of: "Add “", with: "").replacingOccurrences(of: "” to your calendar", with: "")).font(DS.Font.headline)
            Text(s.detail).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            HStack {
                Button("Add to Calendar", systemImage: "calendar.badge.plus") {
                    s.status = "accepted"
                    message = AppointmentFinder.addToCalendar(s)
                    try? ctx.save()
                    Haptics.success()
                }
                .buttonStyle(.borderedProminent).tint(DS.Palette.accent)
                Button("Not now") { s.status = "dismissed"; try? ctx.save() }.buttonStyle(.bordered)
            }
            .font(DS.Font.caption)
        }
        .padding(.vertical, 4)
    }
}
