import SwiftUI
import SwiftData

/// Loose tasks that belong in a routine ("Take vitamins" → Morning), found by meaning, time of day and repetition,
/// and adding them: you approve every one. A routine linked to a Reminders list gets the task moved into that list
/// (so Reminders moves it too); any other routine gets it as a step and the loose task is cleared. Undo restores.
@MainActor
enum RoutineFit {
    struct Candidate: Identifiable {
        let task: TaskItem
        let reason: String
        var id: UUID { task.id }
    }

    // MARK: Which tasks can go in

    /// Open tasks that aren't already part of this routine or of a list used as a routine.
    static func eligible(_ t: TaskItem, for r: Routine) -> Bool {
        guard !t.isDone, !t.isDeleted, !t.isSomeday, t.modelContext != nil else { return false }
        if let list = r.sourceList, t.listName == list { return false }
        if RoutineLists.linkedNames.contains(t.listName) { return false }
        let key = NoteText.fold(t.title)
        return !r.steps.contains { NoteText.fold($0.title) == key }
    }

    // MARK: Suggestions

    private static let kinds: [(match: [String], words: [String], hours: ClosedRange<Int>?)] = [
        (["morning", "wake", "sunrise"], ["shower", "breakfast", "coffee", "teeth", "brush", "floss", "meds", "medicine", "vitamin", "pill",
                                         "dress", "bed", "make bed", "water", "stretch", "journal", "plan", "skincare", "shave", "hair"], 5...11),
        (["evening", "night", "bed", "wind", "sleep", "moon"], ["teeth", "brush", "floss", "alarm", "charger", "phone", "clothes", "lay out",
                                         "set out", "journal", "read", "stretch", "magnesium", "melatonin", "meds", "pill", "skincare",
                                         "dishes", "tidy", "lights", "lock", "pack", "lunch", "tomorrow"], 18...23),
        (["leav", "door", "commute", "out"], ["keys", "wallet", "phone", "bag", "backpack", "lunch", "shoes", "jacket", "coat", "lights",
                                         "stove", "lock", "badge", "laptop", "charger", "water bottle"], nil),
        (["work", "office", "shutdown"], ["inbox", "email", "calendar", "standup", "timesheet", "plan tomorrow", "review", "notes"], nil),
        (["gym", "workout", "exercise", "run"], ["stretch", "warm up", "protein", "water", "shoes", "gym bag", "foam roll"], nil),
        (["clean", "chore", "house", "home", "reset"], ["laundry", "dishes", "vacuum", "trash", "recycling", "wipe", "tidy", "plants",
                                         "water the plants", "bins", "sheets", "fridge", "bathroom", "kitchen"], nil),
    ]

    private static func kind(of r: Routine) -> (words: [String], hours: ClosedRange<Int>?)? {
        let name = (r.name + " " + r.icon).lowercased()
        return kinds.first { $0.match.contains(where: name.contains) }.map { ($0.words, $0.hours) }
    }

    /// Tasks that look like they belong in `r`, best first, each with a reason. Ones you said no to stay out, and a
    /// task that fits another routine better is left to that one (each task is suggested for one routine).
    static func candidates(for r: Routine, from tasks: [TaskItem]) -> [Candidate] {
        let others = RoutineProgress.shared.routines.filter { $0.id != r.id }
        var seenTitles = Set<String>()
        return scored(for: r, from: tasks).filter { c in
            let mine = c.score
            guard !others.contains(where: { o in (scored(for: o, from: [c.candidate.task]).first?.score ?? 0) > mine }) else { return false }
            return seenTitles.insert(NoteText.fold(c.candidate.task.title)).inserted       // the same task twice shows once
        }.prefix(12).map(\.candidate)
    }

    /// Embeddings are the slow part (several per task); worked out once per text.
    private static var vectorCache: [String: [Float]?] = [:]
    private static func vector(_ text: String) -> [Float]? {
        if let hit = vectorCache[text] { return hit }
        if vectorCache.count > 2_000 { vectorCache.removeAll() }
        let v = BrainIndex.embed(text)
        vectorCache[text] = v
        return v
    }

