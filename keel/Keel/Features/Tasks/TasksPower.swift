import SwiftUI
import SwiftData
import UserNotifications
import FoundationModels

// MARK: - This Evening & deadlines (kept in hidden "~" tags, so they sync with no new data fields)

@MainActor
enum TaskMeta {
    static let eveningTag = "~evening"
    static let deadlinePrefix = "~deadline:"

    static func isHidden(_ tag: String) -> Bool { tag.hasPrefix("~") }
    static func visibleTags(_ t: TaskItem) -> [String] { t.tags.filter { !isHidden($0) } }

    static func isEvening(_ t: TaskItem) -> Bool { t.tags.contains(eveningTag) }
    static func setEvening(_ t: TaskItem, _ on: Bool) {
        t.tags.removeAll { $0 == eveningTag }
        if on {
            t.tags.append(eveningTag)
            if t.dueDate == nil { t.dueDate = Calendar.current.startOfDay(for: Date()) }
        }
        t.updatedAt = Date()
    }

    static func deadline(_ t: TaskItem) -> Date? {
        t.tags.first { $0.hasPrefix(deadlinePrefix) }.flatMap { ISO8601DateFormatter.dateOnly.date(from: String($0.dropFirst(deadlinePrefix.count))) }
    }
    /// A hard deadline, separate from when you plan to work on it. You get a heads-up the morning before.
    static func setDeadline(_ t: TaskItem, _ d: Date?) {
        t.tags.removeAll { $0.hasPrefix(deadlinePrefix) }
        let id = "deadline.\(t.id.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        t.updatedAt = Date()
        guard let d else { return }
        t.tags.append(deadlinePrefix + ISO8601DateFormatter.dateOnly.string(from: d))
        let cal = Calendar.current
        guard let dayBefore = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: d)),
              let fire = cal.date(bySettingHour: 9, minute: 0, second: 0, of: dayBefore), fire > Date() else { return }
        let c = UNMutableNotificationContent()
        c.title = "Deadline tomorrow: \(t.title)"
        c.body = "Due \(d.formatted(date: .complete, time: .omitted))."
        c.userInfo = ["taskId": t.id.uuidString]
        KeelAlerts.urgent(c)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c,
            trigger: UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)))
    }
}

struct DeadlineSheet: View {
    let task: TaskItem
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date().addingTimeInterval(3 * 86_400)
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Deadline", selection: $date, in: Date()..., displayedComponents: .date).datePickerStyle(.graphical)
                Text("The deadline is when it must be done. The due date is when you plan to work on it, so the task never looks overdue early.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                if TaskMeta.deadline(task) != nil {
                    Button("Remove deadline", role: .destructive) { TaskMeta.setDeadline(task, nil); dismiss() }
                }
            }
            .navigationTitle("Deadline").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Set") { TaskMeta.setDeadline(task, date); Haptics.tap(); dismiss() } } }
            .onAppear { if let d = TaskMeta.deadline(task) { date = d } }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Now timer (time blindness)

@MainActor
enum NowTimer {
    /// Starts the task with a live countdown on the Lock Screen, Dynamic Island and Watch, sized to how long
    /// tasks like it really take you, with a gentle tap halfway and at the end.
    static func start(_ t: TaskItem, ctx: ModelContext) {
        let minutes = max(5, ADHDCoach.calibratedMinutes(t))
        let session = ShutdownManager.shared.start(minutes: minutes, level: .soft, task: t)
        ctx.insert(session)
        if minutes >= 10 {
            let c = UNMutableNotificationContent()
            c.title = "Halfway: \(t.title)"
            c.body = "\(minutes / 2) minutes left. Still on it?"
            c.sound = .default
            c.interruptionLevel = .active
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "now.half", content: c,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: Double(minutes * 30), repeats: false)))
        }
        Haptics.success()
    }
}

// MARK: - Errands by place

@MainActor
enum Errands {
    static let places: [(name: String, icon: String, words: [String])] = [
        ("Grocery store", "cart.fill", ["grocery", "groceries", "milk", "eggs", "bread", "produce", "whole foods", "kroger", "publix", "trader joe", "aldi"]),
        ("Pharmacy", "cross.case.fill", ["pharmacy", "prescription", "cvs", "walgreens", "refill", "meds", "medicine"]),
        ("Post office", "shippingbox.fill", ["post office", "mail ", "stamps", "ship", "return package", "usps", "ups store", "fedex"]),
        ("Bank", "building.columns.fill", ["bank", "deposit", "atm", "cash", "check"]),
        ("Hardware store", "hammer.fill", ["hardware", "home depot", "lowe's", "lowes", "screws", "paint", "bulb"]),
        ("Target / Walmart", "bag.fill", ["target", "walmart", "costco", "sam's club", "amazon return"]),
        ("Gas & car", "car.fill", ["gas", "oil change", "car wash", "tires", "inspection"]),
        ("Dry cleaner", "tshirt.fill", ["dry clean", "laundry", "tailor"]),
    ]

