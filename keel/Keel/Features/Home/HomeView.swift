import SwiftUI
import SwiftData
import EventKit

// MARK: - Home
//
// The first screen, redesigned per theme to match its mockup (Chart Table, Helm, Living Tide, Logbook, Signal Flags,
// Lighthouse, Instrument Panel). Under the theme's own hero sit the modules you choose: add, reorder or remove them
// (Home → Edit). Everything the classic Today had is still one tap away ("Full Today"), so nothing is lost.

/// What Home knows about your day, worked out once per update.
struct HomeDay {
    struct Entry: Identifiable { let id: String; let time: Date?; let title: String; let task: TaskItem?; let place: String? }

    let now: Date
    let entries: [Entry]          // timed things today, in order (events + timed tasks), then untimed tasks
    let waypoints: [Entry]        // today's tasks only: timed in time order, then untimed by priority (Chart Table's passage)
    let events: [Entry]           // today's remaining events, kept quiet on the chart
    let doneTasks: [TaskItem]     // ticked off today, most recent first
    let next: Entry?
    let nextTask: TaskItem?
    let tide: Int?, swell: Int, anchor: Int?
    let asleepMinutes: Double
    let target: ClosedRange<Int>
    let doneToday: Int

    @MainActor init(tasks: [TaskItem], doneToday: Int, done: [TaskItem] = [], now: Date = Date()) {
        self.now = now
        self.doneToday = doneToday
        self.doneTasks = done
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let ekEvents = CalendarService.shared.todaysEvents().filter { !$0.isAllDay && $0.endDate > now && CalendarRoles.shows($0) }
        let routineLists = RoutineLists.linkedNames          // a list used as a routine shows as its routine, not item by item
        let todays = tasks.filter { !$0.isDone && !$0.isSomeday && ($0.dueDate ?? .distantFuture) < end && !TaskMeta.isDeferred($0, now: now)
            && !routineLists.contains($0.listName) }
        var timed: [Entry] = ekEvents.map { Entry(id: "e:" + ($0.eventIdentifier ?? UUID().uuidString), time: $0.startDate, title: $0.title ?? "Event", task: nil, place: $0.location) }
        timed += todays.filter(\.hasDueTime).map { Entry(id: "t:" + $0.id.uuidString, time: $0.dueDate, title: $0.title, task: $0, place: nil) }
        timed.sort { ($0.time ?? .distantFuture) < ($1.time ?? .distantFuture) }
        let untimed = todays.filter { !$0.hasDueTime }.sorted { $0.priority.rawValue > $1.priority.rawValue }
            .map { Entry(id: "t:" + $0.id.uuidString, time: nil, title: $0.title, task: $0, place: nil) }
        entries = timed + untimed
        waypoints = timed.filter { $0.task != nil } + untimed
        events = timed.filter { $0.task == nil }
        let energy = EnergyLevel(rawValue: UserDefaults.standard.integer(forKey: "energy")) ?? .medium
        nextTask = ADHDCoach.nextThing(tasks: tasks.filter { !$0.isDone }, energy: energy)
        next = timed.first { ($0.time ?? now) > now.addingTimeInterval(-15 * 60) } ?? nextTask.map { Entry(id: "t:" + $0.id.uuidString, time: $0.dueDate, title: $0.title, task: $0, place: nil) }
        let b = BodyEngine.shared.today
        tide = b?.tide; swell = b?.swell ?? 0; anchor = b?.anchor; asleepMinutes = b?.asleep ?? 0
        target = BodyMath.swellTarget(b?.tide)
    }

    var dayOfYear: Int { Calendar.current.ordinality(of: .day, in: .year, for: now) ?? 0 }
    var partOfDay: String {
        let h = Calendar.current.component(.hour, from: now)
        return h < 12 ? "Morning" : h < 17 ? "Afternoon" : "Evening"
    }
    var tideWord: String { guard let t = tide else { return "unknown" }; return t >= 67 ? "high" : t >= 34 ? "steady" : "low" }

    /// One line, written like a log entry: "Wind fair, Tide high. Two passages before noon; Sabbath at half past seven."
    var logLine: String {
        let cal = Calendar.current
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now
        let morning = entries.filter { ($0.time ?? .distantFuture) < noon && ($0.time ?? .distantPast) > now }.count
        let words = ["No", "One", "Two", "Three", "Four", "Five", "Six"]
        var s = tide == nil ? "Fair weather." : "Tide \(tideWord)."
        if now < noon { s += " \(words[min(morning, 6)]) passage\(morning == 1 ? "" : "s") before noon" } else {
            let left = entries.filter { ($0.time ?? .distantPast) > now }.count
            s += " \(words[min(left, 6)]) still ahead"
        }
        if let last = entries.last(where: { $0.time != nil }), let t = last.time, t > now {
            s += "; \(last.title) at \(t.formatted(date: .omitted, time: .shortened))."
        } else { s += "." }
        return s
    }

    func time(_ d: Date?) -> String { d?.formatted(date: .omitted, time: .shortened) ?? "anytime" }
    func navTime(_ d: Date?) -> String { d.map { String(format: "%02d%02d", Calendar.current.component(.hour, from: $0), Calendar.current.component(.minute, from: $0)) } ?? "····" }
}

