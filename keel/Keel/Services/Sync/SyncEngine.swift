import Foundation
import EventKit
import SwiftData
import BackgroundTasks
import Observation

/// Orchestrates auto-sync: all mail accounts → AI triage → tasks; Reminders ⇄ tasks; calendars.
/// Triggers: app launch, pull-to-refresh, BGAppRefresh (~15-60 min, iOS decides),
/// and silent push from the backend when Gmail Pub/Sub or Graph webhooks report new mail.
@MainActor @Observable
final class SyncEngine {
    static let shared = SyncEngine()
    static let refreshId = "com.keel.sync.refresh"

    private(set) var isSyncing = false
    private(set) var lastError: String?
    private var container: ModelContainer?

    private var storeObserver: NSObjectProtocol?
    private var worker: MailStore?

    /// One background mail worker per container, made the first time sync runs.
    private func mailStore(_ container: ModelContainer) -> MailStore {
        if let worker { return worker }
        let w = MailStore(modelContainer: container)
        worker = w
        return w
    }
    private var pendingReminderSync: Task<Void, Never>?

    func configure(container: ModelContainer) {
        self.container = container
        // Live sync: when Reminders (or Calendar) changes while Keel is open, pull it in within ~2 seconds.
        guard storeObserver == nil else { return }
        storeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { _ in
            Task { @MainActor in SyncEngine.shared.scheduleReminderSync() }
        }
    }

