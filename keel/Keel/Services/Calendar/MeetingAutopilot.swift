import Foundation
import EventKit
import UserNotifications
#if !targetEnvironment(macCatalyst)
import ActivityKit
#endif
import UIKit

/// Finds the video-call link in a calendar event (Zoom, Google Meet, Teams, Webex, FaceTime and others).
enum MeetingLink {
    static let hosts: [(String, String)] = [
        ("zoom.us", "Zoom"), ("zoom.com", "Zoom"), ("zoomgov.com", "Zoom"),
        ("meet.google.com", "Google Meet"),
        ("teams.microsoft.com", "Teams"), ("teams.live.com", "Teams"),
        ("webex.com", "Webex"), ("facetime.apple.com", "FaceTime"),
        ("whereby.com", "Whereby"), ("gotomeeting.com", "GoTo"), ("meet.goto.com", "GoTo"),
        ("chime.aws", "Chime"), ("bluejeans.com", "BlueJeans"), ("around.co", "Around"),
        ("meet.jit.si", "Jitsi"), ("discord.gg", "Discord"), ("app.slack.com/huddle", "Slack huddle"),
    ]

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func find(_ e: EKEvent) -> URL? {
        if let u = e.url, service(u) != nil { return u }
        for text in [e.location, e.notes] {
            if let t = text, let u = find(in: t) { return u }
        }
        return nil
    }

    static func find(in text: String) -> URL? {
        guard let detector else { return nil }
        let ns = text as NSString
        for m in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if let u = m.url, service(u) != nil { return u }
        }
        return nil
    }

    static func service(_ url: URL) -> String? {
        let s = (url.host ?? "").lowercased() + url.path.lowercased()
        return hosts.first { s.contains($0.0) }?.1
    }
}

/// Meeting autopilot: a nudge as each meeting starts with one-tap Join and Record,
/// plus a Lock Screen / Dynamic Island timer showing how long is left.
@MainActor
enum MeetingAutopilot {
    static let category = "MEETING_START"
    static let joinAction = "MEETING_JOIN"
    static let recordAction = "MEETING_RECORD"

    static var isOn: Bool { UserDefaults.standard.object(forKey: "meeting.autopilot.on") as? Bool ?? true }
    static var leadMinutes: Int { UserDefaults.standard.object(forKey: "meeting.autopilot.lead") as? Int ?? 1 }
    static var liveTimerOn: Bool { UserDefaults.standard.object(forKey: "meeting.autopilot.live") as? Bool ?? true }
    /// Only nudge for real meetings (other people or a call link), not solo blocks like "Gym".
    static func isMeeting(_ e: EKEvent) -> Bool {
        !e.isAllDay && (e.attendees?.isEmpty == false || MeetingLink.find(e) != nil)
    }

    static var categoryDefinition: UNNotificationCategory {
        UNNotificationCategory(identifier: category, actions: [
            UNNotificationAction(identifier: joinAction, title: "Join", options: [.foreground]),
            UNNotificationAction(identifier: recordAction, title: "Record notes", options: [.foreground]),
        ], intentIdentifiers: [])
    }