struct HomeView: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var open: [TaskItem]
    @Query(TodayView.recentlyDoneQuery) private var recentlyDone: [TaskItem]
    @State private var engine = BodyEngine.shared
    @AppStorage(HomeModules.key) private var modulesRaw = ""
    @State private var editing = false
    @State private var fullToday = false
    @State private var showSOS = false
    @State private var showBrainDump = false
    /// Worked out when tasks change or the minute turns, not on every redraw (redraws were re-reading the
    /// calendar, the coach and Body each time, which made Home stutter).
    @State private var day: HomeDay?
    @State private var minute = Date()

    private var dayKey: String {
        "\(open.count)|\(open.reduce(0.0) { max($0, $1.updatedAt.timeIntervalSince1970) })|\(recentlyDone.count)|\(Int(minute.timeIntervalSince1970 / 60))|\(engine.today?.tide ?? -1)"
    }

    private func rebuild() {
        let cal = Calendar.current
        let doneToday = recentlyDone.filter { $0.completedAt.map { cal.isDateInToday($0) } ?? false }.count
        let done = recentlyDone.filter { $0.completedAt.map { cal.isDateInToday($0) } ?? false }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        day = HomeDay(tasks: open, doneToday: doneToday, done: Array(done.prefix(5)))
    }

    var body: some View {
        let day = self.day ?? HomeDay(tasks: open, doneToday: 0)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero(day)
                    ForEach(HomeModules.current(modulesRaw)) { m in m.view }
                    HStack(spacing: 10) {
                        Button { editing = true } label: { Label("Add to Home", systemImage: "plus.circle.fill") }
                            .buttonStyle(.bordered).tint(DS.Palette.accent)
                        Button { fullToday = true } label: { Label("Full Today", systemImage: "list.bullet.below.rectangle") }
                            .buttonStyle(.bordered).tint(DS.Palette.inkSoft)
                    }
                    .font(DS.Font.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 90)
                }
                .padding(.horizontal, DS.Space.m)
            }
            .scrollIndicators(.hidden)
            .premiumBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { homeToolbar }
            .refreshable { await SyncEngine.shared.syncAll() }
            .task(id: dayKey) { rebuild() }
            .task {
                while !Task.isCancelled {          // the passage moves with the clock, once a minute
                    try? await Task.sleep(for: .seconds(60))
                    minute = Date()
                }
            }
            .sheet(isPresented: $showBrainDump) { BrainDumpView() }
            .fullScreenCover(isPresented: $showSOS) { OverwhelmedView() }
            .sheet(isPresented: $editing) { HomeModulesEditor() }
            .sheet(isPresented: $fullToday) { TodayView().overlay(alignment: .bottom) { UndoToast() } }   // every classic Today card, as before (Undo shows over the sheet too)
            .task { await engine.refresh() }
        }
    }

    /// The same top bar the classic Today has: overwhelmed, brain dump, search, edit Home, settings.
    @ToolbarContentBuilder private var homeToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showSOS = true } label: { Image(systemName: "lifepreserver") }.accessibilityLabel("I'm overwhelmed")
        }
        ToolbarItem(placement: .topBarLeading) {
            Button { showBrainDump = true } label: { Image(systemName: "brain.head.profile") }.accessibilityLabel("Brain dump")
        }
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink { LazyView(SearchView()) } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Search everything")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { editing = true } label: { Label("Edit Home", systemImage: "square.grid.2x2") }
                Button { fullToday = true } label: { Label("Full Today", systemImage: "list.bullet.below.rectangle") }
            } label: { Image(systemName: "ellipsis.circle") }
            .accessibilityLabel("Home options")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { AppRouter.shared.showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
        }
    }

    @ViewBuilder private func hero(_ d: HomeDay) -> some View {
        switch PaletteCache.look {
        case .helm: HelmHome(day: d, startFocus: startFocus)
        case .tide: TideHome(day: d)
        case .logbook: LogbookHome(day: d)
        case .flags: FlagsHome(day: d)
        case .lighthouse: LighthouseHome(day: d, startFocus: startFocus)
        case .panel: PanelHome(day: d)
        default: ChartHome(day: d)
        }
    }

    private func startFocus(_ t: TaskItem?) {
        if let t { NowTimer.start(t, ctx: ctx); try? ctx.save() }
        AppRouter.shared.showFocus = true
        Haptics.tap()
    }
}

// MARK: - Shared pieces

/// A row that opens the task (or just shows the event), with the theme deciding the look of the leading mark.
private struct HomeEntryLink<Content: View>: View {
    let entry: HomeDay.Entry
    @ViewBuilder var label: () -> Content
    var body: some View {
        if let t = entry.task {
            NavigationLink { LazyView(TaskDetailView(task: t)) } label: { label() }.buttonStyle(.plain)
        } else {
            label()
        }
    }
}


// MARK: 1 · Chart Table

private struct ChartHome: View {
    let day: HomeDay
    @Environment(\.modelContext) private var ctx
    @State private var showEvents = false
    @State private var showAll = false
    @State private var planning = false

