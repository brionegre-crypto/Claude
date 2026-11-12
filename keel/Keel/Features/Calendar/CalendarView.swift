import SwiftUI
import SwiftData
import EventKit
import EventKitUI

/// TickTick-style calendar: Day / Week / Month with events from EVERY calendar on the phone
/// and Keel tasks side by side. Tap empty time to add an event, tap an event to see/edit/RSVP,
/// long-press and drag to reschedule.
enum CalendarMode: String, CaseIterable, Identifiable {
    case day = "Day", week = "Week", month = "Month"
    var id: String { rawValue }
}

struct EventRef: Identifiable { let id = UUID(); let event: EKEvent }
struct EventDraft: Identifiable { let id = UUID(); let event: EKEvent?; let start: Date? }

struct CalendarView: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var tasks: [TaskItem]
    @AppStorage("calendar.mode") private var modeRaw = CalendarMode.week.rawValue
    @AppStorage("calendar.hidden") private var hiddenRaw = ""
    @State private var anchor = Calendar.current.startOfDay(for: Date())
    @State private var events: [EKEvent] = []
    @State private var draft: EventDraft?
    @State private var viewing: EventRef?
    @State private var openTask: TaskItem?
    @State private var showCalendars = false
    @State private var newTaskDate: Date?
    @State private var message: String?
    @State private var taskGroup: TaskGroupRef?
    @State private var showQuick = false
    @State private var quickText = ""
    @AppStorage("calendar.showTasks") private var showTasks = true

    private let cal = Calendar.current
    private var mode: CalendarMode { CalendarMode(rawValue: modeRaw) ?? .week }
    private var hidden: Set<String> { Set(hiddenRaw.split(separator: ",").map(String.init)) }

    private var visibleDays: [Date] {
        switch mode {
        case .day: return [anchor]
        case .week:
            let start = cal.dateInterval(of: .weekOfYear, for: anchor)?.start ?? anchor
            return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        case .month:
            let first = cal.date(from: cal.dateComponents([.year, .month], from: anchor)) ?? anchor
            let start = cal.dateInterval(of: .weekOfYear, for: first)?.start ?? first
            return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        }
    }

    private var title: String {
        switch mode {
        case .day: anchor.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        case .week, .month: anchor.formatted(.dateTime.month(.wide).year())
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                switch mode {
                case .day, .week:
                    TimelineGrid(days: visibleDays, events: events, tasks: showTasks ? tasks : [],
                                 onTapSlot: { draft = EventDraft(event: nil, start: $0) },
                                 onTapEvent: { viewing = EventRef(event: $0) },
                                 onTapTask: { openTask = $0 },
                                 onTapTaskGroup: { taskGroup = TaskGroupRef(tasks: $0) },
                                 onTapDay: { anchor = $0; modeRaw = CalendarMode.day.rawValue },
                                 onMoveEvent: moveEvent, onMoveTask: moveTask)
                case .month:
                    ScrollView {
                        MonthGrid(days: visibleDays, month: anchor, selected: anchor, events: events, tasks: showTasks ? tasks : []) { day in
                            withAnimation(DS.spring) { anchor = day }
                            Haptics.tap()
                        }
                        .padding(.horizontal, DS.Space.s)
                        DayAgenda(day: anchor, events: events, tasks: tasks,
                                  onTapEvent: { viewing = EventRef(event: $0) },
                                  onTapTask: { openTask = $0 })
                            .padding()
                    }
                }
            }
            .background(DS.Palette.canvas)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Choose calendars…", systemImage: "calendar.badge.checkmark") { showCalendars = true }
                        Toggle(isOn: $showTasks) { Label("Show tasks on calendar", systemImage: "checklist") }
                        Divider()
                        ShareLink(item: Availability.text()) { Label("Share my availability", systemImage: "calendar.badge.clock") }
                        NavigationLink { WorldClockView() } label: { Label("World clock", systemImage: "globe") }
                        NavigationLink { SharedCalendarsView() } label: { Label("Shared calendars", systemImage: "person.3") }
                        NavigationLink { EventTemplatesView() } label: { Label("Event templates", systemImage: "square.on.square") }
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                    .accessibilityLabel("Calendar options")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Quick event…", systemImage: "text.bubble") { showQuick = true }
                        Button("New event", systemImage: "calendar.badge.plus") { draft = EventDraft(event: nil, start: defaultNewStart()) }
                        Menu("From template", systemImage: "square.on.square") {
                            ForEach(EventTemplate.all) { t in
                                Button("\(t.title) · \(t.minutes) min") {
                                    let start = defaultNewStart()
                                    draft = EventDraft(event: t.makeEvent(start: start), start: start)
                                }
                            }
                        }
                        Button("New task", systemImage: "checklist") { newTaskDate = defaultNewStart() }
                    } label: { Image(systemName: "plus") }
                }
            }
            .task { await CalendarService.shared.requestAccess(); load() }
            .onChange(of: anchor) { load() }
            .onChange(of: modeRaw) { load() }
            .onChange(of: hiddenRaw) { load() }
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in load() }
            .sheet(item: $draft) { d in
                EventEditor(event: d.event, start: d.start) { draft = nil; load() }.ignoresSafeArea()
            }
            .sheet(item: $viewing) { ref in
                EventDetail(event: ref.event) { viewing = nil; load() }.ignoresSafeArea()
            }
            .sheet(item: $openTask) { t in NavigationStack { TaskDetailView(task: t) } }
            .sheet(isPresented: $showCalendars) { CalendarPicker(hiddenRaw: $hiddenRaw) }
            .sheet(item: $taskGroup) { TaskGroupSheet(tasks: $0.tasks) }
            .alert("Quick event", isPresented: $showQuick) {
                TextField("Lunch with Sam Thu 1pm for 90 min", text: $quickText)
                Button("Add") {
                    if let p = try? QuickEvent.create(quickText) {
                        flash("Added “\(p.title)” · \(p.start.formatted(date: .abbreviated, time: p.allDay ? .omitted : .shortened))")
                        anchor = Calendar.current.startOfDay(for: p.start)
                        Haptics.success()
                    } else {
                        flash("Add a day or time, like “tomorrow 3pm”")
                    }
                    quickText = ""
                    load()
                }
                Button("Cancel", role: .cancel) { quickText = "" }
            } message: { Text("Type it like you'd say it.") }
            .sheet(item: Binding(get: { newTaskDate.map { DateBox(date: $0) } }, set: { newTaskDate = $0?.date })) { box in
                QuickTaskSheet(date: box.date)
            }
            .overlay(alignment: .bottom) {
                if let message {
                    Text(message).font(DS.Font.caption).padding(.horizontal, DS.Space.m).padding(.vertical, DS.Space.s)
                        .glassEffect(.regular, in: Capsule()).padding(.bottom, DS.Space.l)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: DS.Space.s) {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous")
            Button("Today") { withAnimation(DS.spring) { anchor = cal.startOfDay(for: Date()) } }.font(DS.Font.caption)
            Button { step(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next")
            Spacer()
            Picker("View", selection: $modeRaw) {
                ForEach(CalendarMode.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
            .pickerStyle(.segmented).frame(maxWidth: 220)
        }
        .padding(.horizontal).padding(.vertical, DS.Space.s)
    }

    private func step(_ dir: Int) {
        let component: Calendar.Component = switch mode { case .day: .day; case .week: .weekOfYear; case .month: .month }
        withAnimation(DS.spring) { anchor = cal.date(byAdding: component, value: dir, to: anchor) ?? anchor }
        Haptics.tap()
    }

    private func defaultNewStart() -> Date {
        let base = cal.isDateInToday(anchor) ? Date() : (cal.date(bySettingHour: 9, minute: 0, second: 0, of: anchor) ?? anchor)
        let minute = cal.component(.minute, from: base)
        return cal.date(byAdding: .minute, value: (30 - minute % 30) % 30, to: base) ?? base
    }

    private func load() {
        guard let first = visibleDays.first, let last = visibleDays.last,
              let end = cal.date(byAdding: .day, value: 1, to: last) else { return }
        let hiddenIds = hidden
        events = CalendarService.shared.events(from: first, to: end)
            .filter { !hiddenIds.contains($0.calendar.calendarIdentifier) }
    }

    private func moveEvent(_ e: EKEvent, to start: Date) {
        do {
            try CalendarService.shared.move(e, to: start)
            Haptics.success()
        } catch {
            flash("“\(e.calendar.title)” is read-only")
        }
        load()
    }

    private func moveTask(_ t: TaskItem, to start: Date) {
        t.dueDate = start
        t.updatedAt = Date()
        try? CalendarService.shared.push(t)
        Haptics.success()
    }

    private func flash(_ text: String) {
        withAnimation { message = text }
        Task { try? await Task.sleep(for: .seconds(2)); withAnimation { message = nil } }
    }
}

private struct DateBox: Identifiable { let id = UUID(); let date: Date }

// MARK: - Shared helpers

extension TaskItem {
    /// A task shows as a time block when its due date has a time (not midnight) and it isn't already
    /// time-blocked onto the Keel calendar (that event is drawn instead, so it never appears twice).
    var timelineStart: Date? {
        guard scheduledBlockStart == nil, let due = dueDate else { return nil }
        let c = Calendar.current.dateComponents([.hour, .minute], from: due)
        return (c.hour == 0 && c.minute == 0) ? nil : due
    }
}

extension EKEvent {
    var stableId: String { "\(calendarItemIdentifier)|\(startDate.timeIntervalSince1970)" }
    var color: Color { Color(cgColor: calendar.cgColor) }
}

// MARK: - Day / Week timeline

/// One thing on the timeline: an event, a task, or several tasks due around the same time.
struct TimelineItem: Identifiable {
    enum Kind { case event(EKEvent), task(TaskItem), tasks([TaskItem]) }
    let id: String
    let kind: Kind
    let start: Date
    let end: Date          // visual end (never shorter than a readable card)
    var lane = 0
    var lanes = 1

    var isTask: Bool { if case .event = kind { return false }; return true }
}

enum TimelineLayout {
    /// Builds a day's items so nothing ever draws on top of anything else:
    /// tasks due in the same slot become one pill, crowded clusters fold their tasks into a single
    /// "N tasks" pill, and every overlapping cluster is split into side-by-side lanes.
    static func items(day: Date, events: [EKEvent], tasks: [TaskItem], hourHeight: CGFloat, maxLanes: Int, slotMinutes: Int) -> [TimelineItem] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = dayStart.addingTimeInterval(86_400)
        let minLength = TimeInterval(30 / hourHeight * 3600)          // ~30pt tall at minimum
        func visualEnd(_ s: Date, _ e: Date) -> Date { min(max(e, s.addingTimeInterval(minLength)), dayEnd) }

        var eventItems: [TimelineItem] = events
            .filter { !$0.isAllDay && $0.startDate < dayEnd && $0.endDate > dayStart }
            .map { e in
                let s = max(e.startDate, dayStart)
                return TimelineItem(id: "e|" + e.stableId, kind: .event(e), start: s, end: visualEnd(s, e.endDate))
            }

        let timed = tasks.filter { t in t.timelineStart.map { $0 >= dayStart && $0 < dayEnd } == true }
        let slot = TimeInterval(slotMinutes * 60)
        let bySlot = Dictionary(grouping: timed) { t in
            Date(timeIntervalSinceReferenceDate: floor((t.timelineStart ?? dayStart).timeIntervalSinceReferenceDate / slot) * slot)
        }
        var taskItems: [TimelineItem] = bySlot.map { key, group in
            let sorted = group.sorted { ($0.timelineStart ?? key, -$0.priority.rawValue) < ($1.timelineStart ?? key, -$1.priority.rawValue) }
            let s = sorted.first?.timelineStart ?? key
            if sorted.count == 1, let t = sorted.first {
                let length = TimeInterval((t.estimatedMinutes ?? 0) * 60)
                return TimelineItem(id: "t|\(t.id)", kind: .task(t), start: s, end: visualEnd(s, s.addingTimeInterval(length)))
            }
            return TimelineItem(id: "g|\(key.timeIntervalSince1970)", kind: .tasks(sorted), start: s, end: visualEnd(s, s))
        }

        // Fold tasks in clusters that would need too many lanes into one pill per cluster.
        var all = eventItems + taskItems
        for cluster in clusters(all) where laneCount(cluster) > maxLanes {
            let clusterTasks = cluster.filter(\.isTask)
            guard clusterTasks.count > 1 else { continue }
            let ids = Set(clusterTasks.map(\.id))
            let folded: [TaskItem] = clusterTasks.flatMap { item -> [TaskItem] in
                switch item.kind { case .task(let t): [t]; case .tasks(let ts): ts; case .event: [] }
            }
            let s = clusterTasks.map(\.start).min() ?? dayStart
            taskItems.removeAll { ids.contains($0.id) }
            taskItems.append(TimelineItem(id: "f|\(s.timeIntervalSince1970)", kind: .tasks(folded), start: s, end: visualEnd(s, s)))
        }
        eventItems.sort { $0.start < $1.start }
        all = eventItems + taskItems

        // Assign lanes within each overlap cluster.
        var out: [TimelineItem] = []
        for cluster in clusters(all) {
            var laneEnds: [Date] = []
            var placed: [TimelineItem] = []
            for var item in cluster {
                if let free = laneEnds.firstIndex(where: { $0 <= item.start }) {
                    item.lane = free; laneEnds[free] = item.end
                } else {
                    item.lane = laneEnds.count; laneEnds.append(item.end)
                }
                placed.append(item)
            }
            out += placed.map { var i = $0; i.lanes = max(1, laneEnds.count); return i }
        }
        return out
    }

    /// Groups items that overlap (directly or through each other), sorted by start, longest first.
    static func clusters(_ items: [TimelineItem]) -> [[TimelineItem]] {
        let sorted = items.sorted { $0.start == $1.start ? $0.end > $1.end : $0.start < $1.start }
        var result: [[TimelineItem]] = []
        var current: [TimelineItem] = []
        var currentEnd = Date.distantPast
        for item in sorted {
            if !current.isEmpty && item.start >= currentEnd { result.append(current); current = [] ; currentEnd = .distantPast }
            current.append(item)
            currentEnd = max(currentEnd, item.end)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    static func laneCount(_ cluster: [TimelineItem]) -> Int {
        var laneEnds: [Date] = []
        for item in cluster {
            if let free = laneEnds.firstIndex(where: { $0 <= item.start }) { laneEnds[free] = item.end } else { laneEnds.append(item.end) }
        }
        return laneEnds.count
    }
}

struct TimelineGrid: View {
    let days: [Date]
    let events: [EKEvent]
    let tasks: [TaskItem]
    var onTapSlot: (Date) -> Void
    var onTapEvent: (EKEvent) -> Void
    var onTapTask: (TaskItem) -> Void
    var onTapTaskGroup: ([TaskItem]) -> Void
    var onTapDay: (Date) -> Void
    var onMoveEvent: (EKEvent, Date) -> Void
    var onMoveTask: (TaskItem, Date) -> Void

    @State private var allDayExpanded = false
    private let cal = Calendar.current
    private var isDay: Bool { days.count == 1 }
    private var hourHeight: CGFloat { isDay ? 64 : 52 }
    private let gutter: CGFloat = 46

    var body: some View {
        GeometryReader { geo in
            let colWidth = (geo.size.width - gutter - 4) / CGFloat(max(days.count, 1))
            VStack(spacing: 0) {
                if !isDay { dayHeader(colWidth) }
                allDayRow(colWidth)
                Rectangle().fill(DS.Palette.inkSoft.opacity(0.15)).frame(height: 0.5)
                ScrollViewReader { proxy in
                    ScrollView {
                        ZStack(alignment: .topLeading) {
                            hourRows
                                .contentShape(Rectangle())
                                .onTapGesture(coordinateSpace: .local) { p in
                                    guard p.x > gutter else { return }
                                    let dayIndex = min(days.count - 1, Int((p.x - gutter) / colWidth))
                                    let minutes = Int(p.y / hourHeight * 60) / 30 * 30
                                    if let d = cal.date(byAdding: .minute, value: minutes, to: cal.startOfDay(for: days[dayIndex])) {
                                        onTapSlot(d)
                                    }
                                }
                            ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                                dayColumn(day: day, index: i, colWidth: colWidth)
                            }
                            nowLine(colWidth)
                        }
                        .padding(.bottom, 80)        // room above the Focus bar
                    }
                    .onAppear { proxy.scrollTo(max(0, cal.component(.hour, from: Date()) - 1), anchor: .top) }
                }
            }
        }
    }

    private func dayHeader(_ colWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter)
            ForEach(days, id: \.self) { day in
                let today = cal.isDateInToday(day)
                Button { onTapDay(day) } label: {
                    VStack(spacing: 3) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(today ? DS.Palette.accent : DS.Palette.inkSoft)
                        Text(day.formatted(.dateTime.day()))
                            .font(.system(size: 16, weight: today ? .bold : .medium, design: .rounded))
                            .frame(width: 30, height: 30)
                            .background(today ? DS.Palette.accent : .clear, in: Circle())
                            .foregroundStyle(today ? .white : DS.Palette.ink)
                    }
                    .frame(width: colWidth)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, DS.Space.xs)
    }

    /// All-day events (duplicates from overlapping holiday calendars merged) and date-only tasks.
    private func allDayRow(_ colWidth: CGFloat) -> some View {
        let limit = allDayExpanded ? 12 : (isDay ? 2 : 2)
        let perDay: [(events: [EKEvent], tasks: [TaskItem])] = days.map { day in
            var seen = Set<String>()
            let evs = events.filter { $0.isAllDay && overlaps($0, day) }
                .filter { seen.insert(($0.title ?? "").lowercased()).inserted }
            let ts = tasks.filter { t in t.timelineStart == nil && t.scheduledBlockStart == nil && t.dueDate.map { cal.isDate($0, inSameDayAs: day) } == true }
            return (evs, ts)
        }
        let anyOverflow = perDay.contains { $0.events.count + $0.tasks.count > 2 }
        let isEmpty = perDay.allSatisfy { $0.events.isEmpty && $0.tasks.isEmpty }
        return Group {
            if !isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    Text("all-day").font(.system(size: 10, weight: .medium)).foregroundStyle(DS.Palette.inkSoft)
                        .frame(width: gutter - 6, alignment: .trailing).padding(.trailing, 6).padding(.top, 5)
                    ForEach(Array(perDay.enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(entry.events.prefix(limit), id: \.stableId) { e in
                                AllDayChip(title: e.title ?? "Event", color: e.color, isTask: false, compact: !isDay)
                                    .onTapGesture { onTapEvent(e) }
                            }
                            ForEach(entry.tasks.prefix(max(0, limit - min(entry.events.count, limit)))) { t in
                                AllDayChip(title: t.title, color: DS.Palette.accent, isTask: true, compact: !isDay)
                                    .onTapGesture { onTapTask(t) }
                            }
                            let extra = entry.events.count + entry.tasks.count - limit
                            if extra > 0 {
                                Text("+\(extra) more").font(.system(size: 10, weight: .medium)).foregroundStyle(DS.Palette.accent)
                            }
                        }
                        .frame(width: colWidth - 2, alignment: .topLeading)
                        .padding(.horizontal, 1)
                    }
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .onTapGesture { if anyOverflow { withAnimation(DS.spring) { allDayExpanded.toggle() } } }
            }
        }
    }

    private var hourRows: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                HStack(alignment: .top, spacing: 0) {
                    Text(hourLabel(h))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.Palette.inkSoft.opacity(0.8))
                        .frame(width: gutter - 8, alignment: .trailing)
                        .padding(.trailing, 8)
                        .offset(y: -7)
                    VStack(spacing: 0) {
                        Rectangle().fill(DS.Palette.inkSoft.opacity(0.14)).frame(height: 0.5)
                        Spacer()
                    }
                }
                .frame(height: hourHeight)
                .id(h)
            }
        }
    }

    private func hourLabel(_ h: Int) -> String {
        guard h > 0, let d = cal.date(bySettingHour: h, minute: 0, second: 0, of: Date()) else { return "" }
        return d.formatted(.dateTime.hour())
    }

    @ViewBuilder
    private func dayColumn(day: Date, index: Int, colWidth: CGFloat) -> some View {
        let items = TimelineLayout.items(day: day, events: events, tasks: tasks, hourHeight: hourHeight,
                                         maxLanes: isDay ? 3 : 2, slotMinutes: isDay ? 15 : 30)
        let dayStart = cal.startOfDay(for: day)
        let x0 = gutter + CGFloat(index) * colWidth + 2

        ForEach(items) { item in
            let laneWidth = (colWidth - 4) / CGFloat(item.lanes)
            let y = CGFloat(item.start.timeIntervalSince(dayStart) / 3600) * hourHeight + 1
            let h = max(26, CGFloat(item.end.timeIntervalSince(item.start) / 3600) * hourHeight - 2)
            itemView(item, height: h, colWidth: colWidth)
                .frame(width: laneWidth - 2, height: h)
                .offset(x: x0 + CGFloat(item.lane) * laneWidth, y: y)
        }
    }

    @ViewBuilder
    private func itemView(_ item: TimelineItem, height: CGFloat, colWidth: CGFloat) -> some View {
        switch item.kind {
        case .event(let e):
            DraggableBlock(hourHeight: hourHeight, colWidth: colWidth, onTap: { onTapEvent(e) },
                           onDrop: { dDays, dMin in shift(e.startDate, dDays, dMin).map { onMoveEvent(e, $0) } }) {
                EventCard(title: e.title ?? "Event", start: e.startDate, end: e.endDate, color: e.color,
                          compact: !isDay, height: height)
            }
        case .task(let t):
            DraggableBlock(hourHeight: hourHeight, colWidth: colWidth, onTap: { onTapTask(t) },
                           onDrop: { dDays, dMin in shift(t.timelineStart ?? Date(), dDays, dMin).map { onMoveTask(t, $0) } }) {
                TaskPill(task: t, compact: !isDay)
            }
        case .tasks(let ts):
            TaskGroupPill(tasks: ts, compact: !isDay)
                .onTapGesture { onTapTaskGroup(ts) }
        }
    }

    private func shift(_ date: Date, _ days: Int, _ minutes: Int) -> Date? {
        cal.date(byAdding: .minute, value: minutes, to: date).flatMap { cal.date(byAdding: .day, value: days, to: $0) }
    }

    @ViewBuilder
    private func nowLine(_ colWidth: CGFloat) -> some View {
        if let i = days.firstIndex(where: { cal.isDateInToday($0) }) {
            let y = CGFloat(Date().timeIntervalSince(cal.startOfDay(for: Date())) / 3600) * hourHeight
            HStack(spacing: 0) {
                Circle().fill(Color.red).frame(width: 9, height: 9)
                Rectangle().fill(Color.red).frame(height: 1.5)
            }
            .frame(width: colWidth + 6)
            .offset(x: gutter + CGFloat(i) * colWidth - 4, y: y - 4.5)
            .allowsHitTesting(false)
            .shadow(color: .red.opacity(0.4), radius: 3)
        }
    }

    private func overlaps(_ e: EKEvent, _ day: Date) -> Bool {
        let s = cal.startOfDay(for: day)
        return e.startDate < s.addingTimeInterval(86_400) && e.endDate > s
    }
}

