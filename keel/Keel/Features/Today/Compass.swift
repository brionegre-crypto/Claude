import SwiftUI
import SwiftData

/// Today → ⊞: Keel's "Compass". Instead of a list of feature names, it starts from you:
/// how your brain is right now, and what you want to do. Tools are grouped by intent
/// ("Get going", "Calm down", "Stay on top"…), and each tile shows something live
/// (money due, people waiting, your focus window) so the menu itself is useful at a glance.
struct HubView: View {
    @Environment(\.modelContext) private var ctx
    @AppStorage(Prefs.calm) private var calm = false
    @AppStorage("hub.state") private var stateRaw = ""
    @State private var search = ""
    @Namespace private var zoom          // tiles grow into the screen they open
    @State private var stats: [String: String] = [:]
    @State private var recent: [String] = UserDefaults.standard.stringArray(forKey: "hub.recent") ?? []

    private var state: BrainState? { BrainState(rawValue: stateRaw) }
    private var groups: [HubGroup] { HubCatalog.groups }
    private var allTools: [HubTool] { groups.flatMap(\.tools) }
    private func tool(_ id: String) -> HubTool? { allTools.first { $0.id == id } }
    private func color(of id: String) -> Color { groups.first { g in g.tools.contains { $0.id == id } }?.color ?? DS.Palette.accent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                if search.isEmpty {
                    header
                    forRightNow
                    if !recent.isEmpty { recentRow }
                    ForEach(groups) { g in groupView(g) }
                    footer
                } else {
                    searchResults
                }
            }
            .padding(.bottom, DS.Space.xl)
        }
        .background(alignment: .top) { CompassBackdrop(tint: state?.color ?? DS.Palette.accent).frame(height: 360).ignoresSafeArea() }
        .navigationTitle("Compass")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Find a tool, or say what you need")
        .task { await loadStats() }
    }

    // MARK: How's your brain?

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.map { $0.headline } ?? "What do you need?").font(DS.Font.hero)
                    .contentTransition(.opacity)
                Text("How's your brain right now?").font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
            }
            .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BrainState.allCases) { s in
                        let on = state == s
                        Button {
                            withAnimation(.spring(duration: 0.45, bounce: 0.3)) { stateRaw = on ? "" : s.rawValue }
                            Haptics.tap()
                        } label: {
                            HStack(spacing: 6) {
                                Text(s.emoji).font(.title3)
                                Text(s.label).font(DS.Font.body.weight(on ? .semibold : .regular))
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background {
                                if on { Capsule().fill(s.color.gradient) } else { Capsule().fill(.ultraThinMaterial) }
                            }
                            .foregroundStyle(on ? .white : DS.Palette.ink)
                            .overlay(Capsule().strokeBorder(.white.opacity(on ? 0.3 : 0.15)))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityHint("Shows tools for feeling \(s.label.lowercased())")
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, DS.Space.m)
    }

    /// Three "prescriptions": tools that fit how you feel (or the time of day), each with the reason.
    private var forRightNow: some View {
        let picks = (state?.picks ?? BrainState.timeOfDayPicks).compactMap { p in tool(p.id).map { ($0, p.why) } }
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            Text(state == nil ? "Good for right now" : "For feeling \(state!.label.lowercased())")
                .font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft).textCase(.uppercase)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.m) {
                    ForEach(picks, id: \.0.id) { pick in
                        let t = pick.0
                        NavigationLink { t.dest().navigationTransition(.zoom(sourceID: "p" + t.id, in: zoom)) } label: {
                            PrescriptionCard(tool: t, why: pick.1, stat: stats[t.id], color: state?.color ?? color(of: t.id))
                        }
                        .buttonStyle(PressStyle())
                        .matchedTransitionSource(id: "p" + t.id, in: zoom)
                        .simultaneousGesture(TapGesture().onEnded { remember(t.id) })
                    }
                }
                .padding(.horizontal)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
        .id(stateRaw)
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private var recentRow: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("Lately").font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft).textCase(.uppercase)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recent.compactMap(tool)) { t in
                        NavigationLink { t.dest() } label: {
                            Label(t.title, systemImage: t.icon).font(DS.Font.caption.weight(.medium))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(color(of: t.id).opacity(0.12), in: Capsule())
                                .foregroundStyle(color(of: t.id))
                        }
                        .buttonStyle(PressStyle())
                        .simultaneousGesture(TapGesture().onEnded { remember(t.id) })
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: Intent groups (bento)

    private func groupView(_ g: HubGroup) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: g.icon).foregroundStyle(g.color.gradient).font(.title3.weight(.semibold))
                VStack(alignment: .leading, spacing: 0) {
                    Text(g.title).font(DS.Font.title)
                    Text(g.subtitle).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
            }
            .padding(.horizontal)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if let hero = g.tools.first {
                NavigationLink { hero.dest().navigationTransition(.zoom(sourceID: "g" + hero.id, in: zoom)) } label: { HeroTile(tool: hero, stat: stats[hero.id], color: g.color) }
                    .buttonStyle(PressStyle())
                    .matchedTransitionSource(id: "g" + hero.id, in: zoom)
                    .simultaneousGesture(TapGesture().onEnded { remember(hero.id) })
                    .padding(.horizontal)
            }
            FlexGrid(columns: 2, spacing: 10) {
                ForEach(g.tools.dropFirst()) { t in
                    NavigationLink { t.dest().navigationTransition(.zoom(sourceID: "g" + t.id, in: zoom)) } label: { ToolTile(tool: t, stat: stats[t.id], color: g.color) }
                        .buttonStyle(PressStyle())
                        .matchedTransitionSource(id: "g" + t.id, in: zoom)
                        .simultaneousGesture(TapGesture().onEnded { remember(t.id) })
                }
            }
            .padding(.horizontal)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Toggle(isOn: $calm) { Label("Calm mode", systemImage: "leaf") }
                    .toggleStyle(.button).buttonStyle(.bordered).tint(DS.Palette.calm)
                NavigationLink { CustomizeTodayView() } label: { Label("Customize Today", systemImage: "slider.horizontal.3") }
                    .buttonStyle(.bordered)
            }
            HStack(spacing: 10) {
                NavigationLink { ImportView() } label: { Label("Move to Keel", systemImage: "square.and.arrow.down") }.buttonStyle(.bordered)
                NavigationLink { FeatureGuideView() } label: { Label("How Keel works", systemImage: "questionmark.circle") }.buttonStyle(.bordered)
            }
        }
        .font(DS.Font.caption)
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Space.m)
    }

    // MARK: Search ("say what you need")

    private var searchResults: some View {
        let q = search.lowercased()
        let words = q.split(separator: " ").map(String.init)
        let hits = allTools.filter { t in
            let hay = (t.title + " " + t.keywords).lowercased()
            return hay.contains(q) || words.contains { $0.count > 2 && hay.contains($0) }
        }
        return VStack(alignment: .leading, spacing: 10) {
            if hits.isEmpty {
                ContentUnavailableView.search(text: search)
            }
            ForEach(hits) { t in
                NavigationLink { t.dest().navigationTransition(.zoom(sourceID: "s" + t.id, in: zoom)) } label: { ToolTile(tool: t, stat: stats[t.id], color: color(of: t.id), wide: true) }
                    .buttonStyle(PressStyle())
                    .matchedTransitionSource(id: "s" + t.id, in: zoom)
                    .simultaneousGesture(TapGesture().onEnded { remember(t.id) })
            }
        }
        .padding()
    }

    // MARK: Data

    private func remember(_ id: String) {
        var r = recent.filter { $0 != id }
        r.insert(id, at: 0)
        recent = Array(r.prefix(6))
        UserDefaults.standard.set(recent, forKey: "hub.recent")
    }

    /// Live lines for the tiles, worked out once when the Compass opens.
    private func loadStats() async {
        // Let the screen finish sliding in first; the live numbers then fade in without hitching the animation.
        try? await Task.sleep(for: .milliseconds(stats.isEmpty ? 380 : 0))
        guard !Task.isCancelled else { return }
        var s: [String: String] = [:]
        let cal = Calendar.current
        let subs = ((try? ctx.fetch(FetchDescriptor<Subscription>())) ?? []).filter { !$0.isHidden }
        let week = Date().addingTimeInterval(7 * 86_400)
        let dueSoon = subs.filter { ($0.nextDate ?? .distantFuture) <= week && ($0.nextDate ?? .distantPast) >= cal.startOfDay(for: Date()) && $0.kind != "trial" }
        let trials = subs.filter { $0.kind == "trial" && ($0.nextDate ?? .distantPast) > Date() }
        if !trials.isEmpty { s["bills"] = "\(trials.count) trial\(trials.count == 1 ? "" : "s") ending" }
        else if !dueSoon.isEmpty { s["bills"] = String(format: "%@%.0f due this week", dueSoon.first?.currency ?? "$", dueSoon.reduce(0) { $0 + $1.amount }) }
        else if !subs.isEmpty { s["bills"] = String(format: "%@%.0f a month", subs.first?.currency ?? "$", subs.filter { $0.kind == "subscription" }.reduce(0) { $0 + $1.monthlyCost }) }

        let promises = ((try? ctx.fetch(FetchDescriptor<Commitment>())) ?? []).filter { $0.status == .open }.count
        if promises > 0 { s["promises"] = "\(promises) open" }
        let people = ((try? ctx.fetch(FetchDescriptor<Person>())) ?? []).filter(\.isDue).count
        if people > 0 { s["people"] = "\(people) to reach out to" }
        let deliveries = ((try? ctx.fetch(FetchDescriptor<Delivery>())) ?? []).filter { !$0.isArchived && $0.status != "delivered" }.count
        if deliveries > 0 { s["deliveries"] = "\(deliveries) on the way" }

        let meds = ((try? ctx.fetch(FetchDescriptor<Medication>())) ?? []).filter(\.isActive)
        if !meds.isEmpty {
            let total = meds.reduce(0) { $0 + $1.times.count }
            let taken = ((try? ctx.fetch(FetchDescriptor<MedDose>())) ?? []).filter { cal.isDateInToday($0.day) }.count
            s["meds"] = "\(min(taken, total)) of \(total) today"
        }

        let tasks = (try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []
        let mail = ((try? ctx.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { !$0.isArchived }))) ?? [])
        let sessions = (try? ctx.fetch(FetchDescriptor<FocusSession>(sortBy: [SortDescriptor(\.startedAt)]))) ?? []
        let accounts = (try? ctx.fetch(FetchDescriptor<MailAccount>())) ?? []
        let dread = Dread.items(tasks: tasks, mail: mail, sessions: sessions, accounts: accounts).count
        if dread > 0 { s["dread"] = "\(dread) you might be avoiding" }
        let quick = QuickRepliesView.candidates(mail, accounts: accounts, scores: (try? ctx.fetch(FetchDescriptor<SenderScore>())) ?? []).count
        if quick > 0 { s["quickReplies"] = "\(min(quick, 5)) ready to clear" }
        let loose = tasks.filter { !$0.isDone && $0.listName == "Inbox" && $0.dueDate == nil }.count
        if loose > 0 { s["sort"] = "\(loose) loose task\(loose == 1 ? "" : "s")" }

        if meds.contains(where: { FocusForecast.timing(for: $0).profile != .none }) || sessions.count >= 8 {
            let sleep = ((try? ctx.fetch(FetchDescriptor<CheckIn>())) ?? []).first { cal.isDateInToday($0.day) }?.sleepHours
            let f = FocusForecast.build(meds: meds, doses: (try? ctx.fetch(FetchDescriptor<MedDose>())) ?? [], sleepHours: sleep, sessions: sessions)
            if let w = f.peaks.first(where: { $0.end > Date() }) { s["forecast"] = "Best: \(w.label)" }
        }
        let log = DailyLog.summary(for: Date(), ctx: ctx)
        if !log.isEmpty { s["dayLog"] = log }
        let saves = SavePoints.all.filter { Date().timeIntervalSince($0.createdAt) < 86_400 }.count
        if saves > 0 { s["savePoints"] = "\(saves) to pick up" }
        if WeeklyReview.isDue { s["weekly"] = "Ready for you" }
        let todayFocus = sessions.filter { cal.isDateInToday($0.startedAt) && $0.endedAt != nil }
            .reduce(0) { $0 + Int((($1.endedAt ?? $1.startedAt).timeIntervalSince($1.startedAt)) / 60) }
        if todayFocus > 0 { s["focusRoom"] = "\(todayFocus) min focused today" }
        if let c = ((try? ctx.fetch(FetchDescriptor<Countdown>(sortBy: [SortDescriptor(\.date)]))) ?? []).first(where: { $0.daysLeft >= 0 }) {
            s["countdowns"] = "\(c.emoji) \(c.title) in \(c.daysLeft)d"
        }
        let routines = RoutineStore.all.count
        if routines > 0 { s["routines"] = "\(routines) ready to run" }
        withAnimation(DS.spring) { stats = s }
    }
}

