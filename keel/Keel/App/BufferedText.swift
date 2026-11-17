import SwiftUI
import UIKit

// MARK: - Fast typing
//
// Text fields tied straight to saved data rewrite that data on every keystroke, and every screen that shows it
// redraws (in a long page, the whole page). These fields keep what you type locally and save it after a short
// pause, when you press Return, or when you leave the field, so typing stays instant.

/// Shared between a page and the line being typed in, without redrawing the page on each keystroke:
/// the current selection, and a way to save what's been typed so far right now.
@MainActor
final class TypingBuffer {
    var selection: TextSelection?
    var flush: (() -> Void)?
    /// The line's text as last typed (selection offsets are measured in it).
    var text = ""

    /// Saves pending typing, then returns the selection (for Bold, Link, Edit with AI…).
    func flushed() -> TextSelection? {
        flush?()
        selection = Self.currentSelection(in: text)
        return selection
    }

    /// The selection, read from the keyboard's text view only when it's needed. The line's field doesn't
    /// track it while you type: a live selection binding stopped the keyboard's word suggestions and
    /// autocorrect from going in when tapped.
    static func currentSelection(in text: String) -> TextSelection? {
        guard let input = FirstResponder.current as? UITextInput, let range = input.selectedTextRange else { return nil }
        let start = input.offset(from: input.beginningOfDocument, to: range.start)
        let length = input.offset(from: range.start, to: range.end)
        guard length > 0, let r = Range(NSRange(location: start, length: length), in: text) else { return nil }
        return TextSelection(range: r)
    }
}

/// Finds whatever currently has the keyboard.
enum FirstResponder {
    private nonisolated(unsafe) static weak var found: UIResponder?
    @MainActor static var current: UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(UIResponder.keel_markFirstResponder), to: nil, from: nil, for: nil)
        return found
    }
    fileprivate static func mark(_ r: UIResponder) { found = r }
}

extension UIResponder {
    @objc func keel_markFirstResponder() { FirstResponder.mark(self) }
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
    @State private var pending: Task<Void, Never>?

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .font(font)
            .focused(focus, equals: id)
            .onAppear {
                text = committed; synced = committed
                buffer.text = committed
                buffer.flush = { flushNow() }
                focus.wrappedValue = id
            }
            .onChange(of: text) { old, new in
                buffer.text = new
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

// MARK: - Select all text on a page

/// The whole page as one block of text, already selected: copy it, share it, or pick part of it.
/// (A page is many lines you edit one at a time, so this is where "select all" across the page lives.)
struct PageAllTextView: View {
    let title: String
    let text: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    @MainActor static func plain(_ note: Note) -> String {
        note.blocks.map { b -> String in
            let t = RichText.plain(b.text)
            switch b.kind {
            case .bullet: return "• " + t
            case .todo: return (b.checked ? "☑︎ " : "☐ ") + t
            default: return t
            }
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    var body: some View {
        SelectAllTextView(text: text)
            .padding(.horizontal, 12)
            .navigationTitle(title.isEmpty ? "All text" : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
                    Button(copied ? "Copied" : "Copy all") { UIPasteboard.general.string = text; Haptics.success(); copied = true }
                }
            }
    }
}

private struct SelectAllTextView: UIViewRepresentable {
    let text: String
    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.isEditable = false
        v.isSelectable = true
        v.font = .preferredFont(forTextStyle: .body)
        v.adjustsFontForContentSizeCategory = true
        v.backgroundColor = .clear
        v.text = text
        DispatchQueue.main.async {
            v.becomeFirstResponder()
            v.selectAll(nil)
        }
        return v
    }
    func updateUIView(_ v: UITextView, context: Context) {}
}
