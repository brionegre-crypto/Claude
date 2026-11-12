import Foundation
import AuthenticationServices
import SwiftUI

/// "Sign in with Notion" through Keel's server, which holds the integration's secret.
/// The app makes a secret `state`, opens Notion's consent screen in a secure browser sheet, and when
/// Notion sends you back, redeems the token from the server once using that same secret.
@MainActor
enum NotionAuth {
    static let workspaceKey = "import.notion.workspace"
    static let refreshKey = "import.notion.refresh"

    enum Failure: LocalizedError {
        case noServer, cancelled, denied(String), expired, server(String)
        var errorDescription: String? {
            switch self {
            case .noServer: "Add your Keel server address first (it's shown when the server finishes deploying)."
            case .cancelled: "Sign-in was cancelled."
            case .denied(let why): why == "access_denied" ? "Notion access wasn't allowed." : "Notion said: \(why.replacingOccurrences(of: "_", with: " "))."
            case .expired: "Sign-in took too long. Please try again."
            case .server(let m): m
            }
        }
    }

    static var serverURL: URL? { KeelServer.baseURL }
    static var savedWorkspace: String? { UserDefaults.standard.string(forKey: workspaceKey) }

    /// Is Notion sign-in set up on the server? (Its status page says so.)
    static func serverReady() async -> Bool {
        guard let base = serverURL, let result = try? await URLSession.shared.data(from: base) else { return false }
        return String(decoding: result.0, as: UTF8.self).contains("✓ Ready")
    }

    static func signIn(with session: WebAuthenticationSession) async throws -> (token: String, workspace: String) {
        guard let base = serverURL else { throw Failure.noServer }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let state = bytes.map { String(format: "%02x", $0) }.joined()
        var start = URLComponents(url: base.appendingPathComponent("notion/start"), resolvingAgainstBaseURL: false)!
        start.queryItems = [URLQueryItem(name: "state", value: state)]

        let callback: URL
        do {
            callback = try await session.authenticate(using: start.url!, callbackURLScheme: "com.keel.app")
        } catch {
            throw Failure.cancelled
        }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { throw Failure.server("Sign-in couldn't be verified. Please try again.") }
        if let err = items.first(where: { $0.name == "error" })?.value { throw Failure.denied(err) }

        // Redeem the token (single use, expires after 5 minutes).
        var req = URLRequest(url: base.appendingPathComponent("notion/redeem"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["state": state])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { throw Failure.expired }
        guard code == 200, let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = j["access_token"] as? String else { throw Failure.server("The server couldn't finish sign-in (\(code)).") }
        let workspace = j["workspace_name"] as? String ?? "your workspace"
        KeychainStore.save(token, for: NotionConnector.keychainKey)
        if let r = j["refresh_token"] as? String { KeychainStore.save(r, for: refreshKey) }
        UserDefaults.standard.set(workspace, forKey: workspaceKey)
        return (token, workspace)
    }

    static func signOut() {
        KeychainStore.delete(NotionConnector.keychainKey)
        KeychainStore.delete(refreshKey)
        UserDefaults.standard.removeObject(forKey: workspaceKey)
        NotionCache.clearAll()
    }
}

/// Pages already read from the workspace are kept on disk until the import finishes, so a large
/// workspace can pick up where it stopped (app closed, signal lost) instead of starting over.
/// A page is read again only if it changed in the workspace since.
enum NotionCache {
    static var root: URL {
        let u = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("notion-import", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var images: URL {
        let u = root.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    struct Entry: Codable {
        var edited: String
        var page: ImportedPage
    }

    private static func file(_ id: String) -> URL { root.appendingPathComponent(id.replacingOccurrences(of: "/", with: "_") + ".json") }

    static func load(_ id: String, edited: String) -> ImportedPage? {
        guard let d = try? Data(contentsOf: file(id)), let e = try? JSONDecoder().decode(Entry.self, from: d), e.edited == edited else { return nil }
        return e.page
    }

    static func save(_ page: ImportedPage, id: String, edited: String) {
        if let d = try? JSONEncoder().encode(Entry(edited: edited, page: page)) { try? d.write(to: file(id), options: .atomic) }
    }

    static var cachedCount: Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).filter { $0.hasSuffix(".json") }.count
    }

    static func clearAll() { try? FileManager.default.removeItem(at: root) }
}
