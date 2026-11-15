import SwiftUI
import SwiftData
import UserNotifications

// MARK: - Mind & mood tools

// 19. Reframe a thought (a simple thought record).

struct KitThought: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var situation = ""
    var thought = ""
    var before = 7
    var traps: [String] = []
    var against = ""
    var balanced = ""
    var after = 5
}

struct KitTrap: Hashable { let name: String; let hint: String }

enum KitTraps {
    static let all: [KitTrap] = [
        KitTrap(name: "All-or-nothing", hint: "Seeing it as total success or total failure."),
        KitTrap(name: "Mind reading", hint: "Assuming you know what others think of you."),
        KitTrap(name: "Fortune telling", hint: "Predicting it'll go badly before it happens."),
        KitTrap(name: "Catastrophising", hint: "Jumping to the worst possible outcome."),
        KitTrap(name: "Should statements", hint: "Holding yourself to rigid rules."),
        KitTrap(name: "Labelling", hint: "\"I'm useless\" instead of \"I made a mistake\"."),
        KitTrap(name: "Discounting the good", hint: "Brushing off what went well."),
        KitTrap(name: "Rejection radar", hint: "Reading a neutral reply as rejection."),
    ]
}

struct KitReframeView: View {
    static let key = "kit.thoughts"
    @State private var list: [KitThought] = []
    @State private var draft = KitThought()
    @State private var step = 0

    var body: some View {
        Form {
            Section { KitIntro(icon: "arrow.triangle.2.circlepath", color: .indigo, text: "Reframe a thought. When a thought hits hard, slow it down: what happened, what you told yourself, which thinking trap it might be, and a fairer way to see it. Most people feel noticeably better after one pass.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section("1 · What happened?") { TextField("Just the facts", text: $draft.situation, axis: .vertical) }
            Section("2 · What went through your mind?") {
                TextField("The thought, in your own words", text: $draft.thought, axis: .vertical)
                Stepper("How much it hurts: \(draft.before)/10", value: $draft.before, in: 0...10)
            }
            Section("3 · Any thinking traps?") {
                ForEach(KitTraps.all, id: \.name) { t in
                    Button {
                        if draft.traps.contains(t.name) { draft.traps.removeAll { $0 == t.name } } else { draft.traps.append(t.name) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) { Text(t.name).foregroundStyle(DS.Palette.ink); Text(t.hint).font(.caption2).foregroundStyle(DS.Palette.inkSoft) }
                            Spacer()
                            if draft.traps.contains(t.name) { Image(systemName: "checkmark").foregroundStyle(.indigo) }
                        }
                    }
                }
            }
            Section("4 · What doesn't fit that thought?") { TextField("Evidence against it", text: $draft.against, axis: .vertical) }
            Section("5 · A fairer way to see it") {
                TextField("What would you tell a friend?", text: $draft.balanced, axis: .vertical)
                Stepper("How much it hurts now: \(draft.after)/10", value: $draft.after, in: 0...10)
            }
            Section {
                Button("Save", systemImage: "checkmark") {
                    list.insert(draft, at: 0); Kit.save(Array(list.prefix(200)), Self.key)
                    draft = KitThought(); Haptics.success()
                }
                .disabled(draft.thought.isEmpty)
            }
            if !list.isEmpty {
                Section("Earlier") {
                    ForEach(list.prefix(20)) { t in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t.thought).font(.callout).strikethrough()
                            Text(t.balanced).font(.callout.weight(.semibold))
                            Text("\(t.before) → \(t.after) · \(t.date.formatted(date: .abbreviated, time: .omitted))").font(.caption2)
                                .foregroundStyle(t.after < t.before ? DS.Palette.calm : DS.Palette.inkSoft)
                        }
                    }
                    .onDelete { list.remove(atOffsets: $0); Kit.save(list, Self.key) }
                }
            }
        }
        .navigationTitle("Reframe a thought")
        .onAppear { list = Kit.load(Self.key) }
    }
}

// 20. Worry time: park worries now, think about them at a set time.

struct KitWorryTimeView: View {
    static let key = "kit.worries"
    @AppStorage("kit.worry.hour") private var hour = 17
    @AppStorage("kit.worry.on") private var on = false
    @Environment(\.modelContext) private var ctx
    @State private var worries: [KitItem] = []
    @State private var draft = ""

