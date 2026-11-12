import SwiftUI

/// The cards Today can show, in an order you choose (or Keel's automatic, time-of-day order).
enum TodayCard: String, CaseIterable, Identifiable {
    case autopilot, meds, planRitual, checkIn, energy, oneThing, aiPlan, upNext, needsYou, pinned, mail, trip,
         dayReview, countdown, promises, followUps, keepInTouch, weeklyReview, avoided, forecast
    var id: String { rawValue }

    var title: String {
        switch self {
        case .autopilot: "Autopilot suggestions"; case .meds: "Medication due"; case .planRitual: "Plan your day prompt"
        case .checkIn: "Mood check-in"; case .energy: "Energy level"; case .oneThing: "Just one thing"; case .aiPlan: "Today's plan"
        case .upNext: "Up next"; case .needsYou: "Needs you (email)"; case .pinned: "Pinned tasks"; case .mail: "Packages & bills"
        case .trip: "Next trip"; case .dayReview: "Day in review (evening)"; case .countdown: "Countdown"; case .promises: "Promises"
        case .followUps: "Awaiting reply"; case .keepInTouch: "Keep in touch"; case .weeklyReview: "Weekly review"; case .avoided: "Dread radar (avoided tasks & email)"
        case .forecast: "Focus forecast"
        }
    }
    var icon: String {
        switch self {
        case .autopilot: "sparkles"; case .meds: "pills.fill"; case .planRitual: "list.bullet.clipboard"; case .checkIn: "face.smiling"
        case .energy: "battery.75"; case .oneThing: "1.circle.fill"; case .aiPlan: "wand.and.stars"; case .upNext: "calendar"
        case .needsYou: "person.crop.circle.badge.exclamationmark"; case .pinned: "pin.fill"; case .mail: "shippingbox.fill"; case .trip: "airplane"
        case .dayReview: "moon.stars.fill"; case .countdown: "hourglass"; case .promises: "hand.raised.fill"; case .followUps: "bubble.left.and.exclamationmark.bubble.right"
        case .keepInTouch: "person.2.fill"; case .weeklyReview: "chart.bar.doc.horizontal"; case .avoided: "tortoise.fill"
        case .forecast: "waveform.path.ecg"
        }
    }

    /// Keel's automatic order: plan in the morning, do in the day, wind down at night.
    static func automatic(_ phase: DayPhase) -> [TodayCard] {
        switch phase {
        case .morning: [.autopilot, .meds, .planRitual, .checkIn, .energy, .forecast, .oneThing, .upNext, .needsYou, .aiPlan, .pinned, .mail, .trip, .countdown, .promises, .followUps, .keepInTouch, .weeklyReview, .avoided]
        case .day: [.autopilot, .meds, .energy, .forecast, .oneThing, .upNext, .needsYou, .pinned, .aiPlan, .mail, .trip, .checkIn, .countdown, .promises, .followUps, .keepInTouch, .weeklyReview, .avoided]
        case .evening: [.dayReview, .autopilot, .meds, .checkIn, .upNext, .needsYou, .oneThing, .pinned, .mail, .trip, .countdown, .promises, .followUps, .keepInTouch, .weeklyReview, .avoided]
        }
    }
    static let calm: [TodayCard] = [.autopilot, .meds, .oneThing, .upNext]

    static let orderKey = "today.order", hiddenKey = "today.hidden"

    /// Your saved order (new cards added later slot in at the end), minus hidden ones.
    static func current(phase: DayPhase) -> [TodayCard] {
        let hidden = Set((UserDefaults.standard.string(forKey: hiddenKey) ?? "").split(separator: ",").map(String.init))
        let saved = (UserDefaults.standard.string(forKey: orderKey) ?? "").split(separator: ",").compactMap { TodayCard(rawValue: String($0)) }
        let order = saved.isEmpty ? automatic(phase) : saved + allCases.filter { !saved.contains($0) && $0 != .dayReview }
        return order.filter { !hidden.contains($0.rawValue) }
    }
}

/// Today → ⊞ → Customize Today.
struct CustomizeTodayView: View {
    @AppStorage(TodayCard.orderKey) private var orderRaw = ""
    @AppStorage(TodayCard.hiddenKey) private var hiddenRaw = ""
    @State private var order: [TodayCard] = []

