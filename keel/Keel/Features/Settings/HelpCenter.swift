import SwiftUI

/// "How do I…": short, step-by-step answers for every part of Keel, searchable in your own words.
/// Open it from Settings → Help, Today → ⊞ → Help, or the ? button in Notes.
struct HowTo: Identifiable, Hashable {
    let id: String
    let area: HelpArea
    let question: String
    let steps: [String]
    var tip: String? = nil
    var keywords: String = ""
}

enum HelpArea: String, CaseIterable, Identifiable {
    case start, today, inbox, calendar, tasks, notes, meetings, focus, health, ai, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .start: "Getting started"; case .today: "Today & Compass"; case .inbox: "Email"; case .calendar: "Calendar"
        case .tasks: "Tasks & reminders"; case .notes: "Notes"; case .meetings: "Meeting notes"; case .focus: "Focus & routines"
        case .health: "Food, meds & health"; case .ai: "AI & privacy"; case .settings: "Settings & Apple Watch"
        }
    }
    var icon: String {
        switch self {
        case .start: "sparkles"; case .today: "sun.max.fill"; case .inbox: "tray.fill"; case .calendar: "calendar"
        case .tasks: "checklist"; case .notes: "note.text"; case .meetings: "waveform.badge.mic"; case .focus: "moon.zzz.fill"
        case .health: "fork.knife"; case .ai: "brain.head.profile"; case .settings: "gearshape.fill"
        }
    }
    var color: Color {
        switch self {
        case .start: .indigo; case .today: .orange; case .inbox: .blue; case .calendar: .red; case .tasks: .green
        case .notes: .yellow; case .meetings: .pink; case .focus: .purple; case .health: .mint; case .ai: .teal; case .settings: .gray
        }
    }
}

