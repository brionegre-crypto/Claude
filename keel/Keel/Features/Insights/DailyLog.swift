import SwiftUI
import SwiftData
import EventKit

/// The daily log: everything you did today, in one timeline that sits with your journal.
/// Some of it Keel already knows (tasks finished, focus, meds, habits, meetings, check-in, journal);
/// the rest is logged as it happens (breathing on iPhone or Apple Watch, routines, things you faced).
struct LogEvent: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case breathe, routine, dread, note }
    var id = UUID()
    var date: Date
    var kind: Kind
    var title: String
    var detail: String = ""
    var source: String = "iPhone"         // "iPhone" or "Apple Watch"
}

@MainActor
enum DailyLog {
    static let key = "dailylog.v1"
    static let keepDays = 120

    static var events: [LogEvent] {
        get {
            guard let d = UserDefaults.standard.data(forKey: key), let e = try? JSONDecoder().decode([LogEvent].self, from: d) else { return [] }
            return e
        }
        set {
            let cutoff = Date().addingTimeInterval(-Double(keepDays) * 86_400)
            if let d = try? JSONEncoder().encode(newValue.filter { $0.date > cutoff }) { UserDefaults.standard.set(d, forKey: key) }
        }
    }

    static func add(_ e: LogEvent) {
        var all = events
        // The same session can arrive twice from the watch (message, then queued transfer): keep one.
        guard !all.contains(where: { $0.kind == e.kind && abs($0.date.timeIntervalSince(e.date)) < 5 && $0.title == e.title }) else { return }
        all.append(e)
        events = all
    }

    static func logBreath(seconds: Int, at date: Date = Date(), source: String = "iPhone") {
        guard seconds >= 20 else { return }
        let mins = max(1, Int((Double(seconds) / 60).rounded()))
        add(LogEvent(date: date, kind: .breathe, title: "Breathed for \(mins) min", detail: "Box breathing", source: source))
    }

    static func logRoutine(_ name: String, steps: Int, minutes: Int, at date: Date = Date(), source: String = "iPhone") {
        add(LogEvent(date: date, kind: .routine, title: "Finished \(name)", detail: "\(steps) steps · \(minutes) min", source: source))
    }

    // MARK: The day's timeline

    struct Entry: Identifiable {
        let id: String
        let time: Date
        let icon: String
        let color: Color
        let title: String
        let detail: String
    }

    static func entries(for day: Date, ctx: ModelContext) -> [Entry] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        func inDay(_ d: Date?) -> Bool { d.map { $0 >= start && $0 < end } ?? false }
        var out: [Entry] = []

        for e in events where inDay(e.date) {
            let (icon, color): (String, Color) = switch e.kind {
            case .breathe: ("wind", .mint)
            case .routine: ("list.number", .orange)
            case .dread: ("tortoise.fill", DS.Palette.warmth)
            case .note: ("pencil", DS.Palette.accent)
            }
            out.append(Entry(id: e.id.uuidString, time: e.date, icon: icon, color: color, title: e.title,
                             detail: [e.detail, e.source == "Apple Watch" ? "on Apple Watch" : ""].filter { !$0.isEmpty }.joined(separator: " · ")))
        }

