import SwiftUI
import SwiftData
import StoreKit
import AppIntents
import UserNotifications

// Settings, laid out like iPhone Settings: icon tiles, grouped sections, one page per area.
// (Kept the type name AccountsView so existing entry points keep working.)

/// iOS-Settings-style colored icon tile.
struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color.gradient, in: .rect(cornerRadius: 7))
    }
}

struct SettingsRow<Destination: View>: View {
    let title: String
    let symbol: String
    let color: Color
    var value: String? = nil
    @ViewBuilder var destination: Destination
    var body: some View {
        NavigationLink { destination } label: {
            HStack(spacing: 12) {
                SettingsIcon(symbol: symbol, color: color)
                Text(title)
                Spacer()
                if let value { Text(value).foregroundStyle(.secondary) }
            }
        }
    }
}

enum Prefs {
    // Appearance
    static let appearance = "appearance"                 // system | light | dark
    static let hapticsOff = "haptics.off"
    static let calm = "calm.on"                         // ADHD calm mode: fewer cards, no counts, no red
    // Mail
    static let undoSeconds = "mail.undoSeconds"         // 0 = send immediately
    static let loadImages = "mail.loadImages"
    static let signature = "mail.signature"
    static let followUpDefault = "mail.followUpDefault" // 0 = off
    // Tasks
    static let defaultList = "tasks.defaultList"
    static let defaultAlert = "tasks.defaultAlert"      // -1 = none, 0 = at time, n = minutes before
    // Focus
    static let focusMinutes = "focus.defaultMinutes"
    static let hyperfocusCheck = "focus.hyperfocusOff"
    // Notifications
    static let reviewReminderOff = "review.reminderOff"
}

struct AccountsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [MailAccount]
    @AppStorage(Prefs.appearance) private var appearance = "system"
    @AppStorage("ai.privateMode") private var privateMode = false
    @State private var showPaywall = false
    @State private var showTour = false
    @State private var query = ""
    @Environment(\.isPresented) private var isPresented

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                if !query.isEmpty {
                    SettingsSearchResults(query: query)
                } else {
                Section {
                    NavigationLink { AccountView() } label: { AccountRow() }
                }
                Section {
                    SettingsRow(title: "Mail Accounts", symbol: "envelope.fill", color: .blue, value: accounts.isEmpty ? "None" : "\(accounts.count)") { MailAccountsSettings() }
                    SettingsRow(title: "Calendars", symbol: "calendar", color: .red) { CalendarSettings() }
                    SettingsRow(title: "Reminders", symbol: "checklist", color: .orange) { RemindersSettings() }
                    SettingsRow(title: "Connected Apps", symbol: "app.connected.to.app.below.fill", color: .indigo) { ConnectedAppsView() }
                } header: { Text("Accounts & Connections") }

                Section {
                    SettingsRow(title: "Notifications", symbol: "bell.badge.fill", color: .red) { NotificationSettings() }
                    SettingsRow(title: "Mail", symbol: "paperplane.fill", color: .blue) { MailSettings() }
                    SettingsRow(title: "Tasks", symbol: "checkmark.circle.fill", color: .green) { TaskSettings() }
                    SettingsRow(title: "Focus", symbol: "moon.fill", color: .indigo) { FocusSettings() }
                    SettingsRow(title: "Medications", symbol: "pills.fill", color: .mint) { MedsView() }
                    SettingsRow(title: "Health & Nutrition", symbol: "fork.knife", color: .green) { NutritionSettingsView() }
                    SettingsRow(title: "Email to Keel", symbol: "envelope.arrow.triangle.branch.fill", color: .blue) { EmailToKeelView() }
                    SettingsRow(title: "Automations", symbol: "bolt.horizontal.fill", color: .orange) { AutomationsView() }
                } header: { Text("Features") }

                Section {
                    SettingsRow(title: "Appearance", symbol: "textformat.size", color: .gray, value: appearance.capitalized) { AppearanceSettings() }
                    SettingsRow(title: "Siri & Shortcuts", symbol: "waveform", color: .purple) { SiriSettings() }
                    SettingsRow(title: "AI & Privacy", symbol: "hand.raised.fill", color: .blue, value: privateMode ? "Private" : nil) { PrivacySettings() }
                } header: { Text("Look & Feel, AI") }

                Section {
                    SettingsRow(title: "Help: How do I…", symbol: "questionmark.bubble.fill", color: .indigo) { HelpCenterView() }
                    SettingsRow(title: "How Keel Works", symbol: "questionmark", color: .teal) { FeatureGuideView() }
                    Button { showTour = true } label: {
                        HStack(spacing: 12) { SettingsIcon(symbol: "play.fill", color: .teal); Text("Replay Welcome Tour").foregroundStyle(.primary) }
                    }
                    if Entitlements.paywallEnabled {
                        Button { showPaywall = true } label: {
                            HStack(spacing: 12) { SettingsIcon(symbol: "star.fill", color: .yellow); Text("Keel Pro").foregroundStyle(.primary) }
                        }
                    }
                } header: { Text("Help") }

                Section {
                    SettingsRow(title: "Data & Storage", symbol: "externaldrive.fill", color: .gray) { DataSettings() }
                    LabeledContent("Version", value: version)
                } header: { Text("Data") } footer: {
                    Text("When you sign in, your content syncs through your own private iCloud. Email stays between this device and your mail provider, and calendars and Reminders stay in your own accounts.")
                }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Settings")
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { if isPresented { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .fullScreenCover(isPresented: $showTour) { WelcomeTour() }
        }
    }
}

// MARK: - Mail accounts