enum HelpLibrary {
    static let all: [HowTo] = [
        // Getting started
        HowTo(id: "bodyhome", area: .health, question: "Find all my health tools (medications, food, body map…)",
              steps: ["Open Body (the card on Today, or Compass → Body & health).", "Medications are right at the top with Add medication. Below is a grid of every health screen: body map, symptoms, as-needed medicines, blood pressure, weight, food, drinks, fasting, workouts, trends, sleep sounds, medical card and a summary for your doctor."],
              keywords: "health medications meds add medicine where body food"),
        HowTo(id: "bodymap", area: .health, question: "Log where it's sore or hurts (body map)",
              steps: ["Body → Body map. Muscles you've worked in the last three days glow and fade as they recover.", "Tap a body part to log a bit sore, sore or pain. Today's workout suggestion tells you to go easy on sore areas."],
              keywords: "body map sore muscle pain injury"),
        HowTo(id: "strength", area: .health, question: "Log a strength workout",
              steps: ["Body → Effort → Strength. Start an empty workout or a routine (Push, Pull, Legs, Upper, Lower, Full body, or your own).", "Add exercises from 110+ moves (search or filter by muscle). Set weight and reps with − / +, and tick each set. A rest timer starts and notifies you.", "Hold a set to mark how hard it was (RPE). Tap the number to mark a warm-up.", "Keel suggests what to lift next time (more weight when you hit every set), spots personal records, shows hard sets per muscle this week, and muscle freshness. Finish to see your summary and save it as a routine."],
              keywords: "strength gym weights lifting sets reps routine personal record pr overload muscle"),
        HowTo(id: "buildworkout", area: .health, question: "Let Keel build today's workout",
              steps: ["Body → Effort (or Strength) → Build my workout. Set your goal (get stronger, build muscle, stay fit) and equipment (gym, dumbbells, none) with the sliders button.", "Keel picks fresh muscles that got the fewest sets this week, skips ones still recovering, sizes the session to your Tide, and lightens weights on lower days. On a low day it suggests recovery mobility instead.", "If Apple Health tracks your cycle, it adds phase-aware advice.", "Tap Start it. Warm-ups adds three ramp-up sets; Plates shows what to load on each side of the bar.", "Coach notes in Strength flag lifts that have stalled and when an easier week would help. Finished workouts save to Apple Health (turn off in Strength if your Watch already records them)."],
              keywords: "build workout generate plan deload plateau warm up plates cycle"),
        HowTo(id: "recoverydrivers", area: .health, question: "See what affects my recovery, and set body goals",
              steps: ["Body → Today → What drives your recovery compares your next-morning Tide after late workouts, caffeine after 2 PM, late meals, stressful days, late nights, short sleep, strength days and rest days. Nothing to log.", "Goals: tap + to set a target (VO₂ max, resting heart rate, sleep, HRV…). Keel shows your trend and when you'll reach it at this rate.", "If your heart rate, HRV, breathing and temperature together look like you're fighting something, Keel warns you that morning.", "Biological age has a What if… simulator and, after 8 weeks, your pace of aging."],
              keywords: "recovery drivers correlations goals target illness warning sick what if pace of aging"),
        HowTo(id: "energybank", area: .health, question: "Read the Energy bank, training load and biological age",
              steps: ["Energy bank (Body → Today): sleep charges you in the morning; stress and workouts drain it hour by hour, calm hours top it up a little. The dashed line is the forecast to bedtime.", "Training load (Body → Effort): each day's heart-rate effort plus strength work. A 7-day vs 28-day ratio of about 0.8–1.3 builds fitness safely; above 1.5 raises injury risk.", "Biological age (Body → Health): how old your body acts, from cardio fitness, heart rate, HRV, sleep, steps, weight, blood pressure and lab results, with what's moving it and the biggest win. Saved weekly."],
              keywords: "energy bank battery training load acwr fitness fatigue biological age"),
        HowTo(id: "records", area: .health, question: "Add lab results and health records",
              steps: ["Body → Health → Health records. Add a PDF, a photo, or scan a paper document.", "Keel reads it on your iPhone, writes a plain-language summary, and finds blood results like cholesterol, HbA1c, vitamin D and ferritin. Check them, then Save.", "Biology shows each result over time against the usual range. You can also type a result in.", "Records stay private on this iPhone. Lab results also sharpen your biological age."],
              keywords: "lab results blood test records biomarkers biology pdf scan cholesterol vitamin"),
        HowTo(id: "foodphoto", area: .health, question: "Log food from a photo and see my nutrition score",
              steps: ["Food → Snap meal (or Log food → Snap meal). Take the photo; Keel names each food on your iPhone and starts each at one typical portion.", "Adjust portions with + and −, untick anything wrong, or Add something it missed. With your own AI key, tap Sharper read for every item and its portion estimated from the photo (or turn on Always).", "Tap Add, then Log. The Nutrition score (0–100) rates the whole day: protein, fibre, sugar, salt, how well it fits your diet, and brain foods."],
              keywords: "food photo camera meal nutrition score quality"),
        HowTo(id: "taskduration", area: .health, question: "Change how long a task takes",
              steps: ["Open a task. Under Plan, tap a length (5 min, 10 min, 15 min…) or use − and + to fine-tune it.", "Or press and hold a task in the list and choose Duration.", "Tasks without their own length use your default, 5 minutes unless you change it in Settings → Tasks → Task length.", "After you've timed 3 tasks with Start now, Keel learns whether things take you longer than planned and plans with the real time. Turn that off with Pad times from what I've timed."],
              keywords: "duration length estimate time minutes how long 37 default"),
        HowTo(id: "teamboards", area: .health, question: "Work with a team or family on shared tasks",
              steps: ["Tasks → wand menu → Team boards (or Compass → Team boards). Sign in with Apple once, then tap New board. Private boards are invitation-only; link boards let anyone with the link edit, even in a web browser.", "Invite people: open the board → people button → choose a role and Create invitation, then share it or send it by text. They open it, sign in with Apple and join. An invitation works for up to 10 people for 7 days.", "Roles: the owner can do everything, including deleting the board and making admins. Admins invite, change roles and remove members. Members add and edit tasks and events. Viewers read, comment and chat.", "Board, Mine, Chat, Calendar and Activity tabs across the top. Swipe tasks to start, finish or take them; tap one to edit and comment with @Name.", "You get an alert straight away when someone assigns you a task, mentions you, finishes a task you made, adds a team event, or messages the board. Team events can be added to your own calendar with a swipe."],
              keywords: "team shared board collaborate assign comments mention family work project invite roles admin viewer chat calendar"),
        HowTo(id: "exerciselibrary", area: .health, question: "Find an exercise, stretch or yoga pose",
              steps: ["In a workout, tap Add exercise. Choose Strength, Cardio, Mobility or Yoga, then filter by muscle or search 700+ moves.", "Stretches and yoga are logged in seconds and cardio in minutes. They don't count toward muscle load, so your strength stats stay accurate."],
              keywords: "exercise library stretch yoga mobility cardio search"),
        HowTo(id: "texting", area: .health, question: "Text someone from Keel (Messages)",
              steps: ["Tap Text on a person (Keep in Touch or their page), on a promise, a waiting-for-reply email, a task, or an email's ⋯ menu.", "Keel opens a text with them filled in. Tap Write it for me and Keel drafts it in your usual style, or pick a quick text.", "Tap Open in Messages and press Send there. Keel never sends a text by itself, and Apple doesn't let any app read your messages.", "Running late? Use the card for your next meeting on Today, the Running late button on a meeting alert, or ask Siri: Text: I'm Running Late."],
              keywords: "text message imessage sms messages running late reply"),
        HowTo(id: "contactslink", area: .health, question: "Link people to my Contacts",
              steps: ["Open a person's page (Keep in Touch → swipe right → Page). Keel matches them to your Contacts by email or name, or tap Link to a contact.", "Linked people show their photo, and their phone, email and birthday fill in. The birthday goes into Birthdays & gifts.", "Call, Text, FaceTime and Email are one tap. Today shows who you're meeting next."],
              keywords: "contacts link photo phone call facetime birthday"),
        HowTo(id: "applemail", area: .health, question: "Send from Apple Mail instead of Keel Mail",
              steps: ["In a new email, hold the send button and choose Send from Apple Mail instead.", "Or in an email's ⋯ menu, choose Open draft in Apple Mail.", "Keel fills in the recipients, subject and text, and you send it from Apple Mail."],
              keywords: "apple mail send mailto handoff draft"),
        HowTo(id: "siriactions", area: .health, question: "Use Keel with Siri, Shortcuts and Apple Intelligence",
              steps: ["Open the Shortcuts app and tap Keel to see every action, including: Text Someone, Running Late, Who Am I Meeting Next, Call Someone, Start a Keel Timer, Add to My Top 3, What's My Top 3, Set Today's Frog, Add to My Done List, Add a Win, I Parked Here, Where Did I Park, Remember Where I Put Something, Where Did I Put It, Impulse Waiting List, Park a Worry, Save an Idea, Log a Drink, How Recovered Am I, and Tomorrow's First Step.", "Add any of them to a shortcut and give it your own phrase to say to Siri, or put it on the Action button.", "Bring in all your Apple Notes: make a shortcut with Find All Notes → Repeat with Each → Save to Keel Notes."],
              keywords: "siri shortcuts apple intelligence action button voice automation"),
        HowTo(id: "connectortools", area: .health, question: "What Claude can do with the Keel connector",
              steps: ["Read: today, tasks, notes (search or a whole note), promises, your calendar for the week, recent email (search too), Body scores, today's medications, your people and your Top 3.", "Do: add or complete tasks, create or add to notes, add calendar events, log a medication or a drink, add to Top 3, save an idea, start focus.", "Draft: emails and texts. These are never sent for you. Keel opens them on your iPhone to check and send.", "Changes reach your iPhone the next time Keel syncs. Private mode in Settings turns the connector's view of your data off."],
              keywords: "claude connector mcp tools ai assistant grok chatgpt"),
        HowTo(id: "toolkit", area: .health, question: "Use the 50 everyday tools (timers, money, mood, growth)",
              steps: ["Open Compass (the four squares on Today) and search, or browse the groups. Every tool explains itself at the top of its screen.", "Get going: Top 3, Eat the frog, Timebox list, Time estimator, Transition timer, Time chimes, Phone down, Timers, Workday left, Task roulette, What fits, Spoons, Mind sweep, Morning pages, Writing sprint, Meeting timer, Tomorrow's first step.", "Calm down: Reframe a thought, Worry time, Name the feeling, Grounding 5-4-3-2-1, Social battery, Affirmations.", "Stay on top: Where did I put it?, Parking, Returns & warranties, Impulse waiting list, No-spend days, Savings jars, Tip & split, Better deal, Chore rotation, Tidy sprint, Pet care, Counters.", "Look back: Done list, Wins jar, Three good things, Chains, Reading, Practice log. Think ahead: Theme days, If-then plans, Don't-do list, Decide for me, Experiments, Idea vault, Bucket list, Letter to future you, Life in weeks.", "Your lists follow you to your other devices through iCloud. Morning pages, writing sprints and running timers stay on this device."],
              keywords: "tools toolkit timer parking returns spoons frog top 3 morning pages chores savings reading worry feelings"),
        HowTo(id: "tabmenus", area: .health, question: "Find the extra tools on each tab",
              steps: ["Today: tap the four-squares button for Compass, or hold it for the day menu: Start the day, Stay on track, When it's hard, Close the day.", "Inbox: ⋯ has Get through it (catch up, quick replies, waiting on a reply, screen new senders), Find, Life admin and Set up.", "Calendar: the filter button has Go to today, Show, Plan, Look back and Share.", "Tasks: the wand has Schedule, Get unstuck, Bigger picture, Lists and Set up.", "Notes: hold the pencil for Create, Your second brain, Organize and Maintain.", "Body: + logs a dose, symptom, blood pressure, sore spot or fast."],
              keywords: "menu more tools options where is find button toolbar"),
        HowTo(id: "bodydash", area: .health, question: "Read my Body screen (Today, Sleep, Effort, Health, Habits)",
              steps: ["Body has five pages along the top: Today, Sleep, Effort, Health and Habits. The bar stays put as you scroll.", "Tap a day in the strip to look back at any of the last two weeks.", "Each tile shows the number, whether it's normal for you (your last 30 days), and a two-week line. Tap a tile or a score ring for its full 7, 30 or 90-day history, with your normal range shaded. Drag across the chart to see any day.", "The + menu at the top logs a dose, symptom, blood pressure, sore spot or fast, and jumps between pages."],
              keywords: "body dashboard metrics hrv resting heart rate sleep schedule trends normal range baseline"),
        HowTo(id: "logdose", area: .health, question: "Log a medication I took",
              steps: ["Body → Medications → Log a dose (also in Medications at the top).", "Pick the medication, or Something else… to type one that isn't in your list.", "Set when you took it: now, a few minutes ago, or up to 3 days back. For a scheduled medication, choose which dose it was or An extra dose.", "Log. Keel stops reminding you about that dose, counts down your pills, and shows it under Logged in the last day."],
              keywords: "log medication dose took taken record pill medicine earlier missed extra"),
        HowTo(id: "prn", area: .health, question: "Track medicine I take only when needed",
              steps: ["Body → As-needed medicines → + (for example ibuprofen, at least 4 hours apart, up to 4 a day).", "Tap Take each time. Keel warns you if it's too soon or you've reached the daily limit, and lets you know when it's OK again."],
              keywords: "as needed prn painkiller ibuprofen inhaler interval"),
        HowTo(id: "doseeffect", area: .health, question: "Track how well a medication works",
              steps: ["After taking a dose, Body asks “How's it working today?”. Tap 1 to 5.", "Keel shows your 2-week average and includes it in the summary for your doctor."],
              keywords: "medication effect rating side effects works"),
        HowTo(id: "symptoms", area: .health, question: "Log symptoms",
              steps: ["Body → Symptoms. Tap one (headache, tired, anxious…) or type your own, then how strong it is.", "See how often each happened in the last 30 days."],
              keywords: "symptoms headache migraine pain log"),
        HowTo(id: "doctor", area: .health, question: "Prepare for a doctor's appointment",
              steps: ["Body → For my doctor. Keel writes a one-page summary of the last 30 days: medications and how often you took them, symptoms, sleep, heart rate, blood pressure and allergies.", "Share it or save it as a page."],
              keywords: "doctor appointment summary report visit"),
        HowTo(id: "medicalcard", area: .health, question: "Keep my medical info handy",
              steps: ["Body → Medical card: blood type, allergies, conditions, emergency contact and doctor. Tap Show my card to show it full-screen.", "Also fill in Medical ID in Apple's Health app; that one works from the Lock Screen."],
              keywords: "medical id allergies blood type emergency"),
        HowTo(id: "bpweight", area: .health, question: "Track blood pressure and weight",
              steps: ["Body → Blood pressure → + to add a reading; Keel shows the trend and what the numbers mean.", "Body → Weight reads Apple Health (from your scale or entries in the Health app)."],
              keywords: "blood pressure weight scale bp"),
        HowTo(id: "fasting", area: .health, question: "Time a fast",
              steps: ["Body → Fasting → Start fasting. Pick a goal (12–20 hours). Keel tells you when you reach it."],
              keywords: "fasting intermittent timer"),
        HowTo(id: "sleepdebt", area: .health, question: "See my sleep debt and rhythm",
              steps: ["Body shows how many hours short you were this week, whether your weekend sleep drifts from your weekday rhythm, and your 7-hour streak.", "When your Tide is low in the early afternoon and you're free, Keel suggests a short nap."],
              keywords: "sleep debt rhythm weekend jet lag nap streak"),
        HowTo(id: "energyleft", area: .health, question: "Know how much energy I have left",
              steps: ["Body → Energy left today estimates what's left from your Tide, today's effort, stress and hours awake.", "Tap how you feel a few times a day (Energy right now); after a week Keel shows when you usually feel best."],
              keywords: "energy left battery peak check-in"),
        HowTo(id: "caffeinecurve", area: .health, question: "See how much caffeine is still in my body",
              steps: ["Body → Caffeine & water: the curve shows caffeine in your body through the day (it halves about every 5 hours) and when it drops low enough not to bother your sleep."],
              keywords: "caffeine curve half life sleep coffee"),
        HowTo(id: "sleepsounds", area: .health, question: "Fall asleep to rain or noise",
              steps: ["Body → Sleep sounds. Pick rain, ocean, fan or noise and when it should stop; it keeps playing with the screen locked."],
              keywords: "sleep sounds rain white noise"),
        HowTo(id: "visualtimer", area: .focus, question: "See time passing (visual timer)",
              steps: ["Compass → Visual timer. Set the minutes and Start: a red disc shrinks as time runs out, and Keel alerts you at the end."],
              keywords: "timer visual time blindness countdown"),
        HowTo(id: "quickwins", area: .tasks, question: "Find tasks I can do in a few minutes",
              steps: ["Compass → Quick wins lists open tasks estimated at 10 minutes or less. Tick one off between meetings."],
              keywords: "quick wins small tasks short"),
        HowTo(id: "protect", area: .calendar, question: "Protect my mornings for focus",
              steps: ["Compass → Protect focus mornings. Pick the hours; Keel blocks them as Focus time on weekdays for the next two weeks, only where you're free.", "Turn it off to remove the blocks."],
              keywords: "focus block morning protect calendar deep work"),
        HowTo(id: "intention", area: .today, question: "Set an intention for the day",
              steps: ["Today → Today's intention: one thing that would make today feel good.", "In the evening the card asks whether you did it."],
              keywords: "intention goal today morning"),
        HowTo(id: "wakealarm", area: .health, question: "Wake up with an alarm at the right time",
              steps: ["Body → Settings → turn on “Wake me with an alarm at my planned time”.", "Keel sets a real alarm (it rings even on Silent) for the wake time the sleep coach planned, and moves it if your plan changes."],
              keywords: "alarm wake up morning sleep coach"),
        HowTo(id: "drinks", area: .health, question: "Track caffeine and water",
              steps: ["Body → Caffeine & water (or Compass → Caffeine & water). Tap Coffee, Tea, Water… each time.", "Keel shows your last-caffeine time for tonight's bedtime and nudges you to drink water if you're behind.", "Caffeine after 2 PM is ticked in Habit impact for you, so you'll see what it does to your sleep."],
              keywords: "coffee caffeine water hydration drink cutoff"),
        HowTo(id: "workoutpick", area: .health, question: "Know how hard to work out today",
              steps: ["Body → Today's workout suggests rest, steady or push, from your Tide and today's Swell.", "Tap “Put it on my calendar” to block it in your first free slot."],
              keywords: "workout exercise training intensity tide"),
        HowTo(id: "weekplan", area: .calendar, question: "Plan my whole week",
              steps: ["Calendar → options → Plan my week, Tasks → ⋯ → Plan the week, or Compass → Plan the week.", "Each day shows its meetings, free hours and tasks. Drag a task onto a day, or tap a task then a day.", "Days that look full turn orange, so you can spread things out."],
              keywords: "week plan schedule balance days drag"),
        HowTo(id: "timereport", area: .calendar, question: "See where my time went",
              steps: ["Calendar → options → Where my time went (or Compass).", "Meetings, deep focus and planned task time for the week, compared with the week before, day by day."],
              keywords: "time report meetings focus analytics week"),
        HowTo(id: "workback", area: .tasks, question: "Break a big deadline into dated steps",
              steps: ["Open a task due more than two days from now → Work back from the deadline.", "Keel uses the task's steps (or writes some) and gives each one a date between today and the day before it's due."],
              keywords: "deadline project steps plan backward schedule"),
        HowTo(id: "upkeep", area: .tasks, question: "Remember home and car upkeep",
              steps: ["Compass → Home & car upkeep. Turn on what applies (HVAC filter, smoke alarms, oil change…) and say when you last did it.", "Each becomes a repeating task in your Home list; finishing it schedules the next one."],
              keywords: "maintenance home car filter oil change chores"),
        HowTo(id: "voicejournal", area: .today, question: "Journal by talking",
              steps: ["Compass → Voice journal → Start talking. Say how your day went and anything you need to do.", "Keel writes the entry, suggests your mood and lists the “I need to…” tasks to add. Edit anything, then Save."],
              keywords: "journal voice talk diary mood"),
        HowTo(id: "gifts", area: .today, question: "Never miss a birthday",
              steps: ["Compass → Birthdays & gifts shows birthdays from your Contacts (and ones you add) for the next 3 months.", "Add gift ideas whenever you think of them; a week before, Keel reminds you with your ideas."],
              keywords: "birthday gift present contacts reminder"),
        HowTo(id: "packing", area: .calendar, question: "Get a packing list for a trip",
              steps: ["Keel finds flights, hotels and trains in your email. A week before, it makes a packing list with the weather there and your medications.", "Compass → Packing lists to make one sooner or see what's packed."],
              keywords: "packing travel trip suitcase list weather"),
        HowTo(id: "documents", area: .settings, question: "Track passports, licenses and warranties",
              steps: ["Compass → Documents → + to add one with its expiry date (or scan it into the Vault).", "Keel reminds you 45 days before an ID expires and 14 days before anything else."],
              keywords: "passport license insurance warranty expire renew document"),
        HowTo(id: "evening", area: .settings, question: "Make evenings calmer",
              steps: ["Settings → Appearance → Evening calm warms Keel's colors after your real sunset.", "Soft sounds and My day on the Lock Screen are in the same place."],
              keywords: "evening night warm calm sunset sounds lock screen live activity"),
        HowTo(id: "status", area: .settings, question: "Check that everything is connected",
              steps: ["Help → Keel status shows iCloud, sync, notifications, instant mail alerts, Apple Health, your Keel server, AI and Apple Watch, each with a green tick or what's missing.", "You can also bring back all the one-time tips from there."],
              keywords: "status connected sync notifications problem troubleshoot not working tips"),
        HowTo(id: "showkey", area: .ai, question: "See an AI key I saved",
              steps: ["Settings → AI & Privacy → AI Model → choose the model → its Key screen → Show Key.", "Unlock with Face ID; copy it if you need it (it clears from the clipboard after 2 minutes)."],
              keywords: "api key show copy claude chatgpt gemini lost"),
        HowTo(id: "connector", area: .ai, question: "Let Claude read my Keel day",
              steps: ["In Claude: Settings → Connectors → Add custom connector → your Keel server address followed by /mcp.", "Tap Connect and enter your connector password (KEEL_MCP_TOKEN from Cloudflare), then Allow.", "Claude can then see your plan, tasks, notes and promises, and add tasks."],
              keywords: "claude connector mcp chat assistant"),
        HowTo(id: "instantmail", area: .inbox, question: "Get new-mail alerts instantly",
              steps: ["Needs your Keel server with its Apple push key. Help → Keel status shows whether it's on.", "Outlook works once that's set; Gmail also needs Google's notice service (see the setup guide). iCloud and other mail use background refresh."],
              keywords: "instant push notifications new mail alerts"),
        HowTo(id: "body", area: .health, question: "See how recovered I am (Tide, Swell and Anchor)",
              steps: ["Open the Body card on Today (or Compass → Body) and tap Connect Apple Health.", "Tide is how recovered you are (0–100%). It compares last night's heart rate variability and resting heart rate with your own normal, plus your sleep.", "Swell is how hard your body worked today, from time in each heart-rate zone. Keel suggests a Swell range that suits your Tide.", "Anchor is your sleep score: enough sleep for what you needed, time asleep vs in bed, deep and REM sleep, and a steady bedtime."],
              tip: "Wear your Apple Watch, including to bed. Tide needs about 5 nights to learn your normal. Everything is worked out on your iPhone and never leaves it.",
              keywords: "body recovery strain sleep score hrv heart rate variability resting heart rate readiness tide swell anchor apple watch fitness"),
        HowTo(id: "bodyhabits", area: .health, question: "Find out which habits help or hurt my recovery",
              steps: ["In Body → Habit impact, tap what you did yesterday (caffeine late, alcohol, screens in bed, meds, a late meal…).", "Do it most days. After at least 3 days with and 3 without a habit, Keel shows how it changes your next-morning Tide."],
              keywords: "journal habits alcohol caffeine impact recovery insights"),
        HowTo(id: "bodysleep", area: .health, question: "Know when to go to bed",
              steps: ["Body → Anchor shows how much sleep you need tonight and when to turn the lights out to wake at your usual time.", "Your need goes up a little after a hard day and when you've been short on sleep.", "Keel reminds you to wind down 45 minutes before. Turn it off in Body → Settings."],
              keywords: "bedtime sleep need sleep debt wind down reminder coach"),
        HowTo(id: "bodystress", area: .health, question: "See my stress through the day",
              steps: ["Body → Stress through the day shows each hour from 8 AM to 10 PM: green is calm, orange some stress, red high.", "It's your heart rate above your resting level while you're not working out, so wear your Apple Watch during the day."],
              keywords: "stress heart rate calm anxious day"),
        HowTo(id: "bodywidgets", area: .health, question: "Put Tide on my Home Screen, Lock Screen or watch face",
              steps: ["iPhone: touch and hold the Home Screen or Lock Screen → Edit → Add Widget → Keel → Body.", "Apple Watch: touch and hold your watch face → Edit → Complications → Keel → Tide. The Keel watch app also shows a Body page."],
              keywords: "widget complication watch face lock screen tide"),
        HowTo(id: "sidebar", area: .settings, question: "Hide the sidebar on Mac or iPad",
              steps: ["Choose View → Hide Keel Sidebar, or press Option-Command-S. Your sections move to a small tab strip at the top.", "Do the same again to bring the sidebar back."],
              keywords: "sidebar hide show mac ipad full screen tabs"),
        HowTo(id: "settingssync", area: .start, question: "Have my settings and AI keys on my Mac and iPad too",
              steps: ["Use the same Apple Account on each device, with iCloud Keychain turned on (Settings → your name → iCloud → Passwords and Keychain).", "Your AI keys (Claude, ChatGPT, Gemini), mail sign-ins, Notion and your Keel account arrive by themselves through iCloud Keychain.", "Your settings follow too: look and fonts, AI model, mail layout and tabs, focus, notes, booking link and more. Change one anywhere and the others match within a minute or so.", "Mail accounts you add on one device are set up on the others once their sign-in arrives."],
              tip: "A few things stay per device on purpose: which device syncs Apple Reminders, which calendars are shown, and Apple Health.",
              keywords: "sync settings mac ipad keys api key claude chatgpt gemini same everywhere icloud keychain"),
        HowTo(id: "booking", area: .calendar, question: "Let people book time with me (booking link)",
              steps: ["Calendar → the options button (top left) → Booking link.", "Name the meeting, pick its length, your hours and how far ahead people can book, then turn on Booking link.", "Share or copy the link. People see only your free times (in their own time zone), pick one, and leave their name and email.", "The booking lands on your calendar with their details, and you get a notification."],
              tip: "Only the open times are sent to your Keel server, never your events. Keel refreshes them about every 30 minutes and right after each booking.",
              keywords: "booking link calendly schedule meeting book appointment availability scheduling page"),
        HowTo(id: "planday", area: .calendar, question: "Drag tasks onto my day (time blocking)",
              steps: ["Calendar → options → Plan my day, or Tasks → ⋯ → Plan my day.", "Drag a task from the top onto an hour. Or tap a task, then tap an hour.", "Keel blocks the time on your calendar, sized to how long things really take you.", "Long-press a planned task to take it off the day."],
              keywords: "time block drag drop schedule plan day hours sunsama akiflow"),
        HowTo(id: "assign", area: .tasks, question: "Hand a task to someone else",
              steps: ["Open the task → Shared → Assign to someone. Pick a person or type a name and email.", "Tap “Email it to them” for a ready-written email with the details and steps.", "The task moves to Waiting on others. Use “Nudge them” to check in, or “Take it back”."],
              keywords: "assign delegate share task person someone else waiting on"),
        HowTo(id: "timeline", area: .notes, question: "See a database as a timeline",
              steps: ["Open a database and tap Timeline in the view buttons.", "Each row is a bar starting on its first date property. Add a second date property to give rows an end date.", "Use the arrows to move through the weeks; tap a bar to open that page."],
              keywords: "timeline gantt database dates bars project schedule"),
        HowTo(id: "handoff", area: .settings, question: "Continue on my Mac or iPad where I left off (Handoff)",
              steps: ["Open a page or task on one device.", "On your Mac it appears in the Dock (or at the bottom of the app switcher on iPad). Click it to open the same page.", "Handoff needs Bluetooth and Wi-Fi on, and the same Apple Account on both devices."],
              keywords: "handoff continuity continue mac ipad another device"),
        HowTo(id: "mailalerts", area: .inbox, question: "Reply to or archive an email from its notification",
              steps: ["When an important email alert appears, press and hold it (or swipe down on it).", "Tap Reply to type an answer right there, or Archive, or Mark as Read."],
              keywords: "notification reply archive mark read lock screen email alert actions"),
        HowTo(id: "shortcutsplus", area: .settings, question: "Use Keel pages and tasks in Shortcuts",
              steps: ["Open the Shortcuts app and search for Keel.", "New actions: Find Keel Tasks (due today, overdue, this week, by list), Open Keel Page, Get Text of Keel Page, Add to Keel Page.", "Pass the results into other actions, like sending today's tasks to someone or adding a daily log line to a page."],
              keywords: "shortcuts automation siri actions find tasks page append"),
        HowTo(id: "spacealerts", area: .notes, question: "Know when someone changes a shared page",
              steps: ["Join or create a shared space (Notes → ⋯ → Shared spaces).", "When someone else edits one of its pages, Keel tells you who and which page, about every 10 minutes while you use the app."],
              keywords: "shared space collaborate team family changes updated notification"),
        HowTo(id: "aiwrite", area: .notes, question: "Write with AI in a page (Claude, ChatGPT, Gemini or Apple Intelligence)",
              steps: ["Ask anywhere: on an empty line press space, or type /ai and pick Ask AI. Say what you want (\"draft an agenda for Monday\") and watch it write.",
                      "Pick the model with the chip at the top of the AI box. Your default is in Settings → AI & Privacy → AI Writing in Notes.",
                      "Edit what you select: select words (or put the cursor on a line), tap ✨ above the keyboard and choose Improve, Shorten, Fix grammar, Change tone, Turn into a list or table, or tell it what to change. Then Replace, Insert below, Retry or discard.",
                      "Live AI blocks: type /AI block and write what it should always show, like \"Summarize this page\" or \"List open questions\". Tap ↻ to refresh; it also refreshes itself when you open the page after a few hours.",
                      "Whole page: tap ✨ in the top bar → Page actions for a summary, TL;DR at the top, action items, a better title, added structure or open questions."],
              tip: "Apple Intelligence is free and stays on your device. Claude, ChatGPT and Gemini use your own API key (Settings → AI & Privacy) and bill you per use. Every AI change is saved in Version history, so you can undo it.",
              keywords: "ai write notion ai claude chatgpt gpt openai gemini model rewrite summarize generate draft brainstorm selection tone grammar"),
        HowTo(id: "signin", area: .start, question: "Use the same Keel on iPhone, iPad and Mac",
              steps: ["Open Settings → Sign in to Keel (top of Settings) and tap Sign in with Apple.", "Do the same on your other devices with the same Apple Account.", "Close and reopen Keel once. Your tasks, notes, habits and everything you make now sync through your private iCloud.", "Add your mail accounts on each device in Settings → Mail Accounts; email is fetched by each device, not copied to iCloud."],
              tip: "Signing in also connects this device to your Keel server, so Claude works without typing an access code.",
              keywords: "account sign in login sync icloud same devices mac ipad"),
        HowTo(id: "windows", area: .settings, question: "Open a page or email in its own window",
              steps: ["On Mac or iPad, right-click (or touch and hold) a page in Notes or an email in Inbox.", "Choose Open in New Window.", "For a small always-handy window with your next task, a focus button and quick capture, tap the Quick window button at the top of Today."],
              keywords: "window multiple mac ipad side by side quick"),
        HowTo(id: "accounts", area: .start, question: "Add my email accounts",
              steps: ["Open Settings (the gear on Today).", "Tap Mail Accounts, then choose under Add Account.", "Pick Gmail, Outlook, iCloud or another provider and sign in.", "Mail starts syncing right away; pull down on Inbox to refresh."],
              keywords: "gmail outlook icloud yahoo connect sign in mail"),
        HowTo(id: "move", area: .start, question: "Bring my notes from another app",
              steps: ["Go to Notes → ✎ (hold) → Import from another app, or Today → ⊞ → Move to Keel.", "Pick the app you're coming from and follow its short guide.", "For Notion, tap Connect Notion to bring a whole workspace at once.", "Review the preview, then tap Import. Every import can be undone."],
              keywords: "import migrate notion obsidian evernote apple notes bear keep"),
        HowTo(id: "tour", area: .start, question: "See everything Keel can do",
              steps: ["Settings → How Keel Works shows every feature explained.", "Settings → Replay Welcome Tour plays the intro again."],
              keywords: "guide features tour learn"),

        // Today
        HowTo(id: "onething", area: .today, question: "Know what to do next",
              steps: ["Open Today.", "Set your energy (Low battery, Steady, Locked in).", "“Just one thing” shows the best next task for your energy, deadlines and free time. Tap it to start."],
              keywords: "next task what now overwhelmed priority"),
        HowTo(id: "plan", area: .today, question: "Plan my day",
              steps: ["On Today, tap Plan my day (or Today → ⊞ → Plan my day).", "Pick your top three, then let Keel time-block the rest around your meetings.", "Add the plan to your calendar with one tap."],
              keywords: "schedule time block morning"),
        HowTo(id: "braindump", area: .today, question: "Empty my head (brain dump)",
              steps: ["Tap the 🧠 button at the top of Today.", "Type or dictate everything on your mind.", "Keel sorts it into tasks with dates, events, notes and worries. Review, then save."],
              keywords: "brain dump capture thoughts dictate"),
        HowTo(id: "compass", area: .today, question: "Find a tool fast (Compass)",
              steps: ["Tap ⊞ on Today to open the Compass.", "Tap how you feel (scattered, stuck, overwhelmed, ready, low) for three suggested tools.", "Or search in your own words, like “anxious” or “where was I”."],
              keywords: "hub tools search menu"),
        HowTo(id: "customize", area: .today, question: "Change the cards on Today",
              steps: ["Scroll to the bottom of Today → Customize Today.", "Switch cards off, or turn off Automatic order and drag them into your order."],
              keywords: "cards layout order hide"),
        HowTo(id: "sos", area: .today, question: "Calm down when it's too much",
              steps: ["Tap the lifebuoy at the top left of Today (I'm overwhelmed).", "Follow the short reset: breathe, pick one tiny thing, park the rest."],
              keywords: "panic anxious stressed overwhelmed sos"),

        // Email
        HowTo(id: "autopilot", area: .today, question: "Let Keel prepare things for me (Autopilot)",
              steps: ["Autopilot sits at the top of Today (and Today → ⊞ → Autopilot).", "After each sync it prepares: replies already drafted, a mass unsubscribe from senders you never read, events that clash moved to a free gap, tasks from your email, overbooked days rebalanced, focus time for deadlines, repeating tasks turned into habits, bills and promises as tasks, and notes for tomorrow's meetings.", "Nothing happens until you tap. Dismiss anything you don't want; it won't come back."],
              keywords: "autopilot suggestions propose unsubscribe reschedule habit tasks automatic"),
        HowTo(id: "triage", area: .inbox, question: "Get through my inbox quickly",
              steps: ["Open Inbox. Priority shows real people and deadlines first.", "Swipe right for task, snooze or star; swipe left for done or trash.", "Try the ⚡ Quick wins tab for replies that take about 2 minutes.", "Today → ⊞ → Quick replies goes through them one by one."],
              keywords: "inbox zero triage swipe archive"),
        HowTo(id: "vip", area: .inbox, question: "Make sure I never miss someone",
              steps: ["Long-press an email from them → Mark Sender as VIP.", "VIP mail stays on top and always notifies you."],
              keywords: "vip important sender notify"),
        HowTo(id: "reply", area: .inbox, question: "Reply in my own voice with AI",
              steps: ["Open an email and tap a reply chip like “Yes, sounds good”.", "Keel drafts the reply in your writing style; edit and send.", "Sending gives you 5 seconds to undo."],
              keywords: "draft reply ai write respond"),
        HowTo(id: "sendlater", area: .inbox, question: "Send an email later",
              steps: ["Write the email, then touch and hold the Send button.", "Pick a suggested time, or Pick a time…. Keel sends it at that time."],
              keywords: "schedule send later"),
        HowTo(id: "search", area: .inbox, question: "Search my email",
              steps: ["Pull down on Inbox to show the search field.", "Use words or operators like from:sam has:attachment before:friday.", "Press Search on the keyboard to look through all your mail on the server."],
              keywords: "find search operators"),
        HowTo(id: "unsub", area: .inbox, question: "Unsubscribe from newsletters",
              steps: ["Keel suggests newsletters you never open at the top of Inbox.", "Tap Unsubscribe. When the sender supports it, it happens in one tap without opening a website."],
              keywords: "newsletter unsubscribe spam promotions"),

        // Calendar
        HowTo(id: "event", area: .calendar, question: "Add or move an event",
              steps: ["Open Calendar and tap an empty time to add an event.", "Long-press and drag an event to move it.", "Events sync with Apple Calendar, Google and Outlook on this iPhone."],
              keywords: "event appointment move drag"),
        HowTo(id: "appointments", area: .calendar, question: "Find appointments in my email",
              steps: ["Keel reads new mail for appointments, bookings and confirmations (doctor, dentist, haircut, interviews, car service, classes) after every sync.", "Each one it finds shows up in Autopilot and in Today → ⊞ → Appointments from email, with Add to Calendar. Anything already on your calendar is skipped.", "Tap Scan the last 60 days to look further back.", "For a single email: open it → ⋯ → Add to Calendar."],
              keywords: "appointment email calendar find search booking confirmation doctor dentist"),
        HowTo(id: "calsync", area: .calendar, question: "How calendar sync works",
              steps: ["Keel uses the calendars already on your iPhone or Mac: iCloud, Google, Outlook/Exchange and any you subscribe to.", "To add Google or Outlook calendars: iPhone Settings → Apps → Calendar → Calendar Accounts (on Mac: System Settings → Internet Accounts).", "Changes go both ways: edit in Keel and it updates in Apple Calendar, Google and Outlook, and the other way round.", "Pick which calendars show in Keel's Calendar with the filter menu."],
              keywords: "calendar sync google outlook icloud two-way accounts"),
        HowTo(id: "leaveby", area: .calendar, question: "Get told when to leave",
              steps: ["Give the event a location.", "Keel checks travel time and sends a Time Sensitive “leave now” alert."],
              keywords: "travel leave late commute"),

        // Tasks
        HowTo(id: "addtask", area: .tasks, question: "Add a task with a reminder",
              steps: ["Tap + in Tasks, or say “Add a task in Keel” to Siri.", "Type it naturally, like “Call mom tomorrow 6pm”: Keel picks up the date and time.", "Open the task to set an alert, repeat, priority or a place."],
              keywords: "new task todo reminder due"),
        HowTo(id: "alarms", area: .tasks, question: "Get full-screen alarms for tasks",
              steps: ["Give the task a time. Timed tasks ring like an alarm clock: full screen, even on the Lock Screen and in Silent mode, with Done and Snooze.", "Allow Alarms the first time Keel asks.", "Turn it off for one task by holding it → Turn Off Full-Screen Alarm, or for all tasks in Settings → Tasks → Full-Screen Alarms."],
              keywords: "alarm full screen ring loud reminder ticktick wake"),
        HowTo(id: "quickactions", area: .start, question: "Use shortcuts from the Keel icon",
              steps: ["On your Home Screen, press and hold the Keel icon.", "Choose New Task, New Note, Start Focus or Record a Meeting."],
              keywords: "haptic touch long press icon shortcut quick action"),
        HowTo(id: "popup", area: .tasks, question: "Make reminders pop up right away",
              steps: ["Settings → Notifications → turn on Time Sensitive Reminders.", "If you see “Allow Time Sensitive for Keel…”, tap it and switch it on in iOS.", "In each Focus mode, allow Time Sensitive notifications so reminders come through."],
              keywords: "notification time sensitive focus banner alert pop up"),
        HowTo(id: "now", area: .tasks, question: "Start a task with a timer (Now timer)",
              steps: ["Hold a task → Start now.", "A countdown sized to how long tasks like it really take you appears on the Lock Screen, Dynamic Island and Watch.", "You get a gentle tap halfway and at the end."],
              keywords: "timer now start time blindness countdown estimate"),
        HowTo(id: "evening", area: .tasks, question: "Plan for this evening and set deadlines",
              steps: ["Hold a task → This Evening: it moves to its own section after Today.", "Hold a task → Set Deadline… for when it must be done; the due date stays the day you plan to work on it.", "You get a heads-up the morning before a deadline."],
              keywords: "evening tonight deadline due date things"),
        HowTo(id: "errands", area: .tasks, question: "Group errands by place",
              steps: ["Tasks like “pick up prescription” or “return package” are grouped automatically: Tasks → ✨ menu → Errands by place.", "Tap Find nearby to open Maps, and tick them off as you go."],
              keywords: "errands store pharmacy post office run shopping"),
        HowTo(id: "sharedlists", area: .tasks, question: "Share a list with anyone",
              steps: ["Tasks → ✨ menu → Shared lists → type a name → Create, or open a list's Share sheet → Share as a link.", "Send the link. They can check off and add items in Keel or any browser, and leave comments.", "With other Apple users you can also share the list in Apple Reminders."],
              keywords: "share list family partner collaborate together groceries link"),
        HowTo(id: "automations", area: .tasks, question: "Set up automations",
              steps: ["Settings → Automations (or Tasks → ✨ → Automations).", "Pick a trigger (email from…, subject has…, a task is done, focus ends) and an action (add a task, write in today's log, notify me, archive the email).", "Use {subject}, {from} or {task} in the text."],
              keywords: "automation rule when then trigger action workflow"),
        HowTo(id: "mealplan", area: .health, question: "Plan meals and make a grocery list",
              steps: ["Today → ⊞ → Meal plan & groceries → Plan this week's meals.", "Only foods your diet guide approves: oily fish twice, pumpkin seeds daily.", "Save plan + add groceries puts the shopping list in Tasks (Groceries), grouped by aisle. Scanning a product checks it off."],
              keywords: "meal plan grocery list shopping diet week"),
        HowTo(id: "rewards", area: .today, question: "Earn rewards and add an accountability buddy",
              steps: ["Today → ⊞ → Rewards & buddy.", "Tasks, habits and focus earn XP and coins; spend coins on rewards you choose.", "Add a buddy's phone or email and send this week's wins in one tap."],
              keywords: "rewards xp level coins treat buddy accountability gamify"),
        HowTo(id: "emailtokeel", area: .inbox, question: "Turn an email into a task by forwarding it",
              steps: ["Settings → Email to Keel shows your address, like you+keel@gmail.com.", "Forward any email there and it becomes a task. Start the subject with “Note:” for a note.", "With any provider: email yourself with a subject starting “Task:” or “Note:”."],
              keywords: "email forward task address plus keel"),
        HowTo(id: "export", area: .settings, question: "Export everything",
              steps: ["Settings → Data & Storage → Export Everything (ZIP).", "You get every note as a Markdown file in its folders, plus tasks, habits, journal and food as spreadsheets."],
              keywords: "export zip markdown csv download leave backup"),
        HowTo(id: "steps", area: .tasks, question: "Break a big task into small steps",
              steps: ["Open the task → Break into tiny steps with AI.", "Keel writes 3–8 tiny steps of 2–10 minutes each. The first is the easiest."],
              keywords: "stuck procrastinate steps break down"),
        HowTo(id: "location", area: .tasks, question: "Get reminded at a place",
              steps: ["Open a task → Location.", "Pick a saved place (home, work) or search for one, and choose arriving or leaving. Manage places in Today → ⊞ → Places."],
              keywords: "location geofence arrive leave place"),
        HowTo(id: "reminders", area: .tasks, question: "Use Apple Reminders with Keel",
              steps: ["Allow Reminders when asked (or Settings → Connected Apps → Reminders).", "Reminders and Keel tasks sync both ways, so Siri's “Add to Reminders” lands in Keel too."],
              keywords: "apple reminders sync siri"),

        // Notes
        HowTo(id: "brainhome", area: .notes, question: "Use the second-brain home",
              steps: ["Notes → the brain icon (or the Second brain tile).", "Your brain map sits on top, unchanged. Below: capture inbox, flashcards due, pages worth another look, notes for today's meetings, projects and recent pages."],
              keywords: "second brain home dashboard brain map resurface"),
        HowTo(id: "related", area: .notes, question: "See related pages and search by meaning",
              steps: ["At the bottom of every page, Related lists pages, tasks and emails about the same thing, found on your device. Tap Link to connect them.", "Search also shows Related by meaning, so \"that pricing idea\" finds the right page even without the exact words."],
              keywords: "related semantic meaning search auto links"),
        HowTo(id: "supertagshelp", area: .notes, question: "Use supertags (#person, #book, #project…)",
              steps: ["Write #book (or #person, #project, #meeting, #idea…) on any line.", "Tap the chip under the line to fill its fields.", "Today → ⊞ → Supertags shows every one as a live collection. Add your own types there."],
              keywords: "supertags types tana fields collection"),
        HowTo(id: "lines", area: .notes, question: "Link to a single line, fold and zoom",
              steps: ["Hold a line → Link to this line → Copy line link (paste it anywhere) or Copy line embed (then type /line embed).", "Lines with things under them get a fold arrow; hold → Zoom in to see just that branch.", "Move up/down takes everything under the line with it."],
              keywords: "block reference line link embed outliner fold zoom"),
        HowTo(id: "trashhelp", area: .notes, question: "Get back a deleted page",
              steps: ["Notes → ✎ → Recently deleted, or Settings → Data & Storage → Backups.", "Pages stay there 30 days. Keel also keeps a daily backup of pages, tasks and people (the last 7)."],
              keywords: "trash deleted restore backup undo"),
        HowTo(id: "capturehelp", area: .notes, question: "Capture anything fast",
              steps: ["Today → ⊞ → Capture inbox: jot, paste a link (articles and YouTube are read for you), or record a voice note.", "Also from Siri (\"Add to capture inbox\"), the Voice Note control, Apple Watch, and the Safari extension.", "File everything with AI sorts it into your folders."],
              keywords: "capture inbox quick jot voice youtube"),
        HowTo(id: "readerhelp", area: .notes, question: "Read articles and keep highlights",
              steps: ["Read Later → hold an article → Read in Keel (or swipe → Reader).", "Double-tap a paragraph to highlight it, then tap the note button to save highlights as a page.", "Kindle, Pocket and Instapaper import from Today → ⊞."],
              keywords: "reader highlights kindle pocket instapaper read later"),
        HowTo(id: "pdfhelp", area: .notes, question: "Read and highlight PDFs",
              steps: ["In a page: ⊕ → PDF to read and highlight.", "Open it, select text, tap the highlighter (or the speech bubble to add a thought). Highlights are copied into the page with the page number."],
              keywords: "pdf annotate highlight reader"),
        HowTo(id: "flashhelp", area: .notes, question: "Study with flashcards",
              steps: ["Write \"question :: answer\" on any line, or a toggle ending in ?.", "Or open a page → ✨ → Make flashcards.", "Today → ⊞ → Flashcards shows what's due, on a smart schedule."],
              keywords: "flashcards spaced repetition study learn"),
        HowTo(id: "askall", area: .today, question: "Ask about anything in my life",
              steps: ["Today → ⊞ → Ask everything.", "It searches pages, email, tasks, calendar and meeting notes, answers with sources, and can save the answer or make a task."],
              keywords: "ask everything question search ai"),
        HowTo(id: "doneforyou", area: .today, question: "See what Keel did overnight",
              steps: ["Today → ⊞ → Done for you.", "Overnight Keel drafts replies for real people, files your captures, preps today's meetings and gets your day ready. Approve with one tap; filing can be undone. Nothing is sent for you."],
              keywords: "overnight agent done for you prep"),
        HowTo(id: "timelinehelp", area: .today, question: "Look back at my life on a timeline",
              steps: ["Today → ⊞ → Life timeline.", "Each month shows email from people, meetings, pages, finished tasks, journal moments, workouts and photos. Search inside it."],
              keywords: "timeline life history what was i doing"),
        HowTo(id: "coachhelp", area: .today, question: "Get a weekly check-in from my coach",
              steps: ["Today → ⊞ → Coach. Add your goals and what matters to you.", "Every Sunday you get one honest check-in: what's moving you forward, what's draining you, and one change to try."],
              keywords: "coach goals values check in reflection"),
        HowTo(id: "spaceshelp", area: .notes, question: "Share a brain with family or a team",
              steps: ["Today → ⊞ → Shared spaces → Create, then share the invite link.", "Add pages to edit together (you see who's there) and shared lists. Your own notes stay private."],
              keywords: "shared space family team collaborate together"),
        HowTo(id: "setuphelp", area: .notes, question: "Set up Projects, Areas, Resources and Archive",
              steps: ["Notes → ✎ → Second-brain setup.", "Add the structure and templates (the weekly review makes itself every Friday).", "Plan where every page goes, review it, then move. Check every link to fix broken links and connect related pages."],
              keywords: "para setup projects areas resources archive reorganize templates links"),
        HowTo(id: "healthhelp", area: .notes, question: "Clean up duplicates and broken links",
              steps: ["Notes → ✎ → Brain health.", "Merge duplicate pages, fix links that point nowhere, clear empty pages and rediscover forgotten ones."],
              keywords: "duplicates broken links orphan cleanup health"),
        HowTo(id: "blockshelp", area: .notes, question: "Use columns, buttons, progress and charts",
              steps: ["Type /columns for side-by-side text, /button for one-tap actions (add a task, open a link, use a template), /progress for to-dos done, /chart to chart a database, /file for any file."],
              keywords: "columns button progress chart file blocks"),
        HowTo(id: "encrypthelp", area: .notes, question: "Keep locked pages encrypted",
              steps: ["Lock a page (⋯ → Lock page). Whenever it's closed, its content is stored encrypted with a key only your devices have, in iCloud Keychain.", "Unlock with Face ID to read and edit it."],
              keywords: "encrypt encryption locked private secure"),
        HowTo(id: "extensionshelp", area: .notes, question: "Add extensions and my own AI commands",
              steps: ["Today → ⊞ → Extensions: get AI commands, supertag packs and template packs.", "Write your own AI command; it appears in every page's ✨ menu. Share it as a link."],
              keywords: "extensions plugins ai commands gallery"),
        HowTo(id: "vaulthelp", area: .notes, question: "Edit my notes in Obsidian too",
              steps: ["Settings → Data & Storage → Markdown copy of your notes → choose a folder.", "Keel writes every page there, and edits you make to those files come back into Keel when you open it. If both changed, you get a conflicted copy instead of losing anything."],
              keywords: "obsidian markdown two-way sync vault files"),
        HowTo(id: "safarihelp", area: .notes, question: "Save pages and highlights from Safari",
              steps: ["Safari → the puzzle piece (or aA) → Keel.", "Save the page to Read Later, or select text first and save it as a highlight."],
              keywords: "safari extension save highlight web clipper"),
        HowTo(id: "voicehelp", area: .today, question: "Talk to Keel hands-free (\"Hey Keel\")",
              steps: ["Open Today → ⊞ → Talk to Keel and switch on Hands-free.", "While that screen is open, just say \"Hey Keel\" and your request: \"Add milk to groceries\", \"What's next?\". Keel answers out loud, listens for a follow-up, then waits for \"Hey Keel\" again. Say \"that's all\" to end a conversation.", "Everything is heard on your device. iPhone only lets Siri listen when Keel isn't open, so from anywhere say \"Hey Siri, talk to Keel\".", "Shortcuts and Siri: Read My Important Email, Add to Capture Inbox, Record a Voice Note, Search My Second Brain."],
              keywords: "voice hands free airpods siri talk"),
        HowTo(id: "look", area: .settings, question: "Change the theme, font or layout",
              steps: ["Settings → Look & Feel → Theme: Standard, Paper, Midnight or High contrast.", "Font: Default, Serif, Rounded or Monospaced, everywhere in the app.", "Layout → Mail layout, Inbox tabs and Tab bar."],
              keywords: "theme font dark paper midnight contrast serif look customize appearance"),
        HowTo(id: "tabbar", area: .settings, question: "Choose what's in the bottom tab bar",
              steps: ["Settings → Look & Feel → Tab bar.", "Remove sections you don't use and add any tool (Habits, Journal, Focus room…), up to five. Today stays first.", "Anything you take out still opens from links, widgets and Siri."],
              keywords: "tab bar bottom customize sections order"),
        HowTo(id: "mailtabs", area: .inbox, question: "Make my own inbox tabs",
              steps: ["Settings → Mail → Inbox Tabs → New tab.", "Pick senders or words, or just describe it (\"anything from investors\") and Keel's AI sorts mail into it.", "Reorder or hide tabs there too. All always stays."],
              keywords: "inbox tabs custom split filter category ai sort"),
        HowTo(id: "maillayout", area: .inbox, question: "Make the email list denser or roomier",
              steps: ["Settings → Mail → Layout.", "Pick Compact, Comfortable or Spacious, how many preview lines, sender pictures, and AI summary or first lines."],
              keywords: "mail layout density compact preview lines avatars"),
        HowTo(id: "autodrafts", area: .inbox, question: "Have replies written before I open the email",
              steps: ["Settings → Mail → Draft Replies in Advance.", "New mail from real people that needs an answer gets a reply written in your voice. Look for Draft ready.", "Open it, check the [bracketed] bits, and send. Nothing is ever sent for you."],
              keywords: "auto draft reply ai advance superhuman"),
        HowTo(id: "askinbox", area: .inbox, question: "Ask a question about my email",
              steps: ["Inbox → ⋯ → Ask your inbox.", "Ask anything, like \"What's the address for Saturday?\". The answer cites the emails it used; tap one to open it."],
              keywords: "ask inbox question search ai answer email"),
        HowTo(id: "besttime", area: .inbox, question: "Send at the best time",
              steps: ["In a new email, hold the Send button.", "Best time picks when that person usually writes, from your past email with them."],
              keywords: "send later best time schedule"),
        HowTo(id: "asknotes", area: .notes, question: "Ask a question across all my notes",
              steps: ["Notes → ✎ menu → Ask my notes (or Today → ⊞).", "The answer cites your pages; tap one to open it. Locked pages are never read."],
              keywords: "ask notes question ai answer search workspace"),
        HowTo(id: "aifill", area: .notes, question: "Let AI fill a database column",
              steps: ["Open a database → Properties → New property → AI autofill.", "Say what to fill, like \"one-line summary\" or \"category: work, home or admin\".", "Tap Fill empty rows. Values stay editable."],
              keywords: "ai autofill database property column fill"),
        HowTo(id: "remindnotes", area: .tasks, question: "Set reminders by typing naturally",
              steps: ["Anywhere you add a task, or on its own line in a note, type \"remind me to call mom every other Sunday 5pm\" and press Return.", "Saved places work too: \"…when I leave work\" or \"…when I get home\" (Settings → Tasks → Places)."],
              keywords: "remind me natural language every other place leave arrive note reminder"),
        HowTo(id: "digest", area: .today, question: "Get a weekly digest",
              steps: ["Every Sunday at 4 PM Keel writes one page: what you finished, new pages, deadlines and the week ahead.", "Turn it off in Settings → Notifications. Make one any time from Today → ⊞ → This week's digest."],
              keywords: "weekly digest summary sunday week"),
        HowTo(id: "shortcutskeys", area: .settings, question: "Use keyboard shortcuts",
              steps: ["On iPad or Mac, press ⌘/ to see them all.", "In email: ⌘R reply, ⌃⌘A archive, ⇧⌘L flag. Anywhere: ⌘K does anything, ⌘O opens a page."],
              keywords: "keyboard shortcuts keys mac ipad"),
        HowTo(id: "embed", area: .notes, question: "Show one page inside another (synced)",
              steps: ["In a page, type /embed and pick a page.", "It shows that page's content right there. Edit the original and every embed updates."],
              keywords: "embed synced block transclude include page inside obsidian"),
        HowTo(id: "linkeddb", area: .notes, question: "Show a database inside a page",
              steps: ["Type /linked database and pick one.", "The full table, board or calendar appears in the page; changes are the same database."],
              keywords: "linked database view inline notion"),
        HowTo(id: "relations", area: .notes, question: "Link databases and add formulas",
              steps: ["Open a database → Properties → New property.", "Relation: pick the database it links to, then choose rows in each cell.", "Formula: write something like {Price} * {Quantity} or days({Due}). Checkboxes count as 1 or 0; relations and multi-selects count their items."],
              keywords: "relation formula rollup database properties calculate"),
        HowTo(id: "mathdiagram", area: .notes, question: "Write equations and diagrams",
              steps: ["Type /equation for math in LaTeX (like \\frac{a}{b}).", "Type /diagram for flowcharts written in Mermaid (like graph TD; A-->B).", "Tap Edit under it to change the source."],
              keywords: "math latex katex equation formula mermaid diagram flowchart"),
        HowTo(id: "outline", area: .notes, question: "Jump around a long page",
              steps: ["⋯ → Outline lists every heading; tap one to jump to it.", "Or type /table of contents to put the list in the page.", "⋯ → Find & replace searches the page and can replace everywhere."],
              keywords: "outline table of contents toc headings jump find replace search"),
        HowTo(id: "comments", area: .notes, question: "Leave comments on a page",
              steps: ["Hold any block → Comment, or ⋯ → Comments for the whole page.", "Comments sync with the page. Swipe one to resolve or delete it."],
              keywords: "comment comments discuss feedback resolve"),
        HowTo(id: "quickopen", area: .notes, question: "Jump to any page fast",
              steps: ["Notes → the magnifying glass, or ⌘O on a keyboard.", "Type a few letters, even out of order (\"mtg nt\" finds Meeting notes), and press Return. No match? Create the page right there."],
              keywords: "quick switcher open jump command o find page"),
        HowTo(id: "mentions", area: .notes, question: "Find pages that mention this one",
              steps: ["At the bottom of a page, Mentioned in lists pages that say its name without linking it.", "Tap Link to turn that mention into a [[link]]."],
              keywords: "unlinked mentions backlinks links obsidian"),
        HowTo(id: "mdfolder", area: .notes, question: "Keep my notes as Markdown files",
              steps: ["Settings → Data & Storage → Markdown copy of your notes → Choose a folder… (iCloud Drive works well).", "Every page is kept there as a .md file in the same folders, updated whenever you leave Keel.", "Obsidian or any Markdown app can open that folder."],
              keywords: "markdown files folder obsidian vault plain text own export backup"),
        HowTo(id: "vault", area: .notes, question: "Keep receipts, warranties and IDs safe",
              steps: ["Notes → Vault (or Today → ⊞ → Paperwork vault).", "Scan, pick a photo or add a PDF. Keel reads it, files it under Vault by type, and pulls out amounts, expiry and return dates.", "You get a task before a return window closes or a document expires (45 days ahead for IDs)."],
              keywords: "vault receipt warranty passport id insurance documents paperwork scan expire return"),
        HowTo(id: "history", area: .notes, question: "Get back an earlier version of a page",
              steps: ["Open the page → ⋯ → Version history.", "Tap a version to preview it, then Restore. What was there is saved first, so you can undo."],
              keywords: "version history restore undo earlier backup page"),
        HowTo(id: "canvas", area: .notes, question: "Make a canvas whiteboard",
              steps: ["Notes → Canvas (or ✎ → New canvas).", "Add cards or existing pages, drag them anywhere, pinch to zoom.", "Select a card, tap Connect, then tap another card to draw an arrow."],
              keywords: "canvas whiteboard board map cards arrows visual"),
        HowTo(id: "tags", area: .notes, question: "Use #tags and saved searches",
              steps: ["Write #anything in a page, like #recipes.", "Notes → ✎ → Tags & saved searches shows every tag with its notes and tasks.", "Searching Notes? Tap Save search to keep it there."],
              keywords: "tags hashtag saved search filter"),
        HowTo(id: "publish", area: .notes, question: "Share a page as a web link",
              steps: ["Open the page → ⋯ → Publish to web.", "Send the link: anyone can read it, no Keel needed.", "Update web page after edits, or Unpublish to take it down."],
              keywords: "publish web link share page public"),
        HowTo(id: "reorganize", area: .notes, question: "Reorganize all my notes into workspaces",
              steps: ["Notes → tap ✨ Reorganize (or hold ✎ → Reorganize everything).", "Keel reads your pages and suggests workspaces (like Work, Personal, Faith) with subject folders inside.", "Rename anything, move a page, or untick what should stay put.", "Tap Apply. You can undo the whole thing from the same screen."],
              keywords: "organize workspace folders sort clean up structure notion"),
        HowTo(id: "folder", area: .notes, question: "Make a folder or workspace",
              steps: ["On Notes, tap New folder.", "To put it in a workspace, name it Workspace/Folder, like “Work/Clients”.", "Hold a folder to rename or remove it; its pages are kept."],
              keywords: "folder workspace create new"),
        HowTo(id: "move-folders", area: .notes, question: "Move folders to another workspace",
              steps: ["On Notes, press and hold a folder, then drag it into another workspace section and let go.", "To move several: tap Select (top of the first section), tap the folders, then drag any one of them, or tap Move to… and pick a workspace.", "Move to… → New workspace… makes a workspace and moves them into it."],
              keywords: "drag drop move folders bulk mass workspace select"),
        HowTo(id: "move-page", area: .notes, question: "Move a page into a folder",
              steps: ["Hold the page → Move to Folder.", "Pick a folder, or New folder… to make one."],
              keywords: "move file folder"),
        HowTo(id: "blocks", area: .notes, question: "Add headings, checklists, tables and more",
              steps: ["In a page, type / to open the block menu.", "Pick a heading, to-do, toggle, table, callout, image, page link or database.", "Use the toolbar above the keyboard for bold, colors and indent."],
              keywords: "format slash heading checklist table bold color"),
        HowTo(id: "link", area: .notes, question: "Link pages together",
              steps: ["Type [[ and the page name, or / → Link to page.", "See how everything connects in Notes → 🧠 Brain map."],
              keywords: "link backlink brain map graph"),
        HowTo(id: "database", area: .notes, question: "Make a database (table or board)",
              steps: ["Notes → hold ✎ → New database.", "Add columns, then switch between Table, Board, Calendar, Gallery and List views."],
              keywords: "database table board kanban"),
        HowTo(id: "lock", area: .notes, question: "Lock a private note",
              steps: ["Open the page → ⋯ → Lock page.", "It opens with Face ID. Locked pages are hidden from search, Spotlight and AI."],
              keywords: "private lock face id secret"),

        // Meetings
        HowTo(id: "record", area: .meetings, question: "Record a meeting and get notes",
              steps: ["Notes → Record, Today → ⊞ → Record a meeting, or type /meeting in a page.", "Pick the meeting type under the title.", "Jot quick notes in My notes if you like.", "Tap End. Keel writes the summary, action items, discussion points, decisions and the transcript."],
              tip: "Recording keeps going if you switch screens or lock your iPhone.",
              keywords: "meeting record transcript notes summary"),
        HowTo(id: "askmeeting", area: .meetings, question: "Ask a question about a meeting",
              steps: ["After the notes are written, scroll to Ask about this meeting.", "Ask anything, like “What did Sam say about the budget?”"],
              keywords: "ask question meeting transcript"),
        HowTo(id: "recap", area: .meetings, question: "Email everyone a recap",
              steps: ["After the notes are written, tap Email recap.", "Keel drafts the summary and next steps to everyone who was invited."],
              keywords: "recap email follow up"),

        // Focus & routines
        HowTo(id: "focus", area: .focus, question: "Start a focus session",
              steps: ["Tap Start focus above the tab bar.", "Pick a length; distracting apps are blocked until it ends.", "Or open Today → ⊞ → Focus room to work alongside a body double."],
              keywords: "focus timer pomodoro block apps body double"),
        HowTo(id: "routine", area: .focus, question: "Set up a morning or evening routine",
              steps: ["Today → ⊞ → Routines → New routine.", "Add steps with minutes and an optional finish-by time.", "Start it and Keel times each step, telling you if you're running late."],
              keywords: "routine morning evening steps timer"),
        HowTo(id: "resume", area: .focus, question: "Pick up where I left off",
              steps: ["Keel saves your place in notes, tasks and emails automatically.", "Today → ⊞ → Save points shows what you were doing, with the next step."],
              keywords: "save point resume interrupted where was i"),

        // Health
        HowTo(id: "scan", area: .health, question: "Check if a food fits my diet",
              steps: ["Today → ⊞ → Eat well → Scan food.", "Point at the barcode: 🟢 go for it, 🟡 sometimes, 🔴 skip, with the reason.", "Not found? Switch to Label and hold up the ingredients."],
              keywords: "scan barcode diet food allowed grocery"),
        HowTo(id: "tomorrow", area: .today, question: "See tomorrow before bed",
              steps: ["From 6 PM, Today shows Tomorrow: your first event, how many meetings, tasks due and any routine.", "Hide it from the card's ⋯ menu."],
              keywords: "tomorrow preview evening bedtime plan next day"),
        HowTo(id: "focusmusic", area: .focus, question: "Play music while I focus",
              steps: ["Start focus → Music: pick an Apple Music playlist, or Spotify, YouTube Music, Amazon Music, Pandora, Tidal, Audible or Podcasts.", "Apple Music plays with play, pause and skip on the focus screen and on the Lock Screen and Dynamic Island. Other apps open so you can press play; their own Lock Screen controls work as usual.", "Your focus sound keeps playing alongside. If you block apps during focus, leave your music app unblocked."],
              keywords: "music focus apple music spotify playlist lock screen dynamic island sound"),
        HowTo(id: "calendarai", area: .calendar, question: "Change my calendar by just saying it",
              steps: ["Calendar → menu → Change my calendar (or Compass → Think ahead).", "Type “move the dentist to Friday 3pm”, “delete lunch with Sam tomorrow”, “rename standup to Team sync” or “add gym Tuesday 6pm”.", "Keel shows exactly what it'll change; nothing happens until you tap Do it."],
              keywords: "ai calendar move reschedule delete cancel rename add event natural language"),
        HowTo(id: "routinebuilder", area: .calendar, question: "Turn repeat tasks into a routine on my calendar",
              steps: ["Calendar → menu → Turn repeat tasks into routines.", "Keel groups chores and habits from Tasks (meds, dishes, trash, watering plants) into Morning, Evening or Weekly reset routines.", "Set the time and days, untick anything that doesn't belong, then Create. The routine lands on your calendar as one repeating block and in Routines to run step by step; the loose tasks are cleared (Undo brings them back)."],
              keywords: "routine chores repeat tasks calendar morning evening weekly reset clean up"),
        HowTo(id: "readstatus", area: .inbox, question: "Know when someone opens my email (read statuses)",
              steps: ["Inbox → ⋯ → Read statuses, and turn on Track opens (it needs your Keel server: sign in under Settings → Account).", "While writing, Tell me when it's opened switches it on or off for that email.", "When it's opened you get a quiet alert, and Read statuses shows how many times and in which mail app.", "It's a hint, not proof: Apple Mail's privacy protection can load the image without anyone reading, and some people block images."],
              keywords: "read receipt read status opened tracking tracker superhuman seen open"),
        HowTo(id: "sendchecks", area: .inbox, question: "Avoid sending without the attachment",
              steps: ["When you tap Send, Keel checks for a mentioned-but-missing attachment, an empty subject, or more than 8 people.", "Pick Send anyway, Attach a file, or Keep editing."],
              keywords: "forgot attachment missing attached no subject check before send"),
        HowTo(id: "clashes", area: .calendar, question: "Sort out double-booked meetings",
              steps: ["Today shows calendar clashes in the next 7 days.", "Tap Can't make … to open an email to the organizer with three of your free times, or Move one to change it by just saying it.", "Turn the card off in Customize Keel → Today."],
              keywords: "clash conflict double booked overlap meetings decline regrets propose new time"),
        HowTo(id: "manytasks", area: .tasks, question: "Add a whole list of tasks at once",
              steps: ["Tap +, then paste or type a list: one per line, or “milk, eggs and bread”.", "Turn on Make N separate tasks, then Save. Each line becomes its own task (dates like “friday” still work). Undo removes them all."],
              keywords: "many tasks list paste bulk add multiple lines at once"),
        HowTo(id: "duptask", area: .tasks, question: "Avoid adding the same task twice",
              steps: ["When you type a task you already have, the + sheet says “You already have …” with its date, so you can skip it or add it anyway."],
              keywords: "duplicate task twice already have same"),
        HowTo(id: "focusreflect", area: .focus, question: "Learn when my focus sessions go best",
              steps: ["After a session (3 minutes or more), tap how it went: scattered, okay or locked in, and note what you got done if you like.", "Focus history shows how sessions felt lately and, after a few, whether mornings, afternoons or evenings go best.", "Turn the question off in Customize Keel → Focus."],
              keywords: "focus reflection how did it go rating best time session review"),
        HowTo(id: "buffers", area: .calendar, question: "Get breathing room after meetings",
              steps: ["Settings → Customize Keel → Calendar → Buffer after meetings: 5, 10, 15 or 30 minutes.", "Keel adds a “Buffer” block after each meeting for the next 7 days, on your Keel calendar, when that time is free. If a meeting moves, its buffer moves; turn it off and they're removed.", "Your booking link treats buffers as busy."],
              keywords: "buffer meetings back to back breathing room gap break calendar"),
        HowTo(id: "wrap", area: .today, question: "Get an end-of-day wrap-up",
              steps: ["It's on by default at 6 PM: a quiet note with how many things you finished and the first event and task tomorrow.", "Change the time or turn it off in Settings → Customize Keel → Today."],
              keywords: "end of day wrap up summary evening recap tomorrow"),
        HowTo(id: "quiet", area: .settings, question: "Stop Keel alerts overnight (quiet hours)",
              steps: ["Settings → Customize Keel → Quiet hours (or Settings → Notifications).", "Pick the hours, then whether Keel's alerts arrive silently or wait until morning.", "Medication reminders, alarms and time-sensitive alerts always come through."],
              keywords: "quiet hours night sleep do not disturb silence alerts notifications overnight"),
        HowTo(id: "sendarchive", area: .inbox, question: "Reply and get the email out of my inbox (Send & archive)",
              steps: ["While replying, hold the send button and choose Send & archive.", "To always do it, turn on Settings → Mail → Archive the conversation when I reply."],
              keywords: "send and archive reply archive inbox zero superhuman"),
        HowTo(id: "rollover", area: .tasks, question: "Move overdue tasks to today automatically",
              steps: ["Settings → Customize Keel → Tasks → Move overdue tasks to today each morning.", "The first time Keel opens each day, yesterday's leftovers move to today (same time of day). Repeating tasks keep their schedule. Tap Undo on the banner to put them back."],
              keywords: "overdue roll over carry over move to today automatically morning"),
        HowTo(id: "tasktrash", area: .tasks, question: "Get back a task I deleted",
              steps: ["Tasks → ⋯ → Recently deleted. Deleted tasks stay for 30 days.", "Tap Restore to bring one back with its notes, steps, tags and repeat."],
              keywords: "deleted task restore undo trash recover"),
        HowTo(id: "favpages", area: .notes, question: "Keep my most-used pages on Today",
              steps: ["Star a page (☆ at the top of the page, or long-press it in Notes → Add to Favorites).", "Favorite pages show as a row on Today; tap one to open it. Turn the row off in Customize Keel → Today."],
              keywords: "favorite pages today pinned notes quick access star"),
        HowTo(id: "customize", area: .settings, question: "Customize how Keel looks and works",
              steps: ["Settings → Customize Keel has a page for each part: Today, Inbox & mail, Calendar, Tasks, Notes, Focus, Body and Compass.", "Today: which cards show, weather, affirmation, shared items, routine card, and when Tomorrow appears. Tasks: sort order, the This Evening section, and what each task shows. Calendar: hour height, fading past events, default event length.", "Notes: folder cards or page tree, Jump back in, favorites, line spacing. Focus: starting level, sound, break lengths, music. Body: hide pages and pick the one it opens on. Compass: hide groups.", "Most screens also link straight to their own customize page from their ⋯ menu."],
              keywords: "customize customise personalize settings options layout hide show order sort"),
        HowTo(id: "signatures", area: .inbox, question: "Set a different signature (and name, color, alerts) for each email account",
              steps: ["Settings → Mail → Accounts & signatures, then tap an account.", "Set the name people see, the account's color, its signature (or start from a style), and a short reply signature, or turn signatures off on replies.", "Turn alerts on or off for that account, and make it the default for new emails.", "Under Reading & replying: when mail is marked read, whether replies quote the original, track opens by default, and the weekly unsubscribe report."],
              keywords: "signature per account email name color default account alerts notifications mark read quote reply customize settings"),
        HowTo(id: "unsubreport", area: .inbox, question: "See which mailing lists I never read",
              steps: ["Inbox → Sales & promos → Unsubscribe report: senders you open less than a quarter of the time, with how many they sent.", "Unsubscribe one by one or all at once; Keep means Keel won't ask again.", "On Sundays you get a quiet reminder (turn it off in Settings → Mail)."],
              keywords: "unsubscribe report newsletters never open weekly cleanup"),
        HowTo(id: "promos", area: .inbox, question: "Keep sales and promotional email out of my way",
              steps: ["Keel sorts store offers, discounts and cold sales pitches into their own Sales & promos tab automatically.", "They never show as Needs you, and Keel never drafts replies to them or to no-reply addresses. People you've written back to are never treated as a pitch.", "Reorder or hide tabs in Settings → Look & Feel → Inbox tabs."],
              keywords: "sales promotions promo marketing offers spam cold pitch category tab sort no reply"),
        HowTo(id: "getzero", area: .inbox, question: "Clear my inbox in one go (Get me to zero)",
              steps: ["Inbox → ⋯ → Get me to zero, then pick older than a day, a week or a month.", "Flagged, pinned and VIP mail stays. Tap Undo on the banner if you change your mind."],
              keywords: "inbox zero archive old bulk clear all superhuman"),
        HowTo(id: "intro", area: .inbox, question: "Reply to an introduction (Instant intro)",
              steps: ["Open the intro email and tap Reply all.", "Tap Instant intro: Keel thanks the person who introduced you, moves them to Bcc and addresses the reply to the person you were introduced to."],
              keywords: "introduction intro bcc move superhuman"),
        HowTo(id: "mute", area: .inbox, question: "Mute a noisy conversation",
              steps: ["Open the email → ⋯ → Mute conversation. New replies in that thread skip your inbox (they're archived, still searchable).", "Unmute from the same menu."],
              keywords: "mute thread conversation reply all noise"),
        HowTo(id: "sender", area: .inbox, question: "See who an email is from",
              steps: ["Tap the sender's name at the top of an email (or ⋯ → About the sender).", "See how often they write, whether you reply, recent subjects and their Keep in touch notes; make them a VIP, text them or look them up."],
              keywords: "sender profile who is this about contact superhuman social"),
        HowTo(id: "tone", area: .inbox, question: "Check how my email sounds before sending",
              steps: ["While writing, Keel flags things that can read as sharp (capitals, “per my last email”, no clear ask, very long).", "Tap How does this sound? for a read of the tone and a calmer version you can swap in with one tap.", "Late at night, Keel offers to send it at 8 AM instead."],
              keywords: "tone harsh rude anxious calm rsd soften kind send time late night"),
        HowTo(id: "logfood", area: .health, question: "Log what I ate",
              steps: ["Body → Food → Log food. Start typing: predictions with pictures appear after a letter or two, your usual foods first, then packaged products with their photos.", "Tap + to add a food to your plate, or tap the food to pick a portion. Type several at once, like “2 eggs, toast and a latte”, and tap Add all.", "Check the plate at the bottom (meal, time, portions), then Log. Each food is saved separately, checked against your diet, and sent to Apple Health if you turned that on.", "Food shows calories left, protein, carbs and fat against your goals; set calories in Goals & Apple Health."],
              keywords: "log meal calories protein nutrition search predict type food picture plate macros carbs fat"),
        HowTo(id: "applehealth", area: .health, question: "Send meals to Apple Health",
              steps: ["Settings → Health & Nutrition → Share with Apple Health.", "Allow the categories iOS asks about."],
              keywords: "apple health sync nutrition"),
        HowTo(id: "meds", area: .health, question: "Track my medication",
              steps: ["Settings → Medications → +.", "Set the dose and times. Reminders are Time Sensitive; mark taken from the notification or Apple Watch."],
              keywords: "meds medication pills dose reminder"),

        // AI
        HowTo(id: "claude", area: .ai, question: "Use Claude in Keel",
              steps: ["Get an API key at console.anthropic.com (Settings → API keys). Add a payment method there; Anthropic bills you per use, usually a few dollars a month.", "In Keel: Settings → AI & Privacy → AI Model → Claude → Claude Key, paste it and tap Test & Save.", "Keel then uses Claude for bigger jobs like day plans, drafts and meeting notes. A Claude Pro or Max chat subscription can't be connected; it has to be an API key."],
              keywords: "claude ai key api anthropic connect pro max subscription own"),
        HowTo(id: "private", area: .ai, question: "Keep everything on my iPhone",
              steps: ["Settings → AI & Privacy → turn on Private Mode.", "Keel then uses only Apple Intelligence on your iPhone."],
              keywords: "privacy private offline on device"),
        HowTo(id: "memory", area: .ai, question: "Teach Keel about me",
              steps: ["Ask Keel “Remember that my manager is Dana”.", "See or delete what it knows in Settings → AI & Privacy → What Keel Knows."],
              keywords: "memory remember facts"),

        // Settings & Watch
        HowTo(id: "opensettings", area: .start, question: "Open Settings",
              steps: ["Tap the gear at the top right of any tab: Today, Inbox, Calendar, Tasks or Notes.", "On Mac or iPad, Settings is also at the bottom of the sidebar, and ⌘, opens it.", "Use the search field at the top of Settings to jump straight to something, like “alarms” or “text size”.", "A red dot on the gear means you haven't signed in to sync your devices yet."],
              keywords: "settings preferences options gear where find"),
        HowTo(id: "textsize", area: .settings, question: "Make the text bigger",
              steps: ["Keel follows your iPhone text size.", "To change Keel only: Settings → Appearance → Text Size."],
              keywords: "text size font large accessibility zoom"),
        HowTo(id: "calm", area: .settings, question: "Make Keel calmer",
              steps: ["Settings → Appearance → Calm Mode.", "Today shows only your next thing; counts and red overdue dates disappear."],
              keywords: "calm minimal quiet counts"),
        HowTo(id: "watch", area: .settings, question: "Use Keel on Apple Watch",
              steps: ["Install Keel from the Watch app on your iPhone.", "Your tasks, habits, meds, routines, food and focus show up on your wrist. Add the complication for one-tap access."],
              keywords: "apple watch wrist complication"),
        HowTo(id: "mac", area: .settings, question: "Use Keel on my Mac",
              steps: ["Install Keel on your Mac from TestFlight (or the App Store once it's out).", "The tabs become a sidebar, and the menu bar has commands: ⌘N new task, ⇧⌘N new note, ⌘F search, ⌥⌘F focus, ⌘1–⌘5 to switch sections, ⌘K the command bar.", "Food scanning, full-screen alarms and app blocking stay on iPhone; on Mac you can type a barcode or paste a label instead."],
              keywords: "mac macbook desktop computer keyboard shortcuts"),
        HowTo(id: "widgets", area: .settings, question: "Add Keel widgets",
              steps: ["Touch and hold your Home Screen → Edit → Add Widget.", "Search Keel and pick a widget."],
              keywords: "widget home screen lock screen"),
        HowTo(id: "backup", area: .settings, question: "Back up my data",
              steps: ["Settings → Data & Storage → Back Up Now….", "Save the backup file to iCloud Drive or Files. Restore from the same screen on a new iPhone."],
              keywords: "backup restore export"),
    ]

