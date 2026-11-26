import SwiftUI
import SwiftData

/// A Reminders list (or any Keel list) used as a routine: the list's open items are the routine's steps, kept in
/// step whenever Keel looks (Voyage, Routines). Ticking a step on the Voyage completes that reminder, so it syncs
/// back to Reminders; a repeating reminder rolls to its next date and stays in the routine.
@MainActor
enum RoutineLists {
    /// Lists already used as routines.
    static var linkedNames: Set<String> { Set(RoutineProgress.shared.routines.compactMap(\.sourceList)) }

    /// Every list you could pick: Apple Reminders lists plus Keel's own lists, A to Z.
    static func available(_ ctx: ModelContext) -> [String] {
        let fromTasks = ((try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? []).map(\.listName)
        let fromReminders = CalendarService.shared.reminderLists.map(\.title)
        return Array(Set(fromTasks + fromReminders)).filter { !$0.isEmpty }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func items(in list: String, ctx: ModelContext) -> [TaskItem] {
        let all = (try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone && $0.listName == list }))) ?? []
        // In the order you'd do them: timed ones by time of day, then the rest in the order they were added.
        let cal = Calendar.current
        func minute(_ t: TaskItem) -> Int? {
            guard t.hasDueTime, let d = t.dueDate else { return nil }
            return cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d)
        }
        return all.filter { !$0.isDeleted && !$0.isSomeday }.sorted {
            switch (minute($0), minute($1)) {
            case let (a?, b?): return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return $0.createdAt < $1.createdAt
            }
        }
    }

    /// The steps a linked routine should have now, keeping each existing step (its id, so today's ticks stay;
    /// its minutes and "skippable") when the reminder is still there.
    static func steps(for r: Routine, ctx: ModelContext) -> [Routine.Step]? {
        guard let list = r.sourceList else { return nil }
        let skip = Set(r.skipTitles ?? [])
        var existing = Dictionary(r.steps.map { (NoteText.fold($0.title), $0) }, uniquingKeysWith: { a, _ in a })
        var out: [Routine.Step] = []
        for t in items(in: list, ctx: ctx) {
            let key = NoteText.fold(t.title)
            guard !skip.contains(key), !out.contains(where: { NoteText.fold($0.title) == key }) else { continue }
            if var s = existing.removeValue(forKey: key) { s.title = t.title; out.append(s) }
            else { out.append(Routine.Step(title: t.title, minutes: max(1, t.estimatedMinutes ?? 5))) }
        }
        return out
    }

    /// Brings every linked routine up to date with its list. Saves only when something changed.
    static func refresh(_ ctx: ModelContext) {
        var all = RoutineStore.all
        var changed = false
        for i in all.indices {
            guard let fresh = steps(for: all[i], ctx: ctx), fresh != all[i].steps else { continue }
            all[i].steps = fresh
            changed = true
        }
        if changed { RoutineStore.all = all }
    }

    /// Use a list as a routine (or return the routine already using it).
    @discardableResult
    static func link(_ list: String, ctx: ModelContext) -> Routine {
        var all = RoutineStore.all
        if let r = all.first(where: { $0.sourceList == list }) { return r }
        var r = Routine(name: list, icon: icon(for: list), steps: [])
        r.sourceList = list
        r.steps = steps(for: r, ctx: ctx) ?? []
        all.append(r)
        RoutineStore.all = all
        Haptics.success()
        return r
    }

    /// Stop following the list; the routine keeps the steps it has now.
    static func unlink(_ r: Routine) -> Routine {
        var u = r
        u.sourceList = nil
        u.skipTitles = nil
        return u
    }

    static func icon(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("morning") || n.contains("wake") { return "sunrise.fill" }
        if n.contains("evening") || n.contains("night") || n.contains("bed") || n.contains("wind") { return "moon.stars.fill" }
        if n.contains("leav") || n.contains("out the door") || n.contains("commute") { return "door.left.hand.open" }
        if n.contains("work") || n.contains("office") { return "briefcase.fill" }
        if n.contains("gym") || n.contains("workout") || n.contains("exercise") { return "dumbbell.fill" }
        if n.contains("clean") || n.contains("chore") || n.contains("house") || n.contains("home") { return "house.fill" }
        if n.contains("meal") || n.contains("kitchen") || n.contains("cook") { return "fork.knife" }
        return "list.bullet"
    }

    // MARK: Suggestions

    struct ListSuggestion: Identifiable {
        var id: String { list }
        let list: String
        let count: Int
        let reason: String
    }

    private static let routineWords = ["morning", "evening", "night", "bedtime", "bed time", "wind down", "wind-down", "routine", "daily",
                                       "every day", "checklist", "before work", "after work", "leaving", "out the door", "wake", "habits",
                                       "chores", "self care", "self-care", "weekly reset", "sunday reset", "shutdown"]

    /// Lists that look like routines: named like one, or mostly repeating items. Lists already in use are left out.
    static func suggestions(_ ctx: ModelContext) -> [ListSuggestion] {
        let linked = linkedNames
        let open = (try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? []
        let byList = Dictionary(grouping: open.filter { !$0.isDeleted }, by: \.listName)
        var out: [ListSuggestion] = []
        for (list, items) in byList where !linked.contains(list) && items.count >= 2 && list != "Inbox" {
            let name = list.lowercased()
            let repeating = items.filter { $0.recurrence != nil }.count
            if routineWords.contains(where: name.contains) {
                out.append(ListSuggestion(list: list, count: items.count, reason: "Named like a routine"))
            } else if Double(repeating) / Double(items.count) >= 0.6 {
                out.append(ListSuggestion(list: list, count: items.count, reason: "\(repeating) of \(items.count) repeat"))
            }
        }
        return out.sorted { $0.count > $1.count }
    }
}

