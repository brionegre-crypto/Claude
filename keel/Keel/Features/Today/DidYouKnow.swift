import SwiftUI

/// "Did you know?" One feature a day on Today for your first week (or until you've seen them all), so Keel's
/// depth unfolds gradually instead of all at once. Dismiss it any time; nothing else changes.
struct DidYouKnowCard: View {
    @AppStorage("dyk.index") private var index = 0
    @AppStorage("dyk.lastDay") private var lastDay = ""
    @AppStorage("dyk.off") private var off = false

    private struct Tip { let title: String; let text: String; let icon: String; let tool: String? }
    private static let tips: [Tip] = [
        .init(title: "Tell Keel what you ate", text: "On Body → Food, type “two eggs and toast”. It's logged and checked against your diet.", icon: "fork.knife", tool: nil),
        .init(title: "Not a normal day?", text: "Sick, travelling or a late night: mark it on Body → Today so it doesn't drag your Tide down.", icon: "calendar.badge.exclamationmark", tool: nil),
        .init(title: "Smart lists that think", text: "In Tasks, make a smart list with a typed filter like “today & #work | p1”.", icon: "line.3.horizontal.decrease.circle", tool: nil),
        .init(title: "Start dates", text: "Give a task a start date and it stays out of the way until then. See what's coming in Upcoming.", icon: "calendar.badge.clock", tool: nil),
        .init(title: "Ask your inbox", text: "In Inbox → ⋯ → Ask your inbox: “When is the dentist?” finds the answer in your mail.", icon: "questionmark.bubble", tool: "askHub"),
        .init(title: "Your diets", text: "Upload the plan from your dietitian, doctor or faith: every scan is checked against it.", icon: "list.bullet.clipboard", tool: nil),
        .init(title: "Smart alarm", text: "On Apple Watch, Keel → Smart alarm wakes you in lighter sleep within a window you choose.", icon: "alarm", tool: nil),
        .init(title: "Plan the week", text: "Keel can lay your tasks into your free time for the whole week in one go.", icon: "calendar.day.timeline.left", tool: "calendarTools"),
        .init(title: "Sort loose tasks", text: "Captured a pile of things? Keel walks you through them one at a time: do, date, delegate or drop.", icon: "tray.and.arrow.down.fill", tool: "sort"),
    ]

    var body: some View {
        let today = ISO8601DateFormatter.dateOnly.string(from: Date())
        if !off, index < Self.tips.count {
            let tip = Self.tips[index]
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Did you know?", systemImage: "lightbulb.fill").font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.warmth)
                    Spacer()
                    Menu {
                        Button("Next tip", systemImage: "forward") { index += 1 }
                        Button("No more tips", systemImage: "xmark") { off = true }
                    } label: { Image(systemName: "ellipsis").foregroundStyle(DS.Palette.inkSoft) }
                }
                Label(tip.title, systemImage: tip.icon).font(DS.Font.headline)
                Text(tip.text).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                if let id = tip.tool, let t = HubCatalog.tool(id) {
                    NavigationLink { LazyView(t.dest()) } label: { Text("Show me").font(DS.Font.caption.weight(.semibold)) }
                }
            }
            .padding(DS.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { PremiumSurface(tint: DS.Palette.warmth) }
            .onAppear {
                // A new tip each new day.
                if lastDay.isEmpty { lastDay = today } else if lastDay != today { lastDay = today; index += 1 }
            }
        }
    }
}