    static func place(for t: TaskItem) -> Int? {
        let s = (t.title + " " + t.notes + " " + t.listName).lowercased()
        return places.indices.first { i in places[i].words.contains { s.contains($0) } }
    }
}

struct ErrandsView: View {
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var open: [TaskItem]
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var ctx

    var body: some View {
        let grouped = Dictionary(grouping: open.compactMap { t in Errands.place(for: t).map { ($0, t) } }, by: { $0.0 })
        List {
            if grouped.isEmpty {
                ContentUnavailableView("No errands", systemImage: "car", description: Text("Tasks like “pick up prescription” or “return package” are grouped here by where you'd do them."))
            }
            ForEach(grouped.keys.sorted(), id: \.self) { i in
                let p = Errands.places[i]
                Section {
                    ForEach(grouped[i]!.map { $0.1 }) { t in
                        Button {
                            _ = TaskActions.setDone(t, true); try? ctx.save(); Haptics.success()
                        } label: { Label(t.title, systemImage: "circle").foregroundStyle(DS.Palette.ink) }
                    }
                } header: {
                    HStack {
                        Label(p.name, systemImage: p.icon)
                        Spacer()
                        Button("Find nearby") {
                            if let q = p.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), let u = URL(string: "maps://?q=\(q)") { openURL(u) }
                        }
                        .font(DS.Font.caption).textCase(nil)
                    }
                } footer: {
                    Text("Tip: give one of these tasks a location to be reminded when you're there.")
                }
            }
        }
        .navigationTitle("Errands")
    }
}

// MARK: - Meal plan + grocery list (from your diet guide)

@MainActor
enum MealPlanner {
    static let groceryList = "Groceries"

    struct Day: Identifiable { var id: String { day }; var day: String; var breakfast: String; var lunch: String; var dinner: String }
    struct Plan { var days: [Day]; var groceries: [(item: String, aisle: String)] }

    @Generable
    struct DayOut {
        var breakfast: String
        var lunch: String
        var dinner: String
    }
    @Generable
    struct WeekOut {
        @Guide(description: "Exactly seven days, Monday to Sunday", .maximumCount(7)) var days: [DayOut]
        @Guide(description: "Everything to buy for the week, one item each, short", .maximumCount(40)) var groceries: [String]
    }

    /// A week of meals from the foods your diet guide approves, with oily fish twice and pumpkin seeds daily.
    static func makePlan() async -> Plan {
        let approved = DietGuide.entries.filter { ($0.status == "approved" || $0.status == "best") && [1, 2, 3, 7, 8, 9, 10].contains($0.s) }
        let foods = approved.prefix(90).map(\.name).joined(separator: "; ")
        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        if case .available = SystemLanguageModel.default.availability {
            let s = LanguageModelSession(instructions: "You plan simple, quick ADHD-friendly meals using only foods from this approved list. Include oily fish (salmon, sardines or mackerel) at least twice and pumpkin seeds every day. No pork, shellfish, soy or refined sugar.")
            if let w = try? await s.respond(to: "Approved foods: \(foods)", generating: WeekOut.self).content, w.days.count >= 7 {
                return Plan(days: names.indices.map { Day(day: names[$0], breakfast: w.days[$0].breakfast, lunch: w.days[$0].lunch, dinner: w.days[$0].dinner) },
                            groceries: w.groceries.map { ($0, aisle(for: $0)) })
            }
        }
        // Without Apple Intelligence: a simple rotation from the guide.
        let proteins = approved.filter { [1, 2].contains($0.s) }.map(\.name)
        let fish = approved.filter { $0.s == 2 }.map(\.name)
        let sides = approved.filter { [7, 8, 10].contains($0.s) }.map(\.name)
        var days: [(String, String, String, String)] = []
        for (i, d) in names.enumerated() {
            let protein = (i == 1 || i == 4) && !fish.isEmpty ? fish[i % fish.count] : (proteins.isEmpty ? "Eggs" : proteins[i % proteins.count])
            let side = sides.isEmpty ? "Vegetables" : sides[(i * 3) % sides.count]
            days.append((d, "Eggs with avocado + pumpkin seeds", "Leftovers or a big salad with \(side)", "\(protein) with \(side)"))
        }
        let items = Array(Set(days.map { $0.3 } + ["Eggs", "Avocado", "Pumpkin seeds", "Leafy greens"]))
        return Plan(days: days.map { Day(day: $0.0, breakfast: $0.1, lunch: $0.2, dinner: $0.3) }, groceries: items.map { ($0, aisle(for: $0)) })
    }

