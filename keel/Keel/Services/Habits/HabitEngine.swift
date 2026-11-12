import Foundation
import SwiftData
import UserNotifications

/// Habit stacking that's anchored to your REAL day, not just a clock:
/// "After my standup ends", "After a focus session", "After inbox zero", "When I get to the gym".
@MainActor
enum HabitEngine {

    /// Called after sync / calendar change. Schedules a nudge right after each anchor event ends.
    static func scheduleEventAnchoredStacks(_ stacks: [HabitStack], habits: [Habit]) {
        let center = UNUserNotificationCenter.current()
        let today = Calendar.current.component(.weekday, from: Date())
        for stack in stacks where stack.isActive && stack.weekdays.contains(today) {
            let chain = habits.filter { $0.stackId == stack.id }.sorted { $0.orderInStack < $1.orderInStack }
            guard let first = chain.first else { continue }
            let body = chain.map { "\($0.name) (\($0.minutes)m)" }.joined(separator: " → ")

            var fireDate: Date?
            switch stack.anchor {
            case .time(let h, let m):
                fireDate = Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date())
            case .afterEvent(let keyword):
                fireDate = CalendarService.shared.todaysEvents()
                    .first { ($0.title ?? "").localizedCaseInsensitiveContains(keyword) && $0.endDate > Date() }?.endDate
            case .afterFocusSession, .afterInboxZero, .manual, .location:
                fireDate = nil   // fired by in-app events (see trigger(_:)) or a geofence
            }
            guard let fireDate, fireDate > Date() else { continue }
            let c = UNMutableNotificationContent()
            c.title = "\(stack.anchor.label): \(first.name)"
            c.body = body
            c.categoryIdentifier = "HABIT_STACK"
            KeelAlerts.urgent(c, relevance: 0.7)
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            center.add(UNNotificationRequest(identifier: "stack.\(stack.id)", content: c,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }

    /// In-app anchors (inbox zero, focus session end) call this.
    static func trigger(_ anchor: StackAnchor, stacks: [HabitStack], habits: [Habit]) -> [Habit] {
        guard let stack = stacks.first(where: { $0.isActive && $0.anchor == anchor }) else { return [] }
        return habits.filter { $0.stackId == stack.id }.sorted { $0.orderInStack < $1.orderInStack }
    }

    /// ADHD-friendly streaks: a missed day spends a grace token instead of wiping the streak.
    /// Tokens refill one per 7-day run. Total completions never decrease.
    static func complete(_ habit: Habit, lastCompletedDay: Date?, ctx: ModelContext) {
        let today = Calendar.current.startOfDay(for: Date())
        ctx.insert(HabitLog(habitId: habit.id, day: today))
        habit.totalCompletions += 1

        if let last = lastCompletedDay {
            let gap = Calendar.current.dateComponents([.day], from: last, to: today).day ?? 0
            if gap == 0 { return }                               // already counted today
            let missed = gap - 1
            if missed <= habit.graceTokens {
                habit.graceTokens -= missed
                habit.currentStreak += 1
            } else {
                habit.currentStreak = 1                          // gentle reset, no shaming copy
            }
        } else {
            habit.currentStreak = 1
        }
        if habit.currentStreak % 7 == 0 { habit.graceTokens = min(habit.graceTokens + 1, 3) }
        habit.bestStreak = max(habit.bestStreak, habit.currentStreak)
        Haptics.success()
    }
}

/// Habits that tick themselves off from Apple Health: "Walk 8,000 steps", "Work out 20 min", "Meditate 5 min".
@MainActor
enum HealthHabits {
    static let options: [(id: String?, label: String)] = [
        (nil, "Off"),
        ("steps:5000", "5,000 steps"), ("steps:8000", "8,000 steps"), ("steps:10000", "10,000 steps"),
        ("workout:20", "20 min exercise"), ("workout:30", "30 min exercise"), ("workout:45", "45 min exercise"),
        ("mindful:5", "5 mindful minutes"), ("mindful:10", "10 mindful minutes"),
    ]

    static func label(_ goal: String?) -> String? { goal.flatMap { g in options.first { $0.id == g }?.label } }

    /// Checks Health and completes any habit whose goal is met today.
    static func check(ctx: ModelContext) async {
        let habits = ((try? ctx.fetch(FetchDescriptor<Habit>())) ?? []).filter { $0.healthGoal != nil }
        guard !habits.isEmpty, HealthService.shared.isAuthorizedHint else { return }
        let today = Calendar.current.startOfDay(for: Date())
        let logs = (try? ctx.fetch(FetchDescriptor<HabitLog>())) ?? []
        var steps: Int?, exercise: Int?, mindful: Int?
        for h in habits {
            guard let goal = h.healthGoal, !logs.contains(where: { $0.habitId == h.id && $0.day == today }) else { continue }
            let parts = goal.split(separator: ":")
            guard parts.count == 2, let target = Int(parts[1]) else { continue }
            let value: Int
            switch parts[0] {
            case "steps": if steps == nil { steps = await HealthService.shared.todaySteps() }; value = steps!
            case "workout": if exercise == nil { exercise = await HealthService.shared.todayExerciseMinutes() }; value = exercise!
            case "mindful": if mindful == nil { mindful = await HealthService.shared.todayMindfulMinutes() }; value = mindful!
            default: continue
            }
            if value >= target {
                let last = logs.filter { $0.habitId == h.id }.map(\.day).max()
                HabitEngine.complete(h, lastCompletedDay: last, ctx: ctx)
            }
        }
        try? ctx.save()
    }
}
