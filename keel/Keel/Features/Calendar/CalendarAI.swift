import SwiftUI
import SwiftData
import EventKit

// MARK: - Turn loose tasks into a routine on your calendar
//
// "Water plants", "Dishes", "Take meds", "Take out trash" sitting in Tasks every day are really a routine.
// Keel spots them, groups them into a ready-made routine (Morning, Evening, Weekly reset), puts that routine
// on your calendar as one repeating block, and clears the loose tasks (with Undo).

struct RoutineSuggestion: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var icon: String
    var hour: Int
    var minute: Int
    var weekday: Int?                 // nil = every day; 1 = Sunday … 7 = Saturday
    var steps: [Step]

    struct Step: Identifiable, Hashable {
        var id = UUID()
        var title: String
        var minutes: Int
        var taskId: UUID?
        var include = true
    }
}

@MainActor
enum RoutineFinder {
    private static let morning = ["brush teeth", "floss", "shower", "make bed", "make the bed", "meds", "medication", "vitamin", "pill", "breakfast",
                                  "stretch", "meditat", "journal", "walk the dog", "walk dog", "feed the", "feed cat", "feed dog", "skincare am", "water"]
    private static let evening = ["dishes", "dishwasher", "trash", "garbage", "laundry", "lunch for tomorrow", "pack lunch", "set out clothes", "lay out clothes",
                                  "wipe counter", "tidy", "skincare", "plan tomorrow", "charge phone", "lock door", "read", "kitchen", "pick up toys"]
    private static let weekly = ["groceries", "grocery", "vacuum", "mop", "clean bathroom", "clean the bathroom", "change sheets", "wash sheets",
                                 "water plants", "water the plants", "pay bills", "meal prep", "recycling", "mow", "clean fridge", "dust", "car wash", "weekly review"]

    /// Open tasks that look like the same thing again and again, grouped into routines.
    static func suggest(from tasks: [TaskItem]) -> [RoutineSuggestion] {
        let open = tasks.filter { !$0.isDone }
        func matches(_ t: TaskItem, _ words: [String]) -> Bool {
            let s = t.title.lowercased()
            return words.contains { s.contains($0) }
        }
        func repeatsDaily(_ t: TaskItem) -> Bool { t.recurrence?.frequency == .daily }
        func repeatsWeekly(_ t: TaskItem) -> Bool { t.recurrence?.frequency == .weekly }

        var used = Set<UUID>()
        func steps(_ pick: (TaskItem) -> Bool) -> [RoutineSuggestion.Step] {
            open.filter { !used.contains($0.id) && pick($0) }.prefix(10).map { t in
                used.insert(t.id)
                return RoutineSuggestion.Step(title: t.title, minutes: max(2, min(30, t.estimatedMinutes ?? 5)), taskId: t.id)
            }
        }
        var out: [RoutineSuggestion] = []
        let w = steps { matches($0, weekly) || repeatsWeekly($0) }
        let m = steps { matches($0, morning) }
        let e = steps { matches($0, evening) || repeatsDaily($0) }
        if m.count >= 2 { out.append(RoutineSuggestion(name: "Morning routine", icon: "sunrise.fill", hour: 7, minute: 0, steps: m)) }
        if e.count >= 2 { out.append(RoutineSuggestion(name: "Evening reset", icon: "moon.stars.fill", hour: 20, minute: 30, steps: e)) }
        if w.count >= 2 { out.append(RoutineSuggestion(name: "Weekly reset", icon: "house.fill", hour: 10, minute: 0, weekday: 1, steps: w)) }
        // A single leftover still fits somewhere: fold it into the closest routine.
        if out.isEmpty, (m + e + w).count >= 2 {
            out.append(RoutineSuggestion(name: "Daily reset", icon: "arrow.triangle.2.circlepath", hour: 19, minute: 0, steps: m + e + w))
        }
        return out
    }

