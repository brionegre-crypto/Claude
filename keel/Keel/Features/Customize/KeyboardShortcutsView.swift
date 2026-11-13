import SwiftUI

/// Help → Keyboard Shortcuts (⌘/). Every key Keel understands on iPad and Mac.
struct KeyboardShortcutsView: View {
    @Environment(\.dismiss) private var dismiss
    private let groups: [(String, [(String, String)])] = [
        ("Anywhere", [("⌘K", "Command bar: do anything"), ("⌘O", "Open a page"), ("⌘F", "Search everything"), ("⌘N", "New task"),
                      ("⇧⌘N", "New note"), ("⌘1 – ⌘5", "Today, Inbox, Calendar, Tasks, Notes"), ("⇧⌘F", "Start focus"),
                      ("⇧⌘P", "Plan my day"), ("⇧⌘J", "Journal"), ("⇧⌘R", "Record a meeting"), ("⌘,", "Settings"), ("⌘/", "This list")]),
        ("Reading email", [("⌘R", "Reply"), ("⇧⌘R", "Reply all"), ("⇧⌘F", "Forward"), ("⌃⌘A", "Archive"), ("⇧⌘L", "Flag or unflag"),
                           ("⇧⌘U", "Mark unread"), ("⌘⌫", "Delete")]),
        ("In a page", [("/", "Insert any block"), ("@", "Mention a page, person or date"), ("[[", "Link to a page"),
                       ("⌥⌘F", "Find & replace"), ("⇧⌘O", "Outline"), ("⇧⌘M", "Comments"), ("⌘B / ⌘I", "Bold / italic")]),
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.0) { g in
                    Section(g.0) {
                        ForEach(g.1, id: \.0) { k in
                            HStack {
                                Text(k.1)
                                Spacer()
                                Text(k.0).font(.callout.monospaced()).foregroundStyle(DS.Palette.inkSoft)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Keyboard Shortcuts").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
