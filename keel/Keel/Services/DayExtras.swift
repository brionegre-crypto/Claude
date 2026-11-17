import Foundation
import SwiftData
import EventKit
import UserNotifications

// MARK: - Buffer time after meetings

/// After each meeting, a short "Buffer" block on your Keel calendar so the next thing can't be booked right on top
/// (your booking link respects it too). Only where the time is free; moved or cancelled meetings take theirs along.
@MainActor
enum MeetingBuffers {
    static let key = "custom.calendar.buffer"                  // minutes; 0 = off
    static var minutes: Int { UserDefaults.standard.integer(forKey: key) }
    private static let marker = "keel-buffer:"

    static func refresh(force: Bool = false) {
        let svc = CalendarService.shared
        guard svc.hasCalendarAccess, force || Throttle.due("buffers.refresh", every: 20 * 60) else { return }
        guard let keelCal = try? svc.keelCalendar() else { return }
        let start = Date(), end = Date().addingTimeInterval(7 * 86_400)
        let all = svc.store.events(matching: svc.store.predicateForEvents(withStart: start.addingTimeInterval(-3600), end: end, calendars: nil))
        let existing = all.filter { $0.calendar.calendarIdentifier == keelCal.calendarIdentifier && ($0.notes ?? "").hasPrefix(marker) }
        let others = all.filter { !($0.notes ?? "").hasPrefix(marker) && !$0.isAllDay }
        let n = minutes

        var wanted: [String: (Date, Date, String)] = [:]
        if n > 0 {
            for e in others where e.calendar.calendarIdentifier != keelCal.calendarIdentifier && MeetingAutopilot.isMeeting(e) && e.endDate > start {
                let s = e.endDate!, f = e.endDate.addingTimeInterval(Double(n * 60))
                let busy = others.contains { o in o !== e && o.startDate < f && o.endDate > s }
                if !busy { wanted[e.calendarItemIdentifier + "@" + String(Int(e.startDate.timeIntervalSince1970))] = (s, f, e.title ?? "meeting") }
            }
        }
        var changed = false
        for b in existing {
            let k = String((b.notes ?? "").dropFirst(marker.count))
            if let w = wanted[k], b.startDate == w.0, b.endDate == w.1 { wanted[k] = nil; continue }
            try? svc.store.remove(b, span: .thisEvent, commit: false); changed = true
        }
        for (k, w) in wanted {
            let b = EKEvent(eventStore: svc.store)
            b.calendar = keelCal
            b.title = "Buffer"
            b.startDate = w.0; b.endDate = w.1
            b.notes = marker + k
            b.availability = .busy
            try? svc.store.save(b, span: .thisEvent, commit: false); changed = true
        }
        if changed { try? svc.store.commit(); svc.invalidateEvents() }
    }
}

// MARK: - End-of-day wrap-up

/// A quiet note at the end of your day: what you got done, and the first thing tomorrow.
/// Re-written whenever you finish something, so it's current when it arrives.
@MainActor
enum DayWrap {
    static let onKey = "custom.today.wrap"
    static let minuteKey = "custom.today.wrapMinute"             // minutes after midnight, default 18:00
    static var isOn: Bool { UserDefaults.standard.object(forKey: onKey) as? Bool ?? true }
    static var minute: Int { let v = UserDefaults.standard.integer(forKey: minuteKey); return v > 0 ? v : 18 * 60 }
    private static let id = "day.wrap"

