import SwiftUI
import SwiftData

// MARK: - Snippets (saved replies)

struct SnippetsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Snippet.uses, order: .reverse) private var snippets: [Snippet]
    @State private var editing: Snippet?
    @State private var showNew = false

    var body: some View {
        List {
            ForEach(snippets) { s in
                Button { editing = s } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name).font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                        Text(s.body).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                    }
                }
            }
            .onDelete { $0.map { snippets[$0] }.forEach(ctx.delete) }
        }
        .navigationTitle("Snippets")
        .toolbar { Button { showNew = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showNew) { SnippetEditor(snippet: nil) }
        .sheet(item: $editing) { SnippetEditor(snippet: $0) }
        .onAppear { Snippets.seedIfNeeded(ctx) }
    }
}

struct SnippetEditor: View {
    let snippet: Snippet?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Section("Text") { TextEditor(text: $text).frame(minHeight: 160) }
            }
            .navigationTitle(snippet == nil ? "New Snippet" : "Edit Snippet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let s = snippet { s.name = name; s.body = text } else { ctx.insert(Snippet(name: name, body: text)) }
                        dismiss()
                    }
                    .disabled(name.isEmpty || text.isEmpty)
                }
            }
            .onAppear { if let s = snippet { name = s.name; text = s.body } }
        }
    }
}

@MainActor
enum Snippets {
    static func seedIfNeeded(_ ctx: ModelContext) {
        guard ((try? ctx.fetchCount(FetchDescriptor<Snippet>())) ?? 0) == 0 else { return }
        for (n, b) in [
            ("Thanks!", "Thanks so much, I really appreciate it."),
            ("Let me check", "Good question. Let me check and get back to you by tomorrow."),
            ("Running late", "Running about 10 minutes late, sorry! See you shortly."),
            ("Not right now", "Thanks for thinking of me. I can't take this on right now, but please keep me in mind for the future."),
            ("Book a time", "Happy to chat. What times work for you this week?"),
        ] { ctx.insert(Snippet(name: n, body: b)) }
    }
}

/// Compose-screen menu that inserts a snippet.
struct SnippetMenu: View {
    @Binding var text: String
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Snippet.uses, order: .reverse) private var snippets: [Snippet]

    private func insert(_ body: String) {
        if let r = text.range(of: "\n\nOn ") ?? text.range(of: "\n\n---------- Forwarded") {
            text.insert(contentsOf: body, at: r.lowerBound)
        } else {
            text = body + text
        }
        Haptics.tap()
    }

    var body: some View {
        Menu {
            ForEach(snippets) { s in
                Button(s.name) {
                    // Insert above any quoted text so replies read naturally.
                    if let r = text.range(of: "\n\nOn ") ?? text.range(of: "\n\n---------- Forwarded") {
                        text.insert(contentsOf: s.body, at: r.lowerBound)
                    } else {
                        text = s.body + text
                    }
                    s.uses += 1
                    Haptics.tap()
                }
            }
            Divider()
            Button("Insert my availability", systemImage: "calendar.badge.clock") { insert(Availability.text()) }
            NavigationLink { SnippetsView() } label: { Label("Edit snippets", systemImage: "pencil") }
        } label: { Image(systemName: "text.badge.plus") }
        .accessibilityLabel("Insert snippet")
        .onAppear { Snippets.seedIfNeeded(ctx) }
    }
}

// MARK: - Newsletter digest

/// Today's newsletters and promotions in one calm screen, with a combined summary and "archive all".
struct DigestView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \EmailMessage.receivedAt, order: .reverse) private var mail: [EmailMessage]
    @Query private var accounts: [MailAccount]
    @State private var briefing: String?
    @State private var summarizing = false

    private var items: [EmailMessage] {
        mail.filter { !$0.isArchived && ($0.category == .newsletters || $0.category == .promotions || $0.category == .updates)
            && $0.receivedAt > Date().addingTimeInterval(-36 * 3600) }
    }

    var body: some View {
        List {
            Section {
                if let briefing {
                    Label(briefing, systemImage: "sparkles").font(DS.Font.body)
                } else {
                    Button(summarizing ? "Summarizing…" : "Summarize all \(items.count)") { Task { await summarize() } }
                        .disabled(summarizing || items.isEmpty)
                }
            } header: { Text("Briefing") }
            ForEach(items) { e in
                NavigationLink { EmailDetailView(email: e) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.fromName.isEmpty ? e.from : e.fromName).font(DS.Font.headline)
                        Text(e.aiSummary ?? e.subject).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(3)
                    }
                }
            }
            if !items.isEmpty {
                Section {
                    Button("Archive all \(items.count)") {
                        let list = items
                        for e in list { e.isArchived = true }
                        Haptics.success()
                        UndoCenter.shared.offer("Archived \(list.count)", undo: { list.forEach { $0.isArchived = false } }, commit: {
                            for e in list {
                                if let a = accounts.first(where: { $0.id == e.accountId }) {
                                    let id = e.providerMessageId
                                    Task { try? await MailProviderFactory.make(for: a).archive(id) }
                                }
                            }
                        })
                    }
                }
            } else {
                ContentUnavailableView("No newsletters today", systemImage: "newspaper", description: Text("Newsletters, updates and promotions from the last day show up here."))
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Digest")
    }

    private func summarize() async {
        summarizing = true; defer { summarizing = false }
        let text = items.prefix(20).map { "\($0.fromName.isEmpty ? $0.from : $0.fromName): \($0.aiSummary ?? $0.subject)" }.joined(separator: "\n")
        briefing = await AIRouter.shared.summarize("Today's newsletters and updates. Give the 3–5 most useful points:\n" + text)
    }
}
