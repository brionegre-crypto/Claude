import SwiftUI
import SwiftData

@main
struct KeelApp: App {
    let container = KeelStore.container
    @Environment(\.scenePhase) private var scenePhase

    init() {
        SyncEngine.registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(SyncEngine.shared)
                .environment(ShutdownManager.shared)
                .onOpenURL { OAuthManager.shared.handleRedirect($0) }
                .task {
                    SyncEngine.shared.configure(container: container)
                    await SyncEngine.shared.syncAll()
                    SyncEngine.scheduleNextRefresh()
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await KeelFocusFilter.syncCurrent() } }
        }
    }
}

/// One shared store for the app, Siri/App Intents and (later) widgets.
@MainActor enum KeelStore {
    static let container: ModelContainer = {
        let schema = Schema([
            MailAccount.self, EmailMessage.self, TaskItem.self, Note.self,
            Habit.self, HabitStack.self, HabitLog.self, FocusSession.self, Commitment.self,
        ])
        // Lives in the App Group so widgets / intents extensions can read it too.
        let config = ModelConfiguration(schema: schema, groupContainer: .identifier("group.com.briangreenejr.keel"))
        return try! ModelContainer(for: schema, configurations: config)
    }()
}

struct RootView: View {
    @State private var tab: Tab = .today
    @State private var showCommandBar = false

    enum Tab { case today, inbox, tasks, notes, focus }

    var body: some View {
        TabView(selection: $tab) {
            TodayView().tabItem { Label("Today", systemImage: "sun.max") }.tag(Tab.today)
            InboxView().tabItem { Label("Inbox", systemImage: "tray") }.tag(Tab.inbox)
            TasksView().tabItem { Label("Tasks", systemImage: "checklist") }.tag(Tab.tasks)
            NotesView().tabItem { Label("Notes", systemImage: "note.text") }.tag(Tab.notes)
            NavigationStack { FocusView() }.tabItem { Label("Focus", systemImage: "moon.zzz") }.tag(Tab.focus)
        }
        // Superhuman-style universal command bar: pull down anywhere / ⌘K on iPad keyboard
        .overlay(alignment: .top) {
            if showCommandBar { CommandBar(isPresented: $showCommandBar) }
        }
        .background(
            Button("") { showCommandBar.toggle() }
                .keyboardShortcut("k", modifiers: .command).hidden()
        )
    }
}
