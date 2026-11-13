import SwiftUI
import SwiftData
import NaturalLanguage

// MARK: - Meaning index (on-device): related pages, suggested links, search by meaning

/// Every page, open task and recent email turned into a "meaning" vector with Apple's on-device language model.
/// Nothing leaves the device. Powers Related, search by meaning, Ask everything and resurfacing.
@MainActor
final class BrainIndex {
    static let shared = BrainIndex()

    struct Item: Codable {
        var kind: String            // note | task | mail
        var id: String
        var title: String
        var stamp: Double           // updatedAt when indexed
        var vec: Data               // [Float], normalized
    }

    private(set) var items: [String: Item] = [:]
    private var loaded = false
    private var building = false
    private var lastBuild = Date.distantPast

    private var url: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("brain-index.plist") }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let d = try? Data(contentsOf: url), let v = try? PropertyListDecoder().decode([String: Item].self, from: d) { items = v }
    }
    private func save() {
        let enc = PropertyListEncoder(); enc.outputFormat = .binary
        try? enc.encode(items).write(to: url, options: .atomic)
    }

    nonisolated static func embed(_ text: String) -> [Float]? {
        let clean = text.replacingOccurrences(of: #"[*_=`#>\[\]()]"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > 2, let model = NLEmbedding.sentenceEmbedding(for: .english),
              let v = model.vector(for: String(clean.prefix(1_000))) else { return nil }
        var f = v.map { Float($0) }
        let n = sqrt(f.reduce(0) { $0 + $1 * $1 })
        guard n > 0 else { return nil }
        for i in f.indices { f[i] /= n }
        return f
    }
    private static func pack(_ f: [Float]) -> Data { f.withUnsafeBufferPointer { Data(buffer: $0) } }
    private static func unpack(_ d: Data) -> [Float] { d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) } }
    private static func dot(_ a: [Float], _ b: [Float]) -> Float {
        var s: Float = 0
        for i in 0..<min(a.count, b.count) { s += a[i] * b[i] }
        return s
    }

    /// Brings the index up to date (only what changed). Cheap to call often; runs at most every 2 minutes.
    func refresh(ctx: ModelContext, force: Bool = false) {
        load()
        guard !building, force || Date().timeIntervalSince(lastBuild) > 120 else { return }
        building = true
        lastBuild = Date()
        var jobs: [(key: String, kind: String, id: String, title: String, text: String, stamp: Double)] = []
        var live = Set<String>()
        for n in (try? ctx.fetch(FetchDescriptor<Note>())) ?? [] where !n.isLocked && !n.isTemplate {
            let key = "note:\(n.id.uuidString)"; live.insert(key)
            let stamp = n.updatedAt.timeIntervalSince1970
            if items[key]?.stamp != stamp { jobs.append((key, "note", n.id.uuidString, n.title, n.title + ". " + n.plainText.prefix(1_200), stamp)) }
        }
        for t in (try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? [] {
            let key = "task:\(t.id.uuidString)"; live.insert(key)
            let stamp = t.updatedAt.timeIntervalSince1970
            if items[key]?.stamp != stamp { jobs.append((key, "task", t.id.uuidString, t.title, t.title + ". " + t.notes.prefix(400), stamp)) }
        }
        var md = FetchDescriptor<EmailMessage>(sortBy: [SortDescriptor(\.receivedAt, order: .reverse)])
        md.fetchLimit = 1_500
        for e in (try? ctx.fetch(md)) ?? [] {
            let key = "mail:\(e.id)"; live.insert(key)
            let stamp = e.receivedAt.timeIntervalSince1970
            if items[key] == nil { jobs.append((key, "mail", e.id, e.subject, e.subject + ". " + (e.aiSummary ?? e.snippet), stamp)) }
        }
        for k in items.keys where !live.contains(k) { items[k] = nil }
        guard !jobs.isEmpty else { building = false; save(); return }
        let work = jobs
        Task.detached(priority: .utility) {
            var out: [(String, Item)] = []
            for j in work {
                if let v = BrainIndex.embed(j.text) { out.append((j.key, Item(kind: j.kind, id: j.id, title: j.title, stamp: j.stamp, vec: BrainIndex.pack(v)))) }
            }
            await MainActor.run {
                for (k, v) in out { BrainIndex.shared.items[k] = v }
                BrainIndex.shared.building = false
                BrainIndex.shared.save()
            }
        }
    }

    struct Hit: Identifiable { let id: String; let kind: String; let title: String; let score: Float }

    /// Things closest in meaning to a page/task/email, best first.
    func related(to key: String, kinds: Set<String> = ["note", "task", "mail"], limit: Int = 8, minScore: Float = 0.55) -> [Hit] {
        load()
        guard let base = items[key].map({ Self.unpack($0.vec) }) else { return [] }
        return rank(base, excluding: key, kinds: kinds, limit: limit, minScore: minScore)
    }

    /// Search by meaning ("that idea about pricing tiers") rather than exact words.
    func search(_ text: String, kinds: Set<String> = ["note", "task", "mail"], limit: Int = 8, minScore: Float = 0.45) -> [Hit] {
        load()
        guard let q = Self.embed(text) else { return [] }
        return rank(q, excluding: nil, kinds: kinds, limit: limit, minScore: minScore)
    }

    private func rank(_ v: [Float], excluding: String?, kinds: Set<String>, limit: Int, minScore: Float) -> [Hit] {
        var hits: [Hit] = []
        for (k, it) in items where k != excluding && kinds.contains(it.kind) {
            let s = Self.dot(v, Self.unpack(it.vec))
            if s >= minScore { hits.append(Hit(id: it.id, kind: it.kind, title: it.title, score: s)) }
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(limit))
    }

    var count: Int { load(); return items.count }
}

