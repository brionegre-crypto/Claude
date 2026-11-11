import Foundation
import FoundationModels

/// Hybrid AI: Apple Intelligence (on-device, free, private) for high-volume work,
/// Claude via your backend for heavy reasoning. Every feature asks the router, never a model directly.
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

    var onDeviceAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    // MARK: High-volume → on-device first

    func triage(_ email: EmailMessage) async -> TriageResult? {
        if onDeviceAvailable, let r = try? await onDevice.triage(email) { return r }
        guard !privateMode else { return HeuristicTriage.triage(email) }
        return (try? await cloud.triage(email)) ?? HeuristicTriage.triage(email)
    }

    func summarize(_ text: String) async -> String? {
        if onDeviceAvailable, text.count < 12_000, let s = try? await onDevice.summarize(text) { return s }
        guard !privateMode else { return nil }
        return try? await cloud.summarize(text)
    }

    // MARK: Heavy reasoning → cloud (falls back to on-device in private mode)

    func planDay(context: DayContext) async -> DayPlan? {
        if !privateMode, let plan = try? await cloud.planDay(context) { return plan }
        return onDeviceAvailable ? try? await onDevice.planDay(context) : nil
    }

    func draftReply(to email: EmailMessage, intent: String) async -> String? {
        if !privateMode, let d = try? await cloud.draftReply(email, intent: intent) { return d }
        return onDeviceAvailable ? try? await onDevice.draftReply(email, intent: intent) : nil
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
