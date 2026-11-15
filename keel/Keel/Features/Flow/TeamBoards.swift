import SwiftUI
import SwiftData
import EventKit
import AuthenticationServices
import UserNotifications

// MARK: - Team boards: shared task boards with members, roles, invitations, chat, a team calendar and instant alerts
//
// Private boards (the default): everyone signs in with Apple and joins by invitation, with a role
// (owner, admin, member, viewer). Link boards: anyone with the link can edit, in Keel or a web browser.
// A board lives on the Keel server it was created on; its link carries that address, so teammates' Keel apps
// talk to the right server whatever their own settings are.

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

struct TeamChatMessage: Codable, Hashable, Identifiable { var id: String; var by: String; var text: String; var at: Double; var mentions: [String]? }

struct TeamEvent: Codable, Hashable, Identifiable {
    var id: String; var title: String; var start: String; var end: String; var notes: String; var by: String
    var startDate: Date? { ISO8601DateFormatter().date(from: start) }
    var endDate: Date? { ISO8601DateFormatter().date(from: end) }
}

struct TeamMe: Codable, Hashable { var name: String; var role: String }

struct TeamBoardData: Codable, Hashable {
    var name: String
    var owner: String
    var members: [String]
    var tasks: [TeamTask]
    var activity: [TeamActivity]
    var version: Int
    var updated: Double
    var secure: Bool?
    var roles: [String: String]?
    var chat: [TeamChatMessage]?
    var events: [TeamEvent]?
    var me: TeamMe?

    var myRole: String { secure == true ? (me?.role ?? "viewer") : "member" }
    var canEdit: Bool { myRole != "viewer" }
    var canManage: Bool { myRole == "owner" || myRole == "admin" }
}

struct TeamBoardRef: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var url: String
    var secure: Bool?
    /// The server the board lives on (scheme + host + port), from its link.
    var host: String {
        guard let u = URL(string: url), let scheme = u.scheme, let h = u.host else { return KeelServer.baseURL?.absoluteString ?? "" }
        return "\(scheme)://\(h)\(u.port.map { ":\($0)" } ?? "")"
    }
}

struct TeamMine: Identifiable, Hashable { let ref: TeamBoardRef; let task: TeamTask; var id: String { ref.id + task.id } }
struct TeamInvite: Identifiable, Hashable { let code: String; let host: String; var id: String { code } }

enum TeamError: LocalizedError {
    case signIn, server(String), http(Int)
    var errorDescription: String? {
        switch self {
        case .signIn: "Sign in with Apple to use private team boards."
        case .server(let m): m
        case .http(let c): "The board's server answered with error \(c)."
        }
    }
}

@MainActor
enum TeamAPI {
    static let key = "team.boards"
    static var boards: [TeamBoardRef] {
        get { LocalLog.load(key) }
        set { LocalLog.save(newValue, key) }
    }
    static var me: String { SharedLists.myName }
    static var ownHost: String? { KeelServer.baseURL.map { u in "\(u.scheme ?? "https")://\(u.host ?? "")\(u.port.map { ":\($0)" } ?? "")" } }

    // Team sign-in per server (Keychain; the key stays on your devices).
    static func tokenKey(_ host: String) -> String { "team.session." + host.replacingOccurrences(of: "https://", with: "") }
    static func token(_ host: String) -> String? { KeychainStore.read(tokenKey(host)).flatMap { $0.isEmpty ? nil : $0 } }
    static func signedIn(_ host: String) -> Bool { token(host) != nil }