    var body: some View {
        let points = day.waypoints
        let shown = showAll ? points : Array(points.prefix(7))
        VStack(alignment: .leading, spacing: 6) {
            Text(day.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased() + " · " + day.time(day.now) + " · DAY \(day.dayOfYear)")
                .font(DS.Font.mono).tracking(0.8).foregroundStyle(DS.Palette.inkSoft)
            Text("Today's passage").font(.system(.largeTitle, design: .serif, weight: .semibold)).foregroundStyle(DS.Palette.ink)
            WaypointChart(day: day).frame(height: 128).padding(.vertical, 4)
            if !day.events.isEmpty { eventsLine }
            // Drag your waypoints onto free hours (the day planner); they land on your calendar.
            Button { planning = true; Haptics.tap() } label: {
                Label("Plan the day: drag tasks onto open water", systemImage: "calendar.day.timeline.left")
                    .font(.footnote.weight(.medium)).foregroundStyle(Nautical.chartRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            HStack {
                ThemedSectionHeader(title: "Waypoints · \(points.count) left · \(day.doneToday) done")
                Spacer()
            }
            .padding(.top, 10)
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, e in
                    if let t = e.task { WaypointRow(number: i + 1, isNext: i == 0, task: t, time: e.time) }
                }
                if points.count > 7 {
                    Button { withAnimation(DS.spring) { showAll.toggle() } } label: {
                        Text(showAll ? "Show fewer" : "\(points.count - 7) more waypoints").font(DS.Font.mono).foregroundStyle(DS.Palette.inkSoft)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(day.doneTasks.prefix(3)) { t in
                    HStack(spacing: 12) {
                        Button { _ = TaskActions.setDone(t, false); try? ctx.save(); Haptics.tap() } label: {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(DS.Palette.canvas)
                                .frame(width: 24, height: 24).background(DS.Palette.ink.opacity(0.55), in: Circle())
                        }
                        .buttonStyle(.plain).accessibilityLabel("Mark \(t.title) not done")
                        Text(t.title).strikethrough().foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                }
                if points.isEmpty && day.doneTasks.isEmpty {
                    Text("Open water: no tasks charted for today.").font(.system(.body, design: .serif).italic()).foregroundStyle(DS.Palette.inkSoft).padding(.vertical, 12)
                }
            }
        }
        .padding(.top, 2)
        .sheet(isPresented: $showEvents) { HomeEventsSheet(events: day.events) }
        .sheet(isPresented: $planning) { DayPlannerView() }
    }

    /// Meetings stay out of the way: one quiet line, tap for the list.
    private var eventsLine: some View {
        Button { showEvents = true } label: {
            HStack(spacing: 6) {
                // "anchor" isn't an SF Symbol: it drew nothing and was looked up again in the asset catalog on every layout.
                Image(systemName: "calendar").font(.caption)
                Text("\(day.events.count) \(day.events.count == 1 ? "event" : "events") · next")
                if let n = day.events.first {
                    Text("\(n.title) \(day.time(n.time))").fontWeight(.semibold).foregroundStyle(DS.Palette.ink).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2)
            }
            .font(.footnote).foregroundStyle(DS.Palette.inkSoft)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(DS.Palette.elevated.opacity(0.5), in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DS.Palette.ink.opacity(0.15), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }
}

/// One task on the passage: its waypoint number (red when it's next), tap the number to tick it off,
/// tap the row to open it, hold for Start focus / Later / Done.
private struct WaypointRow: View {
    let number: Int
    let isNext: Bool
    let task: TaskItem
    let time: Date?
    @Environment(\.modelContext) private var ctx
    @State private var ticked = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: tick) {
                ZStack {
                    Circle().fill(isNext ? Nautical.chartRed : DS.Palette.ink)
                    if ticked { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                    else { Text("\(number)").font(.system(size: 11, weight: .semibold, design: .monospaced)) }
                }
                .foregroundStyle(DS.Palette.canvas)
                .frame(width: 24, height: 24)
                .scaleEffect(ticked ? 1.15 : 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(task.title) done")
            NavigationLink { LazyView(TaskDetailView(task: task)) } label: {
                HStack {
                    Text(task.title).font(.body).foregroundStyle(DS.Palette.ink).lineLimit(1)
                        .strikethrough(ticked)
                    Spacer()
                    Text(time.map { Nautical.clock($0) } ?? "~\(ADHDCoach.minutes(task))m")
                        .font(DS.Font.mono).foregroundStyle(DS.Palette.inkSoft)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { DashLine().stroke(DS.Palette.inkSoft.opacity(0.45), style: StrokeStyle(lineWidth: 0.7, dash: [3, 3])).frame(height: 1) }
        .contextMenu {
            Button { NowTimer.start(task, ctx: ctx); try? ctx.save(); AppRouter.shared.showFocus = true } label: { Label("Start focus", systemImage: "play.fill") }
            Button(action: tick) { Label("Done", systemImage: "checkmark.circle") }
            Button {
                TaskActions.reschedule(task, to: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()); try? ctx.save()
            } label: { Label("Later (tomorrow)", systemImage: "arrow.uturn.right") }
        }
    }

    private func tick() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { ticked = true }
        Haptics.tap()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))      // let the fix mark land before the row leaves
            _ = TaskActions.setDone(task, true); try? ctx.save()
        }
    }
}

private struct HomeEventsSheet: View {
    let events: [HomeDay.Entry]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(events) { e in
                HStack {
                    Text(e.time?.formatted(date: .omitted, time: .shortened) ?? "").font(DS.Font.mono).foregroundStyle(DS.Palette.inkSoft).frame(width: 70, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.title)
                        if let p = e.place, !p.isEmpty { Text(p).font(.caption).foregroundStyle(DS.Palette.inkSoft) }
                    }
                }
            }
            .navigationTitle("Today's events")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct DashLine: Shape {
    func path(in r: CGRect) -> Path { Path { $0.move(to: CGPoint(x: 0, y: r.midY)); $0.addLine(to: CGPoint(x: r.maxX, y: r.midY)) } }
}

/// Today as a plotted course with only your tasks on it: numbered waypoints matching the list (red = next),
/// a red line for how far through the day you are. No labels, so it never gets cluttered.
private struct WaypointChart: View {
    let day: HomeDay
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let cal = Calendar.current
            let start = cal.date(bySettingHour: 6, minute: 0, second: 0, of: day.now) ?? day.now
            let end = cal.date(bySettingHour: 23, minute: 0, second: 0, of: day.now) ?? day.now
            let span = max(1, end.timeIntervalSince(start))
            let course = WaypointChart.course(w: w, h: h)
            let sailed = min(0.999, max(0.001, day.now.timeIntervalSince(start) / span))
            let points = Array(day.waypoints.prefix(7))
            // Timed tasks sit at their time; untimed ones are spaced evenly through what's left of the day.
            let untimedCount = max(1, points.filter { $0.time == nil }.count)
            // Numbers always run in order along the course: each stop sits at its time (or evenly spaced if untimed),
            // but never before the one ahead of it in the list.
            let fractions: [Double] = {
                var k = 0, last = sailed
                let room = max(0.05, 0.98 - sailed), step = min(0.08, room / Double(max(1, points.count)))
                return points.map { e in
                    var f: Double
                    if let t = e.time { f = t.timeIntervalSince(start) / span } else {
                        k += 1; f = sailed + room * Double(k) / Double(untimedCount + 1)
                    }
                    f = min(0.99, max(f, last + step))
                    last = f
                    return f
                }
            }()
            // One measurement of the curve for every marker (each trimmedPath measured the whole curve again,
            // nine times per layout, and the chart lays out on every frame while the tab bar shrinks on scroll).
            let ruler = CourseRuler(w: w, h: h)
            ZStack(alignment: .topLeading) {
                course.stroke(DS.Palette.ink.opacity(0.45), style: StrokeStyle(lineWidth: 1.4, dash: [2, 4]))
                course.trimmedPath(from: 0, to: sailed).stroke(Nautical.chartRed, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                let fix = ruler.point(at: sailed)
                Circle().fill(Nautical.chartRed).frame(width: 12, height: 12).position(fix)
                Circle().stroke(Nautical.chartRed.opacity(0.35), lineWidth: 1).frame(width: 26, height: 26).position(fix)
                ForEach(Array(Array(points.enumerated()).reversed()), id: \.element.id) { i, _ in
                    Text("\(i + 1)").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(DS.Palette.canvas)
                        .frame(width: 20, height: 20)
                        .background(i == 0 ? Nautical.chartRed : DS.Palette.ink, in: Circle())
                        .position(ruler.point(at: fractions[i]))
                }
            }
        }
        .drawingGroup()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's course: \(day.waypoints.count) tasks charted")
    }
}

extension WaypointChart {
    /// The day's course: two curves across the chart.
    static func course(w: CGFloat, h: CGFloat) -> Path {
        let c = CourseRuler.controls(w: w, h: h)
        return Path { p in
            p.move(to: c[0])
            p.addCurve(to: c[3], control1: c[1], control2: c[2])
            p.addCurve(to: c[6], control1: c[4], control2: c[5])
        }
    }
}

/// Points along the course by fraction of its length (what `trimmedPath(from: 0, to: f).currentPoint` gives),
/// measured once per chart size and kept, so layout passes don't re-measure the curve.
struct CourseRuler {
    private let pts: [CGPoint]
    private let cum: [CGFloat]

    @MainActor private static var cache: (size: CGSize, ruler: CourseRuler)?

    @MainActor init(w: CGFloat, h: CGFloat) {
        if let c = Self.cache, c.size == CGSize(width: w, height: h) { self = c.ruler; return }
        let c = Self.controls(w: w, h: h)
        var pts: [CGPoint] = []
        for seg in 0..<2 {
            let p0 = c[seg * 3], p1 = c[seg * 3 + 1], p2 = c[seg * 3 + 2], p3 = c[seg * 3 + 3]
            for i in (seg == 0 ? 0 : 1)...160 {
                let t = CGFloat(i) / 160, u = 1 - t
                let a = u * u * u, b = 3 * u * u * t, d = 3 * u * t * t, e = t * t * t
                pts.append(CGPoint(x: a * p0.x + b * p1.x + d * p2.x + e * p3.x, y: a * p0.y + b * p1.y + d * p2.y + e * p3.y))
            }
        }
        var cum: [CGFloat] = [0]
        for i in 1..<pts.count { cum.append(cum[i - 1] + hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)) }
        self.pts = pts; self.cum = cum
        Self.cache = (CGSize(width: w, height: h), self)
    }

    static func controls(w: CGFloat, h: CGFloat) -> [CGPoint] {
        [CGPoint(x: 10, y: h * 0.85),
         CGPoint(x: w * 0.2, y: h * 0.15), CGPoint(x: w * 0.38, y: h * 0.95), CGPoint(x: w * 0.55, y: h * 0.5),
         CGPoint(x: w * 0.72, y: h * 0.1), CGPoint(x: w * 0.85, y: h * 0.3), CGPoint(x: w - 14, y: h * 0.18)]
    }

    func point(at fraction: Double) -> CGPoint {
        guard let total = cum.last, total > 0 else { return pts.first ?? .zero }
        let target = CGFloat(min(1, max(0, fraction))) * total
        var lo = 0, hi = cum.count - 1
        while lo < hi { let mid = (lo + hi) / 2; if cum[mid] < target { lo = mid + 1 } else { hi = mid } }
        guard lo > 0 else { return pts[0] }
        let seg = cum[lo] - cum[lo - 1], k = seg > 0 ? (target - cum[lo - 1]) / seg : 0
        return CGPoint(x: pts[lo - 1].x + (pts[lo].x - pts[lo - 1].x) * k, y: pts[lo - 1].y + (pts[lo].y - pts[lo - 1].y) * k)
    }
}

// MARK: 2 · The Helm

private struct HelmHome: View {
    let day: HomeDay
    let startFocus: (TaskItem?) -> Void
    @Environment(ShutdownManager.self) private var shutdown
    private let brass = Color(red: 0.85, green: 0.71, blue: 0.42)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(day.now.formatted(.dateTime.weekday(.wide)).uppercased() + " · HEADING").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(brass)
            Text(day.next?.title ?? "Open sea: choose a heading").font(.system(.title, design: .serif, weight: .semibold)).foregroundStyle(DS.Palette.ink).lineLimit(2)
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                compass(now: ctx.date)
            }
            .frame(height: 290)
            .onTapGesture { startFocus(day.nextTask) }
            ForEach(day.entries.prefix(4)) { e in
                HomeEntryLink(entry: e) {
                    HStack(spacing: 12) {
                        Circle().strokeBorder(brass, lineWidth: 1.5).frame(width: 18, height: 18)
                        Text(e.title).foregroundStyle(DS.Palette.ink).lineLimit(1)
                        Spacer()
                        Text(e.time.map { day.time($0) } ?? "").font(.caption.weight(.semibold)).foregroundStyle(brass)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(brass.opacity(0.28)))
                }
            }
        }
        .padding(.top, 10)
    }

    private func compass(now: Date) -> some View {
        let focusing = shutdown.endsAt.map { $0 > now } ?? false
        let remaining = focusing ? (shutdown.endsAt ?? now).timeIntervalSince(now) : (day.next?.time.map { max(0, $0.timeIntervalSince(now)) } ?? 0)
        let fraction = focusing ? remaining / Double(max(1, (shutdown.active?.plannedMinutes ?? 25) * 60)) : min(1, remaining / 3600)
        let hour = Double(Calendar.current.component(.hour, from: now)) + Double(Calendar.current.component(.minute, from: now)) / 60
        return ZStack {
            Circle().fill(RadialGradient(colors: [Color(red: 0.14, green: 0.29, blue: 0.45), Color(red: 0.04, green: 0.09, blue: 0.15)], center: .init(x: 0.5, y: 0.4), startRadius: 0, endRadius: 150))
            Circle().strokeBorder(brass, lineWidth: 2)
            Circle().inset(by: 20).stroke(brass.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [2, 7]))
            ForEach(0..<4) { i in
                Capsule().fill(brass.opacity(0.7)).frame(width: 2, height: 14).offset(y: -128).rotationEffect(.degrees(Double(i) * 90))
            }
            Circle().inset(by: 20).trim(from: 0, to: fraction).stroke(brass, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
            // The needle points to the hour, like a heading through the day.
            HelmNeedle().fill(brass).frame(width: 18, height: 190).rotationEffect(.degrees(hour / 24 * 360))
            Circle().fill(Color(red: 0.96, green: 0.92, blue: 0.84)).frame(width: 14, height: 14)
            VStack(spacing: 2) {
                Text(Duration.seconds(remaining).formatted(remaining >= 3600 ? .time(pattern: .hourMinute) : .time(pattern: .minuteSecond)))
                    .font(.system(size: 34, weight: .regular, design: .serif)).monospacedDigit().foregroundStyle(Color(red: 0.96, green: 0.92, blue: 0.84))
                Text(focusing ? "FOCUSING" : day.next?.time.map { "NEXT \(day.time($0))".uppercased() } ?? "TAP TO FOCUS")
                    .font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(brass)
            }
            .offset(y: 62)
        }
        .frame(width: 280, height: 280)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(focusing ? "Focusing" : "Next: \(day.next?.title ?? "nothing scheduled")")
        .accessibilityHint("Starts a focus session")
    }
}