    var body: some View {
        List {
            Section { KitIntro(icon: "cloud.drizzle.fill", color: .gray, text: "Worry time. When a worry shows up, write it here and let it go for now. Once a day, at your worry time, spend 15 minutes with the list: solve what you can, turn it into a task, or let it go. Worries shrink when they have a place to wait.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section {
                HStack {
                    TextField("Park a worry", text: $draft, axis: .vertical)
                    Button("Park") { worries.insert(KitItem(text: draft), at: 0); save(); draft = ""; Haptics.tap() }.disabled(draft.isEmpty)
                }
            }
            Section("Parked (\(worries.filter { !$0.done }.count))") {
                ForEach(worries.filter { !$0.done }) { w in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(w.text)
                        HStack {
                            Button("Let it go") { resolve(w, "let go") }.buttonStyle(.bordered)
                            Button("Make a task") {
                                let t = TaskItem(title: w.text); t.listName = "Inbox"; ctx.insert(t); try? ctx.save()
                                resolve(w, "task")
                            }
                            .buttonStyle(.bordered)
                        }
                        .font(.caption)
                    }
                }
            }
            Section("Daily worry time") {
                Toggle("Remind me", isOn: $on)
                Stepper("At \(hour > 12 ? hour - 12 : hour) \(hour >= 12 ? "PM" : "AM")", value: $hour, in: 7...21)
            }
            let settled = worries.filter(\.done).count
            if settled > 0 { Section { Text("\(settled) worries settled so far.").foregroundStyle(DS.Palette.calm) } }
        }
        .navigationTitle("Worry time")
        .onAppear { worries = Kit.load(Self.key) }
        .onChange(of: on) { schedule() }
        .onChange(of: hour) { schedule() }
    }

    private func save() { Kit.save(Array(worries.prefix(300)), Self.key) }
    private func resolve(_ w: KitItem, _ how: String) {
        if let i = worries.firstIndex(of: w) { worries[i].done = true; worries[i].detail = how }
        save(); Haptics.success()
    }
    private func schedule() {
        Kit.cancel(["kit.worrytime"])
        guard on else { return }
        let c = UNMutableNotificationContent()
        c.title = "Worry time"
        c.body = "15 minutes with your parked worries, then let the rest of the evening be yours."
        var comps = DateComponents(); comps.hour = hour; comps.minute = 0
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "kit.worrytime", content: c,
                                                                     trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
    }
}

// 21. Name the feeling.

struct KitFeelingGroup: Identifiable, Hashable { var id: String { core }; let core: String; let color: Color; let words: [String]; let tip: String }

enum KitFeelings {
    static let groups: [KitFeelingGroup] = [
        KitFeelingGroup(core: "Happy", color: .yellow, words: ["Proud", "Hopeful", "Playful", "Grateful", "Content", "Relieved"], tip: "Notice what led here, so you can do more of it."),
        KitFeelingGroup(core: "Sad", color: .blue, words: ["Lonely", "Disappointed", "Hurt", "Empty", "Guilty", "Homesick"], tip: "Be gentle with yourself. Reach out to one person, or rest."),
        KitFeelingGroup(core: "Angry", color: .red, words: ["Frustrated", "Irritated", "Resentful", "Jealous", "Disrespected", "Overstimulated"], tip: "Move your body first (walk, shake it out), decide later."),
        KitFeelingGroup(core: "Scared", color: .purple, words: ["Anxious", "Overwhelmed", "Insecure", "Rejected", "Worried", "Panicky"], tip: "Slow your breath: in for 4, out for 6. Then one small step."),
        KitFeelingGroup(core: "Bad", color: .gray, words: ["Tired", "Bored", "Restless", "Stressed", "Foggy", "Unmotivated"], tip: "Check the basics: water, food, sleep, a short walk."),
        KitFeelingGroup(core: "Surprised", color: .orange, words: ["Confused", "Amazed", "Startled", "Excited", "Shocked", "Curious"], tip: "Give yourself a minute before reacting."),
    ]
}

struct KitFeelingsView: View {
    static let key = "kit.feelings"
    @State private var core: KitFeelingGroup?
    @State private var log: [KitItem] = []

