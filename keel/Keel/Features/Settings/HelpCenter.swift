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
        HowTo(id: "logfood", area: .health, question: "Log what I ate",
              steps: ["After a scan, tap Log it. Or Today → ⊞ → Log a meal and describe it.", "See protein, fiber, added sugar and brain foods in Food today."],
              keywords: "log meal calories protein nutrition"),
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
              steps: ["Install Keel on your Mac from TestFlight (or the App Store once it's out).", "The tabs become a sidebar, and the menu bar has commands: ⌘N new task, ⇧⌘N new note, ⌘F search, ⇧⌘F focus, ⌘1–⌘5 to switch sections, ⌘K the command bar.", "Food scanning, full-screen alarms and app blocking stay on iPhone; on Mac you can type a barcode or paste a label instead."],
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
                ForEach(hits) { h in NavigationLink { HowToView(item: h) } label: { HowToRow(item: h) } }
            } else if let area {
                Section { ForEach(HelpLibrary.all.filter { $0.area == area }) { h in NavigationLink { HowToView(item: h) } label: { HowToRow(item: h, showArea: false) } } }
                Section { NavigationLink { HelpCenterView() } label: { Label("All help topics", systemImage: "books.vertical") } }
            } else {
                ForEach(HelpArea.allCases) { a in
                    Section {
                        ForEach(HelpLibrary.all.filter { $0.area == a }) { h in
                            NavigationLink { HowToView(item: h) } label: { HowToRow(item: h, showArea: false) }
                        }
                    } header: {
                        Label(a.title, systemImage: a.icon).font(DS.Font.headline).foregroundStyle(a.color).textCase(nil)
                    }
                }
                Section {
                    NavigationLink { FeatureGuideView() } label: { Label("Every feature, explained", systemImage: "book.pages") }
                    NavigationLink { AssistantView() } label: { Label("Ask Keel anything", systemImage: "bubble.left.and.text.bubble.right") }
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
                    ForEach(Array(related)) { h in NavigationLink { HowToView(item: h) } label: { HowToRow(item: h, showArea: false) } }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(item.area.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
