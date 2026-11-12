import SwiftUI
import SwiftData
import QuickLook

/// Unified mail across Gmail, Outlook and iCloud (Spark/Superhuman style):
/// AI split inbox, Starred / Snoozed / Sent / Archive mailboxes, search (on-phone and all-mail),
/// compose, swipe actions, formatted emails and attachments.
enum Mailbox: String, CaseIterable, Identifiable {
    case inbox = "Inbox", screener = "Screener", starred = "Starred", snoozed = "Snoozed", awaiting = "Awaiting reply", sent = "Sent", archive = "Archive"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .inbox: "tray"; case .screener: "person.crop.circle.badge.questionmark"; case .starred: "star"; case .snoozed: "clock"; case .awaiting: "bubble.left.and.exclamationmark.bubble.right"
        case .sent: "paperplane"; case .archive: "archivebox"
        }
    }
}

struct InboxView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \EmailMessage.receivedAt, order: .reverse) private var allEmails: [EmailMessage]
    @Query private var accounts: [MailAccount]
    @Query private var rules: [SenderRule]
    @AppStorage("focus.hideInbox") private var hiddenByFocus = false
    @State private var mailbox: Mailbox = .inbox
    @State private var split: TriageCategory = .important
    @State private var accountFilter: String? = nil
    @State private var search = ""
    @State private var serverResults: [EmailMessage] = []
    @State private var searchingServer = false
    @State private var sent: [EmailMessage] = []
    @State private var loadingSent = false
    @State private var compose: ComposeDraft?
    @State private var snoozing: EmailMessage?
    @State private var ruleFrom: EmailMessage?
    @State private var pickSnoozeDate = false
    @State private var customSnooze = Date().addingTimeInterval(86_400)

    private func inAccount(_ e: EmailMessage) -> Bool { accountFilter == nil || e.accountId == accountFilter }

    private var mailboxEmails: [EmailMessage] {
        switch mailbox {
        case .inbox: allEmails.filter { !$0.isArchived && inAccount($0) }
        case .starred: allEmails.filter { $0.isStarred && inAccount($0) }
        case .snoozed: allEmails.filter { $0.snoozedUntil != nil && inAccount($0) }
        case .archive: allEmails.filter { $0.isArchived && $0.snoozedUntil == nil && inAccount($0) }
        case .sent: sent.filter(inAccount)
        case .awaiting, .screener: []
        }
    }

    private var visible: [EmailMessage] {
        let base = mailboxEmails
        if !search.isEmpty {
            let q = search.lowercased()
            return base.filter { [$0.subject, $0.fromName, $0.from, $0.snippet, $0.bodyPlain, $0.toLine]
                .contains { $0.lowercased().contains(q) } }
        }
        return mailbox == .inbox ? base.filter { ($0.category ?? .important) == split && !$0.isPinned } : base
    }

    /// Pinned emails sit above every split in Inbox.
    private var pinned: [EmailMessage] {
        mailbox == .inbox && search.isEmpty ? mailboxEmails.filter(\.isPinned) : []
    }

    var body: some View {
        NavigationStack {
            Group {
                if mailbox == .awaiting {
                    FollowUpsView()
                } else if mailbox == .screener {
                    ScreenerView()
                } else if mailbox == .inbox && (hiddenByFocus || ShutdownManager.shared.active != nil) {
                    ContentUnavailableView("Inbox is resting", systemImage: "moon.zzz",
                                           description: Text("You're in focus mode. Email will be here when you're done."))
                } else {
                    list
                }
            }
            .navigationTitle(mailbox.rawValue)
            .searchable(text: $search, prompt: "Search mail")
            .onSubmit(of: .search) { Task { await searchServer() } }
            .onChange(of: search) { if search.isEmpty { serverResults = [] } }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Mailbox", selection: $mailbox) {
                            ForEach(Mailbox.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                        }
                        Divider()
                        Picker("Account", selection: $accountFilter) {
                            Text("All accounts").tag(String?.none)
                            ForEach(accounts) { a in Text("\(a.provider.displayName) · \(a.address)").tag(Optional(a.id)) }
                        }
                    } label: { Image(systemName: "sidebar.left") }
                    .accessibilityLabel("Mailboxes and accounts")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { CatchUpView() } label: { Image(systemName: "sparkles") }
                        .accessibilityLabel("Catch me up")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink { ScheduledMailView() } label: { Label("Scheduled", systemImage: "clock.arrow.circlepath") }
                        NavigationLink { DigestView() } label: { Label("Newsletter digest", systemImage: "newspaper") }
                        NavigationLink { AttachmentsView() } label: { Label("Attachments", systemImage: "paperclip") }
                        NavigationLink { SubscriptionsView() } label: { Label("Subscriptions & bills", systemImage: "creditcard") }
                        NavigationLink { DeliveriesView() } label: { Label("Deliveries", systemImage: "shippingbox") }
                        NavigationLink { TripsView() } label: { Label("Trips", systemImage: "airplane") }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("More mail tools")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { compose = ComposeDraft(accountId: accountFilter) } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("New message")
                }
            }
            .sheet(item: $compose) { ComposeView(draft: $0) }
            .sheet(item: $ruleFrom) { MailRuleEditor(rule: nil, prefillField: "from", prefillText: $0.from) }
            .confirmationDialog("Snooze until…", isPresented: Binding(get: { snoozing != nil && !pickSnoozeDate }, set: { if !$0 && !pickSnoozeDate { snoozing = nil } }), titleVisibility: .visible) {
                ForEach(Self.snoozeOptions(), id: \.0) { option in
                    Button("\(option.0) · \(option.1.formatted(date: .abbreviated, time: .shortened))") {
                        if let e = snoozing { snooze(e, until: option.1) }
                        snoozing = nil
                    }
                }
                Button("Pick a date…") { pickSnoozeDate = true }
            }
            .sheet(isPresented: $pickSnoozeDate) {
                NavigationStack {
                    DatePicker("Snooze until", selection: $customSnooze, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical).padding()
                        .navigationTitle("Snooze until")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { pickSnoozeDate = false; snoozing = nil } }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Snooze") {
                                    if let e = snoozing { snooze(e, until: customSnooze) }
                                    pickSnoozeDate = false; snoozing = nil
                                }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
            .task { wakeSnoozed() }
            .onChange(of: mailbox) { if mailbox == .sent { Task { await loadSent() } } }
        }
    }

    private var list: some View {
        List {
            if mailbox == .inbox && search.isEmpty && Screener.enabled {
                let newSenders = Screener.pending(emails: allEmails, rules: rules).count
                if newSenders > 0 {
                    Button { mailbox = .screener } label: {
                        Label("\(newSenders) new sender\(newSenders == 1 ? "" : "s") to screen", systemImage: "person.crop.circle.badge.questionmark")
                            .font(DS.Font.caption)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            if mailbox == .inbox && search.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(TriageCategory.allCases) { c in
                                let n = mailboxEmails.filter { ($0.category ?? .important) == c && !$0.isRead }.count
                                Button { withAnimation(DS.spring) { split = c }; Haptics.tap() } label: {
                                    Chip(text: "\(c.rawValue.capitalized)\(n > 0 ? " \(n)" : "")",
                                         color: split == c ? DS.Palette.category(c) : .gray)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listRowBackground(Color.clear)
            }

            if mailbox == .sent && loadingSent { ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear) }

            if visible.isEmpty && pinned.isEmpty && !loadingSent && serverResults.isEmpty {
                ContentUnavailableView(search.isEmpty ? "All clear" : "No matches on this phone",
                                       systemImage: search.isEmpty ? "checkmark.seal" : "magnifyingglass",
                                       description: Text(search.isEmpty ? "Nothing here. Nice." : "Press Search to look through all your mail."))
                    .listRowBackground(Color.clear)
            }

            if !pinned.isEmpty {
                Section("Pinned") { ForEach(pinned) { e in row(e) } }
            }
            ForEach(visible) { e in row(e) }

            if !search.isEmpty {
                Section {
                    if searchingServer {
                        ProgressView("Searching all mail…")
                    } else if serverResults.isEmpty {
                        Button { Task { await searchServer() } } label: {
                            Label("Search all mail for “\(search)”", systemImage: "magnifyingglass.circle")
                        }
                    }
                    ForEach(serverResults) { e in
                        NavigationLink { EmailDetailView(email: e) } label: { EmailRow(email: e) }
                    }
                } header: { if !serverResults.isEmpty { Text("All mail") } }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await SyncEngine.shared.syncAll()
            wakeSnoozed()
            if mailbox == .sent { await loadSent() }
        }
    }

    @ViewBuilder
    private func row(_ e: EmailMessage) -> some View {
        NavigationLink { EmailDetailView(email: e) } label: { EmailRow(email: e) }
            .swipeActions(edge: .trailing) {
                if mailbox != .sent {
                    Button { archive(e) } label: { Label("Done", systemImage: "checkmark") }.tint(DS.Palette.calm)
                    Button(role: .destructive) { trash(e) } label: { Label("Trash", systemImage: "trash") }
                }
            }
            .swipeActions(edge: .leading) {
                Button { toTask(e) } label: { Label("Task", systemImage: "checklist") }.tint(DS.Palette.warmth)
                if mailbox != .sent {
                    Button { snoozing = e } label: { Label("Snooze", systemImage: "clock") }.tint(DS.Palette.meeting)
                    Button { star(e) } label: { Label(e.isStarred ? "Unstar" : "Star", systemImage: e.isStarred ? "star.slash" : "star") }.tint(.yellow)
                }
            }
            .contextMenu {
                Button("Reply", systemImage: "arrowshape.turn.up.left") { compose = .reply(to: e, all: false, accounts: accounts) }
                Button("Reply All", systemImage: "arrowshape.turn.up.left.2") { compose = .reply(to: e, all: true, accounts: accounts) }
                Button("Forward", systemImage: "arrowshape.turn.up.right") { compose = .forward(e) }
                Divider()
                Button(e.isRead ? "Mark Unread" : "Mark Read", systemImage: e.isRead ? "envelope.badge" : "envelope.open") { toggleRead(e) }
                Button(e.isStarred ? "Unstar" : "Star", systemImage: "star") { star(e) }
                Button(e.isPinned ? "Unpin" : "Pin to Top", systemImage: e.isPinned ? "pin.slash" : "pin") {
                    withAnimation(DS.spring) { e.isPinned.toggle() }; Haptics.tap()
                }
                Button("Create Rule…", systemImage: "line.3.horizontal.decrease.circle") { ruleFrom = e }
                if e.category == .newsletters || e.category == .promotions || Unsubscribe.canUnsubscribe(e) {
                    Button("Unsubscribe & archive all", systemImage: "hand.raised.slash") {
                        Task { _ = await Unsubscribe.run(e, provider: provider(for: e), ctx: ctx) }
                    }
                }
            }
    }

    // MARK: Actions (local first, then the server)

    private func provider(for e: EmailMessage) -> MailProvider? {
        accounts.first { $0.id == e.accountId }.map(MailProviderFactory.make)
    }

    private func archive(_ e: EmailMessage) {
        withAnimation(DS.spring) { e.isArchived = true; e.snoozedUntil = nil }
        Haptics.success()
        let p = provider(for: e)
        let id = e.providerMessageId
        // The server archive waits for the undo window to close.
        UndoCenter.shared.offer("Archived", undo: { withAnimation { e.isArchived = false } },
                                commit: { Task { try? await p?.archive(id) } })
        checkInboxZero()
    }

    private func trash(_ e: EmailMessage) {
        let id = e.providerMessageId
        let p = provider(for: e)
        withAnimation(DS.spring) { ctx.delete(e) }
        Haptics.tap()
        Task { try? await p?.trash(id) }
    }

    private func star(_ e: EmailMessage) {
        e.isStarred.toggle()
        Haptics.tap()
        let starred = e.isStarred
        Task { try? await provider(for: e)?.setStarred(e.providerMessageId, starred: starred) }
    }

    private func toggleRead(_ e: EmailMessage) {
        e.isRead.toggle()
        let read = e.isRead
        Task { try? await provider(for: e)?.markRead(e.providerMessageId, read: read) }
    }

    /// Snooze hides it on this phone only; it comes back to the inbox at the chosen time.
    private func snooze(_ e: EmailMessage, until date: Date) {
        withAnimation(DS.spring) {
            e.snoozedUntil = date
            e.isArchived = true
        }
        Haptics.tap()
    }

    static func snoozeOptions() -> [(String, Date)] {
        let cal = Calendar.current
        let now = Date()
        func at(_ h: Int, days: Int = 0) -> Date {
            cal.date(bySettingHour: h, minute: 0, second: 0, of: cal.date(byAdding: .day, value: days, to: now)!)!
        }
        var out: [(String, Date)] = [("Later today", now.addingTimeInterval(3 * 3600))]
        if cal.component(.hour, from: now) < 17 { out.append(("This evening", at(18))) }
        out.append(("Tomorrow morning", at(8, days: 1)))
        let weekday = cal.component(.weekday, from: now)
        if weekday != 7 && weekday != 1 { out.append(("This weekend", at(9, days: 7 - weekday))) }
        out.append(("Next week", at(8, days: (9 - weekday) % 7 == 0 ? 7 : (9 - weekday) % 7)))
        return out
    }

    private func wakeSnoozed() {
        for e in allEmails where (e.snoozedUntil ?? .distantFuture) <= Date() {
            e.snoozedUntil = nil
            e.isArchived = false
        }
    }

    private func toTask(_ e: EmailMessage) {
        let t = TaskItem(title: e.extractedTaskTitle ?? "Reply: \(e.subject)", dueDate: e.extractedDueDate, priority: .medium)
        t.sourceEmailId = e.id
        ctx.insert(t)
        try? CalendarService.shared.push(t)
        Haptics.success()
    }

    private func checkInboxZero() {
        if allEmails.filter({ !$0.isArchived }).isEmpty {
            Haptics.milestone()
            Momentum.recordInboxZero()
        }
    }

    private func searchServer() async {
        guard !search.isEmpty else { return }
        searchingServer = true; defer { searchingServer = false }
        var found: [EmailMessage] = []
        let localIds = Set(allEmails.map(\.id))
        for a in accounts where accountFilter == nil || a.id == accountFilter {
            let results = (try? await MailProviderFactory.make(for: a).search(search)) ?? []
            found += results.map { EmailMessage(accountId: a.id, fetched: $0) }.filter { !localIds.contains($0.id) }
        }
        serverResults = found.sorted { $0.receivedAt > $1.receivedAt }
    }

    private func loadSent() async {
        loadingSent = true; defer { loadingSent = false }
        var out: [EmailMessage] = []
        for a in accounts {
            let msgs = (try? await MailProviderFactory.make(for: a).fetchSent(since: Date().addingTimeInterval(-30 * 86_400))) ?? []
            out += msgs.map { m in
                let e = EmailMessage(accountId: a.id, fetched: m)
                e.toLine = m.from          // fetchSent puts the recipient in `from`
                return e
            }
        }
        sent = out.sorted { $0.receivedAt > $1.receivedAt }
    }
}

struct EmailRow: View {
    let email: EmailMessage
    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            Circle().fill(email.isRead ? .clear : DS.Palette.accent).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(email.fromName.isEmpty ? email.from : email.fromName).font(DS.Font.headline).lineLimit(1)
                    if email.isStarred { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                    if email.hasAttachments { Image(systemName: "paperclip").font(.caption2).foregroundStyle(DS.Palette.inkSoft) }
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
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [MailAccount]
    @State private var intent = ""
    @State private var draft = ""
    @State private var drafting = false
    @State private var htmlHeight: CGFloat = 200
    @State private var loadRemote = false
    @AppStorage(Prefs.loadImages) private var alwaysLoadImages = false
    @State private var showPlain = false
    @State private var attachments: [MailAttachment] = []
    @State private var downloading: String?
    @State private var previewURL: URL?
    @State private var compose: ComposeDraft?
    @State private var sentFlash = false
    @State private var unsubscribing = false
    @State private var unsubscribeMessage: String?
    @State private var replyIdeas: [String] = []

    private var provider: MailProvider? {
        accounts.first { $0.id == email.accountId }.map(MailProviderFactory.make)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                header
                if let s = email.aiSummary {
                    GlassCard(tint: DS.Palette.accent) { Label(s, systemImage: "sparkles").font(DS.Font.body) }
                }
                if email.category == .newsletters || email.category == .promotions || Unsubscribe.canUnsubscribe(email) {
                    unsubscribeBanner
                }
                if !attachments.isEmpty { attachmentStrip }
                bodyView
                Divider()
                quickReply
            }
            .padding()
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { toggleStar() } label: { Image(systemName: email.isStarred ? "star.fill" : "star") }
                    .tint(email.isStarred ? .yellow : nil).accessibilityLabel(email.isStarred ? "Unstar" : "Star")
                Button { archive() } label: { Image(systemName: "archivebox") }.accessibilityLabel("Archive")
                Menu {
                    Button("Mark unread", systemImage: "envelope.badge") { email.isRead = false; Task { try? await provider?.markRead(email.providerMessageId, read: false) } }
                    Button("Make it a task", systemImage: "checklist") { makeTask() }
                    Button(showPlain ? "Show formatted" : "Show plain text", systemImage: "doc.plaintext") { showPlain.toggle() }
                    Button("Move to trash", systemImage: "trash", role: .destructive) { trash() }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button { compose = .reply(to: email, all: false, accounts: accounts) } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
                Spacer()
                Button { compose = .reply(to: email, all: true, accounts: accounts) } label: { Label("Reply All", systemImage: "arrowshape.turn.up.left.2") }
                Spacer()
                Button { compose = .forward(email) } label: { Label("Forward", systemImage: "arrowshape.turn.up.right") }
            }
        }
        .sheet(item: $compose) { ComposeView(draft: $0) }
        .quickLookPreview($previewURL)
        .task {
            if !email.isRead {
                email.isRead = true
                try? await provider?.markRead(email.providerMessageId, read: true)
            }
            if email.hasAttachments, let list = try? await provider?.attachments(for: email.providerMessageId) {
                attachments = list
            }
            if email.category == .important || email.category == .actionable || email.category == .calendar || email.category == nil {
                replyIdeas = await AIRouter.shared.replyIdeas(for: email)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(email.subject).font(DS.Font.title).textSelection(.enabled)
            Text("\(email.fromName.isEmpty ? email.from : email.fromName) · \(email.from)")
                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            if !email.toLine.isEmpty {
                Text("To: \(email.toLine)\(email.ccLine.isEmpty ? "" : "  Cc: \(email.ccLine)")")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
            }
            Text(email.receivedAt.formatted(date: .abbreviated, time: .shortened)).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
        }
    }

    @ViewBuilder
    private var bodyView: some View {
        if let html = email.bodyHTML, !showPlain {
            if !loadRemote && !alwaysLoadImages && HTMLMailView.hasRemoteContent(html) {
                Button { loadRemote = true } label: {
                    Label("Images blocked to stop tracking · Load images", systemImage: "eye.slash")
                        .font(DS.Font.caption)
                }
                .buttonStyle(.bordered)
            }
            HTMLMailView(html: html, allowRemote: loadRemote || alwaysLoadImages, height: $htmlHeight)
                .frame(height: htmlHeight)
                .clipShape(.rect(cornerRadius: DS.Radius.chip))
        } else {
            Text(email.bodyPlain).font(DS.Font.body).textSelection(.enabled)
        }
    }

    private var unsubscribeBanner: some View {
        HStack {
            Image(systemName: "hand.raised.slash").foregroundStyle(DS.Palette.warmth)
            Text(unsubscribeMessage ?? "Don't want these anymore?").font(DS.Font.caption)
            Spacer()
            if unsubscribeMessage == nil {
                Button(unsubscribing ? "Working…" : "Unsubscribe") {
                    Task {
                        unsubscribing = true
                        let outcome = await Unsubscribe.run(email, provider: provider, ctx: ctx)
                        unsubscribing = false
                        switch outcome {
                        case .done: unsubscribeMessage = "Unsubscribed. Past emails archived."
                        case .openedWebPage: unsubscribeMessage = "Finish on the sender's page. Past emails archived."
                        case .unavailable: unsubscribeMessage = "This sender doesn't offer an unsubscribe link."
                        }
                    }
                }
                .font(DS.Font.caption).buttonStyle(.bordered).disabled(unsubscribing)
            }
        }
        .padding(DS.Space.s)
        .background(DS.Palette.warmth.opacity(0.1), in: .rect(cornerRadius: DS.Radius.chip))
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(attachments) { a in
                    Button { Task { await open(a) } } label: {
                        HStack(spacing: 6) {
                            if downloading == a.id { ProgressView() } else {
                                Image(systemName: a.mimeType.hasPrefix("image/") ? "photo" : a.mimeType.contains("pdf") ? "doc.richtext" : "doc")
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(a.filename).font(DS.Font.caption).lineLimit(1)
                                Text(ByteCountFormatter.string(fromByteCount: Int64(a.size), countStyle: .file))
                                    .font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.chip))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var quickReply: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("Quick reply").font(DS.Font.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(replyIdeas, id: \.self) { idea in
                        Button { intent = idea; Task { await makeDraft() } } label: { Label(idea, systemImage: "sparkles") }
                            .font(DS.Font.caption).buttonStyle(.bordered).tint(DS.Palette.accent)
                    }
                    ForEach(["Yes, sounds good", "Can't make it", "Need more time", "Thanks!"], id: \.self) { quick in
                        Button(quick) { intent = quick; Task { await makeDraft() } }.font(DS.Font.caption).buttonStyle(.bordered)
                    }
                }
            }
            TextField("Or say what you want to reply…", text: $intent).textFieldStyle(.roundedBorder)
                .onSubmit { Task { await makeDraft() } }
            if drafting { ProgressView() }
            if !draft.isEmpty {
                TextEditor(text: $draft).frame(minHeight: 140)
                    .padding(DS.Space.s).background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.chip))
                HStack {
                    Button { quickSend() } label: { Label("Send", systemImage: "paperplane.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(DS.Palette.accent)
                    Button("Edit") {
                        var d = ComposeDraft.reply(to: email, all: false, accounts: accounts)
                        d.body = draft + d.body
                        compose = d
                    }
                    .buttonStyle(.bordered)
                }
            }
            if sentFlash { Label("Sent", systemImage: "checkmark.circle.fill").foregroundStyle(DS.Palette.calm) }
        }
    }

    private func makeDraft() async {
        drafting = true; defer { drafting = false }
        draft = await AIRouter.shared.draftReply(to: email, intent: intent) ?? ""
    }

    private func quickSend() {
        let body = draft
        Task {
            try? await provider?.send(to: email.from, subject: ComposeDraft.prefixed("Re:", email.subject),
                                      body: body, inReplyTo: email.replyContext)
            Haptics.success()
            draft = ""; intent = ""
            withAnimation { sentFlash = true }
        }
    }

    private func open(_ a: MailAttachment) async {
        downloading = a.id; defer { downloading = nil }
        guard let data = try? await provider?.download(a, messageId: email.providerMessageId) else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(a.filename.replacingOccurrences(of: "/", with: "-"))
        if (try? data.write(to: url)) != nil { previewURL = url }
    }

    private func toggleStar() {
        email.isStarred.toggle()
        let s = email.isStarred
        Task { try? await provider?.setStarred(email.providerMessageId, starred: s) }
    }

    private func archive() {
        email.isArchived = true
        Haptics.success()
        Task { try? await provider?.archive(email.providerMessageId) }
        dismiss()
    }

    private func trash() {
        let id = email.providerMessageId
        let p = provider
        ctx.delete(email)
        Task { try? await p?.trash(id) }
        dismiss()
    }

    private func makeTask() {
        let t = TaskItem(title: email.extractedTaskTitle ?? "Reply: \(email.subject)", dueDate: email.extractedDueDate, priority: .medium)
        t.sourceEmailId = email.id
        ctx.insert(t)
        try? CalendarService.shared.push(t)
        Haptics.success()
    }
}
