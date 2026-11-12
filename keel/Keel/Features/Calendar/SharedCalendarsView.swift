import SwiftUI
import EventKit

/// Family / shared calendars side by side for a day, plus "when are we all free?".
struct SharedCalendarsView: View {
    @State private var calendars: [EKCalendar] = []
    @State private var selected: Set<String> = Self.savedSelection
    @State private var day = Date()
    @State private var minMinutes = 60
    private let svc = CalendarService.shared

    private static var savedSelection: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "shared.calendars") ?? [])
    }

    private var chosen: [EKCalendar] { calendars.filter { selected.contains($0.calendarIdentifier) } }

    var body: some View {
        List {
            Section {
                DatePicker("Day", selection: $day, displayedComponents: .date)
            }
            Section("Calendars") {
                ForEach(calendars, id: \.calendarIdentifier) { c in
                    Button { toggle(c) } label: {
                        HStack {
                            Circle().fill(Color(cgColor: c.cgColor)).frame(width: 10, height: 10)
                            Text(c.title).foregroundStyle(DS.Palette.ink)
                            Text(c.source.title).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                            Spacer()
                            if selected.contains(c.calendarIdentifier) { Image(systemName: "checkmark").foregroundStyle(DS.Palette.accent) }
                        }
                    }
                }
            }
            if !chosen.isEmpty {
                Section {
                    Picker("At least", selection: $minMinutes) {
                        Text("30 min").tag(30); Text("1 hour").tag(60); Text("2 hours").tag(120)
                    }
                    let slots = commonFree()
                    if slots.isEmpty { Text("No shared free time between 8 AM and 9 PM.").foregroundStyle(DS.Palette.inkSoft) }
                    ForEach(slots, id: \.start) { s in
                        Label("\(s.start.formatted(date: .omitted, time: .shortened)) – \(s.end.formatted(date: .omitted, time: .shortened))",
                              systemImage: "person.3.fill").foregroundStyle(DS.Palette.calm)
                    }
                } header: { Text("Everyone's free") }
                ForEach(chosen, id: \.calendarIdentifier) { c in
                    Section(c.title) {
                        let evs = events(for: [c])
                        if evs.isEmpty { Text("Nothing scheduled").foregroundStyle(DS.Palette.inkSoft) }
                        ForEach(evs, id: \.eventIdentifier) { e in
                            HStack {
                                RoundedRectangle(cornerRadius: 2).fill(Color(cgColor: c.cgColor)).frame(width: 4)
                                VStack(alignment: .leading) {
                                    Text(e.title ?? "Busy")
                                    Text(e.isAllDay ? "All day" : "\(e.startDate.formatted(date: .omitted, time: .shortened)) – \(e.endDate.formatted(date: .omitted, time: .shortened))")
                                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Shared Calendars")
        .task {
            await svc.requestAccess()
            calendars = svc.store.calendars(for: .event).sorted { $0.title < $1.title }
            if selected.isEmpty { selected = Set(calendars.filter { $0.title.lowercased().contains("family") }.map(\.calendarIdentifier)) }
        }
    }

    private func toggle(_ c: EKCalendar) {
        if selected.contains(c.calendarIdentifier) { selected.remove(c.calendarIdentifier) } else { selected.insert(c.calendarIdentifier) }
        UserDefaults.standard.set(Array(selected), forKey: "shared.calendars")
        Haptics.tap()
    }

    private func events(for cals: [EKCalendar]) -> [EKEvent] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return svc.events(from: start, to: end, calendars: cals)
    }

    /// Gaps between 8 AM and 9 PM where no chosen calendar has a timed event.
    private func commonFree() -> [DateInterval] {
        let cal = Calendar.current
        guard let open = cal.date(bySettingHour: 8, minute: 0, second: 0, of: day),
              let close = cal.date(bySettingHour: 21, minute: 0, second: 0, of: day) else { return [] }
        let busy = events(for: chosen).filter { !$0.isAllDay }.map { DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate)) }
            .sorted { $0.start < $1.start }
        var cursor = max(open, cal.isDateInToday(day) ? Date() : open)
        var out: [DateInterval] = []
        for b in busy {
            if b.start > cursor, b.start.timeIntervalSince(cursor) >= Double(minMinutes * 60) { out.append(DateInterval(start: cursor, end: min(b.start, close))) }
            cursor = max(cursor, b.end)
            if cursor >= close { break }
        }
        if close > cursor, close.timeIntervalSince(cursor) >= Double(minMinutes * 60) { out.append(DateInterval(start: cursor, end: close)) }
        return out
    }
}