struct MailAccountsSettings: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \MailAccount.address) private var accounts: [MailAccount]
    @State private var error: String?
    @State private var imapKind: MailProviderKind?
    @State private var working = false

    var body: some View {
        List {
            Section {
                ForEach(accounts) { a in
                    NavigationLink { MailAccountDetail(account: a) } label: {
                        HStack(spacing: 12) {
                            SettingsIcon(symbol: "envelope.fill", color: Color(hex: a.colorHex))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.address)
                                Text(a.provider.displayName).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: { Text("Accounts") } footer: {
                if accounts.isEmpty { Text("Add an account to bring your email into Keel.") }
            }
            Section("Add Account") {
                Button { Task { await connect(.gmail) } } label: { Label("Gmail", systemImage: "envelope") }
                Button { Task { await connect(.outlook) } } label: { Label("Outlook / Microsoft 365", systemImage: "envelope") }
                Button { imapKind = .icloud } label: { Label("iCloud Mail", systemImage: "icloud") }
                Button { imapKind = .yahoo } label: { Label("Yahoo Mail", systemImage: "envelope") }
                Button { imapKind = .aol } label: { Label("AOL Mail", systemImage: "envelope") }
                Button { imapKind = .imap } label: { Label("Other (IMAP)", systemImage: "server.rack") }
            }
            if working { Section { ProgressView("Signing in…") } }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("Mail Accounts")
        .sheet(item: $imapKind) { ICloudSetupView(kind: $0) }
    }

    private func connect(_ kind: MailProviderKind) async {
        working = true; error = nil
        defer { working = false }
        do {
            let cfg = kind == .gmail ? OAuthManager.google : OAuthManager.microsoft
            let tokens = try await OAuthManager.shared.signIn(cfg)
            let email = try await fetchAddress(kind, token: tokens.access)
            let a = MailAccount(provider: kind, address: email, displayName: email,
                                colorHex: kind == .gmail ? "#EA4335" : "#0A64D6")
            KeychainStore.saveTokens(tokens, account: a.id)
            ctx.insert(a)
            Haptics.success()
            await SyncEngine.shared.syncAll()
        } catch { self.error = error.localizedDescription }
    }

    private func fetchAddress(_ kind: MailProviderKind, token: String) async throws -> String {
        var req = URLRequest(url: URL(string: kind == .gmail ? "https://gmail.googleapis.com/gmail/v1/users/me/profile" : "https://graph.microsoft.com/v1.0/me")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return (j["emailAddress"] ?? j["mail"] ?? j["userPrincipalName"]) as? String ?? "unknown"
    }
}

struct MailAccountDetail: View {
    @Bindable var account: MailAccount
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemove = false
    @State private var syncing = false

    var body: some View {
        List {
            Section {
                LabeledContent("Address", value: account.address)
                LabeledContent("Type", value: account.provider.displayName)
                LabeledContent("Last synced", value: account.lastSyncedAt?.formatted(.relative(presentation: .named)) ?? "Never")
                Toggle("Sync this account", isOn: $account.isEnabled)
            }
            Section {
                TextField("Uses your shared signature", text: Binding(get: { account.signature ?? "" },
                                                                     set: { account.signature = $0.isEmpty ? nil : $0 }), axis: .vertical)
                    .lineLimit(2...6)
            } header: { Text("Signature") } footer: { Text("Added to emails you send from \(account.address). Leave empty to use the signature in Settings → Mail.") }
            Section {
                NavigationLink { AliasesView(account: account) } label: {
                    LabeledContent("Send As", value: MailAliases.list(account.id).isEmpty ? "None" : "\(MailAliases.list(account.id).count)")
                }
            } footer: { Text("Other addresses you can send from with this account. Replies go out from the address the email was sent to.") }
            Section {
                Button(syncing ? "Syncing…" : "Sync Now") {
                    Task { syncing = true; await SyncEngine.shared.syncAll(); syncing = false }
                }
                .disabled(syncing)
                if let err = SyncEngine.shared.lastError, err.contains(account.address) {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            } footer: {
                if account.provider == .gmail {
                    Text("While Keel's Google project is in testing, Google asks you to sign in again every 7 days. Remove and re-add the account if sync stops.")
                }
            }
            Section {
                Button("Remove Account", role: .destructive) { confirmRemove = true }
            } footer: {
                Text("Removes this account and its email from Keel. Nothing is deleted from your mailbox.")
            }
        }
        .navigationTitle(account.provider.displayName)
        .confirmationDialog("Remove \(account.address)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove Account", role: .destructive) { remove() }
        }
    }

    private func remove() {
        let id = account.id
        let mail = (try? ctx.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { $0.accountId == id }))) ?? []
        mail.forEach(ctx.delete)
        KeychainStore.delete("tokens.\(id)")
        KeychainStore.delete("imap.\(id)")
        ctx.delete(account)
        try? ctx.save()
        dismiss()
    }
}

// MARK: - Calendars & Reminders

struct CalendarSettings: View {
    @AppStorage("calendar.hidden") private var hiddenRaw = ""
    @AppStorage("calendar.showTasks") private var showTasks = true
    @AppStorage("calendar.mode") private var mode = CalendarMode.week.rawValue
    @AppStorage("leaveBy.on") private var leaveBy = true
    @AppStorage("prep.on") private var prepOn = true
    @AppStorage(TransitionAlerts.onKey) private var transitions = true
    @AppStorage(TransitionAlerts.minutesKey) private var transitionMinutes = 5
    @AppStorage("leaveBy.transport") private var transport = "driving"
    @AppStorage("meeting.autopilot.on") private var autopilot = true
    @AppStorage("meeting.autopilot.lead") private var autopilotLead = 1
    @AppStorage("meeting.autopilot.live") private var autopilotLive = true
    private var hidden: Set<String> { Set(hiddenRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        List {
            Section {
                Picker("Default View", selection: $mode) { ForEach(CalendarMode.allCases) { Text($0.rawValue).tag($0.rawValue) } }
                Toggle("Show Tasks on Calendar", isOn: $showTasks)
            }
            Section {
                Toggle("Transition Warnings", isOn: $transitions)
                if transitions {
                    Picker("Warn Me", selection: $transitionMinutes) {
                        Text("5 minutes before").tag(5); Text("10 minutes before").tag(10); Text("15 minutes before").tag(15)
                    }
                }
                Toggle("Meeting Prep Alerts", isOn: $prepOn)
                Toggle("Time to Leave Alerts", isOn: $leaveBy)
                if leaveBy {
                    Picker("Travel By", selection: $transport) {
                        Text("Car").tag("driving"); Text("Transit").tag("transit"); Text("Walking").tag("walking")
                    }
                }
            } footer: { Text("For events with an address, Keel checks Apple Maps travel time from where you are and alerts you when it's time to leave, with a 10-minute buffer. Needs location access. Transition warnings give you a heads-up before every event so switching gears isn't a jolt. Meeting prep alerts arrive 10 minutes before meetings that have related emails, notes, tasks or promises.") }
            Section {
                Toggle("Meeting Autopilot", isOn: $autopilot)
                if autopilot {
                    Picker("Nudge Me", selection: $autopilotLead) {
                        Text("When it starts").tag(0); Text("1 minute before").tag(1)
                        Text("2 minutes before").tag(2); Text("5 minutes before").tag(5)
                    }
                    Toggle("Lock Screen Timer", isOn: $autopilotLive)
                }
            } header: { Text("Meetings") } footer: {
                Text("For meetings with other people or a video link, Keel nudges you with Join and Record notes buttons. The Lock Screen timer shows how long is left, with one-tap Join. Works with Zoom, Google Meet, Teams, Webex, FaceTime and more.")
            }
            .onChange(of: autopilot) { Task { await MeetingAutopilot.refresh() }; if !autopilot { MeetingAutopilot.endAll() } }
            .onChange(of: autopilotLead) { Task { await MeetingAutopilot.refresh() } }
            .onChange(of: autopilotLive) { if !autopilotLive { MeetingAutopilot.endAll() } }
            ForEach(CalendarService.shared.calendarsBySource, id: \.source) { group in
                Section(group.source) {
                    ForEach(group.calendars, id: \.calendarIdentifier) { c in
                        Toggle(isOn: Binding(
                            get: { !hidden.contains(c.calendarIdentifier) },
                            set: { show in
                                var h = hidden
                                if show { h.remove(c.calendarIdentifier) } else { h.insert(c.calendarIdentifier) }
                                hiddenRaw = h.sorted().joined(separator: ",")
                            })) {
                            HStack { Circle().fill(Color(cgColor: c.cgColor)).frame(width: 12, height: 12); Text(c.title) }
                        }
                    }
                }
            }
            Section {
                Button("Add Calendar Accounts…") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            } footer: {
                Text("Keel shows every calendar on this iPhone, including iCloud, Google, Outlook and Exchange, and edits sync both ways. Add accounts in the iPhone Settings app under Apps → Calendar → Calendar Accounts.")
            }
        }
        .navigationTitle("Calendars")
    }
}

struct RemindersSettings: View {
    @AppStorage(Prefs.defaultList) private var defaultList = "Inbox"
    @State private var syncing = false

    var body: some View {
        List {
            Section {
                Picker("Default List", selection: $defaultList) {
                    Text("Inbox").tag("Inbox")
                    ForEach(CalendarService.shared.reminderLists, id: \.calendarIdentifier) { Text($0.title).tag($0.title) }
                }
            } footer: { Text("New tasks go here unless you add one with ~ListName.") }
            Section {
                ForEach(CalendarService.shared.reminderLists, id: \.calendarIdentifier) { l in
                    HStack { Circle().fill(Color(cgColor: l.cgColor)).frame(width: 12, height: 12); Text(l.title) }
                }
            } header: { Text("Synced Lists") } footer: {
                Text("Every Apple Reminders list syncs both ways, live while Keel is open. Completing, editing or deleting in either app updates the other.")
            }
            Section {
                Button(syncing ? "Syncing…" : "Sync Now") {
                    Task { syncing = true; await SyncEngine.shared.syncRemindersOnly(); syncing = false }
                }
                .disabled(syncing)
            }
        }
        .navigationTitle("Reminders")
    }
}

// MARK: - Notifications

struct NotificationSettings: View {
    @AppStorage(Prefs.defaultAlert) private var defaultAlert = 0
    @AppStorage(Prefs.reviewReminderOff) private var reviewOff = false
    @AppStorage(Prefs.hyperfocusCheck) private var hyperfocusOff = false
    @AppStorage(Briefing.onKey) private var briefingOn = true
    @AppStorage(Briefing.minuteKey) private var briefingMinute = 450
    @AppStorage(Journal.reminderOnKey) private var journalOn = false
    @AppStorage(Journal.reminderTimeKey) private var journalMinute = 21 * 60
    @AppStorage(KeelAlerts.timeSensitiveKey) private var timeSensitive = true
    @State private var timeSensitiveBlocked = false

    var body: some View {
        List {
            Section { NotificationStatusRow() } footer: {
                Text("Keel's alerts come from this iPhone: task reminders, focus timers, habit nudges, promises and follow-ups.")
            }
            Section {
                Toggle("Morning Briefing", isOn: $briefingOn)
                if briefingOn {
                    DatePicker("Time", selection: Binding(
                        get: { Calendar.current.date(bySettingHour: briefingMinute / 60, minute: briefingMinute % 60, second: 0, of: Date())! },
                        set: { briefingMinute = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) }),
                        displayedComponents: .hourAndMinute)
                }
            } footer: { Text("Your first event, top tasks, meds, important email and weather in one notification, written by Apple Intelligence.") }
            .onChange(of: briefingOn) { Task { await Briefing.refresh(ctx: KeelStore.container.mainContext) } }
            .onChange(of: briefingMinute) { Task { await Briefing.refresh(ctx: KeelStore.container.mainContext) } }
            Section {
                Picker("Default Alert", selection: $defaultAlert) {
                    Text("None").tag(-1)
                    ForEach(TaskAlerts.offsets.compactMap { $0.minutes == nil ? nil : $0 }, id: \.label) { Text($0.label).tag($0.minutes ?? 0) }
                }
                Toggle("Time Sensitive Reminders", isOn: $timeSensitive)
                    .onChange(of: timeSensitive) {
                        TaskAlerts.rescheduleAll((try? KeelStore.container.mainContext.fetch(FetchDescriptor<TaskItem>())) ?? [])
                    }
                if timeSensitive && timeSensitiveBlocked {
                    Button("Allow Time Sensitive for Keel…", systemImage: "exclamationmark.triangle.fill") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .foregroundStyle(.orange)
                }
            } header: { Text("Tasks & Reminders") } footer: {
                Text("Task reminders, habit nudges, routine steps, meeting prep, promises and follow-ups pop up right away, stay on your Lock Screen for an hour, and come through Focus modes that allow Time Sensitive alerts. Medication and leave-now alerts are always Time Sensitive.")
            }
            .task { timeSensitiveBlocked = await UNUserNotificationCenter.current().notificationSettings().timeSensitiveSetting == .disabled }
            Section("Focus") {
                Toggle("Hyperfocus Check-in", isOn: Binding(get: { !hyperfocusOff }, set: { hyperfocusOff = !$0 }))
            }
            Section {
                Toggle("Weekly Review Reminder", isOn: Binding(get: { !reviewOff }, set: { on in
                    reviewOff = !on
                    if on { WeeklyReview.scheduleReminder() }
                    else { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["weekly.review"]) }
                }))
            } footer: { Text("Sundays at 5 PM.") }
            Section {
                Toggle("Day in Review", isOn: Binding(get: { !UserDefaults.standard.bool(forKey: "dayReview.off") }, set: { on in
                    UserDefaults.standard.set(!on, forKey: "dayReview.off")
                    if on { DayReviewView.scheduleReminder() }
                    else { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["day.review"]) }
                }))
            } footer: { Text("Every evening at 8:30 PM.") }
            Section {
                Toggle("One-Minute Journal", isOn: $journalOn)
                if journalOn {
                    DatePicker("Time", selection: Binding(
                        get: { Calendar.current.date(bySettingHour: journalMinute / 60, minute: journalMinute % 60, second: 0, of: Date())! },
                        set: { journalMinute = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) }),
                        displayedComponents: .hourAndMinute)
                }
            } footer: { Text("A nightly question to answer in a minute. Keel finds mood patterns from your entries.") }
            .onChange(of: journalOn) { Journal.scheduleReminder() }
            .onChange(of: journalMinute) { Journal.scheduleReminder() }
        }
        .navigationTitle("Notifications")
    }
}

