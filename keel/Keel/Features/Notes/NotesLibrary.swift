import SwiftUI
import SwiftData

// MARK: - Library (Chart Table's Notes home)
//
// Notes as a ship's library: a mono count and serif title, "Ask your library" in place of a plain search, pinned pages in
// a slim Chart drawer, and recent pages as paper index cards on a two-column shelf with their first lines showing.
// Everything below (workspaces, folders, the page tree, templates) is unchanged.

struct LibraryHeader: View {
    let total: Int
    let newThisWeek: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(total) PAGES · \(newThisWeek) NEW THIS WEEK").font(DS.Font.mono).tracking(0.8).foregroundStyle(DS.Palette.inkSoft)
            Text("Library").font(.system(.largeTitle, design: .serif, weight: .semibold)).foregroundStyle(DS.Palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Ask a question; the answer comes from your pages, with links to them.
struct AskLibraryBar: View {
    var body: some View {
        NavigationLink { LazyView(AskNotesView()) } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkle").foregroundStyle(Nautical.chartRed)
                Text("Ask your library… “what did we decide about the trip?”")
                    .font(.subheadline).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(DS.Palette.elevated, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DS.Palette.ink.opacity(0.25), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask your library")
    }
}

/// Pinned pages, small, in a strip you scroll sideways.
struct ChartDrawer: View {
    let notes: [Note]
    var open: (Note) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(notes) { n in
                    Button { open(n) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(n.icon ?? (n.isDatabase ? "🗃️" : "📌")).font(.system(size: 16))
                            Text(n.title.isEmpty ? "Untitled" : n.title).font(.system(.footnote, design: .serif).weight(.medium))
                                .foregroundStyle(DS.Palette.ink).lineLimit(2).multilineTextAlignment(.leading)
                        }
                        .frame(width: 96, height: 62, alignment: .topLeading)
                        .padding(9)
                        .background(DS.Palette.elevated, in: .rect(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DS.Palette.ink.opacity(0.22), lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 2)
        }
    }
}

/// Recent pages as paper index cards, two to a row.
struct LibraryShelf: View {
    let notes: [Note]
    var open: (Note) -> Void
    var body: some View {
        FlexGrid(columns: 2, spacing: 10, alignment: .leading) {
            ForEach(notes) { n in
                Button { open(n) } label: { ShelfCard(note: n) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }
}

struct ShelfCard: View {
    let note: Note
    var body: some View {
        let dark = note.isDatabase
        VStack(alignment: .leading, spacing: 5) {
            Text((note.isDatabase ? "🗃 " : "") + (note.title.isEmpty ? "Untitled" : note.title))
                .font(.system(.subheadline, design: .serif).weight(.semibold))
                .foregroundStyle(dark ? DS.Palette.canvas : DS.Palette.ink).lineLimit(2)
            if note.isLocked {
                Label("Locked", systemImage: "lock.fill").font(.caption).foregroundStyle(DS.Palette.inkSoft)
            } else {
                Text(note.isDatabase ? "Database" : (note.aiSummary ?? NoteSnippet.text(note)))
                    .font(.caption).foregroundStyle(dark ? DS.Palette.canvas.opacity(0.75) : DS.Palette.inkSoft)
                    .lineLimit(3).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Text(stamp(note.updatedAt)).font(DS.Font.mono).foregroundStyle(dark ? DS.Palette.canvas.opacity(0.6) : DS.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .padding(11)
        .background(dark ? DS.Palette.ink : DS.Palette.elevated, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DS.Palette.ink.opacity(dark ? 0 : 0.25), lineWidth: 0.8))
        .accessibilityElement(children: .combine)
    }

    private func stamp(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "TODAY " + Nautical.clock(d).uppercased() }
        if cal.isDateInYesterday(d) { return "YESTERDAY" }
        return d.formatted(.dateTime.weekday(.abbreviated).day()).uppercased()
    }
}
