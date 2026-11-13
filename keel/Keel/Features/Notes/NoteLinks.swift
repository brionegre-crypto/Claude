import SwiftUI
import SwiftData

/// [[Wiki links]] between notes: links out from this note, and other notes that link here.
struct NoteLinksSection: View {
    let note: Note
    @Environment(\.modelContext) private var ctx
    @Query private var notes: [Note]

    static func linkTitles(in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"\[\[([^\[\]]+)\]\]"#) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespaces) }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }

    var body: some View {
        let outgoing = Self.linkTitles(in: note.plainText)
        let url = RichText.pageURL(note.id)
        let texts = LinkIndex.texts(notes)          // cached: pages are read once per change, not on every redraw
        let wiki = "[[\(note.title.lowercased())]]"
        let backlinks = notes.filter { other in
            other.id != note.id && !other.isLocked &&
            ((texts.raw[other.id] ?? "").contains(url) || (!note.title.isEmpty && (texts.lower[other.id] ?? "").contains(wiki))
             || other.blocks.contains { $0.kind == .page && $0.refId == note.id.uuidString })
        }
        UnlinkedMentions(note: note, notes: notes)
        if !outgoing.isEmpty || !backlinks.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Divider().padding(.vertical, DS.Space.s)
                if !outgoing.isEmpty {
                    Text("LINKS").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    ForEach(outgoing, id: \.self) { title in
                        if let target = notes.first(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) {
                            NavigationLink { NoteEditor(note: target) } label: { Label(target.title, systemImage: "arrow.up.right.square") }
                        } else {
                            Button {
                                ctx.insert(Note(title: title))
                                Haptics.tap()
                            } label: { Label("Create “\(title)”", systemImage: "plus.square.dashed") }
                        }
                    }
                }
                if !backlinks.isEmpty {
                    Text("LINKED FROM").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).padding(.top, DS.Space.s)
                    ForEach(backlinks) { b in
                        NavigationLink { NoteEditor(note: b) } label: { Label(b.title, systemImage: "arrow.down.left.square") }
                    }
                }
            }
            .font(DS.Font.body)
        }
    }
}

@MainActor
enum DailyNote {
    static func title(for date: Date = Date()) -> String { date.formatted(date: .complete, time: .omitted) }

    /// Opens today's note, creating it from the daily template the first time.
    static func today(_ ctx: ModelContext) -> Note {
        let t = title()
        if let existing = ((try? ctx.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.title == t }))) ?? []).first { return existing }
        let events = CalendarService.shared.todaysEvents().filter { !$0.isAllDay }
            .map { NoteBlock(kind: .bullet, text: "\($0.startDate.formatted(date: .omitted, time: .shortened)) \($0.title ?? "")") }
        var blocks: [NoteBlock] = []
        if !events.isEmpty { blocks += [NoteBlock(kind: .heading, text: "Today")] + events }
        blocks += [
            NoteBlock(kind: .heading, text: "Notes"), NoteBlock(kind: .bullet, text: ""),
            NoteBlock(kind: .heading, text: "Wins"), NoteBlock(kind: .bullet, text: ""),
        ]
        let note = Note(title: t, blocks: blocks)
        ctx.insert(note)
        return note
    }
}
