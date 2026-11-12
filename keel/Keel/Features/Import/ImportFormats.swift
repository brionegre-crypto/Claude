import Foundation
import CryptoKit

// MARK: - What every importer produces

/// One page on its way into Keel, before it's saved. Links point at other pages by `key` until the end,
/// when they're turned into real Keel page links.
struct ImportedPage {
    var key: String                         // unique within the import (usually the source path)
    var title: String
    var icon: String? = nil
    var blocks: [NoteBlock] = []
    var folder: String? = nil
    var parentKey: String? = nil
    var created: Date? = nil
    var updated: Date? = nil
    var pinned = false
    var isDatabase = false
    var schema: [DBProperty] = []
    var props: [String: String] = [:]       // database row values, by property name
    var imagePaths: [UUID: String] = [:]    // image block → file in the import
    var imageData: [UUID: Data] = [:]       // image block → bytes we already have
    var coverPath: String? = nil
    var coverData: Data? = nil
    var dir: String = ""                    // folder the page came from, for relative links
}

enum ImportSource: String, Codable, CaseIterable, Identifiable {
    case notion, notionAPI, obsidian, evernote, keep, textbundle, markdown
    var id: String { rawValue }
    var label: String {
        switch self {
        case .notion: "Notion export"
        case .notionAPI: "Notion (connected)"
        case .obsidian: "Obsidian vault"
        case .evernote: "Evernote"
        case .keep: "Google Keep"
        case .textbundle: "Bear & TextBundle"
        case .markdown: "Markdown, text & HTML"
        }
    }
    var icon: String {
        switch self {
        case .notion, .notionAPI: "square.stack.3d.up.fill"
        case .obsidian: "diamond.fill"
        case .evernote: "leaf.fill"
        case .keep: "lightbulb.fill"
        case .textbundle: "pawprint.fill"
        case .markdown: "doc.text.fill"
        }
    }
}

struct ImportBundle {
    var source: ImportSource
    var name: String
    var pages: [ImportedPage]
    var warnings: [String] = []

    var databases: Int { pages.filter(\.isDatabase).count }
    var rows: Int {
        let dbKeys = Set(pages.filter(\.isDatabase).map(\.key))
        return pages.filter { $0.parentKey.map(dbKeys.contains) ?? false }.count
    }
    var images: Int { pages.reduce(0) { $0 + $1.imagePaths.count + $1.imageData.count } }
    var links: Int {
        pages.reduce(0) { n, p in
            n + p.blocks.reduce(0) { $0 + ($1.kind == .page ? 1 : 0) + $1.text.components(separatedBy: "](").count - 1 }
        }
    }
    var topLevel: [ImportedPage] {
        let keys = Set(pages.map(\.key))
        return pages.filter { $0.parentKey == nil || !keys.contains($0.parentKey!) }
    }
}

// MARK: - Markdown → Keel blocks

enum MarkdownImport {
    struct Result {
        var title: String?
        var blocks: [NoteBlock]
        var images: [UUID: String]
        var frontMatter: [(String, String)]
    }

    /// A line break inside a paragraph. Keel shows it as a new line, but it doesn't split the block
    /// when you edit it (Return does that).
    static let softBreak = "\u{2028}"

    static func parse(_ raw: String, dir: String) -> Result {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        var front: [(String, String)] = []
        // YAML front matter (properties at the top).
        if text.hasPrefix("---\n"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex) {
            let yaml = String(text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound])
            front = parseYAML(yaml)
            text = String(text[end.upperBound...])
        }
        var title: String?
        var blocks: [NoteBlock] = []
        var images: [UUID: String] = [:]
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var listStack: [Int] = []          // leading widths of open list levels (markdown indentation)
        var htmlLists: [Bool] = []         // open <ul>/<ol> from HTML: true = numbered
        var toggleDepth = 0                // inside toggles (<details>)
        var blankRun = 0

