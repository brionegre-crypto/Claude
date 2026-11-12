import SwiftUI
import LocalAuthentication
import Observation

/// Face ID / Touch ID / passcode lock for the whole app, and for individual notes.
@MainActor @Observable
final class AppLock {
    static let shared = AppLock()
    static let enabledKey = "privacy.appLock"

    var isLocked: Bool
    private var authenticating = false

    init() { isLocked = UserDefaults.standard.bool(forKey: Self.enabledKey) }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static var biometryName: String {
        let c = LAContext()
        _ = c.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch c.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    /// Face ID with passcode fallback. Returns true if the person is the owner.
    static func authenticate(_ reason: String) async -> Bool {
        let c = LAContext()
        c.localizedCancelTitle = "Cancel"
        var err: NSError?
        guard c.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return true }   // no passcode set: nothing to protect with
        return (try? await c.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    func lockIfEnabled() { if Self.isEnabled { isLocked = true } }

    func unlock() async {
        guard isLocked, !authenticating else { return }
        authenticating = true; defer { authenticating = false }
        if await Self.authenticate("Unlock Keel") { withAnimation(DS.spring) { isLocked = false } }
    }
}

struct LockScreen: View {
    @State private var lock = AppLock.shared

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: DS.Space.l) {
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(DS.Palette.accent)
                Text("Keel is locked").font(DS.Font.title)
                Button { Task { await lock.unlock() } } label: {
                    Label("Unlock with \(AppLock.biometryName)", systemImage: AppLock.biometryName == "Face ID" ? "faceid" : "lock.open")
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.borderedProminent).tint(DS.Palette.accent).controlSize(.large)
            }
        }
        .task { await lock.unlock() }
    }
}

/// Shown over the app in the app switcher when the lock is on, so screenshots of it reveal nothing.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            Image(systemName: "sailboat.fill").font(.system(size: 48)).foregroundStyle(DS.Palette.accent)
        }
    }
}
