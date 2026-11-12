import Foundation
import SwiftUI
import SwiftData
import CoreLocation
import MapKit
import UserNotifications

/// "Remind me when I get to the store / leave work", using iPhone's own location triggers.
/// They fire even when Keel is closed and need only "While Using" location access.
/// Tasks already synced to Apple Reminders use Reminders' location alert instead, so you never get two.
@MainActor
enum LocationReminders {
    struct Place: Codable, Hashable, Identifiable {
        var id = UUID()
        var name: String
        var icon: String
        var latitude: Double
        var longitude: Double
        var radius: Double = 150
    }

    static let placesKey = "places.v1"
    static let checklistKey = "leaving.checklist"
    static let checklistOnKey = "leaving.on"
    /// iPhone watches at most 20 places per app; leave room for the leaving-home check.
    static let maxTaskRegions = 18

    static var places: [Place] {
        get {
            guard let d = UserDefaults.standard.data(forKey: placesKey), let p = try? JSONDecoder().decode([Place].self, from: d) else { return [] }
            return p
        }
        set { if let d = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(d, forKey: placesKey) } }
    }

    static var home: Place? { places.first { $0.name.lowercased() == "home" } }

    static var checklist: [String] {
        get { UserDefaults.standard.stringArray(forKey: checklistKey) ?? ["Keys", "Wallet", "Phone", "Meds", "Charger"] }
        set { UserDefaults.standard.set(newValue, forKey: checklistKey) }
    }
    static var checklistOn: Bool { UserDefaults.standard.object(forKey: checklistOnKey) as? Bool ?? true }

    static func authorize() {
        let m = CLLocationManager()
        if m.authorizationStatus == .notDetermined { m.requestWhenInUseAuthorization() }
    }

    static var canUseLocation: Bool {
        let s = CLLocationManager().authorizationStatus
        return s == .authorizedWhenInUse || s == .authorizedAlways
    }

    /// Re-creates every location alert. Called on sync and whenever a task's place changes.
    static func refresh(ctx: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("loc.") }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard canUseLocation else { return }

        let tasks = ((try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? [])
            .filter { $0.latitude != nil && $0.longitude != nil && $0.ekReminderId == nil }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        for t in tasks.prefix(maxTaskRegions) {
            guard let lat = t.latitude, let lon = t.longitude else { continue }
            let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon), radius: 150, identifier: "loc.task.\(t.id)")
            region.notifyOnEntry = t.remindOnArrive
            region.notifyOnExit = !t.remindOnArrive
            let c = UNMutableNotificationContent()
            c.title = t.title
            c.body = t.remindOnArrive ? "You're at \(t.locationName ?? "the place")." : "You just left \(t.locationName ?? "the place")."
            c.sound = .default
            c.categoryIdentifier = TaskAlerts.category
            c.userInfo = ["taskId": t.id.uuidString]
            c.interruptionLevel = .timeSensitive
            try? await center.add(UNNotificationRequest(identifier: "loc.task.\(t.id)", content: c,
                                                        trigger: UNLocationNotificationTrigger(region: region, repeats: true)))
        }

        // "Don't forget" as you leave home.
        if checklistOn, let h = home {
            let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: h.latitude, longitude: h.longitude), radius: max(100, h.radius), identifier: "loc.leaving")
            region.notifyOnEntry = false
            region.notifyOnExit = true
            let c = UNMutableNotificationContent()
            c.title = "Leaving home? Don't forget"
            c.body = checklist.joined(separator: " · ")
            c.sound = .default
            c.interruptionLevel = .timeSensitive
            c.userInfo = ["deeplink": "com.keel.app://leaving"]
            try? await center.add(UNNotificationRequest(identifier: "loc.leaving", content: c,
                                                        trigger: UNLocationNotificationTrigger(region: region, repeats: true)))
        }
    }

    /// Where you are right now, named by Apple Maps when possible.
    static func currentPlace(named name: String, icon: String) async -> Place? {
        guard let loc = CLLocationManager().location else { return nil }
        return Place(name: name, icon: icon, latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
    }
}

// MARK: - Places

struct PlacesView: View {
    @Environment(\.modelContext) private var ctx
    @State private var places = LocationReminders.places
    @State private var checklist = LocationReminders.checklist
    @AppStorage(LocationReminders.checklistOnKey) private var checklistOn = true
    @State private var newItem = ""
    @State private var adding: String?
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var message: String?

