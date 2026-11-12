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

    private let steps = 6

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
            hero("sailboat.fill", DS.Palette.accent, "Welcome to Keel", "Email, calendar, tasks, notes and habits in one calm place, built for busy brains.")
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
        Haptics.success()
        dismiss()
    }
}
