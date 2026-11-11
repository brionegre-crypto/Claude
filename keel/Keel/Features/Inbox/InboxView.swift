import SwiftUI
import SwiftData

/// Unified inbox across Gmail, Outlook and iCloud with AI split-inbox (Superhuman/Spark style).
struct InboxView: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<EmailMessage> { !$0.isArchived }, sort: \EmailMessage.receivedAt, order: .reverse)
    private var emails: [EmailMessage]
    @Query private var accounts: [MailAccount]
    @AppStorage("focus.hideInbox") private var hiddenByFocus = false
    @State private var split: TriageCategory = .important
    @State private var accountFilter: String? = nil

    private var visible: [EmailMessage] {
        emails.filter { ($0.category ?? .important) == split && (accountFilter == nil || $0.accountId == accountFilter) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if hiddenByFocus || ShutdownManager.shared.active != nil {
                    ContentUnavailableView("Inbox is resting", systemImage: "moon.zzz",
                                           description: Text("You're in focus mode. Email will be here when you're done."))
                } else {
                    list
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("All accounts") { accountFilter = nil }
                        ForEach(accounts) { a in Button("\(a.provider.displayName) · \(a.address)") { accountFilter = a.id } }
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                }
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(TriageCategory.allCases) { c in
                            let n = emails.filter { ($0.category ?? .important) == c && !$0.isRead }.count
                            Button { withAnimation(DS.spring) { split = c }; Haptics.tap() } label: {
                                Chip(text: "\(c.rawValue.capitalized)\(n > 0 ? " \(n)" : "")",
                                     color: split == c ? DS.Palette.category(c) : .gray)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)

            if visible.isEmpty {
                ContentUnavailableView("All clear", systemImage: "checkmark.seal",
                                       description: Text("Nothing in \(split.rawValue). Nice."))
                    .listRowBackground(Color.clear)
            }

            ForEach(visible) { e in
                NavigationLink { EmailDetailView(email: e) } label: { EmailRow(email: e) }
                    .swipeActions(edge: .trailing) {
                        Button { archive(e) } label: { Label("Done", systemImage: "checkmark") }.tint(DS.Palette.calm)
                    }
                    .swipeActions(edge: .leading) {
                        Button { toTask(e) } label: { Label("Task", systemImage: "checklist") }.tint(DS.Palette.warmth)
                        Button { e.snoozedUntil = Calendar.current.date(byAdding: .hour, value: 3, to: Date()); e.isArchived = true } label: {
                            Label("Snooze", systemImage: "clock")
                        }.tint(DS.Palette.meeting)
                    }
            }
        }
        .listStyle(.plain)
        .refreshable { await SyncEngine.shared.syncAll() }
    }

    private func archive(_ e: EmailMessage) {
        withAnimation(DS.spring) { e.isArchived = true }
        Haptics.success()
        if let a = accounts.first(where: { $0.id == e.accountId }) {
            Task { try? await MailProviderFactory.make(for: a).archive(e.providerMessageId) }
        }
    }

    private func toTask(_ e: EmailMessage) {
        let t = TaskItem(title: e.extractedTaskTitle ?? "Reply: \(e.subject)", dueDate: e.extractedDueDate, priority: .medium)
        t.sourceEmailId = e.id
        ctx.insert(t)
        Haptics.success()
    }
}

struct EmailRow: View {
    let email: EmailMessage
    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            Circle().fill(email.isRead ? .clear : DS.Palette.accent).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(email.fromName.isEmpty ? email.from : email.fromName).font(DS.Font.headline).lineLimit(1)
                    Spacer()
                    Text(email.receivedAt, format: .relative(presentation: .named)).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                Text(email.subject).font(DS.Font.body).lineLimit(1)
                Text(email.aiSummary ?? email.snippet).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                if let task = email.extractedTaskTitle { Chip(text: task, color: DS.Palette.warmth, icon: "sparkles") }
            }
        }
        .padding(.vertical, 4)
    }
}

struct EmailDetailView: View {
    @Bindable var email: EmailMessage
    @Query private var accounts: [MailAccount]
    @State private var intent = ""
    @State private var draft = ""
    @State private var drafting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Text(email.subject).font(DS.Font.title)
                Text("\(email.fromName) · \(email.from)").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                if let s = email.aiSummary {
                    GlassCard(tint: DS.Palette.accent) { Label(s, systemImage: "sparkles").font(DS.Font.body) }
                }
                Text(email.bodyPlain).font(DS.Font.body).textSelection(.enabled)
                Divider()
                Text("Reply").font(DS.Font.headline)
                HStack {
                    ForEach(["Yes, sounds good", "Can't make it", "Need more time"], id: \.self) { quick in
                        Button(quick) { intent = quick; Task { await makeDraft() } }.font(DS.Font.caption).buttonStyle(.bordered)
                    }
                }
                TextField("Or say what you want to reply…", text: $intent).textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await makeDraft() } }
                if drafting { ProgressView() }
                if !draft.isEmpty {
                    TextEditor(text: $draft).frame(minHeight: 160)
                        .padding(DS.Space.s).background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.chip))
                    Button { send() } label: { Label("Send", systemImage: "paperplane.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(DS.Palette.accent)
                }
            }
            .padding()
        }
        .onAppear { email.isRead = true }
    }

    private func makeDraft() async {
        drafting = true; defer { drafting = false }
        draft = await AIRouter.shared.draftReply(to: email, intent: intent) ?? ""
    }

    private func send() {
        guard let a = accounts.first(where: { $0.id == email.accountId }) else { return }
        Task {
            try? await MailProviderFactory.make(for: a).send(to: email.from, subject: "Re: \(email.subject)", body: draft, inReplyTo: nil)
            Haptics.success()
        }
    }
}
