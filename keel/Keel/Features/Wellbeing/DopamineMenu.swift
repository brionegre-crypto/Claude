import SwiftUI

/// A dopamine menu: pre-chosen ways to get a healthy boost, so a bored ADHD brain reaches for
/// something good instead of the phone. Starters are quick, mains are fulfilling, sides go
/// with boring tasks, desserts are fine in moderation (with a timer).
struct DopamineItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var course: String               // starter | main | side | dessert
    var minutes: Int

    static let courses: [(id: String, title: String, blurb: String, icon: String)] = [
        ("starter", "Starters", "Quick boosts, 1–5 minutes", "bolt.fill"),
        ("main", "Mains", "Bigger, more fulfilling", "fork.knife"),
        ("side", "Sides", "Pair with a boring task", "headphones"),
        ("dessert", "Desserts", "Nice in moderation. Set a timer", "birthday.cake.fill"),
    ]

    static let key = "dopamine.menu"
    static var all: [DopamineItem] {
        get {
            guard let d = UserDefaults.standard.data(forKey: key), let items = try? JSONDecoder().decode([DopamineItem].self, from: d) else { return defaults }
            return items
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    static let defaults: [DopamineItem] = [
        .init(title: "Play one favorite song loud", course: "starter", minutes: 3),
        .init(title: "Stretch or do 10 jumping jacks", course: "starter", minutes: 2),
        .init(title: "Step outside for fresh air", course: "starter", minutes: 5),
        .init(title: "Cold water on your face", course: "starter", minutes: 1),
        .init(title: "Walk around the block", course: "main", minutes: 20),
        .init(title: "Call or text a friend", course: "main", minutes: 15),
        .init(title: "Work on a hobby", course: "main", minutes: 30),
        .init(title: "Workout", course: "main", minutes: 30),
        .init(title: "Upbeat playlist", course: "side", minutes: 0),
        .init(title: "Podcast or audiobook", course: "side", minutes: 0),
        .init(title: "Fidget toy", course: "side", minutes: 0),
        .init(title: "Body double with Keel", course: "side", minutes: 0),
        .init(title: "Social media, with a 10-minute timer", course: "dessert", minutes: 10),
        .init(title: "One episode of a show", course: "dessert", minutes: 30),
    ]
}

struct DopamineMenuView: View {
    @State private var items = DopamineItem.all
    @State private var pick: DopamineItem?
    @State private var newTitle = ""
    @State private var newCourse = "starter"

    var body: some View {
        List {
            Section {
                Button { surprise() } label: { Label("Pick one for me", systemImage: "dice.fill").font(DS.Font.headline) }
                if let pick {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pick.title).font(DS.Font.title)
                        if pick.minutes > 0 { Text("About \(pick.minutes) min. Then come back to one small thing.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft) }
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            } footer: { Text("Bored, stuck or restless? Choose from here before reaching for your phone.") }
            ForEach(DopamineItem.courses, id: \.id) { c in
                Section {
                    ForEach(items.filter { $0.course == c.id }) { i in
                        HStack {
                            Text(i.title)
                            Spacer()
                            if i.minutes > 0 { Text("\(i.minutes)m").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft) }
                        }
                    }
                    .onDelete { idx in
                        let ids = idx.map { items.filter { $0.course == c.id }[$0].id }
                        items.removeAll { ids.contains($0.id) }; DopamineItem.all = items
                    }
                } header: { Label(c.title, systemImage: c.icon) } footer: { Text(c.blurb) }
            }
            Section("Add your own") {
                TextField("e.g. Dance in the kitchen", text: $newTitle)
                Picker("Course", selection: $newCourse) { ForEach(DopamineItem.courses, id: \.id) { Text($0.title).tag($0.id) } }
                Button("Add") {
                    items.append(.init(title: newTitle, course: newCourse, minutes: newCourse == "starter" ? 5 : newCourse == "main" ? 20 : 0))
                    DopamineItem.all = items; newTitle = ""
                }
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("Dopamine Menu")
    }

    private func surprise() {
        let pool = items.filter { $0.course == "starter" || $0.course == "main" }
        withAnimation(DS.spring) { pick = pool.randomElement() }
        Haptics.milestone()
    }
}
