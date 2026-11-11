import Foundation

/// Calls Claude through the Keel backend (backend/ — it holds the Anthropic API key, enforces
/// per-user quotas, and picks the model). The app never ships an API key.
@MainActor
final class CloudAI {
    private let endpoint: URL = {
        let s = Bundle.main.object(forInfoDictionaryKey: "KeelAIProxyURL") as? String ?? ""
        return URL(string: s) ?? URL(string: "https://invalid.local")!
    }()

    enum CloudError: Error { case http(Int), refused, badOutput }

    /// `task` tells the backend which model/effort to use (see backend/src/ai.ts ROUTES).
    private func call<T: Decodable>(task: String, system: String, user: String, schema: [String: Any], as: T.Type) async throws -> T {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = KeychainStore.read("keel.session") { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "task": task, "system": system, "user": user, "schema": schema,
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw CloudError.http(code) }
        // Backend returns {"stop_reason": "...", "json": {...}}
        struct Envelope<U: Decodable>: Decodable { let stop_reason: String; let json: U? }
        let env = try JSONDecoder().decode(Envelope<T>.self, from: data)
        if env.stop_reason == "refusal" { throw CloudError.refused }
        guard let out = env.json else { throw CloudError.badOutput }
        return out
    }

    func triage(_ e: EmailMessage) async throws -> TriageResult {
        try await call(task: "triage",
                       system: "Classify the email for a busy professional with ADHD. Be decisive.",
                       user: "From: \(e.fromName) <\(e.from)>\nSubject: \(e.subject)\n\n\(e.bodyPlain.prefix(8_000))",
                       schema: Schemas.triage, as: TriageResult.self)
    }

    func summarize(_ text: String) async throws -> String {
        struct S: Decodable { let summary: String }
        return try await call(task: "summarize", system: "Summarize in at most 3 short bullets.",
                              user: text, schema: Schemas.summary, as: S.self).summary
    }

    func planDay(_ c: DayContext) async throws -> DayPlan {
        let ctx = String(data: try JSONEncoder().encode(c), encoding: .utf8) ?? "{}"
        return try await call(task: "plan_day", system: Prompts.planner, user: ctx, schema: Schemas.dayPlan, as: DayPlan.self)
    }

    func draftReply(_ e: EmailMessage, intent: String) async throws -> String {
        struct D: Decodable { let body: String }
        return try await call(task: "draft_reply",
                              system: "Write a concise reply in the user's voice. Body only.",
                              user: "Original from \(e.fromName):\n\(e.bodyPlain.prefix(10_000))\n\nIntent: \(intent)",
                              schema: Schemas.draft, as: D.self).body
    }

    func breakDown(_ task: String, minutesAvailable: Int?) async throws -> [MicroStep] {
        struct R: Decodable { struct Step: Decodable { let text: String; let minutes: Int }; let steps: [Step] }
        let r = try await call(task: "break_down", system: Prompts.breakdown,
                               user: "Task: \(task)\nTime I have: \(minutesAvailable.map { "\($0) min" } ?? "unknown")",
                               schema: Schemas.steps, as: R.self)
        return r.steps.map { MicroStep(text: $0.text, minutes: $0.minutes) }
    }
}

enum Prompts {
    static let planner = """
    You plan the rest of the user's day. They have ADHD: protect one long focus block, put the \
    hardest task where their energy is highest (usually late morning), batch email into two short \
    windows, add 5-minute transition buffers before meetings, include their habit stacks at their \
    anchors, and end with a shutdown ritual. Max 3 "top three" outcomes. Never overlap fixed events. \
    Be realistic: plan at most 70% of free time.
    """
    static let breakdown = """
    Break the task into 3-8 concrete physical next actions, each 2-10 minutes. The first step must \
    be laughably easy to start (e.g. "Open the doc"). Use verbs. No vague steps like "work on".
    """
}

/// JSON Schemas for structured outputs (output_config.format on the backend).
enum Schemas {
    static let categories = TriageCategory.allCases.map(\.rawValue)
    static let triage: [String: Any] = [
        "type": "object", "additionalProperties": false,
        "required": ["category", "priority", "summary", "taskTitle", "dueDateISO"],
        "properties": [
            "category": ["type": "string", "enum": categories],
            "priority": ["type": "number"],
            "summary": ["type": "string"],
            "taskTitle": ["type": ["string", "null"]],
            "dueDateISO": ["type": ["string", "null"]],
        ],
    ]
    static let summary: [String: Any] = [
        "type": "object", "additionalProperties": false, "required": ["summary"],
        "properties": ["summary": ["type": "string"]],
    ]
    static let draft: [String: Any] = [
        "type": "object", "additionalProperties": false, "required": ["body"],
        "properties": ["body": ["type": "string"]],
    ]
    static let steps: [String: Any] = [
        "type": "object", "additionalProperties": false, "required": ["steps"],
        "properties": ["steps": ["type": "array", "items": [
            "type": "object", "additionalProperties": false, "required": ["text", "minutes"],
            "properties": ["text": ["type": "string"], "minutes": ["type": "integer"]],
        ]]],
    ]
    static let dayPlan: [String: Any] = [
        "type": "object", "additionalProperties": false, "required": ["headline", "blocks", "topThree"],
        "properties": [
            "headline": ["type": "string"],
            "topThree": ["type": "array", "items": ["type": "string"]],
            "blocks": ["type": "array", "items": [
                "type": "object", "additionalProperties": false,
                "required": ["start", "end", "title", "kind"],
                "properties": [
                    "start": ["type": "string"], "end": ["type": "string"], "title": ["type": "string"],
                    "kind": ["type": "string", "enum": ["focus", "meeting", "email", "habit", "break", "shutdown"]],
                ],
            ]],
        ],
    ]
}