    static func aisle(for item: String) -> String {
        let s = item.lowercased()
        if ["salmon", "sardine", "mackerel", "chicken", "beef", "turkey", "fish", "steak", "bison", "lamb"].contains(where: { s.contains($0) }) { return "Meat & seafood" }
        if ["egg", "yogurt", "milk", "cheese", "kefir", "butter"].contains(where: { s.contains($0) }) { return "Dairy & eggs" }
        if ["seed", "nut", "almond", "walnut", "oil", "oat", "rice", "quinoa", "bean", "lentil", "flour"].contains(where: { s.contains($0) }) { return "Pantry" }
        if ["bread", "tortilla", "wrap"].contains(where: { s.contains($0) }) { return "Bakery" }
        if ["frozen"].contains(where: { s.contains($0) }) { return "Frozen" }
        return "Produce"
    }

    /// Saves the plan as a note and the shopping list as tasks in the Groceries list (shareable).
    static func save(_ p: Plan, ctx: ModelContext) -> Note {
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let n = Note(title: "Meal plan · week of \(week.formatted(.dateTime.month().day()))", blocks: [])
        n.icon = "🥗"
        n.folder = NotePath.make("Personal", "Meal plans")
        for d in p.days {
            n.blocks.append(NoteBlock(kind: .heading3, text: d.day))
            n.blocks.append(NoteBlock(kind: .bullet, text: "Breakfast: \(d.breakfast)"))
            n.blocks.append(NoteBlock(kind: .bullet, text: "Lunch: \(d.lunch)"))
            n.blocks.append(NoteBlock(kind: .bullet, text: "Dinner: \(d.dinner)"))
        }
        ctx.insert(n)
        let existing = Set(((try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? []).filter { $0.listName == groceryList }.map { $0.title.lowercased() })
        for g in p.groceries where !existing.contains(g.item.lowercased()) {
            let t = TaskItem(title: g.item)
            t.listName = groceryList
            t.tags = ["~aisle:" + g.aisle]
            ctx.insert(t)
        }
        try? ctx.save()
        return n
    }

    /// Scanning a product in the store checks it off the grocery list.
    static func checkOff(productName: String, ctx: ModelContext) -> String? {
        let words = Set(productName.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count > 3 })
        let open = ((try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? []).filter { $0.listName == groceryList }
        guard let hit = open.first(where: { t in !words.isDisjoint(with: Set(t.title.lowercased().split { !$0.isLetter }.map(String.init))) }) else { return nil }
        _ = TaskActions.setDone(hit, true)
        return hit.title
    }
}

struct MealPlanView: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var open: [TaskItem]
    @State private var plan: MealPlanner.Plan?
    @State private var working = false
    @State private var saved: Note?

    private var groceries: [TaskItem] { open.filter { $0.listName == MealPlanner.groceryList } }

    var body: some View {
        List {
            Section {
                Button {
                    Task { working = true; plan = await MealPlanner.makePlan(); working = false }
                } label: {
                    HStack { Label(working ? "Planning your week…" : "Plan this week's meals", systemImage: "sparkles"); if working { Spacer(); ProgressView() } }
                }
                .disabled(working)
            } footer: { Text("Built only from foods your diet guide approves: oily fish at least twice, pumpkin seeds daily, no pork, shellfish, soy or refined sugar.") }

            if let p = plan {
                ForEach(p.days) { d in
                    Section(d.day) {
                        Label(d.breakfast, systemImage: "sunrise")
                        Label(d.lunch, systemImage: "sun.max")
                        Label(d.dinner, systemImage: "moon.stars")
                    }
                }
                Section {
                    Button("Save plan + add groceries", systemImage: "cart.badge.plus") { saved = MealPlanner.save(p, ctx: ctx); plan = nil; Haptics.success() }
                }
            }

            if !groceries.isEmpty {
                let byAisle = Dictionary(grouping: groceries) { t in t.tags.first { $0.hasPrefix("~aisle:") }.map { String($0.dropFirst(7)) } ?? "Other" }
                ForEach(byAisle.keys.sorted(), id: \.self) { aisle in
                    Section("Groceries · \(aisle)") {
                        ForEach(byAisle[aisle] ?? []) { t in
                            Button { _ = TaskActions.setDone(t, true); try? ctx.save(); Haptics.tap() } label: {
                                Label(t.title, systemImage: "circle").foregroundStyle(DS.Palette.ink)
                            }
                        }
                    }
                }
                Section {
                    NavigationLink { SharedListsView() } label: { Label("Share the grocery list", systemImage: "person.2") }
                } footer: { Text("Scanning a product with the food scanner also checks it off.") }
            }
        }
        .navigationTitle("Meal plan")
        .navigationDestination(item: $saved) { NoteEditor(note: $0) }
    }
}

