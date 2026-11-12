import Foundation
import SwiftData

/// Writes an import into Keel: pages, sub-pages, databases with their columns and rows, images and links.
/// Every import is recorded so it can be undone in one tap.
@MainActor
enum ImportEngine {
    struct Options {
        var folder: String? = nil              // put everything in this folder (nil = keep the source's folders)
        var skipDuplicates = true              // don't import pages you already have (safe to run twice)
        var todosToTasks = false               // also add unchecked to-dos as Keel tasks
    }

    struct Record: Codable, Identifiable {
        var id = UUID()
        var source: ImportSource
        var name: String
        var date = Date()
        var noteIds: [UUID] = []
        var attachmentIds: [UUID] = []
        var taskIds: [UUID] = []
        var skipped = 0
        var images = 0
        var links = 0
        var databases = 0
        var undone = false
    }

    static let historyKey = "imports.history"
    static var history: [Record] {
        get {
            guard let d = UserDefaults.standard.data(forKey: historyKey), let r = try? JSONDecoder().decode([Record].self, from: d) else { return [] }
            return r
        }
        set { if let d = try? JSONEncoder().encode(Array(newValue.prefix(30))) { UserDefaults.standard.set(d, forKey: historyKey) } }
    }

    // MARK: Duplicates

    private static func signature(title: String, blocks: [NoteBlock]) -> String {
        title.lowercased().trimmingCharacters(in: .whitespaces) + "|" + blocks.prefix(4).map(\.text).joined(separator: " ").prefix(240).lowercased()
    }

    static func existingSignatures(_ ctx: ModelContext) -> Set<String> {
        Set(((try? ctx.fetch(FetchDescriptor<Note>())) ?? []).map { signature(title: $0.title, blocks: $0.blocks) })
    }

    static func duplicateCount(_ b: ImportBundle, ctx: ModelContext) -> Int {
        let have = existingSignatures(ctx)
        return b.pages.filter { !$0.isDatabase && have.contains(signature(title: $0.title, blocks: $0.blocks)) }.count
    }

    // MARK: Import

    static func run(_ bundle: ImportBundle, archive: ImportArchive?, options: Options, ctx: ModelContext,
                    progress: (Double, String) -> Void) async -> Record {
        var record = Record(source: bundle.source, name: bundle.name)
        let have = options.skipDuplicates ? existingSignatures(ctx) : []
        let keys = Set(bundle.pages.map(\.key))

        // 1. Create every note, so links and parents can point at them.
        var idFor: [String: UUID] = [:]
        var notes: [(ImportedPage, Note)] = []
        var titleIndex: [String: UUID] = [:]
        let total = Double(max(1, bundle.pages.count))
        for (i, p) in bundle.pages.enumerated() {
            if options.skipDuplicates && !p.isDatabase && have.contains(signature(title: p.title, blocks: p.blocks)) {
                record.skipped += 1
                continue
            }
            let n = Note(title: p.title, blocks: [])
            n.icon = p.icon
            n.isPinned = p.pinned
            n.createdAt = p.created ?? Date()
            n.updatedAt = p.updated ?? p.created ?? Date()
            n.sortIndex = Double(i)
            let isTop = p.parentKey == nil || !keys.contains(p.parentKey!)
            n.folder = isTop ? (options.folder ?? p.folder) : nil
            if p.isDatabase {
                n.isDatabase = true
                n.schema = p.schema
                n.dbGroupBy = p.schema.first { $0.kind == .status || $0.kind == .select }?.id
                n.icon = n.icon ?? "🗃️"
                record.databases += 1
            }
            ctx.insert(n)
            idFor[p.key] = n.id
            if titleIndex[p.title.lowercased()] == nil { titleIndex[p.title.lowercased()] = n.id }
            notes.append((p, n))
            record.noteIds.append(n.id)
            if i % 40 == 0 {
                progress(0.1 + 0.4 * Double(i) / total, "Creating pages… \(i + 1) of \(bundle.pages.count)")
                await Task.yield()
            }
        }

        // 2. Parents, database values, blocks with real links, images.
        let schemaFor: [UUID: [DBProperty]] = Dictionary(notes.filter { $0.1.isDatabase }.map { ($0.1.id, $0.1.schema) }, uniquingKeysWith: { a, _ in a })
        let allPaths = archive?.paths ?? []
        for (i, pair) in notes.enumerated() {
            let (p, n) = pair
            if let pk = p.parentKey, let pid = idFor[pk] {
                n.parentId = pid
                if let schema = schemaFor[pid] { n.props = values(p.props, schema: schema) }
            }
            var blocks = p.blocks.compactMap { b -> NoteBlock? in
                var b = b
                if b.kind == .page {
                    guard let ref = b.refId, let target = resolvePageRef(ref, idFor: idFor, titles: titleIndex) else {
                        return NoteBlock(kind: .text, text: b.text.isEmpty ? "" : "📄 \(b.text)")
                    }
                    b.refId = target.uuidString
                    record.links += 1
                    return b
                }
                b.text = resolveLinks(b.text, dir: p.dir, idFor: idFor, titles: titleIndex, count: &record.links)
                if let body = b.body { b.body = resolveLinks(body, dir: p.dir, idFor: idFor, titles: titleIndex, count: &record.links) }
                if let rows = b.rows { b.rows = rows.map { $0.map { resolveLinks($0, dir: p.dir, idFor: idFor, titles: titleIndex, count: &record.links) } } }
                return b
            }
            // Images: from the import's files or bytes we already have.
            for (bi, b) in blocks.enumerated() where b.kind == .image {
                var data = p.imageData[b.id]
                if data == nil, let path = p.imagePaths[b.id], let archive {
                    if path.hasPrefix("find:") {
                        let name = String(path.dropFirst(5)).lowercased()
                        if let found = allPaths.first(where: { $0.lowercased().hasSuffix("/" + name) || $0.lowercased() == name }) { data = archive.data(found) }
                    } else {
                        data = archive.data(path)
                    }
                }
                if let data, !data.isEmpty {
                    let att = NoteAttachment(noteId: n.id, data: data, kind: "photo")
                    ctx.insert(att)
                    blocks[bi].refId = att.id.uuidString
                    record.attachmentIds.append(att.id)
                    record.images += 1
                }
            }
            blocks.removeAll { $0.kind == .image && $0.refId == nil }
            n.blocks = blocks.isEmpty && !n.isDatabase ? [NoteBlock(kind: .text, text: "")] : blocks

            if options.todosToTasks {
                for b in blocks where b.kind == .todo && !b.checked && !b.text.isEmpty {
                    let t = TaskItem(title: b.text.replacingOccurrences(of: "**", with: ""))
                    t.sourceNoteId = n.id
                    ctx.insert(t)
                    record.taskIds.append(t.id)
                }
            }
            if i % 25 == 0 {
                progress(0.5 + 0.45 * Double(i) / Double(max(1, notes.count)), "Adding content… \(n.title)")
                await Task.yield()
            }
        }
        try? ctx.save()
        progress(1, "Done")
        var h = history
        h.insert(record, at: 0)
        history = h
        return record
    }

