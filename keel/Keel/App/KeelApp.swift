import SwiftUI
import SwiftData
import CoreData
import CoreSpotlight
import UserNotifications

@main
struct KeelApp: App {
    @UIApplicationDelegateAdaptor(KeelAppDelegate.self) private var appDelegate
    let container = KeelStore.container
    @Environment(\.scenePhase) private var scenePhase

    init() {
        SyncEngine.registerBackgroundTasks()
        UNUserNotificationCenter.current().delegate = NotificationHandler.shared
        TaskAlerts.registerCategories()
        WatchBridge.shared.activate()
        KeelDiagnostics.shared.start()           // crash & hang reports (kept on device; shared only if you turn it on)
        if !UserDefaults.standard.bool(forKey: Prefs.reviewReminderOff) { WeeklyReview.scheduleReminder() }
        if !UserDefaults.standard.bool(forKey: "dayReview.off") { DayReviewView.scheduleReminder() }
        Journal.scheduleReminder()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modifier(KeelTextSizeModifier())
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
                    if TaskAlarms.globalOn { _ = await TaskAlarms.authorize() }   // asks once for full-screen task alarms
                    BreakReminders.schedule()
                    await SyncEngine.shared.syncAll()
                    SyncEngine.scheduleNextRefresh()
                }
        }
        .modelContainer(container)
        .commands { KeelCommands() }          // menu bar on Mac (and keyboard shortcuts on iPad)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                WidgetActions.applyPending(ctx: container.mainContext)   // taps on interactive widgets
                Task { await HealthHabits.check(ctx: container.mainContext) }
                Task { await KeelFocusFilter.syncCurrent() }
                LinkSaver.importShared(into: container.mainContext)     // links saved from Safari's share sheet
                LinkSaver.importSharedNotes(into: container.mainContext) // text/images shared from Notes, Messages, Photos…
                MeetingAutopilot.syncActivity()                         // Lock Screen timer for a meeting in progress
                WeeklyDigest.makeIfDue(ctx: container.mainContext)      // Sunday evening: last week on one page
                BrainIndex.shared.refresh(ctx: container.mainContext)   // meaning index for related pages (only what changed)
                BrainBackup.backupIfDue(ctx: container.mainContext)     // a daily safety copy
                NoteTrash.purgeOld()
            }
            if phase == .background {
                WidgetSync.updateNow(container.mainContext)
                if MarkdownMirror.isOn { MarkdownMirror.sync(ctx: container.mainContext) }   // Markdown copy of changed pages
                AppLock.shared.lockIfEnabled()
            }
        }

        // Mac and iPad: pages, emails and the Quick window in their own windows.
        WindowGroup("Page", id: "note", for: UUID.self) { $id in
            NoteWindow(id: id)
                .modifier(KeelTextSizeModifier())
                .environment(SyncEngine.shared)
                .environment(ShutdownManager.shared)
        }
        .modelContainer(container)
        WindowGroup("Email", id: "mail", for: String.self) { $id in
            EmailWindow(id: id)
                .modifier(KeelTextSizeModifier())
                .environment(SyncEngine.shared)
                .environment(ShutdownManager.shared)
        }
        .modelContainer(container)
        WindowGroup("Quick", id: "quick") {
            QuickWindowView()
                .modifier(KeelTextSizeModifier())
                .environment(SyncEngine.shared)
                .environment(ShutdownManager.shared)
        }
        .modelContainer(container)
    }
}

/// Keel's data. Two stores in the App Group:
///  • default.store: your own content (tasks, notes, habits, goals, meds, food…). With iCloud sync on, it syncs
///    through your private iCloud database, so every iPhone, iPad and Mac signed in to your Apple Account matches.
///  • mail.store: the mail cache and things scanned from mail (bills, trips, promises). Each device builds its own
///    from your mail accounts, so nothing is scanned twice and iCloud isn't filled with email.
@MainActor enum KeelStore {
    static let cloudID = "iCloud.com.briangreenejr.keel"
    static let syncKey = "icloud.sync"                 // turned on when you sign in; takes effect next launch
    static let splitKey = "store.split.v1"
    static var syncWanted: Bool { UserDefaults.standard.bool(forKey: syncKey) }
    /// What actually happened at launch: "on", "off", or why sync couldn't start.
    static private(set) var syncState = "off"

