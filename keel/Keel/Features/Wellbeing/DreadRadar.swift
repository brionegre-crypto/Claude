import SwiftUI
import SwiftData

/// Dread Radar: notices what you're avoiding across email and tasks (emails opened again and again without a reply,
/// tasks that keep moving, focus sessions quit on the same task), guesses why, and offers the fix that fits.
/// Before you start you guess how bad it'll be; afterwards you say how bad it was. Over time Keel shows you
/// your own proof that dread overestimates.
@MainActor
enum Dread {
    enum Reason: String, Codable, CaseIterable {
        case tooBig, unclear, money, hardTalk, admin, unknown
        var label: String {
            switch self {
            case .tooBig: "Feels too big"
            case .unclear: "Not sure what to do"
            case .money: "It's about money"
            case .hardTalk: "A hard conversation"
            case .admin: "Boring admin"
            case .unknown: "Just stuck"
            }
        }
        var icon: String {
            switch self {
            case .tooBig: "square.stack.3d.up.fill"; case .unclear: "questionmark.circle.fill"; case .money: "dollarsign.circle.fill"
            case .hardTalk: "bubble.left.and.exclamationmark.bubble.right.fill"; case .admin: "doc.text.fill"; case .unknown: "tortoise.fill"
            }
        }
    }

    struct Item: Identifiable {
        let id: String
        let title: String
        let signal: String            // why Keel thinks you're avoiding it
        let reason: Reason
        let task: TaskItem?
        let email: EmailMessage?
    }

    struct Record: Codable, Identifiable {
        var id: String                // item id
        var title: String
        var predicted: Int            // 1…5
        var actual: Int?
        var reason: Reason
        var date = Date()
    }

    static let opensKey = "dread.opens", recordsKey = "dread.records", dismissedKey = "dread.dismissed"
    static let faces = ["😌", "🙂", "😬", "😰", "😱"]

    // MARK: Signals

    /// Called each time you open an email.
    static func recordOpen(_ emailId: String) {
        var d = UserDefaults.standard.dictionary(forKey: opensKey) as? [String: Int] ?? [:]
        d[emailId, default: 0] += 1
        if d.count > 400 { d = d.filter { $0.value >= 2 } }
        UserDefaults.standard.set(d, forKey: opensKey)
    }

    static func opens(_ emailId: String) -> Int {
        (UserDefaults.standard.dictionary(forKey: opensKey) as? [String: Int])?[emailId] ?? 0
    }

