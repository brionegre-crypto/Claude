import Foundation

/// Optional "bring your own key": use Claude, ChatGPT (OpenAI) or Gemini for Keel's heavier AI jobs.
/// Keys live only in this iPhone's Keychain, and requests go straight from the phone to that company.
/// Apple Intelligence stays the free default; this is used only when the person picks a provider and adds a key.
enum AIProvider: String, CaseIterable, Identifiable {
    case apple, claude, openai, gemini
    var id: String { rawValue }

    var name: String {
        switch self { case .apple: "Apple Intelligence"; case .claude: "Claude"; case .openai: "ChatGPT (OpenAI)"; case .gemini: "Gemini" }
    }
    var company: String {
        switch self { case .apple: "Apple"; case .claude: "Anthropic"; case .openai: "OpenAI"; case .gemini: "Google" }
    }
    /// Model used unless the person types another one in Settings.
    var defaultModel: String {
        switch self { case .apple: ""; case .claude: "claude-opus-5-5"; case .openai: "gpt-4.1-mini"; case .gemini: "gemini-2.5-flash" }
    }
    var keyPage: URL? {
        switch self {
        case .apple: nil
        case .claude: URL(string: "https://console.anthropic.com/settings/keys")
        case .openai: URL(string: "https://platform.openai.com/api-keys")
        case .gemini: URL(string: "https://aistudio.google.com/apikey")
        }
    }
    var keychainKey: String { "ai.key.\(rawValue)" }
}

enum DirectAI {
    enum Failure: LocalizedError {
        case http(Int, String), refused, empty
        var errorDescription: String? {
            switch self {
            case .http(let code, let msg): "The AI service answered \(code): \(msg.prefix(160))"
            case .refused: "The model declined this request."
            case .empty: "The model returned nothing usable."
            }
        }
    }

    static var provider: AIProvider {
        AIProvider(rawValue: UserDefaults.standard.string(forKey: "ai.provider") ?? "apple") ?? .apple
    }
    static func model(for p: AIProvider) -> String {
        let custom = UserDefaults.standard.string(forKey: "ai.model.\(p.rawValue)")?.trimmingCharacters(in: .whitespaces) ?? ""
        return custom.isEmpty ? p.defaultModel : custom
    }
    static func key(for p: AIProvider) -> String? {
        guard let k = KeychainStore.read(p.keychainKey), !k.isEmpty else { return nil }
        return k
    }
    /// True when a non-Apple provider is chosen and has a key.
    static var isConfigured: Bool { provider != .apple && key(for: provider) != nil }

    /// Effort/size per Keel task, mirroring the server routes.
    private static func budget(_ task: String) -> (maxTokens: Int, effort: String) {
        switch task {
        case "plan_day": (8_192, "high")
        case "draft_reply", "break_down": (4_096, "medium")
        default: (1_024, "low")
        }
    }

    /// Returns the model's JSON output (matching `schema`) as Data.
    static func json(task: String, system: String, user: String, schema: [String: Any],
                     provider p: AIProvider = DirectAI.provider, key: String? = nil, model: String? = nil) async throws -> Data {
        guard let apiKey = key ?? self.key(for: p) else { throw Failure.empty }
        let m = model ?? self.model(for: p)
        switch p {
        case .apple: throw Failure.empty
        case .claude: return try await claude(task: task, system: system, user: user, schema: schema, key: apiKey, model: m)
        case .openai: return try await openAI(system: system, user: user, schema: schema, key: apiKey, model: m)
        case .gemini: return try await gemini(system: system, user: user, schema: schema, key: apiKey, model: m)
        }
    }

    // MARK: Claude (Messages API, structured outputs)

