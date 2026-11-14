import SwiftUI
import SwiftData
import Contacts
import CoreLocation
import WeatherKit
import NaturalLanguage
import UserNotifications

// MARK: - Home & car upkeep

/// Easy-to-forget upkeep as repeating tasks: pick what applies, say when you last did it, and Keel keeps track.
@MainActor
enum Upkeep {
    struct Item: Identifiable { let id: String; let title: String; let icon: String; let days: Int }
    static let items: [Item] = [
        .init(id: "hvac", title: "Replace the HVAC filter", icon: "fan", days: 90),
        .init(id: "smoke", title: "Test smoke & CO alarms", icon: "smoke", days: 180),
        .init(id: "alarmbatteries", title: "Change smoke alarm batteries", icon: "battery.25", days: 365),
        .init(id: "waterfilter", title: "Replace the water filter", icon: "drop", days: 180),
        .init(id: "dryer", title: "Clean the dryer vent", icon: "wind", days: 365),
        .init(id: "gutters", title: "Clean the gutters", icon: "house", days: 180),
        .init(id: "fridge", title: "Vacuum the fridge coils", icon: "refrigerator", days: 365),
        .init(id: "oil", title: "Car oil change", icon: "car", days: 180),
        .init(id: "tires", title: "Rotate the tires", icon: "circle.circle", days: 180),
        .init(id: "registration", title: "Renew the car registration", icon: "doc.text", days: 365),
        .init(id: "dentist", title: "Dentist checkup", icon: "mouth", days: 180),
        .init(id: "physical", title: "Yearly checkup", icon: "stethoscope", days: 365),
    ]
    static let key = "upkeep.tasks"          // [item id: task id]

