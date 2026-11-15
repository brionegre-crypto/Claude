import SwiftUI
import SwiftData

// MARK: - Growth tools

// 40. Reading tracker.

struct KitBook: Codable, Identifiable, Hashable { var id = UUID(); var title: String; var pages: Int; var page = 0; var started = Date(); var finished: Date? }

struct KitReadingView: View {
    static let key = "kit.books"
    @AppStorage("kit.books.goal") private var goal = 12
    @State private var books: [KitBook] = []
    @State private var title = ""
    @State private var pages = 300

    var body: some View {
        let year = Calendar.current.component(.year, from: Date())
        let finishedThisYear = books.filter { $0.finished.map { Calendar.current.component(.year, from: $0) == year } ?? false }.count
        List {
            Section { KitIntro(icon: "books.vertical.fill", color: .brown, text: "Reading. Track the books you're reading, where you're up to, and your goal for the year. Update your page as you go; finished books count toward the goal.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(finishedThisYear) of \(goal) books in \(String(year))").font(.headline)
                    ProgressView(value: Double(min(finishedThisYear, goal)), total: Double(max(goal, 1))).tint(.brown)
                }
                Stepper("Yearly goal: \(goal)", value: $goal, in: 1...200)
            }
            Section("Reading now") {
                ForEach($books) { $b in
                    if b.finished == nil {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(b.title).font(.headline)
                            ProgressView(value: Double(b.page), total: Double(max(b.pages, 1))).tint(.brown)
                            Stepper("Page \(b.page) of \(b.pages)", value: $b.page, in: 0...max(b.pages, 1), step: 5)
                                .onChange(of: b.page) { save() }
                            Button("Finished it", systemImage: "checkmark.seal.fill") { b.finished = Date(); b.page = b.pages; save(); Haptics.milestone() }
                                .font(.caption)
                        }
                    }
                }
            }
            Section("Add a book") {
                TextField("Title", text: $title)
                Stepper("\(pages) pages", value: $pages, in: 10...2000, step: 10)
                Button("Start reading") { books.insert(KitBook(title: title, pages: pages), at: 0); save(); title = "" }.disabled(title.isEmpty)
            }
            Section("Finished") {
                ForEach(books.filter { $0.finished != nil }) { b in
                    HStack { Text(b.title); Spacer(); Text(b.finished?.formatted(date: .abbreviated, time: .omitted) ?? "").font(.caption).foregroundStyle(DS.Palette.inkSoft) }
                }
            }
        }
        .navigationTitle("Reading")
        .onAppear { books = Kit.load(Self.key) }
    }
    private func save() { Kit.save(books, Self.key) }
}

// 41. Practice log: hours toward a skill.

struct KitPractice: Codable, Identifiable, Hashable { var id = UUID(); var skill: String; var minutes: Int; var date = Date() }

struct KitPracticeView: View {
    static let key = "kit.practice"
    @State private var log: [KitPractice] = []
    @State private var skill = ""
    @State private var minutes = 30

    var body: some View {
        let skills = Dictionary(grouping: log, by: \.skill).mapValues { $0.reduce(0) { $0 + $1.minutes } }
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        List {
            Section { KitIntro(icon: "music.note.list", color: .purple, text: "Practice log. Log time spent on a skill: guitar, Spanish, coding, drawing. Watch the hours add up and see what you practised this week. Progress you can see keeps you going.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section("Log practice") {
                TextField("Skill", text: $skill)
                if !skills.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(skills.keys.sorted(), id: \.self) { s in Button(s) { skill = s }.buttonStyle(.bordered).controlSize(.small) } }
                    }
                }
                Stepper("\(Kit.minutes(minutes))", value: $minutes, in: 5...480, step: 5)
                Button("Log it") { log.insert(KitPractice(skill: skill, minutes: minutes), at: 0); Kit.save(Array(log.prefix(2000)), Self.key); Haptics.success() }
                    .disabled(skill.isEmpty)
            }
            Section("Totals") {
                ForEach(skills.sorted { $0.value > $1.value }, id: \.key) { s in
                    let week = log.filter { $0.skill == s.key && $0.date > weekAgo }.reduce(0) { $0 + $1.minutes }
                    HStack {
                        VStack(alignment: .leading) {
                            Text(s.key).font(.headline)
                            Text("This week: \(Kit.minutes(week))").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        Text(String(format: "%.1f h", Double(s.value) / 60)).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(.purple)
                    }
                }
            }
        }
        .navigationTitle("Practice log")
        .onAppear { log = Kit.load(Self.key) }
    }
}

// 42. Bucket list.

