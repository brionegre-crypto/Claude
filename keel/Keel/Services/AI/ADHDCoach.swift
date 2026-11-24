import Foundation
import SwiftData

/// Features built for ADHD brains — most aren't in any mainstream productivity app.
@MainActor
enum ADHDCoach {

    // MARK: 1. "Just One Thing" — the single best next action right now

    /// Picks ONE task using energy, time until the next event, deadlines and how long it's been avoided.
    /// Remembered pick: Today redraws often (every email during a sync), but the answer only changes when your
    /// tasks, your energy or the time (in 5-minute steps) change.
    private static var lastPick: (key: String, id: UUID?)?

    static func nextThing(tasks: [TaskItem], energy: EnergyLevel) -> TaskItem? {
        let stamp = tasks.reduce(0.0) { max($0, $1.updatedAt.timeIntervalSince1970) }
        let key = "\(tasks.count)|\(stamp)|\(energy.rawValue)|\(Int(Date().timeIntervalSince1970 / 300))"
        if let p = lastPick, p.key == key { return p.id.flatMap { id in tasks.first { $0.id == id } } }
        let pick = rankNext(tasks: tasks, energy: energy)
        lastPick = (key, pick?.id)
        return pick
    }

    private static func rankNext(tasks: [TaskItem], energy: EnergyLevel) -> TaskItem? {
        let openIds = Set(tasks.filter { !$0.isDone }.map(\.id))
        let open = tasks.filter { !$0.isDone && !$0.isWaitingOn && !($0.blockedById.map(openIds.contains) ?? false) }
        let minutesFree = CalendarService.shared.freeSlots(minMinutes: 5).first.map { Int($0.duration / 60) } ?? 60
        return open.max { score($0, energy, minutesFree) < score($1, energy, minutesFree) }
    }

    /// How much a task deserves to be next. Weighs, in order: deadlines (overdue, today, a hard deadline coming up),
    /// importance (priority, pinned, part of a goal, someone emailed you about it), fit (does it fit before your next
    /// event, does it match your energy), momentum (already started) and avoidance (important things that keep slipping
    /// get a nudge, but not on a low-energy day). Someday tasks sink.
    static func score(_ t: TaskItem, _ energy: EnergyLevel, _ minutesFree: Int) -> Double {
        let cal = Calendar.current, now = Date()
        var s = Double(t.priority.rawValue) * 3
        if let due = t.dueDate {
            let startToday = cal.startOfDay(for: now)
            if due < startToday { s += 8 + min(4, now.timeIntervalSince(due) / 86_400) }       // overdue
            else if cal.isDateInToday(due) { s += t.hasDueTime && due < now.addingTimeInterval(3 * 3600) ? 9 : 6 }
            else { s += max(0, 4 - due.timeIntervalSince(startToday) / 86_400) }              // soon
        }
        if let dl = TaskMeta.deadline(t) { s += max(0, 6 - dl.timeIntervalSince(now) / 86_400) }   // hard deadline
        if t.isPinned { s += 4 }
        if t.goalId != nil { s += 2 }
        if t.sourceEmailId != nil { s += 1.5 }                                                // someone's waiting
        s -= Double(abs(t.energy.rawValue - energy.rawValue)) * 2                             // energy match
        let est = calibratedMinutes(t)
        if est > minutesFree { s -= 3 }                                                       // won't fit before next event
        if energy == .low && est <= 10 { s += 2 }                                             // low energy: quick wins
        let steps = t.microSteps
        if steps.contains(where: \.done) && steps.contains(where: { !$0.done }) { s += 2 }    // already started
        else if !steps.isEmpty { s += 1 }                                                     // easier to start
        if t.timesRescheduled >= 2 && t.priority.rawValue >= TaskPriority.medium.rawValue && energy != .low {
            s += min(3, Double(t.timesRescheduled))                                           // stop it slipping again
        }
        if t.isSomeday { s -= 10 }
        return s
    }

    /// Why a task came out on top, in a few words ("Overdue · high priority · fits before your 2 PM").
    static func reason(_ t: TaskItem) -> String {
        var r: [String] = []
        let cal = Calendar.current
        if let d = t.dueDate { r.append(d < cal.startOfDay(for: Date()) ? "Overdue" : cal.isDateInToday(d) ? "Due today" : "Due soon") }
        if TaskMeta.deadline(t) != nil { r.append("deadline coming") }
        if t.priority.rawValue >= TaskPriority.high.rawValue { r.append("high priority") }
        if t.goalId != nil { r.append("moves a goal forward") }
        if t.timesRescheduled >= 2 { r.append("keeps slipping") }
        return r.prefix(3).joined(separator: " · ")
    }