    static let syncedTypes: [any PersistentModel.Type] = [
        TaskItem.self, Note.self, NoteAttachment.self, Habit.self, HabitStack.self, HabitLog.self, FocusSession.self, Goal.self,
        SavedLink.self, TimeEntry.self, IdealBlock.self, OdysseyPath.self, Person.self, CheckIn.self, TaskTemplate.self, Countdown.self,
        Project.self, Snippet.self, MailRule.self, Medication.self, MedDose.self, TaskAttachment.self, SmartList.self, FoodProduct.self, FoodEntry.self,
    ]
    static let localTypes: [any PersistentModel.Type] = [
        MailAccount.self, EmailMessage.self, Commitment.self, FollowUp.self, SenderRule.self, ScheduledMail.self, Subscription.self,
        Delivery.self, Reservation.self, Suggestion.self, SenderScore.self,
    ]

    static let container: ModelContainer = {
        let all = Schema(syncedTypes + localTypes)
        // Lives in the App Group so widgets / intents extensions can read it too.
        let group = ModelConfiguration.GroupContainer.identifier("group.com.briangreenejr.keel")
        let single = ModelConfiguration(schema: all, groupContainer: group, cloudKitDatabase: .none)
        KeelBackup.applyPendingRestore(storeURL: single.url)       // finish a restore picked last session

        let mailURL = single.url.deletingLastPathComponent().appendingPathComponent("mail.store")
        // First launch with two stores: copy today's store so the mail side keeps your accounts and cache.
        if !UserDefaults.standard.bool(forKey: splitKey) {
            copyStore(from: single.url, to: mailURL)
        }
        // A copied store keeps the original's identity; two stores with the same ID get mixed up
        // ("Failed to find entity for this object in the schema"). Give the mail store its own.
        giveOwnIdentity(mailURL, unlike: single.url)
        let wantCloud = syncWanted
        do {
            let content = ModelConfiguration("Content", schema: Schema(syncedTypes), url: single.url,
                                             cloudKitDatabase: wantCloud ? .private(cloudID) : .none)
            let mail = ModelConfiguration("Mail", schema: Schema(localTypes), url: mailURL, cloudKitDatabase: .none)
            let c = try ModelContainer(for: all, configurations: content, mail)
            UserDefaults.standard.set(true, forKey: splitKey)
            syncState = wantCloud ? "on" : "off"
            return c
        } catch {
            syncState = "Couldn't start iCloud sync: \(error.localizedDescription)"
            print("KeelStore:", error)
            if wantCloud {
                // Try again without iCloud so Keel still opens with all your data.
                let content = ModelConfiguration("Content", schema: Schema(syncedTypes), url: single.url, cloudKitDatabase: .none)
                let mail = ModelConfiguration("Mail", schema: Schema(localTypes), url: mailURL, cloudKitDatabase: .none)
                if let c = try? ModelContainer(for: all, configurations: content, mail) {
                    UserDefaults.standard.set(true, forKey: splitKey)
                    return c
                }
            }
            if let c = try? ModelContainer(for: all, configurations: single) { return c }
            // Never crash on launch: open an empty, temporary store and show what went wrong.
            loadError = "Keel couldn't open your data (\(error.localizedDescription)). Nothing has been deleted. Send this message to support."
            return try! ModelContainer(for: all, configurations: ModelConfiguration(schema: all, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        }
    }()

    /// Shown at the top of the app if the data couldn't be opened, instead of crashing.
    static private(set) var loadError: String?

    private static func giveOwnIdentity(_ url: URL, unlike other: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path), fm.fileExists(atPath: other.path),
              var meta = try? NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: url, options: nil),
              let otherMeta = try? NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: other, options: nil),
              let id = meta[NSStoreUUIDKey] as? String, id == otherMeta[NSStoreUUIDKey] as? String else { return }
        meta[NSStoreUUIDKey] = UUID().uuidString
        try? NSPersistentStoreCoordinator.setMetadata(meta, forPersistentStoreOfType: NSSQLiteStoreType, at: url, options: nil)
    }

    /// Copies a SQLite store and its side files (-wal, -shm) before either is opened.
    private static func copyStore(from: URL, to: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) else { return }
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: from.path + suffix), dst = URL(fileURLWithPath: to.path + suffix)
            if fm.fileExists(atPath: src.path) { try? fm.copyItem(at: src, to: dst) }
        }
    }
}

