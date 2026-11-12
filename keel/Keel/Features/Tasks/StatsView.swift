import SwiftUI
import SwiftData
import Charts

/// How you're doing over time: completions per day, best hours, lists, estimate accuracy.
struct StatsView: View {
    @Query private var tasks: [TaskItem]
    @State private var range = 30

    private let cal = Calendar.current
    private var doneInRange: [TaskItem] {
        let since = cal.date(byAdding: .day, value: -(range - 1), to: cal.startOfDay(for: Date()))!
        return tasks.filter { ($0.completedAt ?? .distantPast) >= since }
    }
    private var perDay: [(day: Date, n: Int)] {
        let today = cal.startOfDay(for: Date())
        let grouped = Dictionary(grouping: doneInRange) { cal.startOfDay(for: $0.completedAt!) }
        return (0..<range).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -i, to: today)!
            return (d, grouped[d]?.count ?? 0)
        }
    }
    /// Days in a row with at least one task done, counting back from today (today may still be 0).
    private var streak: Int {
        let days = Set(tasks.compactMap(\.completedAt).map { cal.startOfDay(for: $0) })
        var d = cal.startOfDay(for: Date())
        if !days.contains(d) { d = cal.date(byAdding: .day, value: -1, to: d)! }
        var n = 0
        while days.contains(d) { n += 1; d = cal.date(byAdding: .day, value: -1, to: d)! }
        return n
    }

    var body: some View {
        List {
            Picker("Range", selection: $range) { Text("7 days").tag(7); Text("30 days").tag(30); Text("90 days").tag(90) }
                .pickerStyle(.segmented).listRowBackground(Color.clear)
            Section {
                HStack {
                    stat("\(doneInRange.count)", "done")
                    stat(String(format: "%.1f", Double(doneInRange.count) / Double(range)), "per day")
                    stat("\(streak)🔥", "day streak")
                }
                Chart(perDay, id: \.day) { d in
                    BarMark(x: .value("Day", d.day, unit: .day), y: .value("Done", d.n))
                        .foregroundStyle(DS.Palette.accent.gradient).cornerRadius(3)
                }
                .frame(height: 150)
            }
            Section("When you get things done") {
                let byHour = Dictionary(grouping: doneInRange) { cal.component(.hour, from: $0.completedAt!) }.mapValues(\.count)
                Chart((6...23).map { ($0, byHour[$0] ?? 0) }, id: \.0) { h in
                    BarMark(x: .value("Hour", h.0), y: .value("Done", h.1)).foregroundStyle(DS.Palette.calm.gradient)
                }
                .chartXAxis { AxisMarks(values: [6, 9, 12, 15, 18, 21]) { v in AxisValueLabel { if let h = v.as(Int.self) { Text(h == 12 ? "12p" : h > 12 ? "\(h - 12)p" : "\(h)a") } } } }
                .frame(height: 120)
                if let best = byHour.max(by: { $0.value < $1.value })?.key, doneInRange.count >= 10 {
                    Text("Your most productive hour is around \(best == 12 ? "noon" : best > 12 ? "\(best - 12) PM" : "\(best) AM"). Protect it for hard tasks.")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
            }
            Section("By list") {
                let byList = Dictionary(grouping: doneInRange, by: \.listName).mapValues(\.count).sorted { $0.value > $1.value }
                ForEach(byList.prefix(8), id: \.key) { LabeledContent($0.key, value: "\($0.value)") }
            }
            Section {
                let timed = tasks.filter { ($0.actualMinutes ?? 0) > 0 && ($0.estimatedMinutes ?? 0) > 0 }
                if timed.count >= 3 {
                    let ratio = Double(timed.reduce(0) { $0 + $1.actualMinutes! }) / Double(timed.reduce(0) { $0 + $1.estimatedMinutes! })
                    LabeledContent("Tasks take", value: String(format: "%.1f× your estimate", ratio))
                    Text(ratio > 1.2 ? "Normal for most brains. Keel already pads your plans by this much." : "Your estimates are spot on.")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                } else {
                    Text("Time a few tasks with the stopwatch to see how your estimates compare.").foregroundStyle(DS.Palette.inkSoft)
                }
                LabeledContent("Open tasks", value: "\(tasks.filter { !$0.isDone }.count)")
                LabeledContent("Overdue", value: "\(tasks.filter { !$0.isDone && ($0.dueDate ?? .distantFuture) < cal.startOfDay(for: Date()) }.count)")
            } header: { Text("Estimates") }
        }
        .navigationTitle("Statistics")
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(DS.Font.headline).monospacedDigit()
            Text(l).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
        }.frame(maxWidth: .infinity)
    }
}

