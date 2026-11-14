import SwiftUI

// MARK: - Block catalog (the "/" menu)

struct SlashCommand: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let keywords: [String]
    let kind: BlockKind

    static let all: [SlashCommand] = [
        .init(id: "text", title: "Text", subtitle: "Plain writing", icon: "text.alignleft", keywords: ["paragraph", "plain"], kind: .text),
        .init(id: "h1", title: "Heading 1", subtitle: "Big section heading", icon: "textformat.size.larger", keywords: ["h1", "title"], kind: .heading),
        .init(id: "h2", title: "Heading 2", subtitle: "Medium heading", icon: "textformat.size", keywords: ["h2", "subtitle"], kind: .heading2),
        .init(id: "h3", title: "Heading 3", subtitle: "Small heading", icon: "textformat.size.smaller", keywords: ["h3"], kind: .heading3),
        .init(id: "todo", title: "To-do list", subtitle: "Track tasks with a checkbox", icon: "checkmark.square", keywords: ["checkbox", "task", "check"], kind: .todo),
        .init(id: "bullet", title: "Bulleted list", subtitle: "A simple list", icon: "list.bullet", keywords: ["ul", "list", "-"], kind: .bullet),
        .init(id: "numbered", title: "Numbered list", subtitle: "A list with numbers", icon: "list.number", keywords: ["ol", "1."], kind: .numbered),
        .init(id: "toggle", title: "Toggle", subtitle: "Hide details inside", icon: "chevron.right.square", keywords: ["collapse", "details", "accordion"], kind: .toggle),
        .init(id: "callout", title: "Callout", subtitle: "Make something stand out", icon: "exclamationmark.bubble", keywords: ["note", "tip", "info", "warning"], kind: .callout),
        .init(id: "quote", title: "Quote", subtitle: "Capture a quote", icon: "text.quote", keywords: ["blockquote"], kind: .quote),
        .init(id: "code", title: "Code", subtitle: "Monospaced snippet", icon: "chevron.left.forwardslash.chevron.right", keywords: ["snippet", "pre"], kind: .code),
        .init(id: "table", title: "Table", subtitle: "Simple rows and columns", icon: "tablecells", keywords: ["grid", "columns"], kind: .table),
        .init(id: "divider", title: "Divider", subtitle: "Separate sections", icon: "minus", keywords: ["line", "hr", "---"], kind: .divider),
        .init(id: "page", title: "Page", subtitle: "A sub-page inside this one", icon: "doc", keywords: ["subpage", "nested"], kind: .page),
        .init(id: "bookmark", title: "Web bookmark", subtitle: "Save a link", icon: "link", keywords: ["url", "link", "web"], kind: .bookmark),
        .init(id: "image", title: "Image", subtitle: "Photo from your library", icon: "photo", keywords: ["picture", "photo"], kind: .image),
        .init(id: "ai", title: "Ask AI", subtitle: "Write, brainstorm or draft with the model you choose", icon: "sparkles", keywords: ["ai", "write", "draft", "generate", "brainstorm", "claude", "chatgpt", "gemini", "gpt"], kind: .text),
        .init(id: "meeting", title: "AI meeting notes", subtitle: "Record, transcribe and write up with context", icon: "waveform.badge.mic", keywords: ["meeting", "record", "transcribe", "notes", "ai"], kind: .text),
    ] + SpecialBlock.commands + SpecialBlock.moreCommands

    static func matching(_ query: String) -> [SlashCommand] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { $0.title.lowercased().contains(q) || $0.keywords.contains { $0.hasPrefix(q) } }
    }
}

// MARK: - Colors

enum BlockColor: String, CaseIterable {
    case gray, brown, red, orange, yellow, green, blue, purple, pink
    var color: Color {
        switch self {
        case .gray: .gray; case .brown: .brown; case .red: .red; case .orange: .orange; case .yellow: .yellow
        case .green: .green; case .blue: .blue; case .purple: .purple; case .pink: .pink
        }
    }

    /// Workspace colour names ("blue", "red_background", "teal") → Keel's ("blue", "bg:red", "green").
    static func fromWorkspace(_ raw: String?) -> String? {
        guard var r = raw?.lowercased(), r != "default", !r.isEmpty else { return nil }
        let bg = r.hasSuffix("_background")
        r = r.replacingOccurrences(of: "_background", with: "")
        let map = ["teal": "green", "grey": "gray", "default": ""]
        r = map[r] ?? r
        guard BlockColor(rawValue: r) != nil else { return nil }
        return bg ? "bg:" + r : r
    }
    /// "blue" → text color; "bg:blue" → background.
    static func parse(_ raw: String?) -> (text: Color?, background: Color?) {
        guard let raw else { return (nil, nil) }
        if raw.hasPrefix("bg:") { return (nil, BlockColor(rawValue: String(raw.dropFirst(3)))?.color.opacity(0.15)) }
        return (BlockColor(rawValue: raw)?.color, nil)
    }
}