private struct HelmNeedle: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); p.addLine(to: CGPoint(x: r.midX, y: r.midY + 8)); p.addLine(to: CGPoint(x: r.minX, y: r.midY))
            p.closeSubpath()
        }
    }
}

// MARK: 3 · Living Tide

private struct TideHome: View {
    let day: HomeDay
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: HorizonSky.colors(at: day.now), startPoint: .top, endPoint: .bottom)
                // The sea: its level is your Tide.
                TideWaves(level: Double(day.tide ?? 50) / 100).fill(.white.opacity(0.25))
                TideWaves(level: Double(day.tide ?? 50) / 100 - 0.08, phase: 1).fill(.white.opacity(0.4))
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(day.partOfDay.uppercased()) · TIDE \(day.tide.map { "\($0)%" } ?? "–")").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.white.opacity(0.9))
                    Text(day.tide.map { $0 >= 67 ? "A high tide.\nGo do the hard thing." : $0 >= 34 ? "A steady tide.\nKeep a good pace." : "A low tide.\nGo gently today." } ?? "Good \(day.partOfDay.lowercased()).")
                        .font(.system(.title, design: .serif, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    HStack(alignment: .lastTextBaseline) {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(day.tide.map { "\($0)" } ?? "–").font(.system(size: 54, weight: .regular, design: .serif)).foregroundStyle(.white)
                            Text("TIDE").font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
                .padding(20)
            }
            .frame(height: 300)
            .clipShape(.rect(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, -DS.Space.m + 6)
            if let n = day.next { card(n, lead: "Next") }
            ForEach(day.entries.filter { $0.id != day.next?.id }.prefix(3)) { card($0, lead: nil) }
            HStack {
                Text("Swell \(day.swell) of \(day.target.lowerBound)–\(day.target.upperBound)")
                Spacer()
                Circle().fill(BodyStyle.swell).frame(width: 10, height: 10)
            }
            .padding(16).background { PremiumSurface(radius: 18) }
        }
    }

    private func card(_ e: HomeDay.Entry, lead: String?) -> some View {
        HomeEntryLink(entry: e) {
            HStack {
                (lead.map { Text("\($0) · ").bold() } ?? Text("")) + Text(e.title)
                Spacer()
                Text(day.time(e.time)).foregroundStyle(lead == nil ? DS.Palette.inkSoft : DS.Palette.accent)
            }
            .foregroundStyle(DS.Palette.ink)
            .padding(16).background { PremiumSurface(radius: 18) }
        }
    }
}

