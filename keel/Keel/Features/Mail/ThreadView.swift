import SwiftUI
import SwiftData

/// Swipe and conversation preferences.
enum MailSwipe {
    static let threadsKey = "mail.threads", leadingKey = "swipe.leading", trailingKey = "swipe.trailing"
    static let defaultLeading = "task,snooze,star", defaultTrailing = "archive,trash"
    static let all: [(id: String, label: String, icon: String)] = [
        ("archive", "Archive", "checkmark"), ("trash", "Trash", "trash"), ("task", "Make a Task", "checklist"),
        ("snooze", "Snooze", "clock"), ("star", "Flag", "flag"), ("read", "Read / Unread", "envelope.open"), ("pin", "Pin", "pin"),
    ]
    static func actions(_ raw: String) -> [String] { raw.split(separator: ",").map(String.init).filter { id in all.contains { $0.id == id } } }
}

/// A whole conversation, oldest first. The newest message is open; tap any other to expand it.
struct ThreadView: View {
    let messages: [EmailMessage]
    @Query private var accounts: [MailAccount]
    @State private var expanded: Set<String> = []
    @State private var compose: ComposeDraft?
    @State private var summary: String?
    @State private var summarizing = false

    private var sorted: [EmailMessage] { messages.sorted { $0.receivedAt < $1.receivedAt } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Text(sorted.last?.subject ?? "").font(DS.Font.title)
                Text("\(messages.count) messages").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                GlassCard(tint: DS.Palette.accent) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let summary {
                            Label("Where this stands", systemImage: "sparkles").font(DS.Font.headline)
                            Text(summary).font(.callout)
                        } else {
                            Button { Task { await summarize() } } label: {
                                Label(summarizing ? "Reading the conversation…" : "Summarize conversation", systemImage: "sparkles")
                            }
                            .disabled(summarizing)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(sorted) { m in
                    let open = expanded.contains(m.id) || m.id == sorted.last?.id
                    GlassCard {
                        VStack(alignment: .leading, spacing: DS.Space.s) {
                            Button { withAnimation(DS.spring) { if expanded.contains(m.id) { expanded.remove(m.id) } else { expanded.insert(m.id) } } } label: {
                                HStack {
                                    Text(m.fromName.isEmpty ? m.from : m.fromName).font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                                    Spacer()
                                    Text(m.receivedAt.formatted(date: .abbreviated, time: .shortened)).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                                }
                            }
                            .buttonStyle(.plain)
                            if open {
                                Text(m.bodyPlain.isEmpty ? m.snippet : m.bodyPlain).font(DS.Font.body).textSelection(.enabled)
                                NavigationLink { EmailDetailView(email: m) } label: {
                                    Label("Open message", systemImage: "arrow.up.right").font(DS.Font.caption)
                                }
                            } else {
                                Text(m.aiSummary ?? m.snippet).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                if let last = sorted.last {
                    Button { compose = .reply(to: last, all: false, accounts: accounts) } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
                    Spacer()
                    Button { compose = .reply(to: last, all: true, accounts: accounts) } label: { Label("Reply All", systemImage: "arrowshape.turn.up.left.2") }
                    Spacer()
                    Button { compose = .forward(last) } label: { Label("Forward", systemImage: "arrowshape.turn.up.right") }
                }
            }
        }
        .sheet(item: $compose) { ComposeView(draft: $0) }
        .task {
            if messages.count >= 4 { await summarize() }      // long threads: summarize straight away
            for m in messages where !m.isRead {
                m.isRead = true
                if let a = accounts.first(where: { $0.id == m.accountId }) {
                    let id = m.providerMessageId
                    try? await MailProviderFactory.make(for: a).markRead(id, read: true)
                }
            }
        }
    }
}

extension ThreadView {
    func summarize() async {
        guard summary == nil, !summarizing else { return }
        summarizing = true; defer { summarizing = false }
        let text = sorted.map { "\($0.fromName.isEmpty ? $0.from : $0.fromName) on \($0.receivedAt.formatted(date: .abbreviated, time: .shortened)): \($0.bodyPlain.prefix(1_200))" }
            .joined(separator: "\n---\n")
        summary = await AIRouter.shared.write("""
        Summarize this email conversation in 3 short sentences: what it's about, what was decided, and what (if anything) is still waiting on me.
        \(text)
        """)
    }
}

/// Settings → Mail → Swipe Actions.
struct SwipeSettingsView: View {
    @AppStorage(MailSwipe.leadingKey) private var leading = MailSwipe.defaultLeading
    @AppStorage(MailSwipe.trailingKey) private var trailing = MailSwipe.defaultTrailing

    var body: some View {
        List {
            picker("Swipe Right (first)", $leading, 0)
            picker("Swipe Right (second)", $leading, 1)
            picker("Swipe Left (first)", $trailing, 0)
            picker("Swipe Left (second)", $trailing, 1)
            Section { Button("Reset to Defaults") { leading = MailSwipe.defaultLeading; trailing = MailSwipe.defaultTrailing } }
        }
        .navigationTitle("Swipe Actions")
    }

    private func picker(_ title: String, _ raw: Binding<String>, _ index: Int) -> some View {
        Picker(title, selection: Binding(
            get: { let a = MailSwipe.actions(raw.wrappedValue); return index < a.count ? a[index] : "none" },
            set: { new in
                var a = MailSwipe.actions(raw.wrappedValue)
                while a.count <= index { a.append("none") }
                a[index] = new
                raw.wrappedValue = a.filter { $0 != "none" }.joined(separator: ",")
            })) {
            Text("None").tag("none")
            ForEach(MailSwipe.all, id: \.id) { Label($0.label, systemImage: $0.icon).tag($0.id) }
        }
    }
}
