import Foundation
import EventKit
import MapKit
import CoreLocation
import UserNotifications

/// "Leave by 2:35 PM": for today's events with a real address, Keel checks travel time from where you are
/// and alerts you with a 10-minute buffer. Uses Apple Maps; nothing leaves your phone except the route request.
@MainActor
enum LeaveBy {
    static let bufferMinutes = 10
    private(set) static var times: [String: Date] = [:]     // event id → leave-by time, for Today

    static var isOn: Bool { UserDefaults.standard.object(forKey: "leaveBy.on") as? Bool ?? true }
    static var transport: MKDirectionsTransportType {
        switch UserDefaults.standard.string(forKey: "leaveBy.transport") {
        case "transit": .transit
        case "walking": .walking
        default: .automobile
        }
    }

    static func isVirtual(_ location: String) -> Bool {
        let l = location.lowercased()
        return ["zoom", "meet.google", "teams", "webex", "http", "facetime", "online", "call"].contains { l.contains($0) }
    }

    static func refresh() async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("leaveby.") }
        center.removePendingNotificationRequests(withIdentifiers: old)
        times = [:]
        guard isOn, let here = CLLocationManager().location else { return }
        let now = Date()
        let events = CalendarService.shared.events(from: now, to: now.addingTimeInterval(12 * 3600))
            .filter { !$0.isAllDay && $0.startDate > now }
        for e in events.prefix(8) {
            guard let loc = e.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty, !isVirtual(loc),
                  let dest = await destination(for: e, text: loc, near: here.coordinate) else { continue }
            let req = MKDirections.Request()
            req.source = .forCurrentLocation()
            req.destination = dest
            req.transportType = transport
            req.arrivalDate = e.startDate
            guard let eta = try? await MKDirections(request: req).calculateETA(), eta.expectedTravelTime > 5 * 60 else { continue }
            let leave = e.startDate.addingTimeInterval(-eta.expectedTravelTime - Double(bufferMinutes * 60))
            let id = e.calendarItemIdentifier
            times[id] = leave
            guard leave > now else { continue }
            let c = UNMutableNotificationContent()
            c.title = "Leave now for \(e.title ?? "your event")"
            c.body = "\(Int(eta.expectedTravelTime / 60)) min \(transport == .walking ? "walk" : transport == .transit ? "by transit" : "drive") to \(loc). Starts at \(e.startDate.formatted(date: .omitted, time: .shortened))."
            c.sound = .default
            c.interruptionLevel = .timeSensitive
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: leave)
            try? await center.add(UNNotificationRequest(identifier: "leaveby.\(id)", content: c,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }

    private static func destination(for e: EKEvent, text: String, near: CLLocationCoordinate2D) async -> MKMapItem? {
        if let geo = e.structuredLocation?.geoLocation {
            return MKMapItem(placemark: MKPlacemark(coordinate: geo.coordinate))
        }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = text
        req.region = MKCoordinateRegion(center: near, latitudinalMeters: 80_000, longitudinalMeters: 80_000)
        return try? await MKLocalSearch(request: req).start().mapItems.first
    }
}
