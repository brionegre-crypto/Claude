import SwiftUI
import SwiftData

// MARK: - Notes search: every page, every line, every field
//
// Search reads each page once into a small text index (refreshed only when a page changes), so typing a query
// scans prepared text instead of rebuilding every page on every keystroke. It looks in titles, every line of
// text, toggles, callouts, code, tables, database fields and text read from scanned images. Matching ignores
// case, accents and curly vs straight quotes, so "cafe" finds "Café" and "don't" finds "don’t".

/// Your search choices (Notes → search → Options, or Settings → Customize Keel → Notes).
enum NoteSearchPrefs {
    static let matchKey = "notes.search.match"
    static let scopeKey = "notes.search.scope"
    static let sortKey = "notes.search.sort"
    static let wholeWordsKey = "notes.search.wholeWords"
    static let templatesKey = "notes.search.templates"
    static let snippetsKey = "notes.search.snippets"
    static let recentsOnKey = "notes.search.recentsOn"
    static let recentsKey = "notes.search.recents"

    enum Match: String, CaseIterable, Identifiable {
        case all = "All words", phrase = "Exact phrase", any = "Any word"
        var id: String { rawValue }
        var help: String {
            switch self {
            case .all: "Pages that contain every word, in any order."
            case .phrase: "Pages that contain the words together, exactly as typed."
            case .any: "Pages that contain at least one of the words."
            }
        }
    }
    enum Scope: String, CaseIterable, Identifiable {
        case everything = "Titles and text", titles = "Titles only"
        var id: String { rawValue }
    }
    enum Sort: String, CaseIterable, Identifiable {
        case best = "Best match", recent = "Recently edited", alpha = "A to Z"
        var id: String { rawValue }
    }

    static var recents: [String] {
        get { UserDefaults.standard.stringArray(forKey: recentsKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(8)), forKey: recentsKey) }
    }
    static func remember(_ q: String) {
        let t = q.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2, UserDefaults.standard.object(forKey: recentsOnKey) as? Bool ?? true else { return }
        recents = [t] + recents.filter { $0.caseInsensitiveCompare(t) != .orderedSame }
    }
}

// MARK: Query

/// What you typed, understood. Plain words, "exact phrases", -excluded words, and a few filters:
/// in:Folder  title:word  #tag  is:pinned  is:todo  is:database  edited:today|week|month|year
struct NoteQuery: Equatable {
    var terms: [String] = []          // folded words or, in phrase mode, one phrase
    var phrases: [String] = []        // "quoted" always means exactly this
    var excluded: [String] = []
    var titleTerms: [String] = []
    var folders: [String] = []
    var tags: [String] = []           // folded "#tag"
    var pinned = false, openTodos = false, database = false
    var editedSince: Date?

    var hasText: Bool { !terms.isEmpty || !phrases.isEmpty || !titleTerms.isEmpty || !tags.isEmpty }
    var isEmpty: Bool { !hasText && folders.isEmpty && !pinned && !openTodos && !database && editedSince == nil }
    /// Everything that should light up in a preview.
    var highlights: [String] { (phrases + terms + titleTerms + tags).filter { !$0.isEmpty }.sorted { $0.count > $1.count } }

