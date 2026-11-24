import SwiftUI
import EventKit

/// What each calendar means for your day: "Show" (its events appear on Today and in planning), "Block time only"
/// (you're busy then, but the events aren't listed, e.g. a calendar someone shares with you), or "Ignore"
/// (neither shown nor counted, e.g. holidays). Events someone else owns that you aren't invited to only ever block time.
@MainActor
enum CalendarRoles {
    enum Role: String, CaseIterable, Identifiable {
        case show, block, ignore
        var id: String { rawValue }
        var label: String { switch self { case .show: "Show"; case .block: "Block time only"; case .ignore: "Ignore" } }
    }
    static let key = "calendar.roles"

    // Read once and kept (looked up for every event, on every redraw of Today and every free-time search).
    private static var cache: [String: String]?
    private static var saved: [String: String] {
        if let c = cache { return c }
        let c = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        cache = c
        return c
    }

    static func role(_ c: EKCalendar) -> Role {
        if let r = saved[c.calendarIdentifier].flatMap(Role.init(rawValue:)) { return r }
        if c.type == .birthday { return .ignore }
        if c.type == .subscription || !c.allowsContentModifications { return .block }   // shared / subscribed: busy, not listed
        return .show
    }

    static func set(_ r: Role, for c: EKCalendar) {
        var s = saved; s[c.calendarIdentifier] = r.rawValue
        UserDefaults.standard.set(s, forKey: key)
        cache = s
    }

    /// Someone else's event on a calendar shared with you, that you weren't invited to.
    static func notMine(_ e: EKEvent) -> Bool {
        guard let org = e.organizer, !org.isCurrentUser else { return false }
        return !(e.attendees?.contains { $0.isCurrentUser } ?? false)
    }

    /// Listed on Today and in your task planning.
    static func shows(_ e: EKEvent) -> Bool {
        guard let c = e.calendar else { return true }
        return role(c) == .show && !notMine(e)
    }

    /// Counts as busy time when Keel looks for free time or schedules tasks.
    static func busy(_ e: EKEvent) -> Bool {
        guard let c = e.calendar else { return true }
        return role(c) != .ignore && e.availability != .free
    }
}

/// Tasks → menu → Set up → Calendars in Tasks & Today.
struct CalendarRolesView: View {
    @State private var tick = 0
    var body: some View {
        let cals = CalendarService.shared.allCalendars.sorted { $0.title < $1.title }
        List {
            Section {
                ForEach(cals, id: \.calendarIdentifier) { c in
                    let _ = tick
                    Picker(selection: Binding(get: { CalendarRoles.role(c) }, set: { CalendarRoles.set($0, for: c); tick += 1 })) {
                        ForEach(CalendarRoles.Role.allCases) { Text($0.label).tag($0) }
                    } label: {
                        Label { Text(c.title) } icon: { Circle().fill(Color(cgColor: c.cgColor)).frame(width: 10, height: 10) }
                    }
                }
            } footer: {
                Text("Show: events appear on Today and in planning. Block time only: you're busy then, but the events aren't listed (good for calendars others share with you). Ignore: not shown and doesn't block time. Events someone else owns that you aren't invited to only block time.")
            }
        }
        .navigationTitle("Calendars in Tasks & Today")
    }
}
