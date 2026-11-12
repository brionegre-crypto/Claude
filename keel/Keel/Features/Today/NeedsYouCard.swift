import SwiftUI
import SwiftData

/// Today → Needs you: only real people waiting on you, most urgent first, with one-tap reply and done.
struct NeedsYouCard: View {
    @Query(sort: \EmailMessage.receivedAt, order: .reverse) private var emails: [EmailMessage]
    @Query private var accounts: [MailAccount]
    @State private var compose: ComposeDraft?

    private var items: [EmailMessage] {
        let mine = Set(accounts.map { $0.address.lowercased() })
        return emails.filter { MailNoise.needsYou($0, myAddresses: mine) }
            .sorted { ($0.priorityScore, $0.receivedAt) > ($1.priorityScore, $1.receivedAt) }
    }

    var body: some View {
        let list = items
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack {
                    Text("Needs you").font(DS.Font.title)
                    Spacer()
                    if list.count > 3 {
                        NavigationLink { CatchUpView() } label: { Text("All \(list.count)").font(DS.Font.caption) }
                    }
                }
                ForEach(list.prefix(3)) { e in row(e) }
            }
            .sheet(item: $compose) { ComposeView(draft: $0) }
        }
    }

    private func row(_ e: EmailMessage) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                NavigationLink { EmailDetailView(email: e) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(e.fromName.isEmpty ? e.from : e.fromName).font(DS.Font.headline).foregroundStyle(DS.Palette.ink).lineLimit(1)
                            Spacer()
                            Text(e.receivedAt, format: .relative(presentation: .named)).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Text(e.subject).font(DS.Font.body).foregroundStyle(DS.Palette.ink).lineLimit(1)
                        Text(e.aiSummary ?? e.snippet).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                    }
                }
                .buttonStyle(.plain)
                HStack(spacing: DS.Space.s) {
                    Button { compose = .reply(to: e, all: false, accounts: accounts) } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
                    if let t = e.extractedTaskTitle {
                        Button { _ = QuickAdd.create(t, in: e.modelContext!, defaultDue: e.extractedDueDate); e.isArchived = true; Haptics.success() } label: {
                            Label("Task", systemImage: "checklist")
                        }
                    }
                    Spacer()
                    Button { done(e) } label: { Label("Done", systemImage: "checkmark") }
                }
                .font(DS.Font.caption).buttonStyle(.bordered)
            }
        }
    }

    private func done(_ e: EmailMessage) {
        withAnimation(DS.spring) { e.isArchived = true; e.isRead = true }
        Haptics.success()
        let id = e.providerMessageId
        if let a = accounts.first(where: { $0.id == e.accountId }) {
            let p = MailProviderFactory.make(for: a)
            UndoCenter.shared.offer("Done", undo: { withAnimation { e.isArchived = false } },
                                    commit: { Task { try? await p.archive(id); try? await p.markRead(id, read: true) } })
        }
    }
}