    static func search(_ q: String, in area: HelpArea? = nil) -> [HowTo] {
        let pool = area.map { a in all.filter { $0.area == a } } ?? all
        let words = q.lowercased().split(separator: " ").map(String.init).filter { $0.count >= 2 }
        guard !words.isEmpty else { return pool }
        return pool
            .map { h -> (HowTo, Int) in
                let hay = (h.question + " " + h.keywords + " " + h.steps.joined(separator: " ")).lowercased()
                let title = h.question.lowercased()
                let score = words.reduce(0) { $0 + (title.contains($1) ? 3 : hay.contains($1) ? 1 : 0) }
                return (h, score)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }
}

/// The help center: browse by area or search “how do I…”.
struct HelpCenterView: View {
    var area: HelpArea? = nil
    @State private var search = ""

    var body: some View {
        List {
            if !search.isEmpty {
                let hits = HelpLibrary.search(search, in: area)
                if hits.isEmpty {
                    ContentUnavailableView {
                        Label("No answer yet", systemImage: "questionmark.bubble")
                    } description: {
                        Text("Try different words, or ask Keel in your own words.")
                    } actions: {
                        NavigationLink("Ask Keel") { AssistantView() }.buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
                ForEach(hits) { h in NavigationLink { LazyView(HowToView(item: h)) } label: { HowToRow(item: h) } }
            } else if let area {
                Section { ForEach(HelpLibrary.all.filter { $0.area == area }) { h in NavigationLink { LazyView(HowToView(item: h)) } label: { HowToRow(item: h, showArea: false) } } }
                Section { NavigationLink { LazyView(HelpCenterView()) } label: { Label("All help topics", systemImage: "books.vertical") } }
            } else {
                ForEach(HelpArea.allCases) { a in
                    Section {
                        ForEach(HelpLibrary.all.filter { $0.area == a }) { h in
                            NavigationLink { LazyView(HowToView(item: h)) } label: { HowToRow(item: h, showArea: false) }
                        }
                    } header: {
                        Label(a.title, systemImage: a.icon).font(DS.Font.headline).foregroundStyle(a.color).textCase(nil)
                    }
                }
                Section {
                    NavigationLink { LazyView(FeatureGuideView()) } label: { Label("Every feature, explained", systemImage: "book.pages") }
                    NavigationLink { LazyView(AssistantView()) } label: { Label("Ask Keel anything", systemImage: "bubble.left.and.text.bubble.right") }
                    NavigationLink { LazyView(KeelStatusView()) } label: { Label("Keel status (is everything connected?)", systemImage: "checkmark.seal") }
                    if let support = KeelServer.baseURL?.appendingPathComponent("support") {
                        Link(destination: support) { Label("Contact support", systemImage: "envelope") }
                        NavigationLink { LazyView(SupportMessagesView()) } label: { Label("Messages from your support page", systemImage: "tray") }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search, prompt: "How do I…")
        .navigationTitle(area.map { "Help: \($0.title)" } ?? "How do I…")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HowToRow: View {
    let item: HowTo
    var showArea = true
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.area.icon).font(.callout.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(item.area.color.gradient, in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.question).font(DS.Font.body)
                if showArea { Text(item.area.title).font(.caption2).foregroundStyle(DS.Palette.inkSoft) }
            }
        }
        .padding(.vertical, 2)
    }
}

struct HowToView: View {
    let item: HowTo
    var body: some View {
        List {
            Section {
                ForEach(Array(item.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(i + 1)").font(DS.Font.headline.monospacedDigit()).foregroundStyle(.white)
                            .frame(width: 26, height: 26).background(item.area.color.gradient, in: Circle())
                        Text(step).font(DS.Font.body).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text(item.question).font(DS.Font.title).foregroundStyle(DS.Palette.ink).textCase(nil).padding(.bottom, 4)
            }
            if let tip = item.tip {
                Section { Label(tip, systemImage: "lightbulb.fill").font(DS.Font.body).foregroundStyle(DS.Palette.ink) }
            }
            let related = HelpLibrary.all.filter { $0.area == item.area && $0.id != item.id }.prefix(3)
            if !related.isEmpty {
                Section("Related") {
                    ForEach(Array(related)) { h in NavigationLink { LazyView(HowToView(item: h)) } label: { HowToRow(item: h, showArea: false) } }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(item.area.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
