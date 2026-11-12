import Foundation
import SwiftData

/// Mail database work done off the main thread, with its own context on the shared store.
/// Sync used to insert and update messages one by one on the main thread, so every new email
/// (and every AI-sorted one) redrew the open screens mid-animation. Now each step is one background
/// batch and one save; the screens pick up the result in a single update.
@ModelActor
actor MailStore {
    struct Batch: Sendable {
        var accountId: String
        var messages: [FetchedMessage]
    }

    struct TriageUpdate: Sendable {
        var id: String
        var category: TriageCategory
        var priority: Double
        var summary: String
        var taskTitle: String?
        var dueDate: Date?
    }

    /// Adds new messages and refreshes read/starred on ones Keel already has. Returns the new message ids.
    func upsert(_ batches: [Batch]) -> [String] {
        var newIds: [String] = []
        for b in batches where !b.messages.isEmpty {
            let incoming = b.messages.map { "\(b.accountId)|\($0.providerId)" }
            let existing = (try? modelContext.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { incoming.contains($0.id) }))) ?? []
            let byId = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var seen = Set<String>()
            for m in b.messages {
                let id = "\(b.accountId)|\(m.providerId)"
                guard seen.insert(id).inserted else { continue }
                if let e = byId[id] {
                    // Already synced: update state only, keep Keel's AI sorting and summary.
                    if e.isRead != m.isRead { e.isRead = m.isRead }
                    if e.isStarred != m.isStarred { e.isStarred = m.isStarred }
                } else {
                    let e = EmailMessage(accountId: b.accountId, fetched: m)
                    modelContext.insert(e)
                    newIds.append(e.id)
                }
            }
        }
        try? modelContext.save()
        return newIds
    }

    /// Machines aren't people: automated mail sorted as important/actionable becomes an update.
    func reclassifyAutomated() {
        let open = (try? modelContext.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { !$0.isArchived }))) ?? []
        var changed = false
        for e in open where (e.category == .important || e.category == .actionable) && MailNoise.isAutomated(e) {
            e.category = .updates
            e.priorityScore = min(e.priorityScore, 0.3)
            changed = true
        }
        if changed { try? modelContext.save() }
    }

    /// Writes a whole round of AI sorting at once.
    func applyTriage(_ updates: [TriageUpdate]) {
        guard !updates.isEmpty else { return }
        let ids = updates.map(\.id)
        let emails = (try? modelContext.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
        let byId = Dictionary(emails.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let now = Date()
        for u in updates {
            guard let e = byId[u.id] else { continue }
            e.category = u.category
            e.priorityScore = u.priority
            e.aiSummary = u.summary
            e.triagedAt = now
            if let t = u.taskTitle {
                e.extractedTaskTitle = t
                e.extractedDueDate = u.dueDate
            }
        }
        try? modelContext.save()
    }
}
