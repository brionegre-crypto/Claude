import SwiftUI
import TipKit
import SwiftData
import EventKit

/// Home screen. ADHD rule: ONE focal point. The "Just One Thing" card dominates; everything else is quieter.
struct TodayView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var multiWindow
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var tasks: [TaskItem]
    @Query(TodayView.topEmails) private var emails: [EmailMessage]     // top 60 by priority, not the whole mailbox
    /// Recently finished tasks, so cards on Today show what's already done (wherever you checked it off).
    @Query(TodayView.recentlyDoneQuery) private var recentlyDone: [TaskItem]
    static var recentlyDoneQuery: FetchDescriptor<TaskItem> {
        var d = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isDone }, sortBy: [SortDescriptor(\.completedAt, order: .reverse)])
        d.fetchLimit = 80
        return d
    }
    /// The open task a plan block is about (same title), or nil.
    private func openTask(for title: String) -> TaskItem? {
        let key = NoteText.fold(title)
        guard !key.isEmpty else { return nil }
        return tasks.first { NoteText.fold($0.title) == key }
    }
    private func doneToday(_ title: String) -> Bool {
        let key = NoteText.fold(title)
        return recentlyDone.contains { ($0.completedAt.map(Calendar.current.isDateInToday) ?? false) && NoteText.fold($0.title) == key }
    }
    static var topEmails: FetchDescriptor<EmailMessage> {
        var d = FetchDescriptor<EmailMessage>(predicate: #Predicate { !$0.isArchived }, sortBy: [SortDescriptor(\.priorityScore, order: .reverse)])
        d.fetchLimit = 60
        return d
    }
    @Query private var stacks: [HabitStack]
    @Query(sort: \Commitment.sentAt) private var commitments: [Commitment]
    @AppStorage("energy") private var energyRaw = EnergyLevel.medium.rawValue
    @AppStorage("year.theme") private var yearTheme = ""
    @Query(sort: \FollowUp.remindAt) private var followUps: [FollowUp]
    @Query private var idealBlocks: [IdealBlock]
    @Query(sort: \Person.name) private var people: [Person]
    @State private var scheduleMessage: String?
    @State private var sleepHours: Double?
    @State private var tideForEnergy: Int?
    @AppStorage("energy.day") private var energyDay = ""
    @Query(sort: \Countdown.date) private var countdowns: [Countdown]
    @State private var plan: DayPlan?
    @State private var planning = false
    @State private var showSettings = false
    @State private var showBrainDump = false
    @State private var showSOS = false
    @State private var showRitual = false
    @State private var dest: TodayDest?

    enum TodayDest: Hashable { case compass, quickWins, timer, customize, focusRoom, forecast, savePoints, dopamine, breathe, dread, dayReview, ask, coach, help }
    @AppStorage(Prefs.calm) private var calm = false
    @AppStorage(DailyAffirmation.toggleKey) private var showAffirmation = true

    private var energy: EnergyLevel { EnergyLevel(rawValue: energyRaw) ?? .medium }
    private var nextThing: TaskItem? { ADHDCoach.nextThing(tasks: tasks, energy: energy) }
    private var events: [EKEvent] { CalendarService.shared.todaysEvents().filter { $0.endDate > Date() && CalendarRoles.shows($0) } }
    /// "Up next" skips all-day events (holidays, birthdays): they have no start to count down to.
    private var upNextEvents: [EKEvent] { events.filter { !$0.isAllDay } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    if Custom.todayShared { SharedToKeelCard() }    // anything you just shared to Keel, right at the top
                    greeting
                        .inlineTip(OpenWaterTip())                  // each tip shows once, at most one new tip a day; takes no room until it shows
                        .inlineTip(CaptureTip())
                    DailyAffirmationCard()                          // on/off: Today menu, or the card's own menu
                    if Custom.todayRoutine { UpcomingRoutineCard() } // a routine on your calendar, ready to start
                    if Calendar.current.component(.hour, from: Date()) >= Custom.tomorrowHour {
                        TomorrowPreviewCard()                       // evenings: tomorrow at a glance (not built during the day)
                    }
                    FavoritePagesCard()                             // starred pages, one tap away
                    ClashesCard()                                   // overlapping events this week, with a fix
                    PinnedEmailsCard()                              // emails you pinned in Inbox
                    if UserDefaults.standard.object(forKey: "custom.today.voyage") as? Bool ?? true {
                        VoyageView()                                // your day as a route: now, ports, open water, anchor
                    }
                    if UserDefaults.standard.object(forKey: "custom.today.nextPeople") as? Bool ?? true {
                        NextMeetingPeopleCard()                     // who you're meeting next, with Running late and Prep
                    }
                    if UserDefaults.standard.object(forKey: "custom.today.waterline") as? Bool ?? true {
                        Waterline(label: "Below the waterline · the rest of your day")
                    }
                    ForEach((calm ? TodayCard.calm : TodayCard.current(phase: DayPhase.now)).filter { $0 != .upNext && $0 != .oneThing }) { card($0) }
                    if calm {
                        Label("Calm mode is on. Everything else is still here when you want it.", systemImage: "leaf")
                            .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                    NavigationLink { LazyView(CustomizeTodayView()) } label: {
                        Label("Customize Today", systemImage: "slider.horizontal.3").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(DS.Space.m)
            }
            .premiumBackground(DS.Palette.accent)
            .scrollEdgeEffectStyle(.hard, for: .top)          // content no longer smears under the top buttons
            .refreshable { await SyncEngine.shared.syncAll() }
            .onAppear { PinnedMailStore.shared.load(ctx) }       // pinned emails, read once per visit
            .task {
                // Short night → suggest a gentler day, unless you've already picked your energy today.
                // Once is enough: asking Health again on every return to Today redrew the screen mid-transition.
                guard sleepHours == nil else { return }
                try? await Task.sleep(for: .milliseconds(400))
                sleepHours = await HealthService.shared.lastNightSleepHours()
                let today = Date().formatted(.iso8601.year().month().day())
                // Tide (recovery) is the better guide when there is one; otherwise hours of sleep.
                if energyDay != today, let tide = BodyScores.today()?.tide {
                    energyRaw = BodyEngine.energy(forTide: tide).rawValue
                    tideForEnergy = tide
                } else if let h = sleepHours, energyDay != today {
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
                if multiWindow {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { openWindow(id: "quick") } label: { Image(systemName: "rectangle.inset.topright.filled") }
                            .accessibilityLabel("Open the Quick window")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { LazyView(SearchView()) } label: { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel("Search everything")
                }
                ToolbarItem(placement: .topBarTrailing) { dayMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { AppRouter.shared.showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showBrainDump) { BrainDumpView() }
            .fullScreenCover(isPresented: $showSOS) { OverwhelmedView() }
            .sheet(isPresented: $showRitual) { ShutdownRitualView() }
            .navigationDestination(item: $dest) { d in
                switch d {
                case .compass: HubView()
                case .quickWins: QuickWinsView()
                case .timer: VisualTimerView()
                case .customize: CustomizeTodayView()
                case .focusRoom: FocusRoomView()
                case .forecast: FocusForecastView()
                case .savePoints: SavePointsView()
                case .dopamine: DopamineMenuView()
                case .breathe: BreatheView()
                case .dread: DreadRadarView()
                case .dayReview: DayReviewView()
                case .ask: AssistantView()
                case .coach: CoachView()
                case .help: HelpCenterView()
                }
            }
        }
    }

    /// Tap: Compass (every tool). Hold: the day, from planning it to closing it down, in the order you'd need it.
    private var dayMenu: some View {
        Menu {
            Button("Open Compass: every tool", systemImage: "square.grid.2x2") { dest = .compass }
            Section("Ask & coach") {
                Button("Ask Keel", systemImage: "bubble.left.and.text.bubble.right.fill") { dest = .ask }
                Button("Coach check-in", systemImage: "figure.mind.and.body") { dest = .coach }
            }
            Section("Start the day") {
                Button("Plan my day", systemImage: "list.bullet.clipboard") { AppRouter.shared.showPlan = true }
                Button("Quick wins (5 minutes or less)", systemImage: "bolt.fill") { dest = .quickWins }
                Button("Visual timer", systemImage: "timer") { dest = .timer }
            }
            Section("Stay on track") {
                Button("Start focus", systemImage: "scope") { AppRouter.shared.showFocus = true }
                Button("Focus room (work alongside someone)", systemImage: "person.2.wave.2.fill") { dest = .focusRoom }
                Button("My best focus hours", systemImage: "chart.bar.fill") { dest = .forecast }
                Button("Where was I? (save points)", systemImage: "bookmark.fill") { dest = .savePoints }
                Button("Dopamine menu", systemImage: "dice.fill") { dest = .dopamine }
            }
            Section("When it's hard") {
                Button("I'm overwhelmed", systemImage: "lifepreserver") { showSOS = true }
                Button("Brain dump", systemImage: "brain.head.profile") { showBrainDump = true }
                Button("Breathe for 2 minutes", systemImage: "wind") { dest = .breathe }
                Button("What am I avoiding?", systemImage: "tortoise.fill") { dest = .dread }
            }
            Section("Close the day") {
                Button("Review today", systemImage: "checkmark.seal") { dest = .dayReview }
                Button("Shutdown ritual", systemImage: "moon.stars") { showRitual = true }
                Button("Weekly review", systemImage: "calendar.badge.checkmark") { AppRouter.shared.showReview = true }
                Button("Journal", systemImage: "book") { AppRouter.shared.showJournal = true }
                NavigationLink { LazyView(WeeklyWinsView()) } label: { Label("This week's wins", systemImage: "trophy") }
            }
            Toggle(isOn: $showAffirmation) { Label("Daily affirmation", systemImage: "quote.bubble") }
            Button("Customize Today", systemImage: "slider.horizontal.3") { dest = .customize }
            NavigationLink { LazyView(CustomizeHubView()) } label: { Label("Customize all of Keel", systemImage: "paintbrush.pointed") }
            Button("How do I… (help)", systemImage: "questionmark.circle") { dest = .help }
        } label: {
            Image(systemName: "square.grid.2x2")
        } primaryAction: {
            dest = .compass
        }
        .accessibilityLabel("Compass. Hold for day tools")
    }

    /// "in 44 min", "in 2 hr 10 min": calm, readable, no ticking seconds.
    static func untilLabel(_ d: Date) -> String {
        let m = max(1, Int(d.timeIntervalSinceNow / 60))
        return m < 60 ? "in \(m) min" : m % 60 == 0 ? "in \(m / 60) hr" : "in \(m / 60) hr \(m % 60) min"
    }

    @ViewBuilder
    private func card(_ c: TodayCard) -> some View {
        switch c {
        case .autopilot: AutopilotTodayCard()
        case .meds: MedsTodayCard()
        case .planRitual: PlanRitualPrompt()
        case .checkIn: CheckInCard()
        case .energy: energyPicker
        case .oneThing: justOneThing
        case .aiPlan: planCard
        case .upNext: if !upNextEvents.isEmpty { upNext }
        case .needsYou: attentionCard
        case .pinned: PinnedTasksCard()
        case .mail: FoundInMailTodayCard()
        case .trip: TripTodayCard()
        case .dayReview: if DayPhase.now == .evening { NavigationLink { LazyView(DayReviewView()) } label: { dayReviewTeaser }.buttonStyle(.plain) }
        case .countdown: countdownCard
        case .promises: promisesCard
        case .followUps: followUpsCard
        case .keepInTouch: keepInTouchCard
        case .weeklyReview:
            if WeeklyReview.isDue {
                NavigationLink { LazyView(WeeklyReviewView()) } label: {
                    GlassCard(tint: .purple) {
                        Label("Your weekly review is ready · 10 min", systemImage: "chart.bar.doc.horizontal")
                            .font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                    }
                }
                .buttonStyle(.plain)
            }
        case .avoided: DreadTodayCard()
        case .forecast: FocusForecastCard()
        case .body: BodyTodayCard()
        case .intention: IntentionCard()
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 8) {
            HorizonHeader(title: Date.now.formatted(.dateTime.weekday(.wide).month().day()), detail: "\(greetingText) · \(HorizonSky.daylightLeft())")
            HStack(alignment: .center) {
                if Custom.todayWeather { WeatherRow() }
                Spacer(minLength: 8)
                TodayProgressRing()                                 // "3 of 7 done" today
            }
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
            if let tide = tideForEnergy {
                Text("Suggested from your Tide (\(tide)%). Tap to change.").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
            } else if let h = sleepHours {
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
                        Button { withAnimation(DS.spring) { _ = TaskActions.setDone(t, true) } } label: {
                            Label("Done", systemImage: "checkmark").font(DS.Font.headline)
                                .padding(.horizontal, DS.Space.m).padding(.vertical, DS.Space.s)
                                .background(DS.Palette.calm.opacity(0.18), in: Capsule()).foregroundStyle(DS.Palette.calm)
                        }
                        .buttonStyle(.plain)
                        NavigationLink { LazyView(FocusView(preselected: t)) } label: {
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
                    RoundedRectangle(cornerRadius: 2).fill(e.calendar.map { Color(cgColor: $0.cgColor) } ?? DS.Palette.meeting).frame(width: 4, height: 34)
                    VStack(alignment: .leading) {
                        Text(e.title ?? "Event").font(DS.Font.headline)
                        Text("\(e.startDate.formatted(date: .omitted, time: .shortened)) · \(e.calendar?.source?.title ?? "")")
                            .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        if e.attendees?.isEmpty == false {
                            NavigationLink { LazyView(MeetingPrepView(event: e)) } label: {
                                Label("Prep", systemImage: "doc.text.magnifyingglass").font(DS.Font.caption)
                            }
                        }
                        // Meeting autopilot: one-tap Join and Record when it's about to start.
                        TimelineView(.everyMinute) { tl in
                            let soon = e.startDate.timeIntervalSince(tl.date) < 15 * 60 && e.endDate > tl.date
                            if soon && MeetingAutopilot.isMeeting(e) {
                                HStack(spacing: DS.Space.s) {
                                    if let link = MeetingLink.find(e) {
                                        Button {
                                            MeetingAutopilot.startActivity(for: e)
                                            UIApplication.shared.open(link)
                                            Haptics.tap()
                                        } label: {
                                            Label("Join \(MeetingLink.service(link) ?? "")", systemImage: "video.fill")
                                                .font(DS.Font.caption.weight(.semibold))
                                                .padding(.horizontal, 10).padding(.vertical, 5)
                                                .background(DS.Palette.meeting, in: Capsule()).foregroundStyle(.white)
                                        }
                                    }
                                    Button { AppRouter.shared.showRecorder = true } label: {
                                        Label("Record", systemImage: "mic.fill")
                                            .font(DS.Font.caption.weight(.semibold))
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(DS.Palette.meeting.opacity(0.15), in: Capsule()).foregroundStyle(DS.Palette.meeting)
                                    }
                                    .accessibilityLabel("Record AI meeting notes")
                                }
                                .buttonStyle(.borderless)
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
                        TimelineView(.everyMinute) { _ in Text(e.startDate <= Date() ? "Now" : Self.untilLabel(e.startDate)) }
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
                        // A block that's one of your tasks can be checked off here; it's the same task as in
                        // Tasks, so ticking it in either place shows in both.
                        let task = openTask(for: b.title)
                        let finished = task == nil && doneToday(b.title)
                        HStack {
                            Text(b.start).font(DS.Font.caption.monospacedDigit()).frame(minWidth: 48, alignment: .leading)
                            Text(b.title).font(DS.Font.body).strikethrough(finished)
                                .foregroundStyle(finished ? DS.Palette.inkSoft : DS.Palette.ink)
                            Spacer()
                            if let task {
                                Button { withAnimation(DS.spring) { _ = TaskActions.setDone(task, true) } } label: {
                                    Image(systemName: "circle").font(.title3).foregroundStyle(DS.Palette.inkSoft)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Mark \(task.title) done")
                            } else if finished {
                                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(DS.Palette.calm)
                                    .accessibilityLabel("Done")
                            } else {
                                Image(systemName: icon(for: b.kind)).foregroundStyle(DS.Palette.inkSoft)
                            }
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
                NavigationLink { LazyView(PromisesView()) } label: {
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
                NavigationLink { LazyView(CountdownsView()) } label: {
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
                            NavigationLink("Body double") { FocusRoomView(task: t) }
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
        ZStack(alignment: .leading) {
            Text(" ").font(DS.Font.caption).hidden()             // the line's room is kept, so the forecast arriving never pushes the page down
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