struct RootView: View {
    @State private var router = AppRouter.shared
    @State private var showCommandBar = false
    @State private var mailRouter = MailRouter.shared
    @AppStorage("onboarding.done") private var onboarded = false
    @AppStorage(Prefs.appearance) private var appearance = "system"
    @AppStorage("accent") private var accentName = "indigo"
    @AppStorage(KeelLook.key) private var lookRaw = KeelLook.standard.rawValue
    @AppStorage(KeelLook.fontKey) private var fontRaw = KeelFontStyle.system.rawValue
    @State private var appLock = AppLock.shared
    @State private var savePoints = SavePointCenter.shared
    @Environment(\.scenePhase) private var phase

    enum Tab: Hashable { case today, inbox, calendar, tasks, notes, settings, tool(String) }
    @AppStorage(TabBarConfig.revKey) private var tabBarRev = 0
    @State private var hiddenSection: HiddenSection?

    private func openTask(_ id: UUID) -> TaskItem? {
        try? KeelStore.container.mainContext.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first
    }
    private func openNote(_ id: UUID) -> Note? {
        try? KeelStore.container.mainContext.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })).first
    }

    private var tabBarItems: [String] { _ = tabBarRev; return TabBarConfig.items }
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Only where there's a sidebar (Mac, and iPad at full width). Never on iPhone.
    private var showsSidebarSettings: Bool { UIDevice.current.userInterfaceIdiom != .phone && sizeClass == .regular }

    var body: some View {
        TabView(selection: $router.tab) {
            // Your tab bar (Settings → Look & Feel → Tab bar).
            ForEach(tabBarItems, id: \.self) { id in
                SwiftUI.Tab(TabBarConfig.title(id), systemImage: TabBarConfig.icon(id), value: TabBarConfig.value(id)) { TabBarConfig.content(id) }
            }
            // Mac and iPad: Settings sits at the bottom of the sidebar. iPhone uses the gear on each tab.
            // Left out of the iPhone tab bar entirely: a sixth tab pushes Notes behind "More".
            if showsSidebarSettings {
                SwiftUI.Tab("Settings", systemImage: "gearshape", value: Tab.settings) { AccountsView() }
                    .tabPlacement(.sidebarOnly)
            }
        }
        .onChange(of: showsSidebarSettings) { _, shown in if !shown && router.tab == .settings { router.tab = .today } }
        // A section you took out of the tab bar still opens (from a link, widget or ⌘-shortcut), as a sheet.
        .onChange(of: router.tab) { old, new in
            guard let id = TabBarConfig.id(for: new), !tabBarItems.contains(id) else { return }
            router.tab = tabBarItems.contains(TabBarConfig.id(for: old) ?? "") ? old : .today
            hiddenSection = HiddenSection(id: id)
        }
        .sheet(item: $hiddenSection) { HiddenSectionSheet(sectionId: $0.id) }
        .tabViewStyle(.sidebarAdaptable)      // tabs on iPhone; a sidebar on Mac and iPad
        // Focus lives above the tab bar (like Music's mini-player): always one tap away, shows the live timer.
        .tabViewBottomAccessory { FocusAccessory { router.showFocus = true } }
        .overlay(alignment: .bottom) { UndoToast() }
        .safeAreaInset(edge: .top) {
            if let err = KeelStore.loadError {
                Text(err).font(DS.Font.caption).foregroundStyle(.white).padding(10).frame(maxWidth: .infinity)
                    .background(.red.gradient).textSelection(.enabled)
            }
        }
        .overlay(alignment: .top) {
            if let p = savePoints.showing {
                SavePointBanner(point: p, resume: {
                    withAnimation(DS.spring) { savePoints.showing = nil }
                    SavePoints.resume(p, ctx: KeelStore.container.mainContext)
                }, dismiss: {
                    withAnimation(DS.spring) { savePoints.showing = nil }
                })
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 4)
            }
        }
        .onChange(of: phase) { _, p in
            if p == .background { savePoints.showing = nil; SavePoints.didEnterBackground() }
            if p == .active, let sp = SavePoints.pendingResume() {
                UserDefaults.standard.removeObject(forKey: SavePoints.awayKey)
                withAnimation(DS.spring) { savePoints.showing = sp }
            }
        }
        .modifier(RouterSheets(router: router, mailRouter: mailRouter))
        .modifier(OpenItemSheets(router: router))
        .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) { OnboardingFlow() }
        .modifier(WhatsNewModifier())
        .preferredColorScheme(KeelLook(rawValue: lookRaw)?.scheme ?? (appearance == "light" ? .light : appearance == "dark" ? .dark : nil))
        .fontDesign(KeelFontStyle(rawValue: fontRaw)?.design ?? .default)
        .tint(Theme(rawValue: accentName)?.color ?? DS.Palette.accent)
        .id(accentName + lookRaw)          // redraw everything with the new accent
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