    private static func scored(for r: Routine, from tasks: [TaskItem]) -> [(candidate: Candidate, score: Double)] {
        let dismissed = Set(UserDefaults.standard.stringArray(forKey: dismissKey(r)) ?? [])
        let pool = tasks.filter { eligible($0, for: r) && !dismissed.contains($0.id.uuidString) }
        guard !pool.isEmpty else { return [] }
        let cal = Calendar.current
        let k = kind(of: r)
        // Meaning: the closest of the routine's name and steps (on-device sentence embeddings).
        let anchors: [(String, [Float])] = ([r.name] + r.steps.map(\.title)).compactMap { s in vector(s).map { (s, $0) } }
        let window: ClosedRange<Int>? = r.startMinute.map { max(0, $0 - 45)...min(24 * 60, $0 + r.totalMinutes + 45) }
            ?? k?.hours.map { ($0.lowerBound * 60)...($0.upperBound * 60 + 59) }

        var out: [(Candidate, Double)] = []
        for t in pool {
            var score = 0.0
            var why: [String] = []
            let title = t.title.lowercased()
            if let k, let w = k.words.first(where: title.contains) {
                score += 0.8; why.append("“\(w)” is a \(r.name.lowercased()) kind of step")
            }
            if let v = vector(t.title), let best = anchors.map({ ($0.0, dot($0.1, v)) }).max(by: { $0.1 < $1.1 }), best.1 >= 0.72 {
                score += best.1 >= 0.82 ? 1.0 : 0.6
                if why.isEmpty { why.append(best.0 == r.name ? "Sounds like part of \(r.name)" : "Like “\(best.0)”") }
            }
            if let window, t.hasDueTime, let d = t.dueDate {
                let m = cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d)
                if window.contains(m) { score += 0.6; why.append("Due \(d.formatted(date: .omitted, time: .shortened)), when this routine runs") }
                else { score -= 1.2 }          // "Floss" at 9:50 PM isn't a morning step, whatever the word says
            }
            if t.recurrence != nil, score > 0 { score += 0.3; why.append("Repeats \(t.recurrence?.label.lowercased() ?? "")") }
            if score >= 1.0 { out.append((Candidate(task: t, reason: why.prefix(2).joined(separator: " · ")), score)) }
        }
        return out.sorted { $0.1 > $1.1 }.map { (candidate: $0.0, score: $0.1) }
    }

    private static func dot(_ a: [Float], _ b: [Float]) -> Double {
        var s: Float = 0
        for i in 0..<min(a.count, b.count) { s += a[i] * b[i] }
        return Double(s)
    }

    private static func dismissKey(_ r: Routine) -> String { "routinefit.dismissed." + r.id.uuidString }
    /// "Not for this routine": don't suggest these again for it.
    static func dismiss(_ ids: [UUID], for r: Routine) {
        let old = UserDefaults.standard.stringArray(forKey: dismissKey(r)) ?? []
        UserDefaults.standard.set(Array(Set(old + ids.map(\.uuidString))), forKey: dismissKey(r))
    }

    // MARK: Adding

    /// Puts the tasks into the routine. Returns a short confirmation. Undo (on screen) puts everything back.
    @discardableResult
    static func add(_ tasks: [TaskItem], to r: Routine, ctx: ModelContext) -> String {
        let tasks = tasks.filter { eligible($0, for: r) }
        guard !tasks.isEmpty, RoutineStore.all.contains(where: { $0.id == r.id }) else { return "" }
        let n = tasks.count, noun = n == 1 ? "task" : "tasks"
        if let list = r.sourceList {
            // Linked to a list: the task joins that list (and moves there in Apple Reminders), so it's a step.
            let moved = tasks.map { (task: $0, from: $0.listName) }
            for t in tasks { t.listName = list; t.updatedAt = Date(); try? CalendarService.shared.push(t) }
            try? ctx.save()
            RoutineLists.refresh(ctx)
            UndoCenter.shared.offer("Moved \(n) \(noun) into \(r.name)", seconds: 6) {
                for m in moved where m.task.modelContext != nil {
                    m.task.listName = m.from; m.task.updatedAt = Date(); try? CalendarService.shared.push(m.task)
                }
                try? ctx.save()
                RoutineLists.refresh(ctx)
            }
        } else {
            // Any other routine: each task becomes a step, and the loose task is cleared (as Tasks into routines does).
            var all = RoutineStore.all
            guard let i = all.firstIndex(where: { $0.id == r.id }) else { return "" }
            let before = all[i]
            all[i].steps += tasks.map { Routine.Step(title: $0.title, minutes: max(1, $0.estimatedMinutes ?? ADHDCoach.minutes($0))) }
            RoutineStore.all = all
            let saved = tasks.map { (title: $0.title, notes: $0.notes, due: $0.dueDate, priority: $0.priority, list: $0.listName,
                                     recurrence: $0.recurrence, energy: $0.energy, minutes: $0.estimatedMinutes) }
            for t in tasks { _ = TaskTrash.keep(t); TaskAlerts.cancel(t); CalendarService.shared.removeReminder(for: t); ctx.delete(t) }
            try? ctx.save()
            UndoCenter.shared.offer("Added \(n) \(noun) to \(r.name)", seconds: 6) {
                var again = RoutineStore.all
                if let j = again.firstIndex(where: { $0.id == before.id }) { again[j] = before; RoutineStore.all = again }
                for x in saved {
                    let t = TaskItem(title: x.title, dueDate: x.due, priority: x.priority)
                    t.notes = x.notes; t.listName = x.list; t.recurrence = x.recurrence; t.energy = x.energy; t.estimatedMinutes = x.minutes
                    ctx.insert(t)
                    try? CalendarService.shared.push(t)
                }
                try? ctx.save()
            }
        }
        Haptics.success()
        return "Added \(n) \(noun) to \(r.name)"
    }
}

