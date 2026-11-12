import SwiftUI
import EventKit

/// World clock with a time converter: "if it's 3 PM here, what time is it for them?"
struct WorldClockView: View {
    @AppStorage("worldclock.zones") private var zonesRaw = "Europe/London,America/Los_Angeles"
    @State private var offsetMinutes = 0.0
    @State private var adding = false

    private var zones: [TimeZone] { zonesRaw.split(separator: ",").compactMap { TimeZone(identifier: String($0)) } }
    private var moment: Date { Date().addingTimeInterval(offsetMinutes * 60) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(offsetMinutes == 0 ? "Right now" : "If it's \(moment.formatted(date: .omitted, time: .shortened)) here")
                        .font(DS.Font.headline)
                    Slider(value: $offsetMinutes, in: -720...720, step: 30)
                    if offsetMinutes != 0 { Button("Back to now") { offsetMinutes = 0 }.font(DS.Font.caption) }
                }
            } footer: { Text("Drag to find a time that works in every city.") }
            Section("Cities") {
                ForEach(zones, id: \.identifier) { z in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(city(z)).font(DS.Font.headline)
                            Text(diff(z)).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        let hour = hourIn(z)
                        Image(systemName: hour >= 7 && hour < 19 ? "sun.max.fill" : "moon.fill")
                            .foregroundStyle(hour >= 9 && hour < 18 ? DS.Palette.calm : DS.Palette.inkSoft)
                        Text(moment.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: z)))
                            .font(.title3.monospacedDigit())
                    }
                }
                .onDelete { idx in
                    var list = zones.map(\.identifier); list.remove(atOffsets: idx)
                    zonesRaw = list.joined(separator: ",")
                }
                Button("Add city", systemImage: "plus") { adding = true }
            }
        }
        .navigationTitle("World Clock")
        .sheet(isPresented: $adding) {
            ZonePicker { id in
                var list = zones.map(\.identifier)
                if !list.contains(id) { list.append(id) }
                zonesRaw = list.joined(separator: ",")
            }
        }
    }

    private func city(_ z: TimeZone) -> String {
        z.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? z.identifier
    }
    private func hourIn(_ z: TimeZone) -> Int {
        var c = Calendar.current; c.timeZone = z
        return c.component(.hour, from: moment)
    }
    private func diff(_ z: TimeZone) -> String {
        let h = Double(z.secondsFromGMT(for: moment) - TimeZone.current.secondsFromGMT(for: moment)) / 3600
        if h == 0 { return "Same time" }
        let n = h == h.rounded() ? String(Int(abs(h))) : String(format: "%.1f", abs(h))
        return "\(n)h \(h > 0 ? "ahead" : "behind")"
    }
}

private struct ZonePicker: View {
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List(TimeZone.knownTimeZoneIdentifiers.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search.replacingOccurrences(of: " ", with: "_")) }, id: \.self) { id in
                Button(id.replacingOccurrences(of: "_", with: " ")) { onPick(id); dismiss() }
            }
            .searchable(text: $search, prompt: "City")
            .navigationTitle("Add City")
            .toolbar { Button("Cancel") { dismiss() } }
        }
    }
}

/// Reusable event types: "1:1 · 30 min", "Gym · 1 hr", "Deep work · 2 hr".
struct EventTemplate: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var minutes: Int
    var location: String = ""

    static let key = "event.templates"
    static var all: [EventTemplate] {
        get {
            guard let d = UserDefaults.standard.data(forKey: key), let t = try? JSONDecoder().decode([EventTemplate].self, from: d) else {
                return [EventTemplate(title: "1:1", minutes: 30), EventTemplate(title: "Deep work", minutes: 120), EventTemplate(title: "Gym", minutes: 60)]
            }
            return t
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    /// An unsaved event filled from the template, to open in the event editor.
    @MainActor func makeEvent(start: Date) -> EKEvent {
        let store = CalendarService.shared.store
        let e = EKEvent(eventStore: store)
        e.title = title
        e.startDate = start
        e.endDate = start.addingTimeInterval(Double(minutes * 60))
        e.location = location.isEmpty ? nil : location
        e.calendar = store.defaultCalendarForNewEvents
        return e
    }
}

struct EventTemplatesView: View {
    @State private var items = EventTemplate.all
    @State private var title = ""
    @State private var minutes = 60

    var body: some View {
        List {
            Section {
                ForEach(items) { t in
                    LabeledContent(t.title, value: t.minutes >= 60 ? "\(t.minutes / 60)h\(t.minutes % 60 == 0 ? "" : " \(t.minutes % 60)m")" : "\(t.minutes)m")
                }
                .onDelete { items.remove(atOffsets: $0); EventTemplate.all = items }
            } footer: { Text("Use these from Calendar → + → From template.") }
            Section("New template") {
                TextField("Name", text: $title)
                Stepper("\(minutes) minutes", value: $minutes, in: 5...480, step: 5)
                Button("Add") {
                    items.append(EventTemplate(title: title, minutes: minutes)); EventTemplate.all = items; title = ""
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("Event Templates")
    }
}
