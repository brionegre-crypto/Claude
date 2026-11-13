import SwiftUI
import SwiftData

/// TickTick-style tasks, synced two-way with Apple Reminders:
/// smart lists, your lists and #tags, an Eisenhower matrix, repeating tasks, alerts and subtasks.
enum TaskFilter: Hashable {
    case today, next7, inbox, all, matrix, completed, someday
    case list(String)
    case tag(String)
    case smart(UUID)

    var title: String {
        switch self {
        case .today: "Today"
        case .next7: "Next 7 Days"
        case .inbox: "Inbox"
        case .all: "All"
        case .matrix: "Matrix"
        case .completed: "Completed"
        case .someday: "Someday"
        case .list(let l): l
        case .tag(let t): "#\(t)"
        case .smart: "Smart list"
        }
    }

    var icon: String {
        switch self {
        case .today: "sun.max"
        case .next7: "calendar.day.timeline.right"
        case .inbox: "tray"
        case .all: "list.bullet"
        case .matrix: "square.grid.2x2"
        case .completed: "checkmark.circle"
        case .someday: "moon.zzz"
        case .list: "list.bullet.rectangle"
        case .tag: "number"
        case .smart: "line.3.horizontal.decrease.circle"
        }
    }
}

struct TasksView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @Query(sort: \SmartList.createdAt) private var smartLists: [SmartList]
    @State private var editingSmart: SmartList?
    @State private var selecting = false
    @State private var selectedTasks = Set<UUID>()
    @State private var newSmart = false
    @AppStorage("tasks.filter") private var filterKey = "today"
    @State private var newTitle = ""
    @State private var search = ""
    @State private var toast: String?
    @AppStorage("tasks.board") private var boardMode = false
    @State private var sharingList: String?
    @FocusState private var addFocused: Bool

    private let cal = Calendar.current

    private var filter: TaskFilter {
        switch filterKey {
        case "today": .today
        case "next7": .next7
        case "inbox": .inbox
        case "all": .all
        case "matrix": .matrix
        case "completed": .completed
        case "someday": .someday
        default:
            filterKey.hasPrefix("list:") ? .list(String(filterKey.dropFirst(5)))
                : filterKey.hasPrefix("tag:") ? .tag(String(filterKey.dropFirst(4)))
                : filterKey.hasPrefix("smart:") ? (UUID(uuidString: String(filterKey.dropFirst(6))).map { .smart($0) } ?? .today) : .today
        }
    }

    private func key(_ f: TaskFilter) -> String {
        switch f {
        case .today: "today"; case .next7: "next7"; case .inbox: "inbox"; case .all: "all"
        case .matrix: "matrix"; case .completed: "completed"; case .someday: "someday"
        case .list(let l): "list:\(l)"; case .tag(let t): "tag:\(t)"; case .smart(let id): "smart:\(id.uuidString)"
        }
    }

    private var lists: [String] {
        Array(Set(tasks.map(\.listName) + CalendarService.shared.reminderLists.map(\.title))).sorted()
    }
    private var tags: [String] { Array(Set(tasks.flatMap(\.tags))).sorted() }

    private var chosen: [TaskItem] { tasks.filter { selectedTasks.contains($0.id) } }

    private var taskBulkBar: some View {
        HStack(spacing: DS.Space.l) {
            Button { chosen.forEach { TaskActions.setDone($0, true) }; finishBulk("Completed") } label: { Label("Complete", systemImage: "checkmark.circle") }
            Button {
                let t = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
                chosen.forEach { TaskActions.reschedule($0, to: t) }; finishBulk("Moved to tomorrow")
            } label: { Label("Tomorrow", systemImage: "sunrise") }
            Menu {
                ForEach(TaskPriority.allCases.reversed(), id: \.self) { p in
                    Button(p.label) { chosen.forEach { $0.priority = p; $0.updatedAt = Date(); try? CalendarService.shared.push($0) }; finishBulk("Priority set") }
                }
            } label: { Label("Priority", systemImage: "flag") }
            Menu {
                ForEach(lists, id: \.self) { l in
                    Button(l) { chosen.forEach { $0.listName = l; $0.updatedAt = Date(); try? CalendarService.shared.push($0) }; finishBulk("Moved to \(l)") }
                }
            } label: { Label("Move", systemImage: "folder") }
            Button(role: .destructive) { chosen.forEach { TaskActions.delete($0, ctx: ctx) }; finishBulk("Deleted") } label: { Label("Delete", systemImage: "trash") }
        }
        .labelStyle(.iconOnly).font(.title3)
        .disabled(selectedTasks.isEmpty)
        .padding(.horizontal, DS.Space.l).padding(.vertical, DS.Space.m)
        .glassEffect(.regular, in: Capsule())
        .padding(.bottom, DS.Space.s)
    }

    private func finishBulk(_ what: String) {
        let n = selectedTasks.count
        Haptics.success()
        UndoCenter.shared.notify("\(what): \(n) task\(n == 1 ? "" : "s")")
        selectedTasks = []
        withAnimation { selecting = false }
    }

    private var screenTitle: String {
        if case .smart(let id) = filter { return smartLists.first { $0.id == id }?.name ?? "Smart list" }
        return filter.title
    }

    private var open: [TaskItem] { tasks.filter { !$0.isDone && !$0.isSomeday } }

    private var filtered: [TaskItem] {
        let endToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        let end7 = cal.date(byAdding: .day, value: 7, to: endToday)!
        var base: [TaskItem]
        switch filter {
        case .today: base = open.filter { ($0.dueDate ?? .distantFuture) < endToday }
        case .next7: base = open.filter { ($0.dueDate ?? .distantFuture) < end7 }
        case .inbox: base = open.filter { $0.dueDate == nil && $0.listName == "Inbox" }
        case .all, .matrix: base = open
        case .completed: base = tasks.filter(\.isDone).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        case .someday: base = tasks.filter { !$0.isDone && $0.isSomeday }
        case .list(let l): base = open.filter { $0.listName == l }
        case .tag(let t): base = open.filter { $0.tags.contains(t) }
        case .smart(let id): base = smartLists.first { $0.id == id }.map { s in tasks.filter { s.matches($0) } } ?? []
        }
        if !search.isEmpty {
            let q = search.lowercased()
            base = base.filter { $0.title.lowercased().contains(q) || $0.notes.lowercased().contains(q) || $0.tags.contains { $0.lowercased().contains(q) } }
        }
        return base
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                if filter == .matrix {
                    MatrixView(tasks: filtered.filter { !$0.isWaitingOn }, onRolled: showRolled)
                } else if boardMode && filter != .completed {
                    BoardView(tasks: boardTasks)
                } else {
                    list
                }
            }
            .navigationTitle(screenTitle)
            .keelSettingsButton()
            .searchable(text: $search, prompt: "Search tasks")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { PromisesView() } label: { Label("Promises", systemImage: "hand.raised.fingers.spread") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { ProjectsView() } label: { Label("Projects", systemImage: "folder") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { ProcessInboxView() } label: { Label("Sort", systemImage: "tray.and.arrow.down") }
                        .accessibilityLabel("Sort loose tasks")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(selecting ? "Done Selecting" : "Select Tasks", systemImage: "checkmark.circle") {
                            withAnimation { selecting.toggle(); selectedTasks = [] }
                        }
                        Button("Auto-schedule today", systemImage: "wand.and.stars") {
                            let r = AutoScheduler.scheduleToday(tasks: tasks)
                            withAnimation { toast = r.scheduled == 0 ? "Nothing fit today" : "Scheduled \(r.scheduled) on your calendar" }
                            Task { try? await Task.sleep(for: .seconds(2.5)); withAnimation { toast = nil } }
                        }
                        Button("Clear today's time blocks", systemImage: "calendar.badge.minus") { AutoScheduler.clearToday(tasks: tasks) }
                        Divider()
                        Button(boardMode ? "Show as list" : "Show as board", systemImage: boardMode ? "list.bullet" : "rectangle.split.3x1") {
                            withAnimation { boardMode.toggle() }
                        }
                        if case .list(let name) = filter {
                            Button("Share “\(name)”…", systemImage: "person.2") { sharingList = name }
                        }
                        NavigationLink { TemplatesView() } label: { Label("Templates", systemImage: "doc.on.doc") }
                        NavigationLink { WeekPlannerView() } label: { Label("Plan the week", systemImage: "calendar.day.timeline.left") }
                        NavigationLink { StatsView() } label: { Label("Statistics", systemImage: "chart.xyaxis.line") }
                        NavigationLink { TagsManagerView() } label: { Label("Manage tags", systemImage: "number") }
                        NavigationLink { ScreenshotTasksView() } label: { Label("From screenshots", systemImage: "camera.viewfinder") }
                        if case .list(let name) = filter {
                            Button("Save “\(name)” as a template", systemImage: "square.and.arrow.down") {
                                TemplateSaver.save(listName: name, tasks: tasks.filter { !$0.isDone }, ctx: ctx)
                                withAnimation { toast = "Saved as a template" }
                                Task { try? await Task.sleep(for: .seconds(2)); withAnimation { toast = nil } }
                            }
                        }
                    } label: { Image(systemName: "wand.and.stars") }
                    .accessibilityLabel("Schedule")
                }
            }
            .refreshable { await SyncEngine.shared.syncAll() }
            .sheet(item: Binding(get: { sharingList.map { ListName(name: $0) } }, set: { sharingList = $0?.name })) { ShareListSheet(listName: $0.name) }
            .sheet(isPresented: $newSmart) { SmartListEditor(list: nil, allLists: lists, allTags: tags) }
            .sheet(item: $editingSmart) { SmartListEditor(list: $0, allLists: lists, allTags: tags) }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast).font(DS.Font.caption).padding(.horizontal, DS.Space.m).padding(.vertical, DS.Space.s)
                        .glassEffect(.regular, in: Capsule()).padding(.bottom, DS.Space.l)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s) {
                ForEach([TaskFilter.today, .next7, .inbox, .all, .matrix, .someday, .completed], id: \.self) { chip($0) }
                ForEach(lists, id: \.self) { chip(.list($0)) }
                ForEach(tags, id: \.self) { chip(.tag($0)) }
                ForEach(smartLists) { s in
                    Button { withAnimation(DS.spring) { filterKey = key(.smart(s.id)) }; Haptics.tap() } label: {
                        Chip(text: s.name, color: filter == .smart(s.id) ? DS.Palette.accent : .gray, icon: s.icon)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editingSmart = s }
                        Button("Delete", systemImage: "trash", role: .destructive) { ctx.delete(s); filterKey = "today" }
                    }
                }
                Button { newSmart = true } label: { Chip(text: "Smart list", color: .gray, icon: "plus") }.buttonStyle(.plain)
            }
            .padding(.horizontal).padding(.vertical, DS.Space.s)
        }
    }

    private func chip(_ f: TaskFilter) -> some View {
        Button { withAnimation(DS.spring) { filterKey = key(f) }; Haptics.tap() } label: {
            Chip(text: f.title, color: filter == f ? DS.Palette.accent : .gray, icon: f.icon)
        }
        .buttonStyle(.plain)
    }

    private var list: some View {
        List(selection: $selectedTasks) {
            if filter != .completed && !selecting {
                Section {
                    HStack {
                        Image(systemName: "plus.circle.fill").foregroundStyle(DS.Palette.accent)
                        TextField("Add a task — “Gym every Mon 7am !high #health”", text: $newTitle)
                            .focused($addFocused)
                            .onSubmit(add)
                            .submitLabel(.done)
                    }
                } footer: {
                    if addFocused {
                        Text("Dates: “tomorrow 5pm” · Repeat: “every weekday”, “every 2 weeks” · !high · #tag · ~List")
                            .font(.caption2)
                    }
                }
            }

            if filter == .completed {
                ForEach(filtered) { t in row(t) }
            } else {
                ForEach(groups, id: \.title) { g in
                    Section(g.title) { ForEach(g.items) { t in row(t) } }
                }
                let waiting = filtered.filter(\.isWaitingOn)
                if !waiting.isEmpty {
                    Section("Waiting on others") { ForEach(waiting) { row($0) } }
                }
            }

            if filtered.isEmpty {
                ContentUnavailableView(filter == .completed ? "Nothing completed yet" : "Nothing here",
                                       systemImage: filter == .today ? "sun.max" : "checkmark.circle",
                                       description: Text(filter == .today ? "A clear day. Add something, or enjoy it." : "Add a task above."))
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(selecting ? .active : .inactive))
        .safeAreaInset(edge: .bottom) { if selecting { taskBulkBar } }
    }

    /// Board shows the current list's open tasks plus recently done ones.
    private var boardTasks: [TaskItem] {
        let done = tasks.filter(\.isDone)
        switch filter {
        case .list(let l): return filtered + done.filter { $0.listName == l }
        case .tag(let t): return filtered + done.filter { $0.tags.contains(t) }
        default: return filtered + done.filter { $0.completedAt.map { Calendar.current.isDateInToday($0) } ?? false }
        }
    }

    private var groups: [(title: String, items: [TaskItem])] {
        let active = filtered.filter { !$0.isWaitingOn }
        let start = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: start)!
        let dayAfter = cal.date(byAdding: .day, value: 2, to: start)!
        let week = cal.date(byAdding: .day, value: 8, to: start)!
        func sorted(_ a: [TaskItem]) -> [TaskItem] {
            a.sorted { ($0.dueDate ?? .distantFuture, -$0.priority.rawValue) < ($1.dueDate ?? .distantFuture, -$1.priority.rawValue) }
        }
        let buckets: [(String, (TaskItem) -> Bool)] = [
            ("Overdue", { ($0.dueDate ?? .distantFuture) < start }),
            ("Today", { ($0.dueDate.map { $0 >= start && $0 < tomorrow }) == true }),
            ("Tomorrow", { ($0.dueDate.map { $0 >= tomorrow && $0 < dayAfter }) == true }),
            ("Next 7 Days", { ($0.dueDate.map { $0 >= dayAfter && $0 < week }) == true }),
            ("Later", { ($0.dueDate.map { $0 >= week }) == true }),
            ("No Date", { $0.dueDate == nil }),
        ]
        let pinned: [(title: String, items: [TaskItem])] = [("Pinned", sorted(active.filter(\.isPinned)))]
        return (pinned + buckets.map { (title, test) in (title, sorted(active.filter { !$0.isPinned && test($0) })) })
            .filter { !$0.items.isEmpty }
    }

    @ViewBuilder
    private func row(_ t: TaskItem) -> some View {
        NavigationLink { TaskDetailView(task: t) } label: {
            TaskRow(task: t, showList: { if case .list = filter { return false }; return true }(), onRolled: showRolled)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { withAnimation { TaskActions.delete(t, ctx: ctx) } } label: { Label("Delete", systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            Button { move(t, days: 1) } label: { Label("Tomorrow", systemImage: "sunrise") }.tint(DS.Palette.warmth)
            Button { move(t, days: 7) } label: { Label("Next week", systemImage: "calendar") }.tint(DS.Palette.meeting)
        }
        .contextMenu {
            Button(t.isDone ? "Mark Not Done" : "Done", systemImage: t.isDone ? "circle" : "checkmark.circle") {
                withAnimation(DS.spring) { _ = TaskActions.setDone(t, !t.isDone) }
                try? ctx.save()
                Haptics.success()
            }
            #if !targetEnvironment(macCatalyst)
            if t.hasDueTime {
                Button(TaskAlarms.wanted(t) ? "Turn Off Full-Screen Alarm" : "Full-Screen Alarm", systemImage: TaskAlarms.wanted(t) ? "alarm.waves.left.and.right" : "alarm") {
                    t.useAlarm = !TaskAlarms.wanted(t)
                    TaskAlerts.schedule(t)
                    Haptics.tap()
                }
            }
            #endif
            Divider()
            Button("Today", systemImage: "sun.max") { move(t, days: 0) }
            Button("Tomorrow", systemImage: "sunrise") { move(t, days: 1) }
            Button("Next week", systemImage: "calendar") { move(t, days: 7) }
            Button("No date", systemImage: "calendar.badge.minus") { t.dueDate = nil; t.updatedAt = Date(); try? CalendarService.shared.push(t); TaskAlerts.cancel(t) }
            Menu("Priority") {
                ForEach(TaskPriority.allCases.reversed(), id: \.self) { p in
                    Button(p.label) { t.priority = p; t.updatedAt = Date(); try? CalendarService.shared.push(t) }
                }
            }
            Divider()
            Button(t.isPinned ? "Unpin" : "Pin", systemImage: t.isPinned ? "pin.slash" : "pin") {
                withAnimation(DS.spring) { t.isPinned.toggle() }; Haptics.tap()
            }
            Button("Duplicate", systemImage: "plus.square.on.square") { TaskActions.duplicate(t, ctx: ctx) }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { TaskActions.delete(t, ctx: ctx) }
        }
    }

    private func move(_ t: TaskItem, days: Int) {
        let day = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: Date()))!
        withAnimation(DS.spring) { TaskActions.reschedule(t, to: day) }
        Haptics.tap()
    }

    private func add() {
        guard !newTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        var defaultList: String?
        var defaultDue: Date?
        switch filter {
        case .list(let l): defaultList = l
        case .today: defaultDue = cal.startOfDay(for: Date())
        default: break
        }
        var input = newTitle
        if case .tag(let tag) = filter, !input.contains("#\(tag)") { input += " #\(tag)" }
        QuickAdd.create(input, in: ctx, defaultList: defaultList, defaultDue: defaultDue)
        newTitle = ""
        Haptics.tap()
    }

    private func showRolled(_ next: Date) {
        withAnimation { toast = "Repeats — next: \(next.formatted(.relative(presentation: .named)))" }
        Task { try? await Task.sleep(for: .seconds(2.5)); withAnimation { toast = nil } }
    }
}

