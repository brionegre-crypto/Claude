import Foundation

/// Imports straight from a workspace with an integration token: every page and database shared with
/// the integration, with their blocks, properties, icons and images. Nothing to export or unzip.
/// The token is kept in the Keychain on this iPhone and only ever sent to api.notion.com.
/// Spaces requests to about three a second across everything in flight (the workspace API's limit).
actor NotionPacer {
    private var next = Date.distantPast
    func wait() async {
        let now = Date()
        let at = max(now, next)
        next = at.addingTimeInterval(0.34)
        let delay = at.timeIntervalSince(now)
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
    }
}

struct NotionConnector: Sendable {
    let token: String
    let pacer = NotionPacer()
    static let keychainKey = "import.notion.token"
    private let base = URL(string: "https://api.notion.com/v1")!

    enum Failure: LocalizedError {
        case unauthorized, http(Int, String), nothingShared
        var errorDescription: String? {
            switch self {
            case .unauthorized: "That token didn't work. Check you copied the whole “Internal Integration Secret”."
            case .http(let c, let m): "The workspace said \(c): \(m)"
            case .nothingShared: "Connected, but nothing is shared with the integration yet. Share pages with it (••• → Connections), then try again."
            }
        }
    }

    // MARK: Requests (gentle: about 3 a second, as the API asks)

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil, attempt: Int = 0) async throws -> [String: Any] {
        var r = URLRequest(url: URL(string: base.absoluteString + path)!)
        r.httpMethod = method
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.timeoutInterval = 30
        if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body) }
        await pacer.wait()
        let (data, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 429 || code >= 500, attempt < 4 {
            let wait = Double((resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? Double(1 << attempt)
            try await Task.sleep(for: .seconds(wait))
            return try await request(path, method: method, body: body, attempt: attempt + 1)
        }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if code == 401 { throw Failure.unauthorized }
        guard (200..<300).contains(code) else { throw Failure.http(code, json["message"] as? String ?? "Unknown error") }
        return json
    }

    /// Quick check for the connect screen: who is this, and is anything shared?
    func verify() async throws -> String {
        let me = try await request("/users/me")
        let bot = me["bot"] as? [String: Any]
        let workspace = bot?["workspace_name"] as? String
        return workspace ?? (me["name"] as? String) ?? "your workspace"
    }

    // MARK: Import

    /// Reads the whole workspace (everything the sign-in shared): several pages at a time within the rate
    /// limit, saving each to disk as it goes so a large workspace can resume where it stopped.
    func fetchAll(progress: @escaping @Sendable (String, Double) async -> Void) async throws -> ImportBundle {
        // 1. Everything shared: pages, database rows and databases.
        var objects: [[String: Any]] = []
        var cursor: String?
        repeat {
            var body: [String: Any] = ["page_size": 100]
            if let cursor { body["start_cursor"] = cursor }
            let r = try await request("/search", method: "POST", body: body)
            objects += (r["results"] as? [[String: Any]]) ?? []
            cursor = (r["has_more"] as? Bool == true) ? r["next_cursor"] as? String : nil
            await progress("Found \(objects.count) pages and databases…", 0.03)
        } while cursor != nil && objects.count < 50_000
        objects.removeAll { $0["archived"] as? Bool == true || $0["in_trash"] as? Bool == true }
        guard !objects.isEmpty else { throw Failure.nothingShared }

        let dbSchemas = Dictionary(objects.filter { $0["object"] as? String == "database" }.compactMap { o -> (String, [DBProperty])? in
            guard let id = o["id"] as? String else { return nil }
            return (id, schema(o))
        }, uniquingKeysWith: { a, _ in a })

        // 2. Each page's content, four at a time (the pacer keeps the overall rate polite).
        var pages: [ImportedPage] = []
        var warnings = Set<String>()
        let total = objects.count
        let started = Date()
        var finished = 0, reused = 0
        var nextIndex = 0
        try await withThrowingTaskGroup(of: (ImportedPage?, Set<String>, Bool).self) { group in
            while nextIndex < min(4, total) {
                let o = objects[nextIndex]; nextIndex += 1
                group.addTask { try await self.readPage(o, schemas: dbSchemas) }
            }
            while let r = try await group.next() {
                if let p = r.0 { pages.append(p) }
                warnings.formUnion(r.1)
                if r.2 { reused += 1 }
                finished += 1
                if nextIndex < total {
                    let o = objects[nextIndex]; nextIndex += 1
                    group.addTask { try await self.readPage(o, schemas: dbSchemas) }
                }
                let fetchedNew = max(1, finished - reused)
                let perPage = Date().timeIntervalSince(started) / Double(fetchedNew)
                let left = Double(total - finished) * perPage
                let eta = left < 60 ? "less than a minute left" : "about \(Int(left / 60) + 1) min left"
                await progress("\(finished) of \(total) pages · \(eta)\(reused > 0 ? " · \(reused) already saved" : "")",
                               0.03 + 0.95 * Double(finished) / Double(total))
            }
        }
        return ImportBundle(source: .notionAPI, name: "Workspace", pages: pages, warnings: Array(warnings).sorted())
    }

    /// One page or database. Reuses the saved copy if it hasn't changed since. Returns (page, warnings, reused).
    private func readPage(_ o: [String: Any], schemas: [String: [DBProperty]]) async throws -> (ImportedPage?, Set<String>, Bool) {
        try Task.checkCancellation()
        guard let id = o["id"] as? String else { return (nil, [], false) }
        let edited = o["last_edited_time"] as? String ?? ""
        if let cached = NotionCache.load(id, edited: edited) { return (cached, [], true) }

        let isDB = o["object"] as? String == "database"
        var warnings = Set<String>()
        var page = ImportedPage(key: id, title: isDB ? plain(o["title"]) : pageTitle(o))
        if page.title.isEmpty { page.title = "Untitled" }
        page.icon = icon(o["icon"]) ?? (isDB ? "🗃️" : nil)
        page.created = date(o["created_time"])
        page.updated = date(o["last_edited_time"])
        page.parentKey = parentId(o["parent"])
        if isDB {
            page.isDatabase = true
            page.schema = schemas[id] ?? []
        } else {
            if let dbId = (o["parent"] as? [String: Any])?["database_id"] as? String {
                page.props = props(o["properties"], schema: schemas[dbId] ?? [])
            }
            var images: [UUID: String] = [:]
            page.blocks = try await blocks(of: id, depth: 0, images: &images, warnings: &warnings)
            page.imagePaths = images
        }
        if let cover = o["cover"] as? [String: Any], let url = fileURL(cover), let saved = await saveImage(url) {
            page.coverPath = saved                     // the page's cover, just like the original
        }
        NotionCache.save(page, id: id, edited: edited)
        return (page, warnings, false)
    }

    // MARK: Blocks

    private func children(_ id: String) async throws -> [[String: Any]] {
        var out: [[String: Any]] = []
        var cursor: String?
        repeat {
            let r = try await request("/blocks/\(id)/children?page_size=100" + (cursor.map { "&start_cursor=\($0)" } ?? ""))
            out += (r["results"] as? [[String: Any]]) ?? []
            cursor = (r["has_more"] as? Bool == true) ? r["next_cursor"] as? String : nil
        } while cursor != nil
        return out
    }

    /// Blocks keep their nesting (`indent`), colours, line breaks and empty spacing lines, so the page
    /// looks the way it did. Toggles keep their contents as real blocks inside them.
    private func blocks(of id: String, depth: Int, images: inout [UUID: String], warnings: inout Set<String>) async throws -> [NoteBlock] {
        var out: [NoteBlock] = []
        for b in try await children(id) {
            guard let type = b["type"] as? String, let v = b[type] as? [String: Any] else { continue }
            let text = rich(v["rich_text"])
            let hasKids = b["has_children"] as? Bool == true
            let bid = b["id"] as? String ?? ""
            var made: NoteBlock?
            var childDepth = depth + 1                 // where this block's children go
            switch type {
            case "paragraph": made = NoteBlock(kind: .text, text: text)          // empty ones are spacing: keep them
            case "heading_1": made = NoteBlock(kind: .heading, text: text)
            case "heading_2": made = NoteBlock(kind: .heading2, text: text)
            case "heading_3": made = NoteBlock(kind: .heading3, text: text)
            case "bulleted_list_item": made = NoteBlock(kind: .bullet, text: text)
            case "numbered_list_item": made = NoteBlock(kind: .numbered, text: text)
            case "to_do": made = NoteBlock(kind: .todo, text: text, checked: v["checked"] as? Bool ?? false)
            case "quote": made = NoteBlock(kind: .quote, text: text)
            case "divider": made = NoteBlock(kind: .divider, text: "")
            case "callout":
                var c = NoteBlock(kind: .callout, text: text)
                c.icon = icon(v["icon"]) ?? "💡"
                made = c
            case "code", "equation":
                var c = NoteBlock(kind: .code, text: type == "equation" ? (v["expression"] as? String ?? "") : plain(v["rich_text"]))
                c.lang = type == "equation" ? "latex" : v["language"] as? String
                made = c
            case "toggle":
                var t = NoteBlock(kind: .toggle, text: text)
                t.collapsed = true
                made = t
            case "image":
                let b2 = NoteBlock(kind: .image, text: rich(v["caption"]))
                if let url = fileURL(v), let saved = await saveImage(url) { images[b2.id] = saved; made = b2 }
                else { warnings.insert("Some images couldn't be downloaded.") }
            case "bookmark", "embed", "link_preview", "video", "file", "pdf", "audio":
                if let url = (v["url"] as? String) ?? fileURL(v)?.absoluteString {
                    var bk = NoteBlock(kind: .bookmark, text: plain(v["caption"]).isEmpty ? url : plain(v["caption"]))
                    bk.refId = url
                    made = bk
                    if ["file", "pdf", "audio", "video"].contains(type) { warnings.insert("Files, PDFs and videos come in as links.") }
                }
            case "child_page":
                var pb = NoteBlock(kind: .page, text: v["title"] as? String ?? "Page"); pb.refId = "key:" + bid
                made = pb
            case "child_database":
                var pb = NoteBlock(kind: .page, text: v["title"] as? String ?? "Database"); pb.refId = "key:" + bid
                made = pb
            case "table":
                var rows: [[String]] = []
                for r in try await children(bid) {
                    if let cells = (r["table_row"] as? [String: Any])?["cells"] as? [Any] { rows.append(cells.map { rich($0) }) }
                }
                var t = NoteBlock(kind: .table, text: ""); t.rows = rows
                made = t
            case "column_list", "column", "synced_block", "template":
                childDepth = depth                     // their contents sit at the same level
            case "table_of_contents", "breadcrumb", "unsupported":
                continue
            default:
                if !text.isEmpty { made = NoteBlock(kind: .text, text: text) }
            }
            if var m = made {
                m.indent = depth > 0 ? min(depth, 8) : nil
                if m.kind == .callout {
                    m.color = BlockColor.fromWorkspace(v["color"] as? String) ?? "bg:gray"
                } else {
                    m.color = BlockColor.fromWorkspace(v["color"] as? String)
                }
                out.append(m)
            }
            // Nested content keeps its nesting.
            if hasKids, depth < 8, !["child_page", "child_database", "table"].contains(type) {
                out += try await blocks(of: bid, depth: childDepth, images: &images, warnings: &warnings)
            }
        }
        return out
    }

    // MARK: Values

    private func plain(_ any: Any?) -> String {
        ((any as? [[String: Any]]) ?? []).map { $0["plain_text"] as? String ?? "" }.joined()
    }

    /// Rich text → Keel's inline markdown (bold, italic, code, strikethrough, links, page mentions).
    private func rich(_ any: Any?) -> String {
        ((any as? [[String: Any]]) ?? []).map { r -> String in
            var t = (r["plain_text"] as? String ?? "").replacingOccurrences(of: "\n", with: MarkdownImport.softBreak)
            guard !t.isEmpty else { return "" }
            let a = r["annotations"] as? [String: Any] ?? [:]
            // Colour wins over underline when both are set (they can't nest).
            func styled(_ s: String) -> String {
                if let c = BlockColor.fromWorkspace(a["color"] as? String) {
                    return c.hasPrefix("bg:") ? "{b:\(c.dropFirst(3))}\(s){/}" : "{c:\(c)}\(s){/}"
                }
                return a["underline"] as? Bool == true ? "{u}\(s){/}" : s
            }
            if let mention = r["mention"] as? [String: Any], let page = mention["page"] as? [String: Any], let id = page["id"] as? String {
                return styled("[\(t)](key:\(id))")
            }
            if a["code"] as? Bool == true { t = "`\(t)`" }
            if a["bold"] as? Bool == true { t = "**\(t)**" }
            if a["italic"] as? Bool == true { t = "*\(t)*" }
            if a["strikethrough"] as? Bool == true { t = "~~\(t)~~" }
            if let href = r["href"] as? String {
                if let id = href.range(of: #"[0-9a-f]{32}"#, options: .regularExpression).map({ String(href[$0]) }), href.contains("notion.so") || href.hasPrefix("/") {
                    return styled("[\(t)](key:\(dashed(id)))")
                }
                return styled("[\(t)](\(href))")
            }
            return styled(t)
        }.joined()
    }

    private func dashed(_ id: String) -> String {
        guard id.count == 32 else { return id }
        let c = Array(id)
        return [String(c[0..<8]), String(c[8..<12]), String(c[12..<16]), String(c[16..<20]), String(c[20..<32])].joined(separator: "-")
    }

    private func pageTitle(_ o: [String: Any]) -> String {
        for (_, v) in (o["properties"] as? [String: Any]) ?? [:] {
            if let p = v as? [String: Any], p["type"] as? String == "title" { return plain(p["title"]) }
        }
        return ""
    }

    private func icon(_ any: Any?) -> String? {
        guard let i = any as? [String: Any] else { return nil }
        return i["emoji"] as? String
    }

    private func parentId(_ any: Any?) -> String? {
        guard let p = any as? [String: Any] else { return nil }
        return (p["page_id"] as? String) ?? (p["database_id"] as? String) ?? (p["block_id"] as? String)
    }

    private func date(_ any: Any?) -> Date? { (any as? String).flatMap { try? Date($0, strategy: .iso8601) } }

    private func fileURL(_ v: [String: Any]) -> URL? {
        let s = ((v["file"] as? [String: Any])?["url"] as? String) ?? ((v["external"] as? [String: Any])?["url"] as? String)
        return s.flatMap(URL.init(string:))
    }

    /// Downloads an image straight to disk (image links expire after an hour, so it's done right away).
    /// Returns a name the importer resolves, so huge workspaces don't fill memory.
    private func saveImage(_ url: URL) async -> String? {
        guard let d = await download(url) else { return nil }
        let ext = url.pathExtension.isEmpty || url.pathExtension.count > 5 ? "img" : url.pathExtension.lowercased()
        let name = UUID().uuidString + "." + ext
        do { try d.write(to: NotionCache.images.appendingPathComponent(name)) } catch { return nil }
        return "notioncache:" + name
    }

    private func download(_ url: URL) async -> Data? {
        guard let result = try? await URLSession.shared.data(from: url) else { return nil }
        let d = result.0, r = result.1
        guard ((r as? HTTPURLResponse)?.statusCode ?? 200) < 400, d.count < 20_000_000 else { return nil }
        return d
    }

    private func schema(_ db: [String: Any]) -> [DBProperty] {
        var out: [DBProperty] = []
        for (name, v) in (db["properties"] as? [String: Any]) ?? [:] {
            guard let p = v as? [String: Any], let type = p["type"] as? String, type != "title" else { continue }
            let options = ((p[type] as? [String: Any])?["options"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            let kind: DBProperty.Kind = switch type {
            case "number": .number
            case "select": .select
            case "multi_select": .multiSelect
            case "status": .status
            case "date", "created_time", "last_edited_time": .date
            case "checkbox": .checkbox
            case "url", "email", "phone_number": .url
            case "people", "created_by", "last_edited_by": .person
            default: .text
            }
            out.append(DBProperty(name: name, kind: kind, options: options))
        }
        return out.sorted { $0.name < $1.name }
    }

    /// A row's values, as text Keel's database understands.
    private func props(_ any: Any?, schema: [DBProperty]) -> [String: String] {
        var out: [String: String] = [:]
        for (name, v) in (any as? [String: Any]) ?? [:] {
            guard let p = v as? [String: Any], let type = p["type"] as? String, type != "title" else { continue }
            let val: String? = switch type {
            case "rich_text": plain(p["rich_text"])
            case "number": (p["number"] as? Double).map { $0.truncatingRemainder(dividingBy: 1) == 0 ? String(Int($0)) : String($0) }
            case "select", "status": ((p[type] as? [String: Any])?["name"] as? String)
            case "multi_select": ((p["multi_select"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }.joined(separator: ", ")
            case "date": ((p["date"] as? [String: Any])?["start"] as? String).map { String($0.prefix(10)) }
            case "created_time", "last_edited_time": (p[type] as? String).map { String($0.prefix(10)) }
            case "checkbox": (p["checkbox"] as? Bool == true) ? "1" : ""
            case "url", "email", "phone_number": p[type] as? String
            case "people": ((p["people"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }.joined(separator: ", ")
            case "formula":
                ((p["formula"] as? [String: Any])).flatMap { f -> String? in
                    if let s = f["string"] as? String { return s }
                    if let n = f["number"] as? Double { return String(n) }
                    if let b = f["boolean"] as? Bool { return b ? "Yes" : "No" }
                    return ((f["date"] as? [String: Any])?["start"] as? String).map { String($0.prefix(10)) }
                }
            default: nil
            }
            if let val, !val.isEmpty { out[name] = val }
        }
        _ = schema
        return out
    }
}
