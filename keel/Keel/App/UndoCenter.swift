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