private struct TideWaves: Shape {
    var level: Double
    var phase: Double = 0
    func path(in r: CGRect) -> Path {
        let y = r.height * (1 - max(0.15, min(0.85, level)) * 0.55)
        return Path { p in
            p.move(to: CGPoint(x: 0, y: y))
            p.addCurve(to: CGPoint(x: r.width * 0.5, y: y + (phase == 0 ? 6 : -6)), control1: CGPoint(x: r.width * 0.15, y: y - 20), control2: CGPoint(x: r.width * 0.35, y: y + 22))
            p.addCurve(to: CGPoint(x: r.width, y: y), control1: CGPoint(x: r.width * 0.65, y: y - 22), control2: CGPoint(x: r.width * 0.85, y: y + 20))
            p.addLine(to: CGPoint(x: r.width, y: r.height)); p.addLine(to: CGPoint(x: 0, y: r.height)); p.closeSubpath()
        }
    }
}

// MARK: 4 · Logbook

private struct LogbookHome: View {
    let day: HomeDay
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SHIP'S LOG · NO. \(day.dayOfYear)").font(DS.Font.mono).tracking(1.2).foregroundStyle(DS.Palette.inkSoft)
            Text(day.now.formatted(.dateTime.weekday(.wide)) + ",\nthe " + ordinal(Calendar.current.component(.day, from: day.now)) + " of " + day.now.formatted(.dateTime.month(.wide)))
                .font(.system(.largeTitle, design: .serif, weight: .regular)).foregroundStyle(DS.Palette.ink)
            Rectangle().fill(DS.Palette.ink).frame(height: 1).padding(.vertical, 4)
            Text("“\(day.logLine)”").font(.system(.body, design: .serif).italic()).foregroundStyle(DS.Palette.inkSoft).padding(.bottom, 6)
            ForEach(day.entries.prefix(10)) { e in
                HomeEntryLink(entry: e) {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(day.navTime(e.time)).font(DS.Font.mono).foregroundStyle(DS.Palette.inkSoft).frame(width: 40, alignment: .leading)
                        Text(e.title).font(e.task?.priority == .high ? .body.weight(.semibold) : .body).foregroundStyle(DS.Palette.ink)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Rectangle().fill(DS.Palette.inkSoft.opacity(0.18)).frame(height: 1) }
                }
            }
        }
        .padding(.top, 14)
    }

    private func ordinal(_ n: Int) -> String {
        let suffix = (11...13).contains(n % 100) ? "th" : [1: "st", 2: "nd", 3: "rd"][n % 10] ?? "th"
        return "\(n)\(suffix)"
    }
}

