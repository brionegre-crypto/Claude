import SwiftUI
import SwiftData

/// "Catch me up": one screen that explains your unread mail: who needs what, what can wait,
/// and one tap to clear the noise. Summaries run on-device with Apple Intelligence.
struct CatchUpView: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<EmailMessage> { !$0.isRead && !$0.isArchived }, sort: \EmailMessage.receivedAt, order: .reverse)
    private var unread: [EmailMessage]
    @Query private var accounts: [MailAccount]
    @State private var summary: String?
    @State private var working = false

    private var needsYou: [EmailMessage] {
        unread.filter { [TriageCategory.important, .actionable, .calendar].contains($0.category ?? .important) }
            .sorted { $0.priorityScore > $1.priorityScore }
    }
    private var noise: [EmailMessage] {
        unread.filter { [TriageCategory.newsletters, .promotions, .updates, .lowPriority].contains($0.category ?? .important) }
    }

    var body: some View {
        List {
            Section {
                if let summary {
                    Text(summary).font(.callout)
                } else if working {
                    ProgressView("Reading \(min(needsYou.count, 25)) emails…")
                } else {
                    Text("\(unread.count) unread: \(needsYou.count) may need you, \(noise.count) can wait.").font(.callout)
                }
            } header: { Label("Catch me up", systemImage: "sparkles") }
            if !needsYou.isEmpty {
                Section("Needs you") {
                    ForEach(needsYou.prefix(15)) { e in
                        NavigationLink { EmailDetailView(email: e) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.fromName.isEmpty ? e.from : e.fromName).font(DS.Font.headline)
                                Text(e.aiSummary ?? e.subject).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                            }
                        }
                    }
                }
            }
            if !noise.isEmpty {
                Section {
                    let senders = Dictionary(grouping: noise) { $0.fromName.isEmpty ? $0.from : $0.fromName }
                        .sorted { $0.value.count > $1.value.count }.prefix(6)
                    ForEach(senders, id: \.key) { s in
                        LabeledContent(s.key, value: "\(s.value.count)")
                    }
                    Button("Mark \(noise.count) as read", systemImage: "envelope.open") { markRead(noise) }
                } header: { Text("Can wait") } footer: { Text("Newsletters, promotions and updates. Marking read also updates your mail account.") }
            }
        }
        .navigationTitle("Catch Up")
        .task { await summarize() }
        .refreshable { summary = nil; await summarize() }
    }

    private func summarize() async {
        guard summary == nil, !needsYou.isEmpty else { return }
        working = true; defer { working = false }
        let lines = needsYou.prefix(25).map { "\($0.fromName.isEmpty ? $0.from : $0.fromName): \($0.subject). \($0.aiSummary ?? $0.snippet)" }
        summary = await AIRouter.shared.write("Catch me up on my unread email. Group by what each person needs from me, most urgent first. Mention deadlines.\n" + lines.joined(separator: "\n"))
            ?? "Top: " + needsYou.prefix(3).map { "\($0.fromName.isEmpty ? $0.from : $0.fromName) (\($0.subject))" }.joined(separator: "; ") + "."
    }

    private func markRead(_ list: [EmailMessage]) {
        for e in list {
            e.isRead = true
            let id = e.providerMessageId
            if let a = accounts.first(where: { $0.id == e.accountId }) {
                let p = MailProviderFactory.make(for: a)
                Task { try? await p.markRead(id, read: true) }
            }
        }
        Haptics.success()
    }
}

/// Every email with an attachment, searchable, with file names loaded as you scroll.
struct AttachmentsView: View {
    @Query(filter: #Predicate<EmailMessage> { $0.hasAttachments }, sort: \EmailMessage.receivedAt, order: .reverse)
    private var mail: [EmailMessage]
    @Query private var accounts: [MailAccount]
    @State private var names: [String: [String]] = [:]
    @State private var search = ""
    @State private var kind = "all"

    private func matches(_ e: EmailMessage) -> Bool {
        let files = names[e.id] ?? []
        if kind != "all", !files.isEmpty {
            let exts: [String] = kind == "docs" ? ["pdf", "doc", "docx", "pages", "xls", "xlsx", "numbers", "ppt", "pptx", "key", "txt", "csv"] : ["jpg", "jpeg", "png", "heic", "gif"]
            guard files.contains(where: { exts.contains(($0 as NSString).pathExtension.lowercased()) }) else { return false }
        }
        guard !search.isEmpty else { return true }
        let q = search.lowercased()
        return ([e.subject, e.fromName, e.from] + files).contains { $0.lowercased().contains(q) }
    }

    var body: some View {
        List {
            Picker("Type", selection: $kind) {
                Text("All").tag("all"); Text("Documents").tag("docs"); Text("Images").tag("images")
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            ForEach(mail.prefix(200).filter(matches)) { e in
                NavigationLink { EmailDetailView(email: e) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(e.fromName.isEmpty ? e.from : e.fromName).font(DS.Font.headline).lineLimit(1)
                            Spacer()
                            Text(e.receivedAt.formatted(date: .abbreviated, time: .omitted)).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Text(e.subject).font(DS.Font.caption).lineLimit(1)
                        if let files = names[e.id] {
                            ForEach(files.prefix(3), id: \.self) { f in
                                Label(f, systemImage: icon(f)).font(DS.Font.caption).foregroundStyle(DS.Palette.accent).lineLimit(1)
                            }
                        }
                    }
                }
                .task { await load(e) }
            }
        }
        .searchable(text: $search, prompt: "File name, sender or subject")
        .navigationTitle("Attachments")
    }

    private func load(_ e: EmailMessage) async {
        guard names[e.id] == nil, let a = accounts.first(where: { $0.id == e.accountId }) else { return }
        let list = (try? await MailProviderFactory.make(for: a).attachments(for: e.providerMessageId)) ?? []
        names[e.id] = list.map(\.filename)
    }

    private func icon(_ f: String) -> String {
        switch (f as NSString).pathExtension.lowercased() {
        case "pdf": "doc.richtext"; case "jpg", "jpeg", "png", "heic", "gif": "photo"
        case "xls", "xlsx", "numbers", "csv": "tablecells"; case "zip": "doc.zipper"; default: "doc"
        }
    }
}