// MARK: - Mail, Tasks, Focus

struct MailSettings: View {
    @AppStorage(Prefs.undoSeconds) private var undoSeconds = 5
    @AppStorage(Prefs.loadImages) private var loadImages = false
    @AppStorage(Prefs.signature) private var signature = ""
    @AppStorage(Prefs.followUpDefault) private var followUp = 0
    @AppStorage("profile.name") private var myName = ""
    @AppStorage("style.on") private var styleOn = true

    var body: some View {
        List {
            Section {
                Picker("Undo Send Delay", selection: $undoSeconds) {
                    Text("Off").tag(0); Text("5 seconds").tag(5); Text("10 seconds").tag(10); Text("20 seconds").tag(20)
                }
                Picker("Remind If No Reply", selection: $followUp) {
                    Text("Off").tag(0); Text("Tomorrow").tag(1); Text("In 3 days").tag(3); Text("In a week").tag(7)
                }
            } header: { Text("Sending") } footer: { Text("“Remind if no reply” is the default for new emails; you can change it on each one.") }
            Section {
                Toggle("Load Remote Images", isOn: $loadImages)
            } header: { Text("Privacy") } footer: {
                Text("When off, images that could tell senders you opened their email are blocked until you tap “Load images”.")
            }
            Section {
                Toggle("Screener", isOn: Binding(get: { !UserDefaults.standard.bool(forKey: "screener.off") },
                                                 set: { UserDefaults.standard.set(!$0, forKey: "screener.off") }))
            } footer: { Text("The first time someone emails you, decide whether they get into your inbox. Blocked senders are archived automatically.") }
            Section {
                Toggle("Group by Conversation", isOn: Binding(get: { UserDefaults.standard.object(forKey: MailSwipe.threadsKey) as? Bool ?? true },
                                                               set: { UserDefaults.standard.set($0, forKey: MailSwipe.threadsKey) }))
                NavigationLink("Swipe Actions") { SwipeSettingsView() }
                NavigationLink("Layout") { MailLayoutSettings() }
                NavigationLink("Inbox Tabs") { InboxTabsSettings() }
                Toggle("Draft Replies in Advance", isOn: Binding(get: { AutoDrafts.isOn }, set: { UserDefaults.standard.set($0, forKey: AutoDrafts.onKey) }))
                NavigationLink("VIPs") { VIPListView() }
                Picker("Notify Me About", selection: Binding(get: { InboxBrain.notifyMode }, set: { UserDefaults.standard.set($0, forKey: InboxBrain.notifyKey) })) {
                    Text("VIPs and urgent mail").tag("urgent"); Text("VIPs only").tag("vip"); Text("Nothing").tag("off")
                }
                NavigationLink("Batched Delivery") { BatchSettingsView() }
            } header: { Text("Inbox") } footer: { Text("Keel learns from you: senders you open and reply to rise to Priority, senders you archive unread sink to Updates.") }
            Section { NavigationLink("Rules") { MailRulesView() } } footer: { Text("Auto-archive, star, file or turn mail into tasks as it arrives.") }
            Section {
                NavigationLink("Templates") { SnippetsView() }
                TextField("Your name", text: $myName).textContentType(.name)
            } header: { Text("Templates") } footer: {
                Text("Saved replies you insert while writing. Fill-ins like {name}, {company} and {date} are filled for you; {me} uses your name.")
            }
            Section("Signature") {
                TextField("Sent from Keel", text: $signature, axis: .vertical).lineLimit(2...5)
            }
            Section {
                Toggle("Write Replies in My Style", isOn: $styleOn)
                NavigationLink("What Keel Learned") { WritingStyleView() }
            } header: { Text("Your Writing Style") } footer: {
                Text("Keel learns your usual greeting, sign-off and length from your sent mail, so AI drafts sound like you. It stays on this iPhone.")
            }
        }
        .navigationTitle("Mail")
    }
}