    var body: some View {
        List {
            if !LocationReminders.canUseLocation {
                Section {
                    Button("Allow Location Access") { LocationReminders.authorize() }
                } footer: { Text("Location reminders need “While Using the App” access. They still fire when Keel is closed.") }
            }
            Section {
                ForEach(places) { p in
                    Label(p.name, systemImage: p.icon)
                }
                .onDelete { places.remove(atOffsets: $0); save() }
                ForEach(["Home", "Work", "Gym", "Store"].filter { n in !places.contains { $0.name == n } }, id: \.self) { n in
                    Button { adding = n; query = "" } label: { Label("Add \(n)", systemImage: "plus.circle") }
                }
                Button { adding = ""; query = "" } label: { Label("Add a Place", systemImage: "mappin.and.ellipse") }
            } header: { Text("Your places") } footer: { Text("Pick them when you add a location to a task: “remind me when I get to the gym”.") }

            Section {
                Toggle("Leaving-Home Checklist", isOn: $checklistOn)
                if checklistOn {
                    ForEach(checklist, id: \.self) { Text($0) }
                        .onDelete { checklist.remove(atOffsets: $0); LocationReminders.checklist = checklist; refresh() }
                    HStack {
                        TextField("Add item", text: $newItem).onSubmit(addItem)
                        Button("Add", action: addItem).disabled(newItem.isEmpty)
                    }
                }
            } header: { Text("Don't forget") } footer: {
                Text(LocationReminders.home == nil ? "Add Home above, then Keel reminds you of these as you leave."
                                                   : "As you leave home, Keel shows this list so nothing gets left behind.")
            }
            if let message { Text(message).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft) }
        }
        .navigationTitle("Places")
        .onChange(of: checklistOn) { refresh() }
        .sheet(item: Binding(get: { adding.map { AddingPlace(name: $0) } }, set: { if $0 == nil { adding = nil } })) { a in
            NavigationStack {
                List {
                    Section {
                        Button {
                            Task {
                                if let p = await LocationReminders.currentPlace(named: a.name.isEmpty ? "Here" : a.name, icon: icon(for: a.name)) {
                                    places.append(p); save(); adding = nil
                                } else { message = "Couldn't find your location. Allow location access and try again." ; adding = nil }
                            }
                        } label: { Label("Use My Current Location", systemImage: "location.fill") }
                    }
                    ForEach(results, id: \.self) { item in
                        Button {
                            let c = item.placemark.coordinate
                            let name = a.name.isEmpty ? (item.name ?? query) : a.name
                            places.append(.init(name: name, icon: icon(for: name), latitude: c.latitude, longitude: c.longitude))
                            save(); adding = nil
                        } label: {
                            VStack(alignment: .leading) {
                                Text(item.name ?? "Place").foregroundStyle(DS.Palette.ink)
                                Text(item.placemark.title ?? "").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                            }
                        }
                    }
                }
                .navigationTitle(a.name.isEmpty ? "Add a Place" : "Set \(a.name)")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search an address or place")
                .onSubmit(of: .search) { Task { await search() } }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { adding = nil } } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    struct AddingPlace: Identifiable { let name: String; var id: String { name } }

    private func icon(for name: String) -> String {
        switch name.lowercased() {
        case "home": "house.fill"
        case "work": "briefcase.fill"
        case "gym": "dumbbell.fill"
        case "store": "cart.fill"
        default: "mappin.circle.fill"
        }
    }

    private func addItem() {
        let t = newItem.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !checklist.contains(t) else { return }
        checklist.append(t); newItem = ""
        LocationReminders.checklist = checklist
        refresh()
    }

    private func save() { LocationReminders.places = places; refresh(); Haptics.success() }
    private func refresh() { Task { await LocationReminders.refresh(ctx: ctx) } }

    private func search() async {
        guard !query.isEmpty else { return }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        if let here = CLLocationManager().location {
            req.region = MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 50_000, longitudinalMeters: 50_000)
        }
        results = (try? await MKLocalSearch(request: req).start().mapItems) ?? []
    }
}

/// Opened from the "Leaving home?" alert: tick things off on the way out.
struct LeavingChecklistView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var done = Set<String>()
    private let items = LocationReminders.checklist

    var body: some View {
        NavigationStack {
            List(items, id: \.self) { item in
                Button {
                    if done.contains(item) { done.remove(item) } else { done.insert(item); Haptics.tap() }
                    if done.count == items.count { Haptics.success() }
                } label: {
                    Label(item, systemImage: done.contains(item) ? "checkmark.circle.fill" : "circle")
                        .font(DS.Font.headline)
                        .foregroundStyle(done.contains(item) ? DS.Palette.calm : DS.Palette.ink)
                }
            }
            .navigationTitle(done.count == items.count ? "All set. Go!" : "Got everything?")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
