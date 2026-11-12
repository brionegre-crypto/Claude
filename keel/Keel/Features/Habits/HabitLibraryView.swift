import SwiftUI
import SwiftData

/// Ready-made habit stacks, each built from tiny 1–5 minute steps. One tap adds it.
struct HabitLibraryView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var stacks: [HabitStack]

    struct Recipe: Identifiable {
        var id: String { name }
        let name: String
        let why: String
        let anchor: StackAnchor
        let steps: [(String, String, Int)]
    }

    static let recipes: [Recipe] = [
        Recipe(name: "Morning launch", why: "Start the day before your phone starts it for you.", anchor: .manual(label: "pour my coffee"),
               steps: [("Take meds", "pills", 1), ("Glass of water", "drop", 1), ("Pick today's one thing", "1.circle", 2), ("Open the first task", "play", 1)]),
        Recipe(name: "Shutdown ritual", why: "Close open loops so work doesn't follow you home.", anchor: .time(hour: 17, minute: 30),
               steps: [("Clear the inbox to zero or snooze", "tray", 5), ("Move unfinished tasks to tomorrow", "arrow.uturn.forward", 2), ("Write tomorrow's first step", "pencil", 2), ("Say “shutdown complete”", "moon", 1)]),
        Recipe(name: "Wind down", why: "Better sleep is the cheapest focus upgrade.", anchor: .time(hour: 21, minute: 30),
               steps: [("Phone on the charger, outside the bedroom", "iphone.slash", 1), ("Lay out tomorrow's clothes", "tshirt", 2), ("Read 10 pages", "book", 10)]),
        Recipe(name: "Post-focus reset", why: "Recover between deep work blocks instead of scrolling.", anchor: .afterFocusSession,
               steps: [("Stand up and stretch", "figure.cooldown", 2), ("Refill water", "drop", 1), ("Look out a window", "eye", 1)]),
        Recipe(name: "Inbox zero reward", why: "Make finishing email feel good.", anchor: .afterInboxZero,
               steps: [("Short walk", "figure.walk", 5), ("Text someone you like", "message", 2)]),
        Recipe(name: "Gym starter", why: "Lower the bar so you show up.", anchor: .location(name: "Gym"),
               steps: [("Put on headphones", "headphones", 1), ("5-min warm-up", "flame", 5), ("Log the workout", "list.bullet", 1)]),
        Recipe(name: "Weekly reset", why: "Sunday clarity for the week ahead.", anchor: .manual(label: "Sunday evening"),
               steps: [("Run the weekly review", "chart.bar.doc.horizontal", 15), ("Check next week's calendar", "calendar", 5), ("Choose 3 outcomes", "target", 5)]),
        Recipe(name: "Meeting buffer", why: "Arrive prepared and leave with next steps.", anchor: .afterEvent(keyword: "meeting"),
               steps: [("Write down action items", "checklist", 2), ("Send the follow-up", "paperplane", 3)]),
        Recipe(name: "Lunch reset", why: "A midday reboot for the afternoon slump.", anchor: .time(hour: 12, minute: 30),
               steps: [("Eat away from the screen", "fork.knife", 15), ("10-minute walk", "figure.walk", 10), ("Re-pick the afternoon's one thing", "1.circle", 2)]),
    ]

    var body: some View {
        List {
            Section { } footer: { Text("Each stack attaches tiny steps to something you already do. Edit any step after adding.") }
            ForEach(Self.recipes) { r in
                let added = stacks.contains { $0.name == r.name }
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(r.name).font(DS.Font.headline)
                            Spacer()
                            Button(added ? "Added" : "Add") { add(r) }
                                .buttonStyle(.borderedProminent).tint(DS.Palette.accent).disabled(added)
                        }
                        Text(r.why).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        Text(r.anchor.label).font(DS.Font.caption).foregroundStyle(DS.Palette.accent)
                        ForEach(Array(r.steps.enumerated()), id: \.offset) { _, s in
                            Label("\(s.0) · \(s.2)m", systemImage: s.1).font(.callout)
                        }
                    }
                }
            }
        }
        .navigationTitle("Habit Library")
    }

    private func add(_ r: Recipe) {
        let s = HabitStack(name: r.name, anchor: r.anchor)
        ctx.insert(s)
        for (i, step) in r.steps.enumerated() {
            let h = Habit(name: step.0, icon: step.1, minutes: step.2)
            h.stackId = s.id; h.orderInStack = i
            ctx.insert(h)
        }
        Haptics.success()
    }
}
