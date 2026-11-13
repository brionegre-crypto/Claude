import UIKit
import Foundation
import SwiftData
import WidgetKit
import Observation
import EventKit
import CoreGraphics

/// Writes the widget snapshot and asks WidgetKit to refresh. Cheap, so it runs after sync,
/// when Keel goes to the background, and after task changes.
@MainActor
enum WidgetSync {
    private static var pending: Task<Void, Never>?

    /// Coalesced: many changes in a row (checking off several tasks) write the widgets once, a moment later,
    /// so taps never wait on it.
    static func update(_ ctx: ModelContext) {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            updateNow(ctx)
        }
    }

    /// Right away: when Keel goes to the background, and from Siri/Shortcuts (which can end straight after).
    static func updateNow(_ ctx: ModelContext) {
        pending?.cancel()
        pending = nil
        let cal = Calendar.current
        let now = Date()
        let endOfDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        let all = (try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []
        let open = all.filter { !$0.isDone }
        let dueToday = open.filter { ($0.dueDate ?? .distantFuture) < endOfDay }
        let doneToday = all.filter { ($0.completedAt.map { cal.isDateInToday($0) } ?? false) || ($0.lastCompletedOccurrence.map { cal.isDateInToday($0) } ?? false) }
        let energy = EnergyLevel(rawValue: UserDefaults.standard.integer(forKey: "energy")) ?? .medium
        let next = ADHDCoach.nextThing(tasks: open, energy: energy)
        let xp = Rewards.xp(ctx: ctx)
        let lv = Rewards.level(xp)
        let rewards = (level: lv.level, progress: Double(lv.into) / Double(max(1, lv.next)), coins: max(0, xp - Rewards.spent))

        let events = CalendarService.shared.events(from: now, to: now.addingTimeInterval(36 * 3600))
            .filter { !$0.isAllDay }
            .prefix(6)
            .map { WidgetSnapshot.Event(title: $0.title ?? "Event", start: $0.startDate, end: $0.endDate, colorHex: hex($0.calendar.cgColor),
                                        joinURL: MeetingLink.find($0)?.absoluteString) }

        WidgetSnapshot(
            nextThing: next?.title,
            nextThingStep: next?.microSteps.first { !$0.done }?.text,
            events: Array(events),
            tasks: dueToday.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }.prefix(6)
                .map { WidgetSnapshot.TaskLine(title: $0.title, due: $0.dueDate, priority: $0.priority.rawValue, id: $0.id) },
            tasksLeftToday: dueToday.count,
            tasksDoneToday: doneToday.count,
            countdowns: ((try? ctx.fetch(FetchDescriptor<Countdown>(sortBy: [SortDescriptor(\.date)]))) ?? [])
                .filter { $0.daysLeft >= 0 }.prefix(5)
                .map { WidgetSnapshot.CountdownLine(title: $0.title, emoji: $0.emoji, date: $0.date) },
            habits: habitLines(ctx),
            briefing: Briefing.latest,
            nextMed: nextMed(ctx)?.name,
            nextMedAt: nextMed(ctx)?.at,
            medsLeftToday: medsLeft(ctx),
            momentum: Momentum.today(ctx: ctx).total,
            groceries: open.filter { $0.listName == MealPlanner.groceryList }.sorted { $0.createdAt < $1.createdAt }.prefix(12)
                .map { WidgetSnapshot.TaskLine(title: $0.title, due: nil, priority: 0, id: $0.id) },
            evening: open.filter { TaskMeta.isEvening($0) }.prefix(6)
                .map { WidgetSnapshot.TaskLine(title: $0.title, due: nil, priority: $0.priority.rawValue, id: $0.id) },
            deadlines: open.compactMap { t in TaskMeta.deadline(t).map { (t, $0) } }.sorted { $0.1 < $1.1 }.prefix(6)
                .map { WidgetSnapshot.TaskLine(title: $0.0.title, due: $0.1, priority: $0.0.priority.rawValue, id: $0.0.id) },
            level: rewards.level,
            levelProgress: rewards.progress,
            coins: rewards.coins,
            mail: unreadMail(ctx),
            notes: favoriteNotes(ctx)
        ).save()
        WidgetCenter.shared.reloadAllTimelines()
        WatchBridge.shared.push(ctx)          // keep Apple Watch in step
    }

    private static func unreadMail(_ ctx: ModelContext) -> [WidgetSnapshot.MailLine] {
        var d = FetchDescriptor<EmailMessage>(predicate: #Predicate { !$0.isRead && !$0.isArchived }, sortBy: [SortDescriptor(\.receivedAt, order: .reverse)])
        d.fetchLimit = 6
        return ((try? ctx.fetch(d)) ?? []).map { .init(id: $0.id, from: $0.fromName.isEmpty ? $0.from : $0.fromName, subject: $0.subject, at: $0.receivedAt) }
    }

    private static func favoriteNotes(_ ctx: ModelContext) -> [WidgetSnapshot.NoteLine] {
        var d = FetchDescriptor<Note>(predicate: #Predicate { $0.isPinned && !$0.isLocked }, sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        d.fetchLimit = 4
        return ((try? ctx.fetch(d)) ?? []).map { .init(id: $0.id, title: $0.title.isEmpty ? "Untitled" : $0.title, icon: $0.icon ?? "📄", preview: String($0.plainText.prefix(120))) }
    }

    /// Today's habits (active stacks, scheduled for today) for the interactive habits widget.
    private static func habitLines(_ ctx: ModelContext) -> [WidgetSnapshot.HabitLine] {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: Date())
        let stacks = ((try? ctx.fetch(FetchDescriptor<HabitStack>())) ?? []).filter { $0.isActive && $0.weekdays.contains(weekday) }
        let ids = Set(stacks.map(\.id))
        let doneToday = Set(((try? ctx.fetch(FetchDescriptor<HabitLog>())) ?? []).filter { cal.isDateInToday($0.day) }.map(\.habitId))
        return ((try? ctx.fetch(FetchDescriptor<Habit>())) ?? [])
            .filter { $0.stackId.map(ids.contains) ?? false }
            .sorted { $0.orderInStack < $1.orderInStack }
            .prefix(8)
            .map { WidgetSnapshot.HabitLine(id: $0.id, name: $0.name, icon: $0.icon, done: doneToday.contains($0.id)) }
    }

    /// The next untaken dose today.
    private static func nextMed(_ ctx: ModelContext) -> (name: String, at: Date)? {
        let cal = Calendar.current
        let doses = (try? ctx.fetch(FetchDescriptor<MedDose>())) ?? []
        let due = ((try? ctx.fetch(FetchDescriptor<Medication>())) ?? []).filter(\.isActive).flatMap { m in
            m.times.compactMap { slot -> (String, Date)? in
                guard MedEngine.taken(m, slot: slot, doses: doses) == nil,
                      let at = cal.date(byAdding: .minute, value: slot, to: cal.startOfDay(for: Date())) else { return nil }
                return ("\(m.name)\(m.dose.isEmpty ? "" : " \(m.dose)")", at)
            }
        }
        return due.min { $0.1 < $1.1 }.map { (name: $0.0, at: $0.1) }
    }

    private static func medsLeft(_ ctx: ModelContext) -> Int? {
        let meds = ((try? ctx.fetch(FetchDescriptor<Medication>())) ?? []).filter(\.isActive)
        guard !meds.isEmpty else { return nil }
        let doses = (try? ctx.fetch(FetchDescriptor<MedDose>())) ?? []
        return meds.flatMap { m in m.times.filter { MedEngine.taken(m, slot: $0, doses: doses) == nil } }.count
    }

    private static func hex(_ color: CGColor?) -> String {
        guard let c = color?.components, c.count >= 3 else { return "#5B8DEF" }
        return String(format: "#%02X%02X%02X", Int(c[0] * 255), Int(c[1] * 255), Int(c[2] * 255))
    }
}