// MARK: - Inline rich text

/// Renders inline markdown (**bold**, *italic*, `code`, [link](url), ~~strike~~) plus ==highlight==.
enum RichText {
    static func render(_ text: String) -> AttributedString {
        guard text.contains("{") else { return renderBasic(text) }
        // Coloured and underlined spans: {c:red}text{/}, {b:yellow}text{/}, {u}text{/}
        guard let re = try? NSRegularExpression(pattern: #"\{(c|b):([a-z]+)\}(.*?)\{/\}|\{u\}(.*?)\{/\}"#) else { return renderBasic(text) }
        let ns = text as NSString
        var out = AttributedString()
        var last = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > last { out += renderBasic(ns.substring(with: NSRange(location: last, length: m.range.location - last))) }
            if m.range(at: 4).location != NSNotFound {
                var seg = render(ns.substring(with: m.range(at: 4)))
                seg.underlineStyle = .single
                out += seg
            } else {
                var seg = render(ns.substring(with: m.range(at: 3)))
                let c = BlockColor(rawValue: ns.substring(with: m.range(at: 2)))?.color
                if ns.substring(with: m.range(at: 1)) == "c" { seg.foregroundColor = c } else { seg.backgroundColor = c?.opacity(0.25) }
                out += seg
            }
            last = m.range.location + m.range.length
        }
        if last < ns.length { out += renderBasic(ns.substring(from: last)) }
        return out
    }

    /// Text without Keel's colour and underline markers (for search, AI and exports).
    static func plain(_ text: String) -> String {
        guard text.contains("{") else { return text }
        return text.replacingOccurrences(of: #"\{(c|b):[a-z]+\}|\{u\}|\{/\}"#, with: "", options: .regularExpression)
    }

    private static func renderBasic(_ text: String) -> AttributedString {
        // "a ==b== c" → segments [a, b, c]; odd segments are highlighted.
        let parts = text.components(separatedBy: "==")
        var out = AttributedString()
        for (i, part) in parts.enumerated() {
            var seg = (try? AttributedString(markdown: part, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(part)
            if i % 2 == 1 && i < parts.count - 1 { seg.backgroundColor = .yellow.opacity(0.35) }
            else if i % 2 == 1 { seg = AttributedString("==") + seg }        // unmatched marker: show it as typed
            out += seg
        }
        return out
    }

    static let pageScheme = "com.keel.app"
    static func pageURL(_ id: UUID) -> String { "\(pageScheme)://note/\(id.uuidString)" }
    static func pageId(from url: URL) -> UUID? {
        guard url.scheme == pageScheme, url.host == "note" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }

    /// Wraps the selected range in markers, or inserts an empty pair at the end.
    static func wrap(_ text: inout String, selection: TextSelection?, left: String, right: String) {
        if case .selection(let range)? = selection?.indices, !range.isEmpty,
           range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex {
            let inner = String(text[range])
            text.replaceSubrange(range, with: left + inner + right)
        } else {
            text += left + right
        }
    }
}

// MARK: - Table block

struct TableBlockView: View {
    @Binding var rows: [[String]]?

    private var grid: [[String]] { rows ?? [["Column 1", "Column 2"], ["", ""]] }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(grid.indices, id: \.self) { r in
                        GridRow {
                            ForEach(grid[r].indices, id: \.self) { c in
                                TextField("", text: cell(r, c), axis: .vertical)
                                    .font(r == 0 ? DS.Font.headline : DS.Font.body)
                                    .padding(8).frame(width: 140, alignment: .leading)
                                    .background(r == 0 ? DS.Palette.elevated : Color.clear)
                                    .overlay(Rectangle().stroke(Color.secondary.opacity(0.25), lineWidth: 0.5))
                            }
                        }
                    }
                }
            }
            HStack {
                Button("+ Row") { var g = grid; g.append(Array(repeating: "", count: g.first?.count ?? 2)); rows = g }
                Button("+ Column") { rows = grid.enumerated().map { i, row in row + [i == 0 ? "Column \(row.count + 1)" : ""] } }
                if grid.count > 2 { Button("− Row") { var g = grid; g.removeLast(); rows = g } }
                if (grid.first?.count ?? 0) > 1 { Button("− Column") { rows = grid.map { Array($0.dropLast()) } } }
            }
            .font(DS.Font.caption).buttonStyle(.borderless).foregroundStyle(DS.Palette.inkSoft)
        }
    }

    private func cell(_ r: Int, _ c: Int) -> Binding<String> {
        Binding(get: { let g = grid; return r < g.count && c < g[r].count ? g[r][c] : "" },
                set: { v in var g = grid; if r < g.count && c < g[r].count { g[r][c] = v; rows = g } })
    }
}