/// Tap to open; long-press then drag to move. Snaps to 15 minutes and whole days.
struct DraggableBlock<Content: View>: View {
    let hourHeight: CGFloat
    let colWidth: CGFloat
    var onTap: () -> Void
    var onDrop: (_ days: Int, _ minutes: Int) -> Void
    @ViewBuilder var content: Content

    @GestureState private var drag: CGSize = .zero
    @State private var lifted = false

    var body: some View {
        content
            .scaleEffect(lifted ? 1.03 : 1)
            .shadow(color: .black.opacity(lifted ? 0.25 : 0), radius: 10, y: 6)
            .offset(drag)
            .zIndex(lifted ? 10 : 0)
            .onTapGesture(perform: onTap)
            .gesture(
                LongPressGesture(minimumDuration: 0.3)
                    .onEnded { _ in withAnimation(DS.spring) { lifted = true }; Haptics.tap() }
                    .sequenced(before: DragGesture())
                    .updating($drag) { value, state, _ in
                        if case .second(true, let d?) = value { state = d.translation }
                    }
                    .onEnded { value in
                        withAnimation(DS.spring) { lifted = false }
                        guard case .second(true, let d?) = value else { return }
                        let minutes = Int((d.translation.height / hourHeight * 60 / 15).rounded()) * 15
                        let days = colWidth > 0 ? Int((d.translation.width / colWidth).rounded()) : 0
                        if minutes != 0 || days != 0 { onDrop(days, minutes) }
                    }
            )
    }
}

