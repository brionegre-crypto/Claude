import SwiftUI
import SwiftData
import UserNotifications

/// First run: a few minutes that leave Keel set up for you. Every step can be skipped.
struct OnboardingFlow: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboarding.done") private var done = false
    @Query private var accounts: [MailAccount]
    @State private var step = 0
    @State private var showMail = false
    @State private var showMeds = false
    @State private var showHabits = false
    @State private var calendarAllowed = false
    @State private var notificationsAllowed = false
    @State private var todayStyle = "balanced"
    @State private var name = ""
    @State private var focusTime = ""
    @State private var aboutMe = ""

    private let steps = 9
    @State private var showImport = false
    @State private var claudeKey = ""
    @State private var keyTesting = false
    @State private var keyResult: String?
    @State private var keyOK = DirectAI.isConfigured
    @State private var tryTool: ToolRoute?

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(step + 1), total: Double(steps)).tint(DS.Palette.accent).padding()
            ScrollView {
                VStack(spacing: DS.Space.l) {
                    switch step {
                    case 0: welcome
                    case 1: email
                    case 2: permissions
                    case 3: today
                    case 4: you
                    case 5: ownClaude
                    case 6: bringStuff
                    case 7: discover
                    default: finished
                    }
                }
                .padding(DS.Space.l)
                .frame(maxWidth: .infinity)
            }
            VStack(spacing: DS.Space.s) {
                Button { next() } label: {
                    Text(step == steps - 1 ? "Open Today" : "Continue")
                        .font(DS.Font.headline).frame(maxWidth: .infinity).padding(.vertical, DS.Space.m)
                        .background(DS.Palette.accent, in: Capsule()).foregroundStyle(.white)
                }
                if step > 0 && step < steps - 1 {
                    Button("Skip this step") { next() }.font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
            }
            .padding(.horizontal, DS.Space.l).padding(.bottom, DS.Space.m)
        }
        .background(DS.Palette.canvas)
        .sheet(isPresented: $showMail) { NavigationStack { MailAccountsSettings().toolbar { Button("Done") { showMail = false } } } }
        .sheet(isPresented: $showMeds) { NavigationStack { MedsView().toolbar { Button("Done") { showMeds = false } } } }
        .sheet(item: $tryTool) { ToolSheet(id: $0.id) }
        .sheet(isPresented: $showImport) { NavigationStack { ImportView() } }
        .sheet(isPresented: $showHabits) { NavigationStack { HabitLibraryView().toolbar { Button("Done") { showHabits = false } } } }
    }

    private func hero(_ icon: String, _ color: Color, _ title: String, _ subtitle: String) -> some View {
        VStack(spacing: DS.Space.m) {
            Image(systemName: icon).font(.system(size: 56, weight: .semibold)).foregroundStyle(color.gradient)
                .frame(width: 110, height: 110)
                .glassEffect(.regular.tint(color.opacity(0.2)), in: .rect(cornerRadius: 30))
            Text(title).font(DS.Font.hero).multilineTextAlignment(.center)
            Text(subtitle).font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft).multilineTextAlignment(.center)
        }
    }

    private var welcome: some View {
        VStack(spacing: DS.Space.l) {
            HorizonHeader(title: "Welcome to Keel", detail: "Your second brain, on calm water")
            Text("Email, calendar, tasks, notes and habits in one calm place, built for busy brains. The sky above every screen follows your day; what needs you sits above the waterline.")
                .font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: DS.Space.m) {
                bullet("1.circle.fill", "One thing at a time", "Today shows your single best next step, not a wall of everything.")
                bullet("sparkles", "Keel does the prep", "Replies drafted, your day balanced, inbox sorted. You approve with a tap.")
                bullet("lock.shield.fill", "Private by design", "AI runs on your iPhone with Apple Intelligence. Keel has no servers of its own.")
            }
        }
    }

    private func bullet(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            Image(systemName: icon).font(.title3).foregroundStyle(DS.Palette.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DS.Font.headline)
                Text(text).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
        }
    }

    private var email: some View {
        VStack(spacing: DS.Space.l) {
            hero("envelope.badge.fill", .blue, "Bring in your email", "Gmail, Outlook, iCloud, Yahoo, AOL or any other account. Keel sorts it, finds what needs you and clears the noise.")
            Button { showMail = true } label: {
                Label(accounts.isEmpty ? "Connect an account" : "Add another account", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.large).tint(DS.Palette.accent)
            ForEach(accounts) { a in
                Label("\(a.provider.displayName) · \(a.address)", systemImage: "checkmark.circle.fill").foregroundStyle(DS.Palette.calm).font(DS.Font.caption)
            }
        }
    }

    private var permissions: some View {
        VStack(spacing: DS.Space.l) {
            hero("calendar.badge.checkmark", .red, "Your calendar and reminders", "Keel shows every calendar on this iPhone and syncs Reminders both ways. Notifications keep tasks, meds and focus on track.")
            Button {
                Task { await CalendarService.shared.requestAccess(); calendarAllowed = CalendarService.shared.hasCalendarAccess }
            } label: {
                Label(calendarAllowed ? "Calendars & Reminders allowed" : "Allow Calendars & Reminders", systemImage: calendarAllowed ? "checkmark.circle.fill" : "calendar").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.large).tint(calendarAllowed ? DS.Palette.calm : DS.Palette.accent)
            Button {
                Task { notificationsAllowed = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false }
            } label: {
                Label(notificationsAllowed ? "Notifications allowed" : "Allow notifications", systemImage: notificationsAllowed ? "checkmark.circle.fill" : "bell.badge").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.large).tint(notificationsAllowed ? DS.Palette.calm : DS.Palette.accent)
        }
        .task { calendarAllowed = CalendarService.shared.hasCalendarAccess }
    }

    private var today: some View {
        VStack(spacing: DS.Space.l) {
            hero("sun.max.fill", .orange, "How should Today feel?", "You can change this any time from Customize Today.")
            ForEach([("minimal", "Minimal", "Just one thing, up next and who needs you."),
                     ("balanced", "Balanced", "Plus your plan, meds, check-in and what Keel prepared."),
                     ("everything", "Everything", "Every card: packages, trips, promises, people and more.")], id: \.0) { option in
                Button { todayStyle = option.0; Haptics.tap() } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.1).font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                            Text(option.2).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        Image(systemName: todayStyle == option.0 ? "checkmark.circle.fill" : "circle").foregroundStyle(DS.Palette.accent)
                    }
                    .padding(DS.Space.m)
                    .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.chip))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var you: some View {
        VStack(spacing: DS.Space.l) {
            hero("brain.fill", .pink, "Teach Keel about you", "Optional. It makes plans, drafts and answers feel like yours. Stays on this iPhone.")
            VStack(spacing: DS.Space.s) {
                TextField("What should Keel call you?", text: $name).textFieldStyle(.roundedBorder)
                Picker("I focus best in the", selection: $focusTime) {
                    Text("Not sure").tag(""); Text("Morning").tag("morning"); Text("Afternoon").tag("afternoon"); Text("Evening").tag("evening")
                }
                .pickerStyle(.segmented)
                TextField("Anything else? (e.g. I work from home, my kids are Leo and Mia)", text: $aboutMe, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Button { showMeds = true } label: { Label("Add medications", systemImage: "pills") }.buttonStyle(.bordered)
                Button { showHabits = true } label: { Label("Pick a habit", systemImage: "link") }.buttonStyle(.bordered)
            }
            .font(DS.Font.caption)
        }
    }

    private var ownClaude: some View {
        VStack(spacing: DS.Space.l) {
            hero("sparkles", .orange, "Use your own Claude", "Optional. Keel's AI already works for free on this device. Add your own Claude key for smarter plans, drafts and meeting notes.")
            VStack(alignment: .leading, spacing: DS.Space.m) {
                bullet("iphone", "Free without a key", "Apple Intelligence runs on your device. Nothing to set up, nothing to pay.")
                bullet("key.fill", "Your key, your bill", "With a Claude API key, requests go straight from your device to Anthropic, which bills you per use. Most people spend a few dollars a month.")
                bullet("exclamationmark.circle", "Not the same as Claude Pro", "A Claude Pro or Max chat subscription can't be connected to other apps. You need an API key from the Anthropic Console, with a payment method added there.")
            }
            if keyOK {
                Label("Claude is connected", systemImage: "checkmark.circle.fill").font(DS.Font.headline).foregroundStyle(DS.Palette.calm)
            } else if KeelServer.isConfigured {
                Label("Claude is already set up through your Keel server", systemImage: "checkmark.circle.fill").font(DS.Font.caption).foregroundStyle(DS.Palette.calm)
            } else {
                VStack(spacing: DS.Space.s) {
                    if let page = AIProvider.claude.keyPage {
                        Link(destination: page) {
                            Label("1. Get a key from Anthropic", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).controlSize(.large)
                    }
                    SecureField("2. Paste your key (starts with sk-ant-)", text: $claudeKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                    Button { Task { await saveClaudeKey() } } label: {
                        Label(keyTesting ? "Checking…" : "3. Connect Claude", systemImage: "link").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).tint(DS.Palette.accent)
                    .disabled(claudeKey.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 || keyTesting)
                    if let keyResult {
                        Text(keyResult).font(DS.Font.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                    }
                    Text("The key is stored only in this device's Keychain. Change or remove it any time in Settings → AI & Privacy.")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).multilineTextAlignment(.center)
                }
            }
        }
    }

    private func saveClaudeKey() async {
        keyTesting = true; defer { keyTesting = false }
        let key = claudeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = await DirectAI.test(.claude, key: key, model: AIProvider.claude.defaultModel) {
            keyResult = error
            Haptics.tap()
        } else {
            KeychainStore.save(key, for: AIProvider.claude.keychainKey)
            UserDefaults.standard.set(AIProvider.claude.rawValue, forKey: "ai.provider")
            claudeKey = ""
            keyResult = nil
            withAnimation(DS.spring) { keyOK = true }
            Haptics.success()
        }
    }

    private var bringStuff: some View {
        VStack(spacing: DS.Space.l) {
            hero("square.and.arrow.down.on.square.fill", .teal, "Bring your stuff", "Move in everything at once. You can also do this any time from Settings → Data & Storage.")
            Button { showImport = true } label: {
                Label("Import notes and tasks", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.large).tint(DS.Palette.accent)
            VStack(alignment: .leading, spacing: DS.Space.m) {
                bullet("doc.richtext", "Notes", "Notion (sign in, or an export), Obsidian, Evernote, Google Keep, Apple Notes and Bear, with folders, links and databases.")
                bullet("checklist", "Tasks", "Apple Reminders syncs both ways by itself. Todoist and other apps come in from a CSV export.")
                bullet("envelope.fill", "Mail and calendar", "Your accounts from the email step, and every calendar on this device, already show up.")
            }
        }
    }

    private var discover: some View {
        VStack(spacing: DS.Space.l) {
            hero("square.grid.2x2.fill", .purple, "A few things Keel can do", "Tap any of them to take a look. Nothing here needs setting up now.")
            DiscoverList { tryTool = ToolRoute(id: $0) }
        }
    }

    private var finished: some View {
        VStack(spacing: DS.Space.l) {
            hero("checkmark.seal.fill", DS.Palette.calm, "You're all set", "A few things to try first:")
            VStack(alignment: .leading, spacing: DS.Space.m) {
                bullet("lifepreserver", "Feeling overwhelmed?", "Tap the lifebuoy on Today for a one-minute reset.")
                bullet("brain.head.profile", "Brain dump", "Get everything out of your head; Keel sorts it into tasks, events and notes.")
                bullet("square.grid.2x2", "Everything", "Every feature lives behind ⊞ on Today. How Keel works explains them all.")
            }
        }
    }

    private func next() {
        if step == 3 { applyTodayStyle() }
        if step == 4 { saveAboutMe() }
        if step < steps - 1 { withAnimation(DS.spring) { step += 1 } } else { finish() }
    }

    private func applyTodayStyle() {
        let keep: Set<TodayCard>
        switch todayStyle {
        case "minimal": keep = [.oneThing, .upNext, .needsYou, .meds]
        case "everything": keep = Set(TodayCard.allCases)
        default: keep = [.autopilot, .meds, .planRitual, .checkIn, .energy, .oneThing, .aiPlan, .upNext, .needsYou, .pinned, .dayReview, .weeklyReview]
        }
        UserDefaults.standard.set(TodayCard.allCases.filter { !keep.contains($0) }.map(\.rawValue).joined(separator: ","), forKey: TodayCard.hiddenKey)
    }

    private func saveAboutMe() {
        let n = name.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { KeelMemory.shared.add("Call me \(n)") }
        if !focusTime.isEmpty { KeelMemory.shared.add("I focus best in the \(focusTime)") }
        let extra = aboutMe.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { KeelMemory.shared.add(extra) }
    }

    private func finish() {
        done = true
        UserDefaults.standard.set(Discover.version, forKey: Discover.seenKey)   // they just saw it in the tour
        Haptics.success()
        dismiss()
    }
}
