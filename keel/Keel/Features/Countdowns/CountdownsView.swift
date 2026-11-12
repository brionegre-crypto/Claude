import SwiftUI
import SwiftData
import Contacts

/// Countdowns to the dates that matter: trips, launches, birthdays (imported from Contacts).
struct CountdownsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Countdown.date) private var countdowns: [Countdown]
    @State private var showNew = false
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        List {
            if let message { Text(message).font(DS.Font.caption).foregroundStyle(DS.Palette.calm).listRowBackground(Color.clear) }
            if !countdowns.contains(where: { $0.daysLeft >= 0 }) {
                ContentUnavailableView("No countdowns yet", systemImage: "hourglass",
                                       description: Text("Add a trip, launch or deadline with ＋, or import birthdays below."))
                    .listRowBackground(Color.clear)
            }
            ForEach(countdowns.filter { $0.daysLeft >= 0 }) { c in
                HStack(spacing: DS.Space.m) {
                    Text(c.emoji).font(.largeTitle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.title).font(DS.Font.headline)
                        Text(c.date.formatted(date: .complete, time: .omitted)).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                    Spacer()
                    VStack(spacing: 0) {
                        Text(c.daysLeft == 0 ? "Today" : "\(c.daysLeft)").font(DS.Font.title).foregroundStyle(DS.Palette.accent)
                        if c.daysLeft > 0 { Text(c.daysLeft == 1 ? "day" : "days").font(.caption2).foregroundStyle(DS.Palette.inkSoft) }
                    }
                }
                .swipeActions { Button(role: .destructive) { ctx.delete(c) } label: { Label("Delete", systemImage: "trash") } }
            }
            Section {
                Button(importing ? "Importing…" : "Import birthdays from Contacts") { Task { await importBirthdays() } }
                    .disabled(importing)
            } footer: { Text("Birthdays roll over to next year automatically.") }
        }
        .navigationTitle("Countdowns")
        .toolbar { Button { showNew = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add") }
        .sheet(isPresented: $showNew) { NewCountdownSheet() }
        .onAppear { Countdowns.rollBirthdays(ctx) }
    }

    private func importBirthdays() async {
        importing = true; defer { importing = false }
        let n = await Countdowns.importBirthdays(ctx)
        withAnimation { message = n < 0 ? "Keel needs Contacts access (Settings → Keel)." : n == 0 ? "No new birthdays found." : "Added \(n) birthday\(n == 1 ? "" : "s")." }
    }
}

@MainActor
enum Countdowns {
    /// Returns how many were added, or -1 if access was refused.
    static func importBirthdays(_ ctx: ModelContext) async -> Int {
        let store = CNContactStore()
        guard (try? await store.requestAccess(for: .contacts)) == true else { return -1 }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactBirthdayKey] as [CNKeyDescriptor]
        let existing = Set(((try? ctx.fetch(FetchDescriptor<Countdown>())) ?? []).map(\.title))
        let found: [(String, DateComponents)] = await Task.detached {
            var out: [(String, DateComponents)] = []
            try? store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { c, _ in
                if let b = c.birthday, b.month != nil, b.day != nil {
                    out.append(("\(c.givenName) \(c.familyName)".trimmingCharacters(in: .whitespaces), b))
                }
            }
            return out
        }.value
        var added = 0
        for (name, b) in found where !name.isEmpty {
            let title = "\(name)'s birthday"
            guard !existing.contains(title), let next = nextOccurrence(month: b.month!, day: b.day!) else { continue }
            let c = Countdown(title: title, date: next)
            c.emoji = "🎂"
            ctx.insert(c)
            added += 1
        }
        return added
    }

    static func nextOccurrence(month: Int, day: Int) -> Date? {
        Calendar.current.nextDate(after: Calendar.current.startOfDay(for: Date()).addingTimeInterval(-1),
                                  matching: DateComponents(month: month, day: day), matchingPolicy: .nextTime)
    }

    /// Birthdays that have passed move to next year.
    static func rollBirthdays(_ ctx: ModelContext) {
        for c in (try? ctx.fetch(FetchDescriptor<Countdown>())) ?? [] where c.emoji == "🎂" && c.daysLeft < 0 {
            let comps = Calendar.current.dateComponents([.month, .day], from: c.date)
            if let next = nextOccurrence(month: comps.month ?? 1, day: comps.day ?? 1) { c.date = next }
        }
    }
}

struct NewCountdownSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var emoji = "🎉"
    @State private var date = Calendar.current.date(byAdding: .day, value: 30, to: Date())!

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    TextField("🎉", text: $emoji).frame(width: 44).font(.title)
                    TextField("Trip to Japan, launch day…", text: $title)
                }
                DatePicker("Date", selection: $date, in: Date()..., displayedComponents: .date)
            }
            .navigationTitle("New Countdown")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let c = Countdown(title: title, date: date)
                        c.emoji = emoji.isEmpty ? "🎉" : String(emoji.prefix(2))
                        ctx.insert(c)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