    static var linked: [String: String] {
        get { (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func recurrence(_ days: Int) -> Recurrence {
        if days % 365 == 0 { return Recurrence(frequency: .yearly, interval: days / 365, fromCompletion: true) }
        if days % 30 == 0 { return Recurrence(frequency: .monthly, interval: days / 30, fromCompletion: true) }
        return Recurrence(frequency: .daily, interval: days, fromCompletion: true)
    }

    static func turnOn(_ item: Item, lastDone: Date, ctx: ModelContext) {
        let next = Calendar.current.date(byAdding: .day, value: item.days, to: Calendar.current.startOfDay(for: lastDone)) ?? Date()
        let t = TaskItem(title: item.title, dueDate: max(Calendar.current.startOfDay(for: Date()), next))
        t.listName = "Home"
        t.recurrence = recurrence(item.days)
        ctx.insert(t)
        try? CalendarService.shared.push(t)
        var l = linked; l[item.id] = t.id.uuidString; linked = l
    }

    static func turnOff(_ item: Item, ctx: ModelContext) {
        var l = linked
        if let s = l[item.id], let id = UUID(uuidString: s),
           let t = try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first {
            CalendarService.shared.removeReminder(for: t); TaskAlerts.cancel(t); ctx.delete(t)
        }
        l[item.id] = nil; linked = l
    }
}

struct UpkeepView: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var open: [TaskItem]
    @State private var adding: Upkeep.Item?
    @State private var lastDone = Date()
    @State private var tick = 0

    var body: some View {
        let _ = tick
        let linked = Upkeep.linked
        List {
            Section {
                ForEach(Upkeep.items) { item in
                    let task = linked[item.id].flatMap(UUID.init(uuidString:)).flatMap { id in open.first { $0.id == id } }
                    HStack {
                        Image(systemName: item.icon).frame(width: 26).foregroundStyle(DS.Palette.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            Text(task?.dueDate.map { "Next: \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Every \(every(item.days))")
                                .font(.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(get: { task != nil }, set: { on in
                            if on { lastDone = Date(); adding = item } else { Upkeep.turnOff(item, ctx: ctx); tick += 1 }
                        }))
                        .labelsHidden()
                    }
                    .accessibilityElement(children: .combine)
                }
            } footer: { Text("Each one becomes a repeating task in your Home list. Finish it and the next one is scheduled from that day.") }
        }
        .navigationTitle("Home & car upkeep")
        .sheet(item: $adding) { item in
            NavigationStack {
                Form {
                    DatePicker("When did you last do it?", selection: $lastDone, in: ...Date(), displayedComponents: .date)
                    Text("Next one: \((Calendar.current.date(byAdding: .day, value: item.days, to: lastDone) ?? lastDone).formatted(date: .abbreviated, time: .omitted))")
                        .foregroundStyle(DS.Palette.inkSoft)
                }
                .navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { adding = nil } }
                    ToolbarItem(placement: .confirmationAction) { Button("Add") { Upkeep.turnOn(item, lastDone: lastDone, ctx: ctx); adding = nil; tick += 1; Haptics.success() } }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func every(_ days: Int) -> String {
        days % 365 == 0 ? (days == 365 ? "year" : "\(days / 365) years") : days % 30 == 0 ? "\(days / 30) months" : "\(days) days"
    }
}

// MARK: - Voice journal

/// Talk for a minute; Keel writes the entry, reads the mood and finds the "I need to…" tasks.
enum VoiceJournal {
    /// 1 (low) to 5 (great), from the words' overall sentiment.
    static func mood(_ text: String) -> Int {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        let score = Double(tag?.rawValue ?? "0") ?? 0
        return min(5, max(1, Int(((score + 1) * 2).rounded()) + 1))
    }

    /// "I need to call the dentist and I should email Sam" → ["Call the dentist", "Email Sam"].
    static func tasks(_ text: String) -> [String] {
        let triggers = ["i need to ", "i have to ", "i should ", "i must ", "remember to ", "don't forget to ", "i've got to ", "i gotta "]
        var out: [String] = []
        let sentences = text.replacingOccurrences(of: " and i ", with: ". I ", options: .caseInsensitive)
            .split(whereSeparator: { ".!?\n".contains($0) }).map(String.init)
        for s in sentences {
            let low = s.lowercased()
            guard let t = triggers.first(where: { low.contains($0) }), let r = low.range(of: t) else { continue }
            let rest = s[s.index(s.startIndex, offsetBy: low.distance(from: low.startIndex, to: r.upperBound))...]
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard rest.count > 2 else { continue }
            out.append(rest.prefix(1).uppercased() + rest.dropFirst())
        }
        return Array(NSOrderedSet(array: out).array as? [String] ?? out)
    }
}

struct VoiceJournalView: View {
    var embedded = false
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var rec = VoiceNoteRecorder()
    @State private var entry = ""
    @State private var mood = 3
    @State private var found: [String] = []
    @State private var keep: Set<String> = []
    @State private var working = false
    @State private var stage = 0          // 0 talk, 1 review

    var body: some View {
        if embedded { page } else { NavigationStack { page } }
    }

    private var page: some View {
            Form {
                if stage == 0 {
                    Section {
                        Text(rec.transcript.isEmpty ? "How was today? What's on your mind? Anything you need to do?" : rec.transcript)
                            .foregroundStyle(rec.transcript.isEmpty ? DS.Palette.inkSoft : DS.Palette.ink)
                            .frame(minHeight: 120, alignment: .topLeading)
                        Button {
                            Task {
                                if rec.recording { rec.stop(); await process() } else { await rec.start() }
                            }
                        } label: {
                            Label(rec.recording ? "Done talking" : "Start talking", systemImage: rec.recording ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.title3.weight(.semibold)).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(rec.recording ? .red : DS.Palette.accent)
                        if working { ProgressView("Writing your entry…") }
                        if let e = rec.error { Text(e).font(.caption).foregroundStyle(.red) }
                    } footer: { Text("Transcribed on this iPhone. Keel writes it up as a journal entry you can edit.") }
                } else {
                    Section("Your entry") { TextField("Entry", text: $entry, axis: .vertical).lineLimit(4...14) }
                    Section("Mood") {
                        Picker("Mood", selection: $mood) { ForEach(1...5, id: \.self) { Text(CheckIn.faces[$0 - 1]).tag($0) } }
                            .pickerStyle(.segmented)
                    }
                    if !found.isEmpty {
                        Section("Tasks you mentioned") {
                            ForEach(found, id: \.self) { t in
                                Toggle(t, isOn: Binding(get: { keep.contains(t) }, set: { if $0 { keep.insert(t) } else { keep.remove(t) } }))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Voice journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !embedded { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { rec.stop(); dismiss() } } }
                if stage == 1 { ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } } }
            }
            .onDisappear { if rec.recording { rec.stop() } }
    }

    private func process() async {
        let text = rec.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        working = true
        mood = VoiceJournal.mood(text)
        found = VoiceJournal.tasks(text)
        keep = Set(found)
        entry = await AIRouter.shared.write("Turn this spoken journal into a short first-person journal entry of 3 to 6 sentences. Keep my words, feelings and details; fix filler words and repetition; no title, no advice.\n\n\(text)")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? text
        working = false
        withAnimation { stage = 1 }
    }

    private func save() {
        let day = Calendar.current.startOfDay(for: Date())
        let existing = (try? ctx.fetch(FetchDescriptor<CheckIn>(predicate: #Predicate { $0.day == day })))?.first
        let c = existing ?? CheckIn(day: day, mood: mood)
        if existing == nil { ctx.insert(c) } else if c.mood == 0 { c.mood = mood }
        c.journal = c.journal.isEmpty ? entry : c.journal + "\n\n" + entry
        if c.prompt.isEmpty { c.prompt = "Voice journal" }
        for t in found where keep.contains(t) { _ = QuickAdd.create(t, in: ctx) }
        try? ctx.save()
        UndoCenter.shared.notify(keep.isEmpty ? "Journal saved" : "Journal saved · \(keep.count) task\(keep.count == 1 ? "" : "s") added")
        Haptics.success()
        dismiss()
    }
}

// MARK: - Birthdays & gift ideas

struct BirthdayEntry: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let next: Date
    let turning: Int?
}

@MainActor
enum Gifts {
    static let ideasKey = "gifts.ideas"          // [name: [idea]]
    static let manualKey = "gifts.birthdays"     // [name: "MM-dd" or "yyyy-MM-dd"]

    static var ideas: [String: [String]] {
        get { (UserDefaults.standard.dictionary(forKey: ideasKey) as? [String: [String]]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: ideasKey) }
    }
    static var manual: [String: String] {
        get { (UserDefaults.standard.dictionary(forKey: manualKey) as? [String: String]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: manualKey) }
    }

    static func nextOccurrence(month: Int, day: Int, year: Int?, from now: Date = Date()) -> (Date, Int?)? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var y = cal.component(.year, from: now)
        for _ in 0..<2 {
            if let d = cal.date(from: DateComponents(year: y, month: month, day: day)), d >= today { return (d, year.map { y - $0 }) }
            y += 1
        }
        return nil
    }

    /// Birthdays from your Contacts and the ones you added, soonest first.
    static func upcoming(days: Int = 90) async -> [BirthdayEntry] {
        var out: [String: BirthdayEntry] = [:]
        let limit = Date().addingTimeInterval(Double(days) * 86_400)
        let fromContacts: [(String, DateComponents)] = await Task.detached(priority: .utility) {
            let store = CNContactStore()
            guard (try? await store.requestAccess(for: .contacts)) == true else { return [] }
            var list: [(String, DateComponents)] = []
            let req = CNContactFetchRequest(keysToFetch: [CNContactGivenNameKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor, CNContactBirthdayKey as CNKeyDescriptor])
            try? store.enumerateContacts(with: req) { c, _ in
                if let b = c.birthday { list.append(("\(c.givenName) \(c.familyName)".trimmingCharacters(in: .whitespaces), b)) }
            }
            return list
        }.value
        for (name, b) in fromContacts {
            guard let m = b.month, let d = b.day, let occ = nextOccurrence(month: m, day: d, year: b.year), occ.0 <= limit else { continue }
            out[name] = BirthdayEntry(name: name, next: occ.0, turning: occ.1)
        }
        for (name, s) in manual {
            let p = s.split(separator: "-").compactMap { Int($0) }
            let (y, m, d): (Int?, Int, Int) = p.count == 3 ? (p[0], p[1], p[2]) : p.count == 2 ? (nil, p[0], p[1]) : (nil, 0, 0)
            guard m > 0, let occ = nextOccurrence(month: m, day: d, year: y), occ.0 <= limit else { continue }
            out[name] = BirthdayEntry(name: name, next: occ.0, turning: occ.1)
        }
        return out.values.sorted { $0.next < $1.next }
    }

    /// A reminder a week before each birthday in the next two months (with your gift ideas in it).
    static func scheduleReminders(_ list: [BirthdayEntry]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { reqs in
            center.removePendingNotificationRequests(withIdentifiers: reqs.map(\.identifier).filter { $0.hasPrefix("bday.") })
        }
        let allIdeas = Self.ideas
        for b in list.prefix(30) {
            guard let at = Calendar.current.date(byAdding: .day, value: -7, to: b.next).flatMap({ Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: $0) }), at > Date() else { continue }
            let c = UNMutableNotificationContent()
            c.title = "\(b.name)'s birthday is in a week"
            let i = allIdeas[b.name] ?? []
            c.body = i.isEmpty ? "Time to think about a card or gift." : "Your gift ideas: " + i.prefix(3).joined(separator: ", ")
            c.userInfo = ["deeplink": "com.keel.app://tool/gifts"]
            center.add(UNNotificationRequest(identifier: "bday.\(b.name).\(Calendar.current.component(.year, from: b.next))", content: c,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: at), repeats: false)))
        }
    }
}

struct GiftsView: View {
    @State private var list: [BirthdayEntry] = []
    @State private var loading = true
    @State private var ideaFor: BirthdayEntry?
    @State private var newIdea = ""
    @State private var adding = false
    @State private var newName = ""
    @State private var newDate = Date()
    @State private var tick = 0

    var body: some View {
        let _ = tick
        let ideas = Gifts.ideas
        List {
            if loading { ProgressView() }
            if !loading && list.isEmpty {
                Text("No birthdays in the next 3 months. Add birthdays to your Contacts, or add one here.").foregroundStyle(DS.Palette.inkSoft)
            }
            ForEach(list) { b in
                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: b.next).day ?? 0
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(b.name).font(DS.Font.body.weight(.semibold))
                        Spacer()
                        Text(days == 0 ? "Today 🎉" : days == 1 ? "Tomorrow" : "in \(days) days").font(.caption).foregroundStyle(days <= 7 ? .orange : DS.Palette.inkSoft)
                    }
                    Text(b.next.formatted(.dateTime.weekday(.wide).month().day()) + (b.turning.map { " · turning \($0)" } ?? ""))
                        .font(.caption).foregroundStyle(DS.Palette.inkSoft)
                    if let i = ideas[b.name], !i.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(i, id: \.self) { idea in
                                Text(idea).font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.pink.opacity(0.12), in: Capsule())
                                    .contextMenu { Button("Remove", role: .destructive) { var all = Gifts.ideas; all[b.name]?.removeAll { $0 == idea }; Gifts.ideas = all; tick += 1 } }
                            }
                        }
                    }
                    Button("Add a gift idea", systemImage: "gift") { newIdea = ""; ideaFor = b }.font(.caption)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Birthdays & gifts")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add a birthday") } }
        .task { await reload() }
        .alert("Gift idea for \(ideaFor?.name ?? "")", isPresented: Binding(get: { ideaFor != nil }, set: { if !$0 { ideaFor = nil } })) {
            TextField("e.g. Running socks", text: $newIdea)
            Button("Add") {
                if let b = ideaFor, !newIdea.trimmingCharacters(in: .whitespaces).isEmpty {
                    var all = Gifts.ideas; all[b.name, default: []].append(newIdea.trimmingCharacters(in: .whitespaces)); Gifts.ideas = all; tick += 1
                }
                ideaFor = nil
            }
            Button("Cancel", role: .cancel) { ideaFor = nil }
        }
        .sheet(isPresented: $adding) {
            NavigationStack {
                Form {
                    TextField("Name", text: $newName)
                    DatePicker("Birthday", selection: $newDate, displayedComponents: .date)
                }
                .navigationTitle("Add a birthday").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { adding = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            let c = Calendar.current.dateComponents([.year, .month, .day], from: newDate)
                            var m = Gifts.manual; m[newName] = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0); Gifts.manual = m
                            adding = false; newName = ""
                            Task { await reload() }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func reload() async {
        list = await Gifts.upcoming()
        loading = false
        Gifts.scheduleReminders(list)
    }
}

// MARK: - Trip packing lists

@MainActor
enum Packing {
    static let madeKey = "packing.made"          // reservation ids that already have a list

    static func isTrip(_ r: Reservation) -> Bool { ["flight", "hotel", "train", "car"].contains(r.kind) }

    /// Builds a packing checklist page for a trip: length, the weather there, your meds, and extras from last time.
    @discardableResult
    static func make(for r: Reservation, ctx: ModelContext) async -> Note {
        let cal = Calendar.current
        let end = r.end ?? cal.date(byAdding: .day, value: 3, to: r.start) ?? r.start
        let nights = max(1, cal.dateComponents([.day], from: cal.startOfDay(for: r.start), to: cal.startOfDay(for: end)).day ?? 1)
        var blocks: [NoteBlock] = [NoteBlock(kind: .text, text: "\(nights) night\(nights == 1 ? "" : "s") · \(r.start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))")]
        func section(_ title: String, _ items: [String]) {
            guard !items.isEmpty else { return }
            blocks.append(NoteBlock(kind: .heading3, text: title))
            blocks += items.map { NoteBlock(kind: .todo, text: $0) }
        }
        // The weather where you're going.
        var weatherItems: [String] = []
        if !r.location.isEmpty, r.start < Date().addingTimeInterval(9 * 86_400),
           let place = try? await CLGeocoder().geocodeAddressString(r.location).first?.location,
           let days = try? await WeatherService.shared.weather(for: place, including: .daily) {
            let trip = days.forecast.filter { $0.date >= cal.startOfDay(for: r.start) && $0.date <= end }
            let high = trip.map { $0.highTemperature.converted(to: .celsius).value }.max() ?? 18
            let low = trip.map { $0.lowTemperature.converted(to: .celsius).value }.min() ?? 10
            let rain = trip.map(\.precipitationChance).max() ?? 0
            blocks.insert(NoteBlock(kind: .callout, text: String(format: "Weather there: %.0f° to %.0f°C, up to %.0f%% chance of rain.", low, high, rain * 100)), at: 1)
            if rain >= 0.4 { weatherItems += ["Umbrella", "Rain jacket"] }
            if low < 8 { weatherItems += ["Warm coat", "Hat & gloves"] }
            if high > 25 { weatherItems += ["Sunscreen", "Sunglasses", "Sun hat"] }
        }
        let meds = ((try? ctx.fetch(FetchDescriptor<Medication>())) ?? []).filter(\.isActive).map { "\($0.name) (enough for \(nights + 1) days)" }
        section("Essentials", ["Phone & charger", "Wallet & ID", "Keys", "Headphones"] + (r.kind == "flight" ? ["Boarding pass (in Wallet)", "Passport if flying abroad"] : []))
        section("Clothes", ["\(nights + 1) × underwear", "\(nights + 1) × socks", "\(min(nights, 6)) × tops", "\(max(1, nights / 3)) × trousers or skirts", "Sleepwear", "Comfortable shoes"])
        section("Toiletries", ["Toothbrush & toothpaste", "Deodorant", "Shampoo & body wash", "Skincare"])
        section("Medicine", meds + ["Pain relief"])
        section("For the weather", weatherItems)
        // Things you added to your last packing list that aren't on the standard one.
        let standard = Set(blocks.map(\.text))
        let lastExtras = ((try? ctx.fetch(FetchDescriptor<Note>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? [])
            .first { $0.title.hasPrefix("Packing: ") }?.blocks.filter { $0.kind == .todo && !standard.contains($0.text) }.map(\.text) ?? []
        section("From your last trip", Array(lastExtras.prefix(12)))

        let n = Note(title: "Packing: \(r.title)", blocks: blocks)
        n.icon = "🧳"
        n.folder = "Trips"
        ctx.insert(n)
        var made = Set(UserDefaults.standard.stringArray(forKey: madeKey) ?? [])
        made.insert(r.id.uuidString)
        UserDefaults.standard.set(Array(made), forKey: madeKey)
        try? ctx.save()
        return n
    }

    /// From sync: a list for any trip starting within a week, made once, with a heads-up.
    static func autoIfDue(ctx: ModelContext) async {
        let made = Set(UserDefaults.standard.stringArray(forKey: madeKey) ?? [])
        let soon = Date().addingTimeInterval(7 * 86_400)
        let trips = ((try? ctx.fetch(FetchDescriptor<Reservation>())) ?? []).filter { isTrip($0) && $0.start > Date() && $0.start < soon && !made.contains($0.id.uuidString) }
        for r in trips.prefix(2) {
            let n = await make(for: r, ctx: ctx)
            let c = UNMutableNotificationContent()
            c.title = "Packing list ready"
            c.body = "For \(r.title) on \(r.start.formatted(date: .abbreviated, time: .omitted))."
            c.userInfo = ["deeplink": "com.keel.app://note/\(n.id.uuidString)"]
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "packing.\(r.id.uuidString)", content: c, trigger: nil))
        }
    }
}

struct PackingView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Reservation.start) private var reservations: [Reservation]
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @State private var making: UUID?

    var body: some View {
        let trips = reservations.filter { Packing.isTrip($0) && ($0.end ?? $0.start) > Date() }
        List {
            Section {
                if trips.isEmpty {
                    Text("No upcoming trips found in your email yet. Flight, hotel, train and car bookings show up here.").foregroundStyle(DS.Palette.inkSoft)
                }
                ForEach(trips) { r in
                    let list = notes.first { $0.title == "Packing: \(r.title)" }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(DS.Font.body.weight(.medium))
                            Text(r.start.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        if let list {
                            let done = list.blocks.filter { $0.kind == .todo && $0.checked }.count, all = list.blocks.filter { $0.kind == .todo }.count
                            Button("\(done)/\(all) packed") { AppRouter.shared.openNoteId = list.id }.font(.caption).buttonStyle(.bordered)
                        } else {
                            Button(making == r.id ? "Making…" : "Make list") {
                                Task { making = r.id; let n = await Packing.make(for: r, ctx: ctx); making = nil; AppRouter.shared.openNoteId = n.id }
                            }
                            .font(.caption).buttonStyle(.borderedProminent).disabled(making != nil)
                        }
                    }
                }
            } footer: { Text("Keel also makes the list by itself a week before each trip, using the weather there and your medications.") }
        }
        .navigationTitle("Packing lists")
    }
}

// MARK: - Documents that expire

struct DocumentsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @State private var adding = false
    @State private var name = ""
    @State private var kind = "id"
    @State private var expires = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()

