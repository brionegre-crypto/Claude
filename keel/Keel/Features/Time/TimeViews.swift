import SwiftUI
import SwiftData
import Charts
import EventKit

// Time tracking, time audit (where your hours actually went vs. your ideal week), and the ideal week itself.

// MARK: - Tracker

@MainActor
enum TimeTracker {
    static func running(_ ctx: ModelContext) -> TimeEntry? {
        ((try? ctx.fetch(FetchDescriptor<TimeEntry>())) ?? []).first { $0.end == nil }
    }

    static func start(_ title: String, area: LifeArea, ctx: ModelContext) {
        stop(ctx)
        ctx.insert(TimeEntry(title: title, area: area))
        Haptics.tap()
    }

    static func stop(_ ctx: ModelContext) {
        if let r = running(ctx) { r.end = Date(); Haptics.success() }
    }

    /// Guesses a life area for a calendar event from its title and calendar.
    static func area(for event: EKEvent) -> LifeArea {
        let t = ((event.title ?? "") + " " + event.calendar.title).lowercased()
        let rules: [(LifeArea, [String])] = [
            (.health, ["gym", "run", "workout", "yoga", "doctor", "dentist", "therapy", "walk", "sleep", "meds"]),
            (.relationships, ["family", "dinner", "date", "mom", "dad", "kids", "friend", "birthday", "wedding", "prayer", "church"]),
            (.wealth, ["budget", "finance", "invest", "tax", "bank", "bills"]),
            (.growth, ["read", "course", "learn", "study", "journal", "class"]),
            (.fun, ["game", "movie", "concert", "trip", "vacation", "party", "hobby"]),
        ]
        return rules.first { $0.1.contains(where: t.contains) }?.0 ?? .work
    }
}