// MARK: - Brain states

enum BrainState: String, CaseIterable, Identifiable {
    case scattered, stuck, overwhelmed, ready, low
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var emoji: String { switch self { case .scattered: "🌀"; case .stuck: "🧱"; case .overwhelmed: "🌊"; case .ready: "⚡️"; case .low: "🪫" } }
    var color: Color {
        switch self {
        case .scattered: .purple; case .stuck: .orange; case .overwhelmed: .teal; case .ready: DS.Palette.accent; case .low: .indigo
        }
    }
    var headline: String {
        switch self {
        case .scattered: "Let's find one thing."
        case .stuck: "Let's get unstuck."
        case .overwhelmed: "Let's slow it down."
        case .ready: "Let's use it."
        case .low: "Let's go gently."
        }
    }

    struct Pick { let id: String; let why: String }

    var picks: [Pick] {
        switch self {
        case .scattered: [Pick(id: "savePoints", why: "Pick up the thread you dropped"),
                          Pick(id: "plan", why: "Turn the noise into one short list"),
                          Pick(id: "focusRoom", why: "Just 5 minutes on one thing")]
        case .stuck: [Pick(id: "dread", why: "Find out what's blocking you, and the fix"),
                      Pick(id: "focusRoom", why: "Someone working alongside you"),
                      Pick(id: "dopamine", why: "A small boost to get moving")]
        case .overwhelmed: [Pick(id: "sos", why: "One minute of breathing, then one tiny step"),
                            Pick(id: "breathe", why: "Slow your body down first"),
                            Pick(id: "sort", why: "Get it out of your head")]
        case .ready: [Pick(id: "forecast", why: "Spend your best hours on your hardest work"),
                      Pick(id: "quickReplies", why: "Clear five emails while you're sharp"),
                      Pick(id: "weekPlan", why: "Set up the rest of the week")]
        case .low: [Pick(id: "dopamine", why: "Something easy that feels good"),
                    Pick(id: "routines", why: "Let a routine do the thinking"),
                    Pick(id: "dayLog", why: "See what you already did today")]
        }
    }

