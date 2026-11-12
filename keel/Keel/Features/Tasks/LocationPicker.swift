import SwiftUI
import MapKit

/// "Remind me when I get to…": search Apple Maps for a place and attach it to a task.
/// It fires through iPhone's location alerts (or Apple Reminders' if the task syncs there), even when Keel is closed.
struct LocationPicker: View {
    @Bindable var task: TaskItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Remind me", selection: $task.remindOnArrive) {
                        Text("When I arrive").tag(true)
                        Text("When I leave").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                let places = LocationReminders.places
                if !places.isEmpty && query.isEmpty {
                    Section("Your places") {
                        ForEach(places) { p in
                            Button { pick(name: p.name, latitude: p.latitude, longitude: p.longitude) } label: {
                                Label(p.name, systemImage: p.icon).foregroundStyle(DS.Palette.ink)
                            }
                        }
                    }
                }
                Section {
                    NavigationLink { PlacesView() } label: { Label("Manage places", systemImage: "mappin.and.ellipse") }
                }
                if searching { ProgressView() }
                ForEach(results, id: \.self) { item in
                    Button { pick(item) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "Place").font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                            Text(item.placemark.title ?? "").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                        }
                    }
                }
                if task.locationName != nil {
                    Section {
                        Button("Remove location", role: .destructive) {
                            task.locationName = nil; task.latitude = nil; task.longitude = nil
                            Task { await LocationReminders.refresh(ctx: ctx) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Location")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Gym, Trader Joe's, an address…")
            .onSubmit(of: .search) { Task { await search() } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func search() async {
        guard !query.isEmpty else { return }
        searching = true; defer { searching = false }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        results = (try? await MKLocalSearch(request: req).start().mapItems) ?? []
    }

    private func pick(_ item: MKMapItem) {
        let c = item.placemark.coordinate
        pick(name: item.name ?? query, latitude: c.latitude, longitude: c.longitude)
    }

    private func pick(name: String, latitude: Double, longitude: Double) {
        task.locationName = name
        task.latitude = latitude
        task.longitude = longitude
        task.updatedAt = Date()
        try? CalendarService.shared.push(task)
        LocationReminders.authorize()
        Task { await LocationReminders.refresh(ctx: ctx) }       // Keel's own alert, if it isn't in Reminders
        Haptics.success()
        dismiss()
    }
}