/// Solid, readable event card: tinted fill, color bar, title, and time when there's room.
struct EventCard: View {
    let title: String
    let start: Date
    let end: Date
    let color: Color
    let compact: Bool
    let height: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                if height < 40 {
                    Text(compact ? title : "\(title)  ·  \(start.formatted(date: .omitted, time: .shortened))")
                        .lineLimit(1)
                } else {
                    Text(title).lineLimit(compact ? 4 : 3)
                    Text("\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: compact ? 9 : 11, weight: .medium))
                        .foregroundStyle(DS.Palette.inkSoft)
                        .lineLimit(1)
                }
            }
            .font(.system(size: compact ? 10.5 : 13, weight: .semibold))
            .foregroundStyle(DS.Palette.ink)
            .padding(.horizontal, compact ? 4 : 7)
            .padding(.vertical, compact ? 3 : 5)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(scheme == .dark ? 0.30 : 0.16))
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

/// A single timed task: slim pill with a tappable checkbox.
struct TaskPill: View {
    @Bindable var task: TaskItem
    let compact: Bool

    var body: some View {
        HStack(spacing: 5) {
            Button {
                TaskActions.setDone(task, true)
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: compact ? 10 : 13, weight: .semibold))
                    .foregroundStyle(task.priority == .none ? DS.Palette.accent : task.priority.color)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(task.title)")
            Text(task.title)
                .font(.system(size: compact ? 10.5 : 13, weight: .medium))
                .foregroundStyle(DS.Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            if !compact, task.recurrence != nil {
                Image(systemName: "repeat").font(.system(size: 10)).foregroundStyle(DS.Palette.inkSoft)
            }
        }
        .padding(.horizontal, compact ? 4 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, compact ? 4 : 6)
        .background(DS.Palette.accent.opacity(0.14), in: .rect(cornerRadius: 8))
    }
}

