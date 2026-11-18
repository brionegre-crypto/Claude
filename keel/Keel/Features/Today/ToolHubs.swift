import SwiftUI

// MARK: - Tools that do one job, combined
//
// Compass had several separate tools for the same job: five ways to ask the AI, five journals, four timers, a
// handful of food screens. Each set is now one place with a row of tabs across the top. It opens on the tab
// you used last. The individual tools still work from search, links and the tab bar.

struct ToolHubSpec {
    let id: String
    let title: String
    let icon: String
    let keywords: String
    let group: String
    let intro: String
    let members: [(id: String, label: String)]
}

@MainActor
enum ToolHubs {
    static let specs: [ToolHubSpec] = [
        .init(id: "askHub", title: "Ask Keel", icon: "bubble.left.and.text.bubble.right.fill",
              keywords: "ask question ai chat assistant everything notes inbox email voice talk", group: "ask",
              intro: "Ask anything. Everything searches your notes, mail, tasks and calendar together; Notes and Inbox stick to one; Chat keeps a conversation going; Voice lets you talk.",
              members: [("askAll", "Everything"), ("ask", "Chat"), ("askNotes", "Notes"), ("askInbox", "Inbox"), ("talk", "Voice")]),
        .init(id: "journalHub", title: "Journal", icon: "book.closed.fill",
              keywords: "journal diary mood daily log voice journal morning pages gratitude three good things letter future",
              group: "back",
              intro: "Every way to journal in one place: a quick daily log, your mood, a spoken entry, free-writing morning pages, three good things, or a letter to future you.",
              members: [("dayLog", "Daily log"), ("journal", "Mood"), ("voicejournal", "Voice"), ("morningPages", "Morning pages"), ("gratitude", "Good things"), ("letter", "Future you")]),
        .init(id: "reviewHub", title: "Reviews", icon: "chart.bar.doc.horizontal.fill",
              keywords: "weekly review digest wins monthly look back done list wins jar", group: "back",
              intro: "Look back on your week and month: the guided review, an automatic digest, your wins, and everything you got done.",
              members: [("weekly", "Weekly review"), ("digest", "Digest"), ("weeklyWins", "Wins"), ("doneList", "Done list"), ("winsJar", "Wins jar"), ("monthly", "Monthly")]),
        .init(id: "timersHub", title: "Timers", icon: "timer",
              keywords: "timer visual timer countdown transition meeting timer pomodoro chimes", group: "go",
              intro: "Every timer in one place: a visual countdown you can see from across the room, quick timers, a heads-up before switching tasks, a meeting timer and gentle time chimes.",
              members: [("visualTimer", "Visual"), ("timers", "Quick"), ("transition", "Transition"), ("meetingTimer", "Meeting"), ("chimes", "Chimes")]),
        .init(id: "calmHub", title: "Calm toolkit", icon: "leaf.fill",
              keywords: "calm breathe grounding feelings reframe worry anxious stress panic", group: "calm",
              intro: "Ways to settle your mind and body. Breathe slows your heart, Grounding brings you back to the room, Feelings names what's going on, Reframe untangles a thought, Worry time parks worries for later.",
              members: [("breathe", "Breathe"), ("grounding", "Grounding"), ("feelings", "Feelings"), ("reframe", "Reframe"), ("worry", "Worry time")]),
        .init(id: "foodHub", title: "Food", icon: "fork.knife.circle.fill",
              keywords: "food meal log eat nutrition calories meal plan groceries caffeine water fasting", group: "food",
              intro: "Everything about eating: today's totals, logging a meal, your meal plan and groceries, caffeine and water, and fasting.",
              members: [("food", "Today"), ("describeMeal", "Log a meal"), ("mealplan", "Meal plan"), ("drinks", "Drinks"), ("fasting", "Fasting")]),
        .init(id: "medsHub", title: "Medications", icon: "pills.fill",
              keywords: "medications meds pills doses as needed prn refill", group: "food",
              intro: "Your daily medications and the ones you take only when needed, with doses, reminders and refills.",
              members: [("meds", "Daily"), ("prn", "As needed")]),
    ]

    static func hubTool(_ spec: ToolHubSpec, from all: [HubTool]) -> HubTool? {
        let tools = spec.members.compactMap { m in all.first { $0.id == m.id }.map { (tool: $0, label: m.label) } }
        guard tools.count >= 2 else { return nil }
        return HubTool(id: spec.id, title: spec.title, icon: spec.icon, keywords: spec.keywords + " " + tools.map(\.tool.keywords).joined(separator: " "),
                       dest: { AnyView(ToolHubView(spec: spec, tools: tools)) })
    }

    static let memberIds: Set<String> = Set(specs.flatMap { $0.members.map(\.id) })
}

/// One combined tool: tabs across the top, each showing one of the original tools.
struct ToolHubView: View {
    let spec: ToolHubSpec
    let tools: [(tool: HubTool, label: String)]
    @State private var selected: String

    init(spec: ToolHubSpec, tools: [(tool: HubTool, label: String)], start: String? = nil) {
        self.spec = spec
        self.tools = tools
        let saved = UserDefaults.standard.string(forKey: "hub.tab.\(spec.id)")
        let first = tools.first?.tool.id ?? ""
        _selected = State(initialValue: start ?? (tools.contains { $0.tool.id == saved } ? saved! : first))
    }

    var body: some View {
        let current = tools.first { $0.tool.id == selected } ?? tools[0]
        current.tool.dest()
            .id(current.tool.id)                       // a fresh screen per tab, so each keeps its own layout
            .safeAreaInset(edge: .top, spacing: 0) { tabs }
            .onChange(of: selected) { _, v in UserDefaults.standard.set(v, forKey: "hub.tab.\(spec.id)") }
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tools, id: \.tool.id) { t in
                    Button {
                        withAnimation(DS.spring) { selected = t.tool.id }
                        Haptics.tap()
                    } label: {
                        Label(t.label, systemImage: t.tool.icon)
                            .font(.subheadline.weight(selected == t.tool.id ? .semibold : .regular))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .foregroundStyle(selected == t.tool.id ? Color.white : DS.Palette.ink)
                            .background(selected == t.tool.id ? AnyShapeStyle(DS.Palette.accent) : AnyShapeStyle(.thinMaterial), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected == t.tool.id ? .isSelected : [])
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
        .background(.bar)
        .accessibilityLabel("\(spec.title) sections")
    }
}