struct KitBucketListView: View {
    var body: some View {
        KitTextListView(key: "kit.bucket", title: "Bucket list", icon: "globe.europe.africa.fill", color: .teal,
                        intro: "Bucket list. The experiences you want to have one day: places, skills, adventures. Tick them off as you go. Writing them down makes \"one day\" much more likely.",
                        placeholder: "One day I want to…", checkable: true, randomTitle: "Inspire me")
    }
}

// 43. Life in weeks.

enum KitLifeWeeks {
    static func lived(born: Date, now: Date = Date()) -> Int {
        max(0, Calendar.current.dateComponents([.weekOfYear], from: born, to: now).weekOfYear ?? 0)
    }
}

struct KitLifeWeeksView: View {
    @AppStorage("kit.lifeweeks.born") private var born: Double = 0
    @State private var pick = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    private let years = 90

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                KitIntro(icon: "square.grid.4x3.fill", color: .indigo, text: "Life in weeks. Every square is one week of a 90-year life; the filled ones are behind you. Not to scare you, but to put today in perspective: this week is one small square, and there's room for a lot.")
                if born == 0 {
                    DatePicker("Your birthday", selection: $pick, in: ...Date(), displayedComponents: .date)
                    Button("Show my weeks") { born = pick.timeIntervalSince1970 }.buttonStyle(.borderedProminent).tint(.indigo)
                } else {
                    let lived = KitLifeWeeks.lived(born: Date(timeIntervalSince1970: born))
                    HStack {
                        KitStat(value: lived.formatted(), label: "weeks lived", color: .indigo)
                        KitStat(value: max(0, years * 52 - lived).formatted(), label: "weeks to 90", color: .indigo)
                    }
                    Canvas { c, size in
                        let cols = 52
                        let cell = size.width / CGFloat(cols)
                        for i in 0..<(years * 52) {
                            let r = CGRect(x: CGFloat(i % cols) * cell + 0.6, y: CGFloat(i / cols) * cell + 0.6, width: cell - 1.2, height: cell - 1.2)
                            let color: Color = i < lived ? .indigo : i == lived ? .orange : Color.gray.opacity(0.18)
                            c.fill(Path(r), with: .color(color))
                        }
                    }
                    .aspectRatio(52 / CGFloat(years), contentMode: .fit)
                    .drawingGroup()
                    .accessibilityLabel("\(lived) of \(years * 52) weeks lived")
                    Button("Change birthday") { born = 0 }.font(.caption)
                }
            }
            .padding(DS.Space.m)
        }
        .navigationTitle("Life in weeks")
    }
}

// 44. Chains: don't break the chain.

struct KitChain: Codable, Identifiable, Hashable { var id = UUID(); var name: String; var days: [String] = [] }

