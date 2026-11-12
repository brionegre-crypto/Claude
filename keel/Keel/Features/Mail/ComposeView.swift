import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import Observation

/// Everything needed to open the composer: new mail, reply, reply-all, forward, or a mailto: link.
struct ComposeDraft: Identifiable {
    let id = UUID()
    var accountId: String?
    var to = ""
    var cc = ""
    var bcc = ""
    var subject = ""
    var body = ""
    var replyTo: ReplyContext?
    /// When forwarding, the original's attachments are downloaded and attached automatically.
    var forwardSource: (accountId: String, providerMessageId: String)?
    /// The email being answered, so AI drafting has context.
    var original: EmailMessage?

    static func reply(to e: EmailMessage, all: Bool, accounts: [MailAccount]) -> ComposeDraft {
        let mine = Set(accounts.map { $0.address.lowercased() })
        var d = ComposeDraft(accountId: e.accountId, subject: prefixed("Re:", e.subject), original: e)
        let others = { (line: String) in addressList(line).filter { !mine.contains($0.lowercased()) } }
        d.to = ([e.from] + (all ? others(e.toLine) : [])).filter { !mine.contains($0.lowercased()) }.uniqued.joined(separator: ", ")
        if all { d.cc = others(e.ccLine).uniqued.joined(separator: ", ") }
        var ctx = e.replyContext
        ctx.replyAll = all
        d.replyTo = ctx
        // Outlook's reply endpoint appends the original itself; Gmail needs the quote in the body.
        if accounts.first(where: { $0.id == e.accountId })?.provider == .gmail {
            d.body = "\n\n" + quote(e)
        }
        return d
    }

    static func forward(_ e: EmailMessage) -> ComposeDraft {
        var d = ComposeDraft(accountId: e.accountId, subject: prefixed("Fwd:", e.subject), original: e)
        d.body = """


        ---------- Forwarded message ----------
        From: \(e.fromName) <\(e.from)>
        Date: \(e.receivedAt.formatted(date: .abbreviated, time: .shortened))
        Subject: \(e.subject)
        To: \(e.toLine)

        \(e.bodyPlain)
        """
        if e.hasAttachments { d.forwardSource = (e.accountId, e.providerMessageId) }
        return d
    }

    /// mailto:someone@example.com?subject=Hi&body=…&cc=…
    static func mailto(_ url: URL) -> ComposeDraft {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        func q(_ name: String) -> String { comps?.queryItems?.first { $0.name.lowercased() == name }?.value ?? "" }
        return ComposeDraft(to: comps?.path.removingPercentEncoding ?? "", cc: q("cc"), bcc: q("bcc"), subject: q("subject"), body: q("body"))
    }

    static func prefixed(_ p: String, _ subject: String) -> String {
        subject.lowercased().hasPrefix(p.lowercased()) ? subject : "\(p) \(subject)"
    }

    static func quote(_ e: EmailMessage) -> String {
        let quoted = e.bodyPlain.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n")
        return "On \(e.receivedAt.formatted(date: .abbreviated, time: .shortened)), \(e.fromName.isEmpty ? e.from : e.fromName) wrote:\n\(quoted)"
    }

    static func addressList(_ line: String) -> [String] {
        line.split(whereSeparator: { ",;".contains($0) })
            .map { parseFrom(String($0)).1.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("@") }
    }
}

extension Array where Element == String {
    var uniqued: [String] {
        var seen = Set<String>()
        return filter { seen.insert($0.lowercased()).inserted }
    }
}

/// Lets mailto: links (and anything else) open the composer from anywhere in the app.
@MainActor @Observable
final class MailRouter {
    static let shared = MailRouter()
    var pending: ComposeDraft?
}