/// Add tasks to a routine: Keel's suggestions (ticked, with why), and every other task to pick by hand.
struct RoutineFitSheet: View {
    let routine: Routine
    /// Opened to review Keel's suggestions: they start ticked. Opened to add by hand: nothing is ticked for you.
    var preselect = true
    var onAdded: () -> Void = {}
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }, sort: \TaskItem.createdAt, order: .reverse) private var open: [TaskItem]
    @State private var suggested: [RoutineFit.Candidate] = []
    @State private var picked: Set<UUID> = []
    @State private var search = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List {
                if !suggested.isEmpty && search.isEmpty {
                    Section {
                        ForEach(suggested) { c in row(c.task, reason: c.reason) }
                    } header: { Text("These look like they belong in \(routine.name)") } footer: {
                        Text(routine.sourceList.map { "They move into your “\($0)” list (and in Reminders), so they become steps." }
                             ?? "Each becomes a step, and the loose task is cleared. Undo puts it back.")
                    }
                } else if loaded && search.isEmpty {
                    Section { Text("Nothing obvious fits \(routine.name) right now. Pick any task below to add it.").foregroundStyle(DS.Palette.inkSoft) }
                }
                Section(search.isEmpty ? "Or pick any task" : "Tasks") {
                    let shownIds = Set(suggested.map(\.id))
                    ForEach(others.filter { search.isEmpty ? !shownIds.contains($0.id) : true }) { t in row(t, reason: t.listName) }
                }
            }
            .searchable(text: $search, prompt: "Find a task")
            .navigationTitle("Add to \(routine.name)").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(picked.isEmpty ? "Add" : "Add \(picked.count)") { addPicked() }.disabled(picked.isEmpty)
                }
            }
            // Also at the bottom: while you search, iOS hides the top bar (and its Add button) until the search closes.
            .safeAreaInset(edge: .bottom) {
                if !picked.isEmpty {
                    Button { addPicked() } label: {
                        Text("Add \(picked.count) to \(routine.name)").font(DS.Font.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent).tint(DS.Palette.accent)
                    .padding(.horizontal).padding(.bottom, 8)
                }
            }
            .task {
                guard !loaded else { return }
                suggested = RoutineFit.candidates(for: routine, from: open)
                if preselect { picked = Set(suggested.map(\.id)) }     // reviewing suggestions: untick any that don't belong
                loaded = true
            }
        }
    }

    private func addPicked() {
        let chosen = open.filter { picked.contains($0.id) }
        // Suggestions you left unticked aren't offered for this routine again.
        RoutineFit.dismiss(suggested.map(\.id).filter { !picked.contains($0) }, for: routine)
        RoutineFit.add(chosen, to: routine, ctx: ctx)
        onAdded(); dismiss()
    }

    private var others: [TaskItem] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return open.filter { RoutineFit.eligible($0, for: routine) && (q.isEmpty || $0.title.lowercased().contains(q)) }.prefix(200).map { $0 }
    }

    private func row(_ t: TaskItem, reason: String) -> some View {
        let on = picked.contains(t.id)
        return Button {
            if on { picked.remove(t.id) } else { picked.insert(t.id) }
            Haptics.tap()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(on ? DS.Palette.accent : DS.Palette.inkSoft)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.title).foregroundStyle(DS.Palette.ink).lineLimit(2)
                    if !reason.isEmpty { Text(reason).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2) }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.title)
        .accessibilityValue(on ? "Selected" : "Not selected")
    }
}
