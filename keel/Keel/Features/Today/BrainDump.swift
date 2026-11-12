import SwiftUI
import SwiftData
import FoundationModels

/// Brain dump: type or dictate everything in your head, in any order. Apple Intelligence sorts it into
/// tasks (with dates), calendar events, notes and worries. You review before anything is saved.
struct BrainDumpItem: Identifiable, Hashable {
    enum Kind: String, CaseIterable { case task, event, note, worry
        var icon: String { switch self { case .task: "checklist"; case .event: "calendar"; case .note: "note.text"; case .worry: "cloud.rain" } }
        var label: String { rawValue.capitalized }
    }
    let id = UUID()
    var kind: Kind
    var title: String
    var when: String = ""
    var detail: String = ""
    var include = true
}

@MainActor
enum BrainDumpSorter {
    @Generable
    struct Item {
        @Guide(description: "task (something to do), event (happens at a set time with others or a place), note (an idea or info to keep), or worry (a feeling or concern)")
        var kind: String
        @Guide(description: "Short title, starting with a verb for tasks")
        var title: String
        @Guide(description: "When it's due or happens, as a short phrase like 'tomorrow 3pm' or 'Friday'; empty if not stated")
        var when: String
        @Guide(description: "Any extra detail mentioned; empty if none")
        var detail: String
    }

    @Generable
    struct Result {
        @Guide(description: "Every separate item mentioned, in order", .maximumCount(30))
        var items: [Item]
    }

    static func sort(_ text: String) async -> [BrainDumpItem] {
        if AIRouter.shared.onDeviceAvailable {
            let session = LanguageModelSession(instructions: "Split a messy brain dump into separate items. Never merge two different things, never invent anything. Today is \(Date().formatted(.dateTime.weekday(.wide).month().day())).")
            if let r = try? await session.respond(to: String(text.prefix(4_000)), generating: Result.self).content, !r.items.isEmpty {
                return r.items.map { BrainDumpItem(kind: .init(rawValue: $0.kind.lowercased()) ?? .task, title: $0.title, when: $0.when, detail: $0.detail) }
            }
        }
        return heuristic(text)
    }

    /// No Apple Intelligence: one line or sentence per item, with simple keyword sorting.
    static func heuristic(_ text: String) -> [BrainDumpItem] {
        text.components(separatedBy: CharacterSet(charactersIn: "\n.;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "-•*"))) }
            .filter { $0.count > 1 }
            .map { line in
                let l = line.lowercased()
                let kind: BrainDumpItem.Kind =
                    ["worried", "anxious", "stressed", "scared", "nervous"].contains { l.contains($0) } ? .worry :
                    l.hasPrefix("idea") || l.hasPrefix("note") || l.hasPrefix("remember that") ? .note :
                    ["meeting", "appointment", "lunch with", "dinner with", "call with", "party"].contains { l.contains($0) } && NaturalDate.parse(line).date != nil ? .event : .task
                return BrainDumpItem(kind: kind, title: line)
            }
    }

    /// Saves the chosen items. Returns a summary like "4 tasks, 1 event, 1 note".
    @discardableResult
    static func save(_ items: [BrainDumpItem], ctx: ModelContext) -> String {
        var counts: [BrainDumpItem.Kind: Int] = [:]
        var worries: [String] = []
        for i in items where i.include {
            let phrase = [i.title, i.when].filter { !$0.isEmpty }.joined(separator: " ")
            switch i.kind {
            case .task:
                let t = QuickAdd.create(phrase, in: ctx)
                if !i.detail.isEmpty { t.notes = i.detail }
                counts[.task, default: 0] += 1
            case .event:
                if (try? QuickEvent.create(phrase)) != nil { counts[.event, default: 0] += 1 }
                else { _ = QuickAdd.create(phrase, in: ctx); counts[.task, default: 0] += 1 }   // no time found: keep it as a task
            case .note:
                ctx.insert(Note(title: i.title, blocks: [NoteBlock(kind: .text, text: i.detail)]))
                counts[.note, default: 0] += 1
            case .worry:
                worries.append(i.title + (i.detail.isEmpty ? "" : ": \(i.detail)"))
                counts[.worry, default: 0] += 1
            }
        }
        if !worries.isEmpty {
            // Worries go on one list, out of your head; the evening review asks if any still matter.
            let title = "Worry list"
            let existing = ((try? ctx.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.title == title }))) ?? []).first
            let note = existing ?? Note(title: title, blocks: [])
            if existing == nil { ctx.insert(note) }
            note.blocks += worries.map { NoteBlock(kind: .bullet, text: "\(Date().formatted(date: .abbreviated, time: .omitted)): \($0)") }
            note.updatedAt = Date()
        }
        try? ctx.save()
        return BrainDumpItem.Kind.allCases.compactMap { k in
            counts[k].map { n in "\(n) \(n == 1 ? k.rawValue : (k == .worry ? "worries" : k.rawValue + "s"))" }
        }.joined(separator: ", ")
    }
}

struct BrainDumpView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var items: [BrainDumpItem] = []
    @State private var sorting = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty { dumpStep } else { reviewStep }
            }
            .navigationTitle(items.isEmpty ? "Brain Dump" : "Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if items.isEmpty {
                        Button(sorting ? "Sorting…" : "Sort it") {
                            Task { sorting = true; items = await BrainDumpSorter.sort(text); sorting = false; Haptics.tap() }
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sorting)
                    } else {
                        Button("Add \(items.filter(\.include).count)") {
                            let summary = BrainDumpSorter.save(items, ctx: ctx)
                            Haptics.success()
                            UndoCenter.shared.notify("Added \(summary)")
                            dismiss()
                        }
                        .disabled(!items.contains(where: \.include))
                    }
                }
            }
        }
    }

    private var dumpStep: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("Everything in your head, in any order. Ramble, it's fine. Tap the 🎙 on the keyboard to talk.")
                .font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
            TextEditor(text: $text)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .padding(DS.Space.s)
                .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.chip))
            if sorting { ProgressView("Sorting tasks, events, notes and worries…").frame(maxWidth: .infinity) }
        }
        .padding()
        .onAppear { focused = true }
    }

    private var reviewStep: some View {
        List {
            Section { } footer: { Text("Tap the icon to change what something is. Untick anything you don't want.") }
            ForEach($items) { $item in
                HStack(spacing: DS.Space.m) {
                    Button { item.include.toggle() } label: {
                        Image(systemName: item.include ? "checkmark.circle.fill" : "circle").foregroundStyle(item.include ? DS.Palette.accent : .secondary)
                    }.buttonStyle(.plain)
                    Menu {
                        ForEach(BrainDumpItem.Kind.allCases, id: \.self) { k in Button(k.label, systemImage: k.icon) { item.kind = k } }
                    } label: { Image(systemName: item.kind.icon).frame(width: 24).foregroundStyle(DS.Palette.accent) }
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Title", text: $item.title)
                        if item.kind == .task || item.kind == .event {
                            TextField("When (optional)", text: $item.when).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                }
                .opacity(item.include ? 1 : 0.45)
            }
            Section {
                Button("Back to editing", systemImage: "chevron.left") { items = [] }
            }
        }
    }
}