        func width(_ l: String) -> Int {
            var w = 0
            for ch in l { if ch == " " { w += 1 } else if ch == "\t" { w += 4 } else { break } }
            return w
        }
        func listLevel(_ w: Int) -> Int {
            while let last = listStack.last, last > w { listStack.removeLast() }
            if listStack.last != w { listStack.append(w) }
            return listStack.count - 1
        }
        func nestedLevel(_ w: Int) -> Int {
            // Content under a list item (an indented paragraph, code, image) sits one level inside it.
            guard w > 0 else { listStack = []; return 0 }
            return listStack.filter { $0 < w }.count
        }
        func add(_ block: NoteBlock, level: Int = 0) {
            var b = block
            // Block colours carried from HTML: ⟪bc:blue_background⟫ at the start.
            if b.text.hasPrefix("⟪bc:"), let close = b.text.firstIndex(of: "⟫") {
                b.color = BlockColor.fromWorkspace(String(b.text[b.text.index(b.text.startIndex, offsetBy: 4)..<close]))
                b.text = String(b.text[b.text.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            }
            let htmlLevel = max(0, htmlLists.count - 1)
            let listy = [BlockKind.bullet, .numbered, .todo, .toggle].contains(b.kind)
            let total = level + toggleDepth + (listy ? htmlLevel : (htmlLists.isEmpty ? 0 : htmlLists.count))
            b.indent = total > 0 ? min(total, 8) : nil
            // Extra blank lines between blocks are deliberate spacing: keep them.
            if blankRun >= 2 && !blocks.isEmpty {
                for _ in 0..<min(3, blankRun - 1) { blocks.append(NoteBlock(kind: .text, text: "")) }
            }
            blankRun = 0
            blocks.append(b)
        }

        while i < lines.count {
            let rawLine = lines[i]
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let w = width(rawLine)
            defer { i += 1 }
            if line.isEmpty { blankRun += 1; continue }
            if line == "-" || line == "*" || line == "+" { continue }        // an empty list marker (e.g. around a toggle)

            // Structure markers from HTML conversion.
            if line == "⟪ul⟫" || line == "⟪ol⟫" { htmlLists.append(line == "⟪ol⟫"); continue }
            if line == "⟪/ul⟫" || line == "⟪/ol⟫" { if !htmlLists.isEmpty { htmlLists.removeLast() }; continue }
            if line.hasPrefix("<details") || line == "⟪details⟫" {
                if let r = line.range(of: #"<summary>(.*?)</summary>"#, options: .regularExpression) {
                    let summary = String(line[r]).replacingOccurrences(of: "<summary>", with: "").replacingOccurrences(of: "</summary>", with: "")
                    var t = NoteBlock(kind: .toggle, text: inline(summary)); t.collapsed = true
                    add(t, level: nestedLevel(w)); toggleDepth += 1
                }
                continue
            }
            if line.hasPrefix("<summary>") || line.hasPrefix("⟪summary⟫") {
                let summary = line.replacingOccurrences(of: "<summary>", with: "").replacingOccurrences(of: "</summary>", with: "").replacingOccurrences(of: "⟪summary⟫", with: "")
                var t = NoteBlock(kind: .toggle, text: inline(summary)); t.collapsed = true
                add(t, level: nestedLevel(w)); toggleDepth += 1
                continue
            }
            if line.hasPrefix("</details>") || line == "⟪/details⟫" { toggleDepth = max(0, toggleDepth - 1); continue }

            // Fenced code
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                let fence = String(line.prefix(3))
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    // Remove the fence's own indentation, keep the code's.
                    var l = lines[i]
                    var drop = w
                    while drop > 0, let f = l.first, f == " " { l.removeFirst(); drop -= 1 }
                    code.append(l); i += 1
                }
                var b = NoteBlock(kind: .code, text: code.joined(separator: "\n"))
                b.lang = lang.isEmpty ? nil : lang
                add(b, level: nestedLevel(w)); continue
            }
            // Math block
            if line.hasPrefix("$$") {
                var math: [String] = [String(line.dropFirst(2))]
                if !(line.count > 2 && line.hasSuffix("$$")) {
                    i += 1
                    while i < lines.count && !lines[i].contains("$$") { math.append(lines[i]); i += 1 }
                }
                var b = NoteBlock(kind: .code, text: math.joined(separator: "\n").replacingOccurrences(of: "$$", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
                b.lang = "latex"; add(b, level: nestedLevel(w)); continue
            }
            // Callouts written as <aside> (workspace exports)
            if line.hasPrefix("<aside") {
                var body: [String] = []
                let first = line.replacingOccurrences(of: #"<aside[^>]*>"#, with: "", options: .regularExpression)
                if !first.isEmpty { body.append(first) }
                i += 1
                while i < lines.count && !lines[i].contains("</aside>") { body.append(lines[i].trimmingCharacters(in: .whitespaces)); i += 1 }
                if i < lines.count { body.append(lines[i].replacingOccurrences(of: "</aside>", with: "").trimmingCharacters(in: .whitespaces)) }
                var joined = body.filter { !$0.isEmpty }.joined(separator: softBreak)
                var b = NoteBlock(kind: .callout, text: "")
                if let f = joined.first, f.unicodeScalars.first?.properties.isEmojiPresentation == true {
                    b.icon = String(f); joined = String(joined.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                b.text = inline(joined)
                b.color = "bg:gray"
                add(b, level: nestedLevel(w)); continue
            }
            // Tables
            if line.hasPrefix("|") {
                var rows: [[String]] = []
                var j = i
                while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    let l = lines[j].trimmingCharacters(in: .whitespaces)
                    let cells = l.trimmingCharacters(in: CharacterSet(charactersIn: "|")).components(separatedBy: "|").map { inline($0.trimmingCharacters(in: .whitespaces)) }
                    if !cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { rows.append(cells) }
                    j += 1
                }
                i = j - 1
                let widthCols = rows.map(\.count).max() ?? 0
                var b = NoteBlock(kind: .table, text: "")
                b.rows = rows.map { $0 + Array(repeating: "", count: max(0, widthCols - $0.count)) }
                add(b, level: nestedLevel(w)); continue
            }
            // Vault-style callout: > [!note] Title
            if line.hasPrefix("> [!"), let close = line.firstIndex(of: "]") {
                let type = line[line.index(line.startIndex, offsetBy: 4)..<close].lowercased()
                var body = [String(line[line.index(after: close)...]).trimmingCharacters(in: CharacterSet(charactersIn: " +-"))]
                while i + 1 < lines.count, lines[i + 1].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    i += 1; body.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces))
                }
                var b = NoteBlock(kind: .callout, text: inline(body.filter { !$0.isEmpty }.joined(separator: softBreak)))
                let style: [String: (String, String)] = ["warning": ("⚠️", "bg:orange"), "caution": ("⚠️", "bg:orange"), "danger": ("🚨", "bg:red"), "error": ("🚨", "bg:red"),
                                                         "tip": ("💡", "bg:green"), "hint": ("💡", "bg:green"), "info": ("ℹ️", "bg:blue"), "note": ("📝", "bg:blue"),
                                                         "question": ("❓", "bg:yellow"), "success": ("✅", "bg:green"), "quote": ("💬", "bg:gray"),
                                                         "todo": ("☑️", "bg:blue"), "bug": ("🐞", "bg:red"), "example": ("📋", "bg:purple"), "abstract": ("📄", "bg:blue")]
                let st = style[String(type)] ?? ("📝", "bg:gray")
                b.icon = st.0; b.color = st.1
                add(b, level: nestedLevel(w)); continue
            }
            // Images on their own line
            if let m = firstMatch(#"^!\[([^\]]*)\]\(([^)]+)\)$"#, line) {
                let target = m[2].components(separatedBy: " \"").first ?? m[2]
                if target.hasPrefix("http") {
                    var b = NoteBlock(kind: .bookmark, text: m[1].isEmpty ? target : m[1]); b.refId = target; add(b, level: nestedLevel(w))
                } else {
                    let b = NoteBlock(kind: .image, text: m[1])
                    images[b.id] = target.hasPrefix("enmedia:") ? target : ImportPaths.resolve(target, from: dir)
                    add(b, level: nestedLevel(w))
                }
                continue
            }
            if let m = firstMatch(#"^!\[\[([^\]|]+)(\|[^\]]*)?\]\]$"#, line) {          // ![[image.png]] embeds
                let name = m[1]
                if ImportPaths.imageExts.contains(ImportPaths.ext(name)) {
                    let b = NoteBlock(kind: .image, text: "")
                    images[b.id] = "find:" + name
                    add(b, level: nestedLevel(w))
                } else {
                    var b = NoteBlock(kind: .page, text: ImportPaths.stem(name)); b.refId = "title:" + ImportPaths.stem(name); add(b, level: nestedLevel(w))
                }
                continue
            }
            // A line that's only a link to another page becomes a page block.
            if let m = firstMatch(#"^\[([^\]]+)\]\(([^)]+\.(md|html))\)$"#, line), !m[2].hasPrefix("http") {
                var b = NoteBlock(kind: .page, text: m[1]); b.refId = "path:" + ImportPaths.resolve(m[2], from: dir); add(b, level: nestedLevel(w)); continue
            }
            // Headings
            if line.hasPrefix("#") {
                let hashes = line.prefix { $0 == "#" }.count
                let rest = String(line.dropFirst(hashes)).trimmingCharacters(in: .whitespaces)
                if hashes <= 6, line.dropFirst(hashes).first == " " {
                    listStack = []
                    if hashes == 1 && title == nil && blocks.isEmpty { title = rest; continue }
                    add(NoteBlock(kind: hashes == 1 ? .heading : hashes == 2 ? .heading2 : .heading3, text: inline(rest)))
                    continue
                }
            }
            // Lists and to-dos, with their nesting.
            if let m = firstMatch(#"^[-*+]\s+\[([ xX])\]\s?(.*)$"#, line) {
                add(NoteBlock(kind: .todo, text: inline(m[2]), checked: m[1] != " "), level: listLevel(w)); continue
            }
            if let m = firstMatch(#"^[-*+]\s+(.*)$"#, line), !(line == "---" || line == "***" || line == "* * *") {
                let numbered = htmlLists.last == true
                add(NoteBlock(kind: numbered ? .numbered : .bullet, text: inline(m[1])), level: listLevel(w)); continue
            }
            if let m = firstMatch(#"^\d+[.)]\s+(.*)$"#, line) {
                add(NoteBlock(kind: .numbered, text: inline(m[1])), level: listLevel(w)); continue
            }
            // Quotes: consecutive lines stay one quote.
            if line.hasPrefix(">") {
                var q = [String(line.dropFirst()).trimmingCharacters(in: .whitespaces)]
                while i + 1 < lines.count, lines[i + 1].trimmingCharacters(in: .whitespaces).hasPrefix(">"),
                      !lines[i + 1].trimmingCharacters(in: .whitespaces).hasPrefix("> [!") {
                    i += 1; q.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces))
                }
                add(NoteBlock(kind: .quote, text: inline(q.joined(separator: softBreak))), level: nestedLevel(w)); continue
            }
            if line == "---" || line == "***" || line == "___" || line == "* * *" { listStack = []; add(NoteBlock(kind: .divider, text: "")); continue }
            // Paragraph: lines that belong together keep their line breaks.
            var para = [line]
            while i + 1 < lines.count {
                let next = lines[i + 1].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || startsBlock(next) { break }
                para.append(next); i += 1
            }
            let joined = para.map { $0.hasSuffix("\\") ? String($0.dropLast()) : $0 }.joined(separator: softBreak)
            add(NoteBlock(kind: .text, text: inline(joined)), level: nestedLevel(w))
        }
        return Result(title: title, blocks: blocks, images: images, frontMatter: front)
    }

    private static func startsBlock(_ l: String) -> Bool {
        l.hasPrefix("#") || l.hasPrefix("-") || l.hasPrefix("*") || l.hasPrefix("+") || l.hasPrefix(">") || l.hasPrefix("|")
            || l.hasPrefix("```") || l.hasPrefix("<") || l.hasPrefix("!") || l.hasPrefix("⟪") || l.range(of: #"^\d+[.)]\s"#, options: .regularExpression) != nil
    }

    /// Inline clean-up: HTML bits to markdown Keel understands.
    static func inline(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: #"<br\s*/?>"#, with: softBreak, options: .regularExpression)
        // Workspace colours: <mark class="highlight-red">, <mark class="highlight-yellow_background">, <span style="color:…">
        t = colorSpans(t)
        t = t.replacingOccurrences(of: #"<u>(.*?)</u>"#, with: "{u}$1{/}", options: .regularExpression)
        t = t.replacingOccurrences(of: #"</?(s|del|strike)>"#, with: "~~", options: .regularExpression)
        t = t.replacingOccurrences(of: #"</?(strong|b)>"#, with: "**", options: .regularExpression)
        t = t.replacingOccurrences(of: #"</?(em|i)>"#, with: "*", options: .regularExpression)
        t = t.replacingOccurrences(of: #"</?mark[^>]*>"#, with: "==", options: .regularExpression)
        t = t.replacingOccurrences(of: #"</?code>"#, with: "`", options: .regularExpression)
        t = t.replacingOccurrences(of: #"<a [^>]*href="([^"]*)"[^>]*>(.*?)</a>"#, with: "[$2]($1)", options: .regularExpression)
        t = t.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return HTMLImport.entities(t)
    }

    private static func colorSpans(_ s: String) -> String {
        guard s.contains("highlight-") || s.contains("color:"),
              let re = try? NSRegularExpression(pattern: #"<(mark|span)[^>]*?(?:class="[^"]*?highlight-([a-z_]+)[^"]*"|style="[^"]*?(background-)?color:\s*([a-z]+)[^"]*")[^>]*>(.*?)</(?:mark|span)>"#) else { return s }
        let ns = s as NSString
        var out = "", last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let inner = ns.substring(with: m.range(at: 5))
            var raw: String?
            if m.range(at: 2).location != NSNotFound { raw = ns.substring(with: m.range(at: 2)) }
            else if m.range(at: 4).location != NSNotFound {
                raw = ns.substring(with: m.range(at: 4)) + (m.range(at: 3).location != NSNotFound ? "_background" : "")
            }
            if let c = BlockColor.fromWorkspace(raw) {
                out += c.hasPrefix("bg:") ? "{b:\(c.dropFirst(3))}\(inner){/}" : "{c:\(c)}\(inner){/}"
            } else {
                out += inner
            }
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    static func firstMatch(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } ?? "" }
    }

    static func parseYAML(_ y: String) -> [(String, String)] {
        var out: [(String, String)] = []
        var listKey: String?, listVals: [String] = []
        func flush() { if let k = listKey { out.append((k, listVals.joined(separator: ", "))) }; listKey = nil; listVals = [] }
        for l in y.components(separatedBy: "\n") {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- "), listKey != nil { listVals.append(String(t.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))); continue }
            flush()
            guard let c = t.firstIndex(of: ":") else { continue }
            let k = String(t[..<c]).trimmingCharacters(in: .whitespaces)
            let v = String(t[t.index(after: c)...]).trimmingCharacters(in: CharacterSet(charactersIn: "\"' []"))
            if v.isEmpty { listKey = k } else { out.append((k, v)) }
        }
        flush()
        return out
    }
}

// MARK: - HTML → markdown

enum HTMLImport {
    static func toMarkdown(_ html: String) -> String {
        var t = html.replacingOccurrences(of: "\r\n", with: "\n")
        // Drop head, scripts and styles.
        for tag in ["head", "script", "style"] {
            t = t.replacingOccurrences(of: "<\(tag)[\\s\\S]*?</\(tag)>", with: "", options: [.regularExpression, .caseInsensitive])
        }
        t = t.replacingOccurrences(of: "\n", with: " ")
        // Block colours: a marker the markdown reader turns back into the block's colour.
        t = t.replacingOccurrences(of: #"(<(?:p|h1|h2|h3|li|blockquote|div|summary)\b[^>]*class="[^"]*block-color-([a-z_]+)[^"]*"[^>]*>)"#,
                                   with: "$1⟪bc:$2⟫", options: [.regularExpression, .caseInsensitive])
        let structure: [(String, String)] = [
            (#"<ul[^>]*>"#, "\n⟪ul⟫\n"), (#"</ul>"#, "\n⟪/ul⟫\n"), (#"<ol[^>]*>"#, "\n⟪ol⟫\n"), (#"</ol>"#, "\n⟪/ol⟫\n"),
            (#"<details[^>]*>"#, "\n"), (#"<summary[^>]*>"#, "\n⟪summary⟫"), (#"</summary>"#, "\n"), (#"</details>"#, "\n⟪/details⟫\n"),
        ]
        for (p, r) in structure { t = t.replacingOccurrences(of: p, with: r, options: [.regularExpression, .caseInsensitive]) }
        let rules: [(String, String)] = [
            (#"<h1[^>]*>"#, "\n# "), (#"<h2[^>]*>"#, "\n## "), (#"<h[3-6][^>]*>"#, "\n### "), (#"</h[1-6]>"#, "\n"),
            (#"<li[^>]*>\s*<input[^>]*checked[^>]*>"#, "\n- [x] "), (#"<li[^>]*>\s*<input[^>]*type="checkbox"[^>]*>"#, "\n- [ ] "),
            (#"<en-todo\s+checked="true"\s*/?>"#, "\n- [x] "), (#"<en-todo[^>]*/?>"#, "\n- [ ] "),
            (#"<li[^>]*>"#, "\n- "), (#"</li>"#, ""),
            (#"<blockquote[^>]*>"#, "\n> "), (#"</blockquote>"#, "\n"),
            (#"<pre[^>]*>"#, "\n```\n"), (#"</pre>"#, "\n```\n"),
            (#"<hr\s*/?>"#, "\n---\n"),
            (#"<br\s*/?>"#, "\n"), (#"</p>"#, "\n\n"), (#"<p[^>]*>"#, "\n"), (#"</div>"#, "\n"), (#"<div[^>]*>"#, ""),
            (#"<tr[^>]*>"#, "\n|"), (#"</t[dh]>"#, " |"), (#"<t[dh][^>]*>"#, " "),
            (#"<img[^>]*src="([^"]+)"[^>]*>"#, "\n![]($1)\n"),
            (#"<en-media[^>]*hash="([0-9a-f]+)"[^>]*/?>(</en-media>)?"#, "\n![](enmedia:$1)\n"),
        ]
        for (p, r) in rules { t = t.replacingOccurrences(of: p, with: r, options: [.regularExpression, .caseInsensitive]) }
        t = MarkdownImport.inline(t)
        // Inline cleanup removes tags but keeps line structure; tidy blank runs.
        t = t.replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func entities(_ s: String) -> String {
        var t = s
        for (a, b) in [("&nbsp;", " "), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…"), ("&amp;", "&")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        return t
    }
}

// MARK: - Detect what was picked

enum ImportDetector {
    static func detect(_ a: ImportArchive) -> ImportSource {
        let paths = a.paths
        let lower = paths.map { $0.lowercased() }
        if lower.contains(where: { $0.hasSuffix(".enex") }) { return .evernote }
        if lower.contains(where: { $0.contains("keep/") && $0.hasSuffix(".json") }) { return .keep }
        if lower.contains(where: { $0.contains(".textbundle/") || $0.hasSuffix(".textpack") }) { return .textbundle }
        if lower.contains(where: { $0.contains(".obsidian/") }) { return .obsidian }
        let idNamed = paths.filter { $0.range(of: #"\s[0-9a-f]{32}\.(md|csv|html)$"#, options: .regularExpression) != nil }.count
        if idNamed > 0 && idNamed * 3 >= paths.filter({ ["md", "csv", "html"].contains(ImportPaths.ext($0)) }).count { return .notion }
        // Lots of [[wiki links]] → a vault even without its settings folder.
        let mds = paths.filter { ImportPaths.ext($0) == "md" }.prefix(30)
        let wiki = mds.filter { (a.text($0) ?? "").contains("[[") }.count
        if mds.count >= 3 && wiki * 3 >= mds.count { return .obsidian }
        return .markdown
    }
}

// MARK: - Parsers

enum ImportParsers {
    static func parse(_ a: ImportArchive, as source: ImportSource) -> ImportBundle {
        switch source {
        case .notion: return notion(a)
        case .obsidian: return obsidian(a)
        case .evernote: return evernote(a)
        case .keep: return keep(a)
        case .textbundle: return textbundle(a)
        case .markdown, .notionAPI: return generic(a)
        }
    }

    private static func key(_ path: String) -> String {
        let p = ImportPaths.normalize(path)
        return (p as NSString).deletingPathExtension
    }

    /// A page from a markdown file, with its title, blocks and images.
    private static func markdownPage(_ a: ImportArchive, path: String, title fallback: String) -> ImportedPage? {
        guard let text = a.text(path) else { return nil }
        let dir = ImportPaths.dir(path)
        let isHTML = ["html", "htm"].contains(ImportPaths.ext(path))
        let md = isHTML ? HTMLImport.toMarkdown(text) : text
        let r = MarkdownImport.parse(md, dir: dir)
        var p = ImportedPage(key: key(path), title: r.title ?? fallback, blocks: r.blocks)
        p.imagePaths = r.images
        p.dir = dir
        if !r.frontMatter.isEmpty { p.blocks.insert(propertiesCallout(r.frontMatter), at: 0) }
        return p
    }

    private static func propertiesCallout(_ fm: [(String, String)]) -> NoteBlock {
        var b = NoteBlock(kind: .callout, text: fm.map { "**\($0.0)**: \($0.1)" }.joined(separator: "\n"))
        b.icon = "🏷️"; b.color = "bg:gray"
        return b
    }

    // MARK: Workspace export (Markdown & CSV)

    static func notion(_ a: ImportArchive) -> ImportBundle {
        var warnings: [String] = []
        let paths = a.paths
        // Drop the export's own wrapper folder so the top pages are top-level.
        let root = commonRoot(paths)

        // Keys are full paths without the extension, the same way links are resolved.
        var pages: [String: ImportedPage] = [:]
        var order: [String] = []
        for p in paths where ["md", "html"].contains(ImportPaths.ext(p)) {
            let title = ImportPaths.stripId(ImportPaths.stem(p))
            guard var page = markdownPage(a, path: p, title: title) else { continue }
            // Parent: the page whose folder this file is in ("Parent 1a2b/Child 3c4d.md").
            let parentDir = ImportPaths.dir(p)
            if !parentDir.isEmpty, parentDir != root { page.parentKey = parentDir }
            // Workspace exports start pages with icons as the first character of the title sometimes.
            if let f = page.title.first, f.unicodeScalars.first?.properties.isEmojiPresentation == true, page.title.count > 2 {
                page.icon = String(f); page.title = String(page.title.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            pages[page.key] = page
            order.append(page.key)
        }

        // Databases: CSV + a folder of row pages.
        var csvs = paths.filter { ImportPaths.ext($0) == "csv" }
        let allVariants = Set(csvs.filter { $0.hasSuffix("_all.csv") })
        csvs = csvs.filter { !allVariants.contains($0.replacingOccurrences(of: ".csv", with: "_all.csv")) }   // prefer the complete "_all" file
        for c in csvs {
            guard let text = a.text(c) else { continue }
            let rows = Importer.parseCSV(text)
            guard let header = rows.first, !header.isEmpty else { continue }
            let dbKey = key(c).replacingOccurrences(of: "_all", with: "")
            var db = pages[dbKey] ?? ImportedPage(key: dbKey, title: ImportPaths.stripId(ImportPaths.stem(c).replacingOccurrences(of: "_all", with: "")))
            db.isDatabase = true
            db.icon = db.icon ?? "🗃️"
            db.blocks = []
            let parentDir = ImportPaths.dir(c)
            db.parentKey = parentDir.isEmpty || parentDir == root ? nil : parentDir
            db.schema = inferSchema(header: header, rows: Array(rows.dropFirst()))
            if pages[dbKey] == nil { order.append(dbKey) }
            pages[dbKey] = db
            // Match each row to its page in the database's folder by title.
            let rowPrefix = dbKey + "/"
            var byTitle: [String: String] = [:]
            for (k, p) in pages where k.hasPrefix(rowPrefix) && !k.dropFirst(rowPrefix.count).contains("/") { byTitle[p.title.lowercased()] = k }
            for r in rows.dropFirst() {
                let title = r.first?.trimmingCharacters(in: .whitespaces) ?? ""
                var props: [String: String] = [:]
                for (i, h) in header.enumerated() where i > 0 && i < r.count {
                    let v = r[i].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !v.isEmpty { props[h] = v }
                }
                if let k = byTitle[title.lowercased()], var rowPage = pages[k] {
                    rowPage.parentKey = dbKey
                    rowPage.props = props
                    rowPage.blocks = stripPropertyLines(rowPage.blocks, names: Set(header.map { $0.lowercased() }))
                    pages[k] = rowPage
                    byTitle[title.lowercased()] = nil
                } else {
                    var rowPage = ImportedPage(key: dbKey + "/row-\(UUID().uuidString)", title: title)
                    rowPage.parentKey = dbKey
                    rowPage.props = props
                    pages[rowPage.key] = rowPage
                    order.append(rowPage.key)
                }
            }
        }
        if paths.contains(where: { ImportPaths.ext($0) == "html" }) && !paths.contains(where: { ImportPaths.ext($0) == "md" }) {
            warnings.append("This is an HTML export. It imports well, but “Markdown & CSV” keeps databases and properties best.")
        }
        let list = order.compactMap { pages[$0] }
        return ImportBundle(source: .notion, name: a.name, pages: list, warnings: warnings)
    }

    /// Row pages repeat their properties as "Status: Done" lines at the top; the database already has them.
    private static func stripPropertyLines(_ blocks: [NoteBlock], names: Set<String>) -> [NoteBlock] {
        var out = blocks
        while let f = out.first, f.kind == .text, let c = f.text.firstIndex(of: ":"),
              names.contains(String(f.text[..<c]).trimmingCharacters(in: .whitespaces).lowercased()) {
            out.removeFirst()
        }
        return out
    }

    /// Picks a property type for each column from its values.
    static func inferSchema(header: [String], rows: [[String]]) -> [DBProperty] {
        var out: [DBProperty] = []
        for (i, h) in header.enumerated() where i > 0 {
            let vals = rows.compactMap { i < $0.count ? $0[i].trimmingCharacters(in: .whitespacesAndNewlines) : nil }.filter { !$0.isEmpty }
            let distinct = Array(Set(vals)).sorted()
            let name = h.lowercased()
            var kind: DBProperty.Kind = .text
            if !vals.isEmpty && vals.allSatisfy({ ["yes", "no", "true", "false", "checked", "unchecked", "☑", "☐"].contains($0.lowercased()) }) { kind = .checkbox }
            else if !vals.isEmpty && vals.allSatisfy({ Double($0.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")) != nil }) { kind = .number }
            else if !vals.isEmpty && vals.allSatisfy({ $0.hasPrefix("http") }) { kind = .url }
            else if !vals.isEmpty && vals.allSatisfy({ ImportDates.parse($0) != nil }) || name.contains("date") || name.contains("due") { kind = .date }
            else if name == "status" || name == "state" || name == "stage" { kind = .status }
            else if vals.contains(where: { $0.contains(", ") }) && distinct.count > 1 && (name.contains("tag") || name.contains("label") || name.contains("categor") || Set(vals.flatMap { $0.components(separatedBy: ", ") }).count <= 30) { kind = .multiSelect }
            else if !vals.isEmpty && distinct.count <= max(8, vals.count / 3) && distinct.allSatisfy({ $0.count <= 40 }) { kind = .select }
            var p = DBProperty(name: h, kind: kind)
            switch kind {
            case .select, .status: p.options = distinct
            case .multiSelect: p.options = Array(Set(vals.flatMap { $0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } })).filter { !$0.isEmpty }.sorted()
            default: break
            }
            out.append(p)
        }
        return out
    }

    // MARK: Vault (wiki links, embeds, folders)

    static func obsidian(_ a: ImportArchive) -> ImportBundle {
        let paths = a.paths.filter { !$0.contains(".obsidian/") && !$0.contains(".trash/") }
        let root = commonRoot(paths)
        func rel(_ p: String) -> String { root.isEmpty ? p : String(p.dropFirst(root.count + 1)) }
        var pages: [ImportedPage] = []
        var folderPages: [String: ImportedPage] = [:]

        func folderKey(_ dir: String) -> String? {
            let parts = dir.split(separator: "/").map(String.init)
            guard parts.count >= 2 else { return nil }              // the top folder becomes a Keel folder, not a page
            for n in 2...parts.count {
                let sub = parts.prefix(n).joined(separator: "/")
                if folderPages["folder:" + sub] == nil {
                    var fp = ImportedPage(key: "folder:" + sub, title: parts[n - 1], icon: "📁")
                    fp.folder = parts[0]
                    fp.parentKey = n > 2 ? "folder:" + parts.prefix(n - 1).joined(separator: "/") : nil
                    folderPages[fp.key] = fp
                }
            }
            return "folder:" + dir
        }

        for p in paths where ImportPaths.ext(p) == "md" {
            let r = rel(p)
            let stem = ImportPaths.stem(p)
            guard var page = markdownPage(a, path: p, title: stem) else { continue }
            if page.title != stem, !page.blocks.isEmpty {            // a vault note's name is its file name
                page.blocks.insert(NoteBlock(kind: .heading, text: page.title), at: 0)
                page.title = stem
            }
            page.key = key(p)
            let dir = ImportPaths.dir(r)
            page.folder = dir.isEmpty ? nil : String(dir.split(separator: "/").first ?? "")
            page.parentKey = folderKey(dir)
            pages.append(page)
        }
        return ImportBundle(source: .obsidian, name: a.name, pages: Array(folderPages.values) + pages,
                            warnings: a.paths.contains(where: { $0.hasSuffix(".canvas") }) ? ["Canvas files aren't imported; their notes are."] : [])
    }

    // MARK: Evernote (.enex)

    static func evernote(_ a: ImportArchive) -> ImportBundle {
        var pages: [ImportedPage] = []
        var warnings: [String] = []
        for p in a.paths where ImportPaths.ext(p) == "enex" {
            guard let xml = a.text(p) else { continue }
            let notebook = ImportPaths.stem(p)
            for chunk in xml.components(separatedBy: "<note>").dropFirst() {
                let title = HTMLImport.entities(between(chunk, "<title>", "</title>") ?? "Untitled")
                var content = between(chunk, "<content>", "</content>") ?? ""
                content = content.replacingOccurrences(of: "<![CDATA[", with: "").replacingOccurrences(of: "]]>", with: "")
                // Attachments: base64 data, matched to <en-media hash> by MD5.
                var media: [String: Data] = [:]
                for res in chunk.components(separatedBy: "<resource>").dropFirst() {
                    guard let b64 = between(res, ">", "</data>").map({ $0.components(separatedBy: ">").last ?? $0 }),
                          let mime = between(res, "<mime>", "</mime>"), mime.hasPrefix("image/"),
                          let d = Data(base64Encoded: b64.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: ""), options: .ignoreUnknownCharacters) else { continue }
                    media[Insecure.MD5.hash(data: d).map { String(format: "%02x", $0) }.joined()] = d
                }
                let r = MarkdownImport.parse(HTMLImport.toMarkdown(content), dir: "")
                var page = ImportedPage(key: "enex:\(p):\(pages.count)", title: title, blocks: r.blocks)
                for (id, ref) in r.images {
                    if ref.hasPrefix("enmedia:"), let d = media[String(ref.dropFirst(8))] { page.imageData[id] = d }
                }
                page.blocks.removeAll { $0.kind == .image && page.imageData[$0.id] == nil }
                page.folder = notebook
                page.created = between(chunk, "<created>", "</created>").flatMap(ImportDates.enex)
                page.updated = between(chunk, "<updated>", "</updated>").flatMap(ImportDates.enex)
                let tags = chunk.components(separatedBy: "<tag>").dropFirst().compactMap { $0.components(separatedBy: "</tag>").first }
                if !tags.isEmpty { page.blocks.insert(propertiesCallout([("Tags", tags.joined(separator: ", "))]), at: 0) }
                pages.append(page)
            }
            if xml.contains("<resource>") && !xml.contains("image/") { warnings.append("PDFs and other attachments aren't imported, only images.") }
        }
        return ImportBundle(source: .evernote, name: a.name, pages: pages, warnings: warnings)
    }

    // MARK: Google Keep (Takeout)

    static func keep(_ a: ImportArchive) -> ImportBundle {
        var pages: [ImportedPage] = []
        for p in a.paths where ImportPaths.ext(p) == "json" && p.lowercased().contains("keep/") {
            guard let d = a.data(p), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  j["isTrashed"] as? Bool != true else { continue }
            let dir = ImportPaths.dir(p)
            var blocks: [NoteBlock] = []
            if let text = j["textContent"] as? String, !text.isEmpty {
                blocks += MarkdownImport.parse(text, dir: dir).blocks
            }
            for item in (j["listContent"] as? [[String: Any]]) ?? [] {
                blocks.append(NoteBlock(kind: .todo, text: item["text"] as? String ?? "", checked: item["isChecked"] as? Bool ?? false))
            }
            var page = ImportedPage(key: key(p), title: (j["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Keep note", blocks: blocks)
            for att in (j["attachments"] as? [[String: Any]]) ?? [] {
                guard let f = att["filePath"] as? String, (att["mimetype"] as? String ?? "").hasPrefix("image") else { continue }
                let b = NoteBlock(kind: .image, text: "")
                page.blocks.append(b)
                page.imagePaths[b.id] = ImportPaths.resolve(f, from: dir)
            }
            page.folder = ((j["labels"] as? [[String: Any]])?.first?["name"] as? String) ?? "Keep"
            page.pinned = j["isPinned"] as? Bool ?? false
            if let us = j["createdTimestampUsec"] as? Double { page.created = Date(timeIntervalSince1970: us / 1_000_000) }
            if let us = j["userEditedTimestampUsec"] as? Double { page.updated = Date(timeIntervalSince1970: us / 1_000_000) }
            if j["isArchived"] as? Bool == true { page.blocks.insert(NoteBlock(kind: .text, text: "*Archived in Keep*"), at: 0) }
            if page.blocks.isEmpty { page.blocks = [NoteBlock(kind: .text, text: "")] }
            pages.append(page)
        }
        return ImportBundle(source: .keep, name: a.name, pages: pages)
    }

    // MARK: TextBundle / Bear / Ulysses-style bundles

    static func textbundle(_ a: ImportArchive) -> ImportBundle {
        var pages: [ImportedPage] = []
        let bundles = Set(a.paths.compactMap { p -> String? in
            guard let r = p.range(of: ".textbundle/") else { return nil }
            return String(p[..<r.lowerBound]) + ".textbundle"
        })
        for b in bundles.sorted() {
            guard let textPath = ["text.md", "text.markdown", "text.txt"].map({ b + "/" + $0 }).first(where: a.exists),
                  var page = markdownPage(a, path: textPath, title: ImportPaths.stem(b)) else { continue }
            page.key = b
            pages.append(page)
        }
        // Plain markdown files alongside bundles.
        var rest = generic(a).pages.filter { p in !bundles.contains { p.key.hasPrefix($0) } }
        rest.removeAll { $0.key.contains(".textbundle/") }
        return ImportBundle(source: .textbundle, name: a.name, pages: pages + rest)
    }

    // MARK: Anything else: .md, .txt, .html, and CSV as databases

    static func generic(_ a: ImportArchive) -> ImportBundle {
        var pages: [ImportedPage] = []
        let root = commonRoot(a.paths)
        func rel(_ p: String) -> String { root.isEmpty ? p : String(p.dropFirst(root.count + 1)) }
        for p in a.paths {
            let ext = ImportPaths.ext(p)
            let dir = ImportPaths.dir(rel(p))
            let folder = dir.isEmpty ? nil : String(dir.split(separator: "/").first ?? "")
            switch ext {
            case "md", "markdown", "html", "htm":
                if var page = markdownPage(a, path: p, title: ImportPaths.stem(p)) { page.folder = folder; pages.append(page) }
            case "txt":
                guard let t = a.text(p) else { continue }
                var paras = t.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                var title = ImportPaths.stem(p)
                if let first = paras.first, first.count < 80, !first.contains("\n") { title = first; paras.removeFirst() }
                var page = ImportedPage(key: key(p), title: title, blocks: paras.map { NoteBlock(kind: .text, text: $0) })
                page.folder = folder
                pages.append(page)
            case "csv":
                guard let t = a.text(p) else { continue }
                let rows = Importer.parseCSV(t)
                guard let header = rows.first, header.count >= 1 else { continue }
                var db = ImportedPage(key: key(p), title: ImportPaths.stem(p), icon: "🗃️")
                db.isDatabase = true; db.folder = folder
                db.schema = inferSchema(header: header, rows: Array(rows.dropFirst()))
                pages.append(db)
                for r in rows.dropFirst() {
                    var row = ImportedPage(key: db.key + "/row-\(UUID().uuidString)", title: r.first ?? "")
                    row.parentKey = db.key
                    for (i, h) in header.enumerated() where i > 0 && i < r.count && !r[i].isEmpty { row.props[h] = r[i] }
                    pages.append(row)
                }
            default: continue
            }
        }
        return ImportBundle(source: .markdown, name: a.name, pages: pages)
    }

    // MARK: Helpers

    /// The single folder everything sits in (an export's wrapper), if there is one.
    static func commonRoot(_ paths: [String]) -> String {
        let firsts = Set(paths.compactMap { p -> String? in p.contains("/") ? String(p.split(separator: "/").first!) : "" })
        guard firsts.count == 1, let only = firsts.first, !only.isEmpty else { return "" }
        return only
    }

    static func between(_ s: String, _ a: String, _ b: String) -> String? {
        guard let r1 = s.range(of: a), let r2 = s.range(of: b, range: r1.upperBound..<s.endIndex) else { return nil }
        return String(s[r1.upperBound..<r2.lowerBound])
    }
}

enum ImportDates {
    static func parse(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count >= 6, t.count <= 40, t.rangeOfCharacter(from: .decimalDigits) != nil else { return nil }
        if let d = try? Date(t, strategy: .iso8601) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd", "MMMM d, yyyy", "MMMM d, yyyy h:mm a", "MMM d, yyyy", "MM/dd/yyyy", "d MMMM yyyy", "yyyy/MM/dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: t) { return d }
        }
        // "March 3, 2024 → March 5, 2024": take the start.
        if let arrow = t.range(of: " → ") { return parse(String(t[..<arrow.lowerBound])) }
        return nil
    }

    static func enex(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.date(from: s)
    }
}
