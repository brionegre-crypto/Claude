import SwiftUI
import SwiftData

/// Today's progress through your routines: which steps are ticked off, and which you've skipped just for today.
/// Starts fresh each morning. Shared by the Voyage (tick steps off where you see them) and the routine player.
@MainActor @Observable
final class RoutineProgress {
    static let shared = RoutineProgress()

    private struct Day: Codable {
        var day: String
        var done: [UUID: Set<UUID>] = [:]        // routine → steps ticked off today
        var skipped: [UUID: Set<UUID>] = [:]     // routine → steps taken out for today only
        var logged: Set<UUID> = []               // routines already written to the daily log today
    }

    private static let key = "routines.progress.v1"
    private var today: Day
    /// Your routines, read once and kept in step with every save (RoutineStore.all calls `reload()`).
    private(set) var routines: [Routine] = RoutineStore.all

    private init() {
        if let d = UserDefaults.standard.data(forKey: Self.key), let day = try? JSONDecoder().decode(Day.self, from: d) { today = day }
        else { today = Day(day: Self.stamp()) }
    }

    func reload() { routines = RoutineStore.all }

    private static func stamp(_ d: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
    /// Yesterday's ticks don't carry over.
    private func fresh() { if today.day != Self.stamp() { today = Day(day: Self.stamp()) } }
    private func save() { if let d = try? JSONEncoder().encode(today) { UserDefaults.standard.set(d, forKey: Self.key) } }

    // MARK: Reading

    func isDone(_ step: Routine.Step, in r: Routine) -> Bool { fresh(); return today.done[r.id]?.contains(step.id) ?? false }
    func isSkipped(_ step: Routine.Step, in r: Routine) -> Bool { fresh(); return today.skipped[r.id]?.contains(step.id) ?? false }
    /// Steps that count today (skipped ones are out).
    func activeSteps(_ r: Routine) -> [Routine.Step] { r.steps.filter { !isSkipped($0, in: r) } }
    func remaining(_ r: Routine) -> [Routine.Step] { activeSteps(r).filter { !isDone($0, in: r) } }
    func doneCount(_ r: Routine) -> Int { activeSteps(r).count - remaining(r).count }
    func isComplete(_ r: Routine) -> Bool { !activeSteps(r).isEmpty && remaining(r).isEmpty }
    func minutesLeft(_ r: Routine) -> Int { remaining(r).reduce(0) { $0 + $1.minutes } }

    // MARK: Changing

    /// Tick a step off (or back on). Ticking it also completes a matching task due today, so the two never disagree.
    func setDone(_ step: Routine.Step, in r: Routine, _ done: Bool, ctx: ModelContext?) {
        fresh()
        var s = today.done[r.id] ?? []
        if done { s.insert(step.id) } else { s.remove(step.id) }
        today.done[r.id] = s
        save()
        if done { completeMatchingTasks([step.title], ctx: ctx) }
        logIfFinished(r)
    }

    /// The whole routine in one tap: every step still left counts as done.
    func completeAll(_ r: Routine, ctx: ModelContext?) {
        fresh()
        let left = remaining(r)
        today.done[r.id, default: []].formUnion(left.map(\.id))
        save()
        completeMatchingTasks(left.map(\.title), ctx: ctx)
        logIfFinished(r)
    }

    /// Untick everything (tapped the routine's check by mistake).
    func reset(_ r: Routine) {
        fresh()
        today.done[r.id] = []
        save()
    }

    /// Take a step out for today only, or put it back.
    func setSkipped(_ step: Routine.Step, in r: Routine, _ skipped: Bool) {
        fresh()
        var s = today.skipped[r.id] ?? []
        if skipped { s.insert(step.id) } else { s.remove(step.id) }
        today.skipped[r.id] = s
        save()
        logIfFinished(r)
    }

    /// Steps finished in the routine player count on the Voyage too.
    func markFromPlayer(_ step: Routine.Step, routineId: UUID) {
        fresh()
        today.done[routineId, default: []].insert(step.id)
        today.logged.insert(routineId)            // the player writes its own log entry
        save()
    }

    private func logIfFinished(_ r: Routine) {
        guard isComplete(r), !today.logged.contains(r.id) else { return }
        today.logged.insert(r.id)
        save()
        DailyLog.logRoutine(r.name, steps: activeSteps(r).count, minutes: activeSteps(r).reduce(0) { $0 + $1.minutes })
        Haptics.success()
    }

    private func completeMatchingTasks(_ titles: [String], ctx: ModelContext?) {
        guard let ctx, !titles.isEmpty else { return }
        let wanted = Set(titles.map(NoteText.fold))
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        let open = (try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? []
        for t in open where wanted.contains(NoteText.fold(t.title)) && (t.dueDate ?? .distantFuture) < end {
            TaskActions.setDone(t, true)
        }
        try? ctx.save()
    }

    /// Removes a step from the routine itself (not just today), with Undo.
    func removeStep(_ step: Routine.Step, from r: Routine) {
        var all = RoutineStore.all
        guard let ri = all.firstIndex(where: { $0.id == r.id }), let si = all[ri].steps.firstIndex(where: { $0.id == step.id }) else { return }
        let before = all[ri]
        all[ri].steps.remove(at: si)
        RoutineStore.all = all
        UndoCenter.shared.offer("Removed “\(step.title)” from \(r.name)") {
            var again = RoutineStore.all
            if let i = again.firstIndex(where: { $0.id == before.id }) { again[i] = before; RoutineStore.all = again }
        }
    }

    func replace(_ r: Routine) {
        var all = RoutineStore.all
        if let i = all.firstIndex(where: { $0.id == r.id }) { all[i] = r; RoutineStore.all = all }
    }
}

/// A routine on the Voyage: one line with a check for the whole thing. Open it to tick off only what's left,
/// skip a step for today, take a step out of the routine, or edit it.
struct RoutineStopRow: View {
    let routine: Routine
    @Environment(\.modelContext) private var ctx
    @State private var progress = RoutineProgress.shared
    @State private var expanded = false
    @State private var showDone = false
    @State private var editing: Routine?

    var body: some View {
        let r = routine
        let complete = progress.isComplete(r)
        let active = progress.activeSteps(r)
        let done = progress.doneCount(r)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(DS.spring) {
                        if complete { progress.reset(r) } else {
                            let before = progress.remaining(r)
                            progress.completeAll(r, ctx: ctx)
                            // A routine whose time has passed leaves the route once done, so the tick can be taken back here.
                            UndoCenter.shared.offer("\(r.name) routine done") {
                                for st in before { progress.setDone(st, in: r, false, ctx: nil) }
                            }
                        }
                    }
                } label: {
                    ZStack {
                        Circle().stroke(DS.Palette.inkSoft.opacity(0.35), lineWidth: 2)
                        Circle().trim(from: 0, to: active.isEmpty ? 0 : Double(done) / Double(active.count))
                            .stroke(DS.Palette.calm, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
                        if complete { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(DS.Palette.calm) }
                    }
                    .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(complete ? "Mark \(r.name) routine not done" : "Mark \(r.name) routine done")

                Button { withAnimation(DS.spring) { expanded.toggle() } } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(r.name) routine").font(DS.Font.body).strikethrough(complete).foregroundStyle(complete ? DS.Palette.inkSoft : DS.Palette.ink).lineLimit(1)
                            Text(summary(r, done: done, total: active.count, complete: complete)).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft)
                            .rotationEffect(.degrees(expanded ? 0 : -90))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(r.name) routine, \(done) of \(active.count) steps done")
                .accessibilityHint(expanded ? "Hides the steps" : "Shows the steps left")

                if !complete {
                    Button { RoutineLaunch.shared.start(r.id) } label: { Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(DS.Palette.accent) }
                        .buttonStyle(.plain).accessibilityLabel("Start \(r.name) routine")
                }
            }
            if expanded { steps(r) }
        }
        .sheet(item: $editing) { e in
            RoutineEditor(routine: e) { progress.replace($0) }
        }
    }

