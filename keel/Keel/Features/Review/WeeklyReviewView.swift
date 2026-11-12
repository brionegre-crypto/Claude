import SwiftUI
import SwiftData
import Charts
import UserNotifications

/// Ali Abdaal-style weekly review: what got done, where the time and energy went,
/// progress on goals, a short reflection, and next week's top three. Saved as a note.
struct WeeklyReviewView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var tasks: [TaskItem]
    @Query private var sessions: [FocusSession]
    @Query private var habitLogs: [HabitLog]
    @Query private var promises: [Commitment]
    @Query(filter: #Predicate<Goal> { !$0.isArchived }) private var goals: [Goal]
    @Query(sort: \CheckIn.day) private var checkIns: [CheckIn]

    @State private var wentWell = ""
    @State private var didnt = ""
    @State private var learned = ""
    @State private var top3 = ["", "", ""]
    @State private var saved = false

    private let cal = Calendar.current
    private var start: Date { cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date()))! }
    private var days: [Date] { (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) } }
    private func inWeek(_ d: Date?) -> Bool { d.map { $0 >= start } ?? false }

    private var completed: [TaskItem] {
        tasks.filter { inWeek($0.completedAt) || inWeek($0.lastCompletedOccurrence) }
    }
    private var focusMinutes: Int {
        sessions.filter { inWeek($0.endedAt) }.reduce(0) { $0 + Int(($1.endedAt ?? $1.startedAt).timeIntervalSince($1.startedAt) / 60) }
    }
    private var habitCount: Int { habitLogs.filter { inWeek($0.day) }.count }
    private var keptPromises: Int { promises.filter { $0.status == .done && inWeek($0.completedAt) }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                Text("\(start.formatted(.dateTime.month(.abbreviated).day())) – \(Date().formatted(.dateTime.month(.abbreviated).day()))")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).textCase(.uppercase)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Space.s) {
                    stat("\(completed.count)", "tasks done", "checkmark.circle.fill", DS.Palette.calm)
                    stat(hours(focusMinutes), "focused", "moon.zzz.fill", DS.Palette.focus)
                    stat("\(habitCount)", "habit check-ins", "link", .purple)
                    stat("\(keptPromises)", "promises kept", "hand.raised.fill", .pink)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text("Your week").font(DS.Font.headline)
                        Chart {
                            ForEach(days, id: \.self) { d in
                                BarMark(x: .value("Day", d, unit: .day), y: .value("Focus minutes", focusMinutes(on: d)))
                                    .foregroundStyle(DS.Palette.focus.gradient)
                                    .cornerRadius(4)
                            }
                            ForEach(days, id: \.self) { d in
                                LineMark(x: .value("Day", d, unit: .day), y: .value("Tasks done", tasksDone(on: d) * 10))
                                    .foregroundStyle(DS.Palette.calm)
                                    .symbol(.circle)
                            }
                        }
                        .chartXAxis { AxisMarks(values: .stride(by: .day)) { AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                        .chartYAxis(.hidden)
                        .frame(height: 140)
                        HStack(spacing: DS.Space.m) {
                            Label("Focus minutes", systemImage: "square.fill").foregroundStyle(DS.Palette.focus)
                            Label("Tasks done", systemImage: "circle.fill").foregroundStyle(DS.Palette.calm)
                        }
                        .font(.caption2)
                    }
                }

                moodSection
                energySection
                goalsSection
                reflection
                saveButton
            }
            .padding()
        }
        .navigationTitle("Weekly review")
    }

    private func stat(_ value: String, _ label: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).font(DS.Font.title).contentTransition(.numericText())
            Text(label).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.m)
        .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.card))
    }

    private func hours(_ minutes: Int) -> String { minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m" }

    private func focusMinutes(on day: Date) -> Int {
        sessions.filter { $0.endedAt.map { cal.isDate($0, inSameDayAs: day) } == true }
            .reduce(0) { $0 + Int(($1.endedAt ?? $1.startedAt).timeIntervalSince($1.startedAt) / 60) }
    }

    private func tasksDone(on day: Date) -> Int {
        tasks.filter { t in
            (t.completedAt.map { cal.isDate($0, inSameDayAs: day) } ?? false) ||
            (t.lastCompletedOccurrence.map { cal.isDate($0, inSameDayAs: day) } ?? false)
        }.count
    }

    private var moodSection: some View {
        let week = checkIns.filter { $0.day >= start }
        return Group {
            if !week.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    SectionHeader(title: "Mood", trailing: "\(week.count) check-ins")
                    Chart(week) { c in
                        LineMark(x: .value("Day", c.day, unit: .day), y: .value("Mood", c.mood))
                            .interpolationMethod(.catmullRom).foregroundStyle(.pink)
                        PointMark(x: .value("Day", c.day, unit: .day), y: .value("Mood", c.mood)).foregroundStyle(.pink)
                    }
                    .chartYScale(domain: 1...5)
                    .chartYAxis { AxisMarks(values: [1, 3, 5]) { v in AxisValueLabel { Text(CheckIn.faces[(v.as(Int.self) ?? 3) - 1]) } } }
                    .frame(height: 110)
                    let highlights = week.map(\.highlight).filter { !$0.isEmpty }
                    if !highlights.isEmpty {
                        Text("Highlights: " + highlights.prefix(4).joined(separator: " · ")).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
            }
        }
    }

    // What energized vs drained you
    private var energySection: some View {
        let rated = completed.filter { $0.feeling != nil }
        let unrated = completed.filter { $0.feeling == nil }.prefix(6)
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            SectionHeader(title: "Energy", trailing: "play · power · people")
            if !rated.isEmpty {
                HStack {
                    ForEach(TaskFeeling.allCases) { f in
                        let n = rated.filter { $0.feeling == f }.count
                        VStack { Text(f.emoji).font(.title2); Text("\(n)").font(DS.Font.headline) }.frame(maxWidth: .infinity)
                    }
                }
                let drainers = rated.filter { $0.feeling == .drained }.map(\.title)
                if !drainers.isEmpty {
                    Text("Drained you: \(drainers.prefix(3).joined(separator: ", ")). Could you batch, delegate, or pair them with something fun next week?")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
            }
            if !unrated.isEmpty {
                Text("How did these feel?").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                ForEach(Array(unrated)) { t in
                    HStack {
                        Text(t.title).font(DS.Font.body).lineLimit(1)
                        Spacer()
                        ForEach(TaskFeeling.allCases) { f in
                            Button(f.emoji) { t.feeling = f; Haptics.tap() }.buttonStyle(.plain)
                        }
                    }
                }
            }
            if rated.isEmpty && unrated.isEmpty {
                Text("Complete a few tasks and rate how they felt to see your energy pattern.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
        }
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            SectionHeader(title: "Goals")
            if goals.isEmpty {
                NavigationLink { GoalsView() } label: { Label("Set a few goals for the year", systemImage: "target") }
            }
            ForEach(goals) { g in
                let moved = completed.filter { $0.goalId == g.id }.count
                HStack {
                    Text("\(g.emoji) \(g.title)").font(DS.Font.body)
                    Spacer()
                    Text(moved == 0 ? "no progress" : "+\(moved) this week")
                        .font(DS.Font.caption).foregroundStyle(moved == 0 ? DS.Palette.warmth : DS.Palette.calm)
                }
            }
        }
    }

    private var reflection: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            SectionHeader(title: "Reflect")
            prompt("What went well?", $wentWell)
            prompt("What didn't go so well?", $didnt)
            prompt("What did I learn?", $learned)
            Text("Top 3 for next week").font(DS.Font.headline)
            ForEach(0..<3, id: \.self) { i in
                TextField("Priority \(i + 1)", text: $top3[i])
                    .padding(DS.Space.s)
                    .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.chip))
            }
        }
    }

    private func prompt(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            TextField("", text: text, axis: .vertical)
                .lineLimit(2...6)
                .padding(DS.Space.s)
                .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.chip))
        }
    }

    private var saveButton: some View {
        Button { save() } label: {
            Label(saved ? "Saved to Notes" : "Save review & plan next week", systemImage: saved ? "checkmark" : "square.and.arrow.down")
                .font(DS.Font.headline).frame(maxWidth: .infinity).padding(.vertical, DS.Space.m)
                .background(DS.Palette.accent, in: Capsule()).foregroundStyle(.white)
        }
        .disabled(saved)
    }

    private func save() {
        var blocks: [NoteBlock] = [
            .init(kind: .text, text: "\(completed.count) tasks · \(hours(focusMinutes)) focused · \(habitCount) habit check-ins · \(keptPromises) promises kept"),
        ]
        for (title, text) in [("What went well", wentWell), ("What didn't go so well", didnt), ("What I learned", learned)] where !text.isEmpty {
            blocks += [.init(kind: .heading, text: title), .init(kind: .text, text: text)]
        }
        let priorities = top3.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !priorities.isEmpty {
            blocks.append(.init(kind: .heading, text: "Top 3 for next week"))
            blocks += priorities.map { NoteBlock(kind: .todo, text: $0) }
        }
        let note = Note(title: "Weekly review · \(start.formatted(.dateTime.month(.abbreviated).day()))–\(Date().formatted(.dateTime.month(.abbreviated).day()))", blocks: blocks)
        ctx.insert(note)

        // Next week's priorities become high-priority tasks for Monday morning.
        let monday = cal.nextDate(after: Date(), matching: DateComponents(hour: 9, weekday: 2), matchingPolicy: .nextTime) ?? Date()
        for p in priorities {
            let t = TaskItem(title: p, dueDate: monday, priority: .high)
            t.tags = ["weekly"]
            t.alertOffsetMinutes = 0
            ctx.insert(t)
            try? CalendarService.shared.push(t)
            TaskAlerts.schedule(t)
        }
        UserDefaults.standard.set(Date(), forKey: "review.last")
        withAnimation(DS.spring) { saved = true }
        Haptics.milestone()
    }
}

