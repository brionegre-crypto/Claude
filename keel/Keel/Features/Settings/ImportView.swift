import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Bring tasks and notes from other apps: CSV task exports, Markdown/text notes and Evernote .enex files.
@MainActor
enum Importer {
    // MARK: CSV tasks

    /// Parses CSV with quoted fields, commas and newlines inside quotes.
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", inQuotes = false
        var chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n": row.append(field); rows.append(row); row = []; field = ""
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows.filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
    }

    static func importTasks(csv: String, ctx: ModelContext) -> Int {
        let rows = parseCSV(csv)
        guard let header = rows.first?.map({ $0.lowercased().trimmingCharacters(in: .whitespaces) }) else { return 0 }
        func col(_ names: [String]) -> Int? { header.firstIndex { h in names.contains(h) } }
        let title = col(["title", "content", "task", "name", "task name", "subject"]) ?? 0
        let notes = col(["description", "notes", "note", "content description", "desc"])
        let due = col(["due date", "due", "date", "duedate", "deadline", "start date"])
        let priority = col(["priority", "importance"])
        let list = col(["list", "list name", "project", "folder", "section"])
        let tags = col(["tags", "labels", "tag"])
        let done = col(["status", "completed", "done", "is completed"])
        let type = col(["type"])
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        var count = 0
        for r in rows.dropFirst() {
            func v(_ i: Int?) -> String { i.flatMap { $0 < r.count ? r[$0].trimmingCharacters(in: .whitespacesAndNewlines) : nil } ?? "" }
            if let type, !["", "task"].contains(v(type).lowercased()) { continue }      // skip section/note rows
            let t = v(title)
            guard !t.isEmpty else { continue }
            let task = TaskItem(title: t)
            task.notes = v(notes)
            let dueText = v(due)
            if !dueText.isEmpty {
                task.dueDate = (try? Date(dueText, strategy: .iso8601))
                    ?? detector?.firstMatch(in: dueText, range: NSRange(dueText.startIndex..., in: dueText))?.date
            }
            switch v(priority).lowercased() {
            case "1", "4", "high", "p1", "urgent", "5": task.priority = .high
            case "2", "3", "medium", "p2", "normal": task.priority = .medium
            case "low", "p3": task.priority = .low
            default: break
            }
            let l = v(list); if !l.isEmpty { task.listName = l }
            task.tags = v(tags).split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" }).map { $0.replacingOccurrences(of: "#", with: "") }.filter { !$0.isEmpty }
            let d = v(done).lowercased()
            if ["completed", "done", "true", "yes", "1", "2"].contains(d) { task.isDone = true; task.completedAt = Date() }
            ctx.insert(task)
            try? CalendarService.shared.push(task)
            count += 1
        }
        return count
    }

    // MARK: Markdown notes

    static func note(fromMarkdown md: String, fallbackTitle: String) -> Note {
        var title = fallbackTitle
        var blocks: [NoteBlock] = []
        var inCode = false, code: [String] = []
        for raw in md.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if inCode { var b = NoteBlock(kind: .code, text: code.joined(separator: "\n")); b.lang = nil; blocks.append(b); code = [] }
                inCode.toggle(); continue
            }
            if inCode { code.append(raw); continue }
            if line.isEmpty { continue }
            if line.hasPrefix("# ") && blocks.isEmpty && title == fallbackTitle { title = String(line.dropFirst(2)); continue }
            if line.hasPrefix("### ") { blocks.append(NoteBlock(kind: .heading3, text: String(line.dropFirst(4)))) }
            else if line.hasPrefix("## ") { blocks.append(NoteBlock(kind: .heading2, text: String(line.dropFirst(3)))) }
            else if line.hasPrefix("# ") { blocks.append(NoteBlock(kind: .heading, text: String(line.dropFirst(2)))) }
            else if line.hasPrefix("- [ ] ") || line.hasPrefix("* [ ] ") { blocks.append(NoteBlock(kind: .todo, text: String(line.dropFirst(6)))) }
            else if line.lowercased().hasPrefix("- [x] ") { blocks.append(NoteBlock(kind: .todo, text: String(line.dropFirst(6)), checked: true)) }
            else if line.hasPrefix("- ") || line.hasPrefix("* ") { blocks.append(NoteBlock(kind: .bullet, text: String(line.dropFirst(2)))) }
            else if let r = line.range(of: #"^\d+\.\s"#, options: .regularExpression) { blocks.append(NoteBlock(kind: .numbered, text: String(line[r.upperBound...]))) }
            else if line.hasPrefix("> ") { blocks.append(NoteBlock(kind: .quote, text: String(line.dropFirst(2)))) }
            else if line == "---" || line == "***" { blocks.append(NoteBlock(kind: .divider, text: "")) }
            else { blocks.append(NoteBlock(kind: .text, text: line)) }
        }
        if !code.isEmpty { blocks.append(NoteBlock(kind: .code, text: code.joined(separator: "\n"))) }
        return Note(title: title, blocks: blocks.isEmpty ? [NoteBlock(kind: .text, text: "")] : blocks)
    }

    // MARK: Evernote

    static func importEnex(_ xml: String, ctx: ModelContext) -> Int {
        var count = 0
        let notes = xml.components(separatedBy: "<note>").dropFirst()
        for chunk in notes {
            let title = between(chunk, "<title>", "</title>") ?? "Imported note"
            let content = between(chunk, "<content>", "</content>") ?? ""
            let text = content.replacingOccurrences(of: "<![CDATA[", with: "").replacingOccurrences(of: "]]>", with: "")
                .replacingOccurrences(of: "<br/>", with: "\n").replacingOccurrences(of: "</div>", with: "\n").replacingOccurrences(of: "</p>", with: "\n")
                .replacingOccurrences(of: #"<en-todo checked="true"/>"#, with: "- [x] ")
                .replacingOccurrences(of: "<en-todo checked=\"false\"/>", with: "- [ ] ").replacingOccurrences(of: "<en-todo/>", with: "- [ ] ")
                .replacingOccurrences(of: "<li>", with: "- ")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&quot;", with: "\"")
            ctx.insert(note(fromMarkdown: text, fallbackTitle: title.replacingOccurrences(of: "&amp;", with: "&")))
            count += 1
        }
        return count
    }

    private static func between(_ s: String, _ a: String, _ b: String) -> String? {
        guard let r1 = s.range(of: a), let r2 = s.range(of: b, range: r1.upperBound..<s.endIndex) else { return nil }
        return String(s[r1.upperBound..<r2.lowerBound])
    }

    static func read(_ url: URL) -> String? {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
}

