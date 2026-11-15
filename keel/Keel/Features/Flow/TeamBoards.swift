import SwiftUI
import SwiftData
import UserNotifications

// MARK: - Team boards: shared task boards with assignees, due dates, comments, @mentions and an activity feed
//
// A board lives on your Keel server. Anyone you send the link to can join: in Keel, or in a web browser if they
// don't have Keel. Everyone sees changes within seconds, and Keel tells you when someone assigns you a task,
// mentions you, or finishes something you asked for.

struct TeamComment: Codable, Hashable, Identifiable { var id: String; var by: String; var text: String; var at: Double; var mentions: [String]? }

struct TeamTask: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var notes: String
    var status: String          // todo | doing | done
    var assignee: String
    var due: String
    var createdBy: String
    var created: Double
    var updated: Double
    var comments: [TeamComment]

    var dueDate: Date? { due.isEmpty ? nil : (ISO8601DateFormatter().date(from: due) ?? Self.dayFormat.date(from: String(due.prefix(10)))) }
    static let dayFormat: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()
}

struct TeamActivity: Codable, Hashable {
    var at: Double
    var by: String
    var text: String
    var task: String?
    var forWhom: [String]?          // people this is news for (assigned, mentioned, their task finished)
    enum CodingKeys: String, CodingKey { case at, by, text, task, forWhom = "for" }
}

struct TeamMine: Identifiable, Hashable { let ref: TeamBoardRef; let task: TeamTask; var id: String { ref.id + task.id } }

struct TeamBoardData: Codable, Hashable {
    var name: String
    var owner: String
    var members: [String]
    var tasks: [TeamTask]
    var activity: [TeamActivity]
    var version: Int
    var updated: Double
}

struct TeamBoardRef: Codable, Hashable, Identifiable { var id: String; var name: String; var url: String }

@MainActor
enum TeamAPI {
    static let key = "team.boards"
    static var boards: [TeamBoardRef] {
        get { LocalLog.load(key) }
        set { LocalLog.save(newValue, key) }
    }
    static var me: String { SharedLists.myName }


    static func create(name: String) async throws -> TeamBoardRef {
        let data = try await KeelCloud.call("team", method: "POST", body: ["name": name, "by": me], auth: true)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = json?["id"] as? String, let url = json?["url"] as? String else { throw KeelCloud.Failure.http(500) }
        let ref = TeamBoardRef(id: id, name: name, url: url)
        boards = [ref] + boards.filter { $0.id != id }
        return ref
    }

    /// A board link (…/t/<id>) or just the id.
    static func boardId(from text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let r = t.range(of: #"[a-f0-9]{32}"#, options: .regularExpression) else { return nil }
        return String(t[r])
    }

    static func join(link: String) async throws -> TeamBoardRef {
        guard let id = boardId(from: link) else { throw KeelCloud.Failure.http(404) }
        let board = try await change(id, ["op": "join"])
        let base = KeelServer.baseURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let ref = TeamBoardRef(id: id, name: board.name, url: "\(base)/t/\(id)")
        boards = [ref] + boards.filter { $0.id != id }
        return ref
    }

    static func get(_ id: String) async throws -> TeamBoardData {
        try JSONDecoder().decode(TeamBoardData.self, from: try await KeelCloud.call("team/\(id)"))
    }

    @discardableResult
    static func change(_ id: String, _ op: [String: Any]) async throws -> TeamBoardData {
        var body = op
        body["by"] = me
        let data = try await KeelCloud.call("team/\(id)", method: "POST", body: body, auth: op["op"] as? String == "delete")
        return try JSONDecoder().decode(TeamBoardData.self, from: data)
    }

    static func dueString(_ d: Date?) -> String { d.map { TeamTask.dayFormat.string(from: $0) } ?? "" }

    // MARK: Notifications for you (assigned, mentioned, your task finished)

    static let seenKey = "team.seen"           // boardId → last activity time seen

    /// Checks each board for news about you since last time and shows it as a notification. Runs when Keel opens.
    static func checkForNews() async {
        guard !boards.isEmpty, !KeelRuntime.isTesting else { return }
        var seen = (UserDefaults.standard.dictionary(forKey: seenKey) as? [String: Double]) ?? [:]
        for ref in boards {
            guard let b = try? await get(ref.id) else { continue }
            let last = seen[ref.id] ?? Date().timeIntervalSince1970 * 1000
            let news = b.activity.filter { $0.at > last && $0.by != me && ($0.forWhom ?? []).contains(me) }
            for a in news.suffix(5) {
                Kit.notify("team.\(ref.id).\(Int(a.at))", title: "\(a.by) · \(b.name)", body: a.text, at: Date().addingTimeInterval(1))
            }
            seen[ref.id] = b.activity.last?.at ?? last
            if b.name != ref.name { boards = boards.map { $0.id == ref.id ? TeamBoardRef(id: $0.id, name: b.name, url: $0.url) : $0 } }
        }
        UserDefaults.standard.set(seen, forKey: seenKey)
    }
}

// MARK: - Boards list

struct TeamBoardsView: View {
    @State private var boards: [TeamBoardRef] = []
    @State private var mine: [TeamMine] = []
    @State private var newName = ""
    @State private var link = ""
    @State private var creating = false
    @State private var joining = false
    @State private var error: String?
    @State private var open: TeamBoardRef?

