import SwiftUI
import SwiftData
import EventKit
import Charts
import TipKit

// MARK: - Plan my week

/// The week ahead as seven days: each day's meetings and free time, and the tasks due that day.
/// Drag a task onto a day (or tap it, then tap the day) to give it that date.
struct PlanMyWeekView: View {
    var embedded = false                       // opened inside another navigation stack (Compass)
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }, animation: .snappy) private var open: [TaskItem]
    @State private var weekStart = PlanMyWeekView.startOfWeek(Date())
    @State private var picked: TaskItem?
    @State private var target: Date?
    @State private var events: [Date: [EKEvent]] = [:]
    @State private var free: [Date: Double] = [:]

    private var cal: Calendar { Calendar.current }
    static func startOfWeek(_ d: Date) -> Date {
        let cal = Calendar.current
        return cal.dateInterval(of: .weekOfYear, for: d)?.start ?? cal.startOfDay(for: d)
    }
    private var days: [Date] { (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) } }
    private var weekEnd: Date { cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart }

    /// No date yet, or overdue: waiting for a day.
    private var tray: [TaskItem] {
        let today = cal.startOfDay(for: Date())
        return open.filter { !$0.isDeleted && ($0.dueDate == nil || $0.dueDate! < today) && !$0.isWaitingOn }
            .sorted { $0.priority.rawValue > $1.priority.rawValue }
    }
    private func due(on day: Date) -> [TaskItem] { open.filter { !$0.isDeleted && ($0.dueDate.map { cal.isDate($0, inSameDayAs: day) } ?? false) } }

    var body: some View {
        if embedded { page } else { NavigationStack { page } }
    }

    private var page: some View {
            VStack(spacing: 0) {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous week")
                    Spacer()
                    Text("\(weekStart.formatted(.dateTime.month(.abbreviated).day())) – \((cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart).formatted(.dateTime.month(.abbreviated).day()))")
                        .font(DS.Font.headline)
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next week")
                }
                .padding(.horizontal).padding(.vertical, 8)
                trayView
                Divider()
                ScrollView {
                    LazyVStack(spacing: 10) { ForEach(days, id: \.self) { dayRow($0) } }.padding()
                }
            }
            .navigationTitle("Plan my week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { if !embedded { ToolbarItem(placement: .confirmationAction) { Button("Done") { try? ctx.save(); dismiss() } } } }
            .task(id: weekStart) { load() }
    }

    private var trayView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(picked == nil ? "Drag a task onto a day, or tap it and then tap the day." : "Now tap a day for “\(picked?.title ?? "")”.")
                .font(DS.Font.caption).foregroundStyle(picked == nil ? DS.Palette.inkSoft : DS.Palette.accent).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if tray.isEmpty { Text("Every task has a day.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft) }
                    ForEach(tray.prefix(40)) { t in
                        let on = picked?.id == t.id
                        Button { withAnimation(.snappy) { picked = on ? nil : t } } label: {
                            Text(t.title).font(DS.Font.caption.weight(.semibold)).lineLimit(1)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(on ? DS.Palette.accent.opacity(0.25) : DS.Palette.elevated, in: Capsule())
                                .overlay(Capsule().strokeBorder(on ? DS.Palette.accent : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .draggable(t.id.uuidString)
                    }
                }
                .padding(.horizontal).padding(.bottom, 10)
            }
        }
    }

    private func dayRow(_ day: Date) -> some View {
        let tasks = due(on: day)
        let meetings = events[day] ?? []
        let hours = free[day] ?? 0
        let busy = tasks.count >= 6 || hours < 2
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(day.formatted(.dateTime.weekday(.wide).day())).font(DS.Font.headline)
                    .foregroundStyle(cal.isDateInToday(day) ? DS.Palette.accent : DS.Palette.ink)
                Spacer()
                Text("\(meetings.count) meeting\(meetings.count == 1 ? "" : "s") · \(String(format: "%.1f", hours)) h free · \(tasks.count) task\(tasks.count == 1 ? "" : "s")")
                    .font(.caption2).foregroundStyle(busy ? .orange : DS.Palette.inkSoft)
            }
            ForEach(tasks) { t in
                HStack {
                    Image(systemName: "circle").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                    Text(t.title).font(DS.Font.caption).lineLimit(1)
                    Spacer()
                    if t.hasDueTime, let d = t.dueDate { Text(d.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(DS.Palette.inkSoft) }
                }
                .contextMenu { Button("No day yet", systemImage: "calendar.badge.minus") { setDay(t, nil) } }
            }
            if tasks.isEmpty { Text(busy ? "A full day already." : "Open. Drop something here.").font(.caption2).foregroundStyle(DS.Palette.inkSoft) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(target == day ? DS.Palette.accent.opacity(0.12) : DS.Palette.elevated, in: .rect(cornerRadius: 14))
        .contentShape(Rectangle())
        .onTapGesture { if let t = picked { setDay(t, day) } }
        .dropDestination(for: String.self) { ids, _ in
            guard let s = ids.first, let id = UUID(uuidString: s), let t = open.first(where: { $0.id == id }) else { return false }
            setDay(t, day); return true
        } isTargeted: { on in withAnimation(.snappy) { target = on ? day : (target == day ? nil : target) } }
    }

    private func shift(_ weeks: Int) {
        withAnimation(.snappy) { weekStart = cal.date(byAdding: .weekOfYear, value: weeks, to: weekStart) ?? weekStart }
    }

    private func setDay(_ t: TaskItem, _ day: Date?) {
        withAnimation(.snappy) {
            if let day {
                // Keep the time of day if it had one.
                if t.hasDueTime, let old = t.dueDate {
                    let c = cal.dateComponents([.hour, .minute], from: old)
                    t.dueDate = cal.date(bySettingHour: c.hour ?? 9, minute: c.minute ?? 0, second: 0, of: day)
                } else { t.dueDate = cal.startOfDay(for: day) }
            } else { t.dueDate = nil }
            t.updatedAt = Date()
            picked = nil
        }
        try? CalendarService.shared.push(t)
        TaskAlerts.schedule(t)
        Haptics.success()
    }

    private func load() {
        var ev: [Date: [EKEvent]] = [:], fr: [Date: Double] = [:]
        for d in days {
            ev[d] = CalendarService.shared.events(from: d, to: d.addingTimeInterval(86_400)).filter { !$0.isAllDay && !($0.title ?? "").hasPrefix("◆") }
            let from = max(cal.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d, Date())
            fr[d] = CalendarService.shared.freeSlots(minMinutes: 30, from: from, until: 18).reduce(0) { $0 + $1.duration / 3600 }
        }
        events = ev; free = fr
    }
}

// MARK: - Where my time went

struct TimeReportView: View {
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var sessions: [FocusSession]
    @Query private var tasks: [TaskItem]
    @State private var weekStart = PlanMyWeekView.startOfWeek(Date())
    @State private var report: (this: Week, last: Week)?

    struct Week {
        var meetings = 0.0, blocks = 0.0, focus = 0.0      // hours
        var done = 0
        var byDay: [Row] = []
    }
    struct Row: Identifiable { let id = UUID(); let day: Date; let kind: String; let hours: Double }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                HStack {
                    Button { weekStart = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Previous week")
                    Spacer()
                    Text("Week of \(weekStart.formatted(.dateTime.month(.wide).day()))").font(DS.Font.headline)
                    Spacer()
                    Button { weekStart = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Next week")
                        .disabled(weekStart >= PlanMyWeekView.startOfWeek(Date()))
                }
                if let r = report {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        stat("Meetings", r.this.meetings, r.last.meetings, .red, lowerIsBetter: true)
                        stat("Deep focus", r.this.focus, r.last.focus, .indigo, lowerIsBetter: false)
                        stat("Planned task time", r.this.blocks, r.last.blocks, .teal, lowerIsBetter: false)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tasks finished").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                            Text("\(r.this.done)").font(.title2.weight(.bold)).monospacedDigit()
                            Text("last week \(r.last.done)").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.Palette.elevated, in: .rect(cornerRadius: 14))
                    }
                    Chart(r.this.byDay) { row in
                        BarMark(x: .value("Day", row.day, unit: .day), y: .value("Hours", row.hours))
                            .foregroundStyle(by: .value("Kind", row.kind))
                    }
                    .chartForegroundStyleScale(["Meetings": Color.red.opacity(0.7), "Focus": Color.indigo, "Task time": Color.teal])
                    .frame(height: 180)
                    Text(summary(r)).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                } else {
                    ProgressView()
                }
            }
            .padding(DS.Space.m)
        }
        .background(DS.Palette.canvas)
        .navigationTitle("Where my time went")
        .task(id: weekStart) { report = (week(weekStart), week(Calendar.current.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart)) }
    }

    private func stat(_ name: String, _ v: Double, _ last: Double, _ c: Color, lowerIsBetter: Bool) -> some View {
        let diff = v - last
        let good = lowerIsBetter ? diff <= 0 : diff >= 0
        return VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
            Text(hours(v)).font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(c)
            if abs(diff) >= 0.25 {
                Text("\(diff > 0 ? "↑" : "↓") \(hours(abs(diff))) vs last week").font(.caption2).foregroundStyle(good ? .green : .orange)
            } else { Text("same as last week").font(.caption2).foregroundStyle(DS.Palette.inkSoft) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.elevated, in: .rect(cornerRadius: 14))
    }

    private func hours(_ h: Double) -> String { let m = Int((h * 60).rounded()); return "\(m / 60)h \(String(format: "%02d", m % 60))m" }

    private func summary(_ r: (this: Week, last: Week)) -> String {
        let total = r.this.meetings + r.this.focus + r.this.blocks
        guard total > 0 else { return "Nothing recorded this week yet." }
        let share = Int(r.this.meetings / total * 100)
        return share >= 50 ? "Meetings took \(share)% of your tracked time. Try protecting a morning or two for focus next week (Plan my week)."
            : "Most of your tracked time went to your own work. Nice."
    }

    private func week(_ start: Date) -> Week {
        let cal = Calendar.current
        var w = Week()
        for i in 0..<7 {
            guard let d = cal.date(byAdding: .day, value: i, to: start), d <= Date() else { continue }
            let next = d.addingTimeInterval(86_400)
            let evs = CalendarService.shared.events(from: d, to: next).filter { !$0.isAllDay }
            let blocks = evs.filter { ($0.title ?? "").hasPrefix("◆") }.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) / 3600 }
            let meetings = evs.filter { !($0.title ?? "").hasPrefix("◆") }.reduce(0.0) { $0 + min(12, $1.endDate.timeIntervalSince($1.startDate) / 3600) }
            let focus = sessions.filter { $0.startedAt >= d && $0.startedAt < next }
                .reduce(0.0) { $0 + (($1.endedAt ?? $1.startedAt).timeIntervalSince($1.startedAt)) / 3600 }
            w.meetings += meetings; w.blocks += blocks; w.focus += focus
            w.byDay += [Row(day: d, kind: "Meetings", hours: meetings), Row(day: d, kind: "Focus", hours: focus), Row(day: d, kind: "Task time", hours: blocks)]
            w.done += tasks.filter { ($0.completedAt.map { $0 >= d && $0 < next } ?? false) }.count
        }
        return w
    }
}

