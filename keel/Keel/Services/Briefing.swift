import Foundation
import SwiftData
import UserNotifications
import FoundationModels

/// Morning briefing: one notification at your chosen time with the day's shape —
/// first event, how many meetings, top tasks, meds and weather. Rebuilt on every sync so it stays fresh.
@MainActor
enum Briefing {
    static let onKey = "briefing.on", minuteKey = "briefing.minute", textKey = "briefing.text"
    static var isOn: Bool { UserDefaults.standard.object(forKey: onKey) as? Bool ?? true }
    static var minute: Int { UserDefaults.standard.object(forKey: minuteKey) as? Int ?? 450 }   // 7:30 AM
    /// The most recent briefing text (shown on Today, the widget and Apple Watch).
    static var latest: String? { UserDefaults.standard.string(forKey: textKey) }

    /// The next morning the briefing will fire for.
    static func nextFire(now: Date = Date()) -> Date {
        let cal = Calendar.current
        let today = cal.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: now)!
        return today > now ? today : cal.date(byAdding: .day, value: 1, to: today)!
    }

    static func refresh(ctx: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        guard isOn else { center.removePendingNotificationRequests(withIdentifiers: ["briefing"]); return }
        let fire = nextFire()
        let facts = facts(for: fire, ctx: ctx)
        var text = facts.joined(separator: " ")
        // Apple Intelligence rewrites it warmly, at most every 2 hours (it's free, but not instant).
        let last = UserDefaults.standard.double(forKey: "briefing.polishedAt")
        if AIRouter.shared.onDeviceAvailable, Date().timeIntervalSince1970 - last > 7200 {
            let session = LanguageModelSession(instructions: "Rewrite these facts as a warm, upbeat morning briefing for someone with ADHD. Two short sentences, under 45 words. Keep every time and name. No greeting like 'Good morning'.")
            if let r = try? await session.respond(to: text).content, !r.isEmpty {
                text = r
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "briefing.polishedAt")
            }
        }
        UserDefaults.standard.set(text, forKey: textKey)
        let c = UNMutableNotificationContent()
        c.title = "☀️ " + (Calendar.current.isDateInToday(fire) ? "Your day" : "Tomorrow") + " at a glance"
        c.body = text
        c.sound = .default
        c.userInfo = ["deeplink": "com.keel.app://today"]
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        try? await center.add(UNNotificationRequest(identifier: "briefing", content: c,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }

    static func facts(for day: Date, ctx: ModelContext) -> [String] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day), end = cal.date(byAdding: .day, value: 1, to: start)!
        var out: [String] = []
        let events = CalendarService.shared.events(from: start, to: end).filter { !$0.isAllDay }
        if let first = events.first {
            out.append("First up: \(first.title ?? "an event") at \(first.startDate.formatted(date: .omitted, time: .shortened)).")
            if events.count > 1 { out.append("\(events.count) events in total.") }
        } else {
            out.append("No meetings: a great day for deep work.")
        }
        let tasks = ((try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? [])
            .filter { !$0.isDone && !$0.isSomeday && ($0.dueDate ?? .distantFuture) < end }
            .sorted { ($0.priority.rawValue, $1.dueDate ?? .distantFuture) > ($1.priority.rawValue, $0.dueDate ?? .distantFuture) }
        if !tasks.isEmpty {
            out.append("\(tasks.count) task\(tasks.count == 1 ? "" : "s") due, starting with “\(tasks[0].title)”.")
        }
        let meds = ((try? ctx.fetch(FetchDescriptor<Medication>())) ?? []).filter(\.isActive)
        if let m = meds.first, let t = m.times.min() {
            out.append("Meds: \(m.name) at \(MedEngine.timeLabel(t)).")
        }
        let important = ((try? ctx.fetch(FetchDescriptor<EmailMessage>())) ?? [])
            .filter { !$0.isRead && !$0.isArchived && $0.category == .important && !MailNoise.isAutomated($0) }.count
        if important > 0 { out.append("\(important) important email\(important == 1 ? "" : "s") waiting.") }
        if cal.isDateInToday(day), let w = KeelWeather.shared.today { out.append("Weather: \(w.plannerLine).") }
        return out
    }
}