/// Several tasks due around the same time, folded into one pill. Tap for the checklist.
struct TaskGroupPill: View {
    let tasks: [TaskItem]
    let compact: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checklist")
                .font(.system(size: compact ? 10 : 12, weight: .semibold))
                .foregroundStyle(DS.Palette.accent)
            Text(compact ? "\(tasks.count) tasks" : (tasks.first?.title ?? "Tasks"))
                .font(.system(size: compact ? 10.5 : 13, weight: .medium))
                .foregroundStyle(DS.Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            if !compact {
                Text("+\(tasks.count - 1)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(DS.Palette.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, compact ? 4 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, compact ? 4 : 6)
        .background(DS.Palette.accent.opacity(0.14), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DS.Palette.accent.opacity(0.35), lineWidth: 1))
        .accessibilityLabel("\(tasks.count) tasks")
    }
}

struct AllDayChip: View {
    let title: String
    let color: Color
    let isTask: Bool
    let compact: Bool
    var body: some View {
        HStack(spacing: 4) {
            if isTask { Image(systemName: "circle").font(.system(size: compact ? 8 : 10, weight: .semibold)).foregroundStyle(color) }
            Text(title).lineLimit(1)
        }
        .font(.system(size: compact ? 10 : 12, weight: .semibold))
        .foregroundStyle(DS.Palette.ink)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.22), in: .rect(cornerRadius: 6))
    }
}