struct TaskSettings: View {
    @AppStorage(Prefs.defaultList) private var defaultList = "Inbox"
    @AppStorage(Prefs.defaultAlert) private var defaultAlert = 0
    @AppStorage(TaskAlarms.globalKey) private var alarms = true

    var body: some View {
        List {
            Section {
                Toggle("Full-Screen Alarms", isOn: Binding(get: { alarms }, set: { on in
                    alarms = on
                    if on { Task { if !(await TaskAlarms.authorize()) { alarms = false } } }
                }))
            } footer: { Text("Timed task alerts take over the screen like an alarm clock, even on the Lock Screen and in Silent mode, with Done and Snooze buttons. You can also turn this on for single tasks.") }
            Section {
                Picker("Default List", selection: $defaultList) {
                    Text("Inbox").tag("Inbox")
                    ForEach(CalendarService.shared.reminderLists, id: \.calendarIdentifier) { Text($0.title).tag($0.title) }
                }
                Picker("Default Alert", selection: $defaultAlert) {
                    Text("None").tag(-1)
                    ForEach(TaskAlerts.offsets.compactMap { $0.minutes == nil ? nil : $0 }, id: \.label) { Text($0.label).tag($0.minutes ?? 0) }
                }
            } footer: { Text("Applies to new tasks that have a time.") }
            Section {
                NavigationLink { PlacesView() } label: { Label("Places & Leaving Home", systemImage: "mappin.and.ellipse") }
                NavigationLink { RoutinesView() } label: { Label("Routines", systemImage: "list.number") }
            } footer: { Text("Location reminders fire when you arrive at or leave a place, even when Keel is closed.") }
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quick add understands:").font(.subheadline.weight(.semibold))
                    Text("tomorrow 5pm · next Friday · every weekday · every 2 weeks · !high · #tag · ~List")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Tasks")
    }
}

struct FocusSettings: View {
    @AppStorage(Prefs.focusMinutes) private var minutes = 25
    @AppStorage(Prefs.hyperfocusCheck) private var hyperfocusOff = false
    @AppStorage(BreakReminders.onKey) private var breaksOn = false
    @AppStorage(BreakReminders.everyKey) private var breakEvery = 60
    @AppStorage(BreakReminders.startKey) private var breakStart = 540
    @AppStorage(BreakReminders.endKey) private var breakEnd = 1050
    @AppStorage(BreakReminders.weekendsKey) private var breakWeekends = false
    @AppStorage("forecast.on") private var forecastOn = true
    @State private var shutdown = ShutdownManager.shared

    private func minuteBinding(_ b: Binding<Int>) -> Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: b.wrappedValue / 60, minute: b.wrappedValue % 60, second: 0, of: Date())! },
                set: { b.wrappedValue = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) })
    }

    var body: some View {
        List {
            Section {
                Toggle("Focus Forecast", isOn: $forecastOn)
                NavigationLink("Set Up Medication Timing") { FocusForecastView() }
            } footer: { Text("Your best focus window each day, from your meds, sleep and focus history. A forecast, not medical advice.") }
            Section {
                Picker("Default Length", selection: $minutes) {
                    ForEach([15, 25, 45, 50, 60, 90], id: \.self) { Text("\($0) minutes").tag($0) }
                }
                Toggle("Hyperfocus Check-in", isOn: Binding(get: { !hyperfocusOff }, set: { hyperfocusOff = !$0 }))
            } footer: { Text("The check-in nudges you 30 minutes after a session ends, in case you lost track of time.") }
            Section {
                Toggle("Break Reminders", isOn: $breaksOn)
                if breaksOn {
                    Picker("Every", selection: $breakEvery) {
                        ForEach([30, 45, 60, 90], id: \.self) { Text("\($0) minutes").tag($0) }
                    }
                    DatePicker("From", selection: minuteBinding($breakStart), displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: minuteBinding($breakEnd), displayedComponents: .hourAndMinute)
                    Toggle("Weekends Too", isOn: $breakWeekends)
                }
            } footer: { Text("Quiet nudges to stand, drink water, rest your eyes or breathe. Never during a focus session.") }
            .onChange(of: breaksOn) { BreakReminders.schedule() }
            .onChange(of: breakEvery) { BreakReminders.schedule() }
            .onChange(of: breakStart) { BreakReminders.schedule() }
            .onChange(of: breakEnd) { BreakReminders.schedule() }
            .onChange(of: breakWeekends) { BreakReminders.schedule() }
            Section {
                LabeledContent("Screen Time Access", value: shutdown.isAuthorized ? "Allowed" : "Not allowed")
                if !shutdown.isAuthorized {
                    Button("Allow App Blocking") { Task { await shutdown.authorize() } }
                }
            } header: { Text("App Blocking") } footer: {
                Text(shutdown.blockingUnavailableReason ?? "Shield and Locked focus can block the apps you choose. Choose them on the Focus screen.")
            }
        }
        .navigationTitle("Focus")
    }
}

// MARK: - Appearance, Siri, Privacy

struct AppearanceSettings: View {
    @AppStorage(Prefs.appearance) private var appearance = "system"
    @AppStorage(Prefs.hapticsOff) private var hapticsOff = false
    @AppStorage("accent") private var accent = "indigo"
    @AppStorage(Prefs.calm) private var calm = false
    @State private var icon = AppIconChoice.allCases.first { $0.iconName == UIApplication.shared.alternateIconName } ?? .standard
    @AppStorage(KeelTextSize.key) private var textSize = 0

