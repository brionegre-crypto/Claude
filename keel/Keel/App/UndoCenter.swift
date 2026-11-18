import SwiftUI
import Observation

/// A single "Undo" toast for destructive actions (deleting a task, archiving an email).
@MainActor @Observable
final class UndoCenter {
    static let shared = UndoCenter()
    var message: String?
    private var undo: (() -> Void)?
    private var commit: (() -> Void)?
    private var timer: Task<Void, Never>?

    /// `commit` runs after the undo window closes (e.g. archive on the mail server); `undo` restores.
    func offer(_ message: String, seconds: Double = 4, undo: @escaping () -> Void, commit: (() -> Void)? = nil) {
        finish()
        self.message = message
        self.undo = undo
        self.commit = commit
        timer = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    /// A confirmation with no Undo button ("Added 4 tasks, 1 event").
    func notify(_ message: String, seconds: Double = 3) {
        finish()
        self.message = message
        timer = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    var hasUndo: Bool { undo != nil }

    func performUndo() {
        timer?.cancel()
        undo?()
        commit = nil
        clear()
        Haptics.tap()
    }

    /// Keeps the Undo open while you decide (shake to undo shows a question).
    func hold() { timer?.cancel() }
    /// Done deciding without undoing: finish as normal.
    func release() { finish() }

    private func finish() {
        timer?.cancel()
        commit?()
        clear()
    }

    private func clear() {
        withAnimation { message = nil }
        undo = nil
        commit = nil
    }
}

struct UndoToast: View {
    @State private var center = UndoCenter.shared
    var body: some View {
        if let message = center.message {
            HStack {
                Text(message).font(DS.Font.body).lineLimit(1)
                Spacer()
                if center.hasUndo { Button("Undo") { center.performUndo() }.font(DS.Font.headline) }
            }
            .padding(.horizontal, DS.Space.m).padding(.vertical, 12)
            .glassEffect(.regular, in: Capsule())
            .padding(.horizontal)
            .padding(.bottom, 110)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Shake to undo

/// Shaking your iPhone right after deleting, archiving or moving something offers to undo it, as in Apple's
/// own apps (only while the Undo button is showing; you can turn Shake to Undo off in iPhone Settings →
/// Accessibility → Touch, which iPhone then respects).
extension Notification.Name {
    static let keelShake = Notification.Name("keel.shake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { NotificationCenter.default.post(name: .keelShake, object: nil) }
        super.motionEnded(motion, with: event)
    }
}

/// Asks "Undo …?" when you shake while something can still be undone.
struct ShakeToUndo: ViewModifier {
    @State private var asking: String?
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .keelShake)) { _ in
                let u = UndoCenter.shared
                guard u.hasUndo, let m = u.message else { return }
                Haptics.tap()
                u.hold()
                asking = m
            }
            .alert("Undo “\(asking ?? "")”?", isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } })) {
                Button("Undo") { UndoCenter.shared.performUndo(); asking = nil }
                Button("Cancel", role: .cancel) { UndoCenter.shared.release(); asking = nil }
            }
    }
}
