import SwiftUI
import SwiftData
import FoundationModels

/// Sorts notes into folders. Apple Intelligence reads each loose note on your iPhone and picks one of your folders,
/// or suggests a new one; without it, Keel matches the note's words against what's already in each folder.
/// Nothing moves until you approve, unless you turn on auto-filing (which only uses folders you already have).
@MainActor
enum NotesOrganizer {
    static let autoKey = "notes.autofile"
    static let seenKey = "notes.autofile.seen"

    struct Proposal: Identifiable {
        let id: UUID              // note id
        let title: String
        var folder: String
        let isNew: Bool
        let confidence: Int       // 0–10
        var accepted: Bool
    }

    @Generable
    struct Pick {
        @Guide(description: "The best folder for this note. Use one of the existing folder names exactly when one fits.")
        var folder: String
        @Guide(description: "True only if no existing folder fits and this is a new folder name of 1-3 words")
        var isNew: Bool
        @Guide(description: "How sure you are, 0 to 10", .range(0...10))
        var confidence: Int
    }

    static var aiAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Notes that could use a folder: top-level pages without one (not templates, locked notes or database rows).
    static func loose(_ notes: [Note]) -> [Note] {
        notes.filter { $0.folder == nil && $0.parentId == nil && !$0.isTemplate && !$0.isLocked && !($0.title.isEmpty && $0.plainText.isEmpty) }
    }

    static func propose(for loose: [Note], all: [Note], allowNew: Bool, progress: (Int, Int) -> Void) async -> [Proposal] {
        let folders = Array(Set(all.compactMap(\.folder))).sorted()
        let profiles = profile(all)
        var out: [Proposal] = []
        let batch = Array(loose.prefix(60))
        for (i, n) in batch.enumerated() {
            progress(i, batch.count)
            if let p = await aiPick(n, folders: folders, allowNew: allowNew) { out.append(p) }
            else if let p = wordPick(n, profiles: profiles) { out.append(p) }
            else if allowNew, let p = rulePick(n) { out.append(p) }
            if i % 4 == 0 { await Task.yield() }
        }
        progress(batch.count, batch.count)
        return out
    }

    // MARK: Apple Intelligence

    private static func aiPick(_ n: Note, folders: [String], allowNew: Bool) async -> Proposal? {
        guard aiAvailable else { return nil }
        let session = LanguageModelSession(instructions: """
        You file notes into folders. Existing folders: \(folders.isEmpty ? "none yet" : folders.joined(separator: ", ")).
        Prefer an existing folder. \(allowNew ? "If none fits, suggest a short, general new folder name (like Work, Health, Recipes, Ideas, Meetings, Family, Money)." : "Only use an existing folder.")
        """)
        let prompt = "Title: \(n.title)\n\n\(n.plainText.prefix(700))"
        guard let pick = try? await session.respond(to: prompt, generating: Pick.self).content else { return nil }
        let name = pick.folder.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'.")))
        guard !name.isEmpty, name.count <= 30 else { return nil }
        let existing = folders.first { $0.caseInsensitiveCompare(name) == .orderedSame }
        if existing == nil && !allowNew { return nil }
        return Proposal(id: n.id, title: n.title.isEmpty ? "Untitled" : n.title, folder: existing ?? name.capitalized,
                        isNew: existing == nil, confidence: pick.confidence, accepted: pick.confidence >= 6)
    }

    // MARK: Without Apple Intelligence

    private static func words(_ s: String) -> Set<String> {
        Set(s.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { $0.count >= 4 && !stop.contains($0) })
    }
    private static let stop: Set<String> = ["this", "that", "with", "from", "have", "will", "your", "about", "what", "when", "there", "their", "they",
                                            "just", "need", "into", "some", "more", "been", "were", "also", "then", "than", "them", "here", "make", "like"]