    static var dismissed: Set<String> { Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []) }
    static func dismiss(_ id: String) {
        UserDefaults.standard.set(Array(Array(dismissed.union([id])).suffix(300)), forKey: dismissedKey)
    }

    static func items(tasks: [TaskItem], mail: [EmailMessage], sessions: [FocusSession], accounts: [MailAccount]) -> [Item] {
        let hidden = dismissed
        let mine = Set(accounts.map { $0.address.lowercased() })
        let today = Calendar.current.startOfDay(for: Date())
        var quits = [UUID: Int]()
        for s in sessions where s.brokeEarly { if let t = s.taskId { quits[t, default: 0] += 1 } }

        var out: [Item] = []
        for t in tasks where !t.isDone && !t.isSomeday && !hidden.contains("task:\(t.id)") {
            let overdueDays = t.dueDate.map { Int(today.timeIntervalSince(Calendar.current.startOfDay(for: $0)) / 86_400) } ?? 0
            let q = quits[t.id] ?? 0
            var signals: [String] = []
            if t.timesRescheduled >= 2 { signals.append("moved \(t.timesRescheduled) times") }
            if q >= 2 { signals.append("\(q) focus sessions stopped early") }
            if overdueDays >= 4 { signals.append("\(overdueDays) days overdue") }
            guard !signals.isEmpty else { continue }
            out.append(Item(id: "task:\(t.id)", title: t.title, signal: signals.joined(separator: " · ").capitalizingFirst,
                            reason: reason(task: t), task: t, email: nil))
        }
        for e in mail where !e.isArchived && !hidden.contains("mail:\(e.id)") {
            let n = opens(e.id)
            guard n >= 3, e.category == .important || e.category == .actionable, !MailNoise.isAutomated(e),
                  !mine.contains(e.from.lowercased()), e.receivedAt < Date().addingTimeInterval(-86_400) else { continue }
            let days = Int(Date().timeIntervalSince(e.receivedAt) / 86_400)
            out.append(Item(id: "mail:\(e.id)", title: "Reply to \(e.fromName.isEmpty ? e.from : e.fromName): \(e.subject)",
                            signal: "Opened \(n) times in \(days) day\(days == 1 ? "" : "s"), no reply yet",
                            reason: reason(email: e), task: nil, email: e))
        }
        return out.sorted { weight($0) > weight($1) }
    }

    private static func weight(_ i: Item) -> Int {
        if let t = i.task { return t.timesRescheduled * 2 + t.priority.rawValue }
        if let e = i.email { return opens(e.id) * 2 + 3 }
        return 0
    }

    // MARK: Why

    private static let moneyWords = ["invoice", "pay", "payment", "tax", "bill", "owe", "refund", "budget", "price", "quote", "salary", "debt", "loan", "$", "€", "£"]
    private static let hardWords = ["sorry", "feedback", "concern", "issue", "unfortunately", "disappointed", "decline", "complaint",
                                    "conflict", "apolog", "difficult", "talk to", "conversation", "quit", "break up", "resign", "boss", "review"]
    private static let adminWords = ["form", "application", "renew", "account", "password", "insurance", "appointment", "register",
                                     "license", "passport", "paperwork", "fill", "update my", "cancel", "return", "dmv", "receipt"]

    static func reason(task t: TaskItem) -> Reason {
        let s = (t.title + " " + t.notes).lowercased()
        if moneyWords.contains(where: { s.contains($0) }) { return .money }
        if hardWords.contains(where: { s.contains($0) }) { return .hardTalk }
        if adminWords.contains(where: { s.contains($0) }) { return .admin }
        if (t.estimatedMinutes ?? 0) >= 60 || (t.microSteps.isEmpty && t.title.split(separator: " ").count >= 6) { return .tooBig }
        if t.title.split(separator: " ").count <= 2 && t.microSteps.isEmpty { return .unclear }
        return .unknown
    }

    static func reason(email e: EmailMessage) -> Reason {
        let body = GmailProvider.stripQuotedReply(e.bodyPlain)
        let s = (e.subject + " " + body.prefix(1500)).lowercased()
        if moneyWords.contains(where: { s.contains($0) }) { return .money }
        if hardWords.contains(where: { s.contains($0) }) { return .hardTalk }
        if body.filter({ $0 == "?" }).count >= 3 { return .unclear }
        if body.split(whereSeparator: { $0.isWhitespace }).count > 350 { return .tooBig }
        if adminWords.contains(where: { s.contains($0) }) { return .admin }
        return .unknown
    }

    // MARK: Dread vs reality

    static var records: [Record] {
        get {
            guard let d = UserDefaults.standard.data(forKey: recordsKey), let r = try? JSONDecoder().decode([Record].self, from: d) else { return [] }
            return r
        }
        set { if let d = try? JSONEncoder().encode(Array(newValue.suffix(120))) { UserDefaults.standard.set(d, forKey: recordsKey) } }
    }

    static func predict(_ item: Item, _ value: Int) {
        var r = records.filter { $0.id != item.id || $0.actual != nil }
        r.append(Record(id: item.id, title: item.title, predicted: value, reason: item.reason))
        records = r
    }

    static func rateActual(_ id: String, _ value: Int) {
        var r = records
        if let i = r.lastIndex(where: { $0.id == id && $0.actual == nil }) { r[i].actual = value; records = r }
    }

    /// Average guess vs average reality, once there are at least 3 finished ones.
    static var gap: (predicted: Double, actual: Double, count: Int)? {
        let done = records.filter { $0.actual != nil }
        guard done.count >= 3 else { return nil }
        let p = Double(done.map(\.predicted).reduce(0, +)) / Double(done.count)
        let a = Double(done.compactMap(\.actual).reduce(0, +)) / Double(done.count)
        return (p, a, done.count)
    }

    static var gapSentence: String? {
        guard let g = gap else { return nil }
        if g.predicted - g.actual >= 0.5 {
            return String(format: "You expect things to feel like a %.1f out of 5. They usually turn out to be a %.1f.", g.predicted, g.actual)
        }
        return String(format: "Your guesses are pretty accurate (%.1f vs %.1f). Trust them, and keep things small.", g.predicted, g.actual)
    }
}