/// Every screen the app can open from anywhere (widgets, Siri, shortcuts, the menu bar), kept out of RootView's
/// body so the compiler can check it quickly.
private struct RouterSheets: ViewModifier {
    @Bindable var router: AppRouter
    @Bindable var mailRouter: MailRouter

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $router.showFocus) { NavigationStack { FocusView() } }
            .sheet(item: $mailRouter.pending) { ComposeView(draft: $0) }
            .sheet(isPresented: $router.showSearch) { NavigationStack { SearchView() } }
            .sheet(isPresented: $router.showSettings) { AccountsView() }
            .sheet(isPresented: $router.showPlan) { PlanRitualView() }
            .modifier(MoreRouterSheets(router: router))
    }
}

/// A task or page opened from a widget, Spotlight or the menu bar.
private struct OpenItemSheets: ViewModifier {
    @Bindable var router: AppRouter

    private func openTask(_ id: UUID) -> TaskItem? {
        try? KeelStore.container.mainContext.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first
    }
    private func openNote(_ id: UUID) -> Note? {
        try? KeelStore.container.mainContext.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })).first
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(get: { router.openTaskId.flatMap { id in openTask(id) } }, set: { if $0 == nil { router.openTaskId = nil } })) { t in
                NavigationStack { TaskDetailView(task: t) }
            }
            .sheet(item: Binding(get: { router.openNoteId.flatMap { id in openNote(id) } }, set: { if $0 == nil { router.openNoteId = nil } })) { n in
                NavigationStack { NoteOrCanvas(note: n) }
            }
            // Tapping a Keel result in iPhone search
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
                let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2, let uuid = UUID(uuidString: parts[1]) else { return }
                if parts[0] == "task" { router.openTaskId = uuid } else { router.openNoteId = uuid }
            }
    }
}

