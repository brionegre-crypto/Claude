import SwiftUI

/// Which sections sit in the bottom tab bar, and in what order. Today is always first; up to five on iPhone.
/// Any tool from Today → ⊞ can be a tab (Habits, Journal, Focus room…). Sections you take out still open
/// from links, widgets and Siri, as a sheet.
@MainActor
enum TabBarConfig {
    static let key = "tabbar.items", revKey = "tabbar.rev"     // rev changes on every save so the tab bar redraws
    static let core = ["today", "inbox", "calendar", "tasks", "notes"]
    static let maxTabs = 5

    static var items: [String] {
        get {
            let saved = UserDefaults.standard.stringArray(forKey: key) ?? core
            var seen = Set<String>()
            var v = saved.filter { valid($0) && seen.insert($0).inserted }      // each section once
            if v.first != "today" { v.removeAll { $0 == "today" }; v.insert("today", at: 0) }
            return Array(v.prefix(maxTabs))
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            UserDefaults.standard.set(UserDefaults.standard.integer(forKey: revKey) + 1, forKey: revKey)
        }
    }

    static func valid(_ id: String) -> Bool {
        core.contains(id) || (id.hasPrefix("tool:") && HubCatalog.tool(String(id.dropFirst(5))) != nil)
    }

    static func value(_ id: String) -> RootView.Tab {
        switch id {
        case "today": .today; case "inbox": .inbox; case "calendar": .calendar; case "tasks": .tasks; case "notes": .notes
        default: .tool(String(id.dropFirst(5)))
        }
    }
    static func id(for tab: RootView.Tab) -> String? {
        switch tab {
        case .today: "today"; case .inbox: "inbox"; case .calendar: "calendar"; case .tasks: "tasks"; case .notes: "notes"
        case .tool(let t): "tool:" + t
        case .settings: nil
        }
    }

    static func title(_ id: String) -> String {
        switch id {
        case "today":
            switch PaletteCache.look { case .helm: "Helm"; case .logbook: "Log"; case .panel: "Bridge"; default: "Today" }
        case "calendar": PaletteCache.look == .chart ? "Chart" : "Calendar"
        case "inbox": "Inbox"; case "tasks": "Tasks"; case "notes": "Notes"
        default: HubCatalog.tool(String(id.dropFirst(5)))?.title ?? "Tool"
        }
    }
    static func icon(_ id: String) -> String {
        switch id {
        case "today":
            switch PaletteCache.look {
            case .chart: "map"; case .helm: "steeringwheel"; case .tide: "water.waves"; case .logbook: "book.closed"
            case .flags: "flag.fill"; case .lighthouse: "light.beacon.max"; case .panel: "gauge.with.needle"; default: "sun.max"
            }
        case "inbox": "tray"; case "calendar": "calendar"; case "tasks": "checklist"; case "notes": "note.text"
        default: HubCatalog.tool(String(id.dropFirst(5)))?.icon ?? "square.grid.2x2"
        }
    }

    /// A tab's screen is built the first time you open it, not at launch, and tabs you haven't opened
    /// don't redraw in the background while mail syncs or tasks change.
    static func content(_ id: String) -> some View {
        BuiltOnFirstVisit(tab: value(id)) { screen(id) }
    }

    @ViewBuilder
    static func screen(_ id: String) -> some View {
        switch id {
        case "today": HomeRoot()
        case "inbox": InboxView()
        case "calendar": CalendarView()
        case "tasks": TasksView()
        case "notes": NotesView()
        default:
            if let t = HubCatalog.tool(String(id.dropFirst(5))) {
                NavigationStack { t.dest().keelSettingsButton() }
            }
        }
    }
}

struct HiddenSection: Identifiable { let id: String }

/// A section that isn't in your tab bar, opened from a link, widget or shortcut.
struct HiddenSectionSheet: View {
    let sectionId: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        TabBarConfig.screen(sectionId)
            .overlay(alignment: .topTrailing) {
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2).symbolRenderingMode(.hierarchical) }
                    .padding(.top, 6).padding(.trailing, 16)
                    .accessibilityLabel("Close")
            }
    }
}

struct TabBarSettings: View {
    @State private var items = TabBarConfig.items

    private var available: [(id: String, title: String, icon: String)] {
        let core = TabBarConfig.core.map { ($0, TabBarConfig.title($0), TabBarConfig.icon($0)) }
        let tools = HubCatalog.everyTool.map { ("tool:" + $0.id, $0.title, $0.icon) }
        return (core + tools).filter { !items.contains($0.0) }.map { (id: $0.0, title: $0.1, icon: $0.2) }
    }

    var body: some View {
        List {
            Section {
                ForEach(items, id: \.self) { id in
                    Label(TabBarConfig.title(id), systemImage: TabBarConfig.icon(id))
                        .deleteDisabled(id == "today" || items.count <= 2)
                        .moveDisabled(id == "today")
                }
                .onMove { from, to in
                    items.move(fromOffsets: from, toOffset: to)
                    if items.first != "today" { items.removeAll { $0 == "today" }; items.insert("today", at: 0) }
                    save()
                }
                .onDelete { idx in items.remove(atOffsets: idx); save() }
            } header: { Text("In your tab bar (\(items.count) of \(TabBarConfig.maxTabs))") } footer: {
                Text("Today stays first. Drag to reorder, swipe to remove. Anything you remove still opens from links, widgets and Siri, and lives in Today → ⊞.")
            }
            Section("Add") {
                ForEach(available, id: \.id) { a in
                    Button { items.append(a.id); save(); Haptics.tap() } label: {
                        HStack { Label(a.title, systemImage: a.icon).foregroundStyle(DS.Palette.ink); Spacer(); Image(systemName: "plus.circle.fill").foregroundStyle(DS.Palette.accent) }
                    }
                    .disabled(items.count >= TabBarConfig.maxTabs)
                }
            }
            Section { Button("Restore the default tabs") { items = TabBarConfig.core; save() } }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Tab bar")
    }

    private func save() { TabBarConfig.items = items }
}

/// Holds a tab's screen back until the tab is first selected; after that it stays, so switching is instant.
struct BuiltOnFirstVisit<Content: View>: View {
    let tab: RootView.Tab
    @ViewBuilder var content: () -> Content
    @State private var built = false
    private var router = AppRouter.shared

    init(tab: RootView.Tab, @ViewBuilder content: @escaping () -> Content) {
        self.tab = tab
        self.content = content
    }

    var body: some View {
        if built || router.tab == tab {
            content().onAppear { built = true }
        } else {
            Color.clear
        }
    }
}


/// The first tab: the redesigned Home for the nautical themes, the classic Today for the classic looks.
struct HomeRoot: View {
    var body: some View {
        if PaletteCache.look.isNautical { HomeView() } else { TodayView() }
    }
}