// MARK: - Cached page text, so links and mentions don't re-read every page on every redraw

@MainActor
enum LinkIndex {
    private static var stamp = ""
    private static var lower: [UUID: String] = [:]
    private static var raw: [UUID: String] = [:]

    /// Plain text of every page, rebuilt only when a page changes.
    static func texts(_ notes: [Note]) -> (lower: [UUID: String], raw: [UUID: String]) {
        let s = "\(notes.count)|\(notes.map(\.updatedAt.timeIntervalSince1970).max() ?? 0)"
        if s != stamp {
            stamp = s
            raw = Dictionary(notes.map { ($0.id, $0.plainText) }, uniquingKeysWith: { a, _ in a })
            lower = raw.mapValues { $0.lowercased() }
        }
        return (lower, raw)
    }
}

// MARK: - Related (bottom of every page)

struct RelatedSection: View {
    let note: Note
    let allNotes: [Note]
    var open: (Note) -> Void
    @Environment(\.modelContext) private var ctx
    @State private var hits: [BrainIndex.Hit] = []

    var body: some View {
        Group {
            if !hits.isEmpty {
                Text("RELATED").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).padding(.top, DS.Space.s)
                ForEach(hits) { h in
                    HStack {
                        switch h.kind {
                        case "note":
                            if let n = allNotes.first(where: { $0.id.uuidString == h.id }) {
                                Button { open(n) } label: { Label(n.title.isEmpty ? "Untitled" : n.title, systemImage: "doc.text") }.buttonStyle(.plain)
                                Spacer()
                                if !linked(n) {
                                    Button("Link") { link(n) }.font(DS.Font.caption).buttonStyle(.bordered)
                                }
                            }
                        case "task":
                            Label(h.title, systemImage: "checklist").foregroundStyle(DS.Palette.ink)
                            Spacer()
                        default:
                            Label(h.title, systemImage: "envelope").foregroundStyle(DS.Palette.ink).lineLimit(1)
                            Spacer()
                        }
                    }
                    .font(DS.Font.body)
                }
            }
        }
        .task(id: note.updatedAt) {
            try? await Task.sleep(for: .milliseconds(600))
            BrainIndex.shared.refresh(ctx: ctx)
            hits = BrainIndex.shared.related(to: "note:\(note.id.uuidString)", limit: 7)
        }
    }

    private func linked(_ n: Note) -> Bool {
        note.plainText.localizedCaseInsensitiveContains("[[\(n.title)]]") || note.plainText.contains(RichText.pageURL(n.id))
    }
    private func link(_ n: Note) {
        note.blocks.append(NoteBlock(kind: .bullet, text: "Related: [\(n.title.isEmpty ? "Untitled" : n.title)](\(RichText.pageURL(n.id)))"))
        Haptics.success()
    }
}