// MARK: - Work back from a deadline

@MainActor
enum WorkBack {
    /// Splits a task into steps (its own, or AI-made) and gives each a date from today to the day before it's due.
    static func plan(_ t: TaskItem, ctx: ModelContext) async -> Int {
        let cal = Calendar.current
        guard let due = t.dueDate, due > Date().addingTimeInterval(86_400) else { return 0 }
        var steps = t.microSteps.filter { !$0.done }.map(\.text)
        if steps.count < 2 { steps = await AIRouter.shared.breakDown(t.title, minutesAvailable: nil).map(\.text) }
        guard !steps.isEmpty else { return 0 }
        let start = cal.startOfDay(for: Date())
        let last = max(start, cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: due)) ?? start)   // a spare day before the deadline
        let span = Double(cal.dateComponents([.day], from: start, to: last).day ?? 0)
        for (i, step) in steps.enumerated() {
            let offset = steps.count == 1 ? span : (span * Double(i) / Double(steps.count - 1)).rounded()
            let day = cal.date(byAdding: .day, value: Int(offset), to: start) ?? start
            let s = TaskItem(title: "\(step) · \(t.title)", dueDate: day, priority: t.priority)
            s.listName = t.listName; s.projectId = t.projectId; s.goalId = t.goalId
            ctx.insert(s)
            try? CalendarService.shared.push(s)
        }
        try? ctx.save()
        return steps.count
    }
}

struct WorkBackSection: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var ctx
    @State private var working = false
    @State private var result: String?
    var body: some View {
        if let due = task.dueDate, due > Date().addingTimeInterval(2 * 86_400), !task.isDone {
            Section {
                Button {
                    Task {
                        working = true
                        let n = await WorkBack.plan(task, ctx: ctx)
                        working = false
                        result = n == 0 ? "Couldn't split this one. Add a few steps above and try again." : "Added \(n) dated steps, finishing the day before it's due."
                        if n > 0 { Haptics.success() }
                    }
                } label: { Label(working ? "Planning…" : "Work back from the deadline", systemImage: "calendar.day.timeline.left") }
                    .disabled(working)
                if let result { Text(result).font(.caption).foregroundStyle(DS.Palette.inkSoft) }
            } footer: {
                Text("Splits it into steps with their own dates between today and \(due.formatted(date: .abbreviated, time: .omitted)), so nothing is left for the last night.")
            }
        }
    }
}