    /// Saves the routine, puts it on the calendar as a repeating block, and clears the loose tasks it replaces.
    static func create(_ s: RoutineSuggestion, onCalendar: Bool, removeTasks: Bool, tasks: [TaskItem], ctx: ModelContext) -> String {
        let steps = s.steps.filter(\.include)
        guard !steps.isEmpty else { return "Pick at least one step." }
        let total = steps.reduce(0) { $0 + $1.minutes }
        let routine = Routine(name: s.name, icon: s.icon, steps: steps.map { Routine.Step(title: $0.title, minutes: $0.minutes) },
                              finishBy: s.hour * 60 + s.minute + total)
        var all = RoutineStore.all
        all.append(routine)
        RoutineStore.all = all

        var notes: [String] = ["Saved to Routines"]
        if onCalendar {
            do {
                try scheduleOnCalendar(s, minutes: total)
                notes.append(s.weekday == nil ? "on your calendar every day" : "on your calendar every week")
            } catch {
                notes.append("couldn't add it to your calendar (\(error.localizedDescription))")
            }
        }
        if removeTasks {
            let ids = Set(steps.compactMap(\.taskId))
            let gone = tasks.filter { ids.contains($0.id) }
            let saved = gone.map { (title: $0.title, notes: $0.notes, due: $0.dueDate, priority: $0.priority, list: $0.listName) }
            for t in gone { _ = TaskTrash.keep(t); TaskAlerts.cancel(t); CalendarService.shared.removeReminder(for: t); ctx.delete(t) }
            try? ctx.save()
            notes.append("\(gone.count) loose task\(gone.count == 1 ? "" : "s") cleared")
            UndoCenter.shared.offer("Moved \(gone.count) task\(gone.count == 1 ? "" : "s") into “\(s.name)”", seconds: 6) {
                for x in saved {
                    let r = TaskItem(title: x.title, dueDate: x.due, priority: x.priority)
                    r.notes = x.notes; r.listName = x.list
                    ctx.insert(r)
                    try? CalendarService.shared.push(r)
                }
                try? ctx.save()
            }
        }
        Haptics.success()
        return notes.joined(separator: ", ") + "."
    }

    static func scheduleOnCalendar(_ s: RoutineSuggestion, minutes: Int) throws {
        let svc = CalendarService.shared
        let store = svc.store
        let cal = Calendar.current
        var start = cal.date(bySettingHour: s.hour, minute: s.minute, second: 0, of: Date()) ?? Date()
        if let wd = s.weekday {
            start = cal.nextDate(after: Date(), matching: DateComponents(hour: s.hour, minute: s.minute, weekday: wd), matchingPolicy: .nextTime) ?? start
        } else if start < Date() {
            start = cal.date(byAdding: .day, value: 1, to: start) ?? start
        }
        let e = EKEvent(eventStore: store)
        e.calendar = try svc.keelCalendar()
        e.title = "↻ \(s.name)"
        e.startDate = start
        e.endDate = start.addingTimeInterval(Double(max(minutes, 5) * 60))
        e.notes = s.steps.filter(\.include).map { "• \($0.title) (\($0.minutes) min)" }.joined(separator: "\n") + "\n\nkeel-routine"
        e.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: s.weekday == nil ? .daily : .weekly, interval: 1, end: nil))
        try store.save(e, span: .futureEvents)
        svc.invalidateEvents()
    }
}