    private var hidden: Set<String> { Set(hiddenRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        List {
            Section {
                Toggle("Automatic order", isOn: Binding(get: { orderRaw.isEmpty }, set: { auto in
                    if auto { orderRaw = "" ; order = TodayCard.automatic(DayPhase.now) }
                    else { orderRaw = order.map(\.rawValue).joined(separator: ",") }
                }))
            } footer: { Text(orderRaw.isEmpty ? "Keel reorders Today through the day: planning in the morning, doing in the day, winding down at night. Turn this off to set your own order." : "Drag to reorder. Switch cards off to hide them; they're still reachable from ⊞.") }
            Section("Cards") {
                ForEach(order) { c in
                    Toggle(isOn: Binding(get: { !hidden.contains(c.rawValue) }, set: { on in
                        var h = hidden
                        if on { h.remove(c.rawValue) } else { h.insert(c.rawValue) }
                        hiddenRaw = h.sorted().joined(separator: ",")
                    })) { Label(c.title, systemImage: c.icon) }
                }
                .onMove { from, to in
                    order.move(fromOffsets: from, toOffset: to)
                    orderRaw = order.map(\.rawValue).joined(separator: ",")
                }
                .moveDisabled(orderRaw.isEmpty)
            }
            Section { Button("Reset to Default") { orderRaw = ""; hiddenRaw = ""; order = TodayCard.automatic(DayPhase.now) } }
        }
        .environment(\.editMode, .constant(orderRaw.isEmpty ? .inactive : .active))
        .navigationTitle("Customize Today")
        .onAppear {
            let saved = orderRaw.split(separator: ",").compactMap { TodayCard(rawValue: String($0)) }
            order = saved.isEmpty ? TodayCard.automatic(DayPhase.now) : saved + TodayCard.allCases.filter { !saved.contains($0) }
        }
    }
}

/// Everything Keel can do, grouped, instead of one very long menu.
struct HubView: View {
    @AppStorage(Prefs.calm) private var calm = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: $calm) { Label("Calm mode", systemImage: "leaf") }
                NavigationLink { CustomizeTodayView() } label: { Label("Customize Today", systemImage: "slider.horizontal.3") }
            }
            Section("AI") {
                link("Autopilot", "sparkles") { AutopilotView() }
                link("Ask Keel", "bubble.left.and.text.bubble.right") { AssistantView() }
                link("Talk to Keel", "waveform") { TalkView() }
                link("What Keel knows", "brain") { MemoryView() }
            }
            Section("Plan") {
                link("Plan my day", "list.bullet.clipboard") { PlanRitualView() }
                link("Plan the week", "calendar.day.timeline.left") { WeekPlannerView() }
                link("Goals", "target") { GoalsView() }
                link("Vision board", "photo.on.rectangle.angled") { VisionBoardView() }
                link("Projects", "folder") { ProjectsView() }
                link("Ideal week", "calendar.badge.clock") { IdealWeekView() }
                link("Odyssey plan", "point.3.filled.connected.trianglepath.dotted") { OdysseyView() }
                link("Sort loose tasks", "tray.and.arrow.down") { ProcessInboxView() }
                link("Routines", "list.number") { RoutinesView() }
                link("Places & leaving home", "mappin.and.ellipse") { PlacesView() }
            }
            Section("Review") {
                link("Weekly review", "chart.bar.doc.horizontal") { WeeklyReviewView() }
                link("Monthly review", "calendar.badge.checkmark") { MonthlyReviewView() }
                link("Statistics", "chart.xyaxis.line") { StatsView() }
                link("Focus history", "chart.bar.xaxis") { FocusHistoryView() }
                link("Time audit", "chart.pie") { TimeAuditView() }
                link("Achievements", "trophy") { AchievementsView() }
            }
            Section("Wellbeing") {
                link("Medications", "pills") { MedsView() }
                link("Habit stacks", "link") { HabitsView() }
                link("Habit library", "books.vertical") { HabitLibraryView() }
                link("Daily log", "list.bullet.rectangle") { DayLogView() }
                link("Breathe", "wind") { BreatheView() }
                link("Mood journal & patterns", "face.smiling") { JournalTimelineView() }
                link("Focus room", "person.2.wave.2") { FocusRoomView() }
                link("Focus forecast", "waveform.path.ecg") { FocusForecastView() }
                link("Dread radar", "tortoise") { DreadRadarView() }
                link("Dopamine menu", "fork.knife") { DopamineMenuView() }
            }
            Section("From your email") {
                link("Bills & money", "creditcard") { SubscriptionsView() }
                link("Clear 5 quick replies", "bolt.horizontal.circle") { QuickRepliesView() }
                link("Deliveries", "shippingbox") { DeliveriesView() }
                link("Trips", "airplane") { TripsView() }
                link("Promises", "hand.raised") { PromisesView() }
                link("Read later", "books.vertical") { ReadLaterView() }
            }
            Section("People & time") {
                link("Keep in touch", "person.2") { PeopleView() }
                link("Countdowns", "hourglass") { CountdownsView() }
                link("Shared calendars", "person.3") { SharedCalendarsView() }
                link("World clock", "globe") { WorldClockView() }
            }
            Section("Capture") {
                link("Record a meeting", "mic") { MeetingRecorderView() }
                link("Save points", "bookmark") { SavePointsView() }
                link("Tasks from screenshots", "camera.viewfinder") { ScreenshotTasksView() }
            }
            Section {
                link("Import from other apps", "square.and.arrow.down") { ImportView() }
                link("How Keel works", "questionmark.circle") { FeatureGuideView() }
            }
        }
        .navigationTitle("Everything")
    }

    private func link<D: View>(_ title: String, _ icon: String, @ViewBuilder _ dest: () -> D) -> some View {
        NavigationLink { dest() } label: { Label(title, systemImage: icon) }
    }
}
