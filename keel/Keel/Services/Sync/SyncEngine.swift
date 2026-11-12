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

        // 1. Mail, all accounts in parallel-ish (sequential per account keeps rate limits sane)
        let accounts = (try? ctx.fetch(FetchDescriptor<MailAccount>())) ?? []
        var fresh: [EmailMessage] = []
        for account in accounts where account.isEnabled {
            do {
                let provider = MailProviderFactory.make(for: account)
                let (msgs, cursor) = try await provider.fetchChanges(cursor: account.syncCursor)
                for m in msgs {
                    let id = "\(account.id)|\(m.providerId)"
                    if let existing = try? ctx.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { $0.id == id })).first {
                        // Already synced: update state only, keep Keel's AI sorting and summary.
                        existing.isRead = m.isRead
                        existing.isStarred = m.isStarred
                    } else {
                        let e = EmailMessage(accountId: account.id, fetched: m)
                        ctx.insert(e)
                        fresh.append(e)
                    }
                }
                account.syncCursor = cursor
                account.lastSyncedAt = Date()
            } catch {
                lastError = "\(account.address): \(error.localizedDescription)"
            }
        }
        try? ctx.save()

        // 1a. Your smart rules run first; a rule's category skips AI sorting.
        await MailRules.apply(to: fresh, accounts: accounts, ctx: ctx)
        MailScanners.backfillIfNeeded(ctx: ctx)
        MailScanners.scan(fresh, ctx: ctx)

        // 2. AI triage on anything new (on-device first — free)
        let untriaged = (try? ctx.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { $0.triagedAt == nil }))) ?? []
        for email in untriaged.prefix(150) {
            guard let r = await AIRouter.shared.triage(email) else { continue }
            email.category = r.category
            email.priorityScore = r.priority
            email.aiSummary = r.summary
            email.triagedAt = Date()
            if let title = r.taskTitle, r.category == .actionable || r.category == .important {
                email.extractedTaskTitle = title
                email.extractedDueDate = r.dueDateISO.flatMap { ISO8601DateFormatter.dateOnly.date(from: $0) }
            }
            // Write category back as a label so Gmail/Outlook (and Claude Duet's connectors) see Keel's sorting.
            if let account = accounts.first(where: { $0.id == email.accountId }) {
                try? await MailProviderFactory.make(for: account).applyLabel(email.providerMessageId, label: r.category.rawValue)
            }
        }

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
        await Briefing.refresh(ctx: ctx)
        await MeetingPrep.scheduleReminders(ctx: ctx)
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