    var body: some View {
        List {
            Section {
                Picker("Text Size", selection: $textSize) {
                    ForEach(KeelTextSize.choices.indices, id: \.self) { i in Text(KeelTextSize.choices[i].0).tag(i) }
                }
            } footer: { Text("Keel follows your iPhone's text size (Settings → Display & Brightness → Text Size, or Accessibility → Larger Text), and works with Display Zoom. Pick a size here to change Keel only. Card grids switch to fewer columns as text gets bigger.") }
            Section {
                Toggle("Calm Mode", isOn: $calm)
            } footer: { Text("For overwhelming days: Today shows only your next thing and what's coming up. Unread counts and red overdue dates are hidden everywhere.") }
            Section("App Icon") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(AppIconChoice.allCases) { choice in
                            Button {
                                icon = choice
                                UIApplication.shared.setAlternateIconName(choice.iconName)
                            } label: {
                                VStack(spacing: 6) {
                                    Image(choice.preview).resizable().frame(width: 60, height: 60)
                                        .clipShape(.rect(cornerRadius: 14))
                                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(icon == choice ? DS.Palette.accent : .clear, lineWidth: 3))
                                    Text(choice.label).font(.caption2).foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            Section("Accent Color") {
                HStack {
                    ForEach(Theme.allCases) { t in
                        Button { accent = t.rawValue; Haptics.tap() } label: {
                            Circle().fill(t.color).frame(width: 34, height: 34)
                                .overlay(Circle().strokeBorder(.white, lineWidth: accent == t.rawValue ? 3 : 0))
                                .overlay { if accent == t.rawValue { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(t.name)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    Text("Automatic").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            LookSettingsSection()
            Section {
                Toggle("Haptics", isOn: Binding(get: { !hapticsOff }, set: { hapticsOff = !$0 }))
            } footer: { Text("Small taps you feel when you complete things.") }
        }
        .navigationTitle("Appearance")
    }
}

struct SiriSettings: View {
    private let phrases = [
        ("Ask Keel …", "Ask anything about your day, or tell Keel to do something"),
        ("Add a task in Keel", "Capture a task by voice"),
        ("Complete [task] in Keel", "Check off a task by name"),
        ("What's on today in Keel", "Hear your day's events and tasks"),
        ("Brain dump in Keel", "Say everything on your mind; Keel sorts it"),
        ("Check my inbox in Keel", "Who needs a reply"),
        ("What should I do now in Keel", "Your single best next step"),
        ("Start focus in Keel / End focus in Keel", "Control focus sessions"),
        ("Did I take my meds in Keel", "Whether you've logged today's doses"),
        ("Plan my day (Shortcuts app)", "Opens the 3-minute planning ritual"),
    ]

    var body: some View {
        List {
            Section {
                ForEach(phrases, id: \.0) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("“Hey Siri, \(p.0)”").font(.body.weight(.medium))
                        Text(p.1).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } header: { Text("Things You Can Say") }
            Section {
                ShortcutsLink()
            } footer: { Text("Keel's actions also work in the Shortcuts app, in Spotlight and with the Action button.") }
        }
        .navigationTitle("Siri & Shortcuts")
    }
}

struct PrivacySettings: View {
    @AppStorage("ai.privateMode") private var privateMode = false
    @AppStorage("ai.provider") private var providerRaw = "apple"
    @AppStorage(AppLock.enabledKey) private var appLock = false
    @State private var showServer = false

    var body: some View {
        List {
            Section {
                Toggle("Require \(AppLock.biometryName)", isOn: Binding(get: { appLock }, set: { on in
                    Task { if await AppLock.authenticate(on ? "Turn on the Keel lock" : "Turn off the Keel lock") { appLock = on } }
                }))
            } header: { Text("App Lock") } footer: {
                Text("Keel locks when you leave it and hides its contents in the app switcher. Lock single notes from a note's ⋯ menu.")
            }
            Section {
                NavigationLink { MemoryView() } label: { LabeledContent("What Keel Knows", value: "\(KeelMemory.shared.facts.count)") }
                Toggle("Look Up Context on the Web", isOn: Binding(get: { UserDefaults.standard.object(forKey: WebContext.onKey) as? Bool ?? true },
                                                                  set: { UserDefaults.standard.set($0, forKey: WebContext.onKey) }))
                Toggle("Autopilot", isOn: Binding(get: { UserDefaults.standard.object(forKey: "autopilot.on") as? Bool ?? true },
                                                  set: { UserDefaults.standard.set($0, forKey: "autopilot.on") }))
            } header: { Text("Personal AI") } footer: {
                Text("Autopilot prepares replies, rebalances overbooked days, finds focus time and more, and waits for your tap before doing anything. Web context lets meeting notes read company websites, invite links and Wikipedia (and run a web search with your own AI key); people's names are never sent, and it's off in Private mode.")
            }
            Section {
                Picker("AI Model", selection: $providerRaw) {
                    ForEach(AIProvider.allCases) { Text($0.name).tag($0.rawValue) }
                }
                if let p = AIProvider(rawValue: providerRaw), p != .apple {
                    NavigationLink { AIKeySettings(provider: p) } label: {
                        LabeledContent("\(p.name) Key", value: DirectAI.key(for: p) == nil ? "Not added" : "Added")
                    }
                }
            } header: { Text("AI Model") } footer: {
                Text(providerRaw == "apple"
                     ? "Free and private. Runs on this iPhone."
                     : "Used for planning, drafts and summaries when Apple Intelligence isn't enough. Requests go from this iPhone straight to the provider, and they bill you per use. Ask Keel and email sorting stay on Apple Intelligence.")
            }
            Section {
                LabeledContent("Apple Intelligence", value: AIRouter.shared.onDeviceAvailable ? "On" : "Off")
                if !AIRouter.shared.onDeviceAvailable {
                    Button("Turn On in Settings…") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            } header: { Text("On-Device AI") } footer: {
                Text("Sorting, summaries, drafts, planning and Ask Keel run on this iPhone with Apple Intelligence. Turn it on in Settings → Apple Intelligence & Siri (iPhone 15 Pro or newer).")
            }
            Section {
                Toggle("Private Mode", isOn: $privateMode)
            } footer: { Text("Keeps everything on this iPhone, even if you connect an optional AI server.") }
            Section {
                LabeledContent("Status", value: KeelServer.isConfigured ? "Connected" : "Not connected")
                Button(KeelServer.isConfigured ? "Change Server…" : "Connect Server…") { showServer = true }
            } header: { Text("Optional AI Server") } footer: {
                Text("Not needed. Advanced users can connect their own server for stronger day planning.")
            }
        }
        .navigationTitle("AI & Privacy")
        .sheet(isPresented: $showServer) { KeelServerSetupView() }
    }
}

// MARK: - Data

struct DataSettings: View {
    @Environment(\.modelContext) private var ctx
    @State private var exportURL: URL?
    @State private var zipURL: URL?
    @State private var confirmErase = false
    @State private var syncing = false
    @AppStorage("onboarding.done") private var onboarded = true

    var body: some View {
        List {
            Section {
                LabeledContent("Last Sync", value: lastSync)
                Button(syncing ? "Syncing…" : "Sync Everything Now") {
                    Task { syncing = true; await SyncEngine.shared.syncAll(); syncing = false }
                }
                .disabled(syncing)
            }
            Section {
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Share Export", systemImage: "square.and.arrow.up") }
                } else {
                    Button { exportURL = makeExport() } label: { Label("Export My Data (JSON)", systemImage: "arrow.down.doc") }
                }
                if let zipURL {
                    ShareLink(item: zipURL) { Label("Share Everything (ZIP)", systemImage: "square.and.arrow.up.on.square") }
                } else {
                    Button { zipURL = try? ExportAll.make(ctx: ctx) } label: { Label("Export Everything (ZIP)", systemImage: "archivebox") }
                }
            } footer: { Text("Export Everything makes a ZIP anyone can open: every note as a Markdown file in its folders, plus tasks, habits, journal and food as spreadsheets. Your data is always yours.") }
            MarkdownMirrorSection()
            DiagnosticsSection()
            Section { NavigationLink { ImportView() } label: { Label("Move to Keel (Import)", systemImage: "square.and.arrow.down") } }
            BackupSection()
            Section {
                Button("Erase All Keel Data", role: .destructive) { confirmErase = true }
            } footer: {
                Text("Removes everything Keel stores on this iPhone, including signed-in accounts. Your email, calendars and Reminders are not touched.")
            }
        }
        .navigationTitle("Data & Storage")
        .confirmationDialog("Erase all Keel data on this iPhone?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase All Data", role: .destructive) { eraseAll() }
        } message: { Text("This can't be undone.") }
    }

    private var lastSync: String {
        let dates = ((try? ctx.fetch(FetchDescriptor<MailAccount>())) ?? []).compactMap(\.lastSyncedAt)
        return dates.max()?.formatted(.relative(presentation: .named)) ?? "Never"
    }

    private func makeExport() -> URL? {
        let iso = ISO8601DateFormatter()
        let tasks = ((try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []).map { t -> [String: Any] in
            ["title": t.title, "notes": t.notes, "list": t.listName, "done": t.isDone, "tags": t.tags,
             "due": t.dueDate.map(iso.string(from:)) ?? "", "priority": t.priority.rawValue]
        }
        let notes = ((try? ctx.fetch(FetchDescriptor<Note>())) ?? []).map { ["title": $0.title, "text": $0.isLocked ? "(locked)" : $0.plainText] }
        let goals = ((try? ctx.fetch(FetchDescriptor<Goal>())) ?? []).map { ["title": $0.title, "area": $0.area.rawValue, "why": $0.why] }
        let habits = ((try? ctx.fetch(FetchDescriptor<Habit>())) ?? []).map { ["name": $0.name, "streak": $0.currentStreak, "total": $0.totalCompletions] as [String: Any] }
        let payload: [String: Any] = ["exportedAt": iso.string(from: Date()), "tasks": tasks, "notes": notes, "goals": goals, "habits": habits]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Keel Export \(Date().formatted(.iso8601.year().month().day())).json")
        return (try? data.write(to: url)) != nil ? url : nil
    }

    private func eraseAll() {
        for a in (try? ctx.fetch(FetchDescriptor<MailAccount>())) ?? [] {
            KeychainStore.delete("tokens.\(a.id)")
            KeychainStore.delete("imap.\(a.id)")
        }
        try? ctx.delete(model: EmailMessage.self)
        try? ctx.delete(model: MailAccount.self)
        try? ctx.delete(model: TaskItem.self)
        try? ctx.delete(model: Note.self)
        try? ctx.delete(model: Habit.self)
        try? ctx.delete(model: HabitStack.self)
        try? ctx.delete(model: HabitLog.self)
        try? ctx.delete(model: FocusSession.self)
        try? ctx.delete(model: Commitment.self)
        try? ctx.delete(model: Goal.self)
        try? ctx.delete(model: FollowUp.self)
        try? ctx.save()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        onboarded = false
        Haptics.success()
    }
}

/// Sign in to any IMAP account: iCloud, Yahoo, AOL, Fastmail, Zoho or your own server.
struct ICloudSetupView: View {
    var kind: MailProviderKind = .icloud
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var checking = false
    @State private var error: String?
    @State private var server = IMAPServer.icloud
    @State private var showAdvanced = false
    @State private var username = ""

    private var title: String {
        switch kind { case .yahoo: "Yahoo Mail"; case .aol: "AOL Mail"; case .imap: "Other Email"; default: "iCloud Mail" }
    }
    private var placeholder: String {
        switch kind { case .yahoo: "you@yahoo.com"; case .aol: "you@aol.com"; case .imap: "you@example.com"; default: "you@icloud.com" }
    }
    private var help: String {
        switch kind {
        case .yahoo: "Yahoo needs an app password, not your normal one: sign in at login.yahoo.com → Account Security → Generate app password, choose “Other app”, and paste it here."
        case .aol: "AOL needs an app password, not your normal one: sign in at login.aol.com → Account Security → Generate app password, and paste it here."
        case .imap: "Most providers need an app password for email apps; check your provider's security settings. Keel fills in the usual server names; change them under Server settings if yours are different."
        default: "Apple doesn't offer a mail API, so Keel connects to iCloud the standard way (IMAP and SMTP) using an app-specific password, not your Apple Account password. Create one at account.apple.com → Sign-In and Security → App-Specific Passwords."
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(placeholder, text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onChange(of: email) { _, new in if kind == .imap, let g = IMAPServer.guess(for: new) { server = g } }
                    SecureField(kind == .imap ? "Password or app password" : "App password", text: $password)
                } footer: {
                    Text(help + " It's stored only in this iPhone's Keychain.")
                }
                if kind == .imap {
                    Section {
                        DisclosureGroup("Server settings", isExpanded: $showAdvanced) {
                            TextField("Incoming (IMAP) server", text: $server.imapHost).textInputAutocapitalization(.never).autocorrectionDisabled()
                            Stepper("IMAP port \(server.imapPort)", value: $server.imapPort, in: 1...65535)
                            TextField("Outgoing (SMTP) server", text: $server.smtpHost).textInputAutocapitalization(.never).autocorrectionDisabled()
                            Picker("SMTP security", selection: $server.smtpPort) {
                                Text("SSL/TLS (465)").tag(465); Text("STARTTLS (587)").tag(587)
                            }
                            TextField("Username (if not your email)", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        }
                    }
                }
                if checking { Section { ProgressView("Checking your sign-in…") } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") { Task { await connect() } }
                        .disabled(email.isEmpty || password.isEmpty || checking)
                }
            }
            .onAppear {
                switch kind {
                case .yahoo: server = .yahoo
                case .aol: server = .aol
                default: server = .icloud
                }
            }
        }
    }

    private func connect() async {
        checking = true; error = nil
        defer { checking = false }
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        let pass = password.trimmingCharacters(in: .whitespaces)
        var target = server
        let u = username.trimmingCharacters(in: .whitespaces)
        target.username = u.isEmpty ? nil : u
        do {
            let verified = try await ICloudMailProvider.verify(address: address, password: pass, server: target)
            let colors: [MailProviderKind: String] = [.icloud: "#3E8EF7", .yahoo: "#6001D2", .aol: "#2E6BF0", .imap: "#5B8DEF"]
            let a = MailAccount(provider: kind, address: address, displayName: address, colorHex: colors[kind] ?? "#5B8DEF")
            KeychainStore.save(pass, for: "imap.\(a.id)")
            if kind != .icloud { verified.save(accountId: a.id) }
            ctx.insert(a)
            Haptics.success()
            dismiss()
            await SyncEngine.shared.syncAll()
        } catch {
            self.error = "Couldn't sign in. Check the email, the app password\(kind == .imap ? " and the server settings" : ""). (\(error.localizedDescription))"
        }
    }
}

// MARK: - Keel Pro (StoreKit 2). OFF while Keel is personal-use only.

enum Entitlements {
    /// Flip to true when you ship to the App Store. While false, every feature is unlocked.
    static let paywallEnabled = false
    static let productIds = ["keel.pro.monthly", "keel.pro.yearly"]

    static func isPro() async -> Bool {
        guard paywallEnabled else { return true }
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, productIds.contains(t.productID), t.revocationDate == nil { return true }
        }
        return false
    }
}

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        // Apple's built-in StoreKit view — handles pricing, trials, purchase and restore, localized.
        SubscriptionStoreView(productIDs: Entitlements.productIds) {
            VStack(spacing: DS.Space.m) {
                Image(systemName: "sailboat.fill").font(.system(size: 56)).foregroundStyle(DS.Palette.accent)
                Text("Keel Pro").font(DS.Font.hero)
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Label("Unlimited email accounts", systemImage: "tray.2")
                    Label("AI day planning", systemImage: "sparkles")
                    Label("App blocking & Locked focus", systemImage: "lock.shield")
                    Label("Promise tracker & body doubling", systemImage: "person.2.wave.2")
                }.font(DS.Font.body)
            }.padding()
        }
        .subscriptionStoreControlStyle(.prominentPicker)
        .storeButton(.visible, for: .restorePurchases)
        .tint(DS.Palette.accent)
    }
}

extension Color {
    init(hex: String) {
        let v = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x5B8DEF
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// Paste the server address and access code from your Mac (Universal Clipboard: copy on Mac, paste here).
struct KeelServerSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var address = UserDefaults.standard.string(forKey: KeelServer.addressKey) ?? ""
    @State private var code = KeelServer.accessCode ?? ""
    @State private var checking = false
    @State private var message: String?
    @State private var ok = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("keel-backend.yourname.workers.dev", text: $address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Access code", text: $code)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } footer: {
                    Text("Both come from deploying the Keel server. Copy each on your Mac and paste here (same Apple Account = shared clipboard).")
                }
                if checking { Section { ProgressView("Checking…") } }
                if let message {
                    Section { Label(message, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle").foregroundStyle(ok ? DS.Palette.calm : .red) }
                }
            }
            .navigationTitle("Claude AI")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Test & Save") { Task { await testAndSave() } }
                        .disabled(address.isEmpty || code.isEmpty || checking)
                }
            }
        }
    }

    private func testAndSave() async {
        checking = true; message = nil
        defer { checking = false }
        switch await KeelServer.check(address: address, accessCode: code) {
        case .ok:
            KeelServer.save(address: address, accessCode: code)
            ok = true; message = "Connected. Claude features are on."
            Haptics.success()
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        case .badCode:
            ok = false; message = "The server is there, but that access code isn't right."
        case .unreachable(let why):
            ok = false; message = "Couldn't reach the server: \(why)"
        }
    }
}

/// Paste and test an API key for Claude, ChatGPT or Gemini.
struct AIKeySettings: View {
    let provider: AIProvider
    @State private var key = ""
    @State private var model = ""
    @State private var testing = false
    @State private var result: String?
    @State private var ok = false

    var body: some View {
        Form {
            Section {
                SecureField("API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField(provider.defaultModel, text: $model).textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: { Text("\(provider.company) API") } footer: {
                Text("Leave the model blank to use \(provider.defaultModel). The key is stored only in this iPhone's Keychain.")
            }
            if let page = provider.keyPage {
                Section { Link("Get a \(provider.company) API key", destination: page) } footer: {
                    Text("API keys are separate from a \(provider.name) chat subscription. Most providers ask you to add a payment method first.")
                }
            }
            Section {
                Button(testing ? "Testing…" : "Test & Save") { Task { await testAndSave() } }
                    .disabled(key.isEmpty || testing)
                if let result { Label(result, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle").foregroundStyle(ok ? .green : .red) }
            }
            if DirectAI.key(for: provider) != nil {
                Section { Button("Remove Key", role: .destructive) { KeychainStore.delete(provider.keychainKey); key = ""; result = "Removed." ; ok = true } }
            }
        }
        .navigationTitle(provider.name)
        .onAppear {
            key = DirectAI.key(for: provider) ?? ""
            model = UserDefaults.standard.string(forKey: "ai.model.\(provider.rawValue)") ?? ""
        }
    }

    private func testAndSave() async {
        testing = true; defer { testing = false }
        let m = model.trimmingCharacters(in: .whitespaces).isEmpty ? provider.defaultModel : model
        if let error = await DirectAI.test(provider, key: key.trimmingCharacters(in: .whitespacesAndNewlines), model: m) {
            ok = false; result = error
        } else {
            KeychainStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines), for: provider.keychainKey)
            UserDefaults.standard.set(model, forKey: "ai.model.\(provider.rawValue)")
            ok = true; result = "Connected. Keel will use \(provider.name)."
            Haptics.success()
        }
    }
}

/// Settings → Mail → VIPs.
struct VIPListView: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<SenderScore> { $0.isVIP }, sort: \SenderScore.name) private var vips: [SenderScore]
    @State private var newAddress = ""

    var body: some View {
        List {
            Section {
                ForEach(vips) { v in
                    HStack {
                        SenderAvatar(name: v.name, email: v.sender, size: 30)
                        VStack(alignment: .leading) {
                            Text(v.name.isEmpty ? v.sender : v.name)
                            Text(v.sender).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in idx.map { vips[$0] }.forEach { $0.isVIP = false } }
            } footer: { Text("VIPs always land in Priority, skip batched delivery and can notify you. Long-press any email to add its sender.") }
            Section("Add a VIP") {
                TextField("name@example.com", text: $newAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Add") { InboxBrain.setVIP(true, sender: newAddress, name: "", ctx: ctx); newAddress = "" }
                    .disabled(!newAddress.contains("@"))
            }
        }
        .navigationTitle("VIPs")
    }
}

/// Settings → Mail → Batched Delivery.
struct BatchSettingsView: View {
    @AppStorage(InboxBrain.batchOnKey) private var on = false
    @AppStorage(InboxBrain.batchTimesKey) private var timesRaw = "540,780,1020"

    private var times: [Int] { timesRaw.split(separator: ",").compactMap { Int($0) }.sorted() }

    var body: some View {
        List {
            Section {
                Toggle("Batched Delivery", isOn: $on)
            } footer: { Text("Non-urgent mail waits and arrives all at once at the times below, so your inbox isn't a constant stream of interruptions. VIPs and urgent mail come straight through.") }
            if on {
                Section("Delivery times") {
                    ForEach(Array(times.enumerated()), id: \.offset) { i, m in
                        DatePicker("Delivery \(i + 1)", selection: Binding(
                            get: { Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date())! },
                            set: { d in
                                var t = times
                                t[i] = Calendar.current.component(.hour, from: d) * 60 + Calendar.current.component(.minute, from: d)
                                timesRaw = t.sorted().map(String.init).joined(separator: ",")
                            }), displayedComponents: .hourAndMinute)
                    }
                    .onDelete { idx in
                        var t = times; t.remove(atOffsets: idx)
                        timesRaw = (t.isEmpty ? [540] : t).map(String.init).joined(separator: ",")
                    }
                    if times.count < 6 {
                        Button("Add a delivery time") { timesRaw = (times + [min(1320, (times.last ?? 540) + 120)]).map(String.init).joined(separator: ",") }
                    }
                }
            }
        }
        .navigationTitle("Batched Delivery")
    }
}

// MARK: - Send-as aliases

struct AliasesView: View {
    let account: MailAccount
    @State private var list: [String] = []
    @State private var new = ""

    var body: some View {
        List {
            Section {
                ForEach(list, id: \.self) { Text($0) }
                    .onDelete { list.remove(atOffsets: $0); MailAliases.save(list, for: account.id) }
                HStack {
                    TextField("alias@example.com", text: $new)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit(add)
                    Button("Add", action: add).disabled(!new.contains("@"))
                }
            } header: { Text("Addresses") } footer: { Text(help) }
        }
        .navigationTitle("Send As")
        .onAppear { list = MailAliases.list(account.id) }
    }

    private var help: String {
        switch account.provider {
        case .gmail: "Add addresses you've already set up in Gmail's settings under “Send mail as”. Gmail uses your main address for any it doesn't recognize."
        case .outlook: "Your mail admin must give this account “send as” permission for the address, or the email won't send."
        default: "Use aliases your email provider lets this account send from, such as iCloud+ custom domain addresses."
        }
    }

    private func add() {
        let a = new.trimmingCharacters(in: .whitespaces).lowercased()
        guard a.contains("@"), a != account.address.lowercased(), !list.contains(a) else { return }
        list.append(a); new = ""
        MailAliases.save(list, for: account.id)
        Haptics.tap()
    }
}

// MARK: - Writing style

struct WritingStyleView: View {
    @Query private var accounts: [MailAccount]
    @State private var profile = WritingStyle.profile
    @State private var learning = false

    var body: some View {
        List {
            if profile.samples < 3 {
                Section {
                    Text("Keel hasn't seen enough of your sent mail yet. Tap Learn Now, or keep using Keel and it learns as you send.")
                        .foregroundStyle(DS.Palette.inkSoft)
                }
            } else {
                Section {
                    LabeledContent("Greeting", value: profile.greeting.isEmpty ? "Usually none" : profile.greeting.replacingOccurrences(of: "{name}", with: "Sam"))
                    LabeledContent("Sign-off", value: profile.signoff.isEmpty ? "Varies" : profile.signoff)
                    LabeledContent("Typical length", value: "\(profile.medianWords) words")
                    LabeledContent("Exclamation marks", value: profile.exclamationRate > 0.4 ? "Often" : profile.exclamationRate < 0.1 ? "Rarely" : "Sometimes")
                    LabeledContent("Emoji", value: profile.emojiRate > 0.3 ? "Often" : profile.emojiRate > 0.05 ? "Sometimes" : "Rarely")
                } header: { Text("From \(profile.samples) emails you sent") } footer: {
                    if let d = profile.learnedAt { Text("Updated \(d.formatted(.relative(presentation: .named))).") }
                }
            }
            Section {
                Button(learning ? "Learning…" : "Learn Now") {
                    Task {
                        learning = true
                        await WritingStyle.relearn(accounts: accounts)
                        profile = WritingStyle.profile
                        learning = false
                    }
                }
                .disabled(learning || accounts.isEmpty)
                Button("Forget My Style", role: .destructive) { WritingStyle.reset(); profile = WritingStyle.profile }
            } footer: { Text("Learn Now reads the last 30 days of mail you sent. Only short statistics are kept.") }
        }
        .navigationTitle("Writing Style")
    }
}

/// Top of Settings: who's signed in and whether this device is syncing.
private struct AccountRow: View {
    @State private var account = KeelAccount.shared
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.isSignedIn ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle.badge.plus")
                .font(.system(size: 34)).foregroundStyle(DS.Palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.isSignedIn ? (account.name.isEmpty ? "Keel Account" : account.name) : "Sign in to Keel").font(DS.Font.headline)
                Text(account.isSignedIn ? (KeelStore.syncState == "on" ? "Syncing with iCloud" : "Signed in") : "Same Keel on iPhone, iPad and Mac")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Settings search: type “alarms”, “text size”, “Claude” or “sync” and jump straight there.
private struct SettingsSearchResults: View {
    let query: String

    private struct Entry: Identifiable {
        let id: String
        let title: String
        let icon: String
        let color: Color
        let words: String
        let destination: () -> AnyView
    }

    private var entries: [Entry] {
        func e<V: View>(_ title: String, _ icon: String, _ color: Color, _ words: String, @ViewBuilder _ d: @escaping () -> V) -> Entry {
            Entry(id: title, title: title, icon: icon, color: color, words: words, destination: { AnyView(d()) })
        }
        return [
            e("Account & iCloud Sync", "person.crop.circle.fill", DS.Palette.accent, "account sign in apple icloud sync devices mac ipad login profile") { AccountView() },
            e("Mail Accounts", "envelope.fill", .blue, "email gmail outlook icloud yahoo add account") { MailAccountsSettings() },
            e("Calendars", "calendar", .red, "calendar google outlook show hide") { CalendarSettings() },
            e("Reminders", "checklist", .orange, "apple reminders sync lists") { RemindersSettings() },
            e("Connected Apps", "app.connected.to.app.below.fill", .indigo, "connect notion health apps integrations") { ConnectedAppsView() },
            e("Notifications", "bell.badge.fill", .red, "notifications alerts time sensitive pop up briefing reminders sound") { NotificationSettings() },
            e("Mail", "paperplane.fill", .blue, "mail swipe signature batched delivery vip notify") { MailSettings() },
            e("Tasks & Full-Screen Alarms", "checkmark.circle.fill", .green, "tasks alarms full screen default list alert") { TaskSettings() },
            e("Focus", "moon.fill", .indigo, "focus block apps screen time sounds hyperfocus") { FocusSettings() },
            e("Medications", "pills.fill", .mint, "meds medication pills dose refill") { MedsView() },
            e("Health & Nutrition", "fork.knife", .green, "health nutrition food diet protein apple health") { NutritionSettingsView() },
            e("Appearance & Text Size", "textformat.size", .gray, "appearance dark light theme color accent icon text size bigger font calm haptics") { AppearanceSettings() },
            e("Siri & Shortcuts", "waveform", .purple, "siri shortcuts voice") { SiriSettings() },
            e("AI & Privacy", "hand.raised.fill", .blue, "ai claude chatgpt gemini key server private apple intelligence memory") { PrivacySettings() },
            e("Help: How do I…", "questionmark.bubble.fill", .indigo, "help how guide tutorial") { HelpCenterView() },
            e("How Keel Works", "questionmark", .teal, "features guide explained") { FeatureGuideView() },
            e("Data & Storage", "externaldrive.fill", .gray, "backup restore export everything zip markdown erase import storage crash reports diagnostics") { DataSettings() },
            e("Email to Keel", "envelope.arrow.triangle.branch.fill", .blue, "email forward address task note plus keel") { EmailToKeelView() },
            e("Automations", "bolt.horizontal.fill", .orange, "automation rules when then trigger") { AutomationsView() },
        ]
    }

    var body: some View {
        let q = query.lowercased().split(separator: " ").map(String.init)
        let hits = entries.filter { en in q.allSatisfy { (en.title + " " + en.words).lowercased().contains($0) } }
        if hits.isEmpty {
            ContentUnavailableView {
                Label("No setting called “\(query)”", systemImage: "magnifyingglass")
            } description: {
                Text("Try other words, or look it up in Help.")
            } actions: {
                NavigationLink("Search Help") { HelpCenterView() }
            }
            .listRowBackground(Color.clear)
        } else {
            ForEach(hits) { h in
                NavigationLink { h.destination() } label: {
                    HStack(spacing: 12) { SettingsIcon(symbol: h.icon, color: h.color); Text(h.title) }
                }
            }
        }
    }
}