// MARK: 5 · Signal Flags

private struct FlagsHome: View {
    let day: HomeDay
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Today").font(.system(size: 40, weight: .heavy)).tracking(-0.5).foregroundStyle(DS.Palette.ink).padding(.top, 10)
            HStack(spacing: 8) {
                block("TIDE", day.tide.map { "\($0)" } ?? "–", Color(red: 0.04, green: 0.24, blue: 0.57), .white)
                block("SWELL", "\(day.swell)", Color(red: 1, green: 0.8, blue: 0), .black)
                block("ANCHOR", day.anchor.map { "\($0)" } ?? "–", Color(red: 0.84, green: 0.16, blue: 0.16), .white)
            }
            VStack(spacing: 0) {
                ForEach(day.entries.prefix(8)) { e in
                    HomeEntryLink(entry: e) {
                        HStack(spacing: 14) {
                            SignalFlag(kind: e.task?.priority ?? .none, isEvent: e.task == nil).frame(width: 26, height: 18)
                            Text(e.title).font(.body.weight(.medium)).foregroundStyle(DS.Palette.ink).lineLimit(1)
                            Spacer()
                            Text(day.time(e.time)).font(.subheadline).foregroundStyle(DS.Palette.inkSoft)
                        }
                        .padding(.vertical, 13)
                        .overlay(alignment: .bottom) { Rectangle().fill(DS.Palette.inkSoft.opacity(0.15)).frame(height: 1) }
                    }
                }
            }
        }
    }
    private func block(_ t: String, _ v: String, _ bg: Color, _ fg: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.caption2.weight(.bold)).tracking(1).opacity(0.8)
            Text(v).font(.system(size: 34, weight: .heavy)).monospacedDigit()
        }
        .foregroundStyle(fg)
        .padding(12).frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(bg, in: .rect(cornerRadius: 16, style: .continuous))
    }
}

/// Priority as a maritime signal flag: the pattern carries the meaning, so it reads without colour too.
struct SignalFlag: View {
    let kind: TaskPriority
    var isEvent = false
    private let blue = Color(red: 0.04, green: 0.24, blue: 0.57), red = Color(red: 0.84, green: 0.16, blue: 0.16), yellow = Color(red: 1, green: 0.8, blue: 0)
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                if isEvent {
                    HStack(spacing: 0) { yellow; blue }                      // "events": yellow over blue
                } else {
                    switch kind {
                    case .high: HStack(spacing: 0) { red; Color.white }       // half red, half white
                    case .medium:
                        HStack(spacing: 0) { ForEach(0..<4) { i in (i.isMultiple(of: 2) ? blue : Color.white).frame(width: w / 4) } }
                    case .low: yellow
                    case .none: VStack(spacing: 0) { blue.frame(height: h / 2); yellow }
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 2))
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.black.opacity(0.12)))
        }
        .accessibilityLabel(isEvent ? "Event" : "\(kind.label) priority")
    }
}

// MARK: 6 · Lighthouse