    /// Most common words in each folder's notes.
    private static func profile(_ all: [Note]) -> [String: [String: Int]] {
        var out: [String: [String: Int]] = [:]
        for n in all {
            guard let f = n.folder else { continue }
            for w in words(n.title + " " + n.title + " " + String(n.plainText.prefix(1500))) { out[f, default: [:]][w, default: 0] += 1 }
        }
        return out
    }

    private static func wordPick(_ n: Note, profiles: [String: [String: Int]]) -> Proposal? {
        let mine = words(n.title + " " + String(n.plainText.prefix(1500)))
        guard !mine.isEmpty else { return nil }
        var best: (String, Double)?
        for (folder, counts) in profiles {
            let total = Double(max(1, counts.values.reduce(0, +)))
            let score = mine.reduce(0.0) { $0 + Double(counts[$1] ?? 0) } / total.squareRoot()
            if score > (best?.1 ?? 0) { best = (folder, score) }
        }
        guard let b = best, b.1 >= 0.6 else { return nil }
        let conf = min(10, Int(b.1 * 4))
        return Proposal(id: n.id, title: n.title.isEmpty ? "Untitled" : n.title, folder: b.0, isNew: false, confidence: conf, accepted: conf >= 5)
    }

    private static let rules: [(String, [String])] = [
        ("Meetings", ["meeting", "agenda", "standup", "1:1", "minutes", "attendees"]),
        ("Journal", ["journal", "today i", "grateful", "mood"]),
        ("Recipes", ["recipe", "ingredients", "tbsp", "teaspoon", "oven", "bake"]),
        ("Health", ["doctor", "medication", "symptom", "workout", "diet", "sleep"]),
        ("Money", ["budget", "invoice", "payment", "bill", "expense", "tax"]),
        ("Ideas", ["idea", "what if", "brainstorm", "someday"]),
        ("Work", ["project", "client", "deadline", "proposal", "quarter", "roadmap"]),
        ("Travel", ["flight", "hotel", "trip", "itinerary", "packing"]),
    ]

    private static func rulePick(_ n: Note) -> Proposal? {
        let t = (n.title + " " + String(n.plainText.prefix(1500))).lowercased()
        if n.linkedEventId != nil { return Proposal(id: n.id, title: n.title, folder: "Meetings", isNew: true, confidence: 8, accepted: true) }
        let scored = rules.map { r in (r.0, r.1.filter { t.contains($0) }.count) }.max { $0.1 < $1.1 }
        guard let s = scored, s.1 >= 2 else { return nil }
        return Proposal(id: n.id, title: n.title.isEmpty ? "Untitled" : n.title, folder: s.0, isNew: true, confidence: min(9, 3 + s.1 * 2), accepted: s.1 >= 3)
    }

    // MARK: Auto-file

    /// Quietly files new loose notes into existing folders when Keel is sure. Notes you've just edited are left alone,
    /// and each note is only tried once, so moving one back out is respected.
    static func autoFile(ctx: ModelContext) async {
        guard UserDefaults.standard.bool(forKey: autoKey) else { return }
        // At most every 10 minutes, so opening Notes stays instant.
        let last = UserDefaults.standard.double(forKey: "notes.autofile.last")
        guard Date().timeIntervalSince1970 - last > 600 else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "notes.autofile.last")
        let all = (try? ctx.fetch(FetchDescriptor<Note>())) ?? []
        guard all.contains(where: { $0.folder != nil }) else { return }
        var seen = Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
        let settled = Date().addingTimeInterval(-10 * 60)
        let candidates = loose(all).filter { !seen.contains($0.id.uuidString) && $0.updatedAt < settled }.prefix(12)
        guard !candidates.isEmpty else { return }
        let picks = await propose(for: Array(candidates), all: all, allowNew: false) { _, _ in }
        for p in picks where p.confidence >= 7 && !p.isNew {
            all.first { $0.id == p.id }?.folder = p.folder
        }
        for n in candidates { seen.insert(n.id.uuidString) }
        UserDefaults.standard.set(Array(seen.suffix(2000)), forKey: seenKey)
        try? ctx.save()
    }
}