/// Lets widgets and links open a specific tab (com.keel.app://tasks, …/calendar, …/focus).
@MainActor @Observable
final class AppRouter {
    static let shared = AppRouter()
    var tab: RootView.Tab = .today
    var showFocus = false
    var showCapture = false
    var openTaskId: UUID?
    var openNoteId: UUID?
    var showSearch = false
    var showSettings = false
    var showPlan = false
    var showAutopilot = false
    var showRecorder = false
    var showReview = false
    var showMoney = false
    var showLeaving = false
    var showJournal = false
    var openTool: ToolRoute?
    var showQuickOpen = false
    var showShortcuts = false
    var showVoice = false

    func handle(_ url: URL) -> Bool {
        guard url.scheme == "com.keel.app" else { return false }
        switch url.host {
        case "today": tab = .today
        case "inbox": tab = .inbox
        case "calendar": tab = .calendar
        case "tasks": tab = .tasks
        case "notes": tab = .notes
        case "focus": showFocus = true
        case "capture": showCapture = true
        case "plan": showPlan = true
        case "autopilot": showAutopilot = true
        case "search": showSearch = true
        case "settings": showSettings = true
        case "record": showRecorder = true
        case "review": showReview = true
        case "money": showMoney = true
        case "leaving": showLeaving = true
        case "journal": showJournal = true
        case "tool":       // com.keel.app://tool/vault (any tool in Today → ⊞)
            let id = url.pathComponents.dropFirst().first ?? ""
            guard HubCatalog.tool(id) != nil else { return false }
            openTool = ToolRoute(id: id)
        case "groceries": openTool = ToolRoute(id: "mealplan")
        case "open": showQuickOpen = true
        case "voice": showVoice = true
        case "inbox-capture": openTool = ToolRoute(id: "capture")
        case "note":
            if let id = url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:)) { openNoteId = id }
        case "nownext":    // Start the next task with a Now timer
            let ctx = KeelStore.container.mainContext
            let open = ((try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? [])
            let energy = EnergyLevel(rawValue: UserDefaults.standard.integer(forKey: "energy")) ?? .medium
            if let t = ADHDCoach.nextThing(tasks: open, energy: energy) { NowTimer.start(t, ctx: ctx); try? ctx.save(); showFocus = true }
        case "resume":
            // After a meeting: offer the latest save point.
            if let p = SavePoints.latest { SavePointCenter.shared.showing = p }
        case "join":
            // From the meeting Live Activity or widget: open the call itself.
            let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "url" }?.value
            if let link, let target = URL(string: link), target.scheme == "https" || target.scheme == "http" {
                UIApplication.shared.open(target)
            }
        default: return false
        }
        return true
    }
}

/// Applies taps queued by interactive widgets.
@MainActor
enum WidgetActions {
    static func applyPending(ctx: ModelContext) {
        let actions = WidgetQueue.drain()
        guard !actions.isEmpty else { return }
        for a in actions { WatchBridge.shared.apply(a) }
    }
}