    // MARK: Links

    private static func resolvePageRef(_ ref: String, idFor: [String: UUID], titles: [String: UUID]) -> UUID? {
        if ref.hasPrefix("key:") { return idFor[String(ref.dropFirst(4))] }
        if ref.hasPrefix("title:") { return titles[String(ref.dropFirst(6)).lowercased()] }
        if ref.hasPrefix("path:") {
            let path = String(ref.dropFirst(5))
            return idFor[(path as NSString).deletingPathExtension] ?? idFor[path]
        }
        return UUID(uuidString: ref)
    }

    /// Markdown links to other imported pages, page mentions and [[wiki links]] become Keel page links.
    static func resolveLinks(_ text: String, dir: String, idFor: [String: UUID], titles: [String: UUID], count: inout Int) -> String {
        guard text.contains("](") || text.contains("[[") else { return text }
        var out = text
        if out.contains("](") {
            let re = try? NSRegularExpression(pattern: #"\[([^\]]*)\]\(([^)\s]+)\)"#)
            let ns = out as NSString
            var result = ""
            var last = 0
            for m in re?.matches(in: out, range: NSRange(location: 0, length: ns.length)) ?? [] {
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let label = ns.substring(with: m.range(at: 1)), target = ns.substring(with: m.range(at: 2))
                var id: UUID?
                if target.hasPrefix("key:") { id = idFor[String(target.dropFirst(4))] }
                else if !target.contains("://"), !target.hasPrefix("mailto:"), !target.hasPrefix("#") {
                    let resolved = ImportPaths.resolve(target, from: dir)
                    id = idFor[(resolved as NSString).deletingPathExtension] ?? idFor[resolved]
                }
                if let id {
                    result += "[\(label)](\(RichText.pageURL(id)))"; count += 1
                } else if target.hasPrefix("key:") {
                    result += label                       // a page that wasn't shared: keep the words
                } else {
                    result += ns.substring(with: m.range)
                }
                last = m.range.location + m.range.length
            }
            result += ns.substring(from: last)
            out = result
        }
        if out.contains("[[") {
            let re = try? NSRegularExpression(pattern: #"\[\[([^\]|#]+)(#[^\]|]*)?(\|([^\]]+))?\]\]"#)
            let ns = out as NSString
            var result = ""
            var last = 0
            for m in re?.matches(in: out, range: NSRange(location: 0, length: ns.length)) ?? [] {
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let name = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
                let alias = m.range(at: 4).location != NSNotFound ? ns.substring(with: m.range(at: 4)) : ImportPaths.name(name)
                let base = ImportPaths.stem(name).lowercased()
                if let id = titles[base] ?? titles[name.lowercased()] {
                    result += "[\(alias)](\(RichText.pageURL(id)))"; count += 1
                } else {
                    result += "[[\(name)]]"
                }
                last = m.range.location + m.range.length
            }
            result += ns.substring(from: last)
            out = result
        }
        return out
    }

    /// Row values by column name → Keel's stored values by column id.
    private static func values(_ byName: [String: String], schema: [DBProperty]) -> [String: String] {
        var out: [String: String] = [:]
        for (name, raw) in byName {
            guard let p = schema.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
            var v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            switch p.kind {
            case .checkbox: v = ["yes", "true", "checked", "1", "☑"].contains(v.lowercased()) ? "1" : ""
            case .date: v = ImportDates.parse(v).map { NotesDatabase.string($0) } ?? v
            case .number: v = v.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
            default: break
            }
            if !v.isEmpty { out[p.id] = v }
        }
        return out
    }

    // MARK: Undo

    static func undo(_ r: Record, ctx: ModelContext) {
        let notes = Set(r.noteIds), atts = Set(r.attachmentIds), tasks = Set(r.taskIds)
        for n in (try? ctx.fetch(FetchDescriptor<Note>())) ?? [] where notes.contains(n.id) { ctx.delete(n) }
        for a in (try? ctx.fetch(FetchDescriptor<NoteAttachment>())) ?? [] where atts.contains(a.id) { ctx.delete(a) }
        for t in (try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? [] where tasks.contains(t.id) { ctx.delete(t) }
        try? ctx.save()
        var h = history
        if let i = h.firstIndex(where: { $0.id == r.id }) { h[i].undone = true }
        history = h
    }
}
