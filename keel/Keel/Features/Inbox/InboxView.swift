import SwiftUI
import Translation
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
    /// The newest 2,500 messages. Older mail is still found by Search (it asks the server), and keeping
    /// the whole history in memory made every sync re-sort everything and stutter the app.
    @Query(InboxView.recentMail) private var allEmails: [EmailMessage]
    static var recentMail: FetchDescriptor<EmailMessage> {
        var d = FetchDescriptor<EmailMessage>(sortBy: [SortDescriptor(\.receivedAt, order: .reverse)])
        d.fetchLimit = 2500
        return d
    }
    @Query private var accounts: [MailAccount]
    @Query private var rules: [SenderRule]
    @AppStorage("focus.hideInbox") private var hiddenByFocus = false
    @State private var mailbox: Mailbox = .inbox
    @AppStorage("inbox.tab") private var tabRaw = InboxTab.priority.rawValue
    @Query private var senderScores: [SenderScore]
    @State private var batchTick = 0
    @State private var accountFilter: String? = nil
    @State private var search = ""
    @State private var serverResults: [EmailMessage] = []
    @State private var searchingServer = false
    @State private var sent: [EmailMessage] = []
    @State private var loadingSent = false
    @State private var compose: ComposeDraft?
    @State private var snoozing: EmailMessage?
    @State private var ruleFrom: EmailMessage?
    @State private var selecting = false
    @State private var unsubCandidates: [UnsubscribeSuggestions.Candidate] = []
    @AppStorage(Prefs.calm) private var calm = false
    @State private var selected = Set<String>()
    @AppStorage(MailSwipe.threadsKey) private var threaded = true
    @AppStorage(MailSwipe.leadingKey) private var leadingRaw = MailSwipe.defaultLeading
    @AppStorage(MailSwipe.trailingKey) private var trailingRaw = MailSwipe.defaultTrailing
    @State private var pickSnoozeDate = false
    @State private var customSnooze = Date().addingTimeInterval(86_400)

    private func inAccount(_ e: EmailMessage) -> Bool { accountFilter == nil || e.accountId == accountFilter }

    private var mailboxEmails: [EmailMessage] {
        if let m = memo.mailbox { return m }
        let m = computeMailbox()
        memo.mailbox = m
        return m
    }

    private func computeMailbox() -> [EmailMessage] {
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
            // Operators like from:sam has:attachment before:friday; plain words work as before.
            let q = mailQuery
            let scores = scoreMap
            let pool = q.inArchive == nil ? base : allEmails.filter(inAccount)
            return pool.filter { q.matches($0, isVIP: scores[$0.from.lowercased()]?.isVIP == true) }
        }
        guard mailbox == .inbox else { return base }
        let scores = scoreMap
        let shown = base.filter { !$0.isPinned && !InboxBrain.isHeld($0, score: scores[$0.from.lowercased()]) }
        if tab == .quick {
            return shown.filter { InboxBrain.isQuickWin($0, score: scores[$0.from.lowercased()]) }.sorted { $0.receivedAt < $1.receivedAt }
        }
        return shown.filter { InboxBrain.tab($0, score: scores[$0.from.lowercased()]) == tab }
            .sorted { a, b in
                let va = scores[a.from.lowercased()]?.isVIP == true, vb = scores[b.from.lowercased()]?.isVIP == true
                return va != vb ? va : a.receivedAt > b.receivedAt
            }
    }

    private var mailQuery: MailQuery { MailQueryParser.parse(search) }

    private var tab: InboxTab { InboxTab(rawValue: tabRaw) ?? .priority }
    private var scoreMap: [String: SenderScore] {
        if let m = memo.scores { return m }
        let m = Dictionary(senderScores.map { ($0.sender, $0) }, uniquingKeysWith: { a, _ in a })
        memo.scores = m
        return m
    }

    /// Lookups shared by every row in one pass, so a big inbox doesn't rescan all mail for each row.
    /// Cleared at the start of each body update, so it always reflects the latest mail.
    private final class Memo {
        var scores: [String: SenderScore]?
        var threads: [String: [EmailMessage]]?
        var mailbox: [EmailMessage]?
        func reset() { scores = nil; threads = nil; mailbox = nil }
    }
    private let memo = Memo()

    private var threadIndex: [String: [EmailMessage]] {
        if let t = memo.threads { return t }
        let t = Dictionary(grouping: mailboxEmails.filter { !$0.threadId.isEmpty }, by: \.threadId)
        memo.threads = t
        return t
    }
    private var tabCounts: [InboxTab: Int] {
        let scores = scoreMap
        let live = mailboxEmails.filter { !$0.isRead && !InboxBrain.isHeld($0, score: scores[$0.from.lowercased()]) }
        var c: [InboxTab: Int] = [:]
        for e in live { c[InboxBrain.tab(e, score: scores[e.from.lowercased()]), default: 0] += 1 }
        c[.quick] = mailboxEmails.filter { InboxBrain.isQuickWin($0, score: scores[$0.from.lowercased()]) }.count
        return c
    }
    private var heldCount: Int {
        _ = batchTick
        guard InboxBrain.batchingOn else { return 0 }
        let scores = scoreMap
        return mailboxEmails.filter { InboxBrain.isHeld($0, score: scores[$0.from.lowercased()]) }.count
    }

    /// Pinned emails sit above every split in Inbox.
    private var pinned: [EmailMessage] {
        mailbox == .inbox && search.isEmpty ? mailboxEmails.filter(\.isPinned) : []
    }

    var body: some View {
        let _ = memo.reset()
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
            .searchable(text: $search, prompt: "Search mail, or try from: has:attachment")
            .searchSuggestions {
                if search.isEmpty {
                    ForEach(MailQueryParser.help, id: \.0) { h in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.0).font(.system(.callout, design: .monospaced)).foregroundStyle(DS.Palette.ink)
                            Text(h.1).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        .searchCompletion(h.0.contains(":") ? String(h.0.prefix { $0 != ":" }) + ":" : h.0)
                    }
                }
            }
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
                        Button(selecting ? "Done Selecting" : "Select Messages", systemImage: "checkmark.circle") {
                            withAnimation { selecting.toggle(); selected = [] }
                        }
                        NavigationLink { QuickRepliesView() } label: { Label("Clear 5 quick replies", systemImage: "bolt.horizontal.circle") }
                        NavigationLink { ScheduledMailView() } label: { Label("Scheduled", systemImage: "clock.arrow.circlepath") }
                        NavigationLink { DigestView() } label: { Label("Newsletter digest", systemImage: "newspaper") }
                        NavigationLink { AttachmentsView() } label: { Label("Attachments", systemImage: "paperclip") }
                        NavigationLink { SubscriptionsView() } label: { Label("Bills & money", systemImage: "creditcard") }
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
            .task { wakeSnoozed(); refreshUnsubscribe() }
            .onChange(of: allEmails.count) { refreshUnsubscribe() }
            .onChange(of: mailbox) { if mailbox == .sent { Task { await loadSent() } } }
        }
    }

    private var list: some View {
        List(selection: $selected) {
            if mailbox == .inbox && search.isEmpty && !selecting && !calm && !unsubCandidates.isEmpty {
                UnsubscribeBanner(candidates: unsubCandidates, provider: provider(for:)) { refreshUnsubscribe() }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .selectionDisabled()
            }
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
            if mailbox == .inbox && search.isEmpty && !selecting {
                InboxTabBar(tab: Binding(get: { tab }, set: { tabRaw = $0.rawValue }), counts: tabCounts, hideCounts: calm)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .selectionDisabled()
                if heldCount > 0 {
                    BatchBanner(waiting: heldCount) { InboxBrain.revealNow(); batchTick += 1; Haptics.tap() }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .selectionDisabled()
                }
            }

            if mailbox == .sent && loadingSent { ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear) }

            if !search.isEmpty && mailQuery.hasOperators {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(DS.Palette.accent)
                        ForEach(mailQuery.chips, id: \.self) { Chip(text: $0, color: DS.Palette.accent) }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .selectionDisabled()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Filters: " + mailQuery.chips.joined(separator: ", "))
            }

            if visible.isEmpty && pinned.isEmpty && !loadingSent && serverResults.isEmpty {
                ContentUnavailableView(search.isEmpty ? "All clear" : "No matches on this phone",
                                       systemImage: search.isEmpty ? "checkmark.seal" : "magnifyingglass",
                                       description: Text(search.isEmpty ? "Nothing here. Nice." : "Press Search to look through all your mail."))
                    .listRowBackground(Color.clear)
            }

            if !pinned.isEmpty {
                Section("Pinned") { ForEach(pinned) { e in row(e) } }
            }
            if mailbox == .inbox && search.isEmpty {
                inboxContent
            } else {
                ForEach(collapse(visible)) { e in row(e) }
            }

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
        .environment(\.editMode, .constant(selecting ? .active : .inactive))
        .safeAreaInset(edge: .bottom) { if selecting { bulkBar } }
        .refreshable {
            await SyncEngine.shared.syncAll()
            wakeSnoozed()
            if mailbox == .sent { await loadSent() }
        }
    }

    // MARK: Smart inbox layout

    @ViewBuilder
    private var inboxContent: some View {
        switch tab {
        case .priority:
            let items = collapse(visible)
            ForEach(["Today", "Yesterday", "This week", "Older"], id: \.self) { name in
                let group = items.filter { InboxBrain.section(for: $0.receivedAt) == name }
                if !group.isEmpty {
                    Section(name) { ForEach(group) { e in row(e) } }
                }
            }
            otherTabsCard
        case .updates, .newsletters:
            if tab == .newsletters {
                HStack {
                    NavigationLink { DigestView() } label: { Label("Read as a digest", systemImage: "newspaper") }
                    Spacer()
                    Button { archiveRead(in: visible) } label: { Label("Clear read", systemImage: "archivebox") }
                }
                .font(DS.Font.caption).buttonStyle(.borderless)
                .selectionDisabled()
            }
            ForEach(SenderBundle.group(visible)) { b in
                if b.emails.count == 1 {
                    row(b.emails[0])
                } else {
                    NavigationLink { SenderBundleView(bundle: b) } label: { SenderBundleRow(bundle: b) }
                        .swipeActions(edge: .trailing) {
                            Button { b.emails.forEach(archive) } label: { Label("Archive all", systemImage: "archivebox") }.tint(DS.Palette.calm)
                        }
                }
            }
        case .quick:
            if !visible.isEmpty {
                NavigationLink { QuickRepliesView() } label: {
                    Label("Clear 5 quick replies, one at a time", systemImage: "bolt.horizontal.circle.fill")
                        .font(DS.Font.headline).foregroundStyle(DS.Palette.accent)
                }
                .selectionDisabled()
                Section {
                    ForEach(collapse(visible)) { e in row(e) }
                } header: { Text("Each of these takes about 2 minutes. Clear a few for momentum.") }
            }
        }
    }

    /// At the bottom of Priority: what's waiting in the other tabs, without letting it crowd your people.
    @ViewBuilder
    private var otherTabsCard: some View {
        let counts = tabCounts
        let u = counts[.updates] ?? 0, n = counts[.newsletters] ?? 0
        if u + n > 0 {
            HStack(spacing: DS.Space.s) {
                if u > 0 { Button { tabRaw = InboxTab.updates.rawValue } label: { Label("\(u) updates", systemImage: "bell") } }
                if n > 0 { Button { tabRaw = InboxTab.newsletters.rawValue } label: { Label("\(n) newsletters", systemImage: "newspaper") } }
                Spacer()
            }
            .font(DS.Font.caption).buttonStyle(.bordered)
            .listRowSeparator(.hidden)
            .selectionDisabled()
        }
    }

    private func archiveRead(in list: [EmailMessage]) {
        let read = list.filter(\.isRead)
        guard !read.isEmpty else { return }
        read.forEach(archive)
    }

    // MARK: Conversations

    private func threadCount(_ e: EmailMessage) -> Int { threadIndex[e.threadId]?.count ?? 1 }

    /// One row per conversation (its newest message) when threading is on.
    private func collapse(_ list: [EmailMessage]) -> [EmailMessage] {
        guard threaded, mailbox != .sent, search.isEmpty else { return list }
        var seen = Set<String>()
        return list.sorted { $0.receivedAt > $1.receivedAt }.filter { seen.insert($0.threadId.isEmpty ? $0.id : $0.threadId).inserted }
    }

    private func conversation(_ e: EmailMessage) -> [EmailMessage] {
        guard threaded, !e.threadId.isEmpty else { return [e] }
        return (threadIndex[e.threadId] ?? [e]).filter { $0.accountId == e.accountId }
    }

    // MARK: Swipes (customizable in Settings → Mail)

    @ViewBuilder
    private func swipeButton(_ action: String, _ e: EmailMessage) -> some View {
        switch action {
        case "archive": Button { archive(e) } label: { Label("Done", systemImage: "checkmark") }.tint(DS.Palette.calm)
        case "trash": Button(role: .destructive) { trash(e) } label: { Label("Trash", systemImage: "trash") }
        case "task": Button { toTask(e) } label: { Label("Task", systemImage: "checklist") }.tint(DS.Palette.warmth)
        case "snooze": Button { snoozing = e } label: { Label("Snooze", systemImage: "clock") }.tint(DS.Palette.meeting)
        case "star": Button { star(e) } label: { Label(e.isStarred ? "Unstar" : "Star", systemImage: e.isStarred ? "star.slash" : "star") }.tint(.yellow)
        case "read": Button { toggleRead(e) } label: { Label(e.isRead ? "Unread" : "Read", systemImage: e.isRead ? "envelope.badge" : "envelope.open") }.tint(.blue)
        case "pin": Button { e.isPinned.toggle(); Haptics.tap() } label: { Label(e.isPinned ? "Unpin" : "Pin", systemImage: "pin") }.tint(.orange)
        default: EmptyView()
        }
    }

    @ViewBuilder
    private func row(_ e: EmailMessage) -> some View {
        let count = threaded && mailbox != .sent ? threadCount(e) : 1
        NavigationLink {
            if count > 1 { ThreadView(messages: conversation(e)) } else { EmailDetailView(email: e) }
        } label: { EmailRow(email: e, count: count, unreadInThread: count > 1 && conversation(e).contains { !$0.isRead }, score: scoreMap[e.from.lowercased()]) }
            .swipeActions(edge: .trailing) {
                ForEach(MailSwipe.actions(trailingRaw).filter { mailbox != .sent || $0 == "task" }, id: \.self) { swipeButton($0, e) }
            }
            .swipeActions(edge: .leading) {
                ForEach(MailSwipe.actions(leadingRaw).filter { mailbox != .sent || $0 == "task" }, id: \.self) { swipeButton($0, e) }
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
                let vip = scoreMap[e.from.lowercased()]?.isVIP == true
                Button(vip ? "Remove VIP" : "Mark Sender as VIP", systemImage: vip ? "star.slash" : "star.circle") {
                    InboxBrain.setVIP(!vip, sender: e.from, name: e.fromName, ctx: ctx); Haptics.success()
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

    private func refreshUnsubscribe() {
        withAnimation(DS.spring) { unsubCandidates = UnsubscribeSuggestions.candidates(allEmails) }
    }

    private func provider(for e: EmailMessage) -> MailProvider? {
        accounts.first { $0.id == e.accountId }.map(MailProviderFactory.make)
    }

    private func archive(_ e: EmailMessage) {
        if !e.isRead { InboxBrain.record(.ignored, sender: e.from, name: e.fromName, ctx: ctx) }
        let group = conversation(e)
        withAnimation(DS.spring) { for m in group { m.isArchived = true; m.snoozedUntil = nil } }
        Haptics.success()
        let p = provider(for: e)
        let ids = group.map(\.providerMessageId)
        // The server archive waits for the undo window to close.
        UndoCenter.shared.offer(group.count > 1 ? "Archived conversation" : "Archived",
                                undo: { withAnimation { for m in group { m.isArchived = false } } },
                                commit: { Task { for id in ids { try? await p?.archive(id) } } })
        checkInboxZero()
    }

    // MARK: Multi-select

    private var selectedEmails: [EmailMessage] {
        mailboxEmails.filter { selected.contains($0.id) }.flatMap(conversation)
    }

    private var bulkBar: some View {
        HStack(spacing: DS.Space.l) {
            Button { bulk { m, p in m.isArchived = true; try? await p?.archive(m.providerMessageId) } } label: { Label("Archive", systemImage: "archivebox") }
            Button { bulk { m, p in m.isRead = true; try? await p?.markRead(m.providerMessageId, read: true) } } label: { Label("Read", systemImage: "envelope.open") }
            Button { bulk { m, p in m.isStarred = true; try? await p?.setStarred(m.providerMessageId, starred: true) } } label: { Label("Star", systemImage: "star") }
            Button(role: .destructive) { bulk { m, p in try? await p?.trash(m.providerMessageId); ctx.delete(m) } } label: { Label("Trash", systemImage: "trash") }
        }
        .labelStyle(.iconOnly).font(.title3)
        .disabled(selected.isEmpty)
        .padding(.horizontal, DS.Space.l).padding(.vertical, DS.Space.m)
        .glassEffect(.regular, in: Capsule())
        .padding(.bottom, DS.Space.s)
    }

    private func bulk(_ action: @escaping (EmailMessage, MailProvider?) async -> Void) {
        let items = selectedEmails
        let pairs = items.map { ($0, provider(for: $0)) }
        Task { for (m, p) in pairs { await action(m, p) } }
        Haptics.success()
        UndoCenter.shared.notify("Updated \(items.count) email\(items.count == 1 ? "" : "s")")
        selected = []
        withAnimation { selecting = false }
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
            // Gmail understands the operators itself; other providers get the plain words.
            let text = a.provider == .gmail ? search : mailQuery.serverText
            guard !text.isEmpty else { continue }
            var q = mailQuery
            q.inArchive = nil              // the server already searched every folder
            let results = (try? await MailProviderFactory.make(for: a).search(text)) ?? []
            found += results.map { EmailMessage(accountId: a.id, fetched: $0) }
                .filter { !localIds.contains($0.id) && (a.provider == .gmail || q.matches($0)) }
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
    var count: Int = 1
    var unreadInThread = false
    var score: SenderScore? = nil

    private var unread: Bool { !email.isRead || unreadInThread }

    /// Up to three small, useful facts: deadline, how long it's waited, invite, attachment, quick win.
    private var chips: [(String, String, Color)] {
        var out: [(String, String, Color)] = []
        let cal = Calendar.current
        if let due = email.extractedDueDate {
            let late = due < cal.startOfDay(for: Date()).addingTimeInterval(86_400)
            out.append(("Due \(cal.isDateInToday(due) ? "today" : cal.isDateInTomorrow(due) ? "tomorrow" : due.formatted(.dateTime.weekday(.abbreviated)))", "calendar.badge.exclamationmark", late ? .red : DS.Palette.warmth))
        }
        let age = Date().timeIntervalSince(email.receivedAt)
        if !email.isRead && age > 86_400 && InboxBrain.tab(email, score: score) == .priority && !MailNoise.isAutomated(email) {
            out.append(("Waiting \(Int(age / 86_400))d", "hourglass", DS.Palette.warmth))
        }
        if email.category == .calendar { out.append(("Invite", "calendar", .blue)) }
        if InboxBrain.isQuickWin(email, score: score) { out.append(("2 min", "bolt.fill", DS.Palette.calm)) }
        if email.hasAttachments { out.append(("Attachment", "paperclip", DS.Palette.inkSoft)) }
        if let task = email.extractedTaskTitle, out.count < 3 { out.append((task, "checklist", DS.Palette.accent)) }
        return Array(out.prefix(3))
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            SenderAvatar(name: email.fromName, email: email.from)
                .overlay(alignment: .topLeading) {
                    if unread { Circle().fill(DS.Palette.accent).frame(width: 10, height: 10).overlay(Circle().stroke(DS.Palette.canvas, lineWidth: 2)).offset(x: -3, y: -3) }
                }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(email.fromName.isEmpty ? email.from : email.fromName)
                        .font(unread ? DS.Font.headline : DS.Font.body).lineLimit(1)
                    if score?.isVIP == true { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                    if count > 1 { Text("\(count)").font(.caption2.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft) }
                    if email.isStarred { Image(systemName: "flag.fill").font(.caption2).foregroundStyle(.orange) }
                    Spacer()
                    Text(Self.time(email.receivedAt)).font(DS.Font.caption).foregroundStyle(unread ? DS.Palette.accent : DS.Palette.inkSoft)
                }
                Text(email.subject).font(DS.Font.body).foregroundStyle(unread ? DS.Palette.ink : DS.Palette.inkSoft).lineLimit(1)
                Text((count > 1 ? "Thread · " : "") + (email.aiSummary ?? email.snippet))
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(count > 1 ? 1 : 2)
                if !chips.isEmpty {
                    HStack(spacing: 4) { ForEach(chips, id: \.0) { MailChip(text: $0.0, icon: $0.1, color: $0.2) } }
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// "9:41 AM" today, "Tue" this week, "Nov 3" otherwise.
    static func time(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
        if d > cal.date(byAdding: .day, value: -6, to: Date())! { return d.formatted(.dateTime.weekday(.abbreviated)) }
        return d.formatted(.dateTime.month(.abbreviated).day())
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
    @State private var readingMode = false
    @State private var eventDraft: EventDraft?
    @State private var readingEvent = false
    @State private var showTranslate = false

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
                    Button("Mark sender as VIP", systemImage: "star.circle") {
                        InboxBrain.setVIP(true, sender: email.from, name: email.fromName, ctx: ctx); Haptics.success()
                        UndoCenter.shared.notify("\(email.fromName.isEmpty ? email.from : email.fromName) is a VIP")
                    }
                    Button(readingEvent ? "Reading…" : "Add to Calendar", systemImage: "calendar.badge.plus") {
                        Task {
                            readingEvent = true
                            let ev = await EmailToEvent.event(from: email)
                            readingEvent = false
                            eventDraft = EventDraft(event: ev, start: ev.startDate)
                        }
                    }
                    Button(showPlain ? "Show formatted" : "Show plain text", systemImage: "doc.plaintext") { showPlain.toggle() }
                    Button(readingMode ? "Exit reading mode" : "Reading mode", systemImage: "text.book.closed") { withAnimation { readingMode.toggle() } }
                    Button("Translate", systemImage: "translate") { showTranslate = true }
                    Button("Move to trash", systemImage: "trash", role: .destructive) { trash() }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("More")
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
        .sheet(item: $eventDraft) { d in EventEditor(event: d.event, start: d.start) { eventDraft = nil }.ignoresSafeArea() }
        .translationPresentation(isPresented: $showTranslate, text: email.subject + "\n\n" + email.bodyPlain)
        .task {
            Dread.recordOpen(email.id)          // Dread Radar notices emails opened again and again
            if !email.isRead {
                InboxBrain.record(.open, sender: email.from, name: email.fromName, ctx: ctx)
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
        if readingMode {
            ReadingModeText(text: email.bodyPlain)
        } else if let html = email.bodyHTML, !showPlain {
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
                    Button { draft = WritingStyle.availabilityReply(to: email.fromName) } label: {
                        Label("Offer my times", systemImage: "calendar.badge.clock")
                    }
                    .font(DS.Font.caption).buttonStyle(.bordered).tint(DS.Palette.meeting)
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
        InboxBrain.record(.reply, sender: email.from, name: email.fromName, ctx: ctx)
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
