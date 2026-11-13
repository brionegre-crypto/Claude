import SwiftUI
import SwiftData

/// List on the left, the open item on the right when there's room (Mac, iPad, a wide window);
/// a normal push stack on iPhone. Links in the list open in the right-hand column.
struct SplitOrStack<Content: View>: View {
    var placeholder: String = "Select an item"
    var icon: String = "sidebar.left"
    @ViewBuilder var content: () -> Content
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        if hSize == .regular {
            NavigationSplitView {
                content().navigationSplitViewColumnWidth(min: 320, ideal: 400, max: 560)
            } detail: {
                ContentUnavailableView(placeholder, systemImage: icon)
            }
        } else {
            NavigationStack { content() }
        }
    }
}

/// A page in its own window (Mac and iPad): right-click a page → Open in New Window.
struct NoteWindow: View {
    @Query private var notes: [Note]

    init(id: UUID?) {
        let target = id ?? UUID()
        _notes = Query(filter: #Predicate<Note> { $0.id == target })
    }

    var body: some View {
        NavigationStack {
            if let n = notes.first {
                NoteEditor(note: n)
            } else {
                ContentUnavailableView("Page not found", systemImage: "doc.questionmark", description: Text("It may have been deleted."))
            }
        }
    }
}

/// An email in its own window.
struct EmailWindow: View {
    @Query private var emails: [EmailMessage]

    init(id: String?) {
        let target = id ?? ""
        _emails = Query(filter: #Predicate<EmailMessage> { $0.id == target })
    }

    var body: some View {
        NavigationStack {
            if let e = emails.first {
                EmailDetailView(email: e)
            } else {
                ContentUnavailableView("Email not found", systemImage: "envelope.badge.shield.half.filled", description: Text("It may have been archived on another device."))
            }
        }
    }
}

/// A small window to keep beside your work: the next thing, a focus button and quick capture.
struct QuickWindowView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(ShutdownManager.self) private var shutdown
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }, sort: \TaskItem.dueDate) private var open: [TaskItem]
    @State private var capture = ""
    @FocusState private var typing: Bool

    private var next: TaskItem? {
        open.first { ($0.dueDate ?? .distantFuture) <= Calendar.current.date(byAdding: .day, value: 1, to: Date())! } ?? open.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Next").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                if let t = next {
                    HStack(alignment: .firstTextBaseline) {
                        Button {
                            TaskActions.setDone(t, true)
                            try? ctx.save()
                            Haptics.success()
                        } label: { Image(systemName: "circle").font(.title3) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Mark done")
                        Text(t.title).font(DS.Font.headline).lineLimit(2)
                    }
                } else {
                    Text("Nothing waiting. Nice.").font(DS.Font.headline)
                }
            }

            if let end = shutdown.endsAt, end > Date() {
                Label {
                    Text(timerInterval: Date()...end, countsDown: true).monospacedDigit()
                } icon: { Image(systemName: "moon.zzz.fill") }
                .font(DS.Font.headline).foregroundStyle(DS.Palette.focus)
            } else {
                Button {
                    _ = shutdown.start(minutes: 25, level: .soft, task: next)
                } label: { Label("Focus 25 min", systemImage: "moon.zzz.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).tint(DS.Palette.focus)
            }

            HStack {
                TextField("Capture a task…", text: $capture)
                    .textFieldStyle(.roundedBorder)
                    .focused($typing)
                    .onSubmit(add)
                Button("Add", action: add).disabled(capture.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(minWidth: 300, minHeight: 220)
    }

    private func add() {
        let title = capture.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        ctx.insert(TaskItem(title: title))
        try? ctx.save()
        capture = ""
        Haptics.tap()
    }
}
