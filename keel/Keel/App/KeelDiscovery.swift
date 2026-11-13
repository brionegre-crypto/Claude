import SwiftUI
import SwiftData
import AppIntents

// MARK: - Open any Keel tool from a link, widget, Siri or the tour

struct ToolRoute: Identifiable, Hashable { let id: String }

/// Shows one tool from Today → ⊞ in a sheet (used by links like com.keel.app://tool/vault).
struct ToolSheet: View {
    let id: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if let t = HubCatalog.tool(id) { t.dest() } else { ContentUnavailableView("Not found", systemImage: "questionmark") }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Siri & Shortcuts for the newer features

/// The Keel tools Siri and Shortcuts can open directly.
enum KeelToolChoice: String, AppEnum {
    case vault, mealplan, errands, sharedLists, rewards, automations, tags

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Keel Tool"
    static let caseDisplayRepresentations: [KeelToolChoice: DisplayRepresentation] = [
        .vault: DisplayRepresentation(title: "Paperwork vault", image: .init(systemName: "archivebox.fill")),
        .mealplan: DisplayRepresentation(title: "Meal plan & groceries", image: .init(systemName: "cart.fill")),
        .errands: DisplayRepresentation(title: "Errands", image: .init(systemName: "car.fill")),
        .sharedLists: DisplayRepresentation(title: "Shared lists", image: .init(systemName: "person.2.fill")),
        .rewards: DisplayRepresentation(title: "Rewards", image: .init(systemName: "gift.fill")),
        .automations: DisplayRepresentation(title: "Automations", image: .init(systemName: "bolt.horizontal.fill")),
        .tags: DisplayRepresentation(title: "Tags & saved searches", image: .init(systemName: "number")),
    ]
}

struct OpenKeelToolIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Keel Tool"
    static let description: IntentDescription = "Opens the paperwork vault, meal plan, errands, shared lists, rewards, automations or tags."
    static let openAppWhenRun = true
    @Parameter(title: "Tool") var tool: KeelToolChoice

    @MainActor func perform() async throws -> some IntentResult {
        AppRouter.shared.openTool = ToolRoute(id: tool.rawValue)
        return .result()
    }
}

/// "Start my next task": picks your next thing (or the task you name) and starts a Now timer for it.
struct StartNowIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Task Now"
    static let description: IntentDescription = "Starts a task with a countdown sized to how long tasks like it really take you."
    @Parameter(title: "Task") var task: TaskEntity?

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = KeelStore.container.mainContext
        let open = (try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? []
        let picked: TaskItem?
        if let task { picked = open.first { $0.id == task.id } } else {
            let energy = EnergyLevel(rawValue: UserDefaults.standard.integer(forKey: "energy")) ?? .medium
            picked = ADHDCoach.nextThing(tasks: open, energy: energy)
        }
        guard let t = picked else { return .result(dialog: "Nothing waiting. Enjoy the break.") }
        guard ShutdownManager.shared.active == nil else { return .result(dialog: "You're already in a session. Finish that one first.") }
        NowTimer.start(t, ctx: ctx)
        try? ctx.save()
        WidgetSync.update(ctx)
        return .result(dialog: "Starting “\(t.title)”. \(max(5, ADHDCoach.calibratedMinutes(t))) minutes on the clock.")
    }
}

struct AddGroceryIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Groceries"
    static let description: IntentDescription = "Adds items to your Keel grocery list, sorted by aisle. Say several at once: “milk, eggs and spinach”."
    @Parameter(title: "Items", requestValueDialog: "What should I add?") var items: String

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = KeelStore.container.mainContext
        let names = Self.split(items)
        guard !names.isEmpty else { return .result(dialog: "I didn't catch anything to add.") }
        let have = Set(((try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? [])
            .filter { $0.listName == MealPlanner.groceryList }.map { $0.title.lowercased() })
        var added: [String] = []
        for n in names where !have.contains(n.lowercased()) {
            let t = TaskItem(title: n)
            t.listName = MealPlanner.groceryList
            t.tags = ["~aisle:" + MealPlanner.aisle(for: n)]
            ctx.insert(t)
            added.append(n)
        }
        try? ctx.save()
        WidgetSync.update(ctx)
        if added.isEmpty { return .result(dialog: "Already on your list.") }
        return .result(dialog: "Added \(Self.list(added)) to groceries.")
    }

    static func split(_ s: String) -> [String] {
        s.replacingOccurrences(of: " and ", with: ",").split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }
    static func list(_ a: [String]) -> String {
        a.count <= 1 ? (a.first ?? "") : a.dropLast().joined(separator: ", ") + " and " + a.last!
    }
}

struct GroceryListIntent: AppIntent {
    static let title: LocalizedStringResource = "What's on My Grocery List"

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let items = ((try? KeelStore.container.mainContext.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? [])
            .filter { $0.listName == MealPlanner.groceryList }.map(\.title)
        guard !items.isEmpty else { return .result(dialog: "Your grocery list is empty.") }
        return .result(dialog: "\(items.count) item\(items.count == 1 ? "" : "s"): \(AddGroceryIntent.list(Array(items.prefix(12)))).")
    }
}

struct ThisEveningIntent: AppIntent {
    static let title: LocalizedStringResource = "Move Task to This Evening"
    @Parameter(title: "Task") var task: TaskEntity

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = KeelStore.container.mainContext
        let id = task.id
        guard let t = try ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first else {
            return .result(dialog: "I couldn't find that task.")
        }
        TaskMeta.setEvening(t, true)
        try ctx.save()
        WidgetSync.update(ctx)
        return .result(dialog: "“\(t.title)” is set for this evening.")
    }
}

