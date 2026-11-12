import SwiftUI
import UserNotifications

/// What Keel can do, explained in plain language. Shown as a welcome tour on first launch,
/// and anytime from Settings → How Keel works.
struct GuideSection: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let summary: String
    let tips: [String]
}

enum Guide {
    static let sections: [GuideSection] = [
        GuideSection(icon: "sun.max.fill", color: .orange, title: "Today",
                     summary: "Your day on one screen, with one clear next step.",
                     tips: ["“Just One Thing” picks your best next task from your energy, deadlines and free time.",
                            "Set your energy (Low battery / Steady / Locked in) and the suggestion adapts.",
                            "“Plan my day” builds a time-blocked plan with Apple Intelligence.",
                            "“Reset my day” moves overdue tasks to tomorrow with no guilt.",
                            "🧠 Brain dump: empty your head, one thing per line, and Keel turns it into tasks."]),
        GuideSection(icon: "tray.full.fill", color: DS.Palette.accent, title: "Inbox",
                     summary: "Gmail, Outlook and iCloud in one inbox, sorted by AI.",
                     tips: ["Mail is sorted into Important, Actionable, Calendar, Updates, Newsletters and Promotions.",
                            "Swipe right: make a task, snooze, or star. Swipe left: done or trash.",
                            "Tap a reply chip (“Yes, sounds good”) and AI drafts the reply for you.",
                            "Tracking images are blocked until you tap “Load images”.",
                            "Search finds mail on your phone; press Search to look through all your mail.",
                            "Sending gives you 5 seconds to undo."]),
        GuideSection(icon: "calendar", color: .teal, title: "Calendar",
                     summary: "Every calendar on your iPhone, with your tasks alongside.",
                     tips: ["Shows Apple Calendar, Google, Outlook and every other calendar on this iPhone; edits sync both ways.",
                            "Tap an empty time to add an event. Long-press and drag to move one.",
                            "Tasks with a time appear as pills; tap the circle to complete them.",
                            "Use the filter button to choose calendars or hide tasks."]),
        GuideSection(icon: "checklist", color: .green, title: "Tasks",
                     summary: "Smart tasks that sync both ways with Apple Reminders.",
                     tips: ["Type naturally: “Gym every Mon 7am !high #health ~Personal”.",
                            "Repeating tasks move to their next date when you check them off.",
                            "Alerts have Complete and Snooze buttons right on the notification.",
                            "“Break into tiny steps” turns a big task into 2–10 minute steps.",
                            "Smart lists: Today, Next 7 Days, Inbox, Matrix (what's urgent vs important), Completed.",
                            "Changes in Apple Reminders show up in Keel within seconds, and the other way round."]),
        GuideSection(icon: "hand.raised.fingers.spread.fill", color: .pink, title: "Promises",
                     summary: "Keel remembers what you promised people in email.",
                     tips: ["When you write “I'll send it Friday”, Keel tracks it for you.",
                            "Find them under Tasks → ✋, or on Today when one is due.",
                            "Tap a promise for a one-tap follow-up email."]),
        GuideSection(icon: "note.text", color: .yellow, title: "Notes",
                     summary: "Flexible pages with checklists, headings and quotes.",
                     tips: ["Type /todo, /h, /quote or /- at the start of a line.",
                            "“Meeting notes for next event” fills in the time and attendees.",
                            "Turn a note's to-dos into real tasks in one tap."]),
        GuideSection(icon: "link", color: .purple, title: "Habit stacks",
                     summary: "Tiny habits chained to things you already do.",
                     tips: ["“After I pour my coffee → take meds → drink water.”",
                            "Stacks can start after a calendar event ends, like your standup.",
                            "Missed a day? Grace days (◇) keep your streak alive."]),
        GuideSection(icon: "moon.zzz.fill", color: .indigo, title: "Focus & shutdown",
                     summary: "Protected time for deep work, and a clean end to your day.",
                     tips: ["Tap the Focus bar above the tabs to start a session.",
                            "Soft hides your inbox; Shield and Locked can also block distracting apps.",
                            "You get a heads-up 5 minutes before the end, and a check-in if you hyperfocus past it.",
                            "The Shutdown ritual closes open loops so your brain can rest."]),
        GuideSection(icon: "target", color: .red, title: "Goals & life areas",
                     summary: "A theme for your year, and a few goals for each part of your life.",
                     tips: ["Open Goals from the ⊞ menu on Today.",
                            "Write why each goal matters; Keel shows it on that goal's tasks when motivation dips.",
                            "Link tasks to a goal and watch its ring fill up."]),
        GuideSection(icon: "chart.bar.doc.horizontal", color: .purple, title: "Weekly review",
                     summary: "Ten minutes on Sunday to look back and plan ahead.",
                     tips: ["See tasks done, hours focused, habit check-ins and promises kept.",
                            "Rate how tasks felt (🎈 play, 💪 power, 🤝 people, 🪫 drained) to learn what gives you energy.",
                            "Your top 3 for next week become Monday tasks automatically."]),
        GuideSection(icon: "bubble.left.and.text.bubble.right.fill", color: .mint, title: "Ask Keel & Siri",
                     summary: "Talk to Keel in plain language. It can look things up and take action.",
                     tips: ["Open Ask Keel from the ⊞ menu on Today, or say “Hey Siri, ask Keel …”.",
                            "Try: “What's on today?”, “Add call the bank tomorrow 10am”, “Start a 25 minute focus”.",
                            "Siri also knows: “Complete Gym in Keel”, “Check my inbox in Keel”, “What's next on my calendar in Keel”."]),
        GuideSection(icon: "rectangle.3.group.fill", color: .blue, title: "Widgets & Live Activity",
                     summary: "Keel on your Home Screen and Lock Screen.",
                     tips: ["Long-press the Home Screen → Edit → Add Widget → Keel.",
                            "“Just One Thing” and “Next Event” come in Home and Lock Screen sizes.",
                            "During focus, a countdown appears on the Lock Screen and in the Dynamic Island."]),
        GuideSection(icon: "envelope.badge.shield.half.filled", color: .orange, title: "Smarter email",
                     summary: "Spend less time in your inbox.",
                     tips: ["Unsubscribe from a newsletter in one tap; Keel archives everything it already sent you.",
                            "When sending, choose “Remind me if no reply”. If they don't answer, Keel nudges you to follow up.",
                            "See everyone you're waiting on under Inbox → Awaiting reply."]),
        GuideSection(icon: "chart.pie.fill", color: .green, title: "Time audit & ideal week",
                     summary: "See where your hours really go, and design the week you want.",
                     tips: ["Start a timer from Time audit, or let Keel count your focus sessions and calendar events.",
                            "Sketch your ideal week (deep work, workouts, family time) and compare it with reality.",
                            "“Plan my day” follows your ideal week where your calendar allows.",
                            "Block your ideal week onto your calendar in one tap."]),
        GuideSection(icon: "mic.fill", color: .red, title: "Meeting notes",
                     summary: "Record a meeting and get notes that write themselves.",
                     tips: ["Notes → ✎ → Record a meeting, or from the ⊞ menu on Today.",
                            "The transcript appears live and stays on your iPhone.",
                            "Keel writes a summary, decisions and action items, and can turn the actions into tasks."]),
        GuideSection(icon: "books.vertical.fill", color: .brown, title: "Read later",
                     summary: "Save articles for when you have the energy.",
                     tips: ["In Safari, tap Share → Keel. Or paste a link in Read later.",
                            "Each link gets a short on-device summary, so you can decide what's worth your time.",
                            "Articles open in a clean reader view."]),
        GuideSection(icon: "point.3.filled.connected.trianglepath.dotted", color: .indigo, title: "Odyssey plan",
                     summary: "Imagine three different five-year futures.",
                     tips: ["Life as planned, Plan B, and a Wild card where money and opinions don't matter.",
                            "Rate each for resources, how much you like it, confidence and fit.",
                            "Compare them side by side, then try one small experiment."]),
        GuideSection(icon: "applewatch", color: .gray, title: "Apple Watch",
                     summary: "Keel on your wrist.",
                     tips: ["See your one thing and next event at a glance.",
                            "Check off tasks and habits with a tap; your iPhone updates too.",
                            "Start or end a focus session, and add tasks by voice."]),
        GuideSection(icon: "sparkles", color: .cyan, title: "AI & privacy",
                     summary: "Keel's AI runs on your iPhone with Apple Intelligence. It's free and private.",
                     tips: ["Prefer Claude, ChatGPT or Gemini? Add your own API key in Settings → AI & Privacy (billed by that provider).",
                            "Turn it on in iPhone Settings → Apple Intelligence & Siri.",
                            "Writing Tools (rewrite, proofread) work in every text box.",
                            "Siri: “Add a task in Keel”, “What should I do now in Keel”, “What did I promise in Keel”."]),
    ]
}