/// Routines → "Suggested for you" and "Use a Reminders list". Shown at the top of Routines.
struct RoutineSuggestionsSection: View {
    let onLinked: (Routine) -> Void
    let onPickList: () -> Void                      // the screen shows the list picker (a sheet on a Section doesn't present)
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var openTasks: [TaskItem]
    @State private var lists: [RoutineLists.ListSuggestion] = []
    @State private var repeatGroups = 0
    @State private var dismissed: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "routines.suggest.dismissed") ?? [])

    var body: some View {
        let shown = lists.filter { !dismissed.contains($0.list) }
        Section {
            ForEach(shown) { s in
                HStack(spacing: DS.Space.m) {
                    Image(systemName: RoutineLists.icon(for: s.list)).font(.title3).foregroundStyle(DS.Palette.accent).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use “\(s.list)” as a routine").font(DS.Font.body)
                        Text("Reminders list · \(s.count) items · \(s.reason)").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                    Spacer()
                    Button("Use") { onLinked(RoutineLists.link(s.list, ctx: ctx)); reload() }
                        .buttonStyle(.borderedProminent).tint(DS.Palette.accent).font(DS.Font.caption.weight(.semibold))
                }
                .swipeActions {
                    Button("Not a routine", systemImage: "xmark") {
                        dismissed.insert(s.list)
                        UserDefaults.standard.set(Array(dismissed), forKey: "routines.suggest.dismissed")
                    }
                }
            }
            if repeatGroups > 0 {
                NavigationLink { LazyView(RoutineBuilderView()) } label: {
                    Label("Keel found \(repeatGroups) routine\(repeatGroups == 1 ? "" : "s") in your repeating tasks", systemImage: "wand.and.stars")
                }
            }
            Button { onPickList() } label: { Label("Use a Reminders list as a routine…", systemImage: "checklist") }
        } header: {
            Text(shown.isEmpty && repeatGroups == 0 ? "From your lists" : "Suggested for you")
        } footer: {
            Text("A list used as a routine stays linked: add, rename or finish a reminder and the routine follows. Ticking a step on Today completes that reminder.")
        }
        .task(id: RoutineProgress.shared.routines.count) { reload() }      // again after a list is linked
    }

    private func reload() {
        lists = RoutineLists.suggestions(ctx)
        repeatGroups = RoutineFinder.suggest(from: openTasks).count
    }
}

/// Pick any Reminders (or Keel) list to use as a routine.
struct RoutineListPicker: View {
    let pick: (String) -> Void
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var lists: [String] = []

    var body: some View {
        NavigationStack {
            List {
                let linked = RoutineLists.linkedNames
                if lists.isEmpty {
                    Text("No lists yet. Lists from Apple Reminders show here once Keel can see your reminders (Settings → Reminders).")
                        .foregroundStyle(DS.Palette.inkSoft)
                }
                ForEach(lists, id: \.self) { l in
                    Button {
                        pick(l); dismiss()
                    } label: {
                        HStack {
                            Label(l, systemImage: RoutineLists.icon(for: l))
                            Spacer()
                            if linked.contains(l) { Text("In use").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft) }
                        }
                    }
                    .disabled(linked.contains(l))
                }
            }
            .navigationTitle("Use a list as a routine").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { lists = RoutineLists.available(ctx) }
        }
    }
}
