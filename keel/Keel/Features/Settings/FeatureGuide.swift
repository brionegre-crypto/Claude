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
                            "🧠 Brain dump: ramble or dictate everything in your head. Apple Intelligence sorts it into tasks with dates, calendar events, notes and a worry list, and you review before saving."]),
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
                            "Long-press a habit → Complete from Apple Health to tick it off automatically when you hit your steps, exercise or mindful minutes.",
                            "Turn on Break Reminders in Settings → Focus for quiet nudges to stand, drink water and rest your eyes. They skip focus sessions.",
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
                            "See everyone you're waiting on under Inbox → Awaiting reply.",
                            "Send later: hold the send button to pick a time. See and change scheduled emails with the clock icon in Inbox.",
                            "Smart replies: important emails show ✨ reply ideas written for that message. Tap one and Keel drafts it.",
                            "Rules: long-press an email → Create Rule to auto-archive, star, file or turn future mail into tasks. Manage them in Settings → Mail → Rules."]),
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
        GuideSection(icon: "wand.and.stars", color: .orange, title: "Auto-schedule & focus rounds",
                     summary: "Let Keel find time for your tasks, then work in rounds.",
                     tips: ["Tap Auto-schedule (Today or Tasks) to fit today's tasks into the gaps in your calendar.",
                            "Turn on Focus rounds for short breaks between rounds and a longer one every fourth.",
                            "Add Keel Capture and Keel Focus to Control Center or the Action button."]),
        GuideSection(icon: "person.crop.circle.badge.questionmark", color: .blue, title: "Screener & keep in touch",
                     summary: "Protect your inbox, and protect your relationships.",
                     tips: ["New senders wait in Inbox → Screener until you let them in or block them.",
                            "Add the people who matter in Keep in touch (⊞ menu). Keel nudges you when it's been too long.",
                            "Call, text or email them in one tap from the reminder."]),
        GuideSection(icon: "face.smiling", color: .pink, title: "Daily check-in",
                     summary: "Ten seconds on how you feel, and one good thing.",
                     tips: ["Tap a face on Today and pick your energy. With Health connected, last night's sleep is saved too.",
                            "Today → ⊞ → Mood journal: mood, energy and sleep over time, every highlight, and patterns like “better mood after 7+ hours of sleep”."]),
        GuideSection(icon: "list.bullet.clipboard", color: .green, title: "Plan your day",
                     summary: "A 3-minute morning ritual that fits your day to your time.",
                     tips: ["Each morning Today offers Plan your day: decide what to do with yesterday's leftovers, tick today's tasks, then see them against the free time you really have.",
                            "If you've planned more than fits, Keel says so before the day does. Then time-block it all onto your calendar in one tap.",
                            "Calm mode (Today → ⊞ or Settings → Appearance) shows only your next thing and what's coming up, with no counts or red overdue dates."]),
        GuideSection(icon: "text.book.closed.fill", color: .indigo, title: "Reading, translation & backup",
                     summary: "Easier reading, any language, and your data safe.",
                     tips: ["In an email's ⋯ menu, Reading mode shows bigger, spaced text and can bold the start of each word to help your eyes keep their place.",
                            "Translate any email on your iPhone, in any language Apple supports.",
                            "Ask Keel now knows your notes, trips, packages, subscriptions, weather, habits, focus time and mood: “When's my flight?”, “What did I write about the budget?”",
                            "Weekly review starts with a short, kind note about your week, written on your iPhone.",
                            "Settings → Data & Storage → Back Up Now saves everything to Files or iCloud Drive. Restore picks a backup and finishes the next time you open Keel.",
                            "Siri: “Brain dump in Keel” to say everything on your mind, and “Plan my day in Keel”."]),
        GuideSection(icon: "calendar.day.timeline.left", color: .teal, title: "Plan the week & statistics",
                     summary: "See the whole week and how you're really doing.",
                     tips: ["Tasks → wand → Plan the week: drag tasks onto days and watch each day's load against its free time.",
                            "Smart lists: tap + Smart list in Tasks to save a filter like “High priority, due this week, #work”.",
                            "Tasks → wand → Statistics: tasks done per day, your streak, your most productive hour and how your estimates compare.",
                            "Tasks → wand → Manage tags: rename, merge or remove tags everywhere.",
                            "In a note's ⋯ menu, Save as Template. New notes can start from it; {{date}} fills in today's date.",
                            "Lock Screen widgets: your next medication dose and today's momentum."]),
        GuideSection(icon: "lock.square.stack", color: .orange, title: "Task power tools",
                     summary: "Dependencies, attachments and smarter repeats.",
                     tips: ["Blocked By: a task waits for another to finish. It won't be suggested or scheduled until then, and Keel tells you when it's unblocked.",
                            "Attach photos and files to any task: receipts, forms, screenshots.",
                            "Custom repeat → Count From When I Finish: “every 2 weeks” starts from the day you actually did it.",
                            "Calendar → filter menu: World clock with a time converter, Shared calendars and Event templates. Use templates from + → From template."]),
        GuideSection(icon: "airplane", color: .blue, title: "Trips & catch up",
                     summary: "Travel plans and a clear inbox, sorted for you.",
                     tips: ["Flight, hotel, car, train and restaurant confirmations in your email become Trips (Inbox → ⋯ → Trips). Add any booking to Calendar in one tap; flights get a 3-hour alert.",
                            "Today shows your next booking with its confirmation code.",
                            "Inbox → ✨ Catch me up: Apple Intelligence explains your unread mail by who needs what, and clears the noise in one tap.",
                            "Inbox → ⋯ → Attachments: every file you've been sent, searchable by name.",
                            "Each mail account can have its own signature (Settings → Mail Accounts)."]),
        GuideSection(icon: "shippingbox.fill", color: .brown, title: "Found in your email",
                     summary: "Subscriptions, bills and packages, without lifting a finger.",
                     tips: ["Today → ⊞ → Subscriptions & bills: everything you pay for, found in receipts, with a monthly total. Keel reminds you 2 days before a renewal or bill.",
                            "Today → ⊞ → Deliveries: packages from shipping emails, with one-tap tracking. Today shows what's arriving.",
                            "Long-press an email → Pin to Top to keep it above everything in Inbox.",
                            "In any task, tap Start to time it. Keel adds the minutes to the task and your Time audit."]),
        GuideSection(icon: "lock.fill", color: .gray, title: "Privacy lock",
                     summary: "Keep Keel and private notes behind Face ID.",
                     tips: ["Settings → AI & Privacy → Require Face ID. Keel locks when you leave and blurs itself in the app switcher.",
                            "Lock a single note from its ⋯ menu. Locked notes are hidden from search, iPhone search and AI.",
                            "Export any note as Markdown or PDF from the same menu."]),
        GuideSection(icon: "sun.horizon.fill", color: .orange, title: "Morning briefing & meeting prep",
                     summary: "Know the shape of your day before it starts.",
                     tips: ["Every morning a notification sums up your first event, top tasks, meds, important email and weather. Set the time in Settings → Notifications.",
                            "Meetings with attendees show Prep on Today: recent emails with those people, promises you made them, related tasks and notes, and a one-tap AI brief.",
                            "Keel also nudges you 10 minutes before a meeting that has something to prep."]),
        GuideSection(icon: "square.grid.2x2.fill", color: .blue, title: "Interactive widgets",
                     summary: "Get things done from your Home Screen.",
                     tips: ["Add the Today's Tasks widget and tap a circle to complete a task without opening Keel.",
                            "The Habits widget lets you tick off today's habits with one tap."]),
        GuideSection(icon: "pills.fill", color: .mint, title: "Medications",
                     summary: "Never wonder “did I already take it?” again.",
                     tips: ["Today → ⊞ → Medications: add each med, its dose and times. Reminders have a Taken button right on the notification.",
                            "Forgot to tap it? Keel nudges you once more 30 minutes later.",
                            "Ask Siri “Did I take my meds in Keel?” or log a dose from Apple Watch.",
                            "Turn on Count pills to get a refill reminder before you run out."]),
        GuideSection(icon: "trophy.fill", color: .orange, title: "Momentum & achievements",
                     summary: "A kind score that celebrates progress.",
                     tips: ["Today → ⊞ → Achievements: your daily momentum from tasks, focus, habits and your check-in. It only goes up.",
                            "Unlock achievements for focus hours, habit streaks, inbox zero days and more."]),
        GuideSection(icon: "car.fill", color: .red, title: "Time to leave & pinned tasks",
                     summary: "Get out the door on time, keep key tasks in sight.",
                     tips: ["For events with an address, Keel checks Apple Maps travel time and alerts you when to leave. Up next on Today shows “Leave by”. Change car, transit or walking in Settings → Calendars.",
                            "Long-press a task → Pin to keep it at the top of Tasks and Today. Duplicate copies it with all its details."]),
        GuideSection(icon: "cloud.sun.fill", color: .cyan, title: "Weather & focus history",
                     summary: "Plan around the sky and see when you focus best.",
                     tips: ["Today shows the weather under the greeting, and Plan my day puts outdoor tasks in the dry, warmer hours. Data from Apple Weather.",
                            "Today → ⊞ → Focus history: 30 days of focus time, your average session, best day and best hour."]),
        GuideSection(icon: "person.3.fill", color: .green, title: "Shared calendars & habit library",
                     summary: "Coordinate with family and start habits in one tap.",
                     tips: ["Today → ⊞ → Shared calendars: pick family or shared calendars, see each one's day, and find when everyone's free.",
                            "Habits → library icon: ready-made stacks like Morning launch, Shutdown ritual and Wind down."]),
        GuideSection(icon: "applewatch", color: .gray, title: "Apple Watch",
                     summary: "Keel on your wrist.",
                     tips: ["Your one thing, energy and a mood check-in right on the home screen.",
                            "Today's tasks (swipe for tomorrow), calendar, important email (swipe to archive) and habits.",
                            "Ask Keel by voice; your iPhone answers with Apple Intelligence.",
                            "Focus timer, Keep in touch with one-tap call or text, promises, follow-ups, countdowns and Day in review.",
                            "Weather on the home screen, a 7-day focus chart, and your mood week.",
                            "Log medication with a tap and check today's momentum score.",
                            "Your morning briefing appears on the home screen until 11 AM.",
                            "Your next trip shows on the home screen, and Inbox shows how many emails are unread.",
                            "Momentum shows tasks done this week and your streak.",
                            "Ask Keel has one-tap questions: meds, packages, trips and your week.",
                            "World clock for your saved cities. Calm mode on your iPhone simplifies the watch home screen too.",
                            "Capture → Brain dump: ramble into your watch and your iPhone sorts it. Deliveries and your subscriptions total are on the home screen.",
                            "Complications: one thing, next event, tasks left and countdown."]),
        GuideSection(icon: "app.connected.to.app.below.fill", color: .indigo, title: "Connected apps",
                     summary: "Bring in what matters from the rest of your iPhone.",
                     tips: ["Settings → Connected Apps shows every connection and sets them up in one tap.",
                            "Share any note, message, photo or link → Keel. Links go to Read later, everything else to Notes.",
                            "Tasks from screenshots: Keel reads recent screenshots on your iPhone and suggests tasks.",
                            "Health: last night's sleep suggests today's energy. Contacts: birthdays become countdowns.",
                            "Shortcuts can import Apple Notes or turn incoming messages into tasks, with your permission."]),
        GuideSection(icon: "folder.fill", color: .blue, title: "Projects & sorting",
                     summary: "Big outcomes, broken down; loose ends, sorted.",
                     tips: ["Projects (Tasks toolbar or ⊞ menu): milestones, a deadline, progress and a board view.",
                            "Sort (tray icon in Tasks): decide on loose tasks one at a time: do now, today, a date, waiting, someday or delete.",
                            "During focus, park distracting thoughts in one tap; sort them afterwards.",
                            "Someday keeps nice-to-have ideas out of today's lists."]),
        GuideSection(icon: "link", color: .yellow, title: "Linked & daily notes",
                     summary: "Connect your thinking.",
                     tips: ["Type [[Note name]] to link notes; each note shows its links and what links to it.",
                            "Notes → ✎ → Today's note opens a daily page with today's events."]),
        GuideSection(icon: "text.badge.plus", color: .blue, title: "Snippets & digest",
                     summary: "Faster email, calmer inbox.",
                     tips: ["Insert saved replies while writing (the ⊕ text button), and edit them in Settings → Mail → Snippets.",
                            "Inbox → 📰 Digest: today's newsletters summarized together, then archive them all."]),
        GuideSection(icon: "paintpalette.fill", color: .pink, title: "Make it yours",
                     summary: "Choose your app icon and accent color.",
                     tips: ["Settings → Appearance: five app icons and six accent colors."]),
        GuideSection(icon: "hourglass", color: .teal, title: "Countdowns, boards & undo",
                     summary: "Little things that make a big difference.",
                     tips: ["Countdowns (⊞ menu) for trips and launches, plus a Home Screen widget.",
                            "Tasks → wand menu → Show as board: drag cards between To do, Doing and Done.",
                            "Deleted a task or archived an email by mistake? Tap Undo.",
                            "Notes take photos, sketches and scanned documents, and scanned text is searchable.",
                            "Focus sounds: brown, pink or white noise, or ocean waves, made on your iPhone.",
                            "Monthly review (⊞ menu): the month at a glance, mood, goals and a short reflection."]),
        GuideSection(icon: "magnifyingglass", color: .gray, title: "Search, templates & places",
                     summary: "Find anything, reuse checklists, and get reminded in the right place.",
                     tips: ["Tap 🔍 on Today to search tasks, notes, email, events, links, goals and people. Keel tasks and notes also appear in iPhone search.",
                            "Search understands plain English: “emails from sam last week”, “overdue tasks”, “unread with attachments”. Press Search to let Apple Intelligence read trickier requests.",
                            "Tasks → wand menu → Templates: reusable checklists like a packing list or weekly reset.",
                            "In a task, tap Location to be reminded when you arrive at or leave a place.",
                            "Calendar → + → Quick event: “Lunch with Sam Thu 1pm for 90 min”.",
                            "In the evening, Today shows Day in review: see what you did and set up tomorrow."]),
        GuideSection(icon: "sparkles", color: .cyan, title: "AI & privacy",
                     summary: "Keel's AI runs on your iPhone with Apple Intelligence. It's free and private.",
                     tips: ["Prefer Claude, ChatGPT or Gemini? Add your own API key in Settings → AI & Privacy (billed by that provider).",
                            "Turn it on in iPhone Settings → Apple Intelligence & Siri.",
                            "Writing Tools (rewrite, proofread) work in every text box.",
                            "Siri: “Add a task in Keel”, “What should I do now in Keel”, “Brain dump in Keel”, “Did I take my meds in Keel”. Ask Keel can still tell you your promises and next meeting."]),
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