extension TaskPriority {
    var label: String { switch self { case .none: "None"; case .low: "Low"; case .medium: "Medium"; case .high: "High" } }
    var color: Color { switch self { case .none: DS.Palette.inkSoft; case .low: DS.Palette.meeting; case .medium: DS.Palette.warmth; case .high: .red } }
}

struct TaskRow: View {
    @Bindable var task: TaskItem
    var showList = true
    var onRolled: ((Date) -> Void)? = nil

    var body: some View {
        HStack(spacing: DS.Space.m) {
            CompletionCheck(isDone: Binding(get: { task.isDone }, set: { done in
                if let next = TaskActions.setDone(task, done) { onRolled?(next) }
            }))
            .tint(task.priority.color)
            .overlay {
                // TickTick-style: the checkbox ring takes the priority color
                if task.priority != .none && !task.isDone {
                    Circle().strokeBorder(task.priority.color, lineWidth: 2).frame(width: 22, height: 22).allowsHitTesting(false)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).strikethrough(task.isDone).foregroundStyle(task.isDone ? DS.Palette.inkSoft : DS.Palette.ink)
                HStack(spacing: 6) {
                    if let d = task.dueDate {
                        Text(dueText(d)).foregroundStyle(d < Date() && !task.isDone && !UserDefaults.standard.bool(forKey: Prefs.calm) ? DS.Palette.warmth : DS.Palette.inkSoft)
                    }
                    if task.isPinned { Image(systemName: "pin.fill").foregroundStyle(DS.Palette.accent) }
                    if task.blockedById != nil { Image(systemName: "lock.fill").accessibilityLabel("Blocked by another task") }
                    if TaskTimer.shared.isRunning(task) { Image(systemName: "stopwatch.fill").foregroundStyle(DS.Palette.warmth) }
                    if task.recurrence != nil { Image(systemName: "repeat") }
                    if task.alertOffsetMinutes != nil { Image(systemName: "bell") }
                    if task.locationName != nil { Image(systemName: "location") }
                    if !task.microSteps.isEmpty { Text("\(task.microSteps.filter(\.done).count)/\(task.microSteps.count)") }
                    if task.sourceEmailId != nil { Image(systemName: "envelope") }
                    if showList && task.listName != "Inbox" { Text(task.listName) }
                    ForEach(task.tags.prefix(2), id: \.self) { Text("#\($0)").foregroundStyle(DS.Palette.accent) }
                }
                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            Spacer()
            Image(systemName: task.energy.icon).font(.caption).foregroundStyle(DS.Palette.inkSoft)
        }
    }

    private func dueText(_ d: Date) -> String {
        let cal = Calendar.current
        let day = cal.isDateInToday(d) ? "Today" : cal.isDateInTomorrow(d) ? "Tomorrow" : cal.isDateInYesterday(d) ? "Yesterday"
            : d.formatted(.dateTime.month(.abbreviated).day())
        return task.hasDueTime ? "\(day) \(d.formatted(date: .omitted, time: .shortened))" : day
    }
}

/// Eisenhower matrix: important = medium/high priority; urgent = due within 2 days (or overdue).
struct MatrixView: View {
    let tasks: [TaskItem]
    var onRolled: (Date) -> Void