    static func request(_ host: String, _ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: host)?.appendingPathComponent(path) else { throw TeamError.http(0) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        if let t = token(host) { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        else if host == ownHost, let code = KeelServer.accessCode, !code.isEmpty { req.setValue("Bearer \(code)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String { throw TeamError.server(msg) }
            throw status == 401 ? TeamError.signIn : TeamError.http(status)
        }
        return data
    }

    /// Exchanges an Apple sign-in for a team key on that server, then turns on instant alerts.
    static func signIn(host: String, identityToken: String, name: String) async throws {
        let data = try await request(host, "team/auth", method: "POST", body: ["identityToken": identityToken, "name": name])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let token = json["token"] as? String else { throw TeamError.http(500) }
        KeychainStore.save(token, for: tokenKey(host))
        await registerPush(host, force: true)
        await restoreBoards(host)
    }

    static func registerPush(_ host: String, force: Bool = false) async {
        guard signedIn(host), let hex = UserDefaults.standard.string(forKey: MailPush.tokenKey) else { return }
        let stampKey = "team.pushed." + host + "." + String(hex.prefix(12))
        if !force, Date().timeIntervalSince1970 - UserDefaults.standard.double(forKey: stampKey) < 12 * 3600 { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: stampKey)
        #if DEBUG
        let sandbox = true
        #else
        let sandbox = false
        #endif
        _ = try? await request(host, "team/push", method: "POST", body: ["token": hex, "sandbox": sandbox])
    }

    /// Your private boards on that server (so a new device finds them).
    static func restoreBoards(_ host: String) async {
        guard let data = try? await request(host, "team/mine"),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        var all = boards
        for b in list {
            guard let id = b["id"] as? String, !all.contains(where: { $0.id == id }) else { continue }
            all.append(TeamBoardRef(id: id, name: b["name"] as? String ?? "Board", url: "\(host)/t/\(id)", secure: true))
        }
        boards = all
    }

    static func create(name: String, secure: Bool) async throws -> TeamBoardRef {
        guard let host = ownHost else { throw TeamError.server("Set up your Keel server first (Settings → Account).") }
        if secure && !signedIn(host) { throw TeamError.signIn }
        let data = try await request(host, "team", method: "POST", body: ["name": name, "by": me, "secure": secure])
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = json?["id"] as? String, let url = json?["url"] as? String else { throw TeamError.http(500) }
        let ref = TeamBoardRef(id: id, name: name, url: url, secure: json?["secure"] as? Bool ?? secure)
        boards = [ref] + boards.filter { $0.id != id }
        return ref
    }

    /// A board link (…/t/<id>) or just the id.
    static func boardId(from text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let r = t.range(of: #"(?<![a-f0-9])[a-f0-9]{32}(?![a-f0-9])"#, options: .regularExpression) else { return nil }
        return String(t[r])
    }

    /// An invitation link (…/join/<code>): its server and code.
    static func invite(from text: String) -> TeamInvite? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: t), let scheme = u.scheme, let h = u.host, u.path.hasPrefix("/join/") else { return nil }
        let code = String(u.path.dropFirst(6))
        guard code.range(of: #"^[a-f0-9]{24}$"#, options: .regularExpression) != nil else { return nil }
        return TeamInvite(code: code, host: "\(scheme)://\(h)\(u.port.map { ":\($0)" } ?? "")")
    }

    static func accept(_ inv: TeamInvite) async throws -> TeamBoardRef {
        guard signedIn(inv.host) else { throw TeamError.signIn }
        let data = try await request(inv.host, "team/join", method: "POST", body: ["code": inv.code])
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = json?["id"] as? String else { throw TeamError.http(500) }
        let name = (json?["board"] as? [String: Any])?["name"] as? String ?? "Board"
        let ref = TeamBoardRef(id: id, name: name, url: "\(inv.host)/t/\(id)", secure: true)
        boards = [ref] + boards.filter { $0.id != id }
        return ref
    }

    /// Joins a link board (no sign-in).
    static func join(link: String) async throws -> TeamBoardRef {
        if let inv = invite(from: link) { return try await accept(inv) }
        guard let id = boardId(from: link) else { throw TeamError.server("That isn't a Keel board link.") }
        let host = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { u in u.host.map { "\(u.scheme ?? "https")://\($0)\(u.port.map { ":\($0)" } ?? "")" } } ?? ownHost ?? ""
        let probe = TeamBoardRef(id: id, name: "Board", url: "\(host)/t/\(id)")
        let board = try await change(probe, ["op": "join"])
        let ref = TeamBoardRef(id: id, name: board.name, url: probe.url, secure: board.secure)
        boards = [ref] + boards.filter { $0.id != id }
        return ref
    }

    static func get(_ ref: TeamBoardRef) async throws -> TeamBoardData {
        try JSONDecoder().decode(TeamBoardData.self, from: try await request(ref.host, "team/\(ref.id)"))
    }

    @discardableResult
    static func change(_ ref: TeamBoardRef, _ op: [String: Any]) async throws -> TeamBoardData {
        var body = op
        body["by"] = me
        return try JSONDecoder().decode(TeamBoardData.self, from: try await request(ref.host, "team/\(ref.id)", method: "POST", body: body))
    }

    static func makeInvite(_ ref: TeamBoardRef, role: String) async throws -> URL {
        let data = try await request(ref.host, "team/\(ref.id)", method: "POST", body: ["op": "invite", "role": role])
        guard let s = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["url"] as? String, let u = URL(string: s) else { throw TeamError.http(500) }
        return u
    }

    static func dueString(_ d: Date?) -> String { d.map { TeamTask.dayFormat.string(from: $0) } ?? "" }

    /// Deletes your team sign-in on every server you used (part of deleting your Keel account).
    static func deleteAccounts() async {
        for host in Set(boards.map(\.host) + [ownHost].compactMap { $0 }) where signedIn(host) {
            _ = try? await request(host, "team/auth", method: "DELETE")
            KeychainStore.delete(tokenKey(host))
        }
    }

    // Catch-up for link boards (private boards push instantly).
    static let seenKey = "team.seen"
    static func checkForNews() async {
        guard !boards.isEmpty, !KeelRuntime.isTesting else { return }
        var seen = (UserDefaults.standard.dictionary(forKey: seenKey) as? [String: Double]) ?? [:]
        for ref in boards {
            if ref.secure == true { await registerPush(ref.host); continue }
            guard let b = try? await get(ref) else { continue }
            let last = seen[ref.id] ?? Date().timeIntervalSince1970 * 1000
            for a in b.activity.filter({ $0.at > last && $0.by != me && ($0.forWhom ?? []).contains(me) }).suffix(5) {
                Kit.notify("team.\(ref.id).\(Int(a.at))", title: "\(a.by) · \(b.name)", body: a.text, at: Date().addingTimeInterval(1))
            }
            seen[ref.id] = b.activity.last?.at ?? last
        }
        UserDefaults.standard.set(seen, forKey: seenKey)
    }
}

// MARK: - Sign in for teams

struct TeamSignInButton: View {
    let host: String
    var done: () -> Void
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SignInWithAppleButton(.signIn) { req in
                req.requestedScopes = [.fullName]
            } onCompletion: { result in
                guard case .success(let auth) = result, let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                      let data = cred.identityToken, let token = String(data: data, encoding: .utf8) else {
                    if case .failure(let e) = result, (e as? ASAuthorizationError)?.code != .canceled { error = e.localizedDescription }
                    return
                }
                let given = [cred.fullName?.givenName, cred.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
                let name = given.isEmpty ? TeamAPI.me : given
                Task {
                    do { try await TeamAPI.signIn(host: host, identityToken: token, name: name); Haptics.success(); done() }
                    catch let e { error = e.localizedDescription }
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 46)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
    }
}

// MARK: - Boards list

struct TeamBoardsView: View {
    @State private var boards: [TeamBoardRef] = []
    @State private var mine: [TeamMine] = []
    @State private var newName = ""
    @State private var link = ""
    @State private var creating = false
    @State private var newSecure = true
    @State private var joining = false
    @State private var error: String?
    @State private var open: TeamBoardRef?
    @State private var needsSignIn: String?

    var body: some View {
        List {
            Section {
                KitIntro(icon: "person.3.fill", color: .indigo, text: "Team boards. Shared task boards for work, a project or the family. Private boards are invitation-only: everyone signs in with Apple and gets a role (owner, admin, member or viewer). Assign tasks, set due dates, chat, keep a team calendar, and get alerts the moment something's assigned to you.")
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            if let host = TeamAPI.ownHost, !TeamAPI.signedIn(host) {
                Section {
                    Text("Sign in once to create private boards and get instant alerts.").font(.callout)
                    TeamSignInButton(host: host) { boards = TeamAPI.boards }
                }
            }
            if !mine.isEmpty {
                Section("Assigned to you") {
                    ForEach(mine) { item in
                        Button { open = item.ref } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.task.title).foregroundStyle(DS.Palette.ink)
                                Text([item.ref.name, item.task.status == "doing" ? "Doing" : "To do", item.task.dueDate.map { "due \($0.formatted(.dateTime.month(.abbreviated).day()))" }]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(DS.Palette.inkSoft)
                            }
                        }
                    }
                }
            }
            Section("Boards") {
                if boards.isEmpty { Text("No boards yet. Create one or join with an invitation.").foregroundStyle(DS.Palette.inkSoft) }
                ForEach(boards) { b in
                    Button { open = b } label: {
                        Label(b.name, systemImage: b.secure == true ? "lock.rectangle.stack" : "rectangle.split.3x1").foregroundStyle(DS.Palette.ink)
                    }
                }
                .onDelete { idx in boards.remove(atOffsets: idx); TeamAPI.boards = boards }
            }
            Section {
                Button("New board", systemImage: "plus.circle.fill") { creating = true }
                Button("Join with an invitation or link", systemImage: "link.badge.plus") { joining = true }
            }
            if let error { Section { Text(error).foregroundStyle(.orange) } }
            if let host = needsSignIn {
                Section("Sign in to continue") { TeamSignInButton(host: host) { needsSignIn = nil; error = nil } }
            }
        }
        .navigationTitle("Team boards")
        .navigationDestination(item: $open) { TeamBoardView(ref: $0) }
        .task {
            if let host = TeamAPI.ownHost, TeamAPI.signedIn(host) { await TeamAPI.restoreBoards(host) }
            boards = TeamAPI.boards
            await loadMine()
        }
        .refreshable { boards = TeamAPI.boards; await loadMine() }
        .sheet(isPresented: $creating) {
            NavigationStack {
                Form {
                    TextField("Name (Launch, Family, Marketing…)", text: $newName)
                    Picker("Who can join", selection: $newSecure) {
                        Text("Invited people only (sign in)").tag(true)
                        Text("Anyone with the link").tag(false)
                    }
                    .pickerStyle(.inline)
                    Text(newSecure ? "Private: people join with an invitation you create, sign in with Apple, and get a role." : "Open: anyone with the link can edit it, in Keel or a browser. No roles.")
                        .font(.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                .navigationTitle("New board")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { creating = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("Create") { create() }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty) }
                }
            }
            .presentationDetents([.medium])
        }
        .alert("Join a board", isPresented: $joining) {
            TextField("Paste the invitation or board link", text: $link)
            Button("Join") {
                let l = link; link = ""
                Task {
                    do { let r = try await TeamAPI.join(link: l); boards = TeamAPI.boards; open = r; error = nil }
                    catch TeamError.signIn { needsSignIn = TeamAPI.invite(from: l)?.host; error = "Sign in with Apple below, then join again." }
                    catch let e { error = e.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func create() {
        let n = newName.trimmingCharacters(in: .whitespaces); newName = ""; creating = false
        Task {
            do { let r = try await TeamAPI.create(name: n, secure: newSecure); boards = TeamAPI.boards; open = r; error = nil }
            catch TeamError.signIn { needsSignIn = TeamAPI.ownHost; error = "Sign in with Apple to create a private board." }
            catch let e { error = e.localizedDescription }
        }
    }

    private func loadMine() async {
        var out: [TeamMine] = []
        // All boards at once rather than one after another.
        let refs = TeamAPI.boards
        let fetched: [(TeamBoardRef, TeamBoardData?)] = await withTaskGroup(of: (TeamBoardRef, TeamBoardData?).self) { group in
            for ref in refs { group.addTask { (ref, try? await TeamAPI.get(ref)) } }
            var all: [(TeamBoardRef, TeamBoardData?)] = []
            for await r in group { all.append(r) }
            return all
        }
        for (ref, board) in fetched {
            guard let b = board else { continue }
            let myName = b.me?.name ?? TeamAPI.me
            out += b.tasks.filter { $0.assignee == myName && $0.status != "done" }.map { TeamMine(ref: ref, task: $0) }
        }
        mine = out.sorted { ($0.task.dueDate ?? .distantFuture) < ($1.task.dueDate ?? .distantFuture) }
    }
}

/// Opened from an invitation link: sign in if needed, then join.
struct TeamJoinView: View {
    let invite: TeamInvite
    @Environment(\.dismiss) private var dismiss
    @State private var joined: TeamBoardRef?
    @State private var error: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Group {
                if let joined {
                    TeamBoardView(ref: joined)
                } else {
                    List {
                        Section { KitIntro(icon: "envelope.open.fill", color: .indigo, text: "You've been invited to a Keel team board. Sign in with Apple so your teammates know it's you, then join.") }
                            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                        if !TeamAPI.signedIn(invite.host) {
                            Section { TeamSignInButton(host: invite.host) { accept() } }
                        } else {
                            Section { Button(working ? "Joining…" : "Join the board", systemImage: "person.badge.plus") { accept() }.disabled(working) }
                        }
                        if let error { Section { Text(error).foregroundStyle(.orange) } }
                    }
                    .navigationTitle("Invitation")
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func accept() {
        working = true
        Task {
            do { joined = try await TeamAPI.accept(invite); Haptics.success() } catch let e { error = e.localizedDescription }
            working = false
        }
    }
}

// MARK: - One board

struct TeamBoardView: View {
    let ref: TeamBoardRef
    @Environment(\.dismiss) private var dismiss
    @State private var board: TeamBoardData?
    @State private var page = 0                // 0 board, 1 mine, 2 chat, 3 calendar, 4 activity
    @State private var newTitle = ""
    @State private var newAssignee = ""
    @State private var newDue: Date?
    @State private var openTask: TeamTask?
    @State private var error: String?
    @State private var showMembers = false

    var body: some View {
        List {
            Picker("", selection: $page) {
                Text("Board").tag(0); Text("Mine").tag(1); Text("Chat").tag(2); Text("Calendar").tag(3); Text("Activity").tag(4)
            }
            .pickerStyle(.segmented).listRowBackground(Color.clear)
            if let error { Text(error).foregroundStyle(.orange).font(.caption) }
            if let b = board {
                switch page {
                case 2: TeamChatSection(board: b) { change(["op": "chat", "text": $0]) }
                case 3: TeamCalendarSection(board: b) { change($0) }
                case 4: activity(b)
                default: tasks(b)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(board?.name ?? ref.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showMembers = true } label: { Image(systemName: "person.2.circle") }.accessibilityLabel("Members and invitations")
            }
        }
        .sheet(isPresented: $showMembers) {
            if let b = board { TeamMembersSheet(ref: ref, board: b, updated: { board = $0 }, left: { dismiss() }) }
        }
        .sheet(item: $openTask) { t in
            if let b = board { TeamTaskSheet(ref: ref, task: t, members: b.members, canEdit: b.canEdit, myName: b.me?.name ?? TeamAPI.me) { board = $0 } }
        }
        .task {
            while !Task.isCancelled {
                do {
                    let fresh = try await TeamAPI.get(ref)
                    if fresh.version != board?.version || fresh.me != board?.me { board = fresh }   // unchanged: don't redraw
                    error = nil
                } catch let e { if board == nil { self.error = e.localizedDescription } }
                try? await Task.sleep(for: .seconds(8))
            }
        }
        .refreshable { board = try? await TeamAPI.get(ref) }
    }

    @ViewBuilder private func tasks(_ b: TeamBoardData) -> some View {
        let myName = b.me?.name ?? TeamAPI.me
        if b.canEdit {
            Section {
                HStack {
                    TextField("New task", text: $newTitle).onSubmit { add() }
                    Menu {
                        Button("Anyone") { newAssignee = "" }
                        ForEach(b.members, id: \.self) { m in Button(m == myName ? "Me" : m) { newAssignee = m } }
                    } label: { Image(systemName: newAssignee.isEmpty ? "person.crop.circle" : "person.crop.circle.fill") }
                    Menu {
                        Button("No date") { newDue = nil }
                        Button("Today") { newDue = Date() }
                        Button("Tomorrow") { newDue = Calendar.current.date(byAdding: .day, value: 1, to: Date()) }
                        Button("In a week") { newDue = Calendar.current.date(byAdding: .day, value: 7, to: Date()) }
                    } label: { Image(systemName: newDue == nil ? "calendar" : "calendar.badge.checkmark") }
                    Button("Add") { add() }.disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !newAssignee.isEmpty || newDue != nil {
                    Text([newAssignee.isEmpty ? nil : "For \(newAssignee)", newDue.map { "due \($0.formatted(.dateTime.month(.abbreviated).day()))" }].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(DS.Palette.inkSoft)
                }
            }
        } else {
            Text("You're a viewer on this board: you can read, comment and chat.").font(.caption).foregroundStyle(DS.Palette.inkSoft)
        }
        ForEach(["todo", "doing", "done"], id: \.self) { status in
            let title = status == "todo" ? "To do" : status == "doing" ? "Doing" : "Done"
            let list = b.tasks.filter { $0.status == status && (page == 0 || $0.assignee == myName) }
                .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            Section("\(title) · \(list.count)") {
                ForEach(list) { t in
                    Button { openTask = t } label: { TeamTaskRow(task: t, myName: myName) }
                        .swipeActions(edge: .leading) {
                            if b.canEdit, status != "done" { Button { set(t, ["status": "done"]) } label: { Label("Done", systemImage: "checkmark") }.tint(DS.Palette.calm) }
                            if b.canEdit, status == "todo" { Button { set(t, ["status": "doing"]) } label: { Label("Start", systemImage: "play") }.tint(.blue) }
                        }
                        .swipeActions(edge: .trailing) {
                            if b.canManage || t.createdBy == myName { Button(role: .destructive) { change(["op": "remove", "id": t.id]) } label: { Label("Delete", systemImage: "trash") } }
                            if b.canEdit, t.assignee != myName { Button { set(t, ["assignee": myName]) } label: { Label("Take it", systemImage: "hand.raised") }.tint(.indigo) }
                        }
                }
            }
        }
    }

    @ViewBuilder private func activity(_ b: TeamBoardData) -> some View {
        Section {
            ForEach(Array(b.activity.reversed().prefix(100).enumerated()), id: \.offset) { _, a in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(a.by) \(a.text)").font(.callout)
                    Text(Date(timeIntervalSince1970: a.at / 1000).formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                }
            }
        }
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
            do { board = try await TeamAPI.change(ref, op); error = nil }
            catch let e { self.error = e.localizedDescription }
        }
    }
}

struct TeamTaskRow: View {
    let task: TeamTask
    var myName: String = TeamAPI.me
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: task.status == "done" ? "checkmark.circle.fill" : task.status == "doing" ? "circle.lefthalf.filled" : "circle")
                .foregroundStyle(task.status == "done" ? DS.Palette.calm : task.status == "doing" ? .blue : DS.Palette.inkSoft)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).foregroundStyle(DS.Palette.ink).strikethrough(task.status == "done")
                HStack(spacing: 6) {
                    Text(task.assignee.isEmpty ? "Anyone" : task.assignee == myName ? "You" : task.assignee)
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

// MARK: - Chat

struct TeamChatSection: View {
    let board: TeamBoardData
    var send: (String) -> Void
    @State private var text = ""

    var body: some View {
        let me = board.me?.name ?? TeamAPI.me
        Section {
            let msgs = Array((board.chat ?? []).suffix(150))
            if msgs.isEmpty { Text("No messages yet. Say hello.").foregroundStyle(DS.Palette.inkSoft) }
            ForEach(msgs) { m in
                HStack {
                    if m.by == me { Spacer(minLength: 40) }
                    VStack(alignment: m.by == me ? .trailing : .leading, spacing: 2) {
                        if m.by != me { Text(m.by).font(.caption2.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft) }
                        Text(m.text)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(m.by == me ? AnyShapeStyle(DS.Palette.accent) : AnyShapeStyle(DS.Palette.elevated), in: .rect(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(m.by == me ? Color.white : DS.Palette.ink)
                        Text(Date(timeIntervalSince1970: m.at / 1000).formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                    }
                    if m.by != me { Spacer(minLength: 40) }
                }
                .listRowSeparator(.hidden)
            }
        }
        Section {
            HStack {
                TextField("Message the team (@Name to mention)", text: $text, axis: .vertical)
                Button { let t = text.trimmingCharacters(in: .whitespaces); text = ""; if !t.isEmpty { send(t); Haptics.tap() } } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

// MARK: - Team calendar: shared events plus task due dates

struct TeamCalendarSection: View {
    let board: TeamBoardData
    var change: ([String: Any]) -> Void
    @State private var adding = false
    @State private var title = ""
    @State private var start = Calendar.current.date(bySetting: .minute, value: 0, of: Date().addingTimeInterval(3600)) ?? Date()
    @State private var minutes = 60
    @State private var added: String?

    private struct Entry: Identifiable { let id: String; let date: Date; let title: String; let detail: String; let event: TeamEvent? }

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var entries: [Entry] = (board.events ?? []).compactMap { e in
            e.startDate.map { Entry(id: "e" + e.id, date: $0, title: e.title, detail: "\($0.formatted(date: .omitted, time: .shortened)) · added by \(e.by)", event: e) }
        }
        entries += board.tasks.filter { $0.status != "done" }.compactMap { t in
            t.dueDate.map { Entry(id: "t" + t.id, date: $0, title: t.title, detail: "Task due" + (t.assignee.isEmpty ? "" : " · \(t.assignee)"), event: nil) }
        }
        let upcoming = entries.filter { $0.date >= today }.sorted { $0.date < $1.date }
        let days = Dictionary(grouping: upcoming) { cal.startOfDay(for: $0.date) }
        return Group {
            if board.canEdit {
                Section { Button("Add a team event", systemImage: "calendar.badge.plus") { adding = true } }
            }
            if let added { Section { Label(added, systemImage: "checkmark.circle").foregroundStyle(DS.Palette.calm) } }
            if upcoming.isEmpty { Section { Text("Nothing coming up. Team events and task due dates show here.").foregroundStyle(DS.Palette.inkSoft) } }
            ForEach(days.keys.sorted(), id: \.self) { day in
                Section(day.formatted(.dateTime.weekday(.wide).month().day())) {
                    ForEach(days[day] ?? []) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(e.title, systemImage: e.event == nil ? "checklist" : "calendar")
                            Text(e.detail).font(.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        .swipeActions {
                            if let ev = e.event {
                                Button { addToMyCalendar(ev) } label: { Label("My calendar", systemImage: "calendar.badge.plus") }.tint(.blue)
                                if board.canEdit { Button(role: .destructive) { change(["op": "event_remove", "id": ev.id]) } label: { Label("Remove", systemImage: "trash") } }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $adding) {
            NavigationStack {
                Form {
                    TextField("What", text: $title)
                    DatePicker("Starts", selection: $start)
                    Stepper("\(Kit.minutes(minutes))", value: $minutes, in: 15...600, step: 15)
                }
                .navigationTitle("Team event")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { adding = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            change(["op": "event_add", "title": title, "start": start.ISO8601Format(), "end": start.addingTimeInterval(Double(minutes * 60)).ISO8601Format()])
                            title = ""; adding = false
                        }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func addToMyCalendar(_ e: TeamEvent) {
        Task {
            if !CalendarService.shared.hasCalendarAccess { await CalendarService.shared.requestAccess() }
            guard let s = e.startDate else { return }
            let store = CalendarService.shared.store
            let ev = EKEvent(eventStore: store)
            ev.title = e.title
            ev.startDate = s
            ev.endDate = e.endDate ?? s.addingTimeInterval(3600)
            ev.notes = "From the \(board.name) team board in Keel."
            ev.calendar = store.defaultCalendarForNewEvents
            if (try? store.save(ev, span: .thisEvent)) != nil { CalendarService.shared.invalidateEvents(); added = "Added “\(e.title)” to your calendar."; Haptics.success() }
        }
    }
}

// MARK: - Members, roles and invitations

struct TeamMembersSheet: View {
    let ref: TeamBoardRef
    let board: TeamBoardData
    var updated: (TeamBoardData) -> Void
    var left: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var inviteRole = "member"
    @State private var inviteURL: URL?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Members (\(board.members.count))") {
                    ForEach(board.members, id: \.self) { m in
                        let role = board.roles?[m] ?? (m == board.owner ? "owner" : "member")
                        HStack {
                            Text(m == board.me?.name ? "\(m) (you)" : m)
                            Spacer()
                            if board.secure == true, board.canManage, role != "owner", m != board.me?.name {
                                Menu(role.capitalized) {
                                    if board.myRole == "owner" { Button("Admin") { op(["op": "set_role", "name": m, "role": "admin"]) } }
                                    Button("Member") { op(["op": "set_role", "name": m, "role": "member"]) }
                                    Button("Viewer") { op(["op": "set_role", "name": m, "role": "viewer"]) }
                                    Divider()
                                    Button("Remove from board", role: .destructive) { op(["op": "remove_member", "name": m]) }
                                }
                            } else {
                                Text(board.secure == true ? role.capitalized : "").foregroundStyle(DS.Palette.inkSoft)
                            }
                        }
                    }
                }
                if board.secure == true {
                    if board.canManage {
                        Section {
                            Picker("Join as", selection: $inviteRole) {
                                if board.myRole == "owner" { Text("Admin").tag("admin") }
                                Text("Member").tag("member")
                                Text("Viewer").tag("viewer")
                            }
                            Button("Create invitation", systemImage: "envelope.badge") {
                                Task {
                                    do { inviteURL = try await TeamAPI.makeInvite(ref, role: inviteRole); error = nil }
                                    catch let e { error = e.localizedDescription }
                                }
                            }
                            if let inviteURL {
                                ShareLink(item: inviteURL, message: Text("Join our \"\(board.name)\" board in Keel:")) { Label("Share invitation", systemImage: "square.and.arrow.up") }
                                Button("Send by text", systemImage: "message") {
                                    AppleMessages.compose(TextDraft(body: "Join our \"\(board.name)\" board in Keel: \(inviteURL.absoluteString)"))
                                }
                            }
                        } header: { Text("Invite") } footer: {
                            Text("An invitation works for up to 10 people for 7 days. Admins can invite and manage members; members add and edit tasks; viewers can read, comment and chat.")
                        }
                    }
                } else {
                    Section {
                        ShareLink(item: URL(string: ref.url) ?? URL(fileURLWithPath: "/"), message: Text("Join our board in Keel (or open it in a browser):")) {
                            Label("Share the board link", systemImage: "person.badge.plus")
                        }
                    } footer: { Text("This is a link board: anyone with the link can open and edit it, in Keel or a web browser.") }
                }
                if let error { Section { Text(error).foregroundStyle(.orange) } }
                Section {
                    if board.myRole == "owner" {
                        Button("Delete board for everyone", systemImage: "trash", role: .destructive) {
                            Task {
                                do { _ = try await TeamAPI.request(ref.host, "team/\(ref.id)", method: "POST", body: ["op": "delete", "by": TeamAPI.me]) } catch {}
                                TeamAPI.boards = TeamAPI.boards.filter { $0.id != ref.id }; dismiss(); left()
                            }
                        }
                    } else {
                        Button("Leave board", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            Task {
                                _ = try? await TeamAPI.change(ref, ["op": "leave"])
                                TeamAPI.boards = TeamAPI.boards.filter { $0.id != ref.id }; dismiss(); left()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func op(_ o: [String: Any]) {
        Task {
            do { updated(try await TeamAPI.change(ref, o)); error = nil } catch let e { error = e.localizedDescription }
        }
    }
}

// MARK: - A task

struct TeamTaskSheet: View {
    let ref: TeamBoardRef
    @State var task: TeamTask
    let members: [String]
    var canEdit = true
    var myName: String = TeamAPI.me
    var updated: (TeamBoardData) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @State private var comment = ""
    @State private var hasDue = false
    @State private var due = Date()
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $task.title).disabled(!canEdit)
                    TextField("Notes", text: $task.notes, axis: .vertical).lineLimit(2...8).disabled(!canEdit)
                }
                Section {
                    Picker("Status", selection: $task.status) { Text("To do").tag("todo"); Text("Doing").tag("doing"); Text("Done").tag("done") }
                    Picker("Assigned to", selection: $task.assignee) {
                        Text("Anyone").tag("")
                        ForEach(members, id: \.self) { Text($0 == myName ? "Me" : $0).tag($0) }
                    }
                    Toggle("Due date", isOn: $hasDue)
                    if hasDue { DatePicker("Due", selection: $due, displayedComponents: .date) }
                }
                .disabled(!canEdit)
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
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(members.filter { $0 != myName }, id: \.self) { m in
                                let first = m.split(separator: " ").first.map(String.init) ?? m
                                Button("@\(first)") { comment += (comment.isEmpty || comment.hasSuffix(" ") ? "" : " ") + "@\(first) " }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
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
                if let error { Section { Text(error).foregroundStyle(.orange) } }
            }
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if canEdit { ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } } }
            }
            .onAppear { if let d = task.dueDate { hasDue = true; due = d } }
        }
    }

    private func send() {
        let text = comment.trimmingCharacters(in: .whitespaces)
        comment = ""
        Task {
            do {
                let b = try await TeamAPI.change(ref, ["op": "comment", "id": task.id, "text": text])
                updated(b)
                if let t = b.tasks.first(where: { $0.id == task.id }) { task.comments = t.comments }
                Haptics.tap()
            } catch let e { error = e.localizedDescription }
        }
    }

    private func save() {
        let fields: [String: Any] = ["op": "update", "id": task.id, "title": task.title, "notes": task.notes, "status": task.status,
                                     "assignee": task.assignee, "due": hasDue ? TeamAPI.dueString(due) : ""]
        Task {
            do { updated(try await TeamAPI.change(ref, fields)); dismiss() } catch let e { error = e.localizedDescription }
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
                            do {
                                _ = try await TeamAPI.change(b, ["op": "add", "title": task.title, "notes": task.notes, "due": TeamAPI.dueString(task.dueDate)])
                                UndoCenter.shared.notify("Added to \(b.name)")
                            } catch let e { UndoCenter.shared.notify(e.localizedDescription) }
                        }
                    }
                }
            } label: { Label("Send to a team board", systemImage: "person.3") }
            .foregroundStyle(DS.Palette.ink)
        }
    }
}