    var body: some View {
        List {
            Section {
                KitIntro(icon: "person.3.fill", color: .indigo, text: "Team boards. Shared task boards for work, a project or the family. Assign tasks, set due dates, move them through To do, Doing and Done, comment and @mention people. Anyone with the link can join, in Keel or in a web browser, and Keel tells you when something's assigned to you.")
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            if !mine.isEmpty {
                Section("Assigned to you") {
                    ForEach(mine) { item in
                        let ref = item.ref
                        let t = item.task
                        Button { open = ref } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title).foregroundStyle(DS.Palette.ink)
                                Text([ref.name, t.status == "doing" ? "Doing" : "To do", t.dueDate.map { "due \($0.formatted(.dateTime.month(.abbreviated).day()))" }].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(DS.Palette.inkSoft)
                            }
                        }
                    }
                }
            }
            Section("Boards") {
                if boards.isEmpty { Text("No boards yet. Create one or join with a link.").foregroundStyle(DS.Palette.inkSoft) }
                ForEach(boards) { b in
                    Button { open = b } label: { Label(b.name, systemImage: "rectangle.split.3x1").foregroundStyle(DS.Palette.ink) }
                }
                .onDelete { idx in boards.remove(atOffsets: idx); TeamAPI.boards = boards }
            }
            Section {
                Button("New board", systemImage: "plus.circle.fill") { creating = true }
                Button("Join with a link", systemImage: "link.badge.plus") { joining = true }
            }
            if let error { Section { Text(error).foregroundStyle(.orange) } }
        }
        .navigationTitle("Team boards")
        .navigationDestination(item: $open) { TeamBoardView(ref: $0) }
        .task { boards = TeamAPI.boards; await loadMine() }
        .refreshable { await loadMine() }
        .alert("New board", isPresented: $creating) {
            TextField("Name (Launch, Family, Marketing…)", text: $newName)
            Button("Create") {
                let n = newName.trimmingCharacters(in: .whitespaces); newName = ""
                guard !n.isEmpty else { return }
                Task {
                    do { let r = try await TeamAPI.create(name: n); boards = TeamAPI.boards; open = r; error = nil }
                    catch let e { error = e.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Join a board", isPresented: $joining) {
            TextField("Paste the board link", text: $link)
            Button("Join") {
                let l = link; link = ""
                Task {
                    do { let r = try await TeamAPI.join(link: l); boards = TeamAPI.boards; open = r; error = nil }
                    catch { self.error = "Couldn't join that board. Check the link and that you're signed in to Keel." }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func loadMine() async {
        var out: [TeamMine] = []
        for ref in TeamAPI.boards {
            guard let b = try? await TeamAPI.get(ref.id) else { continue }
            out += b.tasks.filter { $0.assignee == TeamAPI.me && $0.status != "done" }.map { TeamMine(ref: ref, task: $0) }
        }
        mine = out.sorted { ($0.task.dueDate ?? .distantFuture) < ($1.task.dueDate ?? .distantFuture) }
    }
}

// MARK: - One board

struct TeamBoardView: View {
    let ref: TeamBoardRef
    @Environment(\.dismiss) private var dismiss
    @State private var board: TeamBoardData?
    @State private var page = 0                // 0 board, 1 mine, 2 activity
    @State private var newTitle = ""
    @State private var newAssignee = ""
    @State private var newDue: Date?
    @State private var openTask: TeamTask?
    @State private var error: String?

    var body: some View {
        List {
            Picker("", selection: $page) { Text("Board").tag(0); Text("Mine").tag(1); Text("Activity").tag(2) }
                .pickerStyle(.segmented).listRowBackground(Color.clear)
            if let error { Text(error).foregroundStyle(.orange).font(.caption) }
            if let b = board {
                if page == 2 {
                    Section {
                        ForEach(Array(b.activity.reversed().prefix(80).enumerated()), id: \.offset) { _, a in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(a.by) \(a.text)").font(.callout)
                                Text(Date(timeIntervalSince1970: a.at / 1000).formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                            }
                        }
                    }
                } else {
                    Section {
                        HStack {
                            TextField("New task", text: $newTitle).onSubmit(add)
                            Menu {
                                Button("Anyone") { newAssignee = "" }
                                ForEach(b.members, id: \.self) { m in Button(m == TeamAPI.me ? "Me" : m) { newAssignee = m } }
                            } label: { Label(newAssignee.isEmpty ? "Anyone" : newAssignee, systemImage: "person.crop.circle").labelStyle(.iconOnly) }
                            Menu {
                                Button("No date") { newDue = nil }
                                Button("Today") { newDue = Date() }
                                Button("Tomorrow") { newDue = Calendar.current.date(byAdding: .day, value: 1, to: Date()) }
                                Button("In a week") { newDue = Calendar.current.date(byAdding: .day, value: 7, to: Date()) }
                            } label: { Image(systemName: newDue == nil ? "calendar" : "calendar.badge.checkmark") }
                            Button("Add", action: add).disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        if !newAssignee.isEmpty || newDue != nil {
                            Text([newAssignee.isEmpty ? nil : "For \(newAssignee)", newDue.map { "due \($0.formatted(.dateTime.month(.abbreviated).day()))" }].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                    ForEach(["todo", "doing", "done"], id: \.self) { status in
                        let title = status == "todo" ? "To do" : status == "doing" ? "Doing" : "Done"
                        let tasks = b.tasks.filter { $0.status == status && (page == 0 || $0.assignee == TeamAPI.me) }
                            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
                        Section("\(title) · \(tasks.count)") {
                            ForEach(tasks) { t in
                                Button { openTask = t } label: { TeamTaskRow(task: t) }
                                    .swipeActions(edge: .leading) {
                                        if status != "done" { Button { set(t, ["status": "done"]) } label: { Label("Done", systemImage: "checkmark") }.tint(DS.Palette.calm) }
                                        if status == "todo" { Button { set(t, ["status": "doing"]) } label: { Label("Start", systemImage: "play") }.tint(.blue) }
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) { change(["op": "remove", "id": t.id]) } label: { Label("Delete", systemImage: "trash") }
                                        if t.assignee != TeamAPI.me { Button { set(t, ["assignee": TeamAPI.me]) } label: { Label("Take it", systemImage: "hand.raised") }.tint(.indigo) }
                                    }
                            }
                        }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(board?.name ?? ref.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: URL(string: ref.url) ?? URL(fileURLWithPath: "/"), message: Text("Join our board in Keel (or open it in a browser):")) {
                        Label("Invite people", systemImage: "person.badge.plus")
                    }
                    Button("Invite by text", systemImage: "message") {
                        AppleMessages.compose(TextDraft(body: "Join our \"\(board?.name ?? ref.name)\" board: \(ref.url)"))
                    }
                    if let b = board {
                        Section("Members (\(b.members.count))") { ForEach(b.members, id: \.self) { Text($0 == b.owner ? "\($0) · owner" : $0) } }
                    }
                    Button("Leave board", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        change(["op": "leave"]); TeamAPI.boards = TeamAPI.boards.filter { $0.id != ref.id }; dismiss()
                    }
                    if board?.owner == TeamAPI.me {
                        Button("Delete board for everyone", systemImage: "trash", role: .destructive) {
                            Task {
                                _ = try? await KeelCloud.call("team/\(ref.id)", method: "POST", body: ["op": "delete", "by": TeamAPI.me], auth: true)
                                TeamAPI.boards = TeamAPI.boards.filter { $0.id != ref.id }; dismiss()
                            }
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(item: $openTask) { t in
            if let b = board { TeamTaskSheet(boardId: ref.id, task: t, members: b.members) { board = $0 } }
        }
        .task {
            // Live: refresh every 10 seconds while the board is open.
            while !Task.isCancelled {
                do { board = try await TeamAPI.get(ref.id); error = nil } catch { if board == nil { self.error = "Couldn't load the board." } }
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .refreshable { board = try? await TeamAPI.get(ref.id) }
    }

    private func add() {
        let t = newTitle.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        change(["op": "add", "title": t, "assignee": newAssignee, "due": TeamAPI.dueString(newDue)])
        newTitle = ""; Haptics.tap()
    }

    private func set(_ t: TeamTask, _ fields: [String: Any]) {
        var op: [String: Any] = ["op": "update", "id": t.id]
        for (k, v) in fields { op[k] = v }
        change(op)
        if fields["status"] as? String == "done" { Haptics.success() }
    }

    private func change(_ op: [String: Any]) {
        Task {
            do { board = try await TeamAPI.change(ref.id, op); error = nil }
            catch { self.error = "That change didn't save. Check your connection." }
        }
    }
}

struct TeamTaskRow: View {
    let task: TeamTask
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: task.status == "done" ? "checkmark.circle.fill" : task.status == "doing" ? "circle.lefthalf.filled" : "circle")
                .foregroundStyle(task.status == "done" ? DS.Palette.calm : task.status == "doing" ? .blue : DS.Palette.inkSoft)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).foregroundStyle(DS.Palette.ink).strikethrough(task.status == "done")
                HStack(spacing: 6) {
                    Text(task.assignee.isEmpty ? "Anyone" : task.assignee == TeamAPI.me ? "You" : task.assignee)
                    if let d = task.dueDate {
                        Text("· due \(d.formatted(.dateTime.month(.abbreviated).day()))")
                            .foregroundStyle(d < Calendar.current.startOfDay(for: Date()) && task.status != "done" ? .red : DS.Palette.inkSoft)
                    }
                    if !task.comments.isEmpty { Label("\(task.comments.count)", systemImage: "bubble.left").labelStyle(.titleAndIcon) }
                }
                .font(.caption).foregroundStyle(DS.Palette.inkSoft)
            }
        }
    }
}

struct TeamTaskSheet: View {
    let boardId: String
    @State var task: TeamTask
    let members: [String]
    var updated: (TeamBoardData) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @State private var comment = ""
    @State private var hasDue = false
    @State private var due = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $task.title)
                    TextField("Notes", text: $task.notes, axis: .vertical).lineLimit(2...8)
                }
                Section {
                    Picker("Status", selection: $task.status) { Text("To do").tag("todo"); Text("Doing").tag("doing"); Text("Done").tag("done") }
                    Picker("Assigned to", selection: $task.assignee) {
                        Text("Anyone").tag("")
                        ForEach(members, id: \.self) { Text($0 == TeamAPI.me ? "Me" : $0).tag($0) }
                    }
                    Toggle("Due date", isOn: $hasDue)
                    if hasDue { DatePicker("Due", selection: $due, displayedComponents: .date) }
                }
                Section("Comments") {
                    ForEach(task.comments) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.by).font(.caption.weight(.semibold))
                            Text(c.text)
                            Text(Date(timeIntervalSince1970: c.at / 1000).formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                    HStack {
                        TextField("Comment, @Name to mention", text: $comment, axis: .vertical)
                        Button("Send") { send() }.disabled(comment.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if !members.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack { ForEach(members.filter { $0 != TeamAPI.me }, id: \.self) { m in Button("@\(m.split(separator: " ").first.map(String.init) ?? m)") { comment += (comment.isEmpty || comment.hasSuffix(" ") ? "" : " ") + "@\(m.split(separator: " ").first.map(String.init) ?? m) " }.buttonStyle(.bordered).controlSize(.small) } }
                        }
                    }
                }
                Section {
                    Button("Copy to my own tasks", systemImage: "square.and.arrow.down") {
                        let t = TaskItem(title: task.title, dueDate: hasDue ? due : nil)
                        t.notes = task.notes; t.listName = "Inbox"; ctx.insert(t); try? ctx.save()
                        UndoCenter.shared.notify("Added to your tasks")
                    }
                }
            }
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear { if let d = task.dueDate { hasDue = true; due = d } }
        }
    }

    private func send() {
        let text = comment.trimmingCharacters(in: .whitespaces)
        comment = ""
        Task {
            if let b = try? await TeamAPI.change(boardId, ["op": "comment", "id": task.id, "text": text]) {
                updated(b)
                if let t = b.tasks.first(where: { $0.id == task.id }) { task.comments = t.comments }
                Haptics.tap()
            }
        }
    }

    private func save() {
        let fields: [String: Any] = ["op": "update", "id": task.id, "title": task.title, "notes": task.notes, "status": task.status,
                                     "assignee": task.assignee, "due": hasDue ? TeamAPI.dueString(due) : ""]
        Task {
            if let b = try? await TeamAPI.change(boardId, fields) { updated(b) }
            dismiss()
        }
    }
}

/// From a personal task: send it to a team board.
struct ShareToTeamMenu: View {
    let task: TaskItem
    var body: some View {
        let boards = TeamAPI.boards
        if !boards.isEmpty {
            Menu {
                ForEach(boards) { b in
                    Button(b.name) {
                        Task {
                            _ = try? await TeamAPI.change(b.id, ["op": "add", "title": task.title, "notes": task.notes, "due": TeamAPI.dueString(task.dueDate)])
                            UndoCenter.shared.notify("Added to \(b.name)")
                        }
                    }
                }
            } label: { Label("Send to a team board", systemImage: "person.3") }
            .foregroundStyle(DS.Palette.ink)
        }
    }
}
