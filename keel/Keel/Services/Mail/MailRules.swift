import Foundation
import SwiftData

/// Smart email rules: "If from contains X → archive / star / mark read / file under / make a task".
/// Applied to newly synced mail before AI sorting, so a rule's category wins and saves an AI call.
@MainActor
enum MailRules {
    enum Field: String, CaseIterable, Identifiable {
        case from, subject, any
        var id: String { rawValue }
        var label: String { switch self { case .from: "Sender"; case .subject: "Subject"; case .any: "Sender, subject or body" } }
    }

    static let actions: [(id: String, label: String, icon: String)] = [
        ("archive", "Archive", "archivebox"),
        ("star", "Star", "star"),
        ("read", "Mark as read", "envelope.open"),
        ("task", "Make a task", "checklist"),
    ] + TriageCategory.allCases.map { ("category:\($0.rawValue)", "File under \($0.rawValue.capitalized)", "tray") }

    static func label(for action: String) -> String { actions.first { $0.id == action }?.label ?? action }

    static func matches(_ r: MailRule, _ e: EmailMessage) -> Bool {
        let needle = r.contains.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return false }
        let hay: String
        switch Field(rawValue: r.field) ?? .any {
        case .from: hay = e.from + " " + e.fromName
        case .subject: hay = e.subject
        case .any: hay = e.from + " " + e.fromName + " " + e.subject + " " + e.snippet
        }
        return hay.lowercased().contains(needle)
    }

    /// Runs every enabled rule on the given new messages. Server-side changes go through the provider.
    static func apply(to emails: [EmailMessage], accounts: [MailAccount], ctx: ModelContext) async {
        let rules = ((try? ctx.fetch(FetchDescriptor<MailRule>())) ?? []).filter(\.isOn)
        guard !rules.isEmpty else { return }
        for e in emails {
            for r in rules where matches(r, e) {
                r.timesApplied += 1
                let provider = accounts.first { $0.id == e.accountId }.map(MailProviderFactory.make)
                let id = e.providerMessageId
                switch r.action {
                case "archive":
                    e.isArchived = true
                    try? await provider?.archive(id)
                case "star":
                    e.isStarred = true
                    try? await provider?.setStarred(id, starred: true)
                case "read":
                    e.isRead = true
                    try? await provider?.markRead(id, read: true)
                case "task":
                    let t = TaskItem(title: e.subject.isEmpty ? "Email from \(e.fromName)" : e.subject)
                    t.sourceEmailId = e.id
                    ctx.insert(t)
                default:
                    if r.action.hasPrefix("category:"),
                       let c = TriageCategory(rawValue: String(r.action.dropFirst("category:".count))) {
                        e.category = c
                        e.priorityScore = c == .important ? 0.6 : 0.2
                        e.aiSummary = e.aiSummary ?? e.snippet
                        e.triagedAt = Date()          // a rule decided: skip AI sorting
                    }
                }
            }
        }
        try? ctx.save()
    }
}
