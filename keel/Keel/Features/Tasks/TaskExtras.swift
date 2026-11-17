import SwiftUI
import SwiftData

// MARK: - Recently deleted tasks (kept 30 days)

struct DeletedTask: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var notes: String
    var due: Date?
    var priority: TaskPriority
    var list: String
    var tags: [String]
    var steps: [MicroStep]
    var recurrence: Recurrence?
    var alert: Int?
    var goal: UUID?
    var deletedAt = Date()
}

@MainActor
enum TaskTrash {
    static let key = "tasks.trash"
    static var all: [DeletedTask] {
        let list: [DeletedTask] = LocalLog.load(key)
        return list.filter { Date().timeIntervalSince($0.deletedAt) < 30 * 86_400 }
    }
    static func keep(_ t: TaskItem) -> DeletedTask {
        let d = DeletedTask(title: t.title, notes: t.notes, due: t.dueDate, priority: t.priority, list: t.listName, tags: t.tags,
                            steps: t.microSteps, recurrence: t.recurrence, alert: t.alertOffsetMinutes, goal: t.goalId)
        var list = all
        list.append(d)
        LocalLog.save(Array(list.suffix(300)), key)
        return d
    }
    @discardableResult
    static func restore(_ d: DeletedTask, ctx: ModelContext) -> TaskItem {
        let r = TaskItem(title: d.title, dueDate: d.due, priority: d.priority)
        r.notes = d.notes; r.listName = d.list; r.tags = d.tags; r.microSteps = d.steps
        r.recurrence = d.recurrence; r.alertOffsetMinutes = d.alert; r.goalId = d.goal
        ctx.insert(r)
        try? ctx.save()
        try? CalendarService.shared.push(r)
        TaskAlerts.schedule(r)
        forget(d.id)
        return r
    }
    static func forget(_ id: UUID) { LocalLog.save(all.filter { $0.id != id }, key) }
    static func empty() { LocalLog.save([DeletedTask](), key) }
}

struct DeletedTasksView: View {
    @Environment(\.modelContext) private var ctx
    @State private var items: [DeletedTask] = TaskTrash.all.reversed()
    @State private var confirmEmpty = false

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView("Nothing deleted", systemImage: "trash", description: Text("Deleted tasks stay here for 30 days."))
            }
            ForEach(items) { d in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.title).lineLimit(2)
                        Text("Deleted \(d.deletedAt.formatted(.relative(presentation: .named)))\(d.list == "Inbox" ? "" : " · \(d.list)")")
                            .font(.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                    Spacer()
                    Button("Restore") {
                        TaskTrash.restore(d, ctx: ctx); Haptics.success()
                        withAnimation { items.removeAll { $0.id == d.id } }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                .swipeActions { Button("Delete now", role: .destructive) { TaskTrash.forget(d.id); items.removeAll { $0.id == d.id } } }
            }
        }
        .navigationTitle("Recently deleted")
        .toolbar {
            if !items.isEmpty {
                Button("Empty", role: .destructive) { confirmEmpty = true }
            }
        }
        .confirmationDialog("Delete these for good?", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("Delete \(items.count) for good", role: .destructive) { TaskTrash.empty(); items = [] }
        }
    }
}

// MARK: - Morning roll-over: yesterday's leftovers move to today

@MainActor
enum MorningRollover {
    static let onKey = "custom.tasks.rollover"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: onKey) }
    private static let dayKey = "tasks.rollover.day"

    /// Once a day (the first time Keel opens): overdue tasks move to today at the same time of day.
    /// Repeating tasks keep their own schedule. Undo puts every one back.
    static func runIfDue(ctx: ModelContext) {
        guard isOn else { return }
        let today = Calendar.current.startOfDay(for: Date())
        let stamp = today.formatted(.iso8601.year().month().day())
        guard UserDefaults.standard.string(forKey: dayKey) != stamp else { return }
        UserDefaults.standard.set(stamp, forKey: dayKey)
        let open = (try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? []
        let overdue = open.filter { ($0.dueDate ?? .distantFuture) < today && $0.recurrence == nil }
        guard !overdue.isEmpty else { return }
        let before = overdue.map { ($0, $0.dueDate) }
        let cal = Calendar.current
        for t in overdue {
            guard let due = t.dueDate else { continue }
            let c = cal.dateComponents([.hour, .minute], from: due)
            t.dueDate = t.hasDueTime ? cal.date(bySettingHour: c.hour ?? 9, minute: c.minute ?? 0, second: 0, of: today) : today
            t.timesRescheduled += 1
            t.updatedAt = Date()
            try? CalendarService.shared.push(t)
        }
        try? ctx.save()
        UndoCenter.shared.offer("Moved \(overdue.count) overdue task\(overdue.count == 1 ? "" : "s") to today", seconds: 8) {
            for (t, d) in before { t.dueDate = d; t.timesRescheduled = max(0, t.timesRescheduled - 1); t.updatedAt = Date() }
            try? ctx.save()
        }
    }
}

// MARK: - Favorite pages on Today

struct FavoritePagesCard: View {
    @Query(filter: #Predicate<Note> { $0.isPinned && !$0.isTemplate }, sort: \Note.updatedAt, order: .reverse) private var favorites: [Note]
    @AppStorage("custom.today.favoritePages") private var on = true

    var body: some View {
        if on && !favorites.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Favorite pages", systemImage: "star.fill").font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(favorites.prefix(10)) { n in
                            Button {
                                AppRouter.shared.openNoteId = n.id
                                AppRouter.shared.tab = .notes
                            } label: {
                                HStack(spacing: 6) {
                                    Text(n.icon ?? "📄")
                                    Text(n.title.isEmpty ? "Untitled" : n.title).lineLimit(1).foregroundStyle(DS.Palette.ink)
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background { PremiumSurface(radius: 14) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollClipDisabled()
            }
        }
    }
}