enum WeeklyReview {
    /// A gentle Sunday 5pm nudge, every week.
    static func scheduleReminder() {
        let c = UNMutableNotificationContent()
        c.title = "Weekly review"
        c.body = "10 minutes to look back, notice what gave you energy, and pick next week's top 3."
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "weekly.review", content: c,
            trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 17, weekday: 1), repeats: true)))
    }

    /// Show the Today card on Friday–Sunday if this week's review isn't done yet.
    static var isDue: Bool {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: Date())
        guard [1, 6, 7].contains(weekday) else { return false }
        guard let last = UserDefaults.standard.object(forKey: "review.last") as? Date else { return true }
        return Date().timeIntervalSince(last) > 3 * 86_400
    }
}

/// Focus stats strip for the Focus screen.
struct FocusStatsStrip: View {
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var sessions: [FocusSession]

    var body: some View {
        let cal = Calendar.current
        let weekStart = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date()))!
        let week = sessions.filter { ($0.endedAt ?? .distantPast) >= weekStart }
        let minutes = week.reduce(0) { $0 + Int(($1.endedAt ?? $1.startedAt).timeIntervalSince($1.startedAt) / 60) }
        let streak = streakDays(cal)
        HStack(spacing: DS.Space.l) {
            VStack(alignment: .leading) {
                Text(minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m").font(DS.Font.headline)
                Text("this week").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            VStack(alignment: .leading) {
                Text("\(week.count)").font(DS.Font.headline)
                Text("sessions").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            VStack(alignment: .leading) {
                Text("\(streak) 🔥").font(DS.Font.headline)
                Text("day streak").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Space.m)
        .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.card))
    }

    private func streakDays(_ cal: Calendar) -> Int {
        let focusedDays = Set(sessions.compactMap { $0.endedAt.map { cal.startOfDay(for: $0) } })
        var day = cal.startOfDay(for: Date())
        if !focusedDays.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var n = 0
        while focusedDays.contains(day) { n += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }
        return n
    }
}
