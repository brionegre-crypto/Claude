import Foundation

/// Imports straight from a workspace with an integration token: every page and database shared with
/// the integration, with their blocks, properties, icons and images. Nothing to export or unzip.
/// The token is kept in the Keychain on this iPhone and only ever sent to api.notion.com.
struct NotionConnector: Sendable {
    let token: String
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
        try await Task.sleep(for: .milliseconds(340))
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

    func fetchAll(progress: @escaping @Sendable (String, Double) async -> Void) async throws -> ImportBundle {
        // 1. Everything shared with the integration.
        var objects: [[String: Any]] = []
        var cursor: String?
        repeat {
            var body: [String: Any] = ["page_size": 100]
            if let cursor { body["start_cursor"] = cursor }
            let r = try await request("/search", method: "POST", body: body)
            objects += (r["results"] as? [[String: Any]]) ?? []
            cursor = (r["has_more"] as? Bool == true) ? r["next_cursor"] as? String : nil
            await progress("Found \(objects.count) pages…", 0.05)
        } while cursor != nil && objects.count < 5000
        objects.removeAll { $0["archived"] as? Bool == true || $0["in_trash"] as? Bool == true }
        guard !objects.isEmpty else { throw Failure.nothingShared }

        var pages: [ImportedPage] = []
        var warnings: Set<String> = []
        let dbSchemas = Dictionary(objects.filter { $0["object"] as? String == "database" }.compactMap { o -> (String, [DBProperty])? in
            guard let id = o["id"] as? String else { return nil }
            return (id, schema(o))
        }, uniquingKeysWith: { a, _ in a })

        for (i, o) in objects.enumerated() {
            try Task.checkCancellation()
            guard let id = o["id"] as? String else { continue }
            let isDB = o["object"] as? String == "database"
            var page = ImportedPage(key: id, title: isDB ? plain(o["title"]) : pageTitle(o))
            if page.title.isEmpty { page.title = "Untitled" }
            page.icon = icon(o["icon"]) ?? (isDB ? "🗃️" : nil)
            page.created = date(o["created_time"])
            page.updated = date(o["last_edited_time"])
            page.parentKey = parentId(o["parent"])
            if isDB {
                page.isDatabase = true
                page.schema = dbSchemas[id] ?? []
            } else {
                if let dbId = (o["parent"] as? [String: Any])?["database_id"] as? String {
                    page.props = props(o["properties"], schema: dbSchemas[dbId] ?? [])
                }
                var images: [UUID: Data] = [:]
                page.blocks = try await blocks(of: id, depth: 0, images: &images, warnings: &warnings)
                page.imageData = images
            }
            if let cover = o["cover"] as? [String: Any], let url = fileURL(cover), let d = await download(url) {
                // Covers come in as an image at the top.
                let b = NoteBlock(kind: .image, text: "")
                page.blocks.insert(b, at: 0)
                page.imageData[b.id] = d
            }
            pages.append(page)
            await progress("Reading “\(page.title)”", 0.05 + 0.9 * Double(i + 1) / Double(objects.count))
        }
        return ImportBundle(source: .notionAPI, name: "Workspace", pages: pages, warnings: Array(warnings).sorted())
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

    private func blocks(of id: String, depth: Int, images: inout [UUID: Data], warnings: inout Set<String>) async throws -> [NoteBlock] {
        var out: [NoteBlock] = []
        for b in try await children(id) {
            guard let type = b["type"] as? String, let v = b[type] as? [String: Any] else { continue }
            let text = rich(v["rich_text"])
            let hasKids = b["has_children"] as? Bool == true
            let bid = b["id"] as? String ?? ""
            switch type {
            case "paragraph": if !text.isEmpty { out.append(NoteBlock(kind: .text, text: text)) }
            case "heading_1": out.append(NoteBlock(kind: .heading, text: text))
            case "heading_2": out.append(NoteBlock(kind: .heading2, text: text))
            case "heading_3": out.append(NoteBlock(kind: .heading3, text: text))
            case "bulleted_list_item": out.append(NoteBlock(kind: .bullet, text: text))
            case "numbered_list_item": out.append(NoteBlock(kind: .numbered, text: text))
            case "to_do": out.append(NoteBlock(kind: .todo, text: text, checked: v["checked"] as? Bool ?? false))
            case "quote": out.append(NoteBlock(kind: .quote, text: text))
            case "divider": out.append(NoteBlock(kind: .divider, text: ""))
            case "callout":
                var c = NoteBlock(kind: .callout, text: text)
                c.icon = icon(v["icon"]) ?? "💡"
                out.append(c)
            case "code", "equation":
                var c = NoteBlock(kind: .code, text: type == "equation" ? (v["expression"] as? String ?? "") : plain(v["rich_text"]))
                c.lang = type == "equation" ? "latex" : v["language"] as? String
                out.append(c)
            case "toggle":
                var t = NoteBlock(kind: .toggle, text: text)
                if hasKids, depth < 4 {
                    var sub: [UUID: Data] = [:]
                    t.body = try await blocks(of: bid, depth: depth + 1, images: &sub, warnings: &warnings).map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
                }
                t.collapsed = true
                out.append(t)
                continue
            case "image":
                let b2 = NoteBlock(kind: .image, text: plain(v["caption"]))
                if let url = fileURL(v), let d = await download(url) { images[b2.id] = d; out.append(b2) }
                else { warnings.insert("Some images couldn't be downloaded.") }
            case "bookmark", "embed", "link_preview", "video", "file", "pdf", "audio":
                if let url = (v["url"] as? String) ?? fileURL(v)?.absoluteString {
                    var bk = NoteBlock(kind: .bookmark, text: plain(v["caption"]).isEmpty ? url : plain(v["caption"]))
                    bk.refId = url
                    out.append(bk)
                    if ["file", "pdf", "audio", "video"].contains(type) { warnings.insert("Files, PDFs and videos come in as links.") }
                }
            case "child_page":
                var pb = NoteBlock(kind: .page, text: v["title"] as? String ?? "Page"); pb.refId = "key:" + bid
                out.append(pb); continue
            case "child_database":
                var pb = NoteBlock(kind: .page, text: v["title"] as? String ?? "Database"); pb.refId = "key:" + bid
                out.append(pb); continue
            case "table":
                var rows: [[String]] = []
                for r in try await children(bid) {
                    if let cells = (r["table_row"] as? [String: Any])?["cells"] as? [Any] { rows.append(cells.map { rich($0) }) }
                }
                var t = NoteBlock(kind: .table, text: ""); t.rows = rows
                out.append(t); continue
            case "column_list", "column", "synced_block", "template":
                break                                  // their content is in the children, below
            case "table_of_contents", "breadcrumb", "unsupported":
                continue
            default:
                if !text.isEmpty { out.append(NoteBlock(kind: .text, text: text)) }
            }
            // Nested content (indented list items, columns, synced blocks) flattens in place.
            if hasKids, depth < 4, !["child_page", "child_database", "table", "toggle"].contains(type) {
                out += try await blocks(of: bid, depth: depth + 1, images: &images, warnings: &warnings)
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
            var t = r["plain_text"] as? String ?? ""
            guard !t.isEmpty else { return "" }
            let a = r["annotations"] as? [String: Any] ?? [:]
            if let mention = r["mention"] as? [String: Any], let page = mention["page"] as? [String: Any], let id = page["id"] as? String {
                return "[\(t)](key:\(id))"
            }
            if a["code"] as? Bool == true { t = "`\(t)`" }
            if a["bold"] as? Bool == true { t = "**\(t)**" }
            if a["italic"] as? Bool == true { t = "*\(t)*" }
            if a["strikethrough"] as? Bool == true { t = "~~\(t)~~" }
            if let href = r["href"] as? String {
                if let id = href.range(of: #"[0-9a-f]{32}"#, options: .regularExpression).map({ String(href[$0]) }), href.contains("notion.so") || href.hasPrefix("/") {
                    return "[\(t)](key:\(dashed(id)))"
                }
                return "[\(t)](\(href))"
            }
            return t
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
