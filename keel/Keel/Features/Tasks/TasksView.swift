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
    @Query(sort: \TaskItem.createdAt, order: .reverse, animation: .snappy) private var tasks: [TaskItem]
    @Query(sort: \SmartList.createdAt) private var smartLists: [SmartList]
    @State private var deadlineFor: TaskItem?
    @State private var editingSmart: SmartList?
    @State private var selecting = false
    @State private var planning = false
    @State private var planningWeek = false
    @State private var selectedTasks = Set<UUID>()
    @State private var newSmart = false
    @AppStorage("tasks.filter") private var filterKey = "today"
    @State private var newTitle = ""
    @State private var search = ""
    @State private var toast: String?
    @AppStorage("tasks.board") private var boardMode = false
    @AppStorage("tasks.search.thisList") private var searchThisList = false
    @AppStorage(ReminderFailures.key) private var failedRaw = ""
    @State private var retryingReminders = false

    /// Said out loud when tasks aren't reaching Apple Reminders, instead of failing silently.
    @ViewBuilder private var remindersNotice: some View {
        let cal = CalendarService.shared
        let usesReminders = RemindersBridge.isThisDevice && tasks.contains { $0.ekReminderId != nil }
        let failedIds = failedRaw.isEmpty ? Set<UUID>() : ReminderFailures.ids
        let failed = failedIds.isEmpty ? 0 : tasks.filter { failedIds.contains($0.id) }.count
        if usesReminders && !cal.hasReminderAccess {
            Section {
                Label("Keel can't reach Apple Reminders, so changes here aren't syncing there.", systemImage: "exclamationmark.triangle.fill")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.warmth)
                Button("Allow access in Settings") {
                    if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                }.font(DS.Font.caption)
            }
        } else if failed > 0 {
            Section {
                HStack {
                    Label("\(failed) task\(failed == 1 ? "" : "s") didn't reach Reminders", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.warmth)
                    Spacer()
                    Button(retryingReminders ? "Retrying…" : "Retry") {
                        retryingReminders = true
                        let ids = ReminderFailures.ids
                        for t in tasks where ids.contains(t.id) { try? CalendarService.shared.push(t) }
                        retryingReminders = false
                        Haptics.tap()
                    }
                    .font(DS.Font.caption.weight(.semibold)).buttonStyle(.borderless).disabled(retryingReminders)
                }
            } footer: { Text("Keel also retries on its own each time it syncs.") }
        }
    }
    /// Finished tasks matching the search (shown under the open ones).
    private var searchDone: [TaskItem] {
        guard !search.isEmpty, !searchThisList, filter != .completed else { return [] }
        return memo.get(\.searchDone) {
            let terms = TaskSearch.terms(search)
            return tasks.filter { $0.isDone && TaskSearch.matches($0, terms) }
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        }
    }
    @State private var sharingList: String?
    @FocusState private var addFocused: Bool
    /// Per-update cache: filtering, grouping and sorting run once per screen update instead of once per use.
    @State private var memo = TasksMemo()

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
        memo.get(\.lists) { Array(Set(tasks.map(\.listName) + CalendarService.shared.reminderLists.map(\.title))).sorted() }
    }
    private var tags: [String] { memo.get(\.tags) { Array(Set(tasks.flatMap(\.tags))).filter { !TaskMeta.isHidden($0) }.sorted() } }

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

    private var filtered: [TaskItem] { memo.get(\.filtered) { computeFiltered() } }

    private func computeFiltered() -> [TaskItem] {
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
            // Search covers every task, whatever list you're on, unless you chose "This list".
            // Finished tasks that match are listed separately, under Completed.
            let terms = TaskSearch.terms(search)
            if !searchThisList && filter != .completed {
                base = tasks.filter { !$0.isDone && TaskSearch.matches($0, terms) }
            } else {
                base = base.filter { TaskSearch.matches($0, terms) }
            }
        }
        return base
    }

    var body: some View {
        let _ = memo.reset()          // a fresh update: forget last update's results
        NavigationStack {
            VStack(spacing: 0) {
                // The chips scroll with the content as its first row (as Inbox does). Sitting above the list or
                // matrix, under the large title and search field, they were drawn invisible: a blank strip that
                // still took taps, so you could get into Matrix and not see the way back.
                if filter == .matrix {
                    MatrixView(tasks: filtered.filter { !$0.isWaitingOn }, onRolled: showRolled, header: AnyView(filterBar))
                } else if boardMode && filter != .completed {
                    ScrollView {
                        filterBar
                        BoardView(tasks: boardTasks).containerRelativeFrame(.vertical)   // columns keep their own scrolling
                    }
                } else {
                    list
                }
            }
            .navigationTitle(screenTitle)
            .keelSettingsButton(help: .tasks)
            .searchable(text: $search, prompt: "Search tasks")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { LazyView(PromisesView()) } label: { Label("Promises", systemImage: "hand.raised.fingers.spread") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { LazyView(ProjectsView()) } label: { Label("Projects", systemImage: "folder") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { LazyView(ProcessInboxView()) } label: { Label("Sort", systemImage: "tray.and.arrow.down") }
                        .accessibilityLabel("Sort loose tasks")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(selecting ? "Done Selecting" : "Select Tasks", systemImage: "checkmark.circle") {
                            withAnimation { selecting.toggle(); selectedTasks = [] }
                        }
                        NavigationLink { LazyView(TasksCustomizeView()) } label: { Label("Customize Tasks…", systemImage: "slider.horizontal.3") }
                        NavigationLink { LazyView(DeletedTasksView()) } label: { Label("Recently deleted", systemImage: "trash") }
                        Button(boardMode ? "Show as list" : "Show as board", systemImage: boardMode ? "list.bullet" : "rectangle.split.3x1") {
                            withAnimation { boardMode.toggle() }
                        }
                        Section("Schedule") {
                            Button("Plan my day (drag onto hours)", systemImage: "calendar.day.timeline.left") { planning = true }
                            Button("Auto-schedule today", systemImage: "wand.and.stars") {
                                let r = AutoScheduler.scheduleToday(tasks: tasks)
                                withAnimation { toast = r.scheduled == 0 ? "Nothing fit today" : "Scheduled \(r.scheduled) on your calendar" }
                                Task { try? await Task.sleep(for: .seconds(2.5)); withAnimation { toast = nil } }
                            }
                            Button("Clear today's time blocks", systemImage: "calendar.badge.minus") { AutoScheduler.clearToday(tasks: tasks) }
                            NavigationLink { LazyView(PlanMyWeekView(embedded: true)) } label: { Label("Plan the week", systemImage: "calendar.day.timeline.left") }
                        }
                        Section("Get unstuck") {
                            NavigationLink { LazyView(DoneForYouView()) } label: { Label("Break it down for me", systemImage: "sparkles") }
                            NavigationLink { LazyView(DreadRadarView()) } label: { Label("What am I avoiding?", systemImage: "tortoise.fill") }
                            NavigationLink { LazyView(QuickWinsView()) } label: { Label("Quick wins", systemImage: "bolt.fill") }
                        }
                        Section("Bigger picture") {
                            NavigationLink { LazyView(GoalsView()) } label: { Label("Goals", systemImage: "flag.checkered") }
                            NavigationLink { LazyView(HabitsView()) } label: { Label("Habits", systemImage: "repeat") }
                            NavigationLink { LazyView(RoutinesView()) } label: { Label("Routines", systemImage: "list.bullet.rectangle") }
                            NavigationLink { LazyView(StatsView()) } label: { Label("Statistics", systemImage: "chart.xyaxis.line") }
                            NavigationLink { LazyView(RewardsView()) } label: { Label("Rewards", systemImage: "gift") }
                        }
                        Section("Lists") {
                            if case .list(let name) = filter {
                                Button("Share “\(name)”…", systemImage: "person.2") { sharingList = name }
                                Button("Save “\(name)” as a template", systemImage: "square.and.arrow.down") {
                                    TemplateSaver.save(listName: name, tasks: tasks.filter { !$0.isDone }, ctx: ctx)
                                    withAnimation { toast = "Saved as a template" }
                                    Task { try? await Task.sleep(for: .seconds(2)); withAnimation { toast = nil } }
                                }
                            }
                            NavigationLink { LazyView(TemplatesView()) } label: { Label("Templates", systemImage: "doc.on.doc") }
                            NavigationLink { LazyView(TeamBoardsView()) } label: { Label("Team boards", systemImage: "person.3") }
                            NavigationLink { LazyView(SharedListsView()) } label: { Label("Shared lists", systemImage: "person.2") }
                            NavigationLink { LazyView(ErrandsView()) } label: { Label("Errands by place", systemImage: "car") }
                        }
                        Menu("Set up", systemImage: "gearshape") {
                            NavigationLink { LazyView(TagsManagerView()) } label: { Label("Manage tags", systemImage: "number") }
                            NavigationLink { LazyView(AutomationsView()) } label: { Label("Automations", systemImage: "bolt.horizontal") }
                            NavigationLink { LazyView(ScreenshotTasksView()) } label: { Label("Tasks from screenshots", systemImage: "camera.viewfinder") }
                            NavigationLink { LazyView(TaskCSVImportView()) } label: { Label("Import a spreadsheet", systemImage: "tablecells") }
                        }
                    } label: { Image(systemName: "wand.and.stars") }
                    .accessibilityLabel("Schedule")
                }
            }
            .refreshable { await SyncEngine.shared.syncAll() }
            .sheet(isPresented: $planning) { DayPlannerView() }
            .sheet(item: Binding(get: { sharingList.map { ListName(name: $0) } }, set: { sharingList = $0?.name })) { ShareListSheet(listName: $0.name) }
            .sheet(isPresented: $newSmart) { SmartListEditor(list: nil, allLists: lists, allTags: tags) }
            .sheet(item: $deadlineFor) { DeadlineSheet(task: $0) }
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
            filterBar
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .selectionDisabled()
            remindersNotice
            if !search.isEmpty && filter != .completed {
                Picker("Search in", selection: $searchThisList) {
                    Text("All tasks").tag(false)
                    Text("This list only").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .selectionDisabled()
            }
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
                if !selecting {
                    HorizonHeader(title: screenTitle, detail: tasksHorizonDetail, compact: true)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                // Above the waterline: what's pinned, overdue, today and tonight. Below: what can wait, quieter.
                let above: Set<String> = ["Pinned", "Overdue", "Today", "This Evening"]
                let gs = groups
                ForEach(gs, id: \.title) { g in
                    if !above.contains(g.title), gs.first(where: { !above.contains($0.title) })?.title == g.title, gs.contains(where: { above.contains($0.title) }) {
                        Section { Waterline() }.listRowBackground(Color.clear)
                    }
                    Section(g.title) { ForEach(g.items) { t in row(t).opacity(above.contains(g.title) ? 1 : 0.82) } }
                }
                let waiting = filtered.filter(\.isWaitingOn)
                if !waiting.isEmpty {
                    Section {
                        ForEach(waiting) { row($0) }
                    } header: { Text("Waiting on others") } footer: {
                        // Who has what: "With Sam: 2 · With Alex: 1".
                        let who = memo.get(\.waitingWho) {
                            let d = Dictionary(grouping: waiting.compactMap { TaskAssign.who($0, ctx: ctx)?.name }, by: { $0 })
                            return d.map { "With \($0.key): \($0.value.count)" }.sorted().joined(separator: " · ")
                        }
                        if !who.isEmpty { Text(who) }
                    }
                }
            }

            if !searchDone.isEmpty {
                Section("Completed") {
                    ForEach(searchDone.prefix(100)) { t in row(t).opacity(0.7) }
                }
            }

            if filtered.isEmpty && searchDone.isEmpty {
                ContentUnavailableView(filter == .completed ? "Nothing completed yet" : "Nothing here",
                                       systemImage: filter == .today ? "sun.max" : "checkmark.circle",
                                       description: Text(filter == .today ? "A clear day. Add something, or enjoy it." : "Add a task above."))
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.taskSearchTerms, search.isEmpty ? [] : TaskSearch.terms(search))
        .premiumBackground(DS.Palette.warmth)
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

    private var tasksHorizonDetail: String {
        let end = cal.startOfDay(for: Date()).addingTimeInterval(86_400)
        let due = filtered.filter { ($0.dueDate ?? .distantFuture) < end }.count
        let done = tasks.filter { $0.completedAt.map { cal.isDateInToday($0) } ?? false }.count
        return due == 0 ? (done > 0 ? "\(done) done today · clear sailing" : "Clear sailing · \(HorizonSky.daylightLeft())") : "\(due) to do today\(done > 0 ? " · \(done) done" : "")"
    }

    private var groups: [(title: String, items: [TaskItem])] { memo.get(\.groups) { computeGroups() } }

    private func computeGroups() -> [(title: String, items: [TaskItem])] {
        let active = filtered.filter { !$0.isWaitingOn }
        let start = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: start)!
        let dayAfter = cal.date(byAdding: .day, value: 2, to: start)!
        let week = cal.date(byAdding: .day, value: 8, to: start)!
        let sortMode = Custom.taskSort                      // Settings → Customize Keel → Tasks
        func sorted(_ a: [TaskItem]) -> [TaskItem] {
            switch sortMode {
            case "priority": return a.sorted { ($0.priority.rawValue, $1.dueDate ?? .distantFuture) > ($1.priority.rawValue, $0.dueDate ?? .distantFuture) }
            case "title": return a.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            case "newest": return a.sorted { $0.createdAt > $1.createdAt }
            default: return a.sorted { ($0.dueDate ?? .distantFuture, -$0.priority.rawValue) < ($1.dueDate ?? .distantFuture, -$1.priority.rawValue) }
            }
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
        // Things-style: tonight's tasks get their own section after Today.
        let evening = Custom.taskEveningSection ? active.filter { !$0.isPinned && TaskMeta.isEvening($0) && ($0.dueDate ?? .distantFuture) < tomorrow } : []
        let eveningIds = Set(evening.map(\.id))
        let rest = active.filter { !eveningIds.contains($0.id) }
        var out = pinned + buckets.map { (title, test) in (title, sorted(rest.filter { !$0.isPinned && test($0) })) }
        if let i = out.firstIndex(where: { $0.title == "Today" }) ?? out.firstIndex(where: { $0.title == "Overdue" }) {
            out.insert(("This Evening", sorted(evening)), at: i + 1)
        } else {
            out.insert(("This Evening", sorted(evening)), at: min(2, out.count))
        }
        return out.filter { !$0.items.isEmpty }
    }

    @ViewBuilder
    private func row(_ t: TaskItem) -> some View {
        NavigationLink { LazyView(TaskDetailView(task: t)) } label: {
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
            Button("Start now (\(max(1, ADHDCoach.calibratedMinutes(t))) min)", systemImage: "timer") { NowTimer.start(t, ctx: ctx) }
            Menu("Duration: \(TaskDuration.label(ADHDCoach.minutes(t)))", systemImage: "clock") {
                ForEach(TaskDuration.presets, id: \.self) { m in
                    Button { t.estimatedMinutes = m; t.updatedAt = Date(); Haptics.tap() } label: {
                        if ADHDCoach.minutes(t) == m { Label(TaskDuration.label(m), systemImage: "checkmark") } else { Text(TaskDuration.label(m)) }
                    }
                }
            }
            Divider()
            Button("Today", systemImage: "sun.max") { TaskMeta.setEvening(t, false); move(t, days: 0) }
            Button(TaskMeta.isEvening(t) ? "Not This Evening" : "This Evening", systemImage: "moon.stars") {
                withAnimation(DS.spring) { TaskMeta.setEvening(t, !TaskMeta.isEvening(t)) }; Haptics.tap()
            }
            Button(TaskMeta.deadline(t) == nil ? "Set Deadline…" : "Change Deadline…", systemImage: "flag") { deadlineFor = t }
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
    @Environment(\.taskSearchTerms) private var searchTerms
    @Bindable var task: TaskItem
    var showList = true
    var onRolled: ((Date) -> Void)? = nil

    var body: some View {
        let prefs = TaskRowPrefs.current     // one cached read instead of six settings lookups per row
        let tags = task.tags                 // decoded once per row, not once per badge
        let deadline = tags.first { $0.hasPrefix(TaskMeta.deadlinePrefix) }.flatMap { ISO8601DateFormatter.dateOnly.date(from: String($0.dropFirst(TaskMeta.deadlinePrefix.count))) }
        let steps = task.microSteps
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
                if searchTerms.isEmpty {
                    Text(task.title).strikethrough(task.isDone).foregroundStyle(task.isDone ? DS.Palette.inkSoft : DS.Palette.ink)
                } else {
                    Text(EmailRow.lit(task.title, searchTerms, trim: false)).strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? DS.Palette.inkSoft : DS.Palette.ink)
                    if let hit = TaskSearch.hiddenMatch(task, searchTerms) {
                        // The word was in the task's notes or steps: show where.
                        Text(EmailRow.lit(hit, searchTerms, trim: true)).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                    }
                }
                HStack(spacing: 6) {
                    if let d = task.dueDate {
                        Text(dueText(d)).foregroundStyle(isLate(d) && !task.isDone && !prefs.calm ? DS.Palette.warmth : DS.Palette.inkSoft)
                    }
                    if task.isPinned { Image(systemName: "pin.fill").foregroundStyle(DS.Palette.accent) }
                    if task.blockedById != nil { Image(systemName: "lock.fill").accessibilityLabel("Blocked by another task") }
                    if TaskTimer.shared.isRunning(task) { Image(systemName: "stopwatch.fill").foregroundStyle(DS.Palette.warmth) }
                    if task.recurrence != nil { Image(systemName: "repeat") }
                    if task.alertOffsetMinutes != nil { Image(systemName: "bell") }
                    if task.locationName != nil { Image(systemName: "location") }
                    if !steps.isEmpty { Text("\(steps.filter(\.done).count)/\(steps.count)") }
                    if task.sourceEmailId != nil { Image(systemName: "envelope") }
                    if showList && prefs.showList && task.listName != "Inbox" { Text(task.listName) }
                    if prefs.showDuration && !task.isDone { Text("~\(ADHDCoach.minutes(task))m") }
                    if let dl = deadline {
                        Text("⚑ \(dl.formatted(.dateTime.month(.abbreviated).day()))").foregroundStyle(dl < Date().addingTimeInterval(2 * 86_400) ? DS.Palette.warmth : DS.Palette.inkSoft)
                    }
                    if tags.contains(TaskMeta.eveningTag) { Image(systemName: "moon.stars").foregroundStyle(.indigo) }
                    if prefs.showTags { ForEach(tags.filter { !TaskMeta.isHidden($0) }.prefix(2), id: \.self) { Text("#\($0)").foregroundStyle(DS.Palette.accent) } }
                }
                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            Spacer()
            if prefs.showEnergy { Image(systemName: task.energy.icon).font(.caption).foregroundStyle(DS.Palette.inkSoft) }
        }
    }

    /// Late only once the day is over for date-only tasks (a task due "today" isn't late at 9 AM).
    private func isLate(_ d: Date) -> Bool {
        task.hasDueTime ? d < Date() : d < Calendar.current.startOfDay(for: Date())
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
    /// Shown above the quadrants, inside the scroll view (the Tasks filter chips).
    var header: AnyView? = nil

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
            if let header { header }
            FlexGrid(columns: 2, spacing: DS.Space.s) {
                ForEach(quadrants, id: \.0) { q in
                    GlassCard(tint: q.2) {
                        VStack(alignment: .leading, spacing: DS.Space.s) {
                            Text(q.0).font(DS.Font.headline).foregroundStyle(q.2)
                            Text(q.1).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                            if q.3.isEmpty { Text("—").foregroundStyle(DS.Palette.inkSoft) }
                            ForEach(q.3.prefix(8)) { t in
                                NavigationLink { LazyView(TaskDetailView(task: t)) } label: {
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
                BufferedTextField("Title", text: $task.title, axis: .vertical).font(DS.Font.headline)
                Picker("Priority", selection: $task.priority) {
                    ForEach(TaskPriority.allCases.reversed(), id: \.self) { p in
                        Label(p.label, systemImage: p == .none ? "flag.slash" : "flag.fill").tint(p.color).tag(p)
                    }
                }
            }

            TaskTimerSection(task: task)
            Section { ConnectedStrip(key: "task:" + task.id.uuidString) }
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
                Button { AppleMessages.compose(TextDraft(context: task.title)) } label: { Label("Text someone about this", systemImage: "message") }
                    .foregroundStyle(DS.Palette.ink)
                ShareToTeamMenu(task: task)
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
                    get: { TaskMeta.visibleTags(task).joined(separator: ", ") },
                    set: { task.tags = task.tags.filter(TaskMeta.isHidden) + $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "") }.filter { !$0.isEmpty } }))
                    .textInputAutocapitalization(.never)
            }

            Section("Plan") {
                Picker("Energy needed", selection: $task.energy) { ForEach(EnergyLevel.allCases) { Text($0.label).tag($0) } }
                TaskDurationEditor(task: task)
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
            AssignSection(task: task)                       // hand it to someone
            WorkBackSection(task: task)                     // split a big deadline into dated steps
            Section("Notes") { BufferedTextEditor(text: $task.notes).frame(minHeight: 100) }
            TaskAttachmentsSection(task: task)

            Section {
                Button("Delete task", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle("Task")
        .userActivity(KeelHandoff.taskType) { a in            // Handoff to your other devices
            a.title = task.title
            a.userInfo = ["id": task.id.uuidString]
            a.isEligibleForHandoff = true
        }
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


// MARK: - Speed helpers

/// Remembers derived lists (filtered, grouped, sorted) for the length of one screen update.
/// A plain class in @State: writing to it never triggers another update.
final class TasksMemo {
    var lists: [String]?
    var tags: [String]?
    var filtered: [TaskItem]?
    var groups: [(title: String, items: [TaskItem])]?
    var searchDone: [TaskItem]?
    var waitingWho: String?
    func reset() { lists = nil; tags = nil; filtered = nil; groups = nil; searchDone = nil; waitingWho = nil }
    func get<T>(_ key: ReferenceWritableKeyPath<TasksMemo, T?>, _ make: () -> T) -> T {
        if let v = self[keyPath: key] { return v }
        let v = make(); self[keyPath: key] = v; return v
    }
}

@MainActor
/// Task row settings, read once and refreshed only when a setting changes (not six lookups per row per frame).
struct TaskRowPrefs {
    var calm: Bool, showList: Bool, showDuration: Bool, showTags: Bool, showEnergy: Bool
    nonisolated(unsafe) private static var cached: TaskRowPrefs?
    nonisolated(unsafe) private static var observer: NSObjectProtocol?
    static var current: TaskRowPrefs {
        if let c = cached { return c }
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { _ in
                TaskRowPrefs.cached = nil
            }
        }
        let c = TaskRowPrefs(calm: UserDefaults.standard.bool(forKey: Prefs.calm), showList: Custom.taskShowList,
                             showDuration: Custom.taskShowDuration, showTags: Custom.taskShowTags, showEnergy: Custom.taskShowEnergy)
        cached = c
        return c
    }
}


// MARK: - Task search

/// Task matching that ignores case, accents and curly vs straight quotes, and looks in the title, notes,
/// tags, list name and every step. Every word must be somewhere in the task; "quoted words" must be together.
enum TaskSearch {
    static func terms(_ raw: String) -> [String] {
        let q = NoteQuery.parse(raw, match: .all)
        return (q.phrases + q.terms + q.tags.map { String($0.dropFirst()) } + q.titleTerms).filter { !$0.isEmpty }
    }
    /// A task's searchable text, prepared once per edit (not for every task on every letter you type).
    nonisolated(unsafe) private static var cache: [UUID: (stamp: Int, text: String)] = [:]
    static func text(_ t: TaskItem) -> String {
        let parts = [t.title, t.notes, t.listName] + t.tags + t.microSteps.map(\.text)
        var h = Hasher()
        h.combine(parts)                       // keyed on the text itself, so any edit is picked up
        let stamp = h.finalize()
        if let c = cache[t.id], c.stamp == stamp { return c.text }
        let s = NoteText.fold(parts.joined(separator: " \u{1F} "))
        if cache.count > 8_000 { cache.removeAll(keepingCapacity: true) }
        cache[t.id] = (stamp, s)
        return s
    }
    static func matches(_ t: TaskItem, _ terms: [String]) -> Bool {
        guard !terms.isEmpty else { return true }
        let hay = text(t)
        return terms.allSatisfy { hay.contains($0) }
    }
    /// A match that isn't in the title (in the notes or a step), to show under the title.
    static func hiddenMatch(_ t: TaskItem, _ terms: [String]) -> String? {
        let inTitle = { (s: String) in terms.contains { s.range(of: $0, options: NoteText.compare) != nil } }
        if terms.allSatisfy({ t.title.range(of: $0, options: NoteText.compare) != nil }) { return nil }
        if inTitle(t.notes) { return t.notes }
        if let step = t.microSteps.first(where: { inTitle($0.text) }) { return "Step: " + step.text }
        return nil
    }
}

private struct TaskSearchTermsKey: EnvironmentKey { static let defaultValue: [String] = [] }
extension EnvironmentValues {
    /// The words being searched for in Tasks, so rows can highlight them (empty when not searching).
    var taskSearchTerms: [String] {
        get { self[TaskSearchTermsKey.self] }
        set { self[TaskSearchTermsKey.self] = newValue }
    }
}
