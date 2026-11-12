import SwiftUI
import SwiftData
import CoreSpotlight
import EventKit

/// Search everything: tasks, notes, email, calendar events, saved links, goals and people, in one place.
struct SearchView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var tasks: [TaskItem]
    @Query private var notes: [Note]
    @Query(sort: \EmailMessage.receivedAt, order: .reverse) private var mail: [EmailMessage]
    @Query private var links: [SavedLink]
    @Query private var goals: [Goal]
    @Query private var people: [Person]
    @State private var query = ""
    @State private var events: [EKEvent] = []
    @State private var viewing: EventRef?
    @State private var refined: SmartQuery?

    /// Typed text parsed locally; Apple Intelligence's reading replaces it after you press Search.
    private var smart: SmartQuery { refined ?? SmartQueryParser.parse(query) }
    private func taskOK(_ t: TaskItem) -> Bool {
        let s = smart
        guard s.allows("task"), s.matches(t.title, t.notes, t.tags.joined(separator: " ")) else { return false }
        if s.flags.contains("done") && !t.isDone { return false }
        if s.flags.contains("open") && t.isDone { return false }
        if s.flags.contains("overdue") && (t.isDone || (t.dueDate ?? .distantFuture) >= Calendar.current.startOfDay(for: Date())) { return false }
        if s.flags.contains("starred") || s.flags.contains("unread") || s.flags.contains("attachments") { return false }
        return s.inRange(s.flags.contains("done") ? t.completedAt : t.dueDate)
    }
    private func mailOK(_ e: EmailMessage) -> Bool {
        let s = smart
        guard s.allows("email"), s.matches(e.subject, e.fromName, e.from, e.bodyPlain) else { return false }
        if let f = s.from, !(e.fromName + " " + e.from).lowercased().contains(f) { return false }
        if s.flags.contains("unread") && e.isRead { return false }
        if s.flags.contains("starred") && !e.isStarred { return false }
        if s.flags.contains("attachments") && !e.hasAttachments { return false }
        if s.flags.contains("overdue") || s.flags.contains("done") { return false }
        return s.inRange(e.receivedAt)
    }
    private var plainOnly: Bool { smart.kinds.isEmpty && smart.flags.isEmpty && smart.from == nil }

    var body: some View {
        List {
            if query.count < 2 || (!smart.isStructured && smart.words.isEmpty) {
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
                let t = tasks.filter(taskOK).prefix(smart.isStructured ? 30 : 8)
                if !t.isEmpty {
                    Section("Tasks") { ForEach(Array(t)) { task in NavigationLink { TaskDetailView(task: task) } label: { TaskRow(task: task) } } }
                }
                let n = smart.allows("note") && smart.flags.isEmpty && smart.from == nil
                    ? Array(notes.filter { smart.matches($0.title, $0.plainText) && smart.inRange($0.updatedAt) }.prefix(smart.isStructured ? 20 : 6)) : []
                if !n.isEmpty {
                    Section("Notes") {
                        ForEach(n) { note in
                            NavigationLink { NoteEditor(note: note) } label: {
                                VStack(alignment: .leading) {
                                    Text(note.title).font(DS.Font.headline)
                                    Text(note.plainText).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                                }
                            }
                        }
                    }
                }
                let m = mail.filter(mailOK).prefix(smart.isStructured ? 30 : 8)
                if !m.isEmpty {
                    Section("Email") { ForEach(Array(m)) { e in NavigationLink { EmailDetailView(email: e) } label: { EmailRow(email: e) } } }
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
                    Section("Goals") { ForEach(g) { goal in NavigationLink { GoalDetailView(goal: goal) } label: { Text("\(goal.emoji) \(goal.title)") } } }
                }
                let p = plainOnly && smart.range == nil ? people.filter { smart.matches($0.name, $0.email, $0.notes) } : []
                if !p.isEmpty {
                    Section("People") { ForEach(p) { person in Text(person.name) } }
                }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Keel")
        .onChange(of: query) { refined = nil; loadEvents() }
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
        guard query.count >= 2, s.allows("event"), s.flags.isEmpty, s.from == nil else { events = []; return }
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
    static func refresh(_ ctx: ModelContext) {
        let tasks = ((try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []).filter { !$0.isDone }.prefix(500)
        let notes = ((try? ctx.fetch(FetchDescriptor<Note>())) ?? []).prefix(500)
        var items: [CSSearchableItem] = []
        for t in tasks {
            let a = CSSearchableItemAttributeSet(contentType: .content)
            a.title = t.title
            a.contentDescription = [t.dueDate.map { "Due \($0.formatted(date: .abbreviated, time: t.hasDueTime ? .shortened : .omitted))" }, t.notes.isEmpty ? nil : t.notes]
                .compactMap { $0 }.joined(separator: " · ")
            a.keywords = t.tags + ["task", "keel", t.listName]
            items.append(CSSearchableItem(uniqueIdentifier: "task:\(t.id.uuidString)", domainIdentifier: "tasks", attributeSet: a))
        }
        for n in notes {
            let a = CSSearchableItemAttributeSet(contentType: .text)
            a.title = n.title
            a.contentDescription = String(n.plainText.prefix(300))
            a.keywords = ["note", "keel"]
            items.append(CSSearchableItem(uniqueIdentifier: "note:\(n.id.uuidString)", domainIdentifier: "notes", attributeSet: a))
        }
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: ["tasks", "notes"]) { _ in
            index.indexSearchableItems(items, completionHandler: nil)
        }
    }
}