    private func summary(_ r: Routine, done: Int, total: Int, complete: Bool) -> String {
        var parts: [String] = []
        if let m = r.startMinute { parts.append(RoutinesView.clock(max(0, m))) }     // its own time, even when it's running late
        if complete { parts.append("Done") }
        else {
            parts.append(done == 0 ? "\(total) steps" : "\(done) of \(total) done")
            parts.append("\(progress.minutesLeft(r)) min")
        }
        return parts.joined(separator: " · ")
    }

    /// Only what's left, so a routine never floods the route; finished and skipped steps fold away.
    @ViewBuilder private func steps(_ r: Routine) -> some View {
        let left = progress.remaining(r)
        let finished = progress.activeSteps(r).filter { progress.isDone($0, in: r) }
        let skipped = r.steps.filter { progress.isSkipped($0, in: r) }
        VStack(alignment: .leading, spacing: 2) {
            ForEach(left) { s in stepRow(s, r, done: false) }
            if showDone { ForEach(finished) { s in stepRow(s, r, done: true) } }
            HStack(spacing: 14) {
                if !finished.isEmpty {
                    Button(showDone ? "Hide done" : "\(finished.count) done") { withAnimation(DS.spring) { showDone.toggle() } }
                }
                if !skipped.isEmpty {
                    Menu("\(skipped.count) skipped today") {
                        ForEach(skipped) { s in Button("Put back “\(s.title)”", systemImage: "arrow.uturn.backward") { progress.setSkipped(s, in: r, false) } }
                    }
                }
                Spacer()
                Button("Edit routine…") { editing = r }
            }
            .font(DS.Font.caption.weight(.semibold))
            .foregroundStyle(DS.Palette.accent)
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.leading, 34)
    }

    private func stepRow(_ s: Routine.Step, _ r: Routine, done: Bool) -> some View {
        HStack(spacing: 10) {
            Button { withAnimation(DS.spring) { progress.setDone(s, in: r, !done, ctx: ctx) } } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.body).foregroundStyle(done ? DS.Palette.calm : DS.Palette.inkSoft)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "Mark \(s.title) not done" : "Mark \(s.title) done")
            Text(s.title).font(.callout).strikethrough(done).foregroundStyle(done ? DS.Palette.inkSoft : DS.Palette.ink).lineLimit(2)
            Spacer()
            Text("\(s.minutes) min").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            Menu {
                Button("Skip today", systemImage: "forward") { withAnimation(DS.spring) { progress.setSkipped(s, in: r, true) } }
                Button("Remove from routine", systemImage: "minus.circle", role: .destructive) { withAnimation(DS.spring) { progress.removeStep(s, from: r) } }
            } label: {
                Image(systemName: "ellipsis").font(.caption).foregroundStyle(DS.Palette.inkSoft).frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .accessibilityLabel("More for \(s.title)")
        }
        .padding(.vertical, 3)
    }
}