private struct LighthouseHome: View {
    let day: HomeDay
    let startFocus: (TaskItem?) -> Void
    private let amber = Color(red: 1, green: 0.77, blue: 0.33)
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(day.partOfDay.uppercased()) · \(day.time(day.now))").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(amber).padding(.top, 14)
            Text("One light on the water.").font(.system(.largeTitle, design: .serif, weight: .regular)).foregroundStyle(DS.Palette.ink)
            if let n = day.next {
                VStack(alignment: .leading, spacing: 6) {
                    Text("NOW").font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(amber)
                    Text(n.title).font(.title3.weight(.semibold)).foregroundStyle(DS.Palette.ink)
                    Text([n.time.map { day.time($0) }, n.place].compactMap { $0 }.joined(separator: " · ")).font(.subheadline).foregroundStyle(DS.Palette.inkSoft)
                    HStack(spacing: 10) {
                        Button { startFocus(n.task ?? day.nextTask) } label: { Text("Start").font(.subheadline.weight(.semibold)).padding(.horizontal, 18).padding(.vertical, 9).background(amber, in: Capsule()).foregroundStyle(.black) }
                        if let t = n.task {
                            Button { TaskActions.reschedule(t, to: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()) } label: {
                                Text("Later").font(.subheadline).padding(.horizontal, 18).padding(.vertical, 9).overlay(Capsule().strokeBorder(Color.white.opacity(0.25))).foregroundStyle(DS.Palette.ink)
                            }
                        }
                    }
                    .buttonStyle(.plain).padding(.top, 6)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [amber.opacity(0.18), amber.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(amber.opacity(0.35)))
            }
            Text("THEN").font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(DS.Palette.inkSoft)
            ForEach(day.entries.filter { $0.id != day.next?.id }.prefix(4)) { e in
                HomeEntryLink(entry: e) {
                    HStack { Text(e.title).lineLimit(1); Spacer(); Text(day.time(e.time)) }
                        .font(.subheadline).foregroundStyle(DS.Palette.inkSoft)
                        .padding(14).background(DS.Palette.elevated, in: .rect(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }
}

// MARK: 7 · Instrument Panel

private struct PanelHome: View {
    let day: HomeDay
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("BRIDGE").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(DS.Palette.inkSoft)
                Text(status).font(.system(.title, design: .serif, weight: .semibold)).foregroundStyle(DS.Palette.ink)
            }
            .padding(.top, 12)
            HStack(spacing: 16) {
                BridgeGauge(label: "TIDE", value: day.tide, color: BodyStyle.tide)
                BridgeGauge(label: "SWELL", value: day.swell, color: BodyStyle.swell)
            }
            .frame(maxWidth: .infinity)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                tile("ANCHOR", day.anchor.map { "\($0)" } ?? "–", day.asleepMinutes > 0 ? "\(Int(day.asleepMinutes) / 60)h \(Int(day.asleepMinutes) % 60)m asleep" : "no sleep yet")
                tile("DONE TODAY", "\(day.doneToday)", "\(day.entries.count) still charted")
            }
            if let n = day.next {
                HomeEntryLink(entry: n) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NEXT").font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(DS.Palette.inkSoft)
                        Text("\(n.title) · \(day.time(n.time))").font(.body.weight(.semibold)).foregroundStyle(DS.Palette.ink)
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).background { PremiumSurface(radius: 18) }
                }
            }
        }
    }

    private var status: String {
        guard let t = day.tide else { return "Instruments warming up" }
        return t >= 67 ? "All instruments green" : t >= 34 ? "Steady as she goes" : "Recovery heading"
    }

    private func tile(_ t: String, _ v: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(DS.Palette.inkSoft)
            Text(v).font(.system(.title2, design: .serif, weight: .regular)).foregroundStyle(DS.Palette.ink)
            Text(s).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).background { PremiumSurface(radius: 18) }
    }
}

/// A bridge instrument: a 270° dial with ticks and a red needle.
struct BridgeGauge: View {
    let label: String
    let value: Int?
    let color: Color
    var body: some View {
        let f = Double(value ?? 0) / 100
        ZStack {
            Circle().fill(RadialGradient(colors: [.white, Color(white: 0.9)], center: .init(x: 0.5, y: 0.35), startRadius: 0, endRadius: 80))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 6)
            Circle().inset(by: 14).trim(from: 0.125, to: 0.875).stroke(Color.black.opacity(0.08), style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(90))
            Circle().inset(by: 14).trim(from: 0.125, to: 0.125 + 0.75 * f).stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(90))
            ForEach(0..<9) { i in
                Capsule().fill(Color.black.opacity(0.35)).frame(width: 1.5, height: 7).offset(y: -62).rotationEffect(.degrees(-135 + Double(i) * 33.75))
            }
            Capsule().fill(Color(red: 0.75, green: 0.22, blue: 0.17)).frame(width: 3, height: 44).offset(y: -22).rotationEffect(.degrees(-135 + 270 * f))
            Circle().fill(Color(red: 0.08, green: 0.13, blue: 0.2)).frame(width: 10, height: 10)
            VStack(spacing: 0) {
                Text(value.map { "\($0)" } ?? "–").font(.system(size: 20, design: .serif)).foregroundStyle(Color(red: 0.08, green: 0.13, blue: 0.2))
                Text(label).font(.system(size: 8, weight: .semibold)).tracking(1.5).foregroundStyle(Color(red: 0.42, green: 0.48, blue: 0.56))
            }
            .offset(y: 36)
        }
        .frame(width: 148, height: 148)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label.capitalized) \(value.map { "\($0)" } ?? "no data")")
    }
}

// MARK: - Modules you add to Home