    private func urgent(_ t: TaskItem) -> Bool {
        (t.dueDate ?? .distantFuture) < Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: Date()))!
    }
    private func important(_ t: TaskItem) -> Bool { t.priority.rawValue >= TaskPriority.medium.rawValue }

    var body: some View {
        let quadrants: [(String, String, Color, [TaskItem])] = [
            ("Do now", "Urgent & important", .red, tasks.filter { urgent($0) && important($0) }),
            ("Schedule", "Important, not urgent", DS.Palette.accent, tasks.filter { !urgent($0) && important($0) }),
            ("Quick / hand off", "Urgent, less important", DS.Palette.warmth, tasks.filter { urgent($0) && !important($0) }),
            ("Later / drop", "Neither", DS.Palette.inkSoft, tasks.filter { !urgent($0) && !important($0) }),
        ]
        ScrollView {
            FlexGrid(columns: 2, spacing: DS.Space.s) {
                ForEach(quadrants, id: \.0) { q in
                    GlassCard(tint: q.2) {
                        VStack(alignment: .leading, spacing: DS.Space.s) {
                            Text(q.0).font(DS.Font.headline).foregroundStyle(q.2)
                            Text(q.1).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                            if q.3.isEmpty { Text("—").foregroundStyle(DS.Palette.inkSoft) }
                            ForEach(q.3.prefix(8)) { t in
                                NavigationLink { TaskDetailView(task: t) } label: {
                                    HStack(spacing: 6) {
                                        CompletionCheck(isDone: Binding(get: { t.isDone }, set: { done in
                                            if let next = TaskActions.setDone(t, done) { onRolled(next) }
                                        }))
                                        .scaleEffect(0.8)
                                        Text(t.title).font(DS.Font.caption).lineLimit(2).foregroundStyle(DS.Palette.ink)
                                        Spacer(minLength: 0)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            if q.3.count > 8 { Text("+\(q.3.count - 8) more").font(.caption2).foregroundStyle(DS.Palette.inkSoft) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
                    }
                }
            }
            .padding()
        }
    }
}

struct TaskDetailView: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var allTasks: [TaskItem]
    @State private var breaking = false
    @State private var newStep = ""
    @State private var showRepeat = false
    @State private var newListName = ""
    @State private var showNewList = false
    @State private var confirmDelete = false
    @Query(filter: #Predicate<Goal> { !$0.isArchived }) private var goals: [Goal]
    @State private var showLocation = false
    @Query(filter: #Predicate<Project> { !$0.isArchived }) private var projects: [Project]

    private let cal = Calendar.current

    private var lists: [String] {
        Array(Set(allTasks.map(\.listName) + CalendarService.shared.reminderLists.map(\.title) + ["Inbox"])).sorted()
    }

    var body: some View {
        detailBody.savePoint { SavePoints.task(task) }
    }

    @ViewBuilder private var detailBody: some View {
        Form {
            Section {
                TextField("Title", text: $task.title, axis: .vertical).font(DS.Font.headline)
                Picker("Priority", selection: $task.priority) {
                    ForEach(TaskPriority.allCases.reversed(), id: \.self) { p in
                        Label(p.label, systemImage: p == .none ? "flag.slash" : "flag.fill").tint(p.color).tag(p)
                    }
                }
            }

            TaskTimerSection(task: task)
            Section("When") {
                Toggle("Due date", isOn: Binding(
                    get: { task.dueDate != nil },
                    set: { on in task.dueDate = on ? cal.startOfDay(for: Date()) : nil }))
                if task.dueDate != nil {
                    DatePicker("Date", selection: Binding(get: { task.dueDate ?? Date() }, set: { setDay($0) }), displayedComponents: .date)
                    Toggle("Time", isOn: Binding(
                        get: { task.hasDueTime },
                        set: { on in
                            let day = cal.startOfDay(for: task.dueDate ?? Date())
                            task.dueDate = on ? cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) : day
                            if on && task.alertOffsetMinutes == nil { task.alertOffsetMinutes = 0 }
                        }))
                    if task.hasDueTime {
                        DatePicker("Time", selection: Binding(get: { task.dueDate ?? Date() }, set: { task.dueDate = $0 }), displayedComponents: .hourAndMinute)
                    }
                    Menu {
                        Button("None") { task.recurrence = nil }
                        Button("Daily") { task.recurrence = Recurrence(frequency: .daily) }
                        Button("Every weekday") { task.recurrence = .weekdaysOnly }
                        Button("Weekly on \(weekdayName)") {
                            task.recurrence = Recurrence(frequency: .weekly, weekdays: [cal.component(.weekday, from: task.dueDate ?? Date())])
                        }
                        Button("Monthly") { task.recurrence = Recurrence(frequency: .monthly) }
                        Button("Yearly") { task.recurrence = Recurrence(frequency: .yearly) }
                        Divider()
                        Button("Custom…") { showRepeat = true }
                    } label: {
                        LabeledContent("Repeat", value: task.recurrence?.label ?? "Never")
                    }
                    Picker("Alert", selection: $task.alertOffsetMinutes) {
                        ForEach(TaskAlerts.offsets, id: \.label) { Text($0.label).tag($0.minutes) }
                    }
                    if task.alertOffsetMinutes != nil && task.hasDueTime {
                        Toggle(isOn: Binding(get: { TaskAlarms.wanted(task) }, set: { task.useAlarm = $0; TaskAlerts.schedule(task) })) {
                            Label("Full-screen alarm", systemImage: "alarm")
                        }
                    }
                    if task.completionCount > 0 {
                        LabeledContent("Completed", value: "\(task.completionCount) times")
                    }
                }
            }

            Section {
                Button { showLocation = true } label: {
                    LabeledContent {
                        Text(task.locationName.map { "\(task.remindOnArrive ? "Arriving at" : "Leaving") \($0)" } ?? "None")
                    } label: { Label("Location", systemImage: "location") }
                }
                .foregroundStyle(DS.Palette.ink)
            } footer: {
                if task.locationName != nil { Text("Apple Reminders will alert you at this place, even when Keel is closed.") }
            }

            Section("Organize") {
                Picker("List", selection: $task.listName) {
                    ForEach(lists, id: \.self) { Text($0).tag($0) }
                }
                Picker("Project", selection: $task.projectId) {
                    Text("None").tag(UUID?.none)
                    ForEach(projects) { p in Text("\(p.emoji) \(p.name)").tag(Optional(p.id)) }
                }
                Toggle("Someday", isOn: $task.isSomeday)
                Picker("Goal", selection: $task.goalId) {
                    Text("None").tag(UUID?.none)
                    ForEach(goals) { g in Text("\(g.emoji) \(g.title)").tag(Optional(g.id)) }
                }
                Button("New list…") { showNewList = true }
                TextField("Tags (comma separated)", text: Binding(
                    get: { task.tags.joined(separator: ", ") },
                    set: { task.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "") }.filter { !$0.isEmpty } }))
                    .textInputAutocapitalization(.never)
            }

            Section("Plan") {
                Picker("Energy needed", selection: $task.energy) { ForEach(EnergyLevel.allCases) { Text($0.label).tag($0) } }
                Stepper("Estimate: \(task.estimatedMinutes ?? 25) min  (really ~\(ADHDCoach.calibratedMinutes(task)))",
                        value: Binding(get: { task.estimatedMinutes ?? 25 }, set: { task.estimatedMinutes = $0 }), in: 5...480, step: 5)
                Toggle("Waiting on someone else", isOn: $task.isWaitingOn)
                Picker("Blocked By", selection: $task.blockedById) {
                    Text("Nothing").tag(UUID?.none)
                    ForEach(allTasks.filter { !$0.isDone && $0.id != task.id && $0.blockedById != task.id }.sorted { $0.title < $1.title }) { t in
                        Text(t.title).lineLimit(1).tag(Optional(t.id))
                    }
                }
                Button("Block time on my calendar") {
                    if let slot = CalendarService.shared.freeSlots(minMinutes: ADHDCoach.calibratedMinutes(task)).first {
                        try? CalendarService.shared.timeBlock(task, start: slot.start, minutes: ADHDCoach.calibratedMinutes(task))
                        Haptics.success()
                    }
                }
            }

            Section {
                ForEach($task.microSteps) { $step in
                    HStack {
                        CompletionCheck(isDone: $step.done)
                        TextField("Step", text: $step.text)
                        Text("\(step.minutes)m").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
                .onDelete { task.microSteps.remove(atOffsets: $0) }
                .onMove { task.microSteps.move(fromOffsets: $0, toOffset: $1) }
                HStack {
                    Image(systemName: "plus").foregroundStyle(DS.Palette.accent)
                    TextField("Add a subtask", text: $newStep).onSubmit {
                        guard !newStep.isEmpty else { return }
                        task.microSteps.append(MicroStep(text: newStep, minutes: 5))
                        newStep = ""
                    }
                }
                Button { Task { await breakDown() } } label: {
                    Label(breaking ? "Thinking…" : "Break into tiny steps with AI", systemImage: "sparkles")
                }.disabled(breaking)
            } header: { Text("Subtasks") } footer: { Text("Stuck? The first step is always small enough to start right now.") }

            if task.isDone || task.completionCount > 0 {
                Section {
                    HStack {
                        ForEach(TaskFeeling.allCases) { f in
                            Button { task.feeling = task.feeling == f ? nil : f; Haptics.tap() } label: {
                                VStack(spacing: 2) {
                                    Text(f.emoji).font(.title2)
                                    Text(f.label).font(.caption2).multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                                .background(task.feeling == f ? DS.Palette.accent.opacity(0.15) : .clear, in: .rect(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: { Text("How did it feel?") } footer: {
                    Text("Notice what gives you energy (play, power, people) and what drains you. Your weekly review shows the pattern.")
                }
            }
            if let g = goals.first(where: { $0.id == task.goalId }), !g.why.isEmpty {
                Section("Why this matters") { Text("\(g.emoji) \(g.why)").foregroundStyle(DS.Palette.inkSoft) }
            }
            Section("Notes") { TextEditor(text: $task.notes).frame(minHeight: 100) }
            TaskAttachmentsSection(task: task)

            Section {
                Button("Delete task", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle("Task")
        .toolbar { EditButton() }
        .sheet(isPresented: $showLocation) { LocationPicker(task: task) }
        .sheet(isPresented: $showRepeat) { RecurrenceEditor(rule: $task.recurrence, anchor: task.dueDate ?? Date()) }
        .alert("New list", isPresented: $showNewList) {
            TextField("Name", text: $newListName)
            Button("Create") { if !newListName.isEmpty { task.listName = newListName; newListName = "" } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { TaskActions.delete(task, ctx: ctx); dismiss() }
        }
        .onDisappear {
            guard !task.isDeleted else { return }
            task.updatedAt = Date()
            try? CalendarService.shared.push(task)
            TaskAlerts.schedule(task)
        }
    }

    private var weekdayName: String {
        (task.dueDate ?? Date()).formatted(.dateTime.weekday(.wide))
    }

    /// Changing the day keeps the time of day.
    private func setDay(_ newDay: Date) {
        guard let old = task.dueDate else { task.dueDate = cal.startOfDay(for: newDay); return }
        let c = cal.dateComponents([.hour, .minute], from: old)
        task.dueDate = cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: newDay)
    }

    private func breakDown() async {
        breaking = true; defer { breaking = false }
        let steps = await AIRouter.shared.breakDown(task.title, minutesAvailable: task.estimatedMinutes)
        withAnimation(DS.spring) { task.microSteps = steps }
    }
}

/// Custom repeat: every N days/weeks/months/years, specific weekdays, optional end date.
struct RecurrenceEditor: View {
    @Binding var rule: Recurrence?
    let anchor: Date
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Recurrence(frequency: .weekly)
    @State private var hasEnd = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Repeat every", selection: $draft.frequency) {
                    ForEach(Recurrence.Frequency.allCases) { Text($0.unit.capitalized).tag($0) }
                }
                Stepper("Every \(draft.interval) \(draft.frequency.unit)\(draft.interval == 1 ? "" : "s")", value: $draft.interval, in: 1...30)
                if draft.frequency == .weekly {
                    Section("On") {
                        let symbols = Calendar.current.weekdaySymbols
                        ForEach(1...7, id: \.self) { d in
                            Toggle(symbols[d - 1], isOn: Binding(
                                get: { draft.weekdays.contains(d) },
                                set: { on in
                                    if on { draft.weekdays.append(d) } else { draft.weekdays.removeAll { $0 == d } }
                                    draft.weekdays.sort()
                                }))
                        }
                    }
                }
                Section {
                    Toggle("Count From When I Finish", isOn: Binding(get: { draft.fromCompletion == true }, set: { draft.fromCompletion = $0 ? true : nil }))
                } footer: { Text("Good for chores: “every 2 weeks” means 2 weeks after you last did it, not on a fixed date.") }
                Section {
                    Toggle("Ends", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("On", selection: Binding(get: { draft.endDate ?? anchor }, set: { draft.endDate = $0 }), displayedComponents: .date)
                    }
                }
                Section { Text(draft.label).foregroundStyle(DS.Palette.inkSoft) }
            }
            .navigationTitle("Custom repeat")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if !hasEnd { draft.endDate = nil }
                        rule = draft
                        dismiss()
                    }
                }
            }
            .onAppear {
                draft = rule ?? Recurrence(frequency: .weekly, weekdays: [Calendar.current.component(.weekday, from: anchor)])
                hasEnd = draft.endDate != nil
            }
        }
    }
}

/// Tiny natural-language date parser using NSDataDetector (on-device, free).
enum NaturalDate {
    static func parse(_ s: String) -> (title: String, date: Date?) {
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let m = det.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range, in: s) else { return (s, nil) }
        let title = s.replacingCharacters(in: r, with: "").trimmingCharacters(in: .whitespaces)
        return (title.isEmpty ? s : title, m.date)
    }
}

private struct ListName: Identifiable { var name: String; var id: String { name } }
