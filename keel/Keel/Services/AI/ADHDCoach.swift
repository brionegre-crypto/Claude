import Foundation
import SwiftData

/// Features built for ADHD brains — most aren't in any mainstream productivity app.
@MainActor
enum ADHDCoach {

    // MARK: 1. "Just One Thing" — the single best next action right now

    /// Picks ONE task using energy, time until the next event, deadlines and how long it's been avoided.
    static func nextThing(tasks: [TaskItem], energy: EnergyLevel) -> TaskItem? {
        let open = tasks.filter { !$0.isDone && !$0.isWaitingOn }
        let minutesFree = CalendarService.shared.freeSlots(minMinutes: 5).first.map { Int($0.duration / 60) } ?? 60
        return open.max { score($0, energy, minutesFree) < score($1, energy, minutesFree) }
    }

    private static func score(_ t: TaskItem, _ energy: EnergyLevel, _ minutesFree: Int) -> Double {
        var s = Double(t.priority.rawValue) * 2
        if let due = t.dueDate { s += max(0, 5 - due.timeIntervalSinceNow / 86_400) }   // due soon ↑
        s -= Double(abs(t.energy.rawValue - energy.rawValue)) * 2                         // energy match
        let est = calibratedMinutes(t)
        if est > minutesFree { s -= 3 }                                                   // won't fit before next meeting
        if !t.microSteps.isEmpty { s += 1 }                                               // easier to start
        return s
    }

    // MARK: 2. Time-blindness calibrator — learns how long things REALLY take you

    /// Your personal multiplier, e.g. 1.6 means "you estimate 30 min, it takes 48".
    static var estimateMultiplier: Double {
        get { max(1.0, UserDefaults.standard.double(forKey: "adhd.multiplier").nonZero ?? 1.5) }
        set { UserDefaults.standard.set(newValue, forKey: "adhd.multiplier") }
    }

    static func calibratedMinutes(_ t: TaskItem) -> Int {
        Int(Double(t.estimatedMinutes ?? 25) * estimateMultiplier)
    }

    static func recordActual(_ t: TaskItem, minutes: Int) {
        t.actualMinutes = minutes
        guard let est = t.estimatedMinutes, est > 0 else { return }
        let ratio = Double(minutes) / Double(est)
        estimateMultiplier = estimateMultiplier * 0.8 + ratio * 0.2       // smoothed running average
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
    static let promisePatterns = ["i'll ", "i will ", "let me ", "i'll get back", "will send", "by tomorrow", "by friday", "by eod"]
    static func looksLikePromise(_ sentBody: String) -> Bool {
        let s = sentBody.lowercased()
        return promisePatterns.contains { s.contains($0) }
    }
}

private extension Double { var nonZero: Double? { self == 0 ? nil : self } }
