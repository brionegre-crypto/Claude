#if DEBUG
import Foundation
import SwiftData
import EventKit

/// Debug builds only: launch with `-KeelDemo YES` to fill Keel with made-up data for screenshots and profiling.
/// It signs into nothing: mail accounts are fake and never synced, and iCloud settings sync is skipped.
///
///     xcrun simctl launch booted com.briangreenejr.keel -KeelDemo YES
///
/// The KeelTour scheme (KeelUITests) launches Keel this way and walks every screen.
enum DemoData {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "KeelDemo") }   // launch arguments land in UserDefaults

    /// Before the first screen: settings that keep prompts and onboarding out of the way, plus Body's cache.
    @MainActor static func prepare() {
        guard isOn else { return }
        let d = UserDefaults.standard
        d.set(true, forKey: "onboarding.done")
        d.set(Discover.version, forKey: Discover.seenKey)
        d.set(true, forKey: "alarms.asked")
        seedBody()
        seedStore(KeelStore.container.mainContext)
    }

    private static let demoAccount = "gmail:alex.demo@example.com"

    @MainActor private static func seedStore(_ ctx: ModelContext) {
        let existing = (try? ctx.fetchCount(FetchDescriptor<TaskItem>())) ?? 0
        guard existing == 0 else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: cal.date(byAdding: .day, value: day, to: today)!)!
        }

        // Tasks: a realistic spread across lists, energy levels and dates.
        let tasks: [(String, Date?, TaskPriority, String, EnergyLevel)] = [
            ("Send the Q4 budget to Priya", at(0, 10, 30), .high, "Work", .high),
            ("Book dentist appointment", today, .medium, "Personal", .low),
            ("Review pull request #482", at(0, 14), .medium, "Work", .high),
            ("Pick up dry cleaning", today, .low, "Errands", .low),
            ("Draft the newsletter intro", at(1, 9), .medium, "Writing", .high),
            ("Call Mom", at(1, 18), .none, "Personal", .low),
            ("Renew passport", at(3, 0), .high, "Personal", .medium),
            ("Plan Saturday hike", at(2, 0), .low, "Personal", .medium),
            ("Update team roadmap slide", at(2, 11), .medium, "Work", .medium),
            ("Water the plants", today, .none, "Home", .low),
            ("Reply to landlord about lease", at(0, 16), .high, "Home", .medium),
            ("Order printer ink", nil, .none, "Errands", .low),
            ("Read chapter 4 of Deep Work", nil, .low, "Reading", .medium),
            ("Expense last week's train tickets", at(4, 0), .low, "Work", .low),
            ("Prep agenda for Friday 1:1", at(2, 15), .medium, "Work", .medium),
            ("Clean out garage shelf", nil, .none, "Home", .medium),
            ("Schedule car service", at(6, 0), .low, "Errands", .low),
            ("Write thank-you note to Sam", at(1, 0), .none, "Personal", .low),
            ("Back up laptop", at(5, 0), .medium, "Home", .low),
            ("Research standing desks", nil, .low, "Home", .medium),
        ]
        for (i, t) in tasks.enumerated() {
            let item = TaskItem(title: t.0, dueDate: t.1, priority: t.2)
            item.listName = t.3
            item.energy = t.4
            item.estimatedMinutes = [10, 15, 25, 30, 45][i % 5]
            if i == 0 { item.microSteps = [MicroStep(text: "Open the budget sheet", minutes: 2), MicroStep(text: "Check the totals", minutes: 8), MicroStep(text: "Attach and send", minutes: 3)] }
            ctx.insert(item)
        }
        for t in ["Morning pages", "Inbox zero", "Stretch for 5 minutes"] {
            let done = TaskItem(title: t, dueDate: today)
            done.isDone = true; done.completedAt = Date().addingTimeInterval(-3600); done.stage = "done"
            ctx.insert(done)
        }

        // Notes, including a meeting note with to-dos and a page with headings.
        let notes: [(String, [NoteBlock], Bool)] = [
            ("Weekly planning", [NoteBlock(kind: .heading, text: "This week"), NoteBlock(kind: .todo, text: "Finish the Q4 budget", checked: true),
                                 NoteBlock(kind: .todo, text: "Ship onboarding copy"), NoteBlock(kind: .todo, text: "1:1 with Jordan"),
                                 NoteBlock(kind: .heading2, text: "Notes"), NoteBlock(kind: .text, text: "Keep mornings for deep work. **No meetings before 11.**")], true),
            ("Product sync: 24 Nov", [NoteBlock(kind: .text, text: "Attendees: Priya, Jordan, Alex"), NoteBlock(kind: .bullet, text: "Launch moved to 8 Dec"),
                                      NoteBlock(kind: .bullet, text: "Need final icons from design"), NoteBlock(kind: .todo, text: "Alex: update roadmap slide")], false),
            ("Book notes: Deep Work", [NoteBlock(kind: .quote, text: "Clarity about what matters provides clarity about what does not."),
                                       NoteBlock(kind: .text, text: "Schedule every minute of the workday; time-block, then adjust.")], false),
            ("Gift ideas", [NoteBlock(kind: .bullet, text: "Sam: hiking poles"), NoteBlock(kind: .bullet, text: "Mom: framed photo"), NoteBlock(kind: .bullet, text: "Jordan: coffee beans")], false),
            ("Trip to Lisbon", [NoteBlock(kind: .heading, text: "Packing"), NoteBlock(kind: .todo, text: "Passport"), NoteBlock(kind: .todo, text: "Adapter"),
                                NoteBlock(kind: .heading, text: "Places"), NoteBlock(kind: .bullet, text: "Alfama"), NoteBlock(kind: .bullet, text: "LX Factory")], false),
            ("Recipe: lentil soup", [NoteBlock(kind: .numbered, text: "Sweat onion, carrot, celery"), NoteBlock(kind: .numbered, text: "Add lentils and stock"), NoteBlock(kind: .numbered, text: "Simmer 25 min")], false),
        ]
        for (i, n) in notes.enumerated() {
            let note = Note(title: n.0, blocks: n.1)
            note.isPinned = n.2
            note.updatedAt = Date().addingTimeInterval(Double(-i) * 7200)
            note.createdAt = note.updatedAt
            ctx.insert(note)
        }

        // A fake mail account (never synced: sync is off in demo mode) and an inbox's worth of messages.
        let acct = MailAccount(provider: .gmail, address: "alex.demo@example.com", displayName: "Alex (demo)")
        ctx.insert(acct)
        let mail: [(String, String, String, String, TriageCategory, Bool)] = [
            ("Priya Shah", "priya@example.com", "Q4 budget: can you send by Friday?", "Hi Alex, finance needs the Q4 numbers before the board pack goes out…", .important, false),
            ("Jordan Lee", "jordan@example.com", "Roadmap slide tweaks", "Two small changes for the roadmap slide before Thursday's review…", .actionable, false),
            ("Calendar", "calendar@example.com", "Invitation: Design review, Thu 2pm", "You've been invited to Design review on Thursday at 2:00 pm…", .calendar, false),
            ("Parcel Co", "track@example.com", "Your order is out for delivery", "Your package will arrive today between 1 and 5 pm.", .updates, true),
            ("The Morning Brief", "news@example.com", "5 things to know today", "Markets, weather and the story everyone's talking about…", .newsletters, true),
            ("Sam Rivera", "sam@example.com", "Saturday hike?", "Are we still on for Saturday? Thinking the ridge trail, 9am start.", .important, false),
            ("Landlord", "lettings@example.com", "Lease renewal", "Your lease is up for renewal on 1 January. Please confirm by…", .actionable, false),
            ("Shopfront", "deals@example.com", "40% off this weekend only", "Our biggest sale of the year starts now…", .promotions, true),
            ("GitHub", "noreply@example.com", "[keel] PR #482 ready for review", "Jordan requested your review on #482: Faster inbox list…", .updates, false),
            ("Dr. Okafor's office", "clinic@example.com", "Appointment reminder", "This is a reminder to book your 6-month check-up.", .actionable, true),
            ("Weekly Reads", "hello@example.com", "Issue 112: Calm productivity", "This week: why fewer choices make better days…", .newsletters, true),
            ("Mom", "mom@example.com", "Thanksgiving plans", "What time are you arriving on Thursday? I'll make the pie.", .important, false),
        ]
        for (i, m) in mail.enumerated() {
            let e = EmailMessage(accountId: acct.id, providerMessageId: "demo-\(i)", threadId: "demo-t\(i)", from: m.1, fromName: m.0,
                                 subject: m.2, snippet: m.3, bodyPlain: m.3 + "\n\nThanks,\n" + m.0, receivedAt: Date().addingTimeInterval(Double(-i) * 2700), isRead: m.5)
            e.category = m.4
            e.priorityScore = m.4 == .important ? 0.9 : m.4 == .actionable ? 0.7 : 0.3
            e.aiSummary = m.3
            e.triagedAt = Date()
            e.toLine = acct.address
            ctx.insert(e)
        }
        try? ctx.save()
    }

    /// Two weeks of made-up recovery and sleep, written to Body's cache before Body first loads it.
    private static func seedBody() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("body-days.json")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var days: [BodyDay] = []
        for i in stride(from: 20, through: 0, by: -1) {
            let day = cal.date(byAdding: .day, value: -i, to: today)!
            let wave = sin(Double(i) / 2.3)
            var d = BodyDay(day: day)
            d.hrv = 52 + wave * 9; d.rhr = 57 - wave * 3; d.resp = 14.2; d.spo2 = 97; d.temp = 0.1 * wave; d.vo2 = 44
            d.asleep = 410 + wave * 45; d.inBed = d.asleep + 30; d.deep = 70 + wave * 10; d.rem = 95; d.core = d.asleep - 165; d.awake = 20
            d.bedtime = cal.date(byAdding: .minute, value: -60 - Int(wave * 20), to: day); d.wake = cal.date(byAdding: .minute, value: 400, to: day)
            d.trimp = 60 + wave * 30; d.swell = Int(9 + wave * 4)
            d.stress = [0, 0, 1, 1, 0, 2, 1, 0, 0, 1, 0, 0, 0, 0, 0]
            d.tide = Int(68 + wave * 20); d.anchor = Int(80 + wave * 10); d.need = 7.5; d.calibrating = false
            days.append(d)
        }
        if let data = try? JSONEncoder().encode(days) { try? data.write(to: url, options: .atomic) }
    }

    /// Today's and this week's events, in the simulator's local calendar (grant calendar access first with
    /// `xcrun simctl privacy booted grant calendar com.briangreenejr.keel`).
    @MainActor static func seedEvents() async {
        guard isOn else { return }
        let svc = CalendarService.shared
        await svc.requestAccess()
        guard svc.hasCalendarAccess, let calendar = svc.store.defaultCalendarForNewEvents ?? svc.store.calendars(for: .event).first(where: \.allowsContentModifications) else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekEnd = today.addingTimeInterval(8 * 86_400)
        let have = svc.store.events(matching: svc.store.predicateForEvents(withStart: today, end: weekEnd, calendars: [calendar]))
        guard !have.contains(where: { $0.notes == "keel-demo" }) else { return }
        let plan: [(Int, Int, Int, Int, String, String?)] = [
            (0, 9, 0, 30, "Standup", "Zoom"), (0, 11, 0, 60, "Deep work: budget", nil), (0, 13, 0, 45, "Lunch with Priya", "Café Nero"),
            (0, 15, 30, 30, "Design review", "Room 4"), (0, 19, 0, 90, "Yoga", "Studio B"),
            (1, 9, 0, 30, "Standup", "Zoom"), (1, 14, 0, 60, "Roadmap review", "Room 2"), (1, 17, 0, 60, "Thanksgiving prep", nil),
            (2, 10, 0, 30, "1:1 with Jordan", "Zoom"), (2, 16, 0, 60, "Dentist", "Smile Clinic"),
            (3, 9, 0, 180, "Saturday hike", "Ridge trail"), (5, 9, 0, 30, "Standup", "Zoom"), (6, 12, 0, 60, "Team lunch", "Pizzeria"),
        ]
        for p in plan {
            let e = EKEvent(eventStore: svc.store)
            e.calendar = calendar
            e.title = p.4
            e.location = p.5
            e.notes = "keel-demo"
            e.startDate = cal.date(bySettingHour: p.1, minute: p.2, second: 0, of: cal.date(byAdding: .day, value: p.0, to: today)!)!
            e.endDate = e.startDate.addingTimeInterval(Double(p.3 * 60))
            try? svc.store.save(e, span: .thisEvent, commit: false)
        }
        try? svc.store.commit()
        svc.invalidateEvents()
    }
}
#endif