    private static func claude(task: String, system: String, user: String, schema: [String: Any], key: String, model: String) async throws -> Data {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        let b = budget(task)
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_tokens": b.maxTokens,
            "system": system,
            "fallbacks": "default",            // if a safety check declines, a suitable model answers instead
            "output_config": ["effort": b.effort, "format": ["type": "json_schema", "schema": schema]] as [String: Any],
            "messages": [["role": "user", "content": user]],
        ] as [String: Any])
        let obj = try await send(req)
        if obj["stop_reason"] as? String == "refusal" { throw Failure.refused }
        let text = (obj["content"] as? [[String: Any]] ?? []).first { $0["type"] as? String == "text" }?["text"] as? String
        guard let text, let data = text.data(using: .utf8) else { throw Failure.empty }
        return data
    }

    // MARK: OpenAI (Chat Completions, JSON schema output)

    private static func openAI(system: String, user: String, schema: [String: Any], key: String, model: String) async throws -> Data {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            "response_format": ["type": "json_schema", "json_schema": ["name": "keel_output", "strict": true, "schema": schema] as [String: Any]] as [String: Any],
        ] as [String: Any])
        let obj = try await send(req)
        let message = ((obj["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]) ?? [:]
        if message["refusal"] is String { throw Failure.refused }
        guard let text = message["content"] as? String, let data = text.data(using: .utf8) else { throw Failure.empty }
        return data
    }

    // MARK: Gemini (generateContent, JSON mode)

    private static func gemini(system: String, user: String, schema: [String: Any], key: String, model: String) async throws -> Data {
        let path = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        var req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(path):generateContent")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        let schemaText = String(data: (try? JSONSerialization.data(withJSONObject: schema)) ?? Data(), encoding: .utf8) ?? "{}"
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": [["text": "\(user)\n\nReply with only a JSON object matching this JSON Schema:\n\(schemaText)"]]]],
            "generationConfig": ["responseMimeType": "application/json"],
        ] as [String: Any])
        let obj = try await send(req)
        let parts = (((obj["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        guard let text = parts.first?["text"] as? String, let data = text.data(using: .utf8) else { throw Failure.empty }
        return data
    }

    // MARK: Web research (plain text answer, searched live by the provider)

    /// Asks the chosen provider to search the web and answer briefly. Claude uses its web search tool,
    /// ChatGPT the Responses API web search, Gemini grounding with Google Search.
    static func research(system: String, question: String) async throws -> String {
        let p = provider
        guard p != .apple, let apiKey = key(for: p) else { throw Failure.empty }
        let m = model(for: p)
        switch p {
        case .claude: return try await claudeResearch(system: system, question: question, key: apiKey, model: m)
        case .openai: return try await openAIResearch(system: system, question: question, key: apiKey, model: m)
        case .gemini: return try await geminiResearch(system: system, question: question, key: apiKey, model: m)
        case .apple: throw Failure.empty
        }
    }

    private static func claudeResearch(system: String, question: String, key: String, model: String) async throws -> String {
        var messages: [[String: Any]] = [["role": "user", "content": question]]
        var collected = ""
        // The server runs the searches; a long search can pause the turn. Resend to let it finish (bounded).
        for _ in 0..<3 {
            var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.httpMethod = "POST"
            req.timeoutInterval = 180
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
            req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": model,
                "max_tokens": 4_096,
                "system": system,
                "fallbacks": "default",
                "output_config": ["effort": "medium"],
                "tools": [["type": "web_search_20260209", "name": "web_search", "max_uses": 4] as [String: Any]],
                "messages": messages,
            ] as [String: Any])
            let obj = try await send(req)
            let stop = obj["stop_reason"] as? String
            if stop == "refusal" { throw Failure.refused }
            let content = obj["content"] as? [[String: Any]] ?? []
            // Answers with citations arrive as several text blocks; join them in order.
            collected += content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            guard stop == "pause_turn" else { break }
            messages = [["role": "user", "content": question], ["role": "assistant", "content": content]]
        }
        let text = collected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure.empty }
        return text
    }

    private static func openAIResearch(system: String, question: String, key: String, model: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "instructions": system, "input": question,
            "tools": [["type": "web_search"]],
        ] as [String: Any])
        let obj = try await send(req)
        let text = (obj["output"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "message" }
            .flatMap { ($0["content"] as? [[String: Any]]) ?? [] }
            .filter { $0["type"] as? String == "output_text" }
            .compactMap { $0["text"] as? String }.joined(separator: "\n")
        guard !text.isEmpty else { throw Failure.empty }
        return text
    }

    private static func geminiResearch(system: String, question: String, key: String, model: String) async throws -> String {
        let path = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        var req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(path):generateContent")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": [["text": question]]]],
            "tools": [["google_search": [String: Any]()]],
        ] as [String: Any])
        let obj = try await send(req)
        let parts = (((obj["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw Failure.empty }
        return text
    }

    private static func send(_ req: URLRequest) async throws -> [String: Any] {
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw Failure.http(code, String(decoding: data, as: UTF8.self)) }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Settings → "Test": a tiny request to confirm the key and model work.
    static func test(_ p: AIProvider, key: String, model: String) async -> String? {
        let schema: [String: Any] = ["type": "object", "additionalProperties": false, "required": ["ok"],
                                     "properties": ["ok": ["type": "boolean"]]]
        do {
            _ = try await json(task: "test", system: "Reply with ok=true.", user: "Ping", schema: schema, provider: p, key: key, model: model)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