/// Settings → How Keel works
struct FeatureGuideView: View {
    var body: some View {
        List {
            ForEach(Guide.sections) { s in
                Section {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Label { Text(s.title).font(DS.Font.title) } icon: {
                            Image(systemName: s.icon).foregroundStyle(s.color)
                        }
                        Text(s.summary).font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
                    }
                    .padding(.vertical, DS.Space.xs)
                    ForEach(s.tips, id: \.self) { tip in
                        Label { Text(tip).font(DS.Font.body) } icon: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(s.color.opacity(0.8))
                        }
                    }
                }
            }
        }
        .navigationTitle("How Keel works")
    }
}

/// First-launch welcome tour.
struct WelcomeTour: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboarding.done") private var done = false
    @State private var page = 0

    private let pages: [GuideSection] = [
        GuideSection(icon: "sailboat.fill", color: DS.Palette.accent, title: "Welcome to Keel",
                     summary: "Your email, calendar, tasks, notes and habits in one calm place, built for brains with a lot going on.", tips: []),
    ] + Guide.sections.prefix(6)

    var body: some View {
        VStack(spacing: DS.Space.l) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { i, p in
                    VStack(spacing: DS.Space.l) {
                        Spacer()
                        Image(systemName: p.icon)
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundStyle(p.color.gradient)
                            .frame(width: 120, height: 120)
                            .glassEffect(.regular.tint(p.color.opacity(0.2)), in: .rect(cornerRadius: 32))
                        Text(p.title).font(DS.Font.hero).multilineTextAlignment(.center)
                        Text(p.summary).font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
                            .multilineTextAlignment(.center).padding(.horizontal, DS.Space.l)
                        if let tip = p.tips.first {
                            Text(tip).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                                .multilineTextAlignment(.center).padding(.horizontal, DS.Space.xl)
                        }
                        Spacer()
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pages.count - 1 { withAnimation(DS.spring) { page += 1 } } else { finish() }
            } label: {
                Text(page < pages.count - 1 ? "Next" : "Get started")
                    .font(DS.Font.headline).frame(maxWidth: .infinity).padding(.vertical, DS.Space.m)
                    .background(DS.Palette.accent, in: Capsule()).foregroundStyle(.white)
            }
            .padding(.horizontal, DS.Space.l)
            Button("Skip") { finish() }.font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                .padding(.bottom, DS.Space.m)
        }
        .background(DS.Palette.canvas)
    }

    private func finish() {
        done = true
        Haptics.success()
        dismiss()
    }
}

/// Settings row: shows whether alerts are on, and fixes it in one tap.
struct NotificationStatusRow: View {
    @State private var status: UNAuthorizationStatus = .notDetermined
    @Environment(\.scenePhase) private var phase

    var body: some View {
        HStack {
            Label("Notifications", systemImage: "bell.badge")
            Spacer()
            switch status {
            case .authorized, .provisional, .ephemeral:
                Text("On").foregroundStyle(DS.Palette.calm)
            case .denied:
                Button("Turn on") { openSettings() }
            default:
                Button("Allow") {
                    Task {
                        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                        await refresh()
                    }
                }
            }
        }
        .task { await refresh() }
        .onChange(of: phase) { if phase == .active { Task { await refresh() } } }
    }

    private func refresh() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
    }
}