    /// No state picked: suggestions for the time of day.
    static var timeOfDayPicks: [Pick] {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 11 {
            return [Pick(id: "plan", why: "Two minutes to shape your day"),
                    Pick(id: "forecast", why: "When you'll focus best today"),
                    Pick(id: "routines", why: "Get out the door on time")]
        } else if h < 17 {
            return [Pick(id: "focusRoom", why: "Do the next thing with company"),
                    Pick(id: "quickReplies", why: "Five quick emails, then done"),
                    Pick(id: "savePoints", why: "Back to where you left off")]
        } else {
            return [Pick(id: "dayLog", why: "Everything you did today"),
                    Pick(id: "journal", why: "One minute, then rest"),
                    Pick(id: "breathe", why: "Wind down before bed")]
        }
    }
}

// MARK: - Catalog

struct HubTool: Identifiable {
    let id: String
    let title: String
    let icon: String
    let keywords: String
    let dest: () -> AnyView
}

struct HubGroup: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let tools: [HubTool]
}

@MainActor
enum HubCatalog {
    private static func t<V: View>(_ id: String, _ title: String, _ icon: String, _ keywords: String, @ViewBuilder _ dest: @escaping () -> V) -> HubTool {
        HubTool(id: id, title: title, icon: icon, keywords: keywords, dest: { AnyView(dest()) })
    }