/// The week at a glance: drag tasks onto days and see each day's load against its free time.
struct WeekPlannerView: View {
    @Query private var tasks: [TaskItem]
    @State private var weekOffset = 0

    private let cal = Calendar.current
    private var days: [Date] {
        let start = cal.date(byAdding: .day, value: weekOffset * 7, to: cal.startOfDay(for: Date()))!
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: start)! }
    }
    private var open: [TaskItem] { tasks.filter { !$0.isDone && !$0.isSomeday } }
    private var unplanned: [TaskItem] {
        let today = cal.startOfDay(for: Date())
        return open.filter { $0.dueDate == nil || $0.dueDate! < today }.sorted { $0.priority.rawValue > $1.priority.rawValue }
    }
    private func tasks(on day: Date) -> [TaskItem] { open.filter { $0.dueDate.map { cal.isDate($0, inSameDayAs: day) } ?? false } }

    /// Free minutes on a day between 9 and 6, from the calendar.
    private func freeMinutes(_ day: Date) -> Int {
        let from = cal.isDateInToday(day) ? Date() : cal.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
        return Int(CalendarService.shared.freeSlots(minMinutes: 15, from: from, until: 18).reduce(0) { $0 + $1.duration } / 60)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                if !unplanned.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("UNPLANNED · drag onto a day").font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack { ForEach(unplanned.prefix(30)) { t in pill(t) } }
                        }
                    }
                }
                ForEach(days, id: \.self) { day in dayCard(day) }
            }
            .padding()
        }
        .navigationTitle(weekOffset == 0 ? "Next 7 Days" : "Following Week")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { withAnimation { weekOffset = weekOffset == 0 ? 1 : 0 } } label: {
                    Image(systemName: weekOffset == 0 ? "chevron.right" : "chevron.left")
                }
                .accessibilityLabel(weekOffset == 0 ? "Following week" : "This week")
            }
        }
    }

    private func dayCard(_ day: Date) -> some View {
        let items = tasks(on: day)
        let load = items.reduce(0) { $0 + ADHDCoach.calibratedMinutes($1) }
        let free = freeMinutes(day)
        let over = load > free
        return GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(cal.isDateInToday(day) ? "Today" : cal.isDateInTomorrow(day) ? "Tomorrow" : day.formatted(.dateTime.weekday(.wide).month().day()))
                        .font(DS.Font.headline)
                    Spacer()
                    Text("\(load / 60)h\(load % 60 > 0 ? " \(load % 60)m" : "") / \(free / 60)h free")
                        .font(DS.Font.caption).foregroundStyle(over ? DS.Palette.warmth : DS.Palette.inkSoft)
                }
                ProgressView(value: min(Double(load) / Double(max(free, 1)), 1)).tint(over ? DS.Palette.warmth : DS.Palette.calm)
                if items.isEmpty { Text("Drop tasks here").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft) }
                FlowRow(items: items) { pill($0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .dropDestination(for: String.self) { ids, _ in
            for id in ids {
                if let t = open.first(where: { $0.id.uuidString == id }) { TaskActions.reschedule(t, to: day) }
            }
            Haptics.success()
            return true
        }
    }

    private func pill(_ t: TaskItem) -> some View {
        Text(t.title).font(DS.Font.caption).lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(t.priority.color.opacity(0.15), in: Capsule())
            .draggable(t.id.uuidString) { Text(t.title).padding(8).background(.regularMaterial, in: Capsule()) }
            .contextMenu {
                ForEach(days, id: \.self) { d in
                    Button(d.formatted(.dateTime.weekday(.wide))) { TaskActions.reschedule(t, to: d) }
                }
                Button("No date") { t.dueDate = nil; t.updatedAt = Date(); try? CalendarService.shared.push(t) }
            }
    }
}

/// Simple wrapping row of pills.
struct FlowRow<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content
    var body: some View {
        FlowLayout(spacing: 6) { ForEach(items) { content($0) } }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}