/// The checklist behind a "+N" task pill.
struct TaskGroupSheet: View {
    let tasks: [TaskItem]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(tasks) { t in
                    NavigationLink { TaskDetailView(task: t) } label: { TaskRow(task: t) }
                }
            }
            .navigationTitle(tasks.first?.timelineStart?.formatted(date: .omitted, time: .shortened) ?? "Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct TaskGroupRef: Identifiable { let id = UUID(); let tasks: [TaskItem] }

// MARK: - Month

struct MonthGrid: View {
    let days: [Date]
    let month: Date
    let selected: Date
    let events: [EKEvent]
    let tasks: [TaskItem]
    var onSelect: (Date) -> Void
    private let cal = Calendar.current

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        VStack(spacing: DS.Space.xs) {
            HStack(spacing: 0) {
                ForEach(days.prefix(7), id: \.self) { d in
                    Text(d.formatted(.dateTime.weekday(.narrow))).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(days, id: \.self) { day in
                    let inMonth = cal.isDate(day, equalTo: month, toGranularity: .month)
                    let isSelected = cal.isDate(day, inSameDayAs: selected)
                    let today = cal.isDateInToday(day)
                    let dayEvents = events.filter { $0.startDate < cal.startOfDay(for: day).addingTimeInterval(86_400) && $0.endDate > cal.startOfDay(for: day) }
                    let dayTasks = tasks.filter { $0.dueDate.map { cal.isDate($0, inSameDayAs: day) } == true }
                    Button { onSelect(day) } label: {
                        VStack(spacing: 3) {
                            Text(day.formatted(.dateTime.day()))
                                .font(.system(.subheadline, design: .rounded, weight: today || isSelected ? .bold : .regular))
                                .frame(width: 30, height: 30)
                                .background(isSelected ? DS.Palette.accent : (today ? DS.Palette.accent.opacity(0.15) : .clear), in: Circle())
                                .foregroundStyle(isSelected ? .white : (inMonth ? DS.Palette.ink : DS.Palette.inkSoft.opacity(0.5)))
                            HStack(spacing: 2) {
                                ForEach(Array(dayEvents.prefix(3).enumerated()), id: \.offset) { _, e in
                                    Circle().fill(e.color).frame(width: 5, height: 5)
                                }
                                if !dayTasks.isEmpty { Circle().strokeBorder(DS.Palette.accent, lineWidth: 1).frame(width: 5, height: 5) }
                            }
                            .frame(height: 6)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(dayEvents.count) events, \(dayTasks.count) tasks")
                }
            }
        }
    }
}

/// The selected day's events and tasks, listed under the month grid.
struct DayAgenda: View {
    let day: Date
    let events: [EKEvent]
    let tasks: [TaskItem]
    var onTapEvent: (EKEvent) -> Void
    var onTapTask: (TaskItem) -> Void
    private let cal = Calendar.current

    var body: some View {
        let start = cal.startOfDay(for: day)
        let dayEvents = events.filter { $0.startDate < start.addingTimeInterval(86_400) && $0.endDate > start }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
        let dayTasks = tasks.filter { $0.dueDate.map { cal.isDate($0, inSameDayAs: day) } == true }
        VStack(alignment: .leading, spacing: DS.Space.s) {
            SectionHeader(title: day.formatted(.dateTime.weekday(.wide).month().day()))
            if dayEvents.isEmpty && dayTasks.isEmpty {
                Text("Nothing scheduled. Tap + to add.").font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
            }
            ForEach(dayEvents, id: \.stableId) { e in
                Button { onTapEvent(e) } label: {
                    HStack(spacing: DS.Space.m) {
                        RoundedRectangle(cornerRadius: 2).fill(e.color).frame(width: 4, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title ?? "Event").font(DS.Font.headline)
                            Text(e.isAllDay ? "All day" : "\(e.startDate.formatted(date: .omitted, time: .shortened)) – \(e.endDate.formatted(date: .omitted, time: .shortened))")
                                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        Text(e.calendar.title).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
                .buttonStyle(.plain)
            }
            ForEach(dayTasks) { t in
                HStack {
                    TaskRow(task: t)
                    Button { onTapTask(t) } label: { Image(systemName: "chevron.right").foregroundStyle(DS.Palette.inkSoft) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Apple's event editor / viewer (full editing, alerts, repeat, invitees, RSVP)

struct EventEditor: UIViewControllerRepresentable {
    let event: EKEvent?
    let start: Date?
    var onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = CalendarService.shared.store
        let vc = EKEventEditViewController()
        vc.eventStore = store
        if let event {
            vc.event = event
        } else {
            let e = EKEvent(eventStore: store)
            e.startDate = start ?? Date()
            e.endDate = e.startDate.addingTimeInterval(3600)
            e.calendar = store.defaultCalendarForNewEvents
            vc.event = e
        }
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onDone()
        }
    }
}

struct EventDetail: UIViewControllerRepresentable {
    let event: EKEvent
    var onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = EKEventViewController()
        vc.event = event
        vc.allowsEditing = true
        vc.allowsCalendarPreview = true
        vc.delegate = context.coordinator
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ nav: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, EKEventViewDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) {
            onDone()
        }
    }
}

// MARK: - Calendar visibility

struct CalendarPicker: View {
    @Binding var hiddenRaw: String
    @Environment(\.dismiss) private var dismiss

    private var hidden: Set<String> { Set(hiddenRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        NavigationStack {
            List {
                ForEach(CalendarService.shared.calendarsBySource, id: \.source) { group in
                    Section(group.source) {
                        ForEach(group.calendars, id: \.calendarIdentifier) { c in
                            Toggle(isOn: Binding(
                                get: { !hidden.contains(c.calendarIdentifier) },
                                set: { show in
                                    var h = hidden
                                    if show { h.remove(c.calendarIdentifier) } else { h.insert(c.calendarIdentifier) }
                                    hiddenRaw = h.sorted().joined(separator: ",")
                                })) {
                                Label(c.title, systemImage: "circle.fill").foregroundStyle(Color(cgColor: c.cgColor))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Calendars")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

/// Add a task at a specific date/time from the calendar.
struct QuickTaskSheet: View {
    let date: Date
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var due = Date()
    @State private var hasTime = true

    var body: some View {
        NavigationStack {
            Form {
                TextField("Task", text: $title)
                Toggle("At a specific time", isOn: $hasTime)
                DatePicker("When", selection: $due, displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
            }
            .navigationTitle("New task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let when = hasTime ? due : Calendar.current.startOfDay(for: due)
                        let t = TaskItem(title: title, dueDate: when)
                        if hasTime { t.alertOffsetMinutes = 0 }
                        ctx.insert(t)
                        try? CalendarService.shared.push(t)
                        TaskAlerts.schedule(t)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
            .onAppear { due = date }
        }
        .presentationDetents([.medium])
    }
}
