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
        Ideal day (follow it where events allow): \(c.idealWeek.joined(separator: "; "))
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

    @Generable
    struct FoundPromise {
        @Guide(description: "Short imperative of what the writer committed to do, e.g. 'Send the Q3 deck'")
        var promise: String
        @Guide(description: "The exact sentence from the email that contains the commitment")
        var quote: String
        @Guide(description: "Deadline as YYYY-MM-DD resolved against the sent date, or empty if none stated")
        var dueDate: String
    }

    @Generable
    struct PromiseScan {
        @Guide(description: "Commitments the WRITER made to do something later. Empty if none.", .maximumCount(5))
        var promises: [FoundPromise]
    }

    func extractPromises(body: String, sentAt: Date) async throws -> [PromiseCandidate] {
        let session = LanguageModelSession(instructions: Self.promiseInstructions)
        let prompt = "Sent on \(sentAt.formatted(.iso8601.year().month().day())) (\(sentAt.formatted(.dateTime.weekday(.wide))))\n\n\(body.prefix(3_000))"
        let r = try await session.respond(to: prompt, generating: PromiseScan.self).content
        return r.promises.map { PromiseCandidate(promise: $0.promise, quote: $0.quote, dueDateISO: $0.dueDate.isEmpty ? nil : $0.dueDate) }
    }

    static let promiseInstructions = """
    You read an email the user SENT and list commitments the user made to do something in the future: \
    "I'll send it Friday", "Let me check and get back to you", "I will review by EOD". \
    Ignore requests to others, things already done, pleasantries ("let me know"), and offers ("happy to help"). \
    Resolve relative dates ("Friday", "tomorrow", "next week" = the following Monday) against the sent date.
    """

    @Generable
    struct Step {
        @Guide(description: "A concrete physical action starting with a verb, e.g. 'Open the budget spreadsheet'")
        var text: String
        @Guide(description: "Minutes this step takes", .range(2...10))
        var minutes: Int
    }

    @Generable
    struct Steps {
        @Guide(description: "3 to 8 tiny next actions in order; the first must be laughably easy to start", .maximumCount(8))
        var steps: [Step]
    }

    func breakDown(_ task: String, minutesAvailable: Int?) async throws -> [MicroStep] {
        let session = LanguageModelSession(instructions: Prompts.breakdown)
        let prompt = "Task: \(task)\nTime I have: \(minutesAvailable.map { "\($0) min" } ?? "unknown")"
        return try await session.respond(to: prompt, generating: Steps.self).content.steps
            .map { MicroStep(text: $0.text, minutes: $0.minutes) }
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
