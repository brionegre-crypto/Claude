import SwiftUI
import SwiftData

/// Upcoming trips, grouped from the bookings Keel found in your email.
struct TripsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Reservation.start) private var all: [Reservation]
    @State private var error: String?

    /// Bookings within 2 days of each other belong to the same trip.
    private var trips: [[Reservation]] {
        let upcoming = all.filter { !$0.isHidden && ($0.end ?? $0.start) > Date().addingTimeInterval(-86_400) }
        var groups: [[Reservation]] = []
        for r in upcoming {
            if let lastEnd = groups.last?.map({ $0.end ?? $0.start }).max(), r.start.timeIntervalSince(lastEnd) < 2 * 86_400 {
                groups[groups.count - 1].append(r)
            } else {
                groups.append([r])
            }
        }
        return groups
    }

    var body: some View {
        List {
            if trips.isEmpty {
                ContentUnavailableView("No upcoming trips", systemImage: "airplane.departure",
                                       description: Text("Flight, hotel, car, train and restaurant confirmations in your email show up here automatically."))
            }
            ForEach(Array(trips.enumerated()), id: \.offset) { _, trip in
                Section(header: Text(header(trip))) {
                    ForEach(trip) { r in row(r) }
                }
            }
        }
        .navigationTitle("Trips")
        .alert("Couldn't add to Calendar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {} message: { Text(error ?? "") }
        .task { await TripScanner.backfillIfNeeded(ctx: ctx) }
    }

    private func header(_ trip: [Reservation]) -> String {
        let place = trip.first { $0.kind == "hotel" }?.location ?? trip.first { !$0.location.isEmpty }?.location ?? "Trip"
        let start = trip.first!.start, end = trip.compactMap(\.end).max() ?? trip.last!.start
        let days = Calendar.current.dateComponents([.day], from: Date(), to: start).day ?? 0
        let when = days <= 0 ? "now" : days == 1 ? "tomorrow" : "in \(days) days"
        return "\(place) · \(start.formatted(.dateTime.month(.abbreviated).day()))–\(end.formatted(.dateTime.month(.abbreviated).day())) · \(when)"
    }

    private func row(_ r: Reservation) -> some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            Image(systemName: r.icon).foregroundStyle(DS.Palette.accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(r.title).font(DS.Font.headline)
                Text(r.kind == "hotel"
                     ? "Check in \(r.start.formatted(.dateTime.weekday(.abbreviated).month().day()))" + (r.end.map { " · out \($0.formatted(.dateTime.weekday(.abbreviated).month().day()))" } ?? "")
                     : r.start.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute()))
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                if !r.confirmation.isEmpty {
                    Text("Confirmation \(r.confirmation)").font(DS.Font.caption.monospaced()).textSelection(.enabled)
                }
                if !r.detail.isEmpty { Text(r.detail).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft) }
                HStack {
                    if r.calendarEventId == nil {
                        Button("Add to Calendar", systemImage: "calendar.badge.plus") {
                            do { try TripScanner.addToCalendar(r); Haptics.success() } catch { self.error = error.localizedDescription }
                        }
                    } else {
                        Label("In Calendar", systemImage: "checkmark").foregroundStyle(DS.Palette.calm)
                    }
                }
                .font(DS.Font.caption).buttonStyle(.borderless)
            }
        }
        .swipeActions { Button("Hide") { r.isHidden = true }.tint(.gray) }
        .contextMenu {
            if !r.confirmation.isEmpty { Button("Copy confirmation", systemImage: "doc.on.doc") { UIPasteboard.general.string = r.confirmation } }
            Button("Not a booking", systemImage: "eye.slash", role: .destructive) { r.isHidden = true }
        }
    }
}

/// Today: the next booking in the coming 3 days.
struct TripTodayCard: View {
    @Query(sort: \Reservation.start) private var all: [Reservation]

    var body: some View {
        let soon = all.filter { !$0.isHidden && $0.start > Date().addingTimeInterval(-3600) && $0.start < Date().addingTimeInterval(3 * 86_400) }
        if let r = soon.first {
            NavigationLink { TripsView() } label: {
                GlassCard {
                    HStack(spacing: DS.Space.m) {
                        Image(systemName: r.icon).font(.title2).foregroundStyle(DS.Palette.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                            Text(r.start.formatted(.dateTime.weekday(.wide).hour().minute()) + (r.confirmation.isEmpty ? "" : " · \(r.confirmation)"))
                                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        Text(r.start, style: .relative).font(DS.Font.caption).foregroundStyle(DS.Palette.meeting)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}