struct RoutineBuilderView: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var tasks: [TaskItem]
    @State private var suggestions: [RoutineSuggestion] = []
    @State private var onCalendar = true
    @State private var removeTasks = true
    @State private var result: String?
    @State private var loaded = false

    var body: some View {
        List {
            Section {
                KitIntro(icon: "arrow.triangle.2.circlepath.circle.fill", color: .teal, text: "Tasks you do again and again (dishes, meds, trash night, watering plants) work better as one routine than as a pile of to-dos. Keel groups them into a ready-made routine, puts it on your calendar as one repeating block, and clears the loose tasks. Undo brings them back.")
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            if loaded && suggestions.isEmpty {
                Section {
                    Text("No routine-like tasks right now. When chores and habits pile up in Tasks, Keel will spot them here.")
                        .foregroundStyle(DS.Palette.inkSoft)
                    NavigationLink { LazyView(RoutinesView()) } label: { Label("Open your routines", systemImage: "list.number") }
                }
            }
            ForEach($suggestions) { $s in
                Section {
                    TextField("Name", text: $s.name).font(DS.Font.headline)
                    DatePicker("Starts at", selection: Binding(get: {
                        Calendar.current.date(bySettingHour: s.hour, minute: s.minute, second: 0, of: Date()) ?? Date()
                    }, set: { d in
                        s.hour = Calendar.current.component(.hour, from: d); s.minute = Calendar.current.component(.minute, from: d)
                    }), displayedComponents: .hourAndMinute)
                    Picker("Repeats", selection: $s.weekday) {
                        Text("Every day").tag(Int?.none)
                        ForEach(1...7, id: \.self) { d in Text("Every \(Calendar.current.weekdaySymbols[d - 1])").tag(Int?.some(d)) }
                    }
                    ForEach($s.steps) { $step in
                        HStack {
                            Button { step.include.toggle() } label: {
                                Image(systemName: step.include ? "checkmark.circle.fill" : "circle").foregroundStyle(step.include ? .teal : DS.Palette.inkSoft)
                            }
                            .buttonStyle(.plain)
                            Text(step.title).lineLimit(1)
                            Spacer()
                            Stepper("\(step.minutes)m", value: $step.minutes, in: 1...60).fixedSize().font(.caption)
                        }
                    }
                    Button("Create “\(s.name)”", systemImage: "wand.and.stars") {
                        result = RoutineFinder.create(s, onCalendar: onCalendar, removeTasks: removeTasks, tasks: tasks, ctx: ctx)
                        suggestions.removeAll { $0.id == s.id }
                    }
                    .bold()
                } header: {
                    Label("\(s.steps.filter(\.include).count) steps · \(s.steps.filter(\.include).reduce(0) { $0 + $1.minutes }) min", systemImage: s.icon)
                }
            }
            if !suggestions.isEmpty {
                Section {
                    Toggle("Put it on my calendar", isOn: $onCalendar)
                    Toggle("Clear the loose tasks", isOn: $removeTasks)
                } footer: { Text("The routine goes on a “Keel” calendar as one repeating block, so every calendar app shows it. Run it step by step from Routines.") }
            }
            if let result { Section { Label(result, systemImage: "checkmark.seal.fill").foregroundStyle(DS.Palette.calm) } }
        }
        .navigationTitle("Tasks into routines")
        .task {
            guard !loaded else { return }
            suggestions = RoutineFinder.suggest(from: tasks)
            loaded = true
        }
    }
}

// MARK: - Change your calendar by saying it

struct CalendarChange: Equatable {
    enum Action: String { case add, move, delete, rename }
    var action: Action
    var match: String          // which event (words from its title)
    var start: Date?
    var minutes: Int?
    var title: String?
}

