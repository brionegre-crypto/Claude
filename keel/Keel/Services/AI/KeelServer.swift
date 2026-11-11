import Foundation

/// Where the Keel server lives and how the phone proves it's you.
/// Set in-app (Settings → Claude AI) so no rebuild is needed; Info.plist's KeelAIProxyURL is only a fallback.
enum KeelServer {
    static let addressKey = "keel.server.address"
    static let tokenKey = "keel.session"                 // Keychain item holding the access code

    /// Base URL, e.g. https://keel-backend.yourname.workers.dev
    static var baseURL: URL? {
        if let saved = UserDefaults.standard.string(forKey: addressKey), let url = normalized(saved) { return url }
        guard let plist = Bundle.main.object(forInfoDictionaryKey: "KeelAIProxyURL") as? String,
              !plist.contains("YOUR-BACKEND") else { return nil }
        return normalized(plist)
    }

    static var accessCode: String? { KeychainStore.read(tokenKey) }
    static var isConfigured: Bool { baseURL != nil && !(accessCode ?? "").isEmpty }

    static func save(address: String, accessCode: String) {
        UserDefaults.standard.set(address.trimmingCharacters(in: .whitespacesAndNewlines), forKey: addressKey)
        KeychainStore.save(accessCode.trimmingCharacters(in: .whitespacesAndNewlines), for: tokenKey)
    }

    /// Accepts "keel-backend.x.workers.dev", "https://…", or a pasted ".../v1/messages" URL.
    static func normalized(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        for suffix in ["/v1/messages", "/"] where s.hasSuffix(suffix) { s = String(s.dropLast(suffix.count)) }
        return URL(string: s)
    }

    static func endpoint(_ path: String) -> URL? { baseURL?.appendingPathComponent(path) }

    enum CheckResult { case ok, badCode, unreachable(String) }

    /// Calls /health, which checks the access code without spending any AI credits.
    static func check(address: String, accessCode: String) async -> CheckResult {
        guard let url = normalized(address)?.appendingPathComponent("health") else { return .unreachable("That address doesn't look right.") }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessCode.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            switch (resp as? HTTPURLResponse)?.statusCode ?? 0 {
            case 200: return .ok
            case 401: return .badCode
            case let code: return .unreachable("The server answered with error \(code).")
            }
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }
}