// MARK: - Rewards & accountability

@MainActor
enum Rewards {
    struct Reward: Codable, Identifiable, Hashable { var id = UUID(); var name: String; var cost: Int }
    static let rewardsKey = "rewards.list", spentKey = "rewards.spent", buddyKey = "rewards.buddy"

    static var rewards: [Reward] {
        get { UserDefaults.standard.data(forKey: rewardsKey).flatMap { try? JSONDecoder().decode([Reward].self, from: $0) }
              ?? [Reward(name: "Favorite coffee", cost: 150), Reward(name: "An episode guilt-free", cost: 250), Reward(name: "Something small I've wanted", cost: 1_000)] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: rewardsKey) }
    }
    static var spent: Int {
        get { UserDefaults.standard.integer(forKey: spentKey) }
        set { UserDefaults.standard.set(newValue, forKey: spentKey) }
    }

    /// XP: 10 per task, 5 per habit, 1 per focus minute.
    static func xp(ctx: ModelContext) -> Int {
        let done = ((try? ctx.fetchCount(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isDone }))) ?? 0)
        let repeats = ((try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []).reduce(0) { $0 + $1.completionCount }
        let habits = (try? ctx.fetchCount(FetchDescriptor<HabitLog>())) ?? 0
        let focus = ((try? ctx.fetch(FetchDescriptor<FocusSession>())) ?? []).reduce(0) { total, s in
            total + Int(((s.endedAt ?? s.startedAt).timeIntervalSince(s.startedAt)) / 60)
        }
        return (done + repeats) * 10 + habits * 5 + focus
    }

    static func level(_ xp: Int) -> (level: Int, into: Int, next: Int) {
        var lvl = 1, need = 100, left = xp
        while left >= need { left -= need; lvl += 1; need = 100 + (lvl - 1) * 50 }
        return (lvl, left, need)
    }

    /// This week's wins, written to send to your accountability buddy.
    static func weeklyNote(ctx: ModelContext) -> String {
        let since = Date().addingTimeInterval(-7 * 86_400)
        let done = ((try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isDone }))) ?? []).filter { ($0.completedAt ?? .distantPast) > since }
        let habits = ((try? ctx.fetch(FetchDescriptor<HabitLog>())) ?? []).filter { $0.completedAt > since }.count
        let focus = ((try? ctx.fetch(FetchDescriptor<FocusSession>())) ?? []).filter { $0.startedAt > since }
            .reduce(0) { $0 + Int((($1.endedAt ?? $1.startedAt).timeIntervalSince($1.startedAt)) / 60) }
        var lines = ["My week with Keel:", "✅ \(done.count) tasks done", "🔁 \(habits) habit check-ins", "🎯 \(focus / 60)h \(focus % 60)m focused"]
        if !done.isEmpty { lines.append("Wins: " + done.prefix(4).map(\.title).joined(separator: ", ")) }
        lines.append("Keep me honest next week? 🙌")
        return lines.joined(separator: "\n")
    }
}

