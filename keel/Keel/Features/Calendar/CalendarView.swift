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
                    TimelineGrid(days: visibleDays, events: events, tasks: tasks,
                                 onTapSlot: { draft = EventDraft(event: nil, start: $0) },
                                 onTapEvent: { viewing = EventRef(event: $0) },
                                 onTapTask: { openTask = $0 },
                                 onTapDay: { anchor = $0; modeRaw = CalendarMode.day.rawValue },
                                 onMoveEvent: moveEvent, onMoveTask: moveTask)
                case .month:
                    ScrollView {
                        MonthGrid(days: visibleDays, month: anchor, selected: anchor, events: events, tasks: tasks) { day in
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
                    Button { showCalendars = true } label: { Image(systemName: "calendar.badge.checkmark") }
                        .accessibilityLabel("Choose calendars")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New event", systemImage: "calendar.badge.plus") { draft = EventDraft(event: nil, start: defaultNewStart()) }
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

struct TimelineGrid: View {
    let days: [Date]
    let events: [EKEvent]
    let tasks: [TaskItem]
    var onTapSlot: (Date) -> Void
    var onTapEvent: (EKEvent) -> Void
    var onTapTask: (TaskItem) -> Void
    var onTapDay: (Date) -> Void
    var onMoveEvent: (EKEvent, Date) -> Void
    var onMoveTask: (TaskItem, Date) -> Void

    private let hourHeight: CGFloat = 56
    private let gutter: CGFloat = 44
    private let cal = Calendar.current

    var body: some View {
        GeometryReader { geo in
            let colWidth = (geo.size.width - gutter) / CGFloat(max(days.count, 1))
            VStack(spacing: 0) {
                if days.count > 1 { dayHeader(colWidth) }
                allDayRow(colWidth)
                Divider()
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
                    VStack(spacing: 2) {
                        Text(day.formatted(.dateTime.weekday(.narrow))).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        Text(day.formatted(.dateTime.day()))
                            .font(DS.Font.headline)
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

    /// All-day events and undated-time tasks for each day.
    private func allDayRow(_ colWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("all-day").font(.system(size: 9)).foregroundStyle(DS.Palette.inkSoft).frame(width: gutter)
            ForEach(days, id: \.self) { day in
                let allDay = events.filter { $0.isAllDay && overlaps($0, day) }
                let dayTasks = tasks.filter { t in t.timelineStart == nil && t.scheduledBlockStart == nil && t.dueDate.map { cal.isDate($0, inSameDayAs: day) } == true }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(allDay.prefix(2), id: \.stableId) { e in
                        Text(e.title ?? "Event").font(.system(size: 10, weight: .medium)).lineLimit(1)
                            .padding(.horizontal, 4).frame(maxWidth: .infinity, alignment: .leading)
                            .background(e.color.opacity(0.25), in: .rect(cornerRadius: 4))
                            .onTapGesture { onTapEvent(e) }
                    }
                    ForEach(dayTasks.prefix(days.count > 1 ? 2 : 6)) { t in
                        Label(t.title, systemImage: "circle").font(.system(size: 10)).lineLimit(1)
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 4).frame(maxWidth: .infinity, alignment: .leading)
                            .background(DS.Palette.accent.opacity(0.12), in: .rect(cornerRadius: 4))
                            .onTapGesture { onTapTask(t) }
                    }
                    let extra = max(0, allDay.count - 2) + max(0, dayTasks.count - (days.count > 1 ? 2 : 6))
                    if extra > 0 { Text("+\(extra)").font(.system(size: 9)).foregroundStyle(DS.Palette.inkSoft) }
                }
                .frame(width: colWidth - 2)
                .padding(.horizontal, 1)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 28)
    }

    private var hourRows: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                HStack(alignment: .top, spacing: 0) {
                    Text(hourLabel(h)).font(.system(size: 10)).foregroundStyle(DS.Palette.inkSoft)
                        .frame(width: gutter, alignment: .trailing).padding(.trailing, 4).offset(y: -6)
                    VStack { Divider(); Spacer() }
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
        let timed = events.filter { !$0.isAllDay && overlaps($0, day) }.sorted { $0.startDate < $1.startDate }
        let lanes = laneLayout(timed)
        let laneCount = max(1, (lanes.values.max() ?? 0) + 1)
        let laneWidth = (colWidth - 4) / CGFloat(laneCount)
        let dayStart = cal.startOfDay(for: day)
        let x0 = gutter + CGFloat(index) * colWidth + 2

        ForEach(timed, id: \.stableId) { e in
            let start = max(e.startDate, dayStart)
            let end = min(e.endDate, dayStart.addingTimeInterval(86_400))
            let y = CGFloat(start.timeIntervalSince(dayStart) / 3600) * hourHeight
            let h = max(22, CGFloat(end.timeIntervalSince(start) / 3600) * hourHeight - 2)
            DraggableBlock(hourHeight: hourHeight, colWidth: colWidth,
                           onTap: { onTapEvent(e) },
                           onDrop: { dDays, dMinutes in
                               if let s = cal.date(byAdding: .minute, value: dMinutes, to: e.startDate),
                                  let s2 = cal.date(byAdding: .day, value: dDays, to: s) { onMoveEvent(e, s2) }
                           }) {
                EventBlock(title: e.title ?? "Event", time: e.startDate, color: e.color, compact: days.count > 1)
            }
            .frame(width: laneWidth - 2, height: h)
            .offset(x: x0 + CGFloat(lanes[e.stableId] ?? 0) * laneWidth, y: y)
        }

        ForEach(tasks.filter { $0.timelineStart.map { cal.isDate($0, inSameDayAs: day) } == true }) { t in
            let start = t.timelineStart ?? dayStart
            let y = CGFloat(start.timeIntervalSince(dayStart) / 3600) * hourHeight
            let h = max(22, CGFloat(t.estimatedMinutes ?? 30) / 60 * hourHeight - 2)
            DraggableBlock(hourHeight: hourHeight, colWidth: colWidth,
                           onTap: { onTapTask(t) },
                           onDrop: { dDays, dMinutes in
                               if let s = cal.date(byAdding: .minute, value: dMinutes, to: start),
                                  let s2 = cal.date(byAdding: .day, value: dDays, to: s) { onMoveTask(t, s2) }
                           }) {
                TaskBlock(title: t.title, compact: days.count > 1)
            }
            .frame(width: colWidth - 6, height: h)
            .offset(x: x0 + 1, y: y)
        }
    }

    @ViewBuilder
    private func nowLine(_ colWidth: CGFloat) -> some View {
        if let i = days.firstIndex(where: { cal.isDateInToday($0) }) {
            let y = CGFloat(Date().timeIntervalSince(cal.startOfDay(for: Date())) / 3600) * hourHeight
            HStack(spacing: 0) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Rectangle().fill(.red).frame(height: 1.5)
            }
            .frame(width: colWidth + 4)
            .offset(x: gutter + CGFloat(i) * colWidth - 4, y: y - 4)
            .allowsHitTesting(false)
        }
    }

    private func overlaps(_ e: EKEvent, _ day: Date) -> Bool {
        let s = cal.startOfDay(for: day)
        return e.startDate < s.addingTimeInterval(86_400) && e.endDate > s
    }

    /// Side-by-side lanes for overlapping events (greedy).
    private func laneLayout(_ evts: [EKEvent]) -> [String: Int] {
        var laneEnds: [Date] = []
        var result: [String: Int] = [:]
        for e in evts {
            if let free = laneEnds.firstIndex(where: { $0 <= e.startDate }) {
                laneEnds[free] = e.endDate; result[e.stableId] = free
            } else {
                laneEnds.append(e.endDate); result[e.stableId] = laneEnds.count - 1
            }
        }
        return result
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
            .shadow(color: .black.opacity(lifted ? 0.2 : 0), radius: 8, y: 4)
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

struct EventBlock: View {
    let title: String
    let time: Date
    let color: Color
    let compact: Bool
    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: compact ? 10 : 13, weight: .semibold)).lineLimit(compact ? 3 : 2)
                if !compact { Text(time, style: .time).font(.system(size: 11)).foregroundStyle(DS.Palette.inkSoft) }
            }
            Spacer(minLength: 0)
        }
        .padding(3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(0.18), in: .rect(cornerRadius: 6))
        .accessibilityElement(children: .combine)
    }
}

struct TaskBlock: View {
    let title: String
    let compact: Bool
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle").font(.system(size: compact ? 9 : 12))
            Text(title).font(.system(size: compact ? 10 : 13, weight: .medium)).lineLimit(compact ? 3 : 2)
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Palette.accent.opacity(0.10), in: .rect(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.Palette.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .foregroundStyle(DS.Palette.accent)
    }
}

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
