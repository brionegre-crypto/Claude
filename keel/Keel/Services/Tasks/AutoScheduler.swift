import Foundation
import SwiftData
import EventKit

/// "Auto-schedule my day": fits today's tasks into the free gaps on your calendar,
/// hardest-first while your energy is high, using how long things *really* take you.
@MainActor
enum AutoScheduler {
    struct Result { var scheduled: Int; var unscheduled: [String] }

    static func scheduleToday(tasks: [TaskItem], endHour: Int = 19) -> Result {
        let cal = Calendar.current
        let now = Date()
        let endOfDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        // Today's and overdue tasks that don't have a fixed time yet.
        let candidates = tasks
            .filter { !$0.isDone && !$0.isWaitingOn && $0.scheduledBlockStart == nil && !$0.hasDueTime && ($0.dueDate ?? .distantFuture) < endOfDay }
            .sorted { a, b in
                // Highest priority and highest energy first, while you're freshest.
                (a.priority.rawValue, a.energy.rawValue) > (b.priority.rawValue, b.energy.rawValue)
            }
        // Start at the next quarter hour.
        let minute = cal.component(.minute, from: now)
        var cursor = cal.date(byAdding: .minute, value: (15 - minute % 15) % 15 + 5, to: now) ?? now
        let slots = CalendarService.shared.freeSlots(minMinutes: 15, from: cursor, until: endHour)
        var slotIndex = 0
        var scheduled = 0
        var leftover: [String] = []

        for task in candidates {
            let minutes = max(15, ADHDCoach.calibratedMinutes(task))
            var placed = false
            while slotIndex < slots.count {
                let slot = slots[slotIndex]
                cursor = max(cursor, slot.start)
                let end = cursor.addingTimeInterval(Double(minutes * 60))
                if end <= slot.end {
                    try? CalendarService.shared.timeBlock(task, start: cursor, minutes: minutes)
                    task.dueDate = cursor
                    task.updatedAt = Date()
                    cursor = end.addingTimeInterval(10 * 60)        // 10-minute buffer between blocks
                    scheduled += 1
                    placed = true
                    break
                }
                slotIndex += 1
            }
            if !placed { leftover.append(task.title) }
        }
        if scheduled > 0 { Haptics.success() }
        return Result(scheduled: scheduled, unscheduled: leftover)
    }

    /// Removes today's Keel time blocks (keeps the tasks).
    static func clearToday(tasks: [TaskItem]) {
        let svc = CalendarService.shared
        guard let keel = try? svc.keelCalendar() else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let events = svc.store.events(matching: svc.store.predicateForEvents(withStart: start, end: start.addingTimeInterval(86_400), calendars: [keel]))
        for e in events { try? svc.store.remove(e, span: .thisEvent, commit: false) }
        try? svc.store.commit()
        for t in tasks where t.scheduledBlockStart.map({ cal.isDateInToday($0) }) == true {
            t.scheduledBlockStart = nil
            t.dueDate = start
        }
    }
}