    var body: some View {
        let docs = notes.compactMap { n -> (Note, Date)? in
            guard let s = n.props[PaperworkVault.expiresKey], let d = PaperworkVault.parse(s) else { return nil }
            return (n, d)
        }.sorted { $0.1 < $1.1 }
        List {
            Section {
                if docs.isEmpty { Text("Add your passport, driver's license, insurance and warranties. Keel reminds you well before they expire.").foregroundStyle(DS.Palette.inkSoft) }
                ForEach(docs, id: \.0.id) { pair in
                    let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: pair.1).day ?? 0
                    Button { AppRouter.shared.openNoteId = pair.0.id } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pair.0.title).foregroundStyle(DS.Palette.ink)
                                Text(PaperworkVault.kindTitle(pair.0.props[PaperworkVault.kindKey] ?? "other")).font(.caption).foregroundStyle(DS.Palette.inkSoft)
                            }
                            Spacer()
                            Text(days < 0 ? "Expired" : days == 0 ? "Expires today" : "\(days) days").font(.caption.weight(.semibold))
                                .foregroundStyle(days < 30 ? .red : days < 90 ? .orange : .green)
                        }
                    }
                }
            } footer: { Text("IDs get a reminder 45 days before they expire; everything else 14 days before. Scan a document into the Vault to have its date read for you.") }
        }
        .navigationTitle("Documents")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add a document") } }
        .sheet(isPresented: $adding) {
            NavigationStack {
                Form {
                    TextField("What is it? e.g. Passport", text: $name)
                    Picker("Kind", selection: $kind) { ForEach(PaperworkVault.kinds, id: \.id) { Text($0.title).tag($0.id) } }
                    DatePicker("Expires", selection: $expires, displayedComponents: .date)
                }
                .navigationTitle("Add a document").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { adding = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            let n = Note(title: name, blocks: [])
                            n.icon = "🗂️"
                            n.folder = NotePath.make(PaperworkVault.workspace, PaperworkVault.kindTitle(kind))
                            n.props[PaperworkVault.kindKey] = kind
                            n.props[PaperworkVault.expiresKey] = ISO8601DateFormatter.dateOnly.string(from: expires)
                            ctx.insert(n)
                            PaperworkVault.remind(n, ctx: ctx)
                            try? ctx.save()
                            adding = false; name = ""
                            Haptics.success()
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}
