import SwiftUI
import SwiftData
import EventKit

/// Home screen. ADHD rule: ONE focal point. The "Just One Thing" card dominates; everything else is quieter.
struct TodayView: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var tasks: [TaskItem]
    @Query(sort: \EmailMessage.priorityScore, order: .reverse) private var emails: [EmailMessage]
    @Query private var stacks: [HabitStack]
    @Query(sort: \Commitment.sentAt) private var commitments: [Commitment]
    @AppStorage("energy") private var energyRaw = EnergyLevel.medium.rawValue
    @AppStorage("year.theme") private var yearTheme = ""
    @Query(sort: \FollowUp.remindAt) private var followUps: [FollowUp]
    @Query private var idealBlocks: [IdealBlock]
    @Query(sort: \Person.name) private var people: [Person]
    @State private var scheduleMessage: String?
    @State private var sleepHours: Double?
    @AppStorage("energy.day") private var energyDay = ""
    @Query(sort: \Countdown.date) private var countdowns: [Countdown]
    @State private var plan: DayPlan?
    @State private var planning = false
    @State private var showSettings = false
    @State private var showBrainDump = false
    @State private var showSOS = false
    @AppStorage(Prefs.calm) private var calm = false

    private var energy: EnergyLevel { EnergyLevel(rawValue: energyRaw) ?? .medium }
    private var nextThing: TaskItem? { ADHDCoach.nextThing(tasks: tasks, energy: energy) }
    private var events: [EKEvent] { CalendarService.shared.todaysEvents().filter { $0.endDate > Date() } }
    /// "Up next" skips all-day events (holidays, birthdays): they have no start to count down to.
    private var upNextEvents: [EKEvent] { events.filter { !$0.isAllDay } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    greeting
                    AutopilotTodayCard()
                    MedsTodayCard()
                    if calm {
                        // Calm mode: just the next thing and what's coming. Everything else waits.
                        justOneThing
                        if !upNextEvents.isEmpty { upNext }
                        Label("Calm mode is on. Everything else is still here when you want it.", systemImage: "leaf")
                            .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    } else {
                        PinnedTasksCard()
                        FoundInMailTodayCard()
                        TripTodayCard()
                        // Today reshapes itself through the day: plan in the morning, do in the day, wind down at night.
                        switch DayPhase.now {
                        case .morning:
                            PlanRitualPrompt()
                            CheckInCard()
                            energyPicker
                            justOneThing
                            planCard
                            if !upNextEvents.isEmpty { upNext }
                        case .day:
                            energyPicker
                            justOneThing
                            if !upNextEvents.isEmpty { upNext }
                            planCard
                            CheckInCard()
                        case .evening:
                            NavigationLink { DayReviewView() } label: { dayReviewTeaser }.buttonStyle(.plain)
                            CheckInCard()
                            if !upNextEvents.isEmpty { upNext }
                            justOneThing
                        }
                        countdownCard
                        promisesCard
                        followUpsCard
                        keepInTouchCard
                        if WeeklyReview.isDue {
                            NavigationLink { WeeklyReviewView() } label: {
                                GlassCard(tint: .purple) {
                                    Label("Your weekly review is ready · 10 min", systemImage: "chart.bar.doc.horizontal")
                                        .font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        attentionCard
                        avoidedCard
                    }
                }
                .padding(DS.Space.m)
            }
            .background(DS.Palette.canvas)
            .refreshable { await SyncEngine.shared.syncAll() }
            .task {
                // Short night → suggest a gentler day, unless you've already picked your energy today.
                sleepHours = await HealthService.shared.lastNightSleepHours()
                let today = Date().formatted(.iso8601.year().month().day())
                if let h = sleepHours, energyDay != today {
                    energyRaw = HealthService.energy(forSleep: h).rawValue
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSOS = true } label: { Image(systemName: "lifepreserver") }
                        .accessibilityLabel("I'm overwhelmed")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showBrainDump = true } label: { Image(systemName: "brain.head.profile") }
                        .accessibilityLabel("Brain dump")
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { SearchView() } label: { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel("Search everything")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink { GoalsView() } label: { Label("Goals", systemImage: "target") }
                        NavigationLink { ProjectsView() } label: { Label("Projects", systemImage: "folder") }
                        NavigationLink { ProcessInboxView() } label: { Label("Sort loose tasks", systemImage: "tray.and.arrow.down") }
                        NavigationLink { HabitsView() } label: { Label("Habit stacks", systemImage: "link") }
                        NavigationLink { AutopilotView() } label: { Label("Autopilot", systemImage: "sparkles") }
                        NavigationLink { TalkView() } label: { Label("Talk to Keel", systemImage: "waveform") }
                        Toggle(isOn: $calm) { Label("Calm mode", systemImage: "leaf") }
                        NavigationLink { PlanRitualView() } label: { Label("Plan my day", systemImage: "list.bullet.clipboard") }
                        NavigationLink { HabitLibraryView() } label: { Label("Habit library", systemImage: "books.vertical") }
                        NavigationLink { MedsView() } label: { Label("Medications", systemImage: "pills") }
                        NavigationLink { DopamineMenuView() } label: { Label("Dopamine menu", systemImage: "fork.knife") }
                        NavigationLink { SubscriptionsView() } label: { Label("Subscriptions & bills", systemImage: "creditcard") }
                        NavigationLink { DeliveriesView() } label: { Label("Deliveries", systemImage: "shippingbox") }
                        NavigationLink { TripsView() } label: { Label("Trips", systemImage: "airplane") }
                        NavigationLink { AchievementsView() } label: { Label("Achievements", systemImage: "trophy") }
                        NavigationLink { FocusHistoryView() } label: { Label("Focus history", systemImage: "chart.bar.xaxis") }
                        NavigationLink { JournalTimelineView() } label: { Label("Mood journal", systemImage: "face.smiling") }
                        NavigationLink { SharedCalendarsView() } label: { Label("Shared calendars", systemImage: "person.3") }
                        NavigationLink { WeeklyReviewView() } label: { Label("Weekly review", systemImage: "chart.bar.doc.horizontal") }
                        NavigationLink { MonthlyReviewView() } label: { Label("Monthly review", systemImage: "calendar.badge.checkmark") }
                        NavigationLink { PeopleView() } label: { Label("Keep in touch", systemImage: "person.2") }
                        NavigationLink { CountdownsView() } label: { Label("Countdowns", systemImage: "hourglass") }
                        NavigationLink { ScreenshotTasksView() } label: { Label("Tasks from screenshots", systemImage: "camera.viewfinder") }
                        NavigationLink { TimeAuditView() } label: { Label("Time audit", systemImage: "chart.pie") }
                        NavigationLink { IdealWeekView() } label: { Label("Ideal week", systemImage: "calendar.badge.clock") }
                        NavigationLink { ReadLaterView() } label: { Label("Read later", systemImage: "books.vertical") }
                        NavigationLink { MeetingRecorderView() } label: { Label("Record a meeting", systemImage: "mic") }
                        NavigationLink { OdysseyView() } label: { Label("Odyssey plan", systemImage: "point.3.filled.connected.trianglepath.dotted") }
                        NavigationLink { AssistantView() } label: { Label("Ask Keel", systemImage: "sparkles") }
                        NavigationLink { FeatureGuideView() } label: { Label("How Keel works", systemImage: "questionmark.circle") }
                    } label: { Image(systemName: "square.grid.2x2") }
                    .accessibilityLabel("More")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "person.crop.circle") }
                }
            }
            .sheet(isPresented: $showSettings) { AccountsView() }
            .sheet(isPresented: $showBrainDump) { BrainDumpView() }
            .fullScreenCover(isPresented: $showSOS) { OverwhelmedView() }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).textCase(.uppercase)
            Text(greetingText).font(DS.Font.hero)
            WeatherRow()
            if !yearTheme.isEmpty {
                Label(yearTheme, systemImage: "sparkle").font(DS.Font.caption).foregroundStyle(DS.Palette.accent)
            }
        }
    }

    private var greetingText: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case ..<12: "Good morning"
        case ..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private var energyPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            energyButtons
            if let h = sleepHours {
                Text("Suggested from \(Int(h))h \(Int((h - Double(Int(h))) * 60))m of sleep").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
            }
        }
    }

    private var energyButtons: some View {
        HStack(spacing: DS.Space.s) {
            Text("Energy").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            ForEach(EnergyLevel.allCases) { level in
                Button {
                    withAnimation(DS.spring) { energyRaw = level.rawValue }; Haptics.tap()
                    energyDay = Date().formatted(.iso8601.year().month().day())
                } label: {
                    Label(level.label, systemImage: level.icon).font(DS.Font.caption)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(energy == level ? DS.Palette.accent.opacity(0.16) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(energy == level ? DS.Palette.accent : DS.Palette.inkSoft)
            }
        }
    }

    private var justOneThing: some View {
        GlassCard(tint: DS.Palette.focus) {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Text("JUST ONE THING").font(DS.Font.caption).foregroundStyle(DS.Palette.focus)
                if let t = nextThing {
                    Text(t.title).font(DS.Font.title)
                    if let step = t.microSteps.first(where: { !$0.done }) {
                        Label("Start with: \(step.text)", systemImage: "arrow.turn.down.right")
                            .font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
                    }
                    HStack {
                        Chip(text: "~\(ADHDCoach.calibratedMinutes(t)) min", color: DS.Palette.focus, icon: "clock")
                        if let due = t.dueDate { Chip(text: due.formatted(.relative(presentation: .named)), color: DS.Palette.warmth) }
                        Spacer()
                        NavigationLink { FocusView(preselected: t) } label: {
                            Label("Start", systemImage: "play.fill").font(DS.Font.headline)
                                .padding(.horizontal, DS.Space.m).padding(.vertical, DS.Space.s)
                                .background(DS.Palette.focus, in: Capsule()).foregroundStyle(.white)
                        }
                    }
                } else {
                    Text("Nothing urgent. Enjoy the space — or pick a habit stack.").font(DS.Font.body)
                }
            }
        }
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            SectionHeader(title: "Up next", trailing: "all calendars")
            ForEach(upNextEvents.prefix(3), id: \.eventIdentifier) { e in
                HStack(spacing: DS.Space.m) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(cgColor: e.calendar.cgColor)).frame(width: 4, height: 34)
                    VStack(alignment: .leading) {
                        Text(e.title ?? "Event").font(DS.Font.headline)
                        Text("\(e.startDate.formatted(date: .omitted, time: .shortened)) · \(e.calendar.source.title)")
                            .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        if e.attendees?.isEmpty == false {
                            NavigationLink { MeetingPrepView(event: e) } label: {
                                Label("Prep", systemImage: "doc.text.magnifyingglass").font(DS.Font.caption)
                            }
                        }
                        if let leave = LeaveBy.times[e.calendarItemIdentifier] {
                            Label("Leave by \(leave.formatted(date: .omitted, time: .shortened))", systemImage: "car.fill")
                                .font(DS.Font.caption).foregroundStyle(leave < Date() ? .red : DS.Palette.warmth)
                        }
                    }
                    Spacer()
                    // Time-blindness aid: countdown, not a timestamp ("Now" once it has started)
                    Group {
                        if e.startDate <= Date() { Text("Now") } else { Text(e.startDate, style: .relative) }
                    }.font(DS.Font.caption).foregroundStyle(DS.Palette.meeting)
                }
            }
        }
    }

    private var planCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack {
                    Text("Today's plan").font(DS.Font.headline)
                    Spacer()
                    Button("Auto-schedule") {
                        let r = AutoScheduler.scheduleToday(tasks: tasks)
                        scheduleMessage = r.scheduled == 0 ? "No free time left today, or nothing to schedule."
                            : "Scheduled \(r.scheduled) task\(r.scheduled == 1 ? "" : "s") on your calendar" + (r.unscheduled.isEmpty ? "." : "; \(r.unscheduled.count) didn't fit.")
                    }.font(DS.Font.caption)
                    Button("Reset my day") {
                        ADHDCoach.resetDay(tasks: tasks); Haptics.success()
                        Task { await makePlan() }
                    }.font(DS.Font.caption)
                }
                if let scheduleMessage { Text(scheduleMessage).font(DS.Font.caption).foregroundStyle(DS.Palette.calm) }
                if planning { ProgressView().frame(maxWidth: .infinity) }
                else if let plan {
                    Text(plan.headline).font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
                    ForEach(plan.blocks) { b in
                        HStack {
                            Text(b.start).font(DS.Font.caption.monospacedDigit()).frame(width: 48, alignment: .leading)
                            Text(b.title).font(DS.Font.body)
                            Spacer()
                            Image(systemName: icon(for: b.kind)).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                } else {
                    Button { Task { await makePlan() } } label: {
                        Label("Plan my day with AI", systemImage: "sparkles").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(DS.Palette.accent)
                }
            }
        }
    }

    private var attentionCard: some View { NeedsYouCard() }

    /// Promise tracker teaser: only shows when something is owed today or overdue.
    private var promisesCard: some View {
        let open = commitments.filter { $0.status == .open && !$0.likelyKept }
        let pressing = open.filter { $0.effectiveDue < Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))! }
        return Group {
            if let first = pressing.first {
                NavigationLink { PromisesView() } label: {
                    GlassCard(tint: DS.Palette.warmth) {
                        HStack(spacing: DS.Space.m) {
                            Image(systemName: "hand.raised.fingers.spread").font(.title2).foregroundStyle(DS.Palette.warmth)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pressing.count == 1 ? "You promised \(first.displayName)" : "\(pressing.count) promises due")
                                    .font(DS.Font.headline)
                                Text("“\(first.promise)”").font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var countdownCard: some View {
        let soon = countdowns.filter { $0.daysLeft >= 0 && $0.daysLeft <= 30 }.first
        return Group {
            if let c = soon {
                NavigationLink { CountdownsView() } label: {
                    GlassCard {
                        HStack {
                            Text(c.emoji).font(.title)
                            Text(c.title).font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                            Spacer()
                            Text(c.daysLeft == 0 ? "Today!" : "in \(c.daysLeft) day\(c.daysLeft == 1 ? "" : "s")")
                                .font(DS.Font.headline).foregroundStyle(DS.Palette.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dayReviewTeaser: some View {
        return GlassCard(tint: .indigo) {
            HStack(spacing: DS.Space.m) {
                Image(systemName: "moon.stars.fill").font(.title2).foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Day in review").font(DS.Font.headline)
                    Text("See what you got done and close today in 2 minutes.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(DS.Palette.inkSoft)
            }
        }
        .accessibilityHint("Evening wind-down")
    }

    private var keepInTouchCard: some View {
        let due = people.filter(\.isDue).sorted { $0.nextDue < $1.nextDue }
        return Group {
            if let p = due.first {
                GlassCard(tint: .pink) {
                    HStack(spacing: DS.Space.m) {
                        Image(systemName: "heart.text.square").font(.title2).foregroundStyle(.pink)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reach out to \(p.name)").font(DS.Font.headline)
                            Text(p.lastContact.map { "Last in touch \($0.formatted(.relative(presentation: .named)))" } ?? "It's been a while")
                                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        ReachOutButtons(person: p)
                    }
                }
            }
        }
    }

    private var followUpsCard: some View {
        let due = followUps.filter(\.isDue)
        return Group {
            if let first = due.first {
                Button { MailRouter.shared.pending = FollowUps.nudgeDraft(first) } label: {
                    GlassCard(tint: DS.Palette.meeting) {
                        HStack(spacing: DS.Space.m) {
                            Image(systemName: "bubble.left.and.exclamationmark.bubble.right").font(.title2).foregroundStyle(DS.Palette.meeting)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(due.count == 1 ? "No reply from \(first.recipientName.isEmpty ? first.recipient : first.recipientName)" : "\(due.count) people haven't replied")
                                    .font(DS.Font.headline)
                                Text("Tap to send a friendly nudge").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                            }
                            Spacer()
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var avoidedCard: some View {
        let avoided = ADHDCoach.avoidedTasks(tasks)
        return Group {
            if let t = avoided.first {
                GlassCard(tint: DS.Palette.warmth) {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text("“\(t.title)” keeps sliding. That's normal.").font(DS.Font.headline)
                        Text("Want to shrink it, do it together for 10 minutes, or let it go?").font(DS.Font.body)
                        HStack {
                            NavigationLink("Shrink it") { TaskDetailView(task: t) }
                            Spacer()
                            NavigationLink("Body double") { FocusView(preselected: t, bodyDouble: true) }
                            Spacer()
                            Button("Let it go") { t.listName = "Someday"; t.dueDate = nil }
                        }.font(DS.Font.caption)
                    }
                }
            }
        }
    }

    private func icon(for kind: String) -> String {
        ["focus": "scope", "meeting": "person.2", "email": "tray", "habit": "link", "break": "cup.and.saucer", "shutdown": "moon.zzz"][kind] ?? "circle"
    }

    private func makePlan() async {
        planning = true; defer { planning = false }
        let ctxData = DayContext(
            now: Date().formatted(date: .abbreviated, time: .shortened),
            events: events.map { "\($0.startDate.formatted(date: .omitted, time: .shortened))-\($0.endDate.formatted(date: .omitted, time: .shortened)) \($0.title ?? "")" },
            tasks: tasks.prefix(20).map { "\($0.title) [~\(ADHDCoach.calibratedMinutes($0))m, energy \($0.energy.label)]" },
            importantEmails: emails.filter { $0.category == .important }.prefix(5).map { $0.subject },
            habitStacks: stacks.map { "\($0.name): \($0.anchor.label)" },
            weather: KeelWeather.shared.today?.plannerLine ?? "",
            idealWeek: idealBlocks.filter { $0.weekdays.contains(Calendar.current.component(.weekday, from: Date())) }
                .sorted { $0.startMinute < $1.startMinute }.map { "\($0.timeLabel) \($0.title) (\($0.area.title))" })
        plan = await AIRouter.shared.planDay(context: ctxData)
    }
}

/// "18° · Partly Cloudy · H 21° L 12° · rain from 3 PM" with Apple Weather attribution.
struct WeatherRow: View {
    @State private var weather = KeelWeather.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if let w = weather.today {
                HStack(spacing: 6) {
                    Image(systemName: w.symbol).symbolRenderingMode(.multicolor)
                    Text("\(w.temperature) · \(w.condition) · H \(w.high) L \(w.low)")
                    if let r = w.rainStartsAt {
                        Text("· rain from \(r.formatted(date: .omitted, time: .shortened))").foregroundStyle(DS.Palette.meeting)
                    }
                    Spacer()
                    if let logo = scheme == .dark ? weather.logoDark : weather.logoLight {
                        Button { if let l = weather.legalURL { openURL(l) } } label: {
                            AsyncImage(url: logo) { $0.resizable().scaledToFit() } placeholder: { Color.clear }.frame(height: 10)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Weather data from Apple Weather")
                    }
                }
                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
        }
        .task { await weather.refresh() }
    }
}