/// Notes → ⋯ → Organize my notes. Review where each loose note would go, change any, then move them all at once.
struct OrganizeNotesView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var notes: [Note]
    @AppStorage(NotesOrganizer.autoKey) private var autoFile = false
    @State private var proposals: [NotesOrganizer.Proposal] = []
    @State private var running = false
    @State private var done = 0
    @State private var total = 0
    @State private var allowNew = true
    @State private var finished = false

    private var folders: [String] { Array(Set(notes.compactMap(\.folder) + proposals.map(\.folder))).sorted() }
    @State private var looseCount = 0

    var body: some View {
        NavigationStack {
            List {
                if proposals.isEmpty {
                    Section {
                        Toggle("Suggest new folders", isOn: $allowNew)
                        Button { Task { await run() } } label: {
                            HStack {
                                Label(running ? "Reading \(done) of \(total)…" : "Sort \(looseCount) loose note\(looseCount == 1 ? "" : "s")", systemImage: "wand.and.stars")
                                if running { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(running || looseCount == 0)
                    } footer: {
                        Text(NotesOrganizer.aiAvailable
                             ? "Apple Intelligence reads each note on your iPhone. Nothing leaves your phone, and nothing moves until you approve."
                             : "Keel compares each note with what's already in your folders. Nothing moves until you approve.")
                    }
                    if finished { Section { Text("Everything already has a home, or Keel wasn't sure enough to suggest one.").foregroundStyle(.secondary) } }
                } else {
                    let grouped = Dictionary(grouping: proposals.indices, by: { proposals[$0].folder })
                    ForEach(grouped.keys.sorted(), id: \.self) { folder in
                        Section {
                            ForEach(grouped[folder] ?? [], id: \.self) { i in
                                HStack {
                                    Button { proposals[i].accepted.toggle() } label: {
                                        Image(systemName: proposals[i].accepted ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(proposals[i].accepted ? DS.Palette.accent : .secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel(proposals[i].accepted ? "Will move" : "Won't move")
                                    Text(proposals[i].title).lineLimit(1)
                                    Spacer()
                                    Menu {
                                        ForEach(folders, id: \.self) { f in Button(f) { proposals[i].folder = f; proposals[i].accepted = true } }
                                    } label: { Image(systemName: "folder").foregroundStyle(.secondary) }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Choose a different folder")
                                }
                            }
                        } header: {
                            Label(isNewFolder(folder) ? folder + " · new" : folder, systemImage: "folder.fill")
                        }
                    }
                }
                Section {
                    Toggle("Auto-file new notes", isOn: $autoFile)
                } footer: {
                    Text("When Keel is sure, new notes are filed into your existing folders about 10 minutes after you stop editing them. It never creates folders on its own, and a note you move back stays put.")
                }
            }
            .task { looseCount = NotesOrganizer.loose(notes).count }
            .navigationTitle("Organize notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if !proposals.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Move \(proposals.filter(\.accepted).count)") { apply() }.disabled(!proposals.contains(where: \.accepted))
                    }
                }
            }
        }
    }

    private func isNewFolder(_ f: String) -> Bool { !notes.contains { $0.folder == f } }

    private func run() async {
        running = true
        let loose = NotesOrganizer.loose(notes)
        let result = await NotesOrganizer.propose(for: loose, all: notes, allowNew: allowNew) { d, t in done = d; total = t }
        running = false
        finished = result.isEmpty
        withAnimation(DS.spring) { proposals = result.sorted { $0.confidence > $1.confidence } }
    }

    private func apply() {
        let byId = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for p in proposals where p.accepted { byId[p.id]?.folder = p.folder }
        try? ctx.save()
        Haptics.success()
        dismiss()
    }
}