    static let groups: [HubGroup] = [
        HubGroup(id: "go", title: "Get going", subtitle: "Start, and keep going", icon: "bolt.fill", color: DS.Palette.accent, tools: [
            t("focusRoom", "Focus room", "person.2.wave.2.fill", "body double start focus work timer companion") { FocusRoomView() },
            t("forecast", "Focus forecast", "waveform.path.ecg", "meds medication best time energy peak") { FocusForecastView() },
            t("plan", "Plan my day", "list.bullet.clipboard", "today plan morning priorities") { PlanRitualView() },
            t("routines", "Routines", "list.number", "morning evening steps timer late") { RoutinesView() },
            t("quickReplies", "Quick replies", "bolt.horizontal.circle.fill", "email inbox reply clear") { QuickRepliesView() },
            t("sort", "Sort loose tasks", "tray.and.arrow.down.fill", "inbox process capture brain dump") { ProcessInboxView() },
        ]),
        HubGroup(id: "calm", title: "Calm down", subtitle: "When it's all a bit much", icon: "wind", color: .teal, tools: [
            t("sos", "I'm overwhelmed", "lifepreserver.fill", "sos panic anxious stressed too much help") { OverwhelmedView() },
            t("breathe", "Breathe", "wind", "breathing calm relax anxiety box") { BreatheView() },
            t("dread", "Dread radar", "tortoise.fill", "avoiding procrastinating stuck scared") { DreadRadarView() },
            t("dopamine", "Dopamine menu", "dice.fill", "boost bored reward motivation") { DopamineMenuView() },
        ]),
        HubGroup(id: "top", title: "Stay on top", subtitle: "Money, promises and things in motion", icon: "checkmark.shield.fill", color: .orange, tools: [
            t("bills", "Bills & money", "creditcard.fill", "subscriptions trial renewal payment cost") { SubscriptionsView() },
            t("meds", "Medications", "pills.fill", "meds pills dose refill") { MedsView() },
            t("promises", "Promises", "hand.raised.fill", "commitments owe said i would") { PromisesView() },
            t("savePoints", "Save points", "bookmark.fill", "resume interrupted where was i") { SavePointsView() },
            t("deliveries", "Deliveries", "shippingbox.fill", "packages tracking orders") { DeliveriesView() },
            t("trips", "Trips", "airplane", "travel flight hotel") { TripsView() },
            t("readLater", "Read later", "books.vertical.fill", "articles links saved") { ReadLaterView() },
        ]),
        HubGroup(id: "food", title: "Eat well", subtitle: "Scan it, check it against your plan, log it", icon: "fork.knife", color: .green, tools: [
            t("scanFood", "Scan food", "barcode.viewfinder", "barcode scan grocery diet allowed can i eat label ingredients") { FoodScanView() },
            t("food", "Food today", "fork.knife.circle.fill", "nutrition protein fiber sugar meals log calories health brain food fish") { NutritionView() },
            t("describeMeal", "Log a meal", "text.bubble.fill", "ate lunch dinner breakfast describe meal") { DescribeMealView() },
            t("foodLibrary", "Food library", "books.vertical.fill", "scanned products saved history") { FoodLibraryView() },
            t("dietGuide", "Diet guide", "book.closed.fill", "approved avoid swap alternative brands adhd diet") { DietGuideView() },
        ]),
        HubGroup(id: "back", title: "Look back", subtitle: "See how you're really doing", icon: "clock.arrow.circlepath", color: .pink, tools: [
            t("dayLog", "Daily log", "list.bullet.rectangle.fill", "today what did i do breathe log diary") { DayLogView() },
            t("journal", "Mood journal", "face.smiling.inverse", "mood feelings patterns sleep journal") { JournalTimelineView() },
            t("weekly", "Weekly review", "chart.bar.doc.horizontal.fill", "recap week reflect") { WeeklyReviewView() },
            t("monthly", "Monthly review", "calendar.badge.checkmark", "month reflect") { MonthlyReviewView() },
            t("stats", "Statistics", "chart.xyaxis.line", "numbers trends") { StatsView() },
            t("focusHistory", "Focus history", "chart.bar.xaxis", "sessions time") { FocusHistoryView() },
            t("timeAudit", "Time audit", "chart.pie.fill", "where time goes hours") { TimeAuditView() },
            t("achievements", "Achievements", "trophy.fill", "wins momentum streak") { AchievementsView() },
        ]),
        HubGroup(id: "ahead", title: "Think ahead", subtitle: "Shape the weeks to come", icon: "binoculars.fill", color: .purple, tools: [
            t("weekPlan", "Plan the week", "calendar.day.timeline.left", "week schedule") { WeekPlannerView() },
            t("goals", "Goals", "target", "goal ambitions areas") { GoalsView() },
            t("projects", "Projects", "folder.fill", "project") { ProjectsView() },
            t("habits", "Habit stacks", "link", "habits routine stack") { HabitsView() },
            t("habitLibrary", "Habit library", "books.vertical", "ideas habits") { HabitLibraryView() },
            t("idealWeek", "Ideal week", "calendar.badge.clock", "design week blocks") { IdealWeekView() },
            t("vision", "Vision board", "photo.on.rectangle.angled", "dreams pictures") { VisionBoardView() },
            t("odyssey", "Odyssey plan", "point.3.filled.connected.trianglepath.dotted", "future life paths") { OdysseyView() },
            t("places", "Places", "mappin.and.ellipse", "location home leaving checklist") { PlacesView() },
        ]),
        HubGroup(id: "people", title: "Your people", subtitle: "Stay close without the mental load", icon: "person.2.fill", color: .green, tools: [
            t("people", "Keep in touch", "person.2.fill", "friends family contact call") { PeopleView() },
            t("countdowns", "Countdowns", "hourglass", "birthday dates days until") { CountdownsView() },
            t("shared", "Shared calendars", "person.3.fill", "family team calendar") { SharedCalendarsView() },
            t("clock", "World clock", "globe", "time zones") { WorldClockView() },
        ]),
        HubGroup(id: "ask", title: "Ask & capture", subtitle: "Let Keel do the remembering", icon: "sparkles", color: .indigo, tools: [
            t("autopilot", "Autopilot", "sparkles", "ai suggestions automatic") { AutopilotView() },
            t("ask", "Ask Keel", "bubble.left.and.text.bubble.right.fill", "question ai chat assistant") { AssistantView() },
            t("talk", "Talk to Keel", "waveform", "voice speak") { TalkView() },
            t("record", "Record a meeting", "waveform.badge.mic", "meeting notes transcript") { MeetingRecorderView() },
            t("screenshots", "Tasks from screenshots", "camera.viewfinder", "photo scan") { ScreenshotTasksView() },
            t("brainMap", "Brain map", "brain.head.profile.fill", "notes graph links connections map neurons") { BrainMapView() },
            t("memory", "What Keel knows", "brain", "memory facts about me") { MemoryView() },
            t("help", "How do I…", "questionmark.bubble.fill", "help how do i guide tutorial instructions learn support stuck confused") { HelpCenterView() },
        ]),
    ]
}