struct RewardsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.openURL) private var openURL
    @State private var rewards = Rewards.rewards
    @State private var spent = Rewards.spent
    @State private var xp = 0
    @State private var newName = ""
    @State private var newCost = 200
    @AppStorage(Rewards.buddyKey) private var buddy = ""

    var body: some View {
        let lv = Rewards.level(xp)
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Level \(lv.level)").font(DS.Font.title)
                        Spacer()
                        Text("\(max(0, xp - spent)) coins").font(DS.Font.headline).foregroundStyle(.orange)
                    }
                    ProgressView(value: Double(lv.into), total: Double(lv.next)).tint(DS.Palette.accent)
                    Text("\(lv.next - lv.into) XP to level \(lv.level + 1) · tasks 10, habits 5, focus 1 per minute").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                }
                .padding(.vertical, 4)
            }
            Section {
                ForEach(rewards) { r in
                    HStack {
                        Text(r.name)
                        Spacer()
                        Button("\(r.cost) 🪙") {
                            guard xp - spent >= r.cost else { return }
                            spent += r.cost; Rewards.spent = spent; Haptics.milestone()
                        }
                        .buttonStyle(.bordered).disabled(xp - spent < r.cost)
                    }
                }
                .onDelete { idx in rewards.remove(atOffsets: idx); Rewards.rewards = rewards }
                HStack {
                    TextField("Add a reward", text: $newName)
                    Stepper("\(newCost)", value: $newCost, in: 50...5_000, step: 50).fixedSize()
                    Button("Add") { rewards.append(.init(name: newName, cost: newCost)); Rewards.rewards = rewards; newName = "" }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: { Text("Treat yourself") } footer: { Text("Spend coins on rewards you choose. Earning them is the point: small, real rewards keep ADHD brains coming back.") }
            Section {
                TextField("Buddy's phone or email", text: $buddy).textInputAutocapitalization(.never).keyboardType(.emailAddress)
                Button("Send this week's wins", systemImage: "paperplane.fill") { sendWins() }.disabled(buddy.isEmpty)
            } header: { Text("Accountability buddy") } footer: { Text("Opens Messages or Mail with your week written out. Nothing is sent without you.") }
        }
        .navigationTitle("Rewards")
        .task { xp = Rewards.xp(ctx: ctx) }
    }

    private func sendWins() {
        let text = Rewards.weeklyNote(ctx: ctx)
        let q = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let to = buddy.trimmingCharacters(in: .whitespaces)
        let url = to.contains("@") ? URL(string: "mailto:\(to)?subject=My%20week&body=\(q)") : URL(string: "sms:\(to.filter { $0.isNumber || $0 == "+" })&body=\(q)")
        if let url { openURL(url) }
    }
}

// MARK: - Automations ("when this happens, do that")

struct AutomationRule: Codable, Identifiable, Hashable {
    enum Trigger: String, Codable, CaseIterable { case emailFrom, emailSubject, taskDone, focusEnded }
    enum Action: String, Codable, CaseIterable { case createTask, logToJournal, notify, archiveEmail }
    var id = UUID()
    var enabled = true
    var trigger: Trigger = .emailFrom
    var match = ""                  // sender / words / task words (empty = any)
    var action: Action = .createTask
    var text = ""                   // task title, journal line or message; {subject} {from} {task} are filled in

    var summary: String {
        let when: String = switch trigger {
        case .emailFrom: "Email from “\(match)”"
        case .emailSubject: "Email subject has “\(match)”"
        case .taskDone: match.isEmpty ? "Any task is done" : "Task with “\(match)” is done"
        case .focusEnded: "A focus session ends"
        }
        let then: String = switch action {
        case .createTask: "add task “\(text)”"
        case .logToJournal: "write “\(text)” in today's log"
        case .notify: "notify me “\(text)”"
        case .archiveEmail: "archive the email"
        }
        return "\(when) → \(then)"
    }
}