private extension String {
    var capitalizingFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Radar screen

struct DreadRadarView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var tasks: [TaskItem]
    @Query(filter: #Predicate<EmailMessage> { !$0.isArchived }) private var mail: [EmailMessage]
    @Query private var sessions: [FocusSession]
    @Query private var accounts: [MailAccount]
    @Query private var allMail: [EmailMessage]
    @State private var fixing: Dread.Item?
    @State private var refresh = 0

    /// Things you rated beforehand that are now done: "How bad was it, really?"
    private var toRate: [Dread.Record] {
        _ = refresh
        return Dread.records.filter { r in
            guard r.actual == nil else { return false }
            if r.id.hasPrefix("task:"), let id = UUID(uuidString: String(r.id.dropFirst(5))) {
                return tasks.first { $0.id == id }?.isDone ?? false
            }
            if r.id.hasPrefix("mail:") {
                let eid = String(r.id.dropFirst(5))
                return allMail.first { $0.id == eid }?.isArchived ?? true
            }
            return false
        }
    }

    private var items: [Dread.Item] {
        _ = refresh
        return Dread.items(tasks: tasks, mail: mail, sessions: sessions, accounts: accounts)
    }

    var body: some View {
        let items = self.items
        List {
            if let s = Dread.gapSentence, let g = Dread.gap {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Dread vs reality", systemImage: "chart.bar.xaxis").font(DS.Font.headline)
                        HStack(alignment: .bottom, spacing: DS.Space.l) {
                            bar("Expected", g.predicted, .red)
                            bar("Actually", g.actual, DS.Palette.calm)
                        }
                        .frame(height: 90)
                        Text(s).font(DS.Font.body)
                        Text("From \(g.count) things you faced.").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
            }
            if !toRate.isEmpty {
                Section("You did these. How bad was it, really?") {
                    ForEach(toRate) { r in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(r.title).font(DS.Font.body).lineLimit(2)
                            Text("You guessed \(Dread.faces[r.predicted - 1]) \(r.predicted)/5").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                            FaceScale(selected: nil) { v in Dread.rateActual(r.id, v); refresh += 1; Haptics.success() }
                        }
                    }
                }
            }
            Section {
                if items.isEmpty {
                    ContentUnavailableView("Nothing you're avoiding", systemImage: "checkmark.seal",
                                           description: Text("Keel watches for emails you keep opening without replying and tasks that keep sliding."))
                        .listRowBackground(Color.clear)
                }
                ForEach(items) { i in
                    Button { fixing = i } label: {
                        HStack(alignment: .top, spacing: DS.Space.m) {
                            Image(systemName: i.reason.icon).foregroundStyle(DS.Palette.warmth).frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(i.title).font(DS.Font.headline).foregroundStyle(DS.Palette.ink).lineLimit(2)
                                Text(i.signal).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                                Chip(text: i.reason.label, color: DS.Palette.warmth)
                            }
                        }
                    }
                    .swipeActions { Button("Not avoiding") { Dread.dismiss(i.id); refresh += 1 }.tint(.gray) }
                }
            } header: { Text(items.isEmpty ? "" : "What you might be avoiding") } footer: {
                if !items.isEmpty { Text("No judgment. Avoiding is usually about how something feels, not about time. Tap one for a fix that fits.") }
            }
        }
        .navigationTitle("Dread Radar")
        .sheet(item: $fixing, onDismiss: { refresh += 1 }) { DreadFixView(item: $0) }
    }

    private func bar(_ label: String, _ v: Double, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            Text(String(format: "%.1f", v)).font(DS.Font.caption.monospacedDigit())
            RoundedRectangle(cornerRadius: 6).fill(color.gradient).frame(width: 54, height: CGFloat(v / 5) * 60)
            Text(label).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 1…5 faces.
struct FaceScale: View {
    var selected: Int?
    let pick: (Int) -> Void

    var body: some View {
        HStack {
            ForEach(1...5, id: \.self) { v in
                Button { pick(v) } label: {
                    Text(Dread.faces[v - 1]).font(.system(size: 30))
                        .scaleEffect(selected == v ? 1.25 : 1).opacity(selected == nil || selected == v ? 1 : 0.4)
                }
                .buttonStyle(.borderless).frame(maxWidth: .infinity)
                .accessibilityLabel("\(v) out of 5")
            }
        }
    }
}

// MARK: - Fix flow: guess → fix → do it → how was it?

struct DreadFixView: View {
    let item: Dread.Item
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [MailAccount]
    @State private var predicted: Int?
    @State private var stage = 0                  // 0 guess, 1 fix, 2 rate, 3 done
    @State private var actual: Int?
    @State private var working = false
    @State private var output: String?
    @State private var question = ""
    @State private var compose: ComposeDraft?
    @State private var bandAidEnds: Date?
    @State private var bodyDouble = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(DS.Font.title)
                        Label(item.reason.label, systemImage: item.reason.icon).font(DS.Font.caption).foregroundStyle(DS.Palette.warmth)
                    }
                    switch stage {
                    case 0: guess
                    case 1: fixes
                    case 2: rate
                    default: finished
                    }
                }
                .padding()
            }
            .navigationTitle("Face it")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(item: $compose) { ComposeView(draft: $0) }
            .navigationDestination(isPresented: $bodyDouble) { FocusRoomView(task: item.task) }
        }
    }

    // 0. Guess
    private var guess: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("How bad do you think this will be?").font(DS.Font.headline)
            FaceScale(selected: predicted) { v in withAnimation { predicted = v }; Haptics.tap() }
            if let g = Dread.gap, g.predicted - g.actual >= 0.5 {
                Label(String(format: "Reminder: the last %d times you guessed about %.0f, and it was about %.0f.", g.count, g.predicted, g.actual),
                      systemImage: "lightbulb.fill")
                    .font(DS.Font.caption).padding(DS.Space.m)
                    .background(DS.Palette.calm.opacity(0.12), in: .rect(cornerRadius: DS.Radius.card))
            }
            Button {
                if let p = predicted { Dread.predict(item, p) }
                withAnimation(DS.spring) { stage = 1 }
            } label: {
                Text(predicted == nil ? "Skip" : "Next").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(DS.Palette.accent)
        }
    }

    // 1. The fix that fits
    private var fixes: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text(intro).font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
            primaryFix
            if let output {
                Text(output).font(DS.Font.body).padding(DS.Space.m).frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.card))
                    .textSelection(.enabled)
            }
            if working { ProgressView().frame(maxWidth: .infinity) }
            if let end = bandAidEnds {
                TimelineView(.periodic(from: .now, by: 1)) { tl in
                    let left = max(0, end.timeIntervalSince(tl.date))
                    HStack {
                        Text(left > 0 ? "Just 2 minutes: \(Duration.seconds(left).formatted(.time(pattern: .minuteSecond)))" : "2 minutes done. Keep going or stop, both count.")
                            .font(DS.Font.headline.monospacedDigit())
                        Spacer()
                    }
                    .padding(DS.Space.m).background(DS.Palette.focus.opacity(0.12), in: .rect(cornerRadius: DS.Radius.card))
                }
            }
            Divider()
            Text("Other ways in").font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft)
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Button { bandAidEnds = Date().addingTimeInterval(120); Haptics.tap() } label: { Label("Rip the band-aid: 2 minutes", systemImage: "timer") }
                if item.task != nil { Button { bodyDouble = true } label: { Label("Do it with a body double", systemImage: "person.2.wave.2") } }
                Button { moreTime() } label: { Label("Ask for more time, no guilt", systemImage: "clock.arrow.circlepath") }
                Button(role: .destructive) { letGo() } label: { Label(item.task != nil ? "Let it go (move to Someday)" : "Let it go (archive)", systemImage: "leaf") }
            }
            .buttonStyle(.borderless)
            Button { withAnimation(DS.spring) { stage = 2 } } label: {
                Label("I did it", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(DS.Palette.calm).padding(.top, DS.Space.s)
        }
    }

    private var intro: String {
        switch item.reason {
        case .tooBig: "Big things are hard to start. Let's find a first step small enough to feel silly."
        case .unclear: "When it's fuzzy, the brain stalls. Name the one thing you need to know."
        case .money: "Money stuff carries extra weight. Two minutes is enough to open it and look."
        case .hardTalk: "Hard conversations are easiest to start with one honest sentence. Keel can write it."
        case .admin: "Boring admin is hard for an ADHD brain. Make it a 2-minute sprint."
        case .unknown: "Sometimes it's just stuck. A tiny first move usually unsticks it."
        }
    }

    @ViewBuilder private var primaryFix: some View {
        switch item.reason {
        case .tooBig, .unknown:
            Button { Task { await shrink() } } label: { fixLabel("Shrink it to a first step", "wand.and.stars") }
        case .unclear:
            TextField("The one thing I need to know is…", text: $question).textFieldStyle(.roundedBorder)
            Button { Task { await clarify() } } label: { fixLabel(item.email != nil ? "Draft a reply asking it" : "Add it as the first step", "questionmark.bubble") }
                .disabled(question.isEmpty)
        case .hardTalk:
            Button { Task { await firstSentence() } } label: { fixLabel("Write my first sentence", "text.cursor") }
        case .money, .admin:
            Button { bandAidEnds = Date().addingTimeInterval(120); Haptics.tap() } label: { fixLabel("Start a 2-minute sprint", "timer") }
            Button { Task { await shrink() } } label: { Label("Or shrink it to a first step", systemImage: "wand.and.stars") }.buttonStyle(.borderless)
        }
    }

    private func fixLabel(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon).font(DS.Font.headline).frame(maxWidth: .infinity).padding(.vertical, DS.Space.m)
            .background(DS.Palette.accent, in: Capsule()).foregroundStyle(.white)
    }

    // 2. How was it?
    private var rate: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("How bad was it, really?").font(DS.Font.headline)
            FaceScale(selected: actual) { v in withAnimation { actual = v }; Haptics.tap() }
            Button {
                if let a = actual { Dread.rateActual(item.id, a) }
                markDone()
                let guessText = predicted.map { p in "Guessed \(Dread.faces[p - 1]) \(p)" + (actual.map { ", was \(Dread.faces[$0 - 1]) \($0)" } ?? "") }
                DailyLog.add(LogEvent(date: Date(), kind: .dread, title: "Faced: \(item.title)", detail: guessText ?? item.reason.label))
                withAnimation(DS.spring) { stage = 3 }
                Haptics.milestone()
            } label: { Text("Done").frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent).tint(DS.Palette.calm)
        }
    }

    // 3. Finished
    private var finished: some View {
        VStack(spacing: DS.Space.m) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 60)).foregroundStyle(DS.Palette.calm)
            if let p = predicted, let a = actual {
                Text(a < p ? "You guessed \(Dread.faces[p - 1]) \(p), it was \(Dread.faces[a - 1]) \(a)." : "Done, even though it was hard.")
                    .font(DS.Font.title).multilineTextAlignment(.center)
                if a < p { Text("Remember this next time the dread shows up.").foregroundStyle(DS.Palette.inkSoft) }
            } else {
                Text("Done. That took courage.").font(DS.Font.title)
            }
            Button("Close") { dismiss() }.buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private func shrink() async {
        working = true; defer { working = false }
        let steps = await AIRouter.shared.breakDown(item.task?.title ?? item.title, minutesAvailable: 10)
        if let t = item.task, t.microSteps.isEmpty { t.microSteps = steps; try? ctx.save() }
        output = "First step: " + (steps.first?.text ?? "Open it and read it once.") + (steps.count > 1 ? "\nThen: " + steps.dropFirst().prefix(2).map(\.text).joined(separator: ", then ") : "")
    }

    private func clarify() async {
        if let e = item.email {
            working = true; defer { working = false }
            var d = ComposeDraft.reply(to: e, all: false, accounts: accounts)
            let text = await AIRouter.shared.draftReply(to: e, intent: "Briefly ask for clarification about: \(question). Friendly, two or three sentences.") ?? "Quick question before I reply properly: \(question)?"
            d.body = text + d.body
            compose = d
        } else if let t = item.task {
            t.microSteps.insert(MicroStep(text: "Find out: \(question)", minutes: 5), at: 0)
            try? ctx.save()
            output = "Added as your first step: Find out \(question)."
        }
    }

    private func firstSentence() async {
        working = true; defer { working = false }
        if let e = item.email {
            var d = ComposeDraft.reply(to: e, all: false, accounts: accounts)
            let text = await AIRouter.shared.draftReply(to: e, intent: "Start an honest, kind reply. Only the first two sentences; I'll finish it.") ?? WritingStyle.greeting(for: e.fromName)
            d.body = text + d.body
            compose = d
        } else {
            output = await AIRouter.shared.write("Write the opening one or two sentences I could say or send to start this hard conversation, kindly and honestly: \(item.title)")
                ?? "Hi, I've been meaning to talk to you about something, and I'd rather be honest than put it off."
        }
    }

    private func moreTime() {
        if let e = item.email {
            var d = ComposeDraft.reply(to: e, all: false, accounts: accounts)
            let friday = nextWeekday(6)
            d.body = WritingStyle.greeting(for: e.fromName) + "Thanks for your patience on this. I want to give it proper attention, so I'll get back to you by \(friday.formatted(.dateTime.weekday(.wide)))." + WritingStyle.signoffBlock + d.body
            compose = d
        } else if let t = item.task {
            t.dueDate = Calendar.current.date(byAdding: .day, value: 3, to: Calendar.current.startOfDay(for: Date()))
            t.updatedAt = Date()
            try? ctx.save()
            output = "Moved to \(t.dueDate?.formatted(.dateTime.weekday(.wide)) ?? "later"). That's a decision, not a failure."
        }
    }

    private func letGo() {
        if let t = item.task { t.isSomeday = true; t.dueDate = nil }
        if let e = item.email { e.isArchived = true }
        Dread.dismiss(item.id)
        try? ctx.save()
        Haptics.tap()
        dismiss()
    }

    private func markDone() {
        if let t = item.task, !t.isDone { _ = TaskActions.setDone(t, true) }
        if let e = item.email, !e.isArchived {
            e.isArchived = true
            if let a = accounts.first(where: { $0.id == e.accountId }) {
                Task { try? await MailProviderFactory.make(for: a).archive(e.providerMessageId) }
            }
        }
        try? ctx.save()
    }

    private func nextWeekday(_ weekday: Int) -> Date {
        var d = Calendar.current.startOfDay(for: Date())
        repeat { d = Calendar.current.date(byAdding: .day, value: 1, to: d) ?? d } while Calendar.current.component(.weekday, from: d) != weekday
        return d
    }
}

// MARK: - Today card

struct DreadTodayCard: View {
    @Query private var tasks: [TaskItem]
    @Query(filter: #Predicate<EmailMessage> { !$0.isArchived }) private var mail: [EmailMessage]
    @Query private var sessions: [FocusSession]
    @Query private var accounts: [MailAccount]

    var body: some View {
        let items = Dread.items(tasks: tasks, mail: mail, sessions: sessions, accounts: accounts)
        if let top = items.first {
            NavigationLink { DreadRadarView() } label: {
                GlassCard(tint: DS.Palette.warmth) {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Label(items.count == 1 ? "Something you might be avoiding" : "\(items.count) things you might be avoiding",
                              systemImage: "tortoise.fill").font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                        Text(top.title).font(DS.Font.body).foregroundStyle(DS.Palette.ink).lineLimit(1)
                        Text(Dread.gapSentence ?? "\(top.signal). That's normal. Tap for a fix that fits.")
                            .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
        }
    }
}
