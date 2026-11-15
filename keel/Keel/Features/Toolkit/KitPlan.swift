import SwiftUI
import SwiftData

// MARK: - Plan & priorities tools

// 11. Top 3 today.

struct KitTop3Day: Codable, Hashable { var day: String; var items: [String]; var done: [Bool] }

enum KitTop3 {
    static let key = "kit.top3"
    static func fullDays(_ all: [KitTop3Day]) -> Set<String> {
        Set(all.filter { d in !d.items.filter { !$0.isEmpty }.isEmpty && zip(d.items, d.done).allSatisfy { $0.0.isEmpty || $0.1 } }.map(\.day))
    }
}

struct KitTop3View: View {
    @State private var all: [KitTop3Day] = []
    @State private var today = KitTop3Day(day: Kit.dayKey(), items: ["", "", ""], done: [false, false, false])

    var body: some View {
        List {
            Section { KitIntro(icon: "3.circle.fill", color: DS.Palette.accent, text: "Top 3. Pick just three things that would make today a good day. Not ten. When all three are done, the day counts toward your streak, and anything else is a bonus.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section("Today") {
                ForEach(0..<3, id: \.self) { i in
                    HStack {
                        Button { today.done[i].toggle(); save(); if today.done[i] { Haptics.success() } } label: {
                            Image(systemName: today.done[i] ? "checkmark.circle.fill" : "\(i + 1).circle").font(.title3)
                                .foregroundStyle(today.done[i] ? DS.Palette.calm : DS.Palette.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(today.items[i].isEmpty)
                        TextField("Thing \(i + 1)", text: $today.items[i]).strikethrough(today.done[i]).onSubmit(save)
                    }
                }
            }
            Section {
                HStack {
                    KitStat(value: "\(Kit.streak(KitTop3.fullDays(all)))", label: "day streak")
                    KitStat(value: "\(KitTop3.fullDays(all).count)", label: "perfect days")
                }
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section("Recent") {
                ForEach(all.filter { $0.day != today.day }.suffix(7).reversed(), id: \.day) { d in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.day).font(.caption.weight(.semibold))
                        ForEach(Array(zip(d.items, d.done).enumerated()).filter { !$0.element.0.isEmpty }, id: \.offset) { _, pair in
                            Label(pair.0, systemImage: pair.1 ? "checkmark.circle.fill" : "circle").font(.caption)
                                .foregroundStyle(pair.1 ? DS.Palette.calm : DS.Palette.inkSoft)
                        }
                    }
                }
            }
        }
        .navigationTitle("Top 3")
        .onAppear {
            all = Kit.load(KitTop3.key)
            if let t = all.first(where: { $0.day == Kit.dayKey() }) { today = t }
        }
        .onDisappear(perform: save)
    }

    private func save() {
        all.removeAll { $0.day == today.day }
        all.append(today)
        Kit.save(Array(all.suffix(120)), KitTop3.key)
    }
}

// 12. Eat the frog: the one thing you're dreading, done first.

struct KitFrog: Codable, Hashable { var day: String; var text: String; var done = false }

struct KitFrogView: View {
    static let key = "kit.frogs"
    @Query(filter: #Predicate<TaskItem> { !$0.isDone && !$0.isSomeday }, sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    @State private var frogs: [KitFrog] = []
    @State private var draft = ""

    private var today: KitFrog? { frogs.first { $0.day == Kit.dayKey() } }

    var body: some View {
        List {
            Section { KitIntro(icon: "tortoise.fill", color: .green, text: "Eat the frog. Choose the one task you're most tempted to put off, and do it first, before email or anything else. The rest of the day feels lighter once it's gone.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            if let f = today {
                Section("Today's frog") {
                    Text(f.text).font(.title3.weight(.semibold)).strikethrough(f.done)
                    if !f.done {
                        Button("Eaten!", systemImage: "checkmark.circle.fill") { setToday(done: true); Haptics.milestone() }
                            .buttonStyle(.borderedProminent).tint(.green)
                        Button("Pick a different frog") { frogs.removeAll { $0.day == Kit.dayKey() }; save() }
                    } else {
                        Text("Done. Everything else today is easier.").foregroundStyle(DS.Palette.calm)
                    }
                }
            } else {
                Section("Choose today's frog") {
                    HStack {
                        TextField("The thing I keep avoiding", text: $draft)
                        Button("Set") { setFrog(draft) }.disabled(draft.isEmpty)
                    }
                    ForEach(tasks.filter { $0.timesRescheduled > 0 }.sorted { $0.timesRescheduled > $1.timesRescheduled }.prefix(5)) { t in
                        Button { setFrog(t.title) } label: {
                            HStack { Text(t.title); Spacer(); Text("moved \(t.timesRescheduled)×").font(.caption2).foregroundStyle(.orange) }
                        }
                    }
                }
            }
            Section {
                KitStat(value: "\(frogs.filter(\.done).count)", label: "frogs eaten", color: .green)
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
        .navigationTitle("Eat the frog")
        .onAppear { frogs = Kit.load(Self.key) }
    }

    private func setFrog(_ text: String) {
        frogs.removeAll { $0.day == Kit.dayKey() }
        frogs.append(KitFrog(day: Kit.dayKey(), text: text)); draft = ""; save()
    }
    private func setToday(done: Bool) {
        if let i = frogs.firstIndex(where: { $0.day == Kit.dayKey() }) { frogs[i].done = done }
        save()
    }
    private func save() { Kit.save(Array(frogs.suffix(365)), Self.key) }
}

// 13. Done list: everything you got done, including what was never on a list.

struct KitDoneListView: View {
    static let key = "kit.donelist"
    @Query(KitDoneListView.recentDone) private var completed: [TaskItem]
    static var recentDone: FetchDescriptor<TaskItem> {
        var d = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isDone }, sortBy: [SortDescriptor(\TaskItem.completedAt, order: .reverse)])
        d.fetchLimit = 200
        return d
    }
    @State private var items: [KitItem] = []
    @State private var draft = ""

    var body: some View {
        let todays = items.filter { Calendar.current.isDateInToday($0.date) }
        let tasksToday = completed.filter { $0.completedAt.map { Calendar.current.isDateInToday($0) } ?? false }
        List {
            Section { KitIntro(icon: "checkmark.seal.fill", color: DS.Palette.calm, text: "Done list. The opposite of a to-do list: write down what you did, including the things that were never on a list (made lunch, answered Mum, fixed the printer). Seeing it all is proof the day counted.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section {
                HStack {
                    TextField("I just…", text: $draft).onSubmit(add)
                    Button("Add", action: add).disabled(draft.isEmpty)
                }
            }
            Section("Today · \(todays.count + tasksToday.count) things") {
                ForEach(todays) { i in Label(i.text, systemImage: "checkmark.circle.fill").foregroundStyle(DS.Palette.ink) }
                    .onDelete { idx in
                        let ids = idx.map { todays[$0].id }
                        items.removeAll { ids.contains($0.id) }; Kit.save(items, Self.key)
                    }
                ForEach(tasksToday) { t in Label(t.title, systemImage: "checklist.checked").foregroundStyle(DS.Palette.inkSoft) }
            }
            let earlier = Dictionary(grouping: items.filter { !Calendar.current.isDateInToday($0.date) }) { Kit.dayKey($0.date) }
            ForEach(earlier.keys.sorted(by: >).prefix(14), id: \.self) { day in
                Section(day) { ForEach(earlier[day] ?? []) { Text($0.text).font(.callout) } }
            }
        }
        .navigationTitle("Done list")
        .onAppear { items = Kit.load(Self.key) }
    }

    private func add() {
        guard !draft.isEmpty else { return }
        withAnimation { items.insert(KitItem(text: draft), at: 0) }
        Kit.save(Array(items.prefix(1500)), Self.key); draft = ""; Haptics.success()
    }
}

// 14. Mind sweep: prompts that shake loose everything on your mind, turned into tasks.

struct KitSweepArea: Hashable { let area: String; let items: [String] }

enum KitMindSweep {
    static let prompts: [KitSweepArea] = [
        KitSweepArea(area: "Work", items: ["Projects started but not finished", "People I owe a reply", "Meetings to set up", "Things to ask my manager", "Deadlines coming up"]),
        KitSweepArea(area: "Home", items: ["Repairs", "Cleaning or tidying", "Things to buy", "Bills and paperwork", "Admin I keep putting off"]),
        KitSweepArea(area: "People", items: ["Calls or messages to make", "Birthdays and events", "Thank-yous to send", "Plans to make"]),
        KitSweepArea(area: "Me", items: ["Health appointments", "Things I want to learn", "Hobbies I've let slip", "Errands", "Anything that's nagging me"]),
    ]
}

struct KitMindSweepView: View {
    @Environment(\.modelContext) private var ctx
    @State private var text: [String: String] = [:]
    @State private var made = 0

    var body: some View {
        List {
            Section { KitIntro(icon: "wind", color: .cyan, text: "Mind sweep. Go through each prompt and type whatever it brings to mind, one per line. Don't judge or sort. When you're done, Keel turns every line into a task in your Inbox, and your head gets quieter.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            ForEach(KitMindSweep.prompts, id: \.area) { group in
                Section(group.area) {
                    ForEach(group.items, id: \.self) { p in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p).font(.caption.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft)
                            TextField("One per line", text: Binding(get: { text[p, default: ""] }, set: { text[p] = $0 }), axis: .vertical)
                        }
                    }
                }
            }
            Section {
                Button("Make \(lines.count) task\(lines.count == 1 ? "" : "s")", systemImage: "tray.and.arrow.down.fill") { makeTasks() }
                    .disabled(lines.isEmpty)
                if made > 0 { Text("Added \(made) to your Inbox. Sort them when you're ready.").foregroundStyle(DS.Palette.calm) }
            }
        }
        .navigationTitle("Mind sweep")
    }

    private var lines: [String] {
        text.values.flatMap { $0.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) } }.filter { !$0.isEmpty }
    }
    private func makeTasks() {
        for l in lines { let t = TaskItem(title: l); t.listName = "Inbox"; ctx.insert(t) }
        try? ctx.save()
        made = lines.count; text = [:]
        Haptics.success()
    }
}

// 15. Theme days: give each weekday a theme so you don't decide from scratch.

struct KitThemeDaysView: View {
    @AppStorage("kit.themedays") private var raw = ""
    private let names = Calendar.current.weekdaySymbols

    var body: some View {
        let themes = decode()
        let todayIndex = Calendar.current.component(.weekday, from: Date()) - 1
        Form {
            Section { KitIntro(icon: "calendar.day.timeline.left", color: .purple, text: "Theme days. Give each day of the week a theme, like Monday for admin or Friday for creative work. Fewer decisions, less switching, and you always know what kind of work fits today.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            if !themes[todayIndex].isEmpty {
                Section("Today") { Text(themes[todayIndex]).font(.title3.weight(.semibold)).foregroundStyle(.purple) }
            }
            Section("Week") {
                ForEach(0..<7, id: \.self) { i in
                    HStack {
                        Text(names[i]).frame(width: 100, alignment: .leading).foregroundStyle(i == todayIndex ? .purple : DS.Palette.ink)
                        TextField("Theme", text: Binding(get: { decode()[i] }, set: { v in var t = decode(); t[i] = v; raw = t.joined(separator: "\u{1F}") }))
                    }
                }
            }
        }
        .navigationTitle("Theme days")
    }
    private func decode() -> [String] {
        var parts = raw.components(separatedBy: "\u{1F}")
        while parts.count < 7 { parts.append("") }
        return Array(parts.prefix(7))
    }
}

// 16. Don't-do list.

struct KitDontDoView: View {
    var body: some View {
        KitTextListView(key: "kit.dontdo", title: "Don't-do list", icon: "hand.raised.fill", color: .red,
                        intro: "Don't-do list. What you decide not to do matters as much as what you do. Write the habits, commitments and time-sinks you're saying no to, and look at it when you're tempted.",
                        placeholder: "I don't…",
                        seed: ["Check email before my first focus block", "Say yes on the spot; I say \"let me check\"", "Scroll in bed"])
    }
}

// 17. If-then plans: decide in advance what you'll do when a situation comes up.

struct KitIfThen: Codable, Identifiable, Hashable { var id = UUID(); var when: String; var then: String; var used = 0 }

struct KitIfThenView: View {
    static let key = "kit.ifthen"
    @State private var plans: [KitIfThen] = []
    @State private var when = ""
    @State private var then = ""

    var body: some View {
        List {
            Section { KitIntro(icon: "arrow.right.circle.fill", color: .blue, text: "If-then plans. Decide ahead of time: \"If I sit down at my desk, then I open my top task first.\" Plans like this double the odds you'll follow through, because the decision is already made. Tap one when you used it.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section("New plan") {
                TextField("If… (a situation or cue)", text: $when)
                TextField("Then I will…", text: $then)
                Button("Add plan") {
                    plans.append(KitIfThen(when: when, then: then)); Kit.save(plans, Self.key); when = ""; then = ""
                }
                .disabled(when.isEmpty || then.isEmpty)
            }
            Section("My plans") {
                ForEach($plans) { $p in
                    Button {
                        p.used += 1; Kit.save(plans, Self.key); Haptics.success()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("If \(p.when)").font(.callout.weight(.semibold))
                            Text("then \(p.then)").font(.callout)
                            if p.used > 0 { Text("Used \(p.used)×").font(.caption2).foregroundStyle(DS.Palette.calm) }
                        }
                        .foregroundStyle(DS.Palette.ink)
                    }
                }
                .onDelete { plans.remove(atOffsets: $0); Kit.save(plans, Self.key) }
            }
        }
        .navigationTitle("If-then plans")
        .onAppear { plans = Kit.load(Self.key) }
    }
}

// 18. Spoons: a daily energy budget.

struct KitSpoonCost: Codable, Identifiable, Hashable { var id = UUID(); var name: String; var cost: Int }

struct KitSpoonsView: View {
    static let costsKey = "kit.spoons.costs"
    @AppStorage("kit.spoons.budget") private var budget = 12
    @AppStorage("kit.spoons.day") private var day = ""
    @AppStorage("kit.spoons.used") private var used = 0
    @State private var costs: [KitSpoonCost] = []
    @State private var name = ""
    @State private var cost = 2

    var body: some View {
        let left = budget - used
        List {
            Section { KitIntro(icon: "fork.knife", color: .orange, text: "Spoons. You start each day with a set number of spoons, your energy. Everything costs some: a shower, a meeting, a phone call. Tap what you do to spend spoons, and plan the rest of the day around what's left. It resets every morning.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section {
                VStack(spacing: 10) {
                    HStack(spacing: 4) {
                        ForEach(0..<max(budget, 1), id: \.self) { i in
                            Image(systemName: "fork.knife").font(.caption)
                                .foregroundStyle(i < left ? Color.orange : Color.gray.opacity(0.25))
                        }
                    }
                    Text(left > 0 ? "\(left) of \(budget) spoons left" : "Out of spoons. Rest is the plan now.").font(.headline)
                        .foregroundStyle(left > 2 ? DS.Palette.ink : .orange)
                }
                .frame(maxWidth: .infinity)
                Stepper("Daily spoons: \(budget)", value: $budget, in: 4...30)
                Button("Reset today") { used = 0 }
            }
            Section("Spend") {
                ForEach(costs) { c in
                    Button { used += c.cost; Haptics.tap() } label: {
                        HStack { Text(c.name).foregroundStyle(DS.Palette.ink); Spacer(); Text("−\(c.cost)").foregroundStyle(.orange).monospacedDigit() }
                    }
                }
                .onDelete { costs.remove(atOffsets: $0); Kit.save(costs, Self.costsKey) }
                HStack {
                    TextField("Activity", text: $name)
                    Stepper("\(cost)", value: $cost, in: 1...10).fixedSize()
                    Button("Add") { costs.append(KitSpoonCost(name: name, cost: cost)); Kit.save(costs, Self.costsKey); name = "" }.disabled(name.isEmpty)
                }
            }
        }
        .navigationTitle("Spoons")
        .onAppear {
            if day != Kit.dayKey() { day = Kit.dayKey(); used = 0 }
            costs = Kit.load(Self.costsKey)
            if costs.isEmpty {
                costs = [("Shower", 1), ("Work meeting", 2), ("Cooking", 2), ("Phone call", 1), ("Errand", 2), ("Social plans", 3)]
                    .map { KitSpoonCost(name: $0.0, cost: $0.1) }
                Kit.save(costs, Self.costsKey)
            }
        }
    }
}
