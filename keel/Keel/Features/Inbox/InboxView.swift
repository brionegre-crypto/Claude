import SwiftUI
import Translation
import SwiftData
import QuickLook

/// Unified mail across Gmail, Outlook and iCloud (Spark/Superhuman style):
/// AI split inbox, Starred / Snoozed / Sent / Archive mailboxes, search (on-phone and all-mail),
/// compose, swipe actions, formatted emails and attachments.
enum Mailbox: String, CaseIterable, Identifiable {
    case inbox = "Inbox", screener = "Screener", starred = "Flagged", snoozed = "Snoozed", awaiting = "Awaiting reply", sent = "Sent", archive = "Archive"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .inbox: "tray"; case .screener: "person.crop.circle.badge.questionmark"; case .starred: "flag"; case .snoozed: "clock"; case .awaiting: "bubble.left.and.exclamationmark.bubble.right"
        case .sent: "paperplane"; case .archive: "archivebox"
        }
    }
}

struct InboxView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var multiWindow
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
    @AppStorage("inbox.tab") private var tabRaw = InboxTab.all.rawValue
    @AppStorage("inbox.allTabIntroduced") private var allTabIntroduced = false
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
    @State private var confirmReadAll = false
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

    /// Worked out once per screen update (it's used in several places), not once per use.
    private var visible: [EmailMessage] {
        if let v = memo.visible { return v }
        let v = computeVisible()
        memo.visible = v
        return v
    }

    private func computeVisible() -> [EmailMessage] {
        let base = mailboxEmails
        if !activeSearch.isEmpty {
            // Operators like from:sam has:attachment before:friday; plain words work as before.
            // Searches every mailbox (Inbox, Archive, Starred, Snoozed) unless you chose "This mailbox only".
            let q = mailQuery
            let scores = scoreMap
            let everywhere = q.inArchive != nil || (!searchThisMailbox && mailbox != .sent)
            let pool = everywhere ? allEmails.filter(inAccount) : base
            return pool.filter { q.matches($0, isVIP: scores[$0.from.lowercased()]?.isVIP == true) }
                .sorted { $0.receivedAt > $1.receivedAt }
        }
        guard mailbox == .inbox else { return base }
        if let c = customTab { return base.filter { !$0.isPinned && MailTabs.matches($0, c) }.sorted { $0.receivedAt > $1.receivedAt } }
        // All: a regular inbox. Every account, newest first, nothing sorted away or held back.
        if tab == .all { return base.filter { !$0.isPinned }.sorted { $0.receivedAt > $1.receivedAt } }
        let scores = scoreMap
        let shown = base.filter { !$0.isPinned && !InboxBrain.isHeld($0, score: scores[$0.from.lowercased()]) }
        if tab == .quick {
            return shown.filter { InboxBrain.isQuickWin($0, score: scores[$0.from.lowercased()]) }.sorted { $0.receivedAt < $1.receivedAt }
        }
        // Brand-new mail (unread, last 3 hours) always shows first, whichever tab it would be sorted into,
        // with a "Sort to …" suggestion on the row, so nothing new is filed away before you've seen it.
        let cutoff = Date().addingTimeInterval(-3 * 3600)
        let fresh = shown.filter { !$0.isRead && $0.receivedAt > cutoff }.sorted { $0.receivedAt > $1.receivedAt }
        let freshIds = Set(fresh.map(\.id))
        return fresh + shown.filter { !freshIds.contains($0.id) && InboxBrain.tab($0, score: scores[$0.from.lowercased()]) == tab }
            .sorted { a, b in
                let va = scores[a.from.lowercased()]?.isVIP == true, vb = scores[b.from.lowercased()]?.isVIP == true
                return va != vb ? va : a.receivedAt > b.receivedAt
            }
    }

    private var mailQuery: MailQuery { MailQueryParser.parse(activeSearch) }
    /// What's searched: follows typing a beat behind, so every letter stays instant on a big mailbox.
    @State private var liveSearch = ""
    private var activeSearch: String { search.isEmpty ? "" : (liveSearch.isEmpty ? search : liveSearch) }
    @AppStorage("mail.search.thisMailbox") private var searchThisMailbox = false
    /// Words to light up in each row while searching.
    private var searchHighlights: [String] {
        guard !activeSearch.isEmpty else { return [] }
        let q = mailQuery
        return (q.phrases + q.words + q.subject + q.from).filter { !$0.isEmpty }.sorted { $0.count > $1.count }
    }

    private var inboxHorizonDetail: String {
        let unread = mailboxEmails.filter { !$0.isRead }
        let people = unread.filter { AutoDrafts.isRealPerson($0) }.count
        return unread.isEmpty ? "All caught up · \(HorizonSky.daylightLeft())" : "\(people) need you · \(unread.count - people) can wait"
    }

    /// Which inbox each email came to, when there's more than one account.
    private var accountTags: [String: AccountTag] {
        guard accounts.count > 1 else { return [:] }
        let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .brown]
        let sorted = accounts.sorted { $0.address < $1.address }
        let locals = sorted.map { String($0.address.split(separator: "@").first ?? "") }
        var out: [String: AccountTag] = [:]
        for (i, a) in sorted.enumerated() {
            // The part before @, unless two accounts share it (then the provider).
            let local = locals[i]
            let label = locals.filter { $0 == local }.count > 1 ? a.provider.displayName : local
            out[a.id] = AccountTag(label: String(label.prefix(12)), color: palette[i % palette.count])
        }
        return out
    }

    /// A tab you made (Settings → Look & Feel → Inbox tabs) shows like All, filtered to its rule.
    private var customTab: CustomMailTab? { MailTabs.tab(for: tabRaw) }
    private var tab: InboxTab { InboxTab(rawValue: tabRaw) ?? .all }
    private var tabBarCounts: [String: Int] {
        var out = Dictionary(uniqueKeysWithValues: tabCounts.map { ($0.key.rawValue, $0.value) })
        let unread = mailboxEmails.filter { !$0.isRead }
        for c in MailTabs.custom { out[c.key] = unread.filter { MailTabs.matches($0, c) }.count }
        return out
    }
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
        var visible: [EmailMessage]?
        var tabCounts: [InboxTab: Int]?
        func reset() { scores = nil; threads = nil; mailbox = nil; visible = nil; tabCounts = nil }
    }
    private let memo = Memo()

    private var threadIndex: [String: [EmailMessage]] {
        if let t = memo.threads { return t }
        let t = Dictionary(grouping: mailboxEmails.filter { !$0.threadId.isEmpty }, by: \.threadId)
        memo.threads = t
        return t
    }
    private var tabCounts: [InboxTab: Int] {
        if let c = memo.tabCounts { return c }
        let c = computeTabCounts()
        memo.tabCounts = c
        return c
    }

    private func computeTabCounts() -> [InboxTab: Int] {
        let scores = scoreMap
        let live = mailboxEmails.filter { !$0.isRead && !InboxBrain.isHeld($0, score: scores[$0.from.lowercased()]) }
        var c: [InboxTab: Int] = [:]
        for e in live { c[InboxBrain.tab(e, score: scores[e.from.lowercased()]), default: 0] += 1 }
        c[.quick] = mailboxEmails.filter { InboxBrain.isQuickWin($0, score: scores[$0.from.lowercased()]) }.count
        c[.all] = mailboxEmails.filter { !$0.isRead }.count
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
        SplitOrStack(placeholder: "Select an email", icon: "envelope.open") {
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
            .keelSettingsButton(help: .inbox)
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
            .task(id: search) {
                if search.isEmpty { liveSearch = ""; return }
                if liveSearch.isEmpty { liveSearch = search; return }          // first letter: right away
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                liveSearch = search
            }
            .environment(\.mailSearchTerms, searchHighlights)
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
                    NavigationLink { LazyView(CatchUpView()) } label: { Image(systemName: "sparkles") }
                        .accessibilityLabel("Catch me up")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(selecting ? "Done Selecting" : "Select Messages", systemImage: "checkmark.circle") {
                            withAnimation { selecting.toggle(); selected = [] }
                        }
                        Button("Mark All as Read", systemImage: "envelope.open") { confirmReadAll = true }
                            .disabled(!visible.contains { !$0.isRead })
                        Menu("Get me to zero", systemImage: "sparkles.rectangle.stack") {
                            Button("Archive everything older than a day") { getToZero(days: 1) }
                            Button("Older than a week") { getToZero(days: 7) }
                            Button("Older than a month") { getToZero(days: 30) }
                        }
                        Section("Get through it") {
                            NavigationLink { LazyView(CatchUpView()) } label: { Label("Catch me up", systemImage: "sparkles") }
                            NavigationLink { LazyView(QuickRepliesView()) } label: { Label("Clear 5 quick replies", systemImage: "bolt.horizontal.circle") }
                            NavigationLink { LazyView(FollowUpsView()) } label: { Label("Waiting on a reply", systemImage: "arrowshape.turn.up.left") }
                            NavigationLink { LazyView(ScreenerView()) } label: { Label("Screen new senders", systemImage: "person.crop.circle.badge.questionmark") }
                        }
                        Section("Find") {
                            NavigationLink { LazyView(AskInboxView()) } label: { Label("Ask your inbox", systemImage: "questionmark.bubble") }
                            NavigationLink { LazyView(AttachmentsView()) } label: { Label("Attachments", systemImage: "paperclip") }
                            NavigationLink { LazyView(ScheduledMailView()) } label: { Label("Scheduled to send", systemImage: "clock.arrow.circlepath") }
                            NavigationLink { LazyView(ReadStatusView()) } label: { Label("Read statuses (who opened)", systemImage: "envelope.open") }
                            NavigationLink { LazyView(DigestView()) } label: { Label("Newsletter digest", systemImage: "newspaper") }
                        }
                        Section("Life admin from your mail") {
                            NavigationLink { LazyView(SubscriptionsView()) } label: { Label("Bills & money", systemImage: "creditcard") }
                            NavigationLink { LazyView(DeliveriesView()) } label: { Label("Deliveries", systemImage: "shippingbox") }
                            NavigationLink { LazyView(TripsView()) } label: { Label("Trips", systemImage: "airplane") }
                        }
                        Menu("Set up", systemImage: "gearshape") {
                            NavigationLink { LazyView(VIPListView()) } label: { Label("VIPs", systemImage: "star") }
                            NavigationLink { LazyView(MailRulesView()) } label: { Label("Rules", systemImage: "line.3.horizontal.decrease") }
                            NavigationLink { LazyView(SnippetsView()) } label: { Label("Snippets", systemImage: "text.badge.plus") }
                            NavigationLink { LazyView(SwipeSettingsView()) } label: { Label("Swipe actions", systemImage: "hand.draw") }
                            NavigationLink { LazyView(WritingStyleView()) } label: { Label("My writing style", systemImage: "pencil.and.scribble") }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("More mail tools")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { compose = ComposeDraft(accountId: accountFilter) } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("New message")
                }
            }
            .sheet(item: $compose) { ComposeView(draft: $0) }
            .confirmationDialog(readAllTitle, isPresented: $confirmReadAll, titleVisibility: .visible) {
                Button("Mark All as Read") { markAllRead(visible) }
            }
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
            // Housekeeping waits until the tab has finished sliding in, and runs at most every few minutes,
            // so switching to Inbox never hitches while it scans thousands of emails.
            .task {
                // Once, after this update: open on All so nothing new is tucked away in another tab.
                if !allTabIntroduced { allTabIntroduced = true; tabRaw = InboxTab.all.rawValue }
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                if Date().timeIntervalSince(Self.lastHousekeeping) > 180 || unsubCandidates.isEmpty {
                    Self.lastHousekeeping = Date()
                    wakeSnoozed()
                    refreshUnsubscribe()
                }
            }
            .onChange(of: allEmails.count) {
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    refreshUnsubscribe()
                }
            }
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
                HorizonHeader(title: "Inbox", detail: inboxHorizonDetail, compact: true)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 4, trailing: 12))
                    .selectionDisabled()
                InboxTabBar(items: MailTabs.visibleItems, selected: $tabRaw, counts: tabBarCounts, hideCounts: calm)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .selectionDisabled()
                if heldCount > 0 && tab != .all {
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

            if !search.isEmpty && mailbox != .sent {
                Picker("Search in", selection: $searchThisMailbox) {
                    Text("All mailboxes").tag(false)
                    Text("This mailbox only").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .selectionDisabled()
            }

            if accounts.isEmpty && search.isEmpty {
                // No mail connected yet: "All clear" here read as if your mail had been checked.
                ContentUnavailableView {
                    Label("Connect your email", systemImage: "envelope.badge")
                } description: {
                    Text("Add Gmail, Outlook, iCloud or any IMAP account to see your mail here.")
                } actions: {
                    Button("Add a mail account") { AppRouter.shared.showSettings = true }.buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            } else if visible.isEmpty && pinned.isEmpty && !loadingSent && serverResults.isEmpty {
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
                        NavigationLink { LazyView(EmailDetailView(email: e)) } label: { EmailRow(email: e) }
                    }
                } header: { if !serverResults.isEmpty { Text("All mail") } }
            }
        }
        .listStyle(.plain)
        .premiumBackground(DS.Palette.meeting)
        .environment(\.accountTags, accountTags)
        .modifier(MailLayoutReader())
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
        case .all:
            // Above the waterline: new mail from real people, every account, newest first. Below: everything else, quieter.
            let items = collapse(visible)
            let since = Date().addingTimeInterval(-72 * 3600)
            let fresh = items.filter { !$0.isRead && $0.receivedAt > since && (AutoDrafts.isRealPerson($0) || scoreMap[$0.from.lowercased()]?.isVIP == true) }
            let freshIds = Set(fresh.map(\.id))
            let newOther = items.filter { !$0.isRead && !freshIds.contains($0.id) && $0.receivedAt > since }
            Section {
                if fresh.isEmpty {
                    Label("Nobody's waiting on you. Calm waters.", systemImage: "sailboat").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                ForEach(fresh) { e in row(e) }
            } header: {
                HStack {
                    Label("Needs you · \(fresh.count)", systemImage: "person.wave.2.fill").foregroundStyle(DS.Palette.accent)
                    Spacer()
                    if !(fresh + newOther).isEmpty { Button("Mark all read") { markAllRead(fresh + newOther) }.font(DS.Font.caption).buttonStyle(.borderless) }
                }
                .textCase(nil)
            }
            Section { Waterline(label: "Below the waterline · updates, newsletters, everything else") }
                .listRowBackground(Color.clear)
            let rest = items.filter { !freshIds.contains($0.id) }
            ForEach(["Today", "Yesterday", "This week", "Older"], id: \.self) { name in
                let group = rest.filter { InboxBrain.section(for: $0.receivedAt) == name }
                if !group.isEmpty {
                    Section(name) { ForEach(group) { e in row(e).opacity(e.isRead ? 0.72 : 0.9) } }
                }
            }
        case .priority:
            let items = collapse(visible)
            otherTabsCard
            let fresh = justArrived
            if !fresh.isEmpty {
                Section {
                    ForEach(fresh) { e in row(e) }
                } header: {
                    Label("Just arrived in Updates", systemImage: "sparkle").textCase(nil)
                }
            }
            ForEach(["Today", "Yesterday", "This week", "Older"], id: \.self) { name in
                let group = items.filter { InboxBrain.section(for: $0.receivedAt) == name }
                if !group.isEmpty {
                    Section(name) { ForEach(group) { e in row(e) } }
                }
            }
        case .updates, .newsletters, .promos:
            if tab == .promos {
                HStack {
                    Label("Sales, offers and cold pitches. Keel never drafts replies to these.", systemImage: "tag").foregroundStyle(DS.Palette.inkSoft)
                    Spacer()
                    Button { archiveRead(in: visible) } label: { Label("Clear read", systemImage: "archivebox") }
                }
                .font(DS.Font.caption).buttonStyle(.borderless)
                .selectionDisabled()
                if !unsubCandidates.isEmpty {
                    // The weekly report: senders you never open, with how often they write.
                    NavigationLink { LazyView(UnsubscribeReviewView(candidates: unsubCandidates, provider: provider(for:)).onDisappear { refreshUnsubscribe() }) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "chart.bar.doc.horizontal").font(.title3).foregroundStyle(DS.Palette.warmth)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Unsubscribe report").font(DS.Font.headline)
                                Text("\(unsubCandidates.count) sender\(unsubCandidates.count == 1 ? "" : "s") you almost never open · \(unsubCandidates.reduce(0) { $0 + $1.count }) emails in 60 days")
                                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                            }
                        }
                    }
                    .selectionDisabled()
                }
            }
            if tab == .newsletters {
                HStack {
                    NavigationLink { LazyView(DigestView()) } label: { Label("Read as a digest", systemImage: "newspaper") }
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
                    NavigationLink { LazyView(SenderBundleView(bundle: b)) } label: { SenderBundleRow(bundle: b) }
                        .swipeActions(edge: .trailing) {
                            Button { b.emails.forEach(archive) } label: { Label("Archive all", systemImage: "archivebox") }.tint(DS.Palette.calm)
                        }
                }
            }
        case .quick:
            if !visible.isEmpty {
                NavigationLink { LazyView(QuickRepliesView()) } label: {
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

    /// Unread mail from the last 12 hours that was sorted into Updates, so nothing new slips by unseen.
    private var justArrived: [EmailMessage] {
        let scores = scoreMap
        let since = Date().addingTimeInterval(-12 * 3600)
        return Array(collapse(mailboxEmails.filter {
            !$0.isRead && !$0.isPinned && $0.receivedAt > since
                && InboxBrain.tab($0, score: scores[$0.from.lowercased()]) == .updates
                && !InboxBrain.isHeld($0, score: scores[$0.from.lowercased()])
        }).prefix(5))
    }

    /// At the top of Priority: what's waiting in the other tabs, without letting it crowd your people.
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
        case "star": Button { star(e) } label: { Label(e.isStarred ? "Unflag" : "Flag", systemImage: e.isStarred ? "flag.slash" : "flag") }.tint(.orange)
        case "read": Button { toggleRead(e) } label: { Label(e.isRead ? "Unread" : "Read", systemImage: e.isRead ? "envelope.badge" : "envelope.open") }.tint(.blue)
        case "pin": Button { e.isPinned.toggle(); Haptics.tap() } label: { Label(e.isPinned ? "Unpin" : "Pin", systemImage: "pin") }.tint(.orange)
        default: EmptyView()
        }
    }

    @ViewBuilder
    private func row(_ e: EmailMessage) -> some View {
        let count = threaded && mailbox != .sent ? threadCount(e) : 1
        NavigationLink {
            LazyView(count > 1 ? AnyView(ThreadView(messages: conversation(e))) : AnyView(EmailDetailView(email: e)))
        } label: { EmailRow(email: e, count: count, unreadInThread: count > 1 && conversation(e).contains { !$0.isRead }, score: scoreMap[e.from.lowercased()]) }
            .swipeActions(edge: .trailing) {
                ForEach(MailSwipe.actions(trailingRaw).filter { mailbox != .sent || $0 == "task" }, id: \.self) { swipeButton($0, e) }
            }
            .swipeActions(edge: .leading) {
                ForEach(MailSwipe.actions(leadingRaw).filter { mailbox != .sent || $0 == "task" }, id: \.self) { swipeButton($0, e) }
            }
            .contextMenu {
                if multiWindow {
                    Button("Open in New Window", systemImage: "macwindow.badge.plus") { openWindow(id: "mail", value: e.id) }
                    Divider()
                }
                Button("Reply", systemImage: "arrowshape.turn.up.left") { compose = .reply(to: e, all: false, accounts: accounts) }
                Button("Reply All", systemImage: "arrowshape.turn.up.left.2") { compose = .reply(to: e, all: true, accounts: accounts) }
                Button("Forward", systemImage: "arrowshape.turn.up.right") { compose = .forward(e) }
                Divider()
                Button(e.isRead ? "Mark Unread" : "Mark Read", systemImage: e.isRead ? "envelope.badge" : "envelope.open") { toggleRead(e) }
                Button(e.isStarred ? "Unflag" : "Flag", systemImage: e.isStarred ? "flag.slash" : "flag") { star(e) }
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
        let fresh = UnsubscribeSuggestions.candidates(allEmails)
        UnsubscribeSuggestions.scheduleWeeklyReport(count: fresh.count)
        guard fresh.map(\.id) != unsubCandidates.map(\.id) else { return }      // unchanged: no redraw
        withAnimation(DS.spring) { unsubCandidates = fresh }
    }

    private func provider(for e: EmailMessage) -> MailProvider? {
        accounts.first { $0.id == e.accountId }.map(MailProviderFactory.make)
    }

    /// Get me to zero: archive older inbox mail in one go (flagged, pinned and VIP mail stay), with undo.
    private func getToZero(days: Int) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let scores = scoreMap
        let old = mailboxEmails.filter { !$0.isArchived && $0.receivedAt < cutoff && !$0.isStarred && !$0.isPinned && scores[$0.from.lowercased()]?.isVIP != true }
        guard !old.isEmpty else { UndoCenter.shared.notify("Nothing older to clear"); return }
        withAnimation(DS.spring) { for m in old { m.isArchived = true; m.snoozedUntil = nil } }
        Haptics.success()
        let jobs = old.compactMap { m in provider(for: m).map { ($0, m.providerMessageId) } }
        UndoCenter.shared.offer("Archived \(old.count) older email\(old.count == 1 ? "" : "s")",
                                undo: { withAnimation { for m in old { m.isArchived = false } } },
                                commit: { Task { for (p, id) in jobs { try? await p.archive(id) } } })
        checkInboxZero()
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
            Button { bulk { m, p in m.isRead = false; try? await p?.markRead(m.providerMessageId, read: false) } } label: { Label("Unread", systemImage: "envelope.badge") }
            Button { bulk { m, p in m.isStarred = true; try? await p?.setStarred(m.providerMessageId, starred: true) } } label: { Label("Flag", systemImage: "flag") }
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
        let wasArchived = e.isArchived
        // Hidden at once; deleted (here and on the server) only once the Undo window closes, like Archive.
        withAnimation(DS.spring) { e.isArchived = true }
        Haptics.tap()
        UndoCenter.shared.offer("Deleted",
                                undo: { withAnimation(DS.spring) { e.isArchived = wasArchived } },
                                commit: {
                                    ctx.delete(e)
                                    try? ctx.save()
                                    Task { try? await p?.trash(id) }
                                })
    }

    private func star(_ e: EmailMessage) {
        e.isStarred.toggle()
        Haptics.tap()
        let starred = e.isStarred
        Task { try? await provider(for: e)?.setStarred(e.providerMessageId, starred: starred) }
    }

    private var readAllTitle: String {
        let n = visible.filter { !$0.isRead }.count
        let place = mailbox == .inbox && search.isEmpty ? (customTab?.name ?? (tab == .all ? "your inbox" : tab.title)) : (search.isEmpty ? mailbox.rawValue : "these results")
        return "Mark \(n) unread email\(n == 1 ? "" : "s") in \(place) as read?"
    }

    /// Marks everything in this list read, here at once and on the mail servers in the background (a few at a time).
    private func markAllRead(_ list: [EmailMessage]) {
        let unread = list.flatMap { threaded ? conversation($0) : [$0] }.filter { !$0.isRead }
        guard !unread.isEmpty else { return }
        let jobs = unread.map { ($0.providerMessageId, provider(for: $0)) }
        withAnimation(DS.spring) { for m in unread { m.isRead = true } }
        try? ctx.save()
        Haptics.success()
        UndoCenter.shared.notify("Marked \(unread.count) as read")
        Task {
            for chunk in stride(from: 0, to: jobs.count, by: 6).map({ Array(jobs[$0..<min($0 + 6, jobs.count)]) }) {
                await withTaskGroup(of: Void.self) { g in
                    for (id, p) in chunk { g.addTask { try? await p?.markRead(id, read: true) } }
                }
            }
        }
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

    @MainActor private static var lastHousekeeping = Date.distantPast

    private func wakeSnoozed() {
        let now = Date()
        for e in allEmails where (e.snoozedUntil ?? .distantFuture) <= now {
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

/// With more than one account, each row carries a small tag saying which inbox it came to (like Spark).
struct AccountTag: Equatable { let label: String; let color: Color }
private struct AccountTagsKey: EnvironmentKey { static let defaultValue: [String: AccountTag] = [:] }
extension EnvironmentValues {
    var accountTags: [String: AccountTag] {
        get { self[AccountTagsKey.self] }
        set { self[AccountTagsKey.self] = newValue }
    }
}

struct EmailRow: View {
    @Environment(\.mailSearchTerms) private var searchTerms
    @Environment(\.accountTags) private var accountTags
    @Environment(\.mailLayout) private var layout
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
        if AutoDrafts.has(email.id) && !email.isRead { out.insert(("Draft ready", "pencil.line", DS.Palette.accent), at: 0) }
        // New and not for you personally: suggest where it belongs instead of filing it before you've seen it.
        if !email.isRead && age < 3 * 3600 {
            let t = InboxBrain.tab(email, score: score)
            if t != .priority && t != .all { out.insert(("Sort to \(t.title)", "arrow.turn.down.right", DS.Palette.inkSoft), at: 0) }
        }
        if let task = email.extractedTaskTitle, out.count < 3 { out.append((task, "checklist", DS.Palette.accent)) }
        return Array(out.prefix(3))
    }

    var body: some View {
        let chips = self.chips          // worked out once per row, not twice
        HStack(alignment: .top, spacing: DS.Space.m) {
            if layout.avatars {
                SenderAvatar(name: email.fromName, email: email.from, size: layout.avatarSize)
                    .overlay(alignment: .topLeading) {
                        if unread { Circle().fill(DS.Palette.accent).frame(width: 10, height: 10).overlay(Circle().stroke(DS.Palette.canvas, lineWidth: 2)).offset(x: -3, y: -3) }
                    }
            } else {
                Circle().fill(unread ? DS.Palette.accent : .clear).frame(width: 8, height: 8).padding(.top, 6)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(email.fromName.isEmpty ? email.from : email.fromName)
                        .font(unread ? DS.Font.headline : DS.Font.body).lineLimit(1)
                    if score?.isVIP == true { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                    if count > 1 { Text("\(count)").font(.caption2.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft) }
                    if email.isStarred { Image(systemName: "flag.fill").font(.caption2).foregroundStyle(.orange) }
                    Spacer()
                    if let tag = accountTags[email.accountId] {
                        Text(tag.label).font(.caption2.weight(.semibold)).lineLimit(1)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .foregroundStyle(tag.color).background(tag.color.opacity(0.14), in: Capsule())
                            .accessibilityLabel("To \(tag.label)")
                    }
                    Text(Self.time(email.receivedAt)).font(DS.Font.caption).foregroundStyle(unread ? DS.Palette.accent : DS.Palette.inkSoft)
                }
                if searchTerms.isEmpty {
                    Text(email.subject).font(DS.Font.body).foregroundStyle(unread ? DS.Palette.ink : DS.Palette.inkSoft).lineLimit(1)
                } else {
                    Text(Self.lit(email.subject, searchTerms, trim: false)).font(DS.Font.body).lineLimit(1)
                }
                if !searchTerms.isEmpty {
                    // While searching: the part of the email that matched, with the words highlighted.
                    Text(Self.lit(Self.matchSource(email, searchTerms), searchTerms, trim: true))
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                } else if layout.previewLines > 0 {
                    Text((count > 1 ? "Thread · " : "") + ((layout.aiSummary ? email.aiSummary : nil) ?? email.snippet))
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(count > 1 ? min(1, layout.previewLines) : layout.previewLines)
                }
                if !chips.isEmpty && layout.density != .compact {
                    HStack(spacing: 4) { ForEach(chips, id: \.0) { MailChip(text: $0.0, icon: $0.1, color: $0.2) } }
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, layout.rowPadding)
    }

    /// The text to preview while searching: the preview line if it has a match, otherwise the body.
    static func matchSource(_ e: EmailMessage, _ terms: [String]) -> String {
        let has = { (s: String) in terms.contains { s.range(of: $0, options: NoteText.compare) != nil } }
        if has(e.snippet) { return e.snippet }
        let body = e.bodyPlain.count > 20_000 ? String(e.bodyPlain.prefix(20_000)) : e.bodyPlain
        return has(body) ? body : e.snippet
    }

    @MainActor static func lit(_ text: String, _ terms: [String], trim: Bool) -> AttributedString {
        let display = NoteText.straighten(text)
        if !trim {
            var a = AttributedString(display)
            for t in terms {
                var from = display.startIndex
                while let r = display.range(of: t, options: NoteText.compare, range: from..<display.endIndex) {
                    if let ar = Range<AttributedString.Index>(r, in: a) {
                        a[ar].backgroundColor = DS.Palette.accent.opacity(0.22)
                        a[ar].inlinePresentationIntent = .stronglyEmphasized
                    }
                    from = r.upperBound
                }
            }
            return a
        }
        return NoteSearchIndex.preview(NotePart(kind: .text, blockId: nil, display: display, folded: ""), highlights: terms, tint: DS.Palette.accent)
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
    @State private var showSender = false
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [MailAccount]
    @State private var intent = ""
    @State private var draft = ""
    @State private var autoDrafted = false
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
    @State private var quickSendError: String?
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

    /// The whole conversation this email belongs to (for sharing it).
    private var threadEmails: [EmailMessage] {
        let tid = email.threadId
        guard !tid.isEmpty else { return [email] }
        let found = (try? ctx.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { $0.threadId == tid }))) ?? []
        return found.isEmpty ? [email] : found
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
                ConversationMemoryCard(email: email.from, name: email.fromName)
                quickReply
                ConnectedStrip(key: "mail:" + email.id)
            }
            .padding()
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { toggleStar() } label: { Image(systemName: email.isStarred ? "flag.fill" : "flag") }
                    .tint(email.isStarred ? .orange : nil).accessibilityLabel(email.isStarred ? "Unflag" : "Flag")
                Button { archive() } label: { Image(systemName: "archivebox") }.accessibilityLabel("Archive")
                Menu {
                    Button("Mark unread", systemImage: "envelope.badge") { email.isRead = false; Task { try? await provider?.markRead(email.providerMessageId, read: false) } }
                    Button("Make it a task", systemImage: "checklist") { makeTask() }
                    Button("Text \(email.fromName.isEmpty ? "the sender" : email.fromName)", systemImage: "message") {
                        AppleMessages.compose(email: email.from, name: email.fromName.isEmpty ? nil : email.fromName, context: "about their email: \(email.subject)")
                    }
                    Button("Open draft in Apple Mail", systemImage: "envelope.arrow.triangle.branch") {
                        AppRouter.shared.mailHandoff = MailHandoffDraft(to: [email.from], subject: "Re: \(email.subject)", body: "")
                    }
                    Button("About the sender", systemImage: "person.text.rectangle") { showSender = true }
                    Button(MutedThreads.isMuted(email.threadId) ? "Unmute conversation" : "Mute conversation", systemImage: MutedThreads.isMuted(email.threadId) ? "bell" : "bell.slash") {
                        let mute = !MutedThreads.isMuted(email.threadId)
                        MutedThreads.set(email.threadId, muted: mute)
                        UndoCenter.shared.notify(mute ? "Muted. New replies skip your inbox." : "Unmuted")
                        if mute { archive() }
                    }
                    ShareLink(item: ConversationText.text(threadEmails)) { Label("Share conversation", systemImage: "square.and.arrow.up") }
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
                    #if !targetEnvironment(macCatalyst)
                    Button("Translate", systemImage: "translate") { showTranslate = true }
                    #endif
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
        .sheet(isPresented: $showSender) { NavigationStack { SenderProfileView(address: email.from, name: email.fromName) }.presentationDetents([.medium, .large]) }
        // Keyboard (iPad and Mac), the same keys as Apple Mail.
        .background {
            Group {
                Button("Reply") { compose = .reply(to: email, all: false, accounts: accounts) }.keyboardShortcut("r")
                Button("Reply All") { compose = .reply(to: email, all: true, accounts: accounts) }.keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Forward") { compose = .forward(email) }.keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Archive") { archive() }.keyboardShortcut("a", modifiers: [.command, .control])
                Button("Flag") { toggleStar() }.keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Mark Unread") { email.isRead = false; Task { try? await provider?.markRead(email.providerMessageId, read: false) } }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                Button("Delete") { trash() }.keyboardShortcut(.delete, modifiers: .command)
            }
            .hidden()
        }
        .quickLookPreview($previewURL)
        .sheet(item: $eventDraft) { d in EventEditor(event: d.event, start: d.start) { eventDraft = nil }.ignoresSafeArea() }
        #if !targetEnvironment(macCatalyst)
        .translationPresentation(isPresented: $showTranslate, text: email.subject + "\n\n" + email.bodyPlain)
        #endif
        .task {
            // A reply Keel wrote while syncing is ready to edit or send.
            if draft.isEmpty, let pre = AutoDrafts.draft(for: email.id) { draft = pre; autoDrafted = true }
            Dread.recordOpen(email.id)          // Dread Radar notices emails opened again and again
            if !email.isRead {
                InboxBrain.record(.open, sender: email.from, name: email.fromName, ctx: ctx)
                switch MailAccountPrefs.markReadMode {             // Settings → Mail → Mark as read
                case "manual": break
                case "delay":
                    try? await Task.sleep(for: .seconds(3))
                    if !Task.isCancelled { email.isRead = true; try? await provider?.markRead(email.providerMessageId, read: true) }
                default:
                    email.isRead = true
                    try? await provider?.markRead(email.providerMessageId, read: true)
                }
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
            Button { showSender = true } label: {
                HStack(spacing: 4) {
                    Text("\(email.fromName.isEmpty ? email.from : email.fromName) · \(email.from)")
                    Image(systemName: "info.circle")
                }
                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            .buttonStyle(.plain)
            .accessibilityHint("About the sender")
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
                if autoDrafted {
                    Label("Keel drafted this reply in your voice. Check it, then send.", systemImage: "sparkles")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.accent)
                }
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
            if let quickSendError { Label(quickSendError, systemImage: "exclamationmark.triangle.fill").font(DS.Font.caption).foregroundStyle(DS.Palette.warmth) }
        }
    }

    private func makeDraft() async {
        drafting = true; defer { drafting = false }
        draft = await AIRouter.shared.draftReply(to: email, intent: intent) ?? ""
    }

    private func quickSend() {
        AutoDrafts.clear(email.id)
        let body = draft
        InboxBrain.record(.reply, sender: email.from, name: email.fromName, ctx: ctx)
        Task {
            // Only says Sent (and clears your reply) when the email really went; otherwise your words stay put.
            guard let provider else { quickSendError = "This account isn't connected right now."; return }
            do {
                try await provider.send(to: email.from, subject: ComposeDraft.prefixed("Re:", email.subject),
                                        body: body, inReplyTo: email.replyContext)
                quickSendError = nil
                Haptics.success()
                draft = ""; intent = ""
                withAnimation { sentFlash = true }
            } catch {
                Haptics.tap()
                quickSendError = "Didn't send: \(error.localizedDescription). Your reply is still here; try again."
            }
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