        let tasks = (try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []
        for t in tasks {
            if inDay(t.completedAt) {
                out.append(Entry(id: "t\(t.id)", time: t.completedAt!, icon: "checkmark.circle.fill", color: DS.Palette.calm, title: "Done: \(t.title)", detail: ""))
            } else if inDay(t.lastCompletedOccurrence) {
                out.append(Entry(id: "r\(t.id)", time: t.lastCompletedOccurrence!, icon: "checkmark.circle.fill", color: DS.Palette.calm, title: "Done: \(t.title)", detail: "Repeating"))
            }
        }

        let sessions = ((try? ctx.fetch(FetchDescriptor<FocusSession>())) ?? []).filter { inDay($0.startedAt) && $0.endedAt != nil }
        for s in sessions {
            let mins = Int(((s.endedAt ?? s.startedAt).timeIntervalSince(s.startedAt)) / 60)
            guard mins >= 1 else { continue }
            let task = s.taskId.flatMap { id in tasks.first { $0.id == id }?.title }
            out.append(Entry(id: "f\(s.id)", time: s.startedAt, icon: "moon.zzz.fill", color: DS.Palette.focus,
                             title: "Focused \(mins) min", detail: [task, s.brokeEarly ? "ended early" : nil].compactMap { $0 }.joined(separator: " · ")))
        }

        let meds = (try? ctx.fetch(FetchDescriptor<Medication>())) ?? []
        for d in ((try? ctx.fetch(FetchDescriptor<MedDose>())) ?? []) where inDay(d.takenAt) {
            let m = meds.first { $0.id == d.medicationId }
            out.append(Entry(id: "m\(d.id)", time: d.takenAt, icon: "pills.fill", color: .mint, title: "Took \(m?.name ?? "medication")", detail: m?.dose ?? ""))
        }

        let habits = (try? ctx.fetch(FetchDescriptor<Habit>())) ?? []
        for l in ((try? ctx.fetch(FetchDescriptor<HabitLog>())) ?? []) where inDay(l.completedAt) {
            let h = habits.first { $0.id == l.habitId }
            out.append(Entry(id: "h\(l.habitId)\(l.completedAt.timeIntervalSince1970)", time: l.completedAt, icon: h?.icon ?? "link", color: .purple,
                             title: h?.name ?? "Habit", detail: "Habit"))
        }

        for e in CalendarService.shared.events(from: start, to: min(end, Date())) where !e.isAllDay && e.endDate <= Date() && e.attendees?.isEmpty == false {
            out.append(Entry(id: "e\(e.eventIdentifier ?? UUID().uuidString)", time: e.startDate, icon: "person.2.fill", color: DS.Palette.meeting,
                             title: e.title ?? "Meeting", detail: "\(Int(e.endDate.timeIntervalSince(e.startDate) / 60)) min meeting"))
        }

        let food = (try? ctx.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.date >= start && $0.date < end }))) ?? []
        for f in food {
            let protein = f.facts.protein.map { "\(Int($0)) g protein" }
            out.append(Entry(id: "n\(f.id)", time: f.date, icon: "fork.knife", color: f.verdict.color,
                             title: "\(f.verdict.emoji) \(f.name)", detail: [f.meal.capitalized, protein].compactMap { $0 }.joined(separator: " · ")))
        }

        if let c = ((try? ctx.fetch(FetchDescriptor<CheckIn>())) ?? []).first(where: { cal.isDate($0.day, inSameDayAs: start) }) {
            out.append(Entry(id: "c\(c.id)", time: c.createdAt, icon: "face.smiling", color: .pink,
                             title: "Checked in \(CheckIn.faces[max(0, min(4, c.mood - 1))])",
                             detail: c.highlight.isEmpty ? "" : "Good thing: \(c.highlight)"))
        }
        return out.sorted { $0.time < $1.time }
    }

    /// "Breathed twice · 3 focus sessions · 5 tasks done", for the journal list.
    static func summary(for day: Date, ctx: ModelContext) -> String {
        let e = entries(for: day, ctx: ctx)
        func n(_ prefix: String) -> Int { e.filter { $0.id.hasPrefix(prefix) }.count }
        let breaths = e.filter { $0.icon == "wind" }.count
        var parts: [String] = []
        if breaths > 0 { parts.append(breaths == 1 ? "Breathed once" : "Breathed \(breaths)×") }
        let focus = n("f"); if focus > 0 { parts.append("\(focus) focus session\(focus == 1 ? "" : "s")") }
        let done = n("t") + n("r"); if done > 0 { parts.append("\(done) done") }
        let routines = e.filter { $0.icon == "list.number" }.count; if routines > 0 { parts.append("\(routines) routine\(routines == 1 ? "" : "s")") }
        let meds = n("m"); if meds > 0 { parts.append("meds ✓") }
        return parts.joined(separator: " · ")
    }
}

/// One day, as it happened, next to your journal for that day.
struct DayLogView: View {
    @Environment(\.modelContext) private var ctx
    @State var day: Date = Date()
    @Query(sort: \CheckIn.day, order: .reverse) private var checkIns: [CheckIn]
    @State private var writing = false
    @State private var breathing = false
    @State private var noteText = ""
    @State private var tick = 0

    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var checkIn: CheckIn? { checkIns.first { Calendar.current.isDate($0.day, inSameDayAs: day) } }

    private var entries: [DailyLog.Entry] {
        _ = tick
        return DailyLog.entries(for: day, ctx: ctx)
    }

    var body: some View {
        let entries = self.entries
        List {
            Section {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous day")
                    Spacer()
                    VStack(spacing: 2) {
                        Text(isToday ? "Today" : day.formatted(.dateTime.weekday(.wide))).font(DS.Font.headline)
                        Text(day.formatted(date: .long, time: .omitted)).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }.disabled(isToday).accessibilityLabel("Next day")
                }
                .buttonStyle(.borderless)
            }

            Section("Journal") {
                if let c = checkIn, !c.journal.isEmpty {
                    if !c.prompt.isEmpty { Text(c.prompt).font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft) }
                    Text(c.journal).font(DS.Font.body)
                } else if isToday {
                    Button { writing = true } label: { Label("Write today's one-minute journal", systemImage: "square.and.pencil") }
                } else {
                    Text("No journal entry this day.").foregroundStyle(DS.Palette.inkSoft)
                }
                if isToday, let c = checkIn, !c.journal.isEmpty {
                    Button("Edit") { writing = true }.font(DS.Font.caption)
                }
            }

