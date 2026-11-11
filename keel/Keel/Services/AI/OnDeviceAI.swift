import Foundation
import FoundationModels

/// Apple Intelligence via the Foundation Models framework (iOS 26+). Runs fully on-device, no cost.
@MainActor
final class OnDeviceAI {

    @Generable
    enum Bucket {
        case important, actionable, calendar, updates, newsletters, promotions, lowPriority
    }

    @Generable
    struct Triage {
        @Guide(description: "Which inbox bucket this email belongs in")
        var bucket: Bucket
        @Guide(description: "How urgently the user should look at this, from 0 to 10", .range(0...10))
        var urgency: Int
        @Guide(description: "One sentence, max 20 words, saying what the sender wants")
        var summary: String
        @Guide(description: "A short imperative task title if the email asks the user to do something, otherwise empty")
        var taskTitle: String
        @Guide(description: "Deadline as YYYY-MM-DD if one is stated, otherwise empty")
        var dueDate: String
    }

    @Generable
    struct PlanBlock {
        @Guide(description: "24h start time HH:mm") var start: String
        @Guide(description: "24h end time HH:mm") var end: String
        var title: String
        @Guide(description: "focus, meeting, email, habit, break or shutdown") var kind: String
    }

    @Generable
    struct Plan {
        var headline: String
        @Guide(description: "Exactly three most important outcomes for today") var topThree: [String]
        var blocks: [PlanBlock]
    }

    private let triageInstructions = """
    You sort email for a busy professional. Personal messages from real people and anything \
    with a deadline are important or actionable. Automated mail is updates, newsletters or promotions.
    """

    func triage(_ e: EmailMessage) async throws -> TriageResult {
        // Fresh session per email: the on-device context window is small.
        let session = LanguageModelSession(instructions: triageInstructions)
        let prompt = """
        From: \(e.fromName) <\(e.from)>
        Subject: \(e.subject)
        Body: \(e.bodyPlain.prefix(3_000))
        """
        let t = try await session.respond(to: prompt, generating: Triage.self).content
        return TriageResult(
            category: Self.map(t.bucket),
            priority: Double(t.urgency) / 10,
            summary: t.summary,
            taskTitle: t.taskTitle.isEmpty ? nil : t.taskTitle,
            dueDateISO: t.dueDate.isEmpty ? nil : t.dueDate)
    }

    func summarize(_ text: String) async throws -> String {
        let session = LanguageModelSession(instructions: "Summarize in at most 3 short bullet points.")
        return try await session.respond(to: text).content
    }

    func planDay(_ c: DayContext) async throws -> DayPlan {
        let session = LanguageModelSession(instructions: """
        Build a realistic time-blocked plan for the rest of today. Never overlap fixed events. \
        Put deep focus in the longest free gaps, batch email twice, and end with a shutdown block.
        """)
        let prompt = """
        Now: \(c.now)
        Events: \(c.events.joined(separator: "; "))
        Tasks: \(c.tasks.prefix(15).joined(separator: "; "))
        Habit stacks: \(c.habitStacks.joined(separator: "; "))
        """
        let p = try await session.respond(to: prompt, generating: Plan.self).content
        return DayPlan(headline: p.headline,
                       blocks: p.blocks.map { .init(start: $0.start, end: $0.end, title: $0.title, kind: $0.kind) },
                       topThree: p.topThree)
    }

    func draftReply(_ e: EmailMessage, intent: String) async throws -> String {
        let session = LanguageModelSession(instructions: "Write a concise, friendly email reply. Body only, no subject.")
        return try await session.respond(to: "Original from \(e.fromName): \(e.bodyPlain.prefix(2_500))\n\nMy intent: \(intent)").content
    }

    private static func map(_ b: Bucket) -> TriageCategory {
        switch b {
        case .important: .important
        case .actionable: .actionable
        case .calendar: .calendar
        case .updates: .updates
        case .newsletters: .newsletters
        case .promotions: .promotions
        case .lowPriority: .lowPriority
        }
    }
}
