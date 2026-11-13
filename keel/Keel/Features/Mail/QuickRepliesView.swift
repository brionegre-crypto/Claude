import SwiftUI
import SwiftData

/// "Clear 5 quick replies": one email at a time, with reply ideas written in your style.
/// Small, finishable, and done in a few minutes, which is the point.
struct QuickRepliesView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \EmailMessage.receivedAt, order: .reverse) private var mail: [EmailMessage]
    @Query private var accounts: [MailAccount]
    @Query private var senderScores: [SenderScore]
    @State private var queue: [EmailMessage] = []
    @State private var index = 0
    @State private var replied = 0
    @State private var ideas: [String] = []
    @State private var draft = ""
    @State private var intent = ""
    @State private var working = false
    @State private var sending = false
    @State private var error: String?
    @State private var started = false

    static let goal = 5

    /// Short replies to real people, oldest first so nobody waits longest.
    static func candidates(_ mail: [EmailMessage], accounts: [MailAccount], scores: [SenderScore]) -> [EmailMessage] {
        let mine = Set(accounts.map { $0.address.lowercased() })
        let map = Dictionary(scores.map { ($0.sender, $0) }, uniquingKeysWith: { a, _ in a })
        return mail.filter { e in
            AutoDrafts.isRealPerson(e) && (MailNoise.needsYou(e, myAddresses: mine) && InboxBrain.replyMinutes(e) <= 5)
                || (InboxBrain.isQuickWin(e, score: map[e.from.lowercased()]) && !mine.contains(e.from.lowercased()))
        }
        .sorted { $0.receivedAt < $1.receivedAt }
    }

    private var current: EmailMessage? { index < queue.count ? queue[index] : nil }

    var body: some View {
        VStack(spacing: DS.Space.m) {
            if !started {
                ProgressView()
            } else if let e = current {
                progress
                card(e)
            } else {
                finished
            }
        }
        .padding()
        .navigationTitle("Quick Replies")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !started else { return }
            queue = Array(Self.candidates(mail, accounts: accounts, scores: senderScores).prefix(Self.goal))
            started = true
            await loadIdeas()
        }
    }

    private var progress: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(0..<queue.count, id: \.self) { i in
                    Capsule().fill(i < index ? DS.Palette.calm : i == index ? DS.Palette.accent : DS.Palette.inkSoft.opacity(0.2))
                        .frame(height: 6)
                }
            }
            Text("\(index + 1) of \(queue.count)").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Email \(index + 1) of \(queue.count)")
    }

    private func card(_ e: EmailMessage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack(spacing: DS.Space.s) {
                    SenderAvatar(name: e.fromName, email: e.from)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.fromName.isEmpty ? e.from : e.fromName).font(DS.Font.headline)
                        Text(e.subject).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                    }
                    Spacer()
                    Text(e.receivedAt, style: .relative).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                }
                Text(e.aiSummary ?? String(GmailProvider.stripQuotedReply(e.bodyPlain).prefix(600)))
                    .font(DS.Font.body)
                    .padding(DS.Space.m).frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.card))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(ideas, id: \.self) { idea in
                            Button { intent = idea; Task { await makeDraft(e) } } label: { Label(idea, systemImage: "sparkles") }
                                .buttonStyle(.bordered).tint(DS.Palette.accent)
                        }
                        Button { draft = WritingStyle.availabilityReply(to: e.fromName) } label: {
                            Label("Offer my times", systemImage: "calendar.badge.clock")
                        }
                        .buttonStyle(.bordered).tint(DS.Palette.meeting)
                        Button("Thanks!") { intent = "Thank them briefly"; Task { await makeDraft(e) } }.buttonStyle(.bordered)
                    }
                    .font(DS.Font.caption)
                }
                TextField("Or say what you want to reply…", text: $intent)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await makeDraft(e) } }
                if working { ProgressView("Writing in your style…").frame(maxWidth: .infinity) }
                if !draft.isEmpty {
                    TextEditor(text: $draft).frame(minHeight: 150)
                        .padding(DS.Space.s).background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.chip))
                }
                if let error { Text(error).font(DS.Font.caption).foregroundStyle(.red) }

                HStack(spacing: DS.Space.s) {
                    Button { Task { await send(e) } } label: {
                        Label(sending ? "Sending…" : "Send", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(DS.Palette.accent)
                    .disabled(draft.isEmpty || sending)
                    Button("Done") { markDone(e) }.buttonStyle(.bordered)
                        .accessibilityHint("Archive without replying")
                    Button("Skip") { next() }.buttonStyle(.bordered)
                }
            }
        }
    }

    private var finished: some View {
        VStack(spacing: DS.Space.m) {
            Spacer()
            Image(systemName: queue.isEmpty ? "tray" : "checkmark.seal.fill")
                .font(.system(size: 56)).foregroundStyle(DS.Palette.calm)
                .symbolEffect(.bounce, value: index)
            Text(queue.isEmpty ? "No quick replies waiting" : "\(replied) repl\(replied == 1 ? "y" : "ies") sent")
                .font(DS.Font.title)
            Text(queue.isEmpty ? "Nobody is waiting on a short answer from you. Nice." : "That's \(index) emails off your mind.")
                .font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft).multilineTextAlignment(.center)
            Spacer()
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent).tint(DS.Palette.accent)
        }
        .onAppear { if replied > 0 { Haptics.milestone() } }
    }

    private func loadIdeas() async {
        ideas = []; draft = ""; intent = ""; error = nil
        guard let e = current else { return }
        ideas = await AIRouter.shared.replyIdeas(for: e)
    }

    private func makeDraft(_ e: EmailMessage) async {
        guard !intent.isEmpty else { return }
        working = true; defer { working = false }
        draft = await AIRouter.shared.draftReply(to: e, intent: intent) ?? ""
        if draft.isEmpty { error = "Couldn't write a draft. Type your reply in the box instead." ; draft = WritingStyle.greeting(for: e.fromName) }
    }

    private func send(_ e: EmailMessage) async {
        guard let account = accounts.first(where: { $0.id == e.accountId }) else { error = "This account was removed."; return }
        sending = true; defer { sending = false }
        do {
            var m = OutgoingMail(to: [e.from], subject: ComposeDraft.prefixed("Re:", e.subject), body: draft, replyTo: e.replyContext)
            if let a = MailAliases.match(e, accountId: account.id) { m.fromAlias = a }
            try await MailProviderFactory.make(for: account).send(m)
            InboxBrain.record(.reply, sender: e.from, name: e.fromName, ctx: ctx)
            e.isRead = true
            e.isArchived = true
            Task { try? await MailProviderFactory.make(for: account).archive(e.providerMessageId) }
            replied += 1
            Haptics.success()
            next()
        } catch {
            self.error = "Couldn't send: \(error.localizedDescription)"
        }
    }

    private func markDone(_ e: EmailMessage) {
        e.isRead = true
        e.isArchived = true
        if let account = accounts.first(where: { $0.id == e.accountId }) {
            Task { try? await MailProviderFactory.make(for: account).archive(e.providerMessageId) }
        }
        Haptics.tap()
        next()
    }

    private func next() {
        withAnimation(DS.spring) { index += 1 }
        Task { await loadIdeas() }
    }
}