struct DeadlinesIntent: AppIntent {
    static let title: LocalizedStringResource = "Upcoming Deadlines"
    static let description: IntentDescription = "Hear which deadlines are coming up."

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let open = (try? KeelStore.container.mainContext.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? []
        let list = open.compactMap { t in TaskMeta.deadline(t).map { (t.title, $0) } }.sorted { $0.1 < $1.1 }
        guard !list.isEmpty else { return .result(dialog: "No deadlines coming up.") }
        let lines = list.prefix(3).map { "\($0.0), \($0.1.formatted(.relative(presentation: .named)))" }
        return .result(dialog: "\(list.count) deadline\(list.count == 1 ? "" : "s"). \(lines.joined(separator: "; ")).")
    }
}

struct RewardsStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "My Keel Level"

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = KeelStore.container.mainContext
        let xp = Rewards.xp(ctx: ctx)
        let l = Rewards.level(xp)
        return .result(dialog: "Level \(l.level), \(l.next - l.into) XP to the next one. You have \(max(0, xp - Rewards.spent)) coins to spend.")
    }
}

// MARK: - What's new (shown once to people who already use Keel) and the feature tour

struct DiscoverItem: Identifiable {
    let id: String          // a HubCatalog tool id, or "" for a tip without a screen
    let icon: String
    let color: Color
    let title: String
    let text: String
}

enum Discover {
    static let version = "launch-1"
    static let seenKey = "whatsnew.seen"

    static let items: [DiscoverItem] = [
        DiscoverItem(id: "", icon: "timer", color: .orange, title: "Start now",
                     text: "Hold any task → Start now. A countdown sized to how long it really takes you, on your Lock Screen."),
        DiscoverItem(id: "", icon: "moon.stars.fill", color: .indigo, title: "This Evening & deadlines",
                     text: "Hold a task to save it for tonight, or give it a real deadline. You get a heads-up the day before."),
        DiscoverItem(id: "vault", icon: "archivebox.fill", color: .brown, title: "Paperwork vault",
                     text: "Scan receipts, warranties and IDs. Keel files them and reminds you before returns and expiry dates."),
        DiscoverItem(id: "mealplan", icon: "cart.fill", color: .green, title: "Meal plan & groceries",
                     text: "A week of meals from your diet guide, and a grocery list by aisle that checks itself off when you scan."),
        DiscoverItem(id: "sharedLists", icon: "person.2.fill", color: .blue, title: "Shared lists",
                     text: "Share a list by link. Anyone can tick things off, in Keel or a browser."),
        DiscoverItem(id: "errands", icon: "car.fill", color: .teal, title: "Errands by place",
                     text: "Pharmacy, post office, store: errands grouped by where you need to go."),
        DiscoverItem(id: "automations", icon: "bolt.horizontal.fill", color: .yellow, title: "Automations",
                     text: "When an email arrives or a task is done, Keel can add a task, log it or tidy up for you."),
        DiscoverItem(id: "rewards", icon: "gift.fill", color: .pink, title: "Rewards & a buddy",
                     text: "Earn XP and coins for what you finish, spend them on treats you pick, and share your week with a friend."),
        DiscoverItem(id: "", icon: "scribble.variable", color: .purple, title: "Canvas, history & publishing",
                     text: "In Notes: whiteboards, every earlier version of a page, #tags, and pages you can share as a web link."),
        DiscoverItem(id: "", icon: "mic.fill", color: .red, title: "Ask Siri",
                     text: "“Start my next task in Keel”, “Add milk to groceries in Keel”, or add the new Keel widgets to your Home Screen."),
    ]
}

/// One screen listing what's new, each row opening the feature.
struct DiscoverList: View {
    var onOpen: (String) -> Void
    var body: some View {
        VStack(spacing: DS.Space.s) {
            ForEach(Discover.items) { item in
                Button { if !item.id.isEmpty { onOpen(item.id) } } label: {
                    HStack(alignment: .top, spacing: DS.Space.m) {
                        Image(systemName: item.icon).font(.title3).foregroundStyle(item.color.gradient)
                            .frame(width: 40, height: 40)
                            .background(item.color.opacity(0.14), in: .rect(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                            Text(item.text).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        if !item.id.isEmpty { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft) }
                    }
                    .padding(DS.Space.m)
                    .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.chip))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(item.id.isEmpty ? "" : "Opens \(item.title)")
            }
        }
    }
}

/// Shown once after updating, to people who finished onboarding before these features existed.
struct WhatsNewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var opening: ToolRoute?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.l) {
                    VStack(spacing: DS.Space.s) {
                        Image(systemName: "sparkles").font(.system(size: 44, weight: .semibold)).foregroundStyle(DS.Palette.accent.gradient)
                        Text("New in Keel").font(DS.Font.hero)
                        Text("Tap anything to try it. You can find all of it later in Today → ⊞ and Settings → Help.")
                            .font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft).multilineTextAlignment(.center)
                    }
                    .padding(.top, DS.Space.m)
                    DiscoverList { opening = ToolRoute(id: $0) }
                }
                .padding(DS.Space.l)
            }
            .background(DS.Palette.canvas)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $opening) { ToolSheet(id: $0.id) }
        }
    }
}

/// Decides whether to show What's new: only for people who were already set up, once per release.
struct WhatsNewModifier: ViewModifier {
    @AppStorage("onboarding.done") private var onboarded = false
    @AppStorage(Discover.seenKey) private var seen = ""
    @State private var show = false

    func body(content: Content) -> some View {
        content
            .task {
                guard onboarded, seen != Discover.version else { return }
                try? await Task.sleep(for: .seconds(1.2))      // let Today settle first
                show = true
            }
            .sheet(isPresented: $show, onDismiss: { seen = Discover.version }) { WhatsNewSheet() }
    }
}