    static func reschedule(ctx: ModelContext) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard isOn else { return }
        let cal = Calendar.current
        guard let at = cal.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()), at > Date() else { return }
        let todayStart = cal.startOfDay(for: Date())
        let done = ((try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isDone && $0.completedAt != nil }))) ?? [])
            .filter { ($0.completedAt ?? .distantPast) >= todayStart }.count
        let open = (try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? []
        let tomorrow = open.filter { $0.dueDate.map { cal.isDateInTomorrow($0) } ?? false }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        let firstEvent = CalendarService.shared.events(from: cal.date(byAdding: .day, value: 1, to: todayStart) ?? Date(),
                                                       to: cal.date(byAdding: .day, value: 2, to: todayStart) ?? Date())
            .filter { !$0.isAllDay }.min { $0.startDate < $1.startDate }

        let c = UNMutableNotificationContent()
        c.title = done == 0 ? "That's the day" : "You finished \(done) thing\(done == 1 ? "" : "s") today"
        var lines: [String] = []
        if let e = firstEvent { lines.append("Tomorrow starts with \(e.title ?? "an event") at \(e.startDate.formatted(date: .omitted, time: .shortened)).") }
        if let t = tomorrow.first { lines.append("First task: \(t.title)\(tomorrow.count > 1 ? " (+\(tomorrow.count - 1) more)" : "").") }
        lines.append(done == 0 ? "Rest counts too. Tomorrow is a fresh start." : "Nice work. Time to switch off.")
        c.body = lines.joined(separator: " ")
        c.sound = nil
        c.threadIdentifier = "wrap"
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: at)
        center.addKeel(UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }
}

// MARK: - Quiet hours

/// Overnight, Keel's alerts arrive silently in Notification Center (or wait until morning, your choice).
/// Medication reminders and alarms always come through.
enum QuietHours {
    static let onKey = "custom.quiet.on"
    static let startKey = "custom.quiet.start"                 // minutes after midnight (default 22:00)
    static let endKey = "custom.quiet.end"                     // default 07:00
    static let holdKey = "custom.quiet.hold"                   // true = wait until morning, false = deliver silently

    static var isOn: Bool { UserDefaults.standard.bool(forKey: onKey) }
    static var start: Int { UserDefaults.standard.object(forKey: startKey) as? Int ?? 22 * 60 }
    static var end: Int { UserDefaults.standard.object(forKey: endKey) as? Int ?? 7 * 60 }
    static var holdUntilMorning: Bool { UserDefaults.standard.bool(forKey: holdKey) }

    static func isQuiet(_ d: Date) -> Bool {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return start <= end ? (m >= start && m < end) : (m >= start || m < end)
    }

    /// The morning after a quiet moment.
    static func endOfQuiet(after d: Date) -> Date {
        let cal = Calendar.current
        var e = cal.date(bySettingHour: end / 60, minute: end % 60, second: 0, of: d) ?? d
        if e <= d { e = cal.date(byAdding: .day, value: 1, to: e) ?? e }
        return e
    }

    static func adjust(_ r: UNNotificationRequest) -> UNNotificationRequest {
        guard isOn else { return r }
        let level = r.content.interruptionLevel
        if level == .timeSensitive || level == .critical { return r }
        let id = r.identifier.lowercased()
        if ["med", "dose", "alarm", "prn"].contains(where: { id.contains($0) }) { return r }
        let fire: Date? = {
            if let t = r.trigger as? UNCalendarNotificationTrigger { return t.nextTriggerDate() }
            if let t = r.trigger as? UNTimeIntervalNotificationTrigger { return t.nextTriggerDate() }
            if r.trigger == nil { return Date() }
            return nil                                           // location triggers: leave as they are
        }()
        guard let fire, isQuiet(fire), let c = r.content.mutableCopy() as? UNMutableNotificationContent else { return r }
        let repeats = (r.trigger as? UNCalendarNotificationTrigger)?.repeats == true || (r.trigger as? UNTimeIntervalNotificationTrigger)?.repeats == true
        if holdUntilMorning && !repeats {
            let when = endOfQuiet(after: fire)
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: when)
            return UNNotificationRequest(identifier: r.identifier, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        }
        c.sound = nil
        c.interruptionLevel = .passive
        return UNNotificationRequest(identifier: r.identifier, content: c, trigger: r.trigger)
    }
}

extension UNUserNotificationCenter {
    /// Every Keel alert goes through here, so quiet hours apply everywhere.
    func addKeel(_ request: UNNotificationRequest, withCompletionHandler done: (@Sendable (Error?) -> Void)? = nil) {
        add(QuietHours.adjust(request), withCompletionHandler: done)
    }
    func addKeel(_ request: UNNotificationRequest) async throws {
        try await add(QuietHours.adjust(request))
    }
}