    func scheduleReminderSync() {
        pendingReminderSync?.cancel()
        pendingReminderSync = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await syncRemindersOnly()
        }
    }

    func syncRemindersOnly() async {
        guard let container, !isSyncing else { return }
        let ctx = container.mainContext
        let tasks = (try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []
        await CalendarService.shared.syncReminders(tasks: tasks, insert: { ctx.insert($0) }, delete: { ctx.delete($0) })
        TaskAlerts.rescheduleAll((try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? [])
        try? ctx.save()
    }

    func syncAll() async {
        guard let container, !isSyncing else { return }
        isSyncing = true; defer { isSyncing = false }
        let ctx = container.mainContext

        WidgetActions.applyPending(ctx: ctx)
        await SendLater.sendDue(ctx: ctx)
        await CalendarService.shared.requestAccess()
        await LeaveBy.refresh()
        await MeetingAutopilot.refresh()
        await LocationReminders.refresh(ctx: ctx)
        await FocusForecast.refresh(ctx: ctx)
        await TransitionAlerts.refresh()

        // 1. Mail: download on each account (network, off the main thread while waiting), then save
        //    everything in one background batch so open screens update once instead of per message.
        let accounts = (try? ctx.fetch(FetchDescriptor<MailAccount>())) ?? []
        var batches: [MailStore.Batch] = []
        for account in accounts where account.isEnabled {
            do {
                let provider = MailProviderFactory.make(for: account)
                let (msgs, cursor) = try await provider.fetchChanges(cursor: account.syncCursor)
                batches.append(MailStore.Batch(accountId: account.id, messages: msgs))
                account.syncCursor = cursor
                account.lastSyncedAt = Date()
            } catch {
                lastError = "\(account.address): \(error.localizedDescription)"
            }
        }
        let worker = mailStore(container)
        let newIds = await worker.upsert(batches)
        let fresh: [EmailMessage] = newIds.isEmpty ? [] :
            ((try? ctx.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { newIds.contains($0.id) }))) ?? [])

        // 1a. Your smart rules run first; a rule's category skips AI sorting.
        await MailRules.apply(to: fresh, accounts: accounts, ctx: ctx)
        MailScanners.backfillIfNeeded(ctx: ctx)
        MailScanners.scan(fresh, ctx: ctx)
        Task { await TripScanner.backfillIfNeeded(ctx: ctx) }   // one-time, in the background
        await TripScanner.scan(fresh, ctx: ctx)
        try? ctx.save()                                          // also stores each account's sync position, now that its mail is saved

        // 1b. Machines aren't people: automated mail the AI called important/actionable becomes an update (in the background).
        await worker.reclassifyAutomated()

        // One time: mail the old, stricter "automated" rules pushed into Updates gets sorted again.
        if !UserDefaults.standard.bool(forKey: "mail.retriage.v2") {
            let since = Date().addingTimeInterval(-14 * 86_400)
            let recent = (try? ctx.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { !$0.isArchived && $0.receivedAt > since }))) ?? []
            for e in recent where e.category == .updates && !MailNoise.isAutomated(e) { e.triagedAt = nil }
            try? ctx.save()
            UserDefaults.standard.set(true, forKey: "mail.retriage.v2")
        }

        // 2. AI triage on anything new (on-device first — free). Results are written together at the end,
        //    so the inbox re-sorts once instead of flickering through every email.
        let untriaged = (try? ctx.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { $0.triagedAt == nil }))) ?? []
        var updates: [MailStore.TriageUpdate] = []
        for email in untriaged.prefix(150) {
            guard let r = await AIRouter.shared.triage(email) else { continue }
            var category = r.category
            var priority = r.priority
            if (category == .important || category == .actionable) && MailNoise.isAutomated(email) {
                category = .updates; priority = min(r.priority, 0.3)
            }
            let wantsTask = r.taskTitle != nil && (r.category == .actionable || r.category == .important)
            updates.append(MailStore.TriageUpdate(id: email.id, category: category, priority: priority, summary: r.summary,
                                                  taskTitle: wantsTask ? r.taskTitle : nil,
                                                  dueDate: wantsTask ? r.dueDateISO.flatMap { ISO8601DateFormatter.dateOnly.date(from: $0) } : nil))
            // Write category back as a label so Gmail/Outlook (and Claude Duet's connectors) see Keel's sorting.
            if let account = accounts.first(where: { $0.id == email.accountId }) {
                try? await MailProviderFactory.make(for: account).applyLabel(email.providerMessageId, label: r.category.rawValue)
            }
            // Big first sync: save in chunks so sorting shows up as it goes.
            if updates.count >= 40 { await worker.applyTriage(updates); updates.removeAll() }
        }
        await worker.applyTriage(updates)

        // 2c. Appointments in email (doctor, dentist, interviews…) → one-tap "Add to Calendar".
        await AppointmentFinder.scan(ctx: ctx)

        // 2b. A heads-up only for VIPs and urgent mail.
        await InboxBrain.notify(fresh, ctx: ctx)

        // 2a. Replies close "remind me if no reply" follow-ups; blocked senders are archived;
        //     mail from people on your Keep in touch list counts as contact.
        FollowUps.check(ctx: ctx)
        Screener.archiveBlocked(ctx: ctx)
        KeepInTouch.updateFromMail(ctx: ctx)

        // 2b. Promise tracker: commitments you made in sent mail
        await PromiseTracker.scan(accounts: accounts, ctx: ctx)

        // 3. Apple Reminders ⇄ Keel tasks
        let tasks = (try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []
        await CalendarService.shared.syncReminders(tasks: tasks, insert: { ctx.insert($0) }, delete: { ctx.delete($0) })
        TaskAlerts.rescheduleAll((try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? [])

        // 4. Claude connector: apply what Claude queued, then publish a fresh snapshot
        await ClaudeBridge.applyQueuedActions(ctx: ctx)
        try? ctx.save()
        await HealthHabits.check(ctx: ctx)
        BreakReminders.schedule()
        await Briefing.refresh(ctx: ctx)
        await MeetingPrep.scheduleReminders(ctx: ctx)
        await Autopilot.refresh(ctx: ctx)
        await ClaudeBridge.uploadSnapshot(ctx: ctx)
        WidgetSync.update(ctx)
        SpotlightIndex.refresh(ctx)
    }

    // MARK: Background

    static func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshId, using: nil) { task in
            Task { @MainActor in
                scheduleNextRefresh()
                await SyncEngine.shared.syncAll()
                task.setTaskCompleted(success: SyncEngine.shared.lastError == nil)
            }
        }
    }

    /// Asks iPhone to wake Keel near a specific time (used by Send later).
    static func scheduleRefresh(at date: Date) { scheduleNextRefresh() }

    /// One pending request per app: ask for the sooner of 15 minutes or the next scheduled email.
    static func scheduleNextRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: refreshId)
        var next = Date(timeIntervalSinceNow: 15 * 60)
        if let ctx = shared.container?.mainContext,
           let soonest = ((try? ctx.fetch(FetchDescriptor<ScheduledMail>())) ?? []).map(\.sendAt).min() {
            next = min(next, max(Date(timeIntervalSinceNow: 60), soonest))
        }
        req.earliestBeginDate = next
        try? BGTaskScheduler.shared.submit(req)
    }
}

extension ISO8601DateFormatter {
    static let dateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; return f
    }()
}