@MainActor
enum CalendarAI {
    /// "move dentist to Friday 3pm", "delete lunch tomorrow", "rename standup to Team sync", "add gym Tuesday 6pm".
    static func understand(_ sentence: String) async -> CalendarChange? {
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = .current
        let prompt = """
        Today is \(now.formatted(.dateTime.weekday(.wide).year().month().day().hour().minute())) (\(TimeZone.current.identifier)).
        Turn this calendar request into JSON with keys: action (add, move, delete or rename), match (words from the existing event's title; empty for add), start (ISO 8601 with time zone offset, or empty), minutes (number or 0), title (new title for add or rename, else empty).
        Reply with only the JSON object.
        Request: \(sentence)
        """
        if let raw = await AIRouter.shared.write(prompt),
           let jsonText = raw.range(of: #"\{[\s\S]*\}"#, options: .regularExpression).map({ String(raw[$0]) }),
           let obj = try? JSONSerialization.jsonObject(with: Data(jsonText.utf8)) as? [String: Any],
           let a = CalendarChange.Action(rawValue: ((obj["action"] as? String) ?? "").lowercased()) {
            let start = (obj["start"] as? String).flatMap { iso.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
            let minutes = (obj["minutes"] as? Int) ?? (obj["minutes"] as? Double).map(Int.init)
            return CalendarChange(action: a, match: (obj["match"] as? String) ?? "", start: start,
                                  minutes: (minutes ?? 0) > 0 ? minutes : nil, title: (obj["title"] as? String).flatMap { $0.isEmpty ? nil : $0 })
        }
        return fallback(sentence)
    }

    /// Without AI: the common shapes, read on this device.
    static func fallback(_ sentence: String) -> CalendarChange? {
        let low = sentence.lowercased().trimmingCharacters(in: .whitespaces)
        for verb in ["delete ", "cancel ", "remove "] where low.hasPrefix(verb) {
            var rest = String(low.dropFirst(verb.count))
            for w in [" today", " tomorrow", " on monday", " on tuesday", " on wednesday", " on thursday", " on friday", " on saturday", " on sunday"] { rest = rest.replacingOccurrences(of: w, with: "") }
            return CalendarChange(action: .delete, match: rest.replacingOccurrences(of: "my ", with: "").trimmingCharacters(in: .whitespaces))
        }
        for verb in ["move ", "reschedule ", "push "] where low.hasPrefix(verb) {
            let rest = String(sentence.dropFirst(verb.count))
            guard let to = rest.range(of: " to ", options: .caseInsensitive) else { return nil }
            let what = String(rest[..<to.lowerBound]).replacingOccurrences(of: "my ", with: "")
            let when = String(rest[to.upperBound...])
            guard let p = QuickEvent.parse("x " + when) else { return nil }
            return CalendarChange(action: .move, match: what.trimmingCharacters(in: .whitespaces), start: p.start)
        }
        if let p = QuickEvent.parse(sentence.replacingOccurrences(of: "add ", with: "", options: [.caseInsensitive, .anchored])) {
            return CalendarChange(action: .add, match: "", start: p.start, minutes: p.minutes, title: p.title)
        }
        return nil
    }

    /// The event a change is about: the best title match in the next three weeks (or the past day).
    static func findEvent(_ match: String, near date: Date? = nil) -> EKEvent? {
        let words = match.lowercased().split(separator: " ").map(String.init).filter { $0.count > 1 }
        guard !words.isEmpty else { return nil }
        let events = CalendarService.shared.events(from: Date().addingTimeInterval(-86_400), to: Date().addingTimeInterval(21 * 86_400))
        let scored = events.compactMap { e -> (EKEvent, Int)? in
            let t = (e.title ?? "").lowercased()
            let hits = words.filter { t.contains($0) }.count
            return hits > 0 ? (e, hits) : nil
        }
        return scored.sorted { a, b in a.1 != b.1 ? a.1 > b.1 : a.0.startDate < b.0.startDate }.first?.0
    }

    static func apply(_ c: CalendarChange, to event: EKEvent?) throws -> String {
        let svc = CalendarService.shared
        switch c.action {
        case .add:
            guard let start = c.start else { return "I couldn't tell when." }
            let e = EKEvent(eventStore: svc.store)
            e.title = c.title ?? "New event"
            e.calendar = svc.store.defaultCalendarForNewEvents
            e.startDate = start
            e.endDate = start.addingTimeInterval(Double((c.minutes ?? 60) * 60))
            try svc.store.save(e, span: .thisEvent)
            svc.invalidateEvents()
            return "Added \(e.title ?? "it") on \(start.formatted(date: .abbreviated, time: .shortened))."
        case .move:
            guard let event, let start = c.start else { return "I couldn't find that event or the new time." }
            try svc.move(event, to: start)
            return "Moved \(event.title ?? "it") to \(start.formatted(date: .abbreviated, time: .shortened))."
        case .delete:
            guard let event else { return "I couldn't find that event." }
            let title = event.title ?? "it"
            try svc.store.remove(event, span: .thisEvent)
            svc.invalidateEvents()
            return "Deleted \(title)."
        case .rename:
            guard let event, let t = c.title else { return "I couldn't find that event or the new name." }
            event.title = t
            try svc.store.save(event, span: .thisEvent)
            svc.invalidateEvents()
            return "Renamed it to \(t)."
        }
    }
}

struct CalendarAIView: View {
    @State private var text = ""
    @State private var working = false
    @State private var change: CalendarChange?
    @State private var target: EKEvent?
    @State private var result: String?
    @FocusState private var focused: Bool

    var body: some View {
        List {
            Section {
                TextField("Tell Keel what to change", text: $text, axis: .vertical)
                    .focused($focused).lineLimit(1...4)
                    .onSubmit { Task { await understand() } }
                Button { Task { await understand() } } label: {
                    HStack { Label("Check it", systemImage: "sparkles"); if working { Spacer(); ProgressView() } }
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).count < 4 || working)
            } footer: {
                Text("Try “move the dentist to Friday 3pm”, “delete lunch with Sam tomorrow”, “rename standup to Team sync”, or “add gym Tuesday 6pm for an hour”. Nothing changes until you confirm.")
            }
            if let change {
                Section("Keel will") {
                    Label(summary(change), systemImage: icon(change.action)).font(DS.Font.headline)
                    if change.action != .add {
                        if let target {
                            Text("\(target.title ?? "Event") · \(target.startDate.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                        } else {
                            Text("Couldn't find an event matching “\(change.match)” in the next three weeks.").font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Button(change.action == .delete ? "Delete it" : "Do it", systemImage: "checkmark.circle.fill", role: change.action == .delete ? .destructive : nil) {
                        do { result = try CalendarAI.apply(change, to: target); Haptics.success() } catch { result = "Couldn't change the calendar: \(error.localizedDescription)" }
                        self.change = nil; text = ""
                    }
                    .disabled(change.action != .add && target == nil)
                }
            }
            if let result { Section { Label(result, systemImage: "calendar.badge.checkmark") } }
            Section {
                NavigationLink { LazyView(RoutineBuilderView()) } label: { Label("Turn repeat tasks into a routine on my calendar", systemImage: "arrow.triangle.2.circlepath") }
            }
        }
        .navigationTitle("Change my calendar")
        .onAppear { focused = true }
    }

    private func understand() async {
        working = true; defer { working = false }
        result = nil
        guard let c = await CalendarAI.understand(text) else { result = "I didn't catch that. Try “move [event] to [day time]”."; return }
        change = c
        target = c.action == .add ? nil : CalendarAI.findEvent(c.match, near: c.start)
    }

    private func summary(_ c: CalendarChange) -> String {
        let when = c.start.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? ""
        switch c.action {
        case .add: return "Add \(c.title ?? "an event") on \(when)"
        case .move: return "Move \(target?.title ?? c.match) to \(when)"
        case .delete: return "Delete \(target?.title ?? c.match)"
        case .rename: return "Rename \(target?.title ?? c.match) to \(c.title ?? "")"
        }
    }
    private func icon(_ a: CalendarChange.Action) -> String {
        switch a { case .add: "plus.circle"; case .move: "arrow.right.circle"; case .delete: "trash"; case .rename: "pencil" }
    }
}

// MARK: - Today: the routine that's coming up

/// A routine you put on the calendar shows on Today from an hour before it starts until it ends, with Start.
struct UpcomingRoutineCard: View {
    @State private var playing: Routine?

    private var next: (event: EKEvent, routine: Routine)? {
        let now = Date()
        for e in CalendarService.shared.todaysEvents() where (e.notes ?? "").contains("keel-routine") {
            guard e.endDate > now, e.startDate.timeIntervalSince(now) < 3600 else { continue }
            let name = (e.title ?? "").replacingOccurrences(of: "↻ ", with: "")
            if let r = RoutineStore.all.last(where: { $0.name == name }) { return (e, r) }
        }
        return nil
    }

    var body: some View {
        if let n = next {
            HStack(spacing: 12) {
                Image(systemName: n.routine.icon).font(.title3).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Color.teal.gradient, in: .rect(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(n.routine.name).font(DS.Font.headline)
                    Text("\(n.event.startDate > Date() ? "At " + n.event.startDate.formatted(date: .omitted, time: .shortened) : "Now") · \(n.routine.steps.count) steps · \(n.routine.totalMinutes) min")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                Spacer()
                Button("Start") { playing = n.routine }.buttonStyle(.borderedProminent).tint(.teal)
            }
            .padding(DS.Space.m)
            .background { PremiumSurface(tint: .teal) }
            .fullScreenCover(item: $playing) { RoutinePlayer(routine: $0) }
        }
    }
}
