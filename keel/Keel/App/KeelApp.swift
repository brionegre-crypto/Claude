import SwiftUI
import SwiftData
import CoreSpotlight
import UserNotifications

@main
struct KeelApp: App {
    let container = KeelStore.container
    @Environment(\.scenePhase) private var scenePhase

    init() {
        SyncEngine.registerBackgroundTasks()
        UNUserNotificationCenter.current().delegate = NotificationHandler.shared
        TaskAlerts.registerCategories()
        WatchBridge.shared.activate()
        if !UserDefaults.standard.bool(forKey: Prefs.reviewReminderOff) { WeeklyReview.scheduleReminder() }
        if !UserDefaults.standard.bool(forKey: "dayReview.off") { DayReviewView.scheduleReminder() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(SyncEngine.shared)
                .environment(ShutdownManager.shared)
                .onOpenURL { url in
                    if url.scheme?.lowercased() == "mailto" {
                        MailRouter.shared.pending = ComposeDraft.mailto(url)
                    } else if AppRouter.shared.handle(url) {
                        // opened from a widget or Live Activity
                    } else {
                        OAuthManager.shared.handleRedirect(url)
                    }
                }
                .task {
                    // Task, focus, habit and promise alerts all need this once.
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                    SyncEngine.shared.configure(container: container)
                    MedEngine.scheduleAll(ctx: container.mainContext)
                    BreakReminders.schedule()
                    await SyncEngine.shared.syncAll()
                    SyncEngine.scheduleNextRefresh()
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                WidgetActions.applyPending(ctx: container.mainContext)   // taps on interactive widgets
                Task { await HealthHabits.check(ctx: container.mainContext) }
                Task { await KeelFocusFilter.syncCurrent() }
                LinkSaver.importShared(into: container.mainContext)     // links saved from Safari's share sheet
                LinkSaver.importSharedNotes(into: container.mainContext) // text/images shared from Notes, Messages, Photos…
            }
            if phase == .background {
                WidgetSync.update(container.mainContext)
                AppLock.shared.lockIfEnabled()
            }
        }
    }
}

/// One shared store for the app, Siri/App Intents and (later) widgets.
@MainActor enum KeelStore {
    static let container: ModelContainer = {
        let schema = Schema([
            MailAccount.self, EmailMessage.self, TaskItem.self, Note.self,
            Habit.self, HabitStack.self, HabitLog.self, FocusSession.self, Commitment.self, Goal.self, FollowUp.self, SavedLink.self, TimeEntry.self, IdealBlock.self, OdysseyPath.self, SenderRule.self, Person.self, CheckIn.self, TaskTemplate.self, NoteAttachment.self, Countdown.self, Project.self, Snippet.self, MailRule.self, ScheduledMail.self, Medication.self, MedDose.self, Subscription.self, Delivery.self, Reservation.self, TaskAttachment.self, SmartList.self,
        ])
        // Lives in the App Group so widgets / intents extensions can read it too.
        let config = ModelConfiguration(schema: schema, groupContainer: .identifier("group.com.briangreenejr.keel"))
        KeelBackup.applyPendingRestore(storeURL: config.url)       // finish a restore picked last session
        return try! ModelContainer(for: schema, configurations: config)
    }()
}

struct RootView: View {
    @State private var router = AppRouter.shared
    @State private var showCommandBar = false
    @State private var mailRouter = MailRouter.shared
    @AppStorage("onboarding.done") private var onboarded = false
    @AppStorage(Prefs.appearance) private var appearance = "system"
    @AppStorage("accent") private var accentName = "indigo"
    @State private var appLock = AppLock.shared
    @Environment(\.scenePhase) private var phase

    enum Tab { case today, inbox, calendar, tasks, notes }

    private func openTask(_ id: UUID) -> TaskItem? {
        try? KeelStore.container.mainContext.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first
    }
    private func openNote(_ id: UUID) -> Note? {
        try? KeelStore.container.mainContext.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })).first
    }

    var body: some View {
        TabView(selection: $router.tab) {
            TodayView().tabItem { Label("Today", systemImage: "sun.max") }.tag(Tab.today)
            InboxView().tabItem { Label("Inbox", systemImage: "tray") }.tag(Tab.inbox)
            CalendarView().tabItem { Label("Calendar", systemImage: "calendar") }.tag(Tab.calendar)
            TasksView().tabItem { Label("Tasks", systemImage: "checklist") }.tag(Tab.tasks)
            NotesView().tabItem { Label("Notes", systemImage: "note.text") }.tag(Tab.notes)
        }
        // Focus lives above the tab bar (like Music's mini-player): always one tap away, shows the live timer.
        .tabViewBottomAccessory { FocusAccessory { router.showFocus = true } }
        .overlay(alignment: .bottom) { UndoToast() }
        .sheet(isPresented: $router.showFocus) { NavigationStack { FocusView() } }
        .sheet(item: $mailRouter.pending) { ComposeView(draft: $0) }
        .sheet(isPresented: $router.showSearch) { NavigationStack { SearchView() } }
        .sheet(isPresented: $router.showPlan) { PlanRitualView() }
        .sheet(item: Binding(get: { router.openTaskId.flatMap { id in openTask(id) } }, set: { if $0 == nil { router.openTaskId = nil } })) { t in
            NavigationStack { TaskDetailView(task: t) }
        }
        .sheet(item: Binding(get: { router.openNoteId.flatMap { id in openNote(id) } }, set: { if $0 == nil { router.openNoteId = nil } })) { n in
            NavigationStack { NoteEditor(note: n) }
        }
        // Tapping a Keel result in iPhone search
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
            let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let uuid = UUID(uuidString: parts[1]) else { return }
            if parts[0] == "task" { router.openTaskId = uuid } else { router.openNoteId = uuid }
        }
        .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) { WelcomeTour() }
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .tint(Theme(rawValue: accentName)?.color ?? DS.Palette.accent)
        .id(accentName)          // redraw everything with the new accent
        // Superhuman-style universal command bar: ⌘K on a keyboard
        .overlay(alignment: .top) {
            if showCommandBar || router.showCapture {
                CommandBar(isPresented: Binding(get: { showCommandBar || router.showCapture },
                                                set: { if !$0 { showCommandBar = false; router.showCapture = false } }))
            }
        }
        .background(
            Button("") { showCommandBar.toggle() }
                .keyboardShortcut("k", modifiers: .command).hidden()
        )
        .overlay {
            if appLock.isLocked { LockScreen().transition(.opacity) }
            else if AppLock.isEnabled && phase != .active { PrivacyCover() }
        }
    }
}

/// The bar above the tabs: "Start focus" when idle; a live countdown while a session runs.
struct FocusAccessory: View {
    @Environment(ShutdownManager.self) private var shutdown
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: shutdown.active == nil ? "moon.zzz" : "moon.zzz.fill")
                    .foregroundStyle(DS.Palette.focus)
                    .symbolEffect(.pulse, isActive: shutdown.active != nil)
                if let end = shutdown.endsAt, end > Date() {
                    Text("Focusing").font(DS.Font.headline)
                    Spacer()
                    Text(timerInterval: Date()...end, countsDown: true)
                        .font(DS.Font.headline.monospacedDigit())
                        .foregroundStyle(DS.Palette.focus)
                } else {
                    Text(shutdown.active == nil ? "Start focus" : "Focus block done").font(DS.Font.headline)
                    Spacer()
                    Image(systemName: "chevron.up").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                }
            }
            .padding(.horizontal, DS.Space.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shutdown.active == nil ? "Start a focus session" : "Open focus session")
    }
}