@MainActor
enum Automations {
    static let key = "automations.rules"
    static var rules: [AutomationRule] {
        get { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([AutomationRule].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    private static func fill(_ s: String, subject: String = "", from: String = "", task: String = "") -> String {
        s.replacingOccurrences(of: "{subject}", with: subject).replacingOccurrences(of: "{from}", with: from).replacingOccurrences(of: "{task}", with: task)
    }

    private static func perform(_ r: AutomationRule, ctx: ModelContext, email: EmailMessage? = nil, task: TaskItem? = nil) {
        let text = fill(r.text, subject: email?.subject ?? "", from: email?.fromName ?? email?.from ?? "", task: task?.title ?? "")
        switch r.action {
        case .createTask:
            let t = TaskItem(title: text.isEmpty ? (email?.subject ?? "Follow up") : text, dueDate: Calendar.current.startOfDay(for: Date()))
            t.sourceEmailId = email?.id
            ctx.insert(t)
        case .logToJournal:
            DailyLog.add(LogEvent(date: Date(), kind: .note, title: text.isEmpty ? "Automation ran" : text))
        case .notify:
            let c = UNMutableNotificationContent()
            c.title = text.isEmpty ? "Keel automation" : text
            c.body = email?.subject ?? task?.title ?? ""
            c.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "auto.\(UUID().uuidString)", content: c, trigger: nil))
        case .archiveEmail:
            email?.isArchived = true
        }
    }

    static func emailsArrived(_ emails: [EmailMessage], ctx: ModelContext) {
        let active = rules.filter { $0.enabled && ($0.trigger == .emailFrom || $0.trigger == .emailSubject) }
        guard !active.isEmpty else { return }
        for e in emails {
            for r in active {
                let m = r.match.lowercased()
                let hit = r.trigger == .emailFrom ? (e.from.lowercased().contains(m) || e.fromName.lowercased().contains(m)) : e.subject.lowercased().contains(m)
                if hit && !m.isEmpty { perform(r, ctx: ctx, email: e) }
            }
        }
    }

    static func taskCompleted(_ t: TaskItem, ctx: ModelContext?) {
        guard let ctx else { return }
        for r in rules where r.enabled && r.trigger == .taskDone && (r.match.isEmpty || t.title.lowercased().contains(r.match.lowercased())) {
            perform(r, ctx: ctx, task: t)
        }
    }

    static func focusEnded(ctx: ModelContext) {
        for r in rules where r.enabled && r.trigger == .focusEnded { perform(r, ctx: ctx) }
    }
}

struct AutomationsView: View {
    @State private var rules = Automations.rules
    @State private var editing: AutomationRule?

    var body: some View {
        List {
            Section {
                ForEach($rules) { $r in
                    HStack {
                        Toggle(isOn: $r.enabled) { Text(r.summary).font(DS.Font.body) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editing = r }
                }
                .onDelete { idx in rules.remove(atOffsets: idx) }
                Button("New automation", systemImage: "plus") { editing = AutomationRule() }
            } footer: {
                Text("Examples: email from your kid's school → add task “Read school email”; a task with “workout” done → write “Worked out 💪” in today's log; a focus session ends → remind me to stretch.")
            }
            Section("Ideas") {
                ForEach(starters, id: \.id) { s in
                    Button(s.summary) { rules.append(s) }.font(DS.Font.caption)
                }
            }
        }
        .navigationTitle("Automations")
        .onChange(of: rules) { _, new in Automations.rules = new }
        .sheet(item: $editing) { r in
            AutomationEditor(rule: r) { saved in
                if let i = rules.firstIndex(where: { $0.id == saved.id }) { rules[i] = saved } else { rules.append(saved) }
            }
        }
    }

    private var starters: [AutomationRule] {
        [AutomationRule(trigger: .emailSubject, match: "permission slip", action: .createTask, text: "Sign: {subject}"),
         AutomationRule(trigger: .taskDone, match: "workout", action: .logToJournal, text: "Worked out 💪"),
         AutomationRule(trigger: .focusEnded, action: .notify, text: "Stand up, stretch, water")]
    }
}

private struct AutomationEditor: View {
    @State var rule: AutomationRule
    let onSave: (AutomationRule) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("When") {
                    Picker("Trigger", selection: $rule.trigger) {
                        Text("Email from…").tag(AutomationRule.Trigger.emailFrom)
                        Text("Email subject has…").tag(AutomationRule.Trigger.emailSubject)
                        Text("A task is done").tag(AutomationRule.Trigger.taskDone)
                        Text("Focus session ends").tag(AutomationRule.Trigger.focusEnded)
                    }
                    if rule.trigger != .focusEnded {
                        TextField(rule.trigger == .taskDone ? "Task words (empty = any task)" : "Name, address or words", text: $rule.match)
                    }
                }
                Section {
                    Picker("Action", selection: $rule.action) {
                        Text("Add a task").tag(AutomationRule.Action.createTask)
                        Text("Write in today's log").tag(AutomationRule.Action.logToJournal)
                        Text("Notify me").tag(AutomationRule.Action.notify)
                        if rule.trigger == .emailFrom || rule.trigger == .emailSubject { Text("Archive the email").tag(AutomationRule.Action.archiveEmail) }
                    }
                    if rule.action != .archiveEmail { TextField("Text", text: $rule.text) }
                } header: { Text("Then") } footer: { Text("Use {subject}, {from} or {task} to fill in details.") }
            }
            .navigationTitle("Automation").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(rule); dismiss() } }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