    var body: some View {
        List {
            Section { KitIntro(icon: "heart.circle.fill", color: .pink, text: "Name the feeling. Putting a precise word on a feeling (\"overstimulated\", not just \"bad\") calms the brain's alarm. Pick the closest broad feeling, then the word that fits best, and Keel offers one thing that tends to help.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section("I feel…") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                    ForEach(KitFeelings.groups) { g in
                        Button { withAnimation(.snappy) { core = g } } label: {
                            Text(g.core).font(.callout.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(g.color.opacity(core == g ? 0.45 : 0.18), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let g = core {
                Section("More exactly") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 8) {
                        ForEach(g.words, id: \.self) { w in
                            Button {
                                log.insert(KitItem(text: w, detail: g.core), at: 0); Kit.save(Array(log.prefix(500)), Self.key); Haptics.tap()
                            } label: {
                                Text(w).font(.callout).frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(g.color.opacity(0.15), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Label(g.tip, systemImage: "lightbulb.fill").font(.callout).foregroundStyle(g.color)
                }
            }
            if !log.isEmpty {
                Section("Lately") {
                    ForEach(log.prefix(10)) { i in
                        HStack { Text(i.text); Spacer(); Text(i.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(DS.Palette.inkSoft) }
                    }
                }
            }
        }
        .navigationTitle("Name the feeling")
        .onAppear { log = Kit.load(Self.key) }
    }
}

// 22. Grounding: 5-4-3-2-1.

struct KitGroundingView: View {
    private let steps: [(n: Int, sense: String, icon: String)] = [
        (5, "things you can see", "eye.fill"), (4, "things you can touch", "hand.raised.fill"),
        (3, "things you can hear", "ear.fill"), (2, "things you can smell", "nose.fill"), (1, "thing you can taste", "mouth.fill"),
    ]
    @State private var i = 0

    var body: some View {
        VStack(spacing: DS.Space.l) {
            KitIntro(icon: "leaf.circle.fill", color: .teal, text: "Grounding, 5-4-3-2-1. When panic or overwhelm hits, bring yourself back to the room by naming things with each sense, slowly. Say them out loud or in your head.")
            Spacer()
            if i < steps.count {
                let s = steps[i]
                Image(systemName: s.icon).font(.system(size: 60)).foregroundStyle(.teal.gradient)
                Text("\(s.n)").font(.system(size: 80, weight: .bold, design: .rounded))
                Text("Name \(s.n) \(s.sense)").font(.title3.weight(.semibold))
                Button { withAnimation(.smooth) { i += 1 }; Haptics.tap() } label: { Text("Next").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.teal).padding(.horizontal, 40)
            } else {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 70)).foregroundStyle(DS.Palette.calm)
                Text("You're here. Take one slow breath.").font(.title3.weight(.semibold))
                Button("Again") { withAnimation { i = 0 } }
            }
            Spacer()
        }
        .padding(DS.Space.m)
        .navigationTitle("Grounding")
    }
}

// 23. Social battery.

struct KitBatteryView: View {
    static let key = "kit.socialbattery"
    @State private var level = 60.0
    @State private var note = ""
    @State private var log: [KitItem] = []

    var body: some View {
        List {
            Section { KitIntro(icon: "battery.75percent", color: .green, text: "Social battery. How much people-energy do you have right now? Log it after plans and calls. Over time you'll see which kinds of contact drain you and which recharge you, and you can plan your week around it.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section {
                VStack(spacing: 8) {
                    Image(systemName: icon).font(.system(size: 44)).foregroundStyle(color)
                    Text("\(Int(level))%").font(.title.weight(.bold)).monospacedDigit()
                    Slider(value: $level, in: 0...100, step: 5).tint(color)
                    Text(advice).font(.caption).foregroundStyle(DS.Palette.inkSoft).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                TextField("After what? (optional)", text: $note)
                Button("Log it") {
                    log.insert(KitItem(text: note, detail: "\(Int(level))"), at: 0); Kit.save(Array(log.prefix(300)), Self.key); note = ""; Haptics.tap()
                }
            }
            if !log.isEmpty {
                Section("Lately") {
                    ForEach(log.prefix(14)) { i in
                        HStack {
                            Text("\(i.detail)%").monospacedDigit().frame(width: 50, alignment: .leading)
                            Text(i.text.isEmpty ? "–" : i.text)
                            Spacer()
                            Text(i.date.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                }
            }
        }
        .navigationTitle("Social battery")
        .onAppear { log = Kit.load(Self.key) }
    }
    private var icon: String { level >= 75 ? "battery.100percent" : level >= 50 ? "battery.75percent" : level >= 25 ? "battery.25percent" : "battery.0percent" }
    private var color: Color { level >= 50 ? .green : level >= 25 ? .orange : .red }
    private var advice: String {
        level >= 75 ? "Plenty in the tank. Good time for plans or a call you've been putting off."
        : level >= 50 ? "Doing fine. Keep some time to yourself later."
        : level >= 25 ? "Running low. It's OK to keep the rest of today quiet."
        : "Empty. Cancel what you can without guilt and recharge alone."
    }
}

// 24. Wins jar.

struct KitWinsJarView: View {
    var body: some View {
        KitTextListView(key: "kit.wins", title: "Wins jar", icon: "star.circle.fill", color: .yellow,
                        intro: "Wins jar. Drop in every win, big or tiny: finished the report, called the dentist, got out of bed on a hard day. On a bad day, pull one out at random to remind yourself what you're capable of.",
                        placeholder: "A win, however small", randomTitle: "Pull a win out of the jar")
    }
}

// 25. Three good things.

struct KitGratitudeView: View {
    static let key = "kit.gratitude"
    @State private var all: [KitTop3Day] = []
    @State private var today = KitTop3Day(day: Kit.dayKey(), items: ["", "", ""], done: [false, false, false])

    var body: some View {
        List {
            Section { KitIntro(icon: "sun.max.fill", color: .orange, text: "Three good things. Each evening, write three things that went well and, if you like, why. It trains your attention toward what's working, and it's one of the best-studied ways to lift your mood.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section("Today") {
                ForEach(0..<3, id: \.self) { i in
                    TextField("Good thing \(i + 1)", text: $today.items[i], axis: .vertical)
                }
            }
            Section {
                KitStat(value: "\(Kit.streak(Set(all.filter { $0.items.contains { !$0.isEmpty } }.map(\.day))))", label: "day streak", color: .orange)
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            ForEach(all.filter { $0.day != today.day }.suffix(10).reversed(), id: \.day) { d in
                Section(d.day) { ForEach(d.items.filter { !$0.isEmpty }, id: \.self) { Text($0).font(.callout) } }
            }
        }
        .navigationTitle("Three good things")
        .onAppear {
            all = Kit.load(Self.key)
            if let t = all.first(where: { $0.day == Kit.dayKey() }) { today = t }
        }
        .onDisappear {
            all.removeAll { $0.day == today.day }
            if today.items.contains(where: { !$0.isEmpty }) { all.append(today) }
            Kit.save(Array(all.suffix(365)), Self.key)
        }
    }
}

// 26. Affirmations.

struct KitAffirmationsView: View {
    var body: some View {
        KitTextListView(key: "kit.affirmations", title: "Affirmations", icon: "quote.bubble.fill", color: .pink,
                        intro: "Affirmations. Kind, true sentences to come back to when your inner critic gets loud. Keep the ones that ring true for you, add your own, and tap the button for one at random.",
                        placeholder: "Something true and kind", randomTitle: "Show me one",
                        seed: ["My brain works differently, not wrongly.", "Starting is the hardest part, and I can start small.",
                               "Rest is productive.", "I've handled hard days before.", "Done is better than perfect."])
    }
}

// 27. Letter to future you.

struct KitLetter: Codable, Identifiable, Hashable { var id = UUID(); var text: String; var written = Date(); var opens: Date }

struct KitFutureLetterView: View {
    static let key = "kit.letters"
    @State private var letters: [KitLetter] = []
    @State private var text = ""
    @State private var opens = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()

    var body: some View {
        List {
            Section { KitIntro(icon: "envelope.badge.fill", color: .indigo, text: "Letter to future you. Write to yourself in a few months or a year: what's going on, what you hope, what you're worried about. Keel seals it and notifies you the day it opens.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section("Write") {
                TextField("Dear future me…", text: $text, axis: .vertical).lineLimit(4...12)
                DatePicker("Open on", selection: $opens, in: Date().addingTimeInterval(86_400)..., displayedComponents: .date)
                Button("Seal it", systemImage: "envelope.fill") { seal() }.disabled(text.isEmpty)
            }
            Section("Letters") {
                ForEach(letters) { l in
                    if l.opens <= Date() {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Written \(l.written.formatted(date: .long, time: .omitted))").font(.caption.weight(.semibold))
                            Text(l.text)
                        }
                    } else {
                        Label("Sealed until \(l.opens.formatted(date: .long, time: .omitted))", systemImage: "lock.fill").foregroundStyle(DS.Palette.inkSoft)
                    }
                }
                .onDelete { letters.remove(atOffsets: $0); Kit.save(letters, Self.key) }
            }
        }
        .navigationTitle("Letter to future you")
        .onAppear { letters = Kit.load(Self.key) }
    }

    private func seal() {
        let l = KitLetter(text: text, opens: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: opens) ?? opens)
        letters.insert(l, at: 0); Kit.save(letters, Self.key)
        Kit.notify("kit.letter.\(l.id)", title: "A letter from past you", body: "Written \(l.written.formatted(date: .abbreviated, time: .omitted)). Open Keel to read it.", at: l.opens)
        text = ""; Haptics.success()
    }
}