    static func parse(_ raw: String, match: NoteSearchPrefs.Match) -> NoteQuery {
        var q = NoteQuery()
        var loose: [String] = []
        for token in tokenize(NoteText.straighten(raw)) {
            if token.quoted { let f = NoteText.fold(token.text); if !f.isEmpty { q.phrases.append(f) }; continue }
            let t = token.text
            let lower = t.lowercased()
            if lower.hasPrefix("-"), t.count > 1 { q.excluded.append(NoteText.fold(String(t.dropFirst()))); continue }
            if lower.hasPrefix("in:"), t.count > 3 { q.folders.append(NoteText.fold(String(t.dropFirst(3)))); continue }
            if lower.hasPrefix("title:"), t.count > 6 { q.titleTerms.append(NoteText.fold(String(t.dropFirst(6)))); continue }
            if lower.hasPrefix("#"), t.count > 1 { q.tags.append(NoteText.fold(t)); continue }
            switch lower {
            case "is:pinned", "is:favorite", "is:starred": q.pinned = true; continue
            case "is:todo", "has:todo": q.openTodos = true; continue
            case "is:database", "is:db": q.database = true; continue
            default: break
            }
            if lower.hasPrefix("edited:") {
                let cal = Calendar.current, now = Date()
                switch lower.dropFirst(7) {
                case "today": q.editedSince = cal.startOfDay(for: now)
                case "yesterday": q.editedSince = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now))
                case "week": q.editedSince = cal.date(byAdding: .day, value: -7, to: now)
                case "month": q.editedSince = cal.date(byAdding: .month, value: -1, to: now)
                case "year": q.editedSince = cal.date(byAdding: .year, value: -1, to: now)
                default: loose.append(t)
                }
                continue
            }
            loose.append(t)
        }
        let folded = loose.map(NoteText.fold).filter { !$0.isEmpty }
        if match == .phrase, folded.count > 1 { q.terms = [folded.joined(separator: " ")] } else { q.terms = folded }
        return q
    }

    private static func tokenize(_ s: String) -> [(text: String, quoted: Bool)] {
        var out: [(String, Bool)] = []
        var cur = "", inQuote = false
        for ch in s {
            if ch == "\"" {
                if inQuote { out.append((cur, true)); cur = "" } else if !cur.isEmpty { out.append((cur, false)); cur = "" }
                inQuote.toggle()
            } else if ch.isWhitespace && !inQuote {
                if !cur.isEmpty { out.append((cur, false)); cur = "" }
            } else { cur.append(ch) }
        }
        if !cur.isEmpty { out.append((cur, inQuote)) }      // an unclosed quote still counts as a phrase
        return out
    }
}

// MARK: Text helpers