struct KitChainsView: View {
    static let key = "kit.chains"
    @State private var chains: [KitChain] = []
    @State private var name = ""

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let last = (0..<28).compactMap { cal.date(byAdding: .day, value: -27 + $0, to: today) }
        List {
            Section { KitIntro(icon: "link", color: .red, text: "Chains. Pick something to do every day (write, stretch, practise) and mark each day you do it. The chain of marks grows, and soon not breaking it becomes its own motivation. Tap any of the last four weeks to fix a missed mark.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            ForEach($chains) { $ch in
                Section {
                    HStack {
                        Text(ch.name).font(.headline)
                        Spacer()
                        Label("\(Kit.streak(Set(ch.days)))", systemImage: "flame.fill").foregroundStyle(.red).font(.callout.weight(.semibold))
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                        ForEach(last, id: \.self) { d in
                            let k = Kit.dayKey(d)
                            let on = ch.days.contains(k)
                            Button {
                                if on { ch.days.removeAll { $0 == k } } else { ch.days.append(k); Haptics.tap() }
                                Kit.save(chains, Self.key)
                            } label: {
                                RoundedRectangle(cornerRadius: 5).fill(on ? Color.red.opacity(0.85) : Color.gray.opacity(0.15))
                                    .frame(height: 26)
                                    .overlay {
                                        if cal.isDateInToday(d) { RoundedRectangle(cornerRadius: 5).strokeBorder(DS.Palette.ink.opacity(0.5), lineWidth: 1.5) }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(d.formatted(date: .abbreviated, time: .omitted)): \(on ? "done" : "not done")")
                        }
                    }
                }
            }
            .onDelete { chains.remove(atOffsets: $0); Kit.save(chains, Self.key) }
            Section("New chain") {
                HStack {
                    TextField("Every day I…", text: $name)
                    Button("Add") { chains.append(KitChain(name: name)); Kit.save(chains, Self.key); name = "" }.disabled(name.isEmpty)
                }
            }
        }
        .navigationTitle("Chains")
        .onAppear { chains = Kit.load(Self.key) }
    }
}

// 45. Experiments: try a change for a set time and see if it works.

struct KitExperiment: Codable, Identifiable, Hashable {
    var id = UUID(); var change: String; var hope: String; var days: Int; var start = Date(); var checks: [String: Bool] = [:]; var verdict: String?
}

struct KitExperimentsView: View {
    static let key = "kit.experiments"
    @State private var list: [KitExperiment] = []
    @State private var change = ""
    @State private var hope = ""
    @State private var days = 14

    var body: some View {
        List {
            Section { KitIntro(icon: "flask.fill", color: .green, text: "Experiments. Instead of forcing a new habit forever, try it for a set time: \"No phone in bed for 14 days, to see if I sleep better.\" Check in each day. At the end, decide with evidence: keep it, tweak it or drop it.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            ForEach($list) { $e in
                let end = Calendar.current.date(byAdding: .day, value: e.days, to: e.start) ?? Date()
                let yes = e.checks.values.filter { $0 }.count
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(e.change).font(.headline)
                        Text("Hoping: \(e.hope)").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                        ProgressView(value: min(1, Date().timeIntervalSince(e.start) / end.timeIntervalSince(e.start))).tint(.green)
                        Text("\(yes) of \(e.checks.count) check-ins went well").font(.caption)
                    }
                    if let v = e.verdict {
                        Label("Decided: \(v)", systemImage: "checkmark.seal.fill").foregroundStyle(DS.Palette.calm)
                    } else if Date() >= end {
                        HStack {
                            ForEach(["Keep it", "Tweak it", "Drop it"], id: \.self) { v in
                                Button(v) { e.verdict = v; Kit.save(list, Self.key); Haptics.success() }.buttonStyle(.bordered).font(.caption)
                            }
                        }
                    } else if e.checks[Kit.dayKey()] == nil {
                        HStack {
                            Text("Today?").font(.caption.weight(.semibold))
                            Spacer()
                            Button("Went well") { e.checks[Kit.dayKey()] = true; Kit.save(list, Self.key); Haptics.tap() }.buttonStyle(.borderedProminent).tint(.green)
                            Button("Not really") { e.checks[Kit.dayKey()] = false; Kit.save(list, Self.key) }.buttonStyle(.bordered)
                        }
                        .font(.caption)
                    }
                }
            }
            .onDelete { list.remove(atOffsets: $0); Kit.save(list, Self.key) }
            Section("New experiment") {
                TextField("The change (no phone in bed)", text: $change)
                TextField("What I hope happens (I sleep better)", text: $hope)
                Stepper("For \(days) days", value: $days, in: 3...60)
                Button("Start") { list.insert(KitExperiment(change: change, hope: hope, days: days), at: 0); Kit.save(list, Self.key); change = ""; hope = "" }
                    .disabled(change.isEmpty)
            }
        }
        .navigationTitle("Experiments")
        .onAppear { list = Kit.load(Self.key) }
    }
}

// 46. Idea vault.

struct KitIdea: Codable, Identifiable, Hashable { var id = UUID(); var text: String; var stars = 0; var date = Date() }

struct KitIdeaVaultView: View {
    static let key = "kit.ideas"
    @Environment(\.modelContext) private var ctx
    @State private var ideas: [KitIdea] = []
    @State private var draft = ""

    var body: some View {
        List {
            Section { KitIntro(icon: "lightbulb.max.fill", color: .yellow, text: "Idea vault. Ideas arrive at the worst times. Drop them here so they stop circling in your head, star the good ones later, and turn the best into a task when you're ready. No pressure to act on any of them.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section {
                HStack {
                    TextField("An idea", text: $draft, axis: .vertical)
                    Button("Save") { ideas.insert(KitIdea(text: draft), at: 0); save(); draft = ""; Haptics.tap() }.disabled(draft.isEmpty)
                }
            }
            Section("\(ideas.count) ideas") {
                ForEach($ideas) { $i in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(i.text)
                        HStack(spacing: 2) {
                            ForEach(1...3, id: \.self) { s in
                                Button { i.stars = i.stars == s ? 0 : s; save() } label: {
                                    Image(systemName: s <= i.stars ? "star.fill" : "star").foregroundStyle(.yellow)
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                            Button("Make a task") {
                                let t = TaskItem(title: i.text); t.listName = "Inbox"; ctx.insert(t); try? ctx.save()
                                UndoCenter.shared.notify("Added to your Inbox")
                            }
                            .font(.caption).buttonStyle(.bordered)
                        }
                    }
                }
                .onDelete { ideas.remove(atOffsets: $0); save() }
            }
        }
        .navigationTitle("Idea vault")
        .onAppear { ideas = Kit.load(Self.key, as: KitIdea.self).sorted { $0.stars > $1.stars } }
    }
    private func save() { Kit.save(ideas, Self.key) }
}
