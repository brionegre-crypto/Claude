import Foundation
import AuthenticationServices
import CryptoKit
import Security

/// OAuth 2.0 + PKCE for Gmail and Outlook using ASWebAuthenticationSession (no client secret in the app).
@MainActor
final class OAuthManager: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthManager()

    struct Config {
        let authURL: URL, tokenURL: URL, clientId: String, redirect: String, scopes: [String]
        var extraParams: [String: String] = [:]
    }

    // ⚠️ Fill in client IDs: Google Cloud Console (iOS client) / Azure App Registration (public client).
    static let google = Config(
        authURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
        tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
        clientId: "YOUR_GOOGLE_IOS_CLIENT_ID.apps.googleusercontent.com",
        redirect: "com.googleusercontent.apps.YOUR_GOOGLE_IOS_CLIENT_ID:/oauth2redirect",
        scopes: ["openid", "email", "https://www.googleapis.com/auth/gmail.modify",
                 "https://www.googleapis.com/auth/calendar"],
        extraParams: ["access_type": "offline", "prompt": "consent"])

    static let microsoft = Config(
        authURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
        tokenURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
        clientId: "YOUR_AZURE_APP_CLIENT_ID",
        redirect: "msauth.com.keel.Keel://auth",
        scopes: ["offline_access", "openid", "email", "Mail.ReadWrite", "Mail.Send", "Calendars.ReadWrite", "Tasks.ReadWrite"])

    struct Tokens: Codable { var access: String; var refresh: String?; var expiresAt: Date }

    func signIn(_ cfg: Config) async throws -> Tokens {
        let verifier = Self.randomURLSafe(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var comps = URLComponents(url: cfg.authURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "client_id", value: cfg.clientId),
            .init(name: "redirect_uri", value: cfg.redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: cfg.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ] + cfg.extraParams.map { .init(name: $0.key, value: $0.value) }

        let scheme = String(cfg.redirect.prefix { $0 != ":" })
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: comps.url!, callbackURLScheme: scheme) { url, err in
                if let url { cont.resume(returning: url) } else { cont.resume(throwing: err ?? URLError(.cancelled)) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else { throw URLError(.badServerResponse) }

        return try await tokenRequest(cfg, params: [
            "grant_type": "authorization_code", "code": code,
            "redirect_uri": cfg.redirect, "code_verifier": verifier,
        ])
    }

    func refresh(_ cfg: Config, refreshToken: String) async throws -> Tokens {
        var t = try await tokenRequest(cfg, params: ["grant_type": "refresh_token", "refresh_token": refreshToken])
        if t.refresh == nil { t.refresh = refreshToken }
        return t
    }

    private func tokenRequest(_ cfg: Config, params: [String: String]) async throws -> Tokens {
        var req = URLRequest(url: cfg.tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var all = params; all["client_id"] = cfg.clientId
        if cfg.tokenURL.host?.contains("microsoft") == true { all["scope"] = cfg.scopes.joined(separator: " ") }
        req.httpBody = all.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        struct R: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Int }
        let r = try JSONDecoder().decode(R.self, from: data)
        return Tokens(access: r.access_token, refresh: r.refresh_token, expiresAt: Date().addingTimeInterval(TimeInterval(r.expires_in - 60)))
    }

    func handleRedirect(_ url: URL) { /* ASWebAuthenticationSession handles callbacks; kept for deep links */ }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }

    private static func randomURLSafe(_ n: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
        return Data(bytes).base64URL
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// Tokens and passwords live in the Keychain, never in SwiftData or UserDefaults.
enum KeychainStore {
    static func save(_ value: String, for key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly // allows background sync
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func saveTokens(_ t: OAuthManager.Tokens, account: String) {
        if let d = try? JSONEncoder().encode(t), let s = String(data: d, encoding: .utf8) { save(s, for: "tokens.\(account)") }
    }

    static func tokens(account: String) -> OAuthManager.Tokens? {
        guard let s = read("tokens.\(account)"), let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(OAuthManager.Tokens.self, from: d)
    }
}
