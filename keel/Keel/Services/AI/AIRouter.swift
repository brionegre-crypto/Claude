import Foundation
import FoundationModels

/// Keel's AI runs on Apple Intelligence: on-device, free and private. Claude is an optional add-on,
/// used only if you connect a Keel server (Settings → Claude AI). Every feature asks the router.
@MainActor
final class AIRouter {
    static let shared = AIRouter()

    let onDevice = OnDeviceAI()
    let cloud = CloudAI()

    /// User setting: never send content off the phone.
    var privateMode: Bool {
        get { UserDefaults.standard.bool(forKey: "ai.privateMode") }
        set { UserDefaults.standard.set(newValue, forKey: "ai.privateMode") }
    }

    /// Claude is used only when a server is connected and Private mode is off.
    var cloudEnabled: Bool { !privateMode && (DirectAI.isConfigured || KeelServer.isConfigured) }
    /// You chose Claude / ChatGPT / Gemini in Settings: use it first for writing and thinking jobs.
    var preferCloud: Bool { !privateMode && DirectAI.isConfigured }

    var onDeviceAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    // MARK: Everything tries Apple Intelligence first; Claude only if connected

    func triage(_ email: EmailMessage) async -> TriageResult? {
        if onDeviceAvailable, let r = try? await onDevice.triage(email) { return r }
        if cloudEnabled, let r = try? await cloud.triage(email) { return r }
        return HeuristicTriage.triage(email)
    }

    func summarize(_ text: String) async -> String? {
        if preferCloud, let s = try? await cloud.summarize(text) { return s }
        if onDeviceAvailable, let s = try? await onDevice.summarize(String(text.prefix(12_000))) { return s }
        return cloudEnabled ? try? await cloud.summarize(text) : nil
    }

    /// Promise tracker: free keyword pre-filter, then Apple Intelligence; keyword fallback otherwise.
    func extractPromises(body: String, sentAt: Date) async -> [PromiseCandidate] {
        guard ADHDCoach.looksLikePromise(body) else { return [] }        // skips ~90% of sent mail
        if onDeviceAvailable, let r = try? await onDevice.extractPromises(body: body, sentAt: sentAt) { return r }
        if cloudEnabled, let r = try? await cloud.extractPromises(body: body, sentAt: sentAt) { return r }
        return HeuristicPromises.extract(body)
    }

    func planDay(context: DayContext) async -> DayPlan? {
        // With a Claude server connected, its stronger planning is used first.
        if cloudEnabled, let plan = try? await cloud.planDay(context) { return plan }
        return onDeviceAvailable ? try? await onDevice.planDay(context) : nil
    }

    func draftReply(to email: EmailMessage, intent: String) async -> String? {
        if preferCloud, let d = try? await cloud.draftReply(email, intent: intent) { return d }
        if onDeviceAvailable, let d = try? await onDevice.draftReply(email, intent: intent) { return d }
        return cloudEnabled ? try? await cloud.draftReply(email, intent: intent) : nil
    }

    /// Three one-tap reply ideas for an email, cached on the message.
    func replyIdeas(for email: EmailMessage) async -> [String] {
        if let cached = email.suggestedReply, !cached.isEmpty { return cached.components(separatedBy: "|") }
        guard onDeviceAvailable, let ideas = try? await onDevice.replyIdeas(email), !ideas.isEmpty else { return [] }
        email.suggestedReply = ideas.prefix(3).map { $0.replacingOccurrences(of: "|", with: "/") }.joined(separator: "|")
        return Array(ideas.prefix(3))
    }

    /// "Break into tiny steps". Without any AI, a simple starter plan still beats a blank page.
    func breakDown(_ task: String, minutesAvailable: Int?) async -> [MicroStep] {
        if preferCloud, let steps = try? await cloud.breakDown(task, minutesAvailable: minutesAvailable), !steps.isEmpty { return steps }
        if onDeviceAvailable, let steps = try? await onDevice.breakDown(task, minutesAvailable: minutesAvailable), !steps.isEmpty { return steps }
        if cloudEnabled, let steps = try? await cloud.breakDown(task, minutesAvailable: minutesAvailable) { return steps }
        return [
            MicroStep(text: "Open what you need for “\(task)”", minutes: 2),
            MicroStep(text: "Write the very first sentence or action", minutes: 5),
            MicroStep(text: "Do 10 minutes, then decide the next step", minutes: 10),
        ]
    }
}

// MARK: - Shared result types

struct TriageResult: Codable {
    var category: TriageCategory
    var priority: Double
    var summary: String
    var taskTitle: String?
    var dueDateISO: String?
}

struct DayContext: Codable {
    var now: String
    var events: [String]
    var tasks: [String]
    var importantEmails: [String]
    var habitStacks: [String]
    var weather: String = ""            // e.g. "18°, cloudy, rain likely from 3 PM"
    var idealWeek: [String] = []        // today's blocks from the ideal week
}

struct DayPlan: Codable {
    struct Block: Codable, Identifiable {
        var id: String { start + title }
        var start: String     // "09:30"
        var end: String
        var title: String
        var kind: String      // focus | meeting | email | habit | break | shutdown
    }
    var headline: String
    var blocks: [Block]
    var topThree: [String]
}

struct PromiseCandidate: Codable {
    var promise: String
    var quote: String
    var dueDateISO: String?
}

/// Private-mode fallback: the sentence containing the promise phrase becomes the promise.
enum HeuristicPromises {
    static func extract(_ body: String) -> [PromiseCandidate] {
        body.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { ADHDCoach.looksLikePromise($0) && $0.count < 200 }
            .prefix(3)
            .map { PromiseCandidate(promise: $0, quote: $0, dueDateISO: nil) }
    }
}

/// Zero-cost fallback for old iPhones in private mode.
enum HeuristicTriage {
    static func triage(_ e: EmailMessage) -> TriageResult {
        let s = (e.subject + " " + e.snippet).lowercased()
        let cat: TriageCategory =
            s.contains("unsubscribe") ? .newsletters :
            s.contains("invitation") || s.contains("meeting") ? .calendar :
            s.contains("receipt") || s.contains("order") || s.contains("shipped") ? .updates :
            s.contains("% off") || s.contains("sale") ? .promotions : .important
        return TriageResult(category: cat, priority: cat == .important ? 0.6 : 0.2, summary: e.snippet)
    }
}