            Section {
                if entries.isEmpty {
                    Text(isToday ? "Nothing logged yet. Things you do in Keel or on your watch appear here." : "Nothing logged this day.")
                        .foregroundStyle(DS.Palette.inkSoft)
                }
                ForEach(entries) { e in
                    HStack(alignment: .top, spacing: DS.Space.m) {
                        Text(e.time.formatted(date: .omitted, time: .shortened)).font(DS.Font.caption.monospacedDigit())
                            .foregroundStyle(DS.Palette.inkSoft).frame(width: 64, alignment: .leading)
                        Image(systemName: e.icon).foregroundStyle(e.color).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title).font(DS.Font.body)
                            if !e.detail.isEmpty { Text(e.detail).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft) }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                if isToday {
                    HStack {
                        TextField("Add to today's log…", text: $noteText).onSubmit(addNote)
                        Button("Add", action: addNote).disabled(noteText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } header: { Text("Log") } footer: {
                Text("Breathing from iPhone or Apple Watch, focus, tasks, meds, habits, routines, meetings and your check-in, all in one place.")
            }
        }
        .navigationTitle("Daily Log")
        .toolbar {
            if isToday {
                Button { breathing = true } label: { Label("Breathe", systemImage: "wind") }
            }
        }
        .sheet(isPresented: $writing, onDismiss: { tick += 1 }) { JournalEntryView() }
        .sheet(isPresented: $breathing, onDismiss: { tick += 1 }) { BreatheView() }
    }

    private func shift(_ days: Int) {
        if let d = Calendar.current.date(byAdding: .day, value: days, to: day), d <= Date() { withAnimation { day = d } }
    }

    private func addNote() {
        let t = noteText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        DailyLog.add(LogEvent(date: Date(), kind: .note, title: t))
        noteText = ""; tick += 1
        Haptics.tap()
    }
}

/// Box breathing on iPhone. Every session goes into today's log.
struct BreatheView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expanded = false
    @State private var phase = "Ready"
    @State private var round = 0
    @State private var rounds = 4
    @State private var running = false
    @State private var startedAt: Date?
    @State private var logged = false

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.xl) {
                Spacer()
                ZStack {
                    Circle().fill(Color.mint.opacity(0.15)).frame(width: 260, height: 260)
                    Circle().fill(Color.mint.opacity(0.55).gradient)
                        .frame(width: expanded ? 250 : 100, height: expanded ? 250 : 100)
                    Text(phase).font(DS.Font.title).foregroundStyle(DS.Palette.ink)
                }
                .accessibilityElement().accessibilityLabel(phase)
                Text(round > 0 ? "Round \(round) of \(rounds)" : "In 4 · hold 4 · out 4 · hold 4")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                if !running {
                    Picker("Length", selection: $rounds) {
                        Text("1 min").tag(4); Text("2 min").tag(8); Text("4 min").tag(16)
                    }
                    .pickerStyle(.segmented).frame(maxWidth: 260)
                    Button { running = true } label: {
                        Text(round > 0 ? "Again" : "Start").font(DS.Font.headline).frame(width: 200).padding(.vertical, DS.Space.m)
                            .background(Color.mint, in: Capsule()).foregroundStyle(.white)
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Breathe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { logSession(); dismiss() } } }
            .task(id: running) {
                guard running else { return }
                startedAt = Date(); logged = false
                for r in 1...rounds {
                    round = r
                    phase = "Breathe in"; Haptics.tap()
                    withAnimation(.easeInOut(duration: 4)) { expanded = true }
                    try? await Task.sleep(for: .seconds(4)); if Task.isCancelled { break }
                    phase = "Hold"
                    try? await Task.sleep(for: .seconds(4)); if Task.isCancelled { break }
                    phase = "Breathe out"; Haptics.tap()
                    withAnimation(.easeInOut(duration: 4)) { expanded = false }
                    try? await Task.sleep(for: .seconds(4)); if Task.isCancelled { break }
                    phase = "Hold"
                    try? await Task.sleep(for: .seconds(4)); if Task.isCancelled { break }
                }
                phase = "Well done"
                Haptics.success()
                logSession()
                running = false
            }
            .onDisappear { logSession() }
        }
    }

    private func logSession() {
        guard let s = startedAt, !logged else { return }
        logged = true
        DailyLog.logBreath(seconds: Int(Date().timeIntervalSince(s)), at: s)
    }
}