// MARK: - Tiles

/// Slight press-in with a spring, so tiles feel physical.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.22, bounce: 0.15), value: configuration.isPressed)
    }
}

private struct Glyph: View {
    let icon: String
    let color: Color
    var size: CGFloat = 36
    var body: some View {
        Image(systemName: icon).font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: .rect(cornerRadius: size * 0.32, style: .continuous))
    }
}

private struct PrescriptionCard: View {
    let tool: HubTool
    let why: String
    let stat: String?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Glyph(icon: tool.icon, color: .white.opacity(0.25), size: 40)
            Spacer(minLength: 0)
            Text(tool.title).font(DS.Font.headline).foregroundStyle(.white)
            Text(why).font(DS.Font.caption).foregroundStyle(.white.opacity(0.9)).lineLimit(2, reservesSpace: true)
            if let stat { Text(stat).font(.caption2.weight(.semibold)).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3)
                .background(.white.opacity(0.2), in: Capsule()).lineLimit(1) }
        }
        .padding(16)
        .frame(width: 210, alignment: .leading)
        .frame(minHeight: 180)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(color.gradient)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: tool.icon).font(.system(size: 90, weight: .bold)).foregroundStyle(.white.opacity(0.08))
                        .offset(x: 18, y: -10).rotationEffect(.degrees(-12))
                }
                .clipShape(.rect(cornerRadius: 26, style: .continuous))
        }
        .shadow(color: color.opacity(0.3), radius: 14, y: 8)
        .accessibilityElement(children: .combine)
    }
}