struct ImportView: View {
    @Environment(\.modelContext) private var ctx
    @State private var picking: String?
    @State private var result: String?

    var body: some View {
        List {
            Section {
                row("Tasks from a CSV file", "checklist", "Most to-do apps can export CSV. Keel reads the title, notes, due date, priority, list, tags and done status.", "csv")
                row("Notes from Markdown or text", "doc.text", "Pick one or many .md or .txt files, such as a notes workspace export unzipped in Files. Headings, lists, to-dos, quotes and code become blocks.", "md")
                row("Evernote export (.enex)", "note.text", "Export a notebook from Evernote and pick the .enex file.", "enex")
            } footer: { Text("Imports are added alongside what's already in Keel. Nothing is replaced.") }
            if let result { Section { Label(result, systemImage: "checkmark.circle.fill").foregroundStyle(DS.Palette.calm) } }
        }
        .navigationTitle("Import")
        .fileImporter(isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
                      allowedContentTypes: types(picking), allowsMultipleSelection: picking == "md") { res in
            let kind = picking
            guard case .success(let urls) = res else { return }
            var n = 0
            for url in urls {
                guard let text = Importer.read(url) else { continue }
                switch kind {
                case "csv": n += Importer.importTasks(csv: text, ctx: ctx)
                case "enex": n += Importer.importEnex(text, ctx: ctx)
                default:
                    ctx.insert(Importer.note(fromMarkdown: text, fallbackTitle: url.deletingPathExtension().lastPathComponent))
                    n += 1
                }
            }
            try? ctx.save()
            Haptics.success()
            result = "Imported \(n) \(kind == "csv" ? "task" : "note")\(n == 1 ? "" : "s")."
        }
    }

    private func row(_ title: String, _ icon: String, _ detail: String, _ kind: String) -> some View {
        Button { result = nil; picking = kind } label: {
            HStack(alignment: .top, spacing: DS.Space.m) {
                Image(systemName: icon).font(.title3).foregroundStyle(DS.Palette.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                    Text(detail).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
            }
        }
    }

    private func types(_ kind: String?) -> [UTType] {
        switch kind {
        case "csv": [.commaSeparatedText, .plainText]
        case "enex": [UTType(filenameExtension: "enex") ?? .xml, .xml]
        default: [UTType(filenameExtension: "md") ?? .plainText, .plainText, .text]
        }
    }
}