private struct MoreRouterSheets: ViewModifier {
    @Bindable var router: AppRouter

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $router.showAutopilot) { NavigationStack { AutopilotView() } }
            .sheet(isPresented: $router.showRecorder) { NavigationStack { MeetingRecorderView(autoStart: true) } }
            .sheet(isPresented: $router.showReview) { NavigationStack { WeeklyReviewView() } }
            .sheet(isPresented: $router.showMoney) { NavigationStack { SubscriptionsView() } }
            .sheet(isPresented: $router.showLeaving) { LeavingChecklistView() }
            .sheet(isPresented: $router.showJournal) { JournalEntryView() }
            .sheet(item: $router.openTool) { r in ToolSheet(id: r.id) }
            .sheet(isPresented: $router.showQuickOpen) { QuickOpenView() }
            .sheet(isPresented: $router.showShortcuts) { KeyboardShortcutsView() }
            .sheet(isPresented: $router.showVoice) { VoiceNoteView() }
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

/// Menu bar commands and keyboard shortcuts (Mac, and iPad with a keyboard).
struct KeelCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") { AppRouter.shared.showCapture = true }
                .keyboardShortcut("n")
            Button("New Note") { KeelCommands.newNote() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Record a Meeting") { AppRouter.shared.showRecorder = true }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Open Page…") { AppRouter.shared.showQuickOpen = true }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { AppRouter.shared.showShortcuts = true }.keyboardShortcut("/")
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { AppRouter.shared.showSettings = true }.keyboardShortcut(",")
        }
        CommandMenu("Go") {
            Button("Today") { AppRouter.shared.tab = .today }.keyboardShortcut("1")
            Button("Inbox") { AppRouter.shared.tab = .inbox }.keyboardShortcut("2")
            Button("Calendar") { AppRouter.shared.tab = .calendar }.keyboardShortcut("3")
            Button("Tasks") { AppRouter.shared.tab = .tasks }.keyboardShortcut("4")
            Button("Notes") { AppRouter.shared.tab = .notes }.keyboardShortcut("5")
            Divider()
            Button("Search Everything") { AppRouter.shared.showSearch = true }.keyboardShortcut("f")
            Button("Start Focus") { AppRouter.shared.showFocus = true }.keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Plan My Day") { AppRouter.shared.showPlan = true }.keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Journal") { AppRouter.shared.showJournal = true }.keyboardShortcut("j", modifiers: [.command, .shift])
        }
    }

    @MainActor static func newNote() {
        let n = Note(title: "")
        KeelStore.container.mainContext.insert(n)
        try? KeelStore.container.mainContext.save()
        AppRouter.shared.tab = .notes
        AppRouter.shared.openNoteId = n.id
    }
}

// MARK: - Haptic Touch on the app icon

/// Press and hold the Keel icon: New Task, New Note, Start Focus, Record a Meeting, Search.
final class KeelAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem { KeelQuickActions.perform(item.type, delay: 0.6) }   // Keel wasn't running yet
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = KeelSceneDelegate.self
        return config
    }
}

final class KeelSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        KeelQuickActions.perform(shortcutItem.type, delay: 0.1)
        completionHandler(true)
    }
}

enum KeelQuickActions {
    static func perform(_ type: String, delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                let r = AppRouter.shared
                switch type.components(separatedBy: ".").last {
                case "capture": r.showCapture = true
                case "note": KeelCommands.newNote()
                case "focus": r.showFocus = true
                case "record": r.showRecorder = true
                case "search": r.showSearch = true
                default: break
                }
            }
        }
    }
}

/// The gear at the top of every tab: Settings is always one tap away, in the same place.
struct SettingsButton: ViewModifier {
    @State private var account = KeelAccount.shared
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { AppRouter.shared.showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .overlay(alignment: .topTrailing) {
                            if !account.isSignedIn { Circle().fill(.red).frame(width: 7, height: 7).offset(x: 3, y: -2) }   // sign-in reminder
                        }
                }
                .accessibilityLabel(account.isSignedIn ? "Settings" : "Settings. Sign in to sync your devices")
            }
        }
    }
}

extension View {
    func keelSettingsButton() -> some View { modifier(SettingsButton()) }
}