enum NoteText {
    /// Curly quotes, dashes and non-breaking spaces as typed on a keyboard, and one space between words.
    static func straighten(_ s: String) -> String {
        var t = s
        for (a, b) in [("\u{2018}", "'"), ("\u{2019}", "'"), ("\u{201C}", "\""), ("\u{201D}", "\""),
                       ("\u{2013}", "-"), ("\u{2014}", "-"), ("\u{00A0}", " ")] where t.contains(a) {
            t = t.replacingOccurrences(of: a, with: b)
        }
        return t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    /// For matching: no case, no accents, no width differences.
    static func fold(_ s: String) -> String {
        straighten(s).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
    static let compare: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    /// How many times `term` appears in already-folded `text` (stops counting at `cap`).
    static func count(_ term: String, in text: String, wholeWords: Bool, cap: Int = 50) -> Int {
        guard !term.isEmpty, text.count >= term.count else { return 0 }
        var n = 0
        var from = text.startIndex
        while n < cap, let r = text.range(of: term, range: from..<text.endIndex) {
            if !wholeWords || isWordBoundary(text, r) { n += 1 }
            from = r.upperBound
        }
        return n
    }
    static func isWordBoundary(_ text: String, _ r: Range<String.Index>) -> Bool {
        let before = r.lowerBound > text.startIndex ? text[text.index(before: r.lowerBound)] : " "
        let after = r.upperBound < text.endIndex ? text[r.upperBound] : " "
        return !(before.isLetter || before.isNumber) && !(after.isLetter || after.isNumber)
    }
}

// MARK: Index

/// One searchable piece of a page: a line, a table, a database field, or scanned-image text.
struct NotePart {
    enum Kind: String { case text = "Text", table = "Table", field = "Database field", code = "Code", scan = "Scanned image" }
    let kind: Kind
    let blockId: UUID?
    let display: String       // shown in previews
    let folded: String        // matched against
}

@MainActor
enum NoteSearchIndex {
    private struct Entry { let stamp: Date; let titleFolded: String; let parts: [NotePart]; let hasOpenTodos: Bool }
    private static var entries: [UUID: Entry] = [:]
    /// Text read from scanned images and photos, by page. Refreshed each time a search starts.
    private static var scans: [UUID: [NotePart]] = [:]

    private static func entry(_ n: Note) -> Entry {
        if let e = entries[n.id], e.stamp == n.updatedAt { return e }
        var parts: [NotePart] = []
        var todos = false
        if !n.isLocked {                                     // locked pages: title only (as before, by design)
            for b in n.blocks {
                if b.kind == .todo && !b.checked { todos = true }
                let line = RichText.plain(b.text)
                if !line.isEmpty { add(&parts, b.kind == .code ? .code : .text, b.id, line) }
                if let body = b.body, !body.isEmpty { add(&parts, .text, b.id, RichText.plain(body)) }
                if let rows = b.rows {
                    for row in rows { let r = row.filter { !$0.isEmpty }.joined(separator: " · "); if !r.isEmpty { add(&parts, .table, b.id, r) } }
                }
                if b.kind == .bookmark, let url = b.refId, !url.isEmpty { add(&parts, .text, b.id, url) }
            }
            // Database fields: only real columns (their keys are ids), not Keel's own bookkeeping.
            for (key, value) in n.props where UUID(uuidString: key) != nil && !value.isEmpty {
                add(&parts, .field, nil, value)
            }
        }
        let e = Entry(stamp: n.updatedAt, titleFolded: NoteText.fold(n.title), parts: parts, hasOpenTodos: todos)
        entries[n.id] = e
        return e
    }
    private static func add(_ parts: inout [NotePart], _ kind: NotePart.Kind, _ id: UUID?, _ text: String) {
        let display = NoteText.straighten(text)
        guard !display.isEmpty else { return }
        parts.append(NotePart(kind: kind, blockId: id, display: display, folded: NoteText.fold(display)))
    }

    /// Prepares the index a little at a time, so the first search is instant without stalling Notes.
    static func warm(_ notes: [Note]) async {
        for (i, n) in notes.enumerated() {
            _ = entry(n)
            if i % 40 == 39 { await Task.yield(); if Task.isCancelled { return } }
        }
    }

    static func refreshScans(_ ctx: ModelContext) {
        var d = FetchDescriptor<NoteAttachment>(predicate: #Predicate { $0.recognizedText != "" })
        d.propertiesToFetch = [\.noteId, \.recognizedText]
        let found = (try? ctx.fetch(d)) ?? []
        var out: [UUID: [NotePart]] = [:]
        for a in found {
            let display = NoteText.straighten(a.recognizedText)
            out[a.noteId, default: []].append(NotePart(kind: .scan, blockId: nil, display: display, folded: NoteText.fold(display)))
        }
        scans = out
    }

    struct Hit: Identifiable {
        let note: Note
        var id: UUID { note.id }
        let score: Double
        let matches: Int
        let inTitle: Bool
        let foundIn: [NotePart.Kind]
        let jumpTo: UUID?
        let preview: NotePart?
    }

    static func search(_ q: NoteQuery, in notes: [Note], scope: NoteSearchPrefs.Scope, match: NoteSearchPrefs.Match,
                       wholeWords: Bool, sort: NoteSearchPrefs.Sort) -> [Hit] {
        guard !q.isEmpty else { return [] }
        let now = Date()
        var hits: [Hit] = []
        let titlesOnly = scope == .titles
        let required = q.phrases + (match == .any ? [] : q.terms) + q.tags
        let anyOf = match == .any ? q.terms : []

        for n in notes {
            if q.pinned && !n.isPinned { continue }
            if q.database && !n.isDatabase { continue }
            if let since = q.editedSince, n.updatedAt < since { continue }
            if !q.folders.isEmpty {
                let f = NoteText.fold(n.folder ?? "")
                guard q.folders.contains(where: { f == $0 || f.hasPrefix($0 + "/") || f.contains($0) }) else { continue }
            }
            let e = entry(n)
            if q.openTodos && !e.hasOpenTodos { continue }
            var parts: [NotePart] = []
            if !titlesOnly {
                parts = e.parts
                if !n.isLocked, let s = scans[n.id] { parts += s }
            }

            func found(_ term: String) -> (title: Int, body: Int, first: NotePart?, kinds: Set<NotePart.Kind>) {
                let t = NoteText.count(term, in: e.titleFolded, wholeWords: wholeWords)
                var b = 0, first: NotePart?, kinds = Set<NotePart.Kind>()
                for p in parts {
                    let c = NoteText.count(term, in: p.folded, wholeWords: wholeWords)
                    if c > 0 { b += c; kinds.insert(p.kind); if first == nil { first = p } }
                }
                return (t, b, first, kinds)
            }

            var score = 0.0, total = 0, inTitle = false, ok = true
            var kinds = Set<NotePart.Kind>(), preview: NotePart?
            for term in required {
                let r = found(term)
                if r.title + r.body == 0 { ok = false; break }
                total += r.title + r.body; kinds.formUnion(r.kinds)
                if r.title > 0 {
                    inTitle = true
                    score += 12
                    if e.titleFolded.hasPrefix(term) { score += 6 }
                    if e.titleFolded == term { score += 10 }
                }
                score += Double(min(r.body, 20))
                if preview == nil { preview = r.first }
            }
            guard ok else { continue }
            if !anyOf.isEmpty {
                var any = false
                for term in anyOf {
                    let r = found(term)
                    guard r.title + r.body > 0 else { continue }
                    any = true; total += r.title + r.body; kinds.formUnion(r.kinds)
                    if r.title > 0 { inTitle = true; score += 12 }
                    score += Double(min(r.body, 20))
                    if preview == nil { preview = r.first }
                }
                if !any { continue }
            }
            for term in q.titleTerms {
                let c = NoteText.count(term, in: e.titleFolded, wholeWords: wholeWords)
                if c == 0 { ok = false; break }
                inTitle = true; total += c; score += 15
            }
            guard ok else { continue }
            if q.excluded.contains(where: { x in e.titleFolded.contains(x) || parts.contains { $0.folded.contains(x) } }) { continue }
            // Words found close together in one line beat words scattered over a page.
            if match != .phrase, q.terms.count > 1, parts.contains(where: { p in q.terms.allSatisfy { p.folded.contains($0) } }) { score += 6 }
            let days = now.timeIntervalSince(n.updatedAt) / 86_400
            score += 4 * exp(-days / 30)
            if n.isPinned { score += 2 }
            hits.append(Hit(note: n, score: score, matches: max(total, q.hasText ? 1 : 0), inTitle: inTitle,
                            foundIn: NotePart.Kind.all.filter { kinds.contains($0) }, jumpTo: preview?.blockId, preview: preview))
        }
        switch sort {
        case .best: hits.sort { ($0.score, $0.note.updatedAt) > ($1.score, $1.note.updatedAt) }
        case .recent: hits.sort { $0.note.updatedAt > $1.note.updatedAt }
        case .alpha: hits.sort { $0.note.title.localizedCaseInsensitiveCompare($1.note.title) == .orderedAscending }
        }
        return hits
    }

    /// The matching line, trimmed around the first match, with every match highlighted.
    static func preview(_ part: NotePart, highlights: [String], tint: Color) -> AttributedString {
        let text = part.display
        var start = text.startIndex
        if let first = highlights.lazy.compactMap({ text.range(of: $0, options: NoteText.compare) }).first {
            start = text.index(first.lowerBound, offsetBy: -50, limitedBy: text.startIndex) ?? text.startIndex
            if start > text.startIndex, let space = text[start...].firstIndex(of: " "), space < first.lowerBound {
                start = text.index(after: space)
            }
        }
        let end = text.index(start, offsetBy: 220, limitedBy: text.endIndex) ?? text.endIndex
        let slice = (start > text.startIndex ? "…" : "") + String(text[start..<end]) + (end < text.endIndex ? "…" : "")
        var out = AttributedString(slice)
        for h in highlights {
            var from = slice.startIndex
            while let r = slice.range(of: h, options: NoteText.compare, range: from..<slice.endIndex) {
                if let ar = Range<AttributedString.Index>(r, in: out) {
                    out[ar].backgroundColor = tint.opacity(0.22)
                    out[ar].foregroundColor = DS.Palette.ink
                    out[ar].inlinePresentationIntent = .stronglyEmphasized
                }
                from = r.upperBound
            }
        }
        return out
    }
}

extension NotePart.Kind {
    static let all: [NotePart.Kind] = [.text, .table, .field, .code, .scan]
}

// MARK: - Results

/// Notes search results: every page that contains what you typed, best first, with the matching line shown.
struct NoteSearchResults: View {
    let query: String
    let notes: [Note]
    let templates: [Note]
    var open: (Note, UUID?) -> Void

    @AppStorage(NoteSearchPrefs.matchKey) private var matchRaw = NoteSearchPrefs.Match.all.rawValue
    @AppStorage(NoteSearchPrefs.scopeKey) private var scopeRaw = NoteSearchPrefs.Scope.everything.rawValue
    @AppStorage(NoteSearchPrefs.sortKey) private var sortRaw = NoteSearchPrefs.Sort.best.rawValue
    @AppStorage(NoteSearchPrefs.wholeWordsKey) private var wholeWords = false
    @AppStorage(NoteSearchPrefs.templatesKey) private var includeTemplates = false
    @AppStorage(NoteSearchPrefs.snippetsKey) private var showPreviews = true
    @State private var memo = SearchMemo()
    @State private var limit = 60

    private var match: NoteSearchPrefs.Match { .init(rawValue: matchRaw) ?? .all }
    private var scope: NoteSearchPrefs.Scope { .init(rawValue: scopeRaw) ?? .everything }
    private var sort: NoteSearchPrefs.Sort { .init(rawValue: sortRaw) ?? .best }
    private var parsed: NoteQuery { NoteQuery.parse(query, match: match) }

    /// Re-searched only when the query, a choice, or the pages themselves change, never just to redraw.
    private var hits: [NoteSearchIndex.Hit] {
        let pool = includeTemplates ? notes + templates : notes
        let key = "\(query)|\(matchRaw)|\(scopeRaw)|\(sortRaw)|\(wholeWords)|\(includeTemplates)|\(pool.count)|\(pool.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0)"
        if memo.key == key { return memo.hits }
        let h = NoteSearchIndex.search(parsed, in: pool, scope: scope, match: match, wholeWords: wholeWords, sort: sort)
        memo.key = key; memo.hits = h
        return h
    }

    var body: some View {
        let results = hits
        let q = parsed
        Section {
            if results.isEmpty {
                ContentUnavailableView {
                    Label("No pages contain “\(query)”", systemImage: "magnifyingglass")
                } description: {
                    Text(emptyHint(q))
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(results.prefix(limit)) { hit in resultRow(hit, q) }
                if results.count > limit {
                    Button("Show all \(results.count) pages") { limit = .max }.font(DS.Font.caption)
                }
            }
        } header: {
            HStack(spacing: 8) {
                Text(results.isEmpty ? "No matches" : "\(results.count) page\(results.count == 1 ? "" : "s")" + matchesText(results))
                    .font(DS.Font.headline).foregroundStyle(DS.Palette.ink).textCase(nil)
                Spacer()
                optionsMenu
                Button(KeelTags.saved.contains(query) ? "Saved" : "Save") {
                    if !KeelTags.saved.contains(query) { KeelTags.saved = [query] + KeelTags.saved; Haptics.tap() }
                }
                .font(DS.Font.caption).textCase(nil).buttonStyle(.borderless)
            }
        } footer: {
            if !results.isEmpty { Text("Searched \(notes.count) page\(notes.count == 1 ? "" : "s")\(includeTemplates ? " and templates" : ""): titles, text, tables, database fields and scanned images.") }
        }
        .onChange(of: query) { limit = 60 }
    }

    private func matchesText(_ r: [NoteSearchIndex.Hit]) -> String {
        let n = r.reduce(0) { $0 + $1.matches }
        return n > r.count ? " · \(n) matches" : ""
    }

    private func emptyHint(_ q: NoteQuery) -> String {
        if match == .phrase || !q.phrases.isEmpty { return "Try All words instead of an exact phrase (Options)." }
        if scope == .titles { return "You're searching titles only. Switch to Titles and text in Options." }
        if wholeWords { return "Whole words is on. Turn it off to find parts of words too." }
        if q.terms.count > 1 && match == .all { return "Every word has to be on the page. Try Any word in Options." }
        return "Locked pages are searched by title only."
    }

    private func resultRow(_ hit: NoteSearchIndex.Hit, _ q: NoteQuery) -> some View {
        let n = hit.note
        return Button { NoteSearchPrefs.remember(query); open(n, hit.jumpTo) } label: {
            HStack(alignment: .top, spacing: DS.Space.m) {
                Text(n.icon ?? (n.isDatabase ? "🗃️" : "📄")).font(.system(size: 18))
                    .frame(width: 34, height: 34)
                    .background((n.isDatabase ? Color.purple : DS.Palette.accent).opacity(0.1), in: .rect(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        titleText(n, q).font(DS.Font.body.weight(.medium)).lineLimit(1)
                        if n.isLocked { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(DS.Palette.inkSoft) }
                        if n.isPinned { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                        Spacer(minLength: 0)
                        if hit.matches > 1 {
                            Text("\(hit.matches)").font(.caption2.weight(.semibold).monospacedDigit())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .foregroundStyle(DS.Palette.accent).background(DS.Palette.accent.opacity(0.12), in: Capsule())
                                .accessibilityLabel("\(hit.matches) matches")
                        }
                    }
                    if showPreviews, let p = hit.preview {
                        Text(NoteSearchIndex.preview(p, highlights: q.highlights, tint: DS.Palette.accent))
                            .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(3)
                    }
                    Text(detail(hit)).font(.caption2).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func titleText(_ n: Note, _ q: NoteQuery) -> Text {
        let title = n.title.isEmpty ? "Untitled" : n.title
        guard !n.title.isEmpty else { return Text(title).foregroundStyle(DS.Palette.inkSoft) }
        let part = NotePart(kind: .text, blockId: nil, display: title, folded: NoteText.fold(title))
        var a = NoteSearchIndex.preview(part, highlights: q.highlights + q.titleTerms, tint: DS.Palette.accent)
        a.foregroundColor = DS.Palette.ink
        return Text(a)
    }

    private func detail(_ hit: NoteSearchIndex.Hit) -> String {
        var parts: [String] = []
        if hit.inTitle { parts.append("Title") }
        parts += hit.foundIn.map(\.rawValue)
        if let f = hit.note.folder { parts.append(f.replacingOccurrences(of: "/", with: " › ")) }
        parts.append("Edited " + hit.note.updatedAt.formatted(.relative(presentation: .named)))
        return parts.joined(separator: " · ")
    }

    private var optionsMenu: some View {
        Menu {
            Picker("Match", selection: $matchRaw) {
                ForEach(NoteSearchPrefs.Match.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
            Picker("Look in", selection: $scopeRaw) {
                ForEach(NoteSearchPrefs.Scope.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
            Picker("Sort", selection: $sortRaw) {
                ForEach(NoteSearchPrefs.Sort.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
            Toggle("Whole words only", isOn: $wholeWords)
            Toggle("Include templates", isOn: $includeTemplates)
            Toggle("Show matching lines", isOn: $showPreviews)
        } label: {
            Label("Options", systemImage: "line.3.horizontal.decrease.circle").labelStyle(.iconOnly)
        }
        .accessibilityLabel("Search options")
    }
}

private final class SearchMemo { var key = ""; var hits: [NoteSearchIndex.Hit] = [] }

// MARK: - Suggestions under the search field

/// Recent and saved searches, plus the search shortcuts, shown before you type.
struct NoteSearchSuggestions: View {
    @Binding var text: String
    @AppStorage(NoteSearchPrefs.recentsOnKey) private var recentsOn = true
    @State private var recents = NoteSearchPrefs.recents

    private let tips: [(String, String)] = [
        ("\"exact phrase\"", "Words together, exactly"),
        ("-word", "Leave out pages with this word"),
        ("title:", "Only in page titles"),
        ("in:", "Only in a folder, e.g. in:Work"),
        ("#", "Pages with a tag"),
        ("is:todo", "Pages with unchecked to-dos"),
        ("is:pinned", "Your favorite pages"),
        ("edited:week", "Changed in the last 7 days"),
    ]

    var body: some View {
        if recentsOn && !recents.isEmpty {
            Section("Recent") {
                ForEach(recents, id: \.self) { r in
                    Label(r, systemImage: "clock.arrow.circlepath").searchCompletion(r)
                }
                Button("Clear recent searches", role: .destructive) { NoteSearchPrefs.recents = []; recents = [] }
                    .font(DS.Font.caption)
            }
        }
        if !KeelTags.saved.isEmpty {
            Section("Saved") {
                ForEach(KeelTags.saved.prefix(6), id: \.self) { s in Label(s, systemImage: "bookmark").searchCompletion(s) }
            }
        }
        Section("Search shortcuts") {
            ForEach(tips, id: \.0) { t in
                Button { text = t.0 == "\"exact phrase\"" ? "\"" : t.0 } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.0).font(.body.monospaced())
                        Text(t.1).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
            }
        }
    }
}
