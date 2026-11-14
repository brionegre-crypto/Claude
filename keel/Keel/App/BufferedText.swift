import SwiftUI

// MARK: - Fast typing
//
// Text fields tied straight to saved data rewrite that data on every keystroke, and every screen that shows it
// redraws (in a long page, the whole page). These fields keep what you type locally and save it after a short
// pause, when you press Return, or when you leave the field, so typing stays instant.

/// Shared between a page and the line being typed in, without redrawing the page on each keystroke:
/// the current selection, and a way to save what's been typed so far right now.
final class TypingBuffer {
    var selection: TextSelection?
    var flush: (() -> Void)?

    /// Saves pending typing, then returns the selection (for Bold, Link, Edit with AI…).
    func flushed() -> TextSelection? {
        flush?()
        return selection
    }
}

/// One line of a page while you type in it.
struct BlockTextField: View {
    let placeholder: String
    let font: Font
    /// The saved text of this line.
    let committed: String
    let id: UUID
    var focus: FocusState<UUID?>.Binding
    let buffer: TypingBuffer
    /// Saves the new text (and runs the page's shortcuts: Return, /, @, Markdown, paste).
    let commit: (String) -> Void

    @State private var text = ""
    @State private var synced = ""
    @State private var selection: TextSelection?
    @State private var pending: Task<Void, Never>?

    var body: some View {
        TextField(placeholder, text: $text, selection: $selection, axis: .vertical)
            .font(font)
            .focused(focus, equals: id)
            .onAppear {
                text = committed; synced = committed
                buffer.flush = { flushNow() }
                focus.wrappedValue = id
            }
            .onChange(of: text) { old, new in
                guard new != synced else { return }
                if Self.needsNow(old: old, new: new) {
                    flushNow()
                } else {
                    pending?.cancel()
                    pending = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        guard !Task.isCancelled else { return }
                        flushNow()
                    }
                }
            }
            .onChange(of: selection) { _, s in buffer.selection = s }
            .onChange(of: committed) { _, v in
                // Changed from outside (Bold, a Markdown shortcut, AI): show it, unless you're mid-word.
                guard pending == nil, v != text else { return }
                synced = v; text = v
            }
            .onDisappear { flushNow() }
    }

    /// Things the page must react to straight away: a new line, a paste, the / and @ menus, Markdown shortcuts
    /// at the start of a line, and space on an empty line.
    static func needsNow(old: String, new: String) -> Bool {
        new.contains("\n") || abs(new.count - old.count) > 1 || new.hasPrefix("/") || old.hasPrefix("/")
            || new.contains("@") || old.contains("@") || new.count <= 4
    }

    private func flushNow() {
        pending?.cancel(); pending = nil
        guard text != synced else { return }
        synced = text
        commit(text)
    }
}

/// A text field for a saved property (a title, a name) that saves after a short pause.
struct BufferedTextField: View {
    let title: String
    @Binding var text: String
    var axis: Axis = .horizontal

    @State private var local = ""
    @State private var synced = ""
    @State private var pending: Task<Void, Never>?
    @State private var loaded = false

    init(_ title: String, text: Binding<String>, axis: Axis = .horizontal) {
        self.title = title; self._text = text; self.axis = axis
    }

    var body: some View {
        TextField(title, text: $local, axis: axis)
            .onAppear { if !loaded { local = text; synced = text; loaded = true } }
            .onChange(of: local) { _, v in
                guard v != synced else { return }
                pending?.cancel()
                pending = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    save()
                }
            }
            .onChange(of: text) { _, v in
                guard pending == nil, v != local else { return }
                local = v; synced = v
            }
            .onSubmit { save() }
            .onDisappear { save() }
    }

    private func save() {
        pending?.cancel(); pending = nil
        guard local != synced else { return }
        synced = local
        text = local
    }
}

/// A multi-line editor for a saved property (task notes) that saves after a short pause.
struct BufferedTextEditor: View {
    @Binding var text: String

    @State private var local = ""
    @State private var synced = ""
    @State private var pending: Task<Void, Never>?
    @State private var loaded = false

    var body: some View {
        TextEditor(text: $local)
            .onAppear { if !loaded { local = text; synced = text; loaded = true } }
            .onChange(of: local) { _, v in
                guard v != synced else { return }
                pending?.cancel()
                pending = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    save()
                }
            }
            .onChange(of: text) { _, v in
                guard pending == nil, v != local else { return }
                local = v; synced = v
            }
            .onDisappear { save() }
    }

    private func save() {
        pending?.cancel(); pending = nil
        guard local != synced else { return }
        synced = local
        text = local
    }
}
