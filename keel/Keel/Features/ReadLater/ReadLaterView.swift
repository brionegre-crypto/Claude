import SwiftUI
import SwiftData
import SafariServices

/// Read later: save links (from Safari's share sheet, the clipboard, or here), get an on-device summary,
/// and read them in a clean reader view.
@MainActor
enum LinkSaver {
    struct Shared: Codable { var url: String; var title: String?; var date: Date }

    static var queueURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.groupId)?
            .appendingPathComponent("shared-links.json")
    }

    /// Links saved from Safari's share sheet wait in the App Group until Keel opens.
    static func importShared(into ctx: ModelContext) {
        guard let url = queueURL, let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([Shared].self, from: data), !items.isEmpty else { return }
        try? FileManager.default.removeItem(at: url)
        for item in items { add(item.url, title: item.title, ctx: ctx) }
    }

    private struct SharedNote: Codable { var text: String; var images: [String]; var date: Date }

    /// Text and images shared to Keel (from Notes, Messages, Photos, anywhere) become Keel notes.
    static func importSharedNotes(into ctx: ModelContext) {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.groupId) else { return }
        let file = dir.appendingPathComponent("shared-notes.json")
        guard let data = try? Data(contentsOf: file),
              let items = try? JSONDecoder().decode([SharedNote].self, from: data), !items.isEmpty else { return }
        try? FileManager.default.removeItem(at: file)
        for item in items {
            let firstLine = item.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            let title = firstLine.isEmpty ? "Shared \(item.date.formatted(date: .abbreviated, time: .shortened))" : String(firstLine.prefix(60))
            let note = Note(title: title, blocks: item.text.isEmpty ? [] : [NoteBlock(kind: .text, text: item.text)])
            ctx.insert(note)
            for name in item.images {
                let url = dir.appendingPathComponent("shared-images").appendingPathComponent(name)
                if let img = try? Data(contentsOf: url) {
                    NoteMedia.add(img, kind: "photo", to: note, ctx: ctx)
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    @discardableResult
    static func add(_ raw: String, title: String? = nil, ctx: ModelContext) -> SavedLink? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        guard let url = URL(string: s), url.host != nil else { return nil }
        let key = s
        let existing = (try? ctx.fetch(FetchDescriptor<SavedLink>(predicate: #Predicate { $0.url == key }))) ?? []
        if let found = existing.first { return found }
        let link = SavedLink(url: s, title: title ?? url.host ?? s)
        link.siteName = url.host?.replacingOccurrences(of: "www.", with: "") ?? ""
        ctx.insert(link)
        Task { await enrich(link) }
        return link
    }

    /// Fetches the page title and text, then summarizes it on-device.
    static func enrich(_ link: SavedLink) async {
        guard let url = URL(string: link.url),
              let result = try? await URLSession.shared.data(from: url) else { return }
        let html = String(decoding: result.0.prefix(600_000), as: UTF8.self)
        if let t = firstMatch(html, #"<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)"#)
            ?? firstMatch(html, #"<title[^>]*>([^<]+)</title>"#) {
            link.title = t.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#39;", with: "'")
        }
        let text = html.strippingHTML
        if text.count > 200, let summary = await AIRouter.shared.summarize(String(text.prefix(10_000))) {
            link.summary = summary
        }
    }

    private static func firstMatch(_ s: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }
}

struct ReadLaterView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \SavedLink.addedAt, order: .reverse) private var links: [SavedLink]
    @State private var showRead = false
    @State private var newURL = ""
    @State private var reading: SavedLink?

    private var visible: [SavedLink] { links.filter { $0.isRead == showRead } }

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "link.badge.plus").foregroundStyle(DS.Palette.accent)
                    TextField("Paste a link", text: $newURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit(addTyped)
                    if UIPasteboard.general.hasURLs {
                        Button("Paste") { if let u = UIPasteboard.general.url { LinkSaver.add(u.absoluteString, ctx: ctx); Haptics.success() } }
                            .font(DS.Font.caption).buttonStyle(.bordered)
                    }
                }
            } footer: {
                Text("Tip: in Safari, tap Share → Keel to save any page.")
            }

            if visible.isEmpty {
                ContentUnavailableView(showRead ? "Nothing read yet" : "Your reading list is empty",
                                       systemImage: "books.vertical",
                                       description: Text("Save articles to read when you have the energy for it."))
                    .listRowBackground(Color.clear)
            }

            ForEach(visible) { link in
                Button { open(link) } label: { LinkRow(link: link) }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { ctx.delete(link) } label: { Label("Delete", systemImage: "trash") }
                        Button { link.isRead.toggle(); link.readAt = link.isRead ? Date() : nil } label: {
                            Label(link.isRead ? "Unread" : "Read", systemImage: link.isRead ? "circle" : "checkmark")
                        }
                        .tint(DS.Palette.calm)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            QuickAdd.create("Read: \(link.title)", in: ctx)
                            Haptics.success()
                        } label: { Label("Task", systemImage: "checklist") }
                        .tint(DS.Palette.warmth)
                    }
            }
        }
        .navigationTitle("Read Later")
        .toolbar {
            Picker("Show", selection: $showRead) { Text("Unread").tag(false); Text("Read").tag(true) }
                .pickerStyle(.segmented).frame(width: 170)
        }
        .task { LinkSaver.importShared(into: ctx) }
        .refreshable { for l in links where l.summary == nil { await LinkSaver.enrich(l) } }
        .sheet(item: $reading) { link in
            if let url = URL(string: link.url) { SafariReader(url: url).ignoresSafeArea() }
        }
    }

    private func addTyped() {
        guard !newURL.isEmpty else { return }
        if LinkSaver.add(newURL, ctx: ctx) != nil { Haptics.success() }
        newURL = ""
    }

    private func open(_ link: SavedLink) {
        reading = link
        link.isRead = true
        link.readAt = Date()
    }
}

struct LinkRow: View {
    let link: SavedLink
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(link.title).font(DS.Font.headline).lineLimit(2).foregroundStyle(DS.Palette.ink)
            HStack(spacing: 6) {
                Text(link.siteName).font(DS.Font.caption).foregroundStyle(DS.Palette.accent)
                Text("· \(link.addedAt.formatted(.relative(presentation: .named)))").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            if let s = link.summary {
                Text(s).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(4)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Safari's reader view inside Keel.
struct SafariReader: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = true
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = UIColor(DS.Palette.accent)
        return vc
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
