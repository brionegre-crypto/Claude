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