    // MARK: 2. Time-blindness calibrator — learns how long things REALLY take you

    /// Your personal multiplier, e.g. 1.6 means "you estimate 30 min, it takes 48".
    /// Only used once Keel has actually timed a few of your tasks (and padding is on in Settings → Tasks);
    /// until then a task takes exactly as long as its duration says.
    static var estimateMultiplier: Double {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: padKey) as? Bool ?? true, d.integer(forKey: samplesKey) >= 3 else { return 1.0 }
            return max(1.0, d.double(forKey: "adhd.multiplier").nonZero ?? 1.0)
        }
        set { UserDefaults.standard.set(newValue, forKey: "adhd.multiplier") }
    }
    static let samplesKey = "adhd.multiplier.samples"
    static let padKey = "tasks.padEstimates"
    static let defaultMinutesKey = "tasks.defaultMinutes"

    /// How long a task without its own duration takes (Settings → Tasks → Default length). 5 minutes unless you change it.
    static var defaultMinutes: Int {
        let m = UserDefaults.standard.integer(forKey: defaultMinutesKey)
        return m > 0 ? m : 5
    }

    /// The task's own duration, or the default.
    static func minutes(_ t: TaskItem) -> Int { t.estimatedMinutes ?? defaultMinutes }

    static func calibratedMinutes(_ t: TaskItem) -> Int {
        Int((Double(minutes(t)) * estimateMultiplier).rounded())
    }

    static func recordActual(_ t: TaskItem, minutes: Int) {
        t.actualMinutes = minutes
        guard let est = t.estimatedMinutes, est > 0 else { return }
        let ratio = Double(minutes) / Double(est)
        let d = UserDefaults.standard
        let samples = d.integer(forKey: samplesKey)
        let old = samples == 0 ? ratio : (d.double(forKey: "adhd.multiplier").nonZero ?? ratio)
        d.set(old * 0.8 + ratio * 0.2, forKey: "adhd.multiplier")        // smoothed running average
        d.set(samples + 1, forKey: samplesKey)
    }

    // MARK: 3. Wall of Awful detector — tasks you keep avoiding

    /// A task rescheduled 3+ times isn't a scheduling problem, it's an emotional one.
    /// Keel offers: break it down, body-double it, or consciously drop it.
    static func avoidedTasks(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.filter { !$0.isDone && $0.timesRescheduled >= 3 }
    }

    // MARK: 4. "Reset my day" — one tap, zero guilt

    /// Moves every overdue/unfinished task to tomorrow (or a "Someday" list if avoided too often)
    /// and regenerates today's plan from now. No red overdue badges, ever.
    static func resetDay(tasks: [TaskItem]) {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
        for t in tasks where !t.isDone {
            guard let due = t.dueDate, due < Date() else { continue }
            if t.timesRescheduled >= 5 { t.listName = "Someday"; t.dueDate = nil }
            else { t.dueDate = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow); t.timesRescheduled += 1 }
            t.updatedAt = Date()
        }
    }

    // MARK: 5. Brain dump → sorted

    /// Paste or dictate everything in your head; AI splits it into tasks, notes, events and worries.
    static func parseBrainDump(_ text: String) -> [TaskItem] {
        // On-device first pass: one line = one item. (Cloud/Apple Intelligence refines dates & lists.)
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "-•*"))) }
            .filter { !$0.isEmpty }
            .map { TaskItem(title: $0) }
    }

    // MARK: 6. Promise tracker — commitments you made in SENT mail

    /// Scans your sent emails for "I'll send it Friday" / "Let me get back to you" and turns them
    /// into tasks — the #1 thing ADHD folks forget, and no mail client tracks it.
    nonisolated static let promisePatterns = ["i'll ", "i’ll ", "i will ", "let me check", "let me look", "let me get back", "i'll get back",
                                  "will send", "will get you", "will follow up", "i can send", "i'm going to", "i’m going to",
                                  "by tomorrow", "by friday", "by monday", "by eod", "by end of", "later today", "next week"]
    nonisolated static func looksLikePromise(_ sentBody: String) -> Bool {
        let s = sentBody.lowercased()
        return promisePatterns.contains { s.contains($0) }
    }
}

private extension Double { var nonZero: Double? { self == 0 ? nil : self } }