private struct HeroTile: View {
    let tool: HubTool
    let stat: String?
    let color: Color

    var body: some View {
        HStack(spacing: DS.Space.m) {
            Glyph(icon: tool.icon, color: color, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(tool.title).font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                Text(stat ?? "Open").font(DS.Font.caption).foregroundStyle(stat == nil ? DS.Palette.inkSoft : color).lineLimit(1)
            }
            Spacer()
            Image(systemName: "arrow.up.right").font(.caption.weight(.bold)).foregroundStyle(color)
                .padding(8).background(color.opacity(0.12), in: Circle())
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.thinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(color.opacity(0.25)))
        .accessibilityElement(children: .combine)
    }
}

private struct ToolTile: View {
    let tool: HubTool
    let stat: String?
    let color: Color
    var wide = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Glyph(icon: tool.icon, color: color, size: 32)
                Text(tool.title).font(DS.Font.body.weight(.semibold)).foregroundStyle(DS.Palette.ink)
                    .lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                if let stat {
                    Text(stat).font(.caption2.weight(.medium)).foregroundStyle(color).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: wide ? 0 : 104, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS.Palette.elevated))
        .overlay(alignment: .topTrailing) {
            if stat != nil { Circle().fill(color).frame(width: 7, height: 7).padding(12) }   // something live here
        }
        .accessibilityElement(children: .combine)
    }
}

/// A slow, soft mesh of color behind the top of the Compass, tinted by how you feel.
private struct CompassBackdrop: View {
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        MeshGradient(width: 3, height: 3, points: [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], drift ? SIMD2<Float>(0.62, 0.42) : SIMD2<Float>(0.38, 0.58), [1, 0.5],
            [0, 1], [0.5, 1], [1, 1],
        ], colors: [
            tint.opacity(0.35), tint.opacity(0.18), .purple.opacity(0.2),
            .teal.opacity(0.15), tint.opacity(0.25), .pink.opacity(0.12),
            .clear, .clear, .clear,
        ])
        .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
        .animation(.easeInOut(duration: 0.6), value: tint)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) { drift = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
