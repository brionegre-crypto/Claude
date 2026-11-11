import Foundation
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

    func configure(container: ModelContainer) { self.container = container }

    func syncAll() async {
        guard let container, !isSyncing else { return }
        isSyncing = true; defer { isSyncing = false }
        let ctx = container.mainContext

        await CalendarService.shared.requestAccess()

        // 1. Mail, all accounts in parallel-ish (sequential per account keeps rate limits sane)
        let accounts = (try? ctx.fetch(FetchDescriptor<MailAccount>())) ?? []
        for account in accounts where account.isEnabled {
            do {
                let provider = MailProviderFactory.make(for: account)
                let (msgs, cursor) = try await provider.fetchChanges(cursor: account.syncCursor)
                for m in msgs {
                    let e = EmailMessage(accountId: account.id, providerMessageId: m.providerId, threadId: m.threadId,
                                         from: m.from, fromName: m.fromName, subject: m.subject, snippet: m.snippet,
                                         bodyPlain: m.body, receivedAt: m.date, isRead: m.isRead)
                    ctx.insert(e)
                }
                account.syncCursor = cursor
                account.lastSyncedAt = Date()
            } catch {
                lastError = "\(account.address): \(error.localizedDescription)"
            }
        }
        try? ctx.save()

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

        // 3. Apple Reminders ⇄ Keel tasks
        let tasks = (try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []
        await CalendarService.shared.syncReminders(tasks: tasks) { ctx.insert($0) }

        // 4. Claude connector: apply what Claude queued, then publish a fresh snapshot
        await ClaudeBridge.applyQueuedActions(ctx: ctx)
        try? ctx.save()
        await ClaudeBridge.uploadSnapshot(ctx: ctx)
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

    static func scheduleNextRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: refreshId)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }
}

extension ISO8601DateFormatter {
    static let dateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; return f
    }()
}
