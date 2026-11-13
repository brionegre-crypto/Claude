import SwiftUI
import SwiftData

/// Calls to your own Keel server for sharing, publishing and crash reports.
@MainActor
enum KeelCloud {
    enum Failure: LocalizedError {
        case noServer, http(Int)
        var errorDescription: String? {
            switch self {
            case .noServer: "Sign in to Keel (Settings → Account) to share. Sharing uses your Keel server."
            case .http(let c): "The Keel server answered with error \(c)."
            }
        }
    }

    static func call(_ path: String, method: String = "GET", body: Any? = nil, auth: Bool = false) async throws -> Data {
        guard let base = KeelServer.baseURL else { throw Failure.noServer }
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 20
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        if auth {
            guard let code = KeelServer.accessCode, !code.isEmpty else { throw Failure.noServer }
            req.setValue("Bearer \(code)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Failure.http(status) }
        return data
    }
}

// MARK: - Shared lists (anyone with the link, in Keel or a browser)

struct SharedListItem: Codable, Identifiable, Hashable {
    var id: String
    var text: String
    var done: Bool
    var by: String?
}

struct SharedListData: Codable {
    struct Comment: Codable, Hashable { var text: String; var by: String; var at: Double }
    var title: String
    var items: [SharedListItem]
    var comments: [Comment]
}

struct SharedListRef: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var url: String
}

@MainActor
enum SharedLists {
    static let key = "shared.lists"
    static var all: [SharedListRef] {
        get { (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode([SharedListRef].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }
    static var myName: String {
        let n = KeelAccount.shared.name
        return n.isEmpty ? UIDevice.current.name : n
    }

    /// Shares a Keel task list (or starts an empty one) and returns the link.
    static func create(title: String, items: [String]) async throws -> SharedListRef {
        let body: [String: Any] = ["title": title, "items": items.map { ["id": UUID().uuidString.prefix(12).lowercased(), "text": $0, "done": false] }]
        let data = try await KeelCloud.call("share/list", method: "POST", body: body, auth: true)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = json?["id"] as? String, let url = json?["url"] as? String else { throw KeelCloud.Failure.http(500) }
        let ref = SharedListRef(id: id, title: title, url: url)
        all = [ref] + all.filter { $0.id != id }
        return ref
    }

    /// Adds a list someone shared with you, from its link.
    static func join(link: String) -> SharedListRef? {
        guard let id = link.split(separator: "/").last.map(String.init), id.count == 32, id.allSatisfy(\.isHexDigit) else { return nil }
        let ref = SharedListRef(id: id, title: "Shared list", url: link)
        all = [ref] + all.filter { $0.id != id }
        return ref
    }

    static func load(_ id: String) async throws -> SharedListData {
        try JSONDecoder().decode(SharedListData.self, from: try await KeelCloud.call("share/list/\(id)"))
    }

    static func send(_ id: String, _ op: [String: Any]) async throws -> SharedListData {
        var body = op
        body["by"] = myName
        return try JSONDecoder().decode(SharedListData.self, from: try await KeelCloud.call("share/list/\(id)", method: "POST", body: body))
    }
}

/// Tasks → Shared lists: lists you share by link with anyone (no Apple device needed).
struct SharedListsView: View {
    @State private var lists = SharedLists.all
    @State private var newTitle = ""
    @State private var joinLink = ""
    @State private var creating = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                ForEach(lists) { l in
                    NavigationLink { SharedListView(ref: l) } label: { Label(l.title, systemImage: "person.2.fill") }
                }
                .onDelete { idx in lists.remove(atOffsets: idx); SharedLists.all = lists }
                HStack {
                    TextField("New shared list, e.g. Groceries", text: $newTitle)
                    Button(creating ? "…" : "Create") {
                        Task {
                            creating = true; defer { creating = false }
                            do { _ = try await SharedLists.create(title: newTitle, items: []); newTitle = ""; lists = SharedLists.all }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty || creating)
                }
            } footer: {
                Text("Anyone with the link can check off and add items, in Keel or in any web browser. For lists shared with other Apple users, you can also share the list in Apple Reminders.")
            }
            Section("Join a list") {
                HStack {
                    TextField("Paste a shared-list link", text: $joinLink).textInputAutocapitalization(.never)
                    Button("Add") {
                        if SharedLists.join(link: joinLink) != nil { joinLink = ""; lists = SharedLists.all } else { error = "That doesn't look like a Keel list link." }
                    }
                }
            }
            if let error { Text(error).font(DS.Font.caption).foregroundStyle(.red) }
        }
        .navigationTitle("Shared lists")
    }
}

struct SharedListView: View {
    let ref: SharedListRef
    @State private var data: SharedListData?
    @State private var newItem = ""
    @State private var comment = ""
    @State private var error: String?
    private let tick = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            if let d = data {
                Section {
                    ForEach(d.items) { i in
                        Button {
                            Task { await run(["op": "toggle", "id": i.id]); Haptics.tap() }
                        } label: {
                            HStack {
                                Image(systemName: i.done ? "checkmark.circle.fill" : "circle").foregroundStyle(i.done ? DS.Palette.calm : DS.Palette.inkSoft)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(i.text).strikethrough(i.done).foregroundStyle(i.done ? DS.Palette.inkSoft : DS.Palette.ink)
                                    if let by = i.by { Text("added by \(by)").font(.caption2).foregroundStyle(DS.Palette.inkSoft) }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions { Button("Remove", role: .destructive) { Task { await run(["op": "remove", "id": i.id]) } } }
                    }
                    HStack {
                        TextField("Add an item", text: $newItem).onSubmit(addItem)
                        Button("Add", action: addItem).disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section("Comments") {
                    ForEach(Array(d.comments.enumerated()), id: \.offset) { _, c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.text)
                            Text("\(c.by) · \(Date(timeIntervalSince1970: c.at / 1000).formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                    HStack {
                        TextField("Write a comment", text: $comment)
                        Button("Send") { let t = comment; comment = ""; Task { await run(["op": "comment", "text": t]) } }.disabled(comment.isEmpty)
                    }
                }
            } else if let error {
                Text(error).foregroundStyle(.red)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(data?.title ?? ref.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let url = URL(string: ref.url) { ShareLink(item: url) { Image(systemName: "square.and.arrow.up") } }
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
        .onReceive(tick) { _ in Task { await refresh() } }
    }

    private func addItem() {
        let t = newItem.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        newItem = ""
        Task { await run(["op": "add", "text": t]) }
    }

    private func refresh() async {
        do {
            let d = try await SharedLists.load(ref.id)
            data = d
            if d.title != ref.title { SharedLists.all = SharedLists.all.map { $0.id == ref.id ? SharedListRef(id: $0.id, title: d.title, url: $0.url) : $0 } }
        } catch { self.error = error.localizedDescription }
    }

    private func run(_ op: [String: Any]) async {
        do { data = try await SharedLists.send(ref.id, op) } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Publish a page as a link

@MainActor
enum NotePublisher {
    static let idKey = "publishedId"

    static func publish(_ n: Note) async throws -> URL {
        var body: [String: Any] = ["title": n.title.isEmpty ? "Untitled" : n.title, "html": html(n)]
        if let id = n.props[idKey] { body["id"] = id }
        let data = try await KeelCloud.call("publish", method: "POST", body: body, auth: true)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = json?["id"] as? String, let s = json?["url"] as? String, let url = URL(string: s) else { throw KeelCloud.Failure.http(500) }
        n.props[idKey] = id
        return url
    }

    static func unpublish(_ n: Note) async throws {
        guard let id = n.props[idKey] else { return }
        _ = try await KeelCloud.call("publish/\(id)", method: "DELETE", auth: true)
        n.props[idKey] = nil
    }

    static func url(_ n: Note) -> URL? {
        guard let id = n.props[idKey], let base = KeelServer.baseURL else { return nil }
        return base.appendingPathComponent("p/\(id)")
    }

    /// The page's blocks as simple HTML (headings, lists, checkboxes, quotes, code, tables).
    static func html(_ n: Note) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        func inline(_ s: String) -> String {
            var t = esc(RichText.plain(s))
            t = t.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
            return t
        }
        var out = ""
        for b in n.blocks {
            switch b.kind {
            case .heading: out += "<h2>\(inline(b.text))</h2>"
            case .heading2: out += "<h3>\(inline(b.text))</h3>"
            case .heading3: out += "<h4>\(inline(b.text))</h4>"
            case .bullet: out += "<ul><li>\(inline(b.text))</li></ul>"
            case .numbered: out += "<ol><li>\(inline(b.text))</li></ol>"
            case .todo: out += "<p>\(b.checked ? "☑" : "☐") \(inline(b.text))</p>"
            case .quote: out += "<blockquote>\(inline(b.text))</blockquote>"
            case .code: out += "<pre><code>\(esc(b.text))</code></pre>"
            case .divider: out += "<hr>"
            case .callout: out += "<blockquote>\(b.icon ?? "💡") \(inline(b.text))</blockquote>"
            case .toggle: out += "<details><summary>\(inline(b.text))</summary><p>\(inline(b.body ?? ""))</p></details>"
            case .table:
                let rows = b.rows ?? []
                out += "<table>" + rows.map { "<tr>" + $0.map { "<td>\(inline($0))</td>" }.joined() + "</tr>" }.joined() + "</table>"
            default:
                if !b.text.isEmpty { out += "<p>\(inline(b.text))</p>" }
            }
        }
        return out
    }
}
