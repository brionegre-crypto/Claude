import SwiftUI
import SwiftData
import CoreSpotlight
import EventKit

/// Search everything: tasks, notes, email, calendar events, saved links, goals and people, in one place.
struct SearchView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var tasks: [TaskItem]
    @Query private var notes: [Note]
    /// The newest 5,000 emails, searched instantly on this device (older mail: Inbox search asks the server).
    @Query(SearchView.recentMail) private var mail: [EmailMessage]
    static var recentMail: FetchDescriptor<EmailMessage> {
        var d = FetchDescriptor<EmailMessage>(sortBy: [SortDescriptor(\.receivedAt, order: .reverse)])
        d.fetchLimit = 5_000
        return d
    }
    @Query private var links: [SavedLink]
    @Query private var goals: [Goal]
    @Query private var people: [Person]
    @State private var query = ""
    @State private var live = ""          // what's searched: follows typing a beat behind, so every keystroke stays instant
    @State private var events: [EKEvent] = []
    @State private var viewing: EventRef?
    @State private var refined: SmartQuery?

    /// Typed text parsed locally; Apple Intelligence's reading replaces it after you press Search.
    private var smart: SmartQuery { refined ?? SmartQueryParser.parse(live) }
    private func taskOK(_ t: TaskItem) -> Bool {
        let s = smart
        guard s.allows("task"), s.words.isEmpty || s.matches(folded: TaskSearch.text(t)) else { return false }
        if s.flags.contains("done") && !t.isDone { return false }
        if s.flags.contains("open") && t.isDone { return false }
        if s.flags.contains("overdue") && (t.isDone || (t.dueDate ?? .distantFuture) >= Calendar.current.startOfDay(for: Date())) { return false }
        if s.flags.contains("starred") || s.flags.contains("unread") || s.flags.contains("attachments") { return false }
        return s.inRange(s.flags.contains("done") ? t.completedAt : t.dueDate)
    }
    private func mailOK(_ e: EmailMessage) -> Bool {
        let s = smart
        guard s.allows("email"), s.matches(folded: MailSearchText.folded(e)) else { return false }
        if let f = s.from, !(e.fromName + " " + e.from).lowercased().contains(f) { return false }
        if s.flags.contains("unread") && e.isRead { return false }
        if s.flags.contains("starred") && !e.isStarred { return false }
        if s.flags.contains("attachments") && !e.hasAttachments { return false }
        if s.flags.contains("overdue") || s.flags.contains("done") { return false }
        return s.inRange(e.receivedAt)
    }
    /// Notes matching the words (every word somewhere on the page), best first, within any date range asked for.
    private var noteResults: [NoteSearchIndex.Hit] {
        var q = NoteQuery()
        q.terms = smart.words.map(NoteText.fold).filter { !$0.isEmpty }
        guard !q.terms.isEmpty else { return [] }
        let pool = notes.filter { !$0.isTemplate && smart.inRange($0.updatedAt) }
        return NoteSearchIndex.search(q, in: pool, scope: .everything, match: .all, wholeWords: false, sort: .best)
    }
    private var plainOnly: Bool { smart.kinds.isEmpty && smart.flags.isEmpty && smart.from == nil }

    var body: some View {
        List {
            if live.count >= 3 {
                Section {
                    NavigationLink { LazyView(AskEverythingView(initial: live)) } label: { Label("Ask Keel: “\(live)”", systemImage: "sparkle.magnifyingglass") }
                    ForEach(SearchActions.matching(live)) { a in
                        Button { a.run(live) } label: { Label(a.title(live), systemImage: a.icon) }
                    }
                } footer: { Text("Find anything, ask a question, or do something, all from here.") }
            }
            if live.count >= 3, !smart.isStructured {
                let meaning = BrainIndex.shared.search(live, kinds: ["note"], limit: 5)
                if !meaning.isEmpty {
                    Section("Related by meaning") {
                        ForEach(meaning) { h in
                            if let n = notes.first(where: { $0.id.uuidString == h.id }) {
                                NavigationLink { LazyView(NoteOrCanvas(note: n)) } label: { Label(n.title.isEmpty ? "Untitled" : n.title, systemImage: "sparkle.magnifyingglass") }
                            }
                        }
                    }
                }
            }
            if live.count < 2 || (!smart.isStructured && smart.words.isEmpty) {
                ContentUnavailableView("Search everything", systemImage: "magnifyingglass",
                                       description: Text("Tasks, notes, email, events, links, goals and people.\nTry “emails from sam last week”, “overdue tasks” or “notes about budget this month”."))
                    .listRowBackground(Color.clear)
            } else {
                if smart.isStructured {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            Image(systemName: refined == nil ? "text.magnifyingglass" : "sparkles").foregroundStyle(DS.Palette.accent)
                            ForEach(smart.chips, id: \.self) { Chip(text: $0, color: DS.Palette.accent) }
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                // Open tasks first, and tasks with the words in their title before ones with them in notes or steps.
                let t = tasks.filter(taskOK).sorted { a, b in
                    if a.isDone != b.isDone { return !a.isDone }
                    let ta = smart.matches(a.title), tb = smart.matches(b.title)
                    return ta != tb ? ta : a.updatedAt > b.updatedAt
                }.prefix(smart.isStructured ? 30 : 8)
                if !t.isEmpty {
                    Section("Tasks") { ForEach(Array(t)) { task in NavigationLink { LazyView(TaskDetailView(task: task)) } label: { TaskRow(task: task) } } }
                }
                // Notes use the same engine as Notes search: every line, table, database field and scanned image.
                let noteHits = smart.allows("note") && smart.flags.isEmpty && smart.from == nil ? noteResults : []
                let n = Array(noteHits.prefix(smart.isStructured ? 20 : 6))
                if !n.isEmpty {
                    Section {
                        ForEach(n) { hit in
                            NavigationLink { LazyView(NoteOrCanvas(note: hit.note, focusBlock: hit.jumpTo)) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.note.title.isEmpty ? "Untitled" : hit.note.title).font(DS.Font.headline)
                                    if let p = hit.preview {
                                        Text(NoteSearchIndex.preview(p, highlights: smart.words.map(NoteText.fold), tint: DS.Palette.accent))
                                            .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                                    } else {
                                        Text(NoteSnippet.text(hit.note)).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(noteHits.count > n.count ? "Notes · \(noteHits.count) pages" : "Notes")
                    }
                }
                let m = mail.filter(mailOK).prefix(smart.isStructured ? 30 : 8)
                if !m.isEmpty {
                    Section("Email") { ForEach(Array(m)) { e in NavigationLink { LazyView(EmailDetailView(email: e)) } label: { EmailRow(email: e) } } }
                }
                if !events.isEmpty {
                    Section("Calendar") {
                        ForEach(events, id: \.stableId) { e in
                            Button { viewing = EventRef(event: e) } label: {
                                HStack {
                                    RoundedRectangle(cornerRadius: 2).fill(e.color).frame(width: 4, height: 30)
                                    VStack(alignment: .leading) {
                                        Text(e.title ?? "Event").font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                                        Text(e.startDate.formatted(date: .abbreviated, time: .shortened)).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                                    }
                                }
                            }
                        }
                    }
                }
                let l = plainOnly && smart.range == nil ? Array(links.filter { smart.matches($0.title, $0.summary ?? "", $0.url) }.prefix(5)) : []
                if !l.isEmpty {
                    Section("Read later") { ForEach(l) { LinkRow(link: $0) } }
                }
                let g = plainOnly && smart.range == nil ? goals.filter { smart.matches($0.title, $0.why) } : []
                if !g.isEmpty {
                    Section("Goals") { ForEach(g) { goal in NavigationLink { LazyView(GoalDetailView(goal: goal)) } label: { Text("\(goal.emoji) \(goal.title)") } } }
                }
                let p = plainOnly && smart.range == nil ? people.filter { smart.matches($0.name, $0.email, $0.notes) } : []
                if !p.isEmpty {
                    Section("People") { ForEach(p) { person in Text(person.name) } }
                }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Keel")
        .onChange(of: query) { refined = nil }
        .onAppear { NoteSearchIndex.refreshScans(ctx) }      // text in scanned images is searchable too
        .task(id: query) {
            // Short pause while you're still typing; clearing is immediate.
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(120)) }
            guard !Task.isCancelled else { return }
            live = query
            loadEvents()
        }
        .onSubmit(of: .search) {
            let q = query
            Task {
                if let r = await SmartQueryParser.refine(q), q == query { refined = r; loadEvents() }
            }
        }
        .sheet(item: $viewing) { ref in EventDetail(event: ref.event) { viewing = nil }.ignoresSafeArea() }
    }

    private func loadEvents() {
        let s = smart
        guard live.count >= 2, s.allows("event"), s.flags.isEmpty, s.from == nil else { events = []; return }
        let now = Date()
        let r = s.range ?? DateInterval(start: now.addingTimeInterval(-90 * 86_400), end: now.addingTimeInterval(180 * 86_400))
        events = CalendarService.shared.events(from: r.start, to: r.end)
            .filter { s.matches($0.title ?? "", $0.location ?? "") }
            .prefix(s.isStructured ? 20 : 8).map { $0 }
    }
}

/// Puts Keel tasks and notes into iPhone search (swipe down on the Home Screen).
@MainActor
enum SpotlightIndex {
    /// Keeps iPhone search (swipe down on the Home Screen) up to date with every open task and every unlocked
    /// page, full text included. Only what changed since last time is sent to the index, so it stays light.
    static func refresh(_ ctx: ModelContext) {
        let tasks = ((try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? [])
        let notes = ((try? ctx.fetch(FetchDescriptor<Note>())) ?? []).filter { !$0.isLocked && !$0.isTemplate }
        let before = loadStamps()
        var now: [String: Double] = [:]
        var items: [CSSearchableItem] = []
        for t in tasks {
            let key = "task:\(t.id.uuidString)"
            let stamp = t.updatedAt.timeIntervalSince1970 + Double(t.microSteps.count)
            now[key] = stamp
            guard before[key] != stamp else { continue }
            let a = CSSearchableItemAttributeSet(contentType: .content)
            a.title = t.title
            a.contentDescription = [t.dueDate.map { "Due \($0.formatted(date: .abbreviated, time: t.hasDueTime ? .shortened : .omitted))" }, t.notes.isEmpty ? nil : t.notes]
                .compactMap { $0 }.joined(separator: " · ")
            a.textContent = ([t.notes] + t.microSteps.map(\.text)).joined(separator: "\n")
            a.keywords = t.tags + ["task", "keel", t.listName]
            items.append(CSSearchableItem(uniqueIdentifier: key, domainIdentifier: "tasks", attributeSet: a))
        }
        for n in notes {
            let key = "note:\(n.id.uuidString)"
            let stamp = n.updatedAt.timeIntervalSince1970
            now[key] = stamp
            guard before[key] != stamp else { continue }
            let text = n.plainText
            let a = CSSearchableItemAttributeSet(contentType: .text)
            a.title = n.title.isEmpty ? "Untitled" : n.title
            a.contentDescription = String(text.prefix(300))
            a.textContent = String(text.prefix(60_000))          // the whole page, so any word in it finds it
            a.keywords = ["note", "keel"] + (n.folder.map { [$0] } ?? [])
            items.append(CSSearchableItem(uniqueIdentifier: key, domainIdentifier: "notes", attributeSet: a))
        }
        let removed = before.keys.filter { now[$0] == nil }        // deleted, locked, finished or turned into templates
        guard !items.isEmpty || !removed.isEmpty else { return }
        push(items, removed: Array(removed), save: now)
    }

    nonisolated private static func push(_ items: [CSSearchableItem], removed: [String], save: [String: Double]) {
        let index = CSSearchableIndex.default()
        func send() {
            if items.isEmpty { saveStamps(save); return }
            index.indexSearchableItems(items) { error in if error == nil { saveStamps(save) } }
        }
        if removed.isEmpty { send() } else { index.deleteSearchableItems(withIdentifiers: removed) { _ in send() } }
    }

    // What was last sent to the index (item → last change), kept in a small file.
    nonisolated private static var stampsURL: URL {
        URL.applicationSupportDirectory.appending(path: "spotlight-index-v2.json")
    }
    private static func loadStamps() -> [String: Double] {
        guard let d = try? Data(contentsOf: stampsURL) else {
            // First run with full-text indexing: clear the old, partial index so nothing stale lingers.
            CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: ["tasks", "notes"], completionHandler: nil)
            return [:]
        }
        return (try? JSONDecoder().decode([String: Double].self, from: d)) ?? [:]
    }
    nonisolated private static func saveStamps(_ s: [String: Double]) {
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(s).write(to: stampsURL, options: .atomic)
    }
}
