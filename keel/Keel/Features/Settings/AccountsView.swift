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

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "sailboat.fill")
                            .font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 60, height: 60)
                            .background(DS.Palette.accent.gradient, in: .rect(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keel").font(.title2.weight(.semibold))
                            Text(accounts.isEmpty ? "Add an email account to get started" : "\(accounts.count) account\(accounts.count == 1 ? "" : "s") · syncing")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    SettingsRow(title: "Mail Accounts", symbol: "envelope.fill", color: .blue, value: accounts.isEmpty ? "None" : "\(accounts.count)") { MailAccountsSettings() }
                    SettingsRow(title: "Calendars", symbol: "calendar", color: .red) { CalendarSettings() }
                    SettingsRow(title: "Reminders", symbol: "checklist", color: .orange) { RemindersSettings() }
                    SettingsRow(title: "Connected Apps", symbol: "app.connected.to.app.below.fill", color: .indigo) { ConnectedAppsView() }
                }

                Section {
                    SettingsRow(title: "Notifications", symbol: "bell.badge.fill", color: .red) { NotificationSettings() }
                    SettingsRow(title: "Mail", symbol: "paperplane.fill", color: .blue) { MailSettings() }
                    SettingsRow(title: "Tasks", symbol: "checkmark.circle.fill", color: .green) { TaskSettings() }
                    SettingsRow(title: "Focus", symbol: "moon.fill", color: .indigo) { FocusSettings() }
                }

                Section {
                    SettingsRow(title: "Appearance", symbol: "textformat.size", color: .gray, value: appearance.capitalized) { AppearanceSettings() }
                    SettingsRow(title: "Siri & Shortcuts", symbol: "waveform", color: .purple) { SiriSettings() }
                    SettingsRow(title: "AI & Privacy", symbol: "hand.raised.fill", color: .blue, value: privateMode ? "Private" : nil) { PrivacySettings() }
                }

                Section {
                    SettingsRow(title: "How Keel Works", symbol: "questionmark", color: .teal) { FeatureGuideView() }
                    Button { showTour = true } label: {
                        HStack(spacing: 12) { SettingsIcon(symbol: "play.fill", color: .teal); Text("Replay Welcome Tour").foregroundStyle(.primary) }
                    }
                    if Entitlements.paywallEnabled {
                        Button { showPaywall = true } label: {
                            HStack(spacing: 12) { SettingsIcon(symbol: "star.fill", color: .yellow); Text("Keel Pro").foregroundStyle(.primary) }
                        }
                    }
                }

                Section {
                    SettingsRow(title: "Data & Storage", symbol: "externaldrive.fill", color: .gray) { DataSettings() }
                    LabeledContent("Version", value: version)
                } footer: {
                    Text("Your data stays on this iPhone and your own email, calendar and Reminders accounts. Keel has no servers of its own.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
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
    @State private var showICloud = false
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
                Button { showICloud = true } label: { Label("iCloud Mail", systemImage: "icloud") }
            }
            if working { Section { ProgressView("Signing in…") } }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("Mail Accounts")
        .sheet(isPresented: $showICloud) { ICloudSetupView() }
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
    private var hidden: Set<String> { Set(hiddenRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        List {
            Section {
                Picker("Default View", selection: $mode) { ForEach(CalendarMode.allCases) { Text($0.rawValue).tag($0.rawValue) } }
                Toggle("Show Tasks on Calendar", isOn: $showTasks)
            }
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

    var body: some View {
        List {
            Section { NotificationStatusRow() } footer: {
                Text("Keel's alerts come from this iPhone: task reminders, focus timers, habit nudges, promises and follow-ups.")
            }
            Section("Tasks") {
                Picker("Default Alert", selection: $defaultAlert) {
                    Text("None").tag(-1)
                    ForEach(TaskAlerts.offsets.compactMap { $0.minutes == nil ? nil : $0 }, id: \.label) { Text($0.label).tag($0.minutes ?? 0) }
                }
            }
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
            Section { NavigationLink("Rules") { MailRulesView() } } footer: { Text("Auto-archive, star, file or turn mail into tasks as it arrives.") }
            Section { NavigationLink("Snippets") { SnippetsView() } } footer: { Text("Saved replies you can insert while writing an email.") }
            Section("Signature") {
                TextField("Sent from Keel", text: $signature, axis: .vertical).lineLimit(2...5)
            }
        }
        .navigationTitle("Mail")
    }
}

struct TaskSettings: View {
    @AppStorage(Prefs.defaultList) private var defaultList = "Inbox"
    @AppStorage(Prefs.defaultAlert) private var defaultAlert = 0

    var body: some View {
        List {
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
    @State private var shutdown = ShutdownManager.shared

    var body: some View {
        List {
            Section {
                Picker("Default Length", selection: $minutes) {
                    ForEach([15, 25, 45, 50, 60, 90], id: \.self) { Text("\($0) minutes").tag($0) }
                }
                Toggle("Hyperfocus Check-in", isOn: Binding(get: { !hyperfocusOff }, set: { hyperfocusOff = !$0 }))
            } footer: { Text("The check-in nudges you 30 minutes after a session ends, in case you lost track of time.") }
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
    @State private var icon = AppIconChoice.allCases.first { $0.iconName == UIApplication.shared.alternateIconName } ?? .standard

    var body: some View {
        List {
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
        ("What's next on my calendar in Keel", "Your next event"),
        ("Check my inbox in Keel", "Who needs a reply"),
        ("What should I do now in Keel", "Your single best next step"),
        ("Start focus in Keel / End focus in Keel", "Control focus sessions"),
        ("What did I promise in Keel", "Commitments from your sent email"),
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
    @State private var showServer = false

    var body: some View {
        List {
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
                    Button { exportURL = makeExport() } label: { Label("Export My Data", systemImage: "arrow.down.doc") }
                }
            } footer: { Text("A JSON file with your tasks, notes, goals and habits.") }
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
        let notes = ((try? ctx.fetch(FetchDescriptor<Note>())) ?? []).map { ["title": $0.title, "text": $0.plainText] }
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

struct ICloudSetupView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var checking = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("you@icloud.com", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("App-specific password (xxxx-xxxx-xxxx-xxxx)", text: $password)
                } footer: {
                    Text("Apple doesn't offer a mail API, so Keel connects to iCloud the standard way (IMAP and SMTP) using an app-specific password, not your Apple Account password. Create one at account.apple.com → Sign-In and Security → App-Specific Passwords. It's stored only in this iPhone's Keychain.")
                }
                if checking { Section { ProgressView("Checking with iCloud…") } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("iCloud Mail")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") { Task { await connect() } }
                        .disabled(email.isEmpty || password.isEmpty || checking)
                }
            }
        }
    }

    private func connect() async {
        checking = true; error = nil
        defer { checking = false }
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        let pass = password.trimmingCharacters(in: .whitespaces)
        do {
            try await ICloudMailProvider.verify(address: address, password: pass)
            let a = MailAccount(provider: .icloud, address: address, displayName: address, colorHex: "#3E8EF7")
            KeychainStore.save(pass, for: "imap.\(a.id)")
            ctx.insert(a)
            Haptics.success()
            dismiss()
            await SyncEngine.shared.syncAll()
        } catch {
            self.error = error.localizedDescription
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