enum HomeModule: String, CaseIterable, Identifiable {
    case body, nextThing, needsYou, voyage, meds, checkIn, intention, forecast, pinnedTasks, pinnedEmails, autopilot,
         clashes, routine, tomorrow, trips, deliveries, avoided, affirmation, favoritePages, progress, didYouKnow, planRitual
    var id: String { rawValue }
    var title: String {
        switch self {
        case .body: "Body (Tide, Swell, Anchor)"; case .nextThing: "Next thing & focus"; case .needsYou: "Email that needs you"
        case .voyage: "Your day as a voyage"; case .meds: "Medication due"; case .checkIn: "Mood check-in"; case .intention: "Today's intention"
        case .forecast: "Focus forecast"; case .pinnedTasks: "Pinned tasks"; case .pinnedEmails: "Pinned emails"; case .autopilot: "Autopilot suggestions"
        case .clashes: "Calendar clashes"; case .routine: "Upcoming routine"; case .tomorrow: "Tomorrow preview"; case .trips: "Next trip"
        case .deliveries: "Packages & bills"; case .avoided: "Dread radar"; case .affirmation: "Daily affirmation"; case .favoritePages: "Favourite pages"
        case .progress: "Done today"; case .didYouKnow: "Did you know?"; case .planRitual: "Plan your day"
        }
    }
    var icon: String {
        switch self {
        case .body: "water.waves"; case .nextThing: "scope"; case .needsYou: "envelope.badge"; case .voyage: "sailboat"; case .meds: "pills.fill"
        case .checkIn: "face.smiling"; case .intention: "sparkle"; case .forecast: "waveform.path.ecg"; case .pinnedTasks: "pin.fill"; case .pinnedEmails: "pin.circle"
        case .autopilot: "sparkles"; case .clashes: "exclamationmark.2"; case .routine: "list.bullet.rectangle"; case .tomorrow: "moon.haze"
        case .trips: "airplane"; case .deliveries: "shippingbox.fill"; case .avoided: "tortoise.fill"; case .affirmation: "quote.opening"
        case .favoritePages: "star.fill"; case .progress: "checkmark.circle"; case .didYouKnow: "lightbulb"; case .planRitual: "list.bullet.clipboard"
        }
    }

    @MainActor @ViewBuilder var view: some View {
        switch self {
        case .body: BodyTodayCard()
        case .nextThing: NextThingModule()
        case .needsYou: NeedsYouCard()
        case .voyage: VoyageView()
        case .meds: MedsTodayCard()
        case .checkIn: CheckInCard()
        case .intention: IntentionCard()
        case .forecast: FocusForecastCard()
        case .pinnedTasks: PinnedTasksCard()
        case .pinnedEmails: PinnedEmailsCard()
        case .autopilot: AutopilotTodayCard()
        case .clashes: ClashesCard()
        case .routine: UpcomingRoutineCard()
        case .tomorrow: TomorrowPreviewCard()
        case .trips: TripTodayCard()
        case .deliveries: FoundInMailTodayCard()
        case .avoided: DreadTodayCard()
        case .affirmation: DailyAffirmationCard()
        case .favoritePages: FavoritePagesCard()
        case .progress: TodayProgressRing()
        case .didYouKnow: DidYouKnowCard()
        case .planRitual: PlanRitualPrompt()
        }
    }
}

enum HomeModules {
    static let key = "home.modules"
    /// Out of the box: your mail, body and a nudge, below the theme's own layout. Change it any time.
    static let defaults: [HomeModule] = [.needsYou, .meds, .body, .didYouKnow]
    static func current(_ raw: String) -> [HomeModule] {
        raw.isEmpty ? defaults : raw.split(separator: ",").compactMap { HomeModule(rawValue: String($0)) }
    }
}

/// The next thing, with one tap to focus on it (for themes whose layout doesn't already put it centre stage).
private struct NextThingModule: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var open: [TaskItem]
    var body: some View {
        let energy = EnergyLevel(rawValue: UserDefaults.standard.integer(forKey: "energy")) ?? .medium
        if let t = ADHDCoach.nextThing(tasks: open, energy: energy) {
            HStack(spacing: 12) {
                Image(systemName: "scope").font(.title2).foregroundStyle(DS.Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXT").font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(DS.Palette.inkSoft)
                    Text(t.title).font(.headline).foregroundStyle(DS.Palette.ink).lineLimit(2)
                }
                Spacer()
                Button("Focus") { NowTimer.start(t, ctx: ctx); try? ctx.save(); AppRouter.shared.showFocus = true }
                    .buttonStyle(.borderedProminent).tint(DS.Palette.accent)
            }
            .padding(DS.Space.m).background { PremiumSurface() }
        }
    }
}

/// Home → Add to Home: pick, order and remove what sits under the theme's layout.
struct HomeModulesEditor: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(HomeModules.key) private var raw = ""
    @State private var chosen: [HomeModule] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(chosen) { m in Label(m.title, systemImage: m.icon) }
                        .onMove { chosen.move(fromOffsets: $0, toOffset: $1); save() }
                        .onDelete { chosen.remove(atOffsets: $0); save() }
                } header: { Text("On your Home") } footer: { Text("Drag to reorder; swipe to remove. Your theme's own layout always sits at the top.") }
                Section("Add") {
                    ForEach(HomeModule.allCases.filter { !chosen.contains($0) }) { m in
                        Button { chosen.append(m); save(); Haptics.tap() } label: {
                            HStack { Label(m.title, systemImage: m.icon).foregroundStyle(DS.Palette.ink); Spacer(); Image(systemName: "plus.circle.fill").foregroundStyle(DS.Palette.accent) }
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Your Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { chosen = HomeModules.current(raw) }
        }
    }

    private func save() { raw = chosen.map(\.rawValue).joined(separator: ",") }
}