    /// Schedules start nudges for the next 24 hours. Called on every sync.
    static func refresh() async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("meeting.") }
        center.removePendingNotificationRequests(withIdentifiers: old)
        endFinished()
        guard isOn else { return }
        let now = Date()
        let lead = Double(leadMinutes * 60)
        let events = CalendarService.shared.events(from: now, to: now.addingTimeInterval(24 * 3600))
            .filter { isMeeting($0) && $0.startDate.addingTimeInterval(-lead) > now && $0.status != .canceled }
        for e in events.prefix(12) {
            let c = UNMutableNotificationContent()
            let title = e.title ?? "Meeting"
            let link = MeetingLink.find(e)
            c.title = leadMinutes == 0 ? "\(title) is starting" : "\(title) starts in \(leadMinutes) min"
            c.body = link.flatMap(MeetingLink.service).map { "Tap Join to open \($0), or Record to take AI notes." }
                ?? "Tap Record notes and Keel writes up the meeting for you."
            c.sound = .default
            c.interruptionLevel = .timeSensitive
            c.categoryIdentifier = category
            c.threadIdentifier = "meetings"
            var info: [String: Any] = ["meetingEventId": e.calendarItemIdentifier]
            if let link { info["joinURL"] = link.absoluteString }
            c.userInfo = info
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: e.startDate.addingTimeInterval(-lead))
            try? await center.add(UNNotificationRequest(identifier: "meeting.\(e.calendarItemIdentifier).\(Int(e.startDate.timeIntervalSince1970))",
                                                        content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }

    /// Notification buttons: Join opens the call, Record opens AI meeting notes. Either starts the live timer.
    static func handle(action: String, info: [AnyHashable: Any]) {
        let event = (info["meetingEventId"] as? String).flatMap { CalendarService.shared.store.calendarItem(withIdentifier: $0) as? EKEvent }
        let link = (info["joinURL"] as? String).flatMap { URL(string: $0) }
        if let event { startActivity(for: event) }
        switch action {
        case joinAction: if let link { UIApplication.shared.open(link) }
        case recordAction: AppRouter.shared.showRecorder = true
        default: if let event, MeetingLink.find(event) == nil { AppRouter.shared.tab = .calendar }
        }
    }

    // MARK: Live timer (Lock Screen + Dynamic Island)

    /// When Keel opens during (or just before) a meeting, show how long is left.
    static func syncActivity() {
        endFinished()
        guard isOn, liveTimerOn else { return }
        let now = Date()
        let current = CalendarService.shared.events(from: now.addingTimeInterval(-6 * 3600), to: now.addingTimeInterval(600))
            .filter { isMeeting($0) && $0.startDate <= now.addingTimeInterval(300) && $0.endDate > now && $0.status != .canceled }
            .sorted { $0.startDate > $1.startDate }
            .first
        if let current { startActivity(for: current) }
    }

    static func startActivity(for e: EKEvent) {
        #if !targetEnvironment(macCatalyst)
        guard liveTimerOn, ActivityAuthorizationInfo().areActivitiesEnabled, e.endDate > Date() else { return }
        let id = e.calendarItemIdentifier
        if Activity<MeetingActivityAttributes>.activities.contains(where: { $0.attributes.eventId == id && $0.activityState == .active }) { return }
        let link = MeetingLink.find(e)
        let attrs = MeetingActivityAttributes(eventId: id, title: e.title ?? "Meeting",
                                              joinURL: link?.absoluteString, service: link.flatMap(MeetingLink.service))
        let state = MeetingActivityAttributes.ContentState(start: e.startDate, end: e.endDate, recording: false)
        let content = ActivityContent(state: state, staleDate: e.endDate.addingTimeInterval(60))
        Task {
            // One meeting timer at a time: the previous one ends first.
            for a in Activity<MeetingActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
            _ = try? Activity.request(attributes: attrs, content: content)
        }
            #endif
    }

    /// Shows a red dot on the Lock Screen timer while Keel is recording the meeting.
    static func setRecording(_ on: Bool) {
        #if !targetEnvironment(macCatalyst)
        Task {
            for a in Activity<MeetingActivityAttributes>.activities where a.activityState == .active {
                var s = a.content.state
                guard s.recording != on else { continue }
                s.recording = on
                await a.update(ActivityContent(state: s, staleDate: s.end.addingTimeInterval(60)))
            }
        }
            #endif
    }

    static func endFinished() {
        #if !targetEnvironment(macCatalyst)
        Task {
            let now = Date()
            for a in Activity<MeetingActivityAttributes>.activities where a.content.state.end <= now {
                await a.end(nil, dismissalPolicy: .immediate)
            }
        }
            #endif
    }

    static func endAll() {
        #if !targetEnvironment(macCatalyst)
        Task {
            for a in Activity<MeetingActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        }
            #endif
    }
}