/// Today card / Time audit header: the running timer, or quick-start buttons.
struct TimerCard: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<TimeEntry> { $0.end == nil }) private var running: [TimeEntry]
    @State private var title = ""
    @State private var area: LifeArea = .work

    var body: some View {
        GlassCard {
            if let r = running.first {
                HStack {
                    Image(systemName: r.area.icon).foregroundStyle(DS.Palette.accent)
                    VStack(alignment: .leading) {
                        Text(r.title).font(DS.Font.headline)
                        Text(r.area.title).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                    Spacer()
                    Text(r.start, style: .timer).font(DS.Font.headline.monospacedDigit())
                    Button { TimeTracker.stop(ctx) } label: { Image(systemName: "stop.circle.fill").font(.title) }
                        .tint(.red).accessibilityLabel("Stop timer")
                }
            } else {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    HStack {
                        TextField("What are you working on?", text: $title)
                        Button { TimeTracker.start(title.isEmpty ? area.title : title, area: area, ctx: ctx); title = "" } label: {
                            Image(systemName: "play.circle.fill").font(.title)
                        }
                        .accessibilityLabel("Start timer")
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(LifeArea.allCases) { a in
                                Button { area = a } label: { Chip(text: a.title, color: area == a ? DS.Palette.accent : .gray, icon: a.icon) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Time audit

struct TimeAuditView: View {
    @Query(sort: \TimeEntry.start, order: .reverse) private var entries: [TimeEntry]
    @Query private var sessions: [FocusSession]
    @Query private var ideal: [IdealBlock]
    @State private var weekOffset = 0

    private let cal = Calendar.current
    private var weekStart: Date {
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return cal.date(byAdding: .weekOfYear, value: weekOffset, to: thisWeek) ?? thisWeek
    }
    private var weekEnd: Date { cal.date(byAdding: .day, value: 7, to: weekStart)! }

    /// Minutes per area this week: tracked time + focus sessions + calendar events.
    private var actual: [LifeArea: Int] {
        var m: [LifeArea: Int] = [:]
        for e in entries where e.start >= weekStart && e.start < weekEnd { m[e.area, default: 0] += e.minutes }
        for s in sessions where s.startedAt >= weekStart && s.startedAt < weekEnd {
            m[.work, default: 0] += Int(((s.endedAt ?? s.startedAt).timeIntervalSince(s.startedAt)) / 60)
        }
        for ev in CalendarService.shared.events(from: weekStart, to: min(weekEnd, Date())) where !ev.isAllDay {
            m[TimeTracker.area(for: ev), default: 0] += Int(ev.endDate.timeIntervalSince(ev.startDate) / 60)
        }
        return m
    }

    private var planned: [LifeArea: Int] {
        var m: [LifeArea: Int] = [:]
        for b in ideal { m[b.area, default: 0] += b.minutes * b.weekdays.count }
        return m
    }

    var body: some View {
        let actual = actual
        let planned = planned
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                TimerCard()

                HStack {
                    Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(weekOffset == 0 ? "This week" : weekOffset == -1 ? "Last week" : weekStart.formatted(.dateTime.month().day()))
                        .font(DS.Font.headline)
                    Spacer()
                    Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }.disabled(weekOffset >= 0)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text("Where your time went").font(DS.Font.headline)
                        Chart {
                            ForEach(LifeArea.allCases) { a in
                                BarMark(x: .value("Hours", Double(actual[a] ?? 0) / 60), y: .value("Area", a.title))
                                    .foregroundStyle(by: .value("Type", "Actual"))
                                    .position(by: .value("Type", "Actual"))
                                if !planned.isEmpty {
                                    BarMark(x: .value("Hours", Double(planned[a] ?? 0) / 60), y: .value("Area", a.title))
                                        .foregroundStyle(by: .value("Type", "Ideal"))
                                        .position(by: .value("Type", "Ideal"))
                                }
                            }
                        }
                        .chartForegroundStyleScale(["Actual": DS.Palette.accent, "Ideal": DS.Palette.inkSoft.opacity(0.35)])
                        .frame(height: 260)
                    }
                }

                insights(actual: actual, planned: planned)

                NavigationLink { IdealWeekView() } label: {
                    Label(ideal.isEmpty ? "Design your ideal week" : "Edit your ideal week", systemImage: "calendar.badge.clock")
                        .frame(maxWidth: .infinity).padding(.vertical, DS.Space.m)
                        .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.card))
                }

                let week = entries.filter { $0.start >= weekStart && $0.start < weekEnd }
                if !week.isEmpty {
                    SectionHeader(title: "Tracked")
                    ForEach(week) { e in
                        HStack {
                            Image(systemName: e.area.icon).foregroundStyle(DS.Palette.inkSoft).frame(width: 22)
                            Text(e.title)
                            Spacer()
                            Text("\(e.minutes / 60)h \(e.minutes % 60)m").foregroundStyle(DS.Palette.inkSoft).monospacedDigit()
                        }
                        .font(DS.Font.body)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Time Audit")
    }

    @ViewBuilder
    private func insights(actual: [LifeArea: Int], planned: [LifeArea: Int]) -> some View {
        let gaps = LifeArea.allCases.compactMap { a -> (LifeArea, Int)? in
            guard let p = planned[a], p > 0 else { return nil }
            return (a, (actual[a] ?? 0) - p)
        }
        .sorted { abs($0.1) > abs($1.1) }
        if let biggest = gaps.first, abs(biggest.1) >= 60 {
            GlassCard(tint: biggest.1 < 0 ? DS.Palette.warmth : DS.Palette.calm) {
                Text(biggest.1 < 0
                     ? "You planned \(abs(biggest.1) / 60)h more \(biggest.0.title.lowercased()) than you got. What could make room for it next week?"
                     : "You spent \(biggest.1 / 60)h more on \(biggest.0.title.lowercased()) than planned. Intentional, or did it creep in?")
                    .font(DS.Font.body)
            }
        } else if planned.isEmpty {
            Text("Design your ideal week to compare it with what really happened.")
                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
        }
    }
}

// MARK: - Ideal week

struct IdealWeekView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \IdealBlock.startMinute) private var blocks: [IdealBlock]
    @State private var editing: IdealBlock?
    @State private var showNew = false
    @State private var applied = false

    private let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        List {
            Section {
                Text("Sketch the week you'd love to have: deep work, workouts, family time, rest. Keel uses it when planning your days, and the time audit compares it with reality.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            ForEach(weekdayOrder, id: \.self) { d in
                let dayBlocks = blocks.filter { $0.weekdays.contains(d) }
                if !dayBlocks.isEmpty {
                    Section(Calendar.current.weekdaySymbols[d - 1]) {
                        ForEach(dayBlocks) { b in
                            Button { editing = b } label: {
                                HStack {
                                    Image(systemName: b.area.icon).foregroundStyle(DS.Palette.accent).frame(width: 22)
                                    Text(b.title).foregroundStyle(DS.Palette.ink)
                                    Spacer()
                                    Text(b.timeLabel).foregroundStyle(DS.Palette.inkSoft).monospacedDigit()
                                }
                            }
                        }
                    }
                }
            }
            if blocks.isEmpty {
                Section {
                    Button("Start from a template") { seedTemplate() }
                }
            } else {
                Section {
                    Button(applied ? "Added to your calendar" : "Block this week on my calendar") { applyToCalendar() }
                        .disabled(applied)
                } footer: { Text("Adds the rest of this week's blocks to the Keel calendar. You can move or delete them like any event.") }
            }
        }
        .navigationTitle("Ideal Week")
        .toolbar { Button { showNew = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showNew) { IdealBlockEditor(block: nil) }
        .sheet(item: $editing) { IdealBlockEditor(block: $0) }
    }

    private func seedTemplate() {
        let weekdays = [2, 3, 4, 5, 6]
        let template: [(String, LifeArea, [Int], Int, Int)] = [
            ("Deep work", .work, weekdays, 9 * 60, 11 * 60 + 30),
            ("Email & admin", .work, weekdays, 13 * 60, 14 * 60),
            ("Workout", .health, [2, 4, 6], 7 * 60, 8 * 60),
            ("Family dinner", .relationships, [1, 2, 3, 4, 5, 6, 7], 18 * 60 + 30, 19 * 60 + 30),
            ("Reading", .growth, [1, 3, 5], 21 * 60, 21 * 60 + 30),
            ("Weekly review", .growth, [1], 17 * 60, 17 * 60 + 30),
            ("Play", .fun, [7], 10 * 60, 13 * 60),
        ]
        for t in template { ctx.insert(IdealBlock(title: t.0, area: t.1, weekdays: t.2, startMinute: t.3, endMinute: t.4)) }
    }

    private func applyToCalendar() {
        let cal = Calendar.current
        let svc = CalendarService.shared
        guard let keelCal = try? svc.keelCalendar() else { return }
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: Date())) else { continue }
            let wd = cal.component(.weekday, from: day)
            for b in blocks where b.weekdays.contains(wd) {
                guard let start = cal.date(byAdding: .minute, value: b.startMinute, to: day), start > Date() else { continue }
                let e = EKEvent(eventStore: svc.store)
                e.calendar = keelCal
                e.title = b.title
                e.startDate = start
                e.endDate = start.addingTimeInterval(Double(b.minutes * 60))
                try? svc.store.save(e, span: .thisEvent, commit: false)
            }
        }
        try? svc.store.commit()
        applied = true
        Haptics.success()
    }
}

struct IdealBlockEditor: View {
    let block: IdealBlock?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var area: LifeArea = .work
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
    @State private var end = Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: Date())!

    var body: some View {
        NavigationStack {
            Form {
                TextField("e.g. Deep work", text: $title)
                Picker("Life area", selection: $area) { ForEach(LifeArea.allCases) { Label($0.title, systemImage: $0.icon).tag($0) } }
                DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
                Section("Days") {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { d in
                        Toggle(Calendar.current.weekdaySymbols[d - 1], isOn: Binding(
                            get: { weekdays.contains(d) },
                            set: { if $0 { weekdays.insert(d) } else { weekdays.remove(d) } }))
                    }
                }
                if let block {
                    Section { Button("Delete Block", role: .destructive) { ctx.delete(block); dismiss() } }
                }
            }
            .navigationTitle(block == nil ? "New Block" : "Edit Block")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(title.isEmpty || weekdays.isEmpty) }
            }
            .onAppear(perform: load)
        }
    }

    private func minutes(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func load() {
        guard let b = block else { return }
        title = b.title; area = b.area; weekdays = Set(b.weekdays)
        let today = Calendar.current.startOfDay(for: Date())
        start = today.addingTimeInterval(Double(b.startMinute * 60))
        end = today.addingTimeInterval(Double(b.endMinute * 60))
    }

    private func save() {
        let s = minutes(start), e = max(minutes(end), minutes(start) + 15)
        if let b = block {
            b.title = title; b.area = area; b.weekdays = weekdays.sorted(); b.startMinute = s; b.endMinute = e
        } else {
            ctx.insert(IdealBlock(title: title, area: area, weekdays: weekdays.sorted(), startMinute: s, endMinute: e))
        }
        Haptics.success()
        dismiss()
    }
}
