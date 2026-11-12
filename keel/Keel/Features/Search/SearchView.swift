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

    private func hit(_ fields: String...) -> Bool {
        let q = query.lowercased()
        return fields.contains { $0.lowercased().contains(q) }
    }

    var body: some View {
        List {
            if query.count < 2 {
                ContentUnavailableView("Search everything", systemImage: "magnifyingglass",
                                       description: Text("Tasks, notes, email, events, saved links, goals and people."))
                    .listRowBackground(Color.clear)
            } else {
                let t = tasks.filter { hit($0.title, $0.notes, $0.tags.joined(separator: " ")) }.prefix(8)
                if !t.isEmpty {
                    Section("Tasks") { ForEach(Array(t)) { task in NavigationLink { TaskDetailView(task: task) } label: { TaskRow(task: task) } } }
                }
                let n = notes.filter { hit($0.title, $0.plainText) }.prefix(6)
                if !n.isEmpty {
                    Section("Notes") {
                        ForEach(Array(n)) { note in
                            NavigationLink { NoteEditor(note: note) } label: {
                                VStack(alignment: .leading) {
                                    Text(note.title).font(DS.Font.headline)
                                    Text(note.plainText).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                                }
                            }
                        }
                    }
                }
                let m = mail.filter { hit($0.subject, $0.fromName, $0.from, $0.bodyPlain) }.prefix(8)
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
                let l = links.filter { hit($0.title, $0.summary ?? "", $0.url) }.prefix(5)
                if !l.isEmpty {
                    Section("Read later") { ForEach(Array(l)) { LinkRow(link: $0) } }
                }
                let g = goals.filter { hit($0.title, $0.why) }
                if !g.isEmpty {
                    Section("Goals") { ForEach(g) { goal in NavigationLink { GoalDetailView(goal: goal) } label: { Text("\(goal.emoji) \(goal.title)") } } }
                }
                let p = people.filter { hit($0.name, $0.email, $0.notes) }
                if !p.isEmpty {
                    Section("People") { ForEach(p) { person in Text(person.name) } }
                }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Keel")
        .onChange(of: query) { loadEvents() }
        .sheet(item: $viewing) { ref in EventDetail(event: ref.event) { viewing = nil }.ignoresSafeArea() }
    }

    private func loadEvents() {
        guard query.count >= 2 else { events = []; return }
        let q = query.lowercased()
        let now = Date()
        events = CalendarService.shared.events(from: now.addingTimeInterval(-90 * 86_400), to: now.addingTimeInterval(180 * 86_400))
            .filter { ($0.title ?? "").lowercased().contains(q) || ($0.location ?? "").lowercased().contains(q) }
            .prefix(8).map { $0 }
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