struct ComposeView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [MailAccount]
    @State var draft: ComposeDraft
    @State private var accountId = ""
    @State private var alias = ""                 // "" = the account's own address
    @State private var attachments: [OutgoingAttachment] = []
    @State private var showCcBcc = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFiles = false
    @State private var aiPrompt = ""
    @State private var showAI = false
    @State private var aiWorking = false
    @State private var sendCountdown: Int?
    @State private var sendTask: Task<Void, Never>?
    @State private var error: String?
    @State private var loadingForwarded = false
    @FocusState private var bodyFocused: Bool
    @State private var followUpDays: Int? = nil
    @State private var pickSendTime = false
    @State private var sendTime = Date().addingTimeInterval(3600)
    @Environment(\.modelContext) private var ctx

    var body: some View {
        composeBody
            // If you're pulled away mid-email, Keel remembers it and offers it back when you return.
            .savePoint { sendCountdown == nil ? SavePoints.draft(draft, accountId: accountId) : nil }
    }

    @ViewBuilder private var composeBody: some View {
        NavigationStack {
            Form {
                Section {
                    if accounts.count > 1 || !MailAliases.list(accountId).isEmpty {
                        Picker("From", selection: identity) {
                            ForEach(accounts) { a in
                                Text(a.address).tag(a.id + "\n")
                                ForEach(MailAliases.list(a.id), id: \.self) { Text($0).tag(a.id + "\n" + $0) }
                            }
                        }
                    }
                    field("To", text: $draft.to)
                    if showCcBcc || !draft.cc.isEmpty || !draft.bcc.isEmpty {
                        field("Cc", text: $draft.cc)
                        field("Bcc", text: $draft.bcc)
                    } else {
                        Button("Add Cc / Bcc") { showCcBcc = true }.font(DS.Font.caption)
                    }
                    TextField("Subject", text: $draft.subject)
                    Picker(selection: $followUpDays) {
                        ForEach(FollowUps.options, id: \.label) { Text($0.label).tag($0.days) }
                    } label: { Label("Remind me if no reply", systemImage: "bell.badge") }
                }
                Section {
                    // Apple Intelligence Writing Tools (proofread, rewrite, tone) work here automatically.
                    TextEditor(text: $draft.body)
                        .frame(minHeight: 220)
                        .focused($bodyFocused)
                }
                if !attachments.isEmpty || loadingForwarded {
                    Section("Attachments") {
                        if loadingForwarded { ProgressView("Adding the original attachments…") }
                        ForEach(attachments) { a in
                            HStack {
                                Image(systemName: icon(for: a.mimeType))
                                Text(a.filename).lineLimit(1)
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: Int64(a.data.count), countStyle: .file))
                                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                            }
                        }
                        .onDelete { attachments.remove(atOffsets: $0) }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle(draft.replyTo != nil ? "Reply" : (draft.forwardSource != nil || draft.subject.hasPrefix("Fwd:") ? "Forward" : "New Message"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { SavePoints.remove(refId: draft.id.uuidString); dismiss() }.disabled(sendCountdown != nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Section("Send later") {
                            ForEach(SendLater.presets(), id: \.1) { p in
                                Button(p.0, systemImage: "clock") { scheduleSend(at: p.1) }
                            }
                            Button("Pick a time…", systemImage: "calendar.badge.clock") { pickSendTime = true }
                        }
                    } label: { Image(systemName: "paperplane.fill") } primaryAction: { startSend() }
                        .disabled(recipients(draft.to).isEmpty || sendCountdown != nil)
                        .accessibilityLabel("Send. Hold for send later")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) { Image(systemName: "photo") }
                        .accessibilityLabel("Attach photos")
                    Button { showFiles = true } label: { Image(systemName: "paperclip") }.accessibilityLabel("Attach files")
                    SnippetMenu(text: $draft.body, to: draft.to,
                                recipientName: draft.original?.fromName ?? "", subject: draft.subject)
                    Spacer()
                    Button { showAI = true } label: { Label("Write with AI", systemImage: "sparkles") }
                }
            }
            .overlay(alignment: .bottom) { if let n = sendCountdown { undoBar(n) } }
            .sheet(isPresented: $pickSendTime) {
                NavigationStack {
                    Form {
                        DatePicker("Send at", selection: $sendTime, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.graphical)
                        Section { } footer: { Text("Keel sends it at this time. If Keel is closed, iPhone may run it a few minutes later.") }
                    }
                    .navigationTitle("Send Later").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { pickSendTime = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("Schedule") { pickSendTime = false; scheduleSend(at: sendTime) } }
                    }
                }
                .presentationDetents([.large])
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { urls.forEach(addFile) }
            }
            .onChange(of: photoItems) { _, items in Task { await addPhotos(items) } }
            .alert("Write with AI", isPresented: $showAI) {
                TextField("e.g. politely decline, suggest next week", text: $aiPrompt)
                Button("Write") { Task { await writeWithAI() } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Say what you want to say. Keel drafts it; you review before sending.") }
            .interactiveDismissDisabled(sendCountdown != nil || !draft.body.isEmpty)
            .onChange(of: accountId) { old, new in
                // Switching the From account swaps in that account's signature.
                let a = signature(for: old), b = signature(for: new)
                guard a != b, !old.isEmpty else { return }
                if !a.isEmpty, let r = draft.body.range(of: a) { draft.body.replaceSubrange(r, with: b) }
                else if !b.isEmpty { draft.body = "\n\n" + b + draft.body }
            }
            .task {
                accountId = draft.accountId ?? accounts.first?.id ?? ""
                if let o = draft.original, alias.isEmpty, let a = MailAliases.match(o, accountId: accountId) { alias = a }
                let signature = signature(for: accountId)
                if !signature.isEmpty && !draft.body.contains(signature) { draft.body = "\n\n" + signature + draft.body }
                let defaultFollowUp = UserDefaults.standard.integer(forKey: Prefs.followUpDefault)
                if defaultFollowUp > 0 && followUpDays == nil { followUpDays = defaultFollowUp }
                if draft.replyTo == nil && draft.to.isEmpty { bodyFocused = false }
                await loadForwardedAttachments()
            }
        }
    }

    /// One picker for every address you can send from: each account, then its aliases.
    private var identity: Binding<String> {
        Binding(get: { accountId + "\n" + alias }, set: { v in
            let parts = v.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            accountId = parts.first ?? accountId
            alias = parts.count > 1 ? parts[1] : ""
        })
    }

    private func outgoing(for account: MailAccount) -> OutgoingMail {
        var m = OutgoingMail(to: recipients(draft.to), cc: recipients(draft.cc), bcc: recipients(draft.bcc),
                             subject: draft.subject, body: draft.body,
                             replyTo: account.id == draft.accountId ? draft.replyTo : nil,
                             attachments: attachments)
        if !alias.isEmpty && account.id == accountId && alias.lowercased() != account.address.lowercased() { m.fromAlias = alias }
        return m
    }

    /// The sending account's own signature, or the shared one.
    private func signature(for id: String) -> String {
        accounts.first { $0.id == id }?.signature ?? UserDefaults.standard.string(forKey: Prefs.signature) ?? ""
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label).foregroundStyle(DS.Palette.inkSoft).frame(minWidth: 36, alignment: .leading)
            TextField("", text: text)
                .keyboardType(.emailAddress).textContentType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
        }
    }

    private func undoBar(_ seconds: Int) -> some View {
        HStack {
            ProgressView().tint(.white)
            Text("Sending in \(seconds)…").font(DS.Font.headline).foregroundStyle(.white)
            Spacer()
            Button("Undo") {
                sendTask?.cancel(); sendTask = nil
                withAnimation(DS.spring) { sendCountdown = nil }
                Haptics.tap()
            }
            .font(DS.Font.headline).foregroundStyle(.white)
        }
        .padding(DS.Space.m)
        .background(DS.Palette.ink.opacity(0.9), in: Capsule())
        .padding()
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func recipients(_ line: String) -> [String] { ComposeDraft.addressList(line) }

    /// Spark-style undo send: a 5-second window before anything leaves the phone.
    private func startSend() {
        error = nil
        let seconds = UserDefaults.standard.object(forKey: Prefs.undoSeconds) as? Int ?? 5
        guard seconds > 0 else { Task { sendCountdown = 0; await send() }; return }
        withAnimation(DS.spring) { sendCountdown = seconds }
        sendTask = Task {
            for n in stride(from: seconds - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                sendCountdown = n
            }
            await send()
        }
    }

    private func scheduleSend(at date: Date) {
        guard let account = accounts.first(where: { $0.id == accountId }) ?? accounts.first else {
            error = "Add an email account first (Today → profile icon)."; return
        }
        let mail = outgoing(for: account)
        let scheduled = SendLater.schedule(mail, accountId: account.id, at: date, ctx: ctx)
        SavePoints.remove(refId: draft.id.uuidString)
        if let days = followUpDays, let to = mail.to.first {
            FollowUps.create(account: account.id, to: to, name: draft.original?.fromName ?? "", subject: draft.subject, days: days, ctx: ctx)
        }
        Haptics.success()
        UndoCenter.shared.offer("Scheduled for \(date.formatted(date: .abbreviated, time: .shortened))", undo: { [ctx] in ctx.delete(scheduled); try? ctx.save() })
        dismiss()
    }

    private func send() async {
        guard let account = accounts.first(where: { $0.id == accountId }) ?? accounts.first else {
            error = "Add an email account first (Today → profile icon)."; sendCountdown = nil; return
        }
        let mail = outgoing(for: account)
        do {
            try await MailProviderFactory.make(for: account).send(mail)
            SavePoints.remove(refId: draft.id.uuidString)
            if mail.replyTo != nil, let o = draft.original { InboxBrain.record(.reply, sender: o.from, name: o.fromName, ctx: ctx) }
            if let days = followUpDays, let to = mail.to.first {
                FollowUps.create(account: account.id, to: to, name: draft.original?.fromName ?? "", subject: draft.subject, days: days, ctx: ctx)
            }
            Haptics.success()
            dismiss()
        } catch {
            self.error = "Couldn't send: \(error.localizedDescription). Your message is still here."
            sendCountdown = nil
        }
    }

    private func writeWithAI() async {
        guard !aiPrompt.isEmpty else { return }
        aiWorking = true; defer { aiWorking = false }
        let context = draft.original ?? EmailMessage(accountId: accountId, providerMessageId: "new", threadId: "",
                                                     from: draft.to, fromName: draft.to, subject: draft.subject,
                                                     snippet: "", bodyPlain: "(new email, no previous message)",
                                                     receivedAt: Date(), isRead: true)
        if let text = await AIRouter.shared.draftReply(to: context, intent: aiPrompt) {
            let quoteStart = draft.body.range(of: "\n\nOn ")?.lowerBound ?? draft.body.range(of: "\n\n---------- Forwarded")?.lowerBound
            let tail = quoteStart.map { String(draft.body[$0...]) } ?? ""
            draft.body = text + tail
        }
        aiPrompt = ""
    }

    private func addFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        attachments.append(OutgoingAttachment(filename: url.lastPathComponent, mimeType: mime, data: data))
    }

    private func addPhotos(_ items: [PhotosPickerItem]) async {
        for (i, item) in items.enumerated() {
            if let data = try? await item.loadTransferable(type: Data.self) {
                attachments.append(OutgoingAttachment(filename: "Photo \(attachments.count + i + 1).jpg", mimeType: "image/jpeg", data: data))
            }
        }
        photoItems = []
    }

    private func loadForwardedAttachments() async {
        guard let src = draft.forwardSource, attachments.isEmpty,
              let account = accounts.first(where: { $0.id == src.accountId }) else { return }
        loadingForwarded = true; defer { loadingForwarded = false }
        let provider = MailProviderFactory.make(for: account)
        guard let list = try? await provider.attachments(for: src.providerMessageId) else { return }
        for a in list {
            if let data = try? await provider.download(a, messageId: src.providerMessageId) {
                attachments.append(OutgoingAttachment(filename: a.filename, mimeType: a.mimeType, data: data))
            }
        }
    }

    private func icon(for mime: String) -> String {
        mime.hasPrefix("image/") ? "photo" : mime.contains("pdf") ? "doc.richtext" : "doc"
    }
}
