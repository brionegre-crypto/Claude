import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// "Move to Keel": bring notes in from other apps. Drop in anything (a zip, a folder, files) and Keel
/// works out where it came from, shows you exactly what it found, then imports pages, sub-pages,
/// databases, images and links. Every import can be undone.
struct ImportView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    enum Stage { case choose, scanning, preview, importing, done }
    @State private var stage: Stage = .choose
    @State private var picking = false
    @State private var forced: ImportSource?
    @State private var archive: ImportArchive?
    @State private var bundle: ImportBundle?
    @State private var duplicates = 0
    @State private var options = ImportEngine.Options()
    @State private var useFolder = true
    @State private var folderName = ""
    @State private var progress = 0.0
    @State private var status = ""
    @State private var record: ImportEngine.Record?
    @State private var error: String?
    @State private var guide: ImportSource?
    @State private var connecting = false
    @State private var history = ImportEngine.history
    @State private var confirmUndo: ImportEngine.Record?
    @State private var showBrain = false

    var body: some View {
        Group {
            switch stage {
            case .choose: chooser
            case .scanning: working("Reading your files…", detail: "Working out where they came from")
            case .preview: if let bundle { preview(bundle) }
            case .importing: working(status, detail: "\(Int(progress * 100))%")
            case .done: if let record { done(record) }
            }
        }
        .navigationTitle(stage == .choose ? "Move to Keel" : "Import")
        .navigationBarTitleDisplayMode(stage == .choose ? .large : .inline)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder, .zip, .item], allowsMultipleSelection: true) { res in
            if case .success(let urls) = res, !urls.isEmpty { scan(urls) }
        }
        .sheet(item: $guide) { s in
            SourceGuideSheet(source: s, pick: {
                guide = nil
                forced = s == .markdown ? nil : s
                Task { try? await Task.sleep(for: .milliseconds(450)); picking = true }     // after the sheet closes
            }, connect: {
                guide = nil
                Task { try? await Task.sleep(for: .milliseconds(450)); connecting = true }
            })
        }
        .sheet(isPresented: $connecting) {
            NotionConnectSheet { b in
                connecting = false
                show(b, archive: nil)
            }
        }
        .navigationDestination(isPresented: $showBrain) { BrainMapView() }
        .confirmationDialog("Undo this import?", isPresented: Binding(get: { confirmUndo != nil }, set: { if !$0 { confirmUndo = nil } }), titleVisibility: .visible) {
            Button("Remove \(confirmUndo?.noteIds.count ?? 0) imported pages", role: .destructive) {
                if let r = confirmUndo { ImportEngine.undo(r, ctx: ctx); history = ImportEngine.history; if record?.id == r.id { stage = .choose } }
                Haptics.success()
            }
        } message: { Text("Only what this import added is removed. Pages you've edited since are removed too.") }
        .alert("Couldn't read that", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    // MARK: 1. Choose

    private var chooser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                Text("Bring your notes, pages and databases. Keel keeps the structure, the links between pages and your images, and shows you everything before it imports.")
                    .font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)

                Button { forced = nil; picking = true } label: {
                    HStack(spacing: DS.Space.m) {
                        Image(systemName: "tray.and.arrow.down.fill").font(.title).foregroundStyle(.white)
                            .frame(width: 60, height: 60).background(DS.Palette.accent.gradient, in: .rect(cornerRadius: 18, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Drop in anything").font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                            Text("A .zip, a folder or files. Keel recognises where it's from.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(DS.Palette.inkSoft)
                    }
                    .padding(DS.Space.m)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DS.Palette.elevated))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(DS.Palette.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                }
                .buttonStyle(PressStyle())

                Text("Or pick where you're coming from").font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft).textCase(.uppercase)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    sourceTile("Notion", "Connect or upload an export", "square.stack.3d.up.fill", .primary) { guide = .notion }
                    sourceTile("Obsidian", "Pick your vault folder", "diamond.fill", .purple) { guide = .obsidian }
                    sourceTile("Evernote", ".enex notebooks", "leaf.fill", .green) { guide = .evernote }
                    sourceTile("Apple Notes", "Share notes to Keel", "note.text", .yellow) { guide = .markdown }
                    sourceTile("Google Keep", "Takeout download", "lightbulb.fill", .orange) { guide = .keep }
                    sourceTile("Bear & more", "Markdown or TextBundle", "pawprint.fill", .red) { guide = .textbundle }
                }

                VStack(spacing: 0) {
                    NavigationLink { TaskCSVImportView() } label: { listRow("Tasks from a CSV file", "checklist") }
                    Divider().padding(.leading, 44)
                    Button { forced = .markdown; picking = true } label: { listRow("Markdown, text or HTML files", "doc.text") }
                }
                .padding(.horizontal, DS.Space.m)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DS.Palette.elevated))
                .buttonStyle(.plain)

                if !history.isEmpty {
                    Text("Your imports").font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft).textCase(.uppercase)
                    VStack(spacing: 0) {
                        ForEach(history) { r in
                            HStack {
                                Image(systemName: r.source.icon).foregroundStyle(DS.Palette.accent).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(r.source.label) · \(r.noteIds.count) pages").font(DS.Font.body).strikethrough(r.undone)
                                    Text(r.date.formatted(date: .abbreviated, time: .shortened) + (r.undone ? " · undone" : ""))
                                        .font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                                }
                                Spacer()
                                if !r.undone { Button("Undo") { confirmUndo = r }.font(DS.Font.caption).buttonStyle(.bordered) }
                            }
                            .padding(.vertical, 8)
                            if r.id != history.last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, DS.Space.m)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DS.Palette.elevated))
                }

                Label("Imports are added to what's already in Keel. Nothing is replaced, everything stays on this iPhone, and every import can be undone.",
                      systemImage: "lock.shield").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            .padding()
        }
    }

    private func sourceTile(_ title: String, _ subtitle: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(color == .primary ? Color(uiColor: .systemBackground) : .white)
                    .frame(width: 40, height: 40).background((color == .primary ? DS.Palette.ink : color).gradient, in: .rect(cornerRadius: 12, style: .continuous))
                Text(title).font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                Text(subtitle).font(.caption2).foregroundStyle(DS.Palette.inkSoft).lineLimit(2, reservesSpace: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS.Palette.elevated))
        }
        .buttonStyle(PressStyle())
    }

    private func listRow(_ title: String, _ icon: String) -> some View {
        HStack(spacing: DS.Space.m) {
            Image(systemName: icon).foregroundStyle(DS.Palette.accent).frame(width: 28)
            Text(title).font(DS.Font.body).foregroundStyle(DS.Palette.ink)
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(DS.Palette.inkSoft)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: 2. Scan

    private func scan(_ urls: [URL]) {
        stage = .scanning
        let force = forced
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (ImportArchive, ImportBundle) in
                let a = ImportArchive(urls: urls)
                let source = force ?? ImportDetector.detect(a)
                return (a, ImportParsers.parse(a, as: source == .notionAPI ? .notion : source))
            }.value
            if result.1.pages.isEmpty {
                error = "Keel couldn't find any notes in that. Try the export steps for your app, or pick the files inside the zip."
                stage = .choose
                return
            }
            show(result.1, archive: result.0)
        }
    }

    private func show(_ b: ImportBundle, archive: ImportArchive?) {
        self.archive = archive
        bundle = b
        duplicates = ImportEngine.duplicateCount(b, ctx: ctx)
        folderName = [ImportSource.notion, .notionAPI].contains(b.source) ? "Notion" : b.source == .obsidian ? "Vault" : b.source == .keep ? "" : b.source.label
        useFolder = !folderName.isEmpty && ![ImportSource.obsidian, .evernote, .keep].contains(b.source)
        withAnimation { stage = .preview }
    }

    private func rescan(as s: ImportSource) {
        guard let a = archive else { return }
        stage = .scanning
        Task {
            let b = await Task.detached(priority: .userInitiated) { ImportParsers.parse(a, as: s) }.value
            show(b, archive: a)
        }
    }

    // MARK: 3. Preview

    private func preview(_ b: ImportBundle) -> some View {
        List {
            Section {
                HStack(spacing: DS.Space.m) {
                    Image(systemName: b.source.icon).font(.title2).foregroundStyle(.white)
                        .frame(width: 48, height: 48).background(DS.Palette.accent.gradient, in: .rect(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Looks like: \(b.source.label)").font(DS.Font.headline)
                        Text(b.name).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                    }
                    Spacer()
                    if archive != nil {
                        Menu {
                            ForEach(ImportSource.allCases.filter { $0 != .notionAPI && $0 != b.source }) { s in
                                Button(s.label, systemImage: s.icon) { rescan(as: s) }
                            }
                        } label: { Text("Not right?").font(DS.Font.caption) }
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    stat("\(b.pages.count - b.rows - b.databases)", "pages")
                    stat("\(b.databases)", "databases")
                    stat("\(b.rows)", "rows")
                    stat("\(b.images)", "images")
                    stat("\(b.links)", "links")
                    stat("\(duplicates)", "already here")
                }
                .padding(.vertical, 4)
            }

            if !b.warnings.isEmpty {
                Section { ForEach(b.warnings, id: \.self) { Label($0, systemImage: "info.circle").font(DS.Font.caption) } }
            }

            Section("What's inside") {
                ForEach(Array(b.topLevel.prefix(40).enumerated()), id: \.offset) { item in
                    let p = item.element
                    let kids = b.pages.filter { $0.parentKey == p.key }.count
                    HStack(spacing: DS.Space.m) {
                        Text(p.icon ?? (p.isDatabase ? "🗃️" : "📄")).frame(width: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.title.isEmpty ? "Untitled" : p.title).font(DS.Font.body).lineLimit(1)
                            if kids > 0 || p.folder != nil {
                                Text([kids > 0 ? "\(kids) \(p.isDatabase ? "row" : "page")\(kids == 1 ? "" : "s") inside" : nil, p.folder].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                            }
                        }
                    }
                }
                if b.topLevel.count > 40 { Text("and \(b.topLevel.count - 40) more").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft) }
            }

            Section {
                Toggle("Put It All in One Folder", isOn: $useFolder)
                if useFolder { TextField("Folder name", text: $folderName) }
                Toggle("Skip Pages I Already Have", isOn: $options.skipDuplicates)
                Toggle("Add Unchecked To-dos as Tasks", isOn: $options.todosToTasks)
            } header: { Text("Options") } footer: {
                Text(useFolder ? "Top-level pages go in “\(folderName.isEmpty ? "Imported" : folderName)”; sub-pages stay inside their parents." : "Keeps the folders from where you're coming from.")
            }

            Section {
                Button { Task { await runImport(b) } } label: {
                    Text("Import \(max(0, b.pages.count - (options.skipDuplicates ? duplicates : 0))) pages")
                        .font(DS.Font.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).tint(DS.Palette.accent)
                .listRowBackground(Color.clear)
                Button("Cancel", role: .cancel) { withAnimation { stage = .choose; bundle = nil; archive = nil } }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: 4. Import

    private func runImport(_ b: ImportBundle) async {
        var opts = options
        opts.folder = useFolder ? (folderName.trimmingCharacters(in: .whitespaces).isEmpty ? "Imported" : folderName.trimmingCharacters(in: .whitespaces)) : nil
        withAnimation { stage = .importing; progress = 0; status = "Starting…" }
        let r = await ImportEngine.run(b, archive: archive, options: opts, ctx: ctx) { p, s in
            progress = p; status = s
        }
        record = r
        history = ImportEngine.history
        archive = nil
        Haptics.milestone()
        withAnimation(.spring) { stage = .done }
    }

    private func working(_ title: String, detail: String) -> some View {
        VStack(spacing: DS.Space.l) {
            Spacer()
            ZStack {
                Circle().stroke(DS.Palette.accent.opacity(0.15), lineWidth: 10)
                Circle().trim(from: 0, to: stage == .importing ? max(0.03, progress) : 0.3)
                    .stroke(DS.Palette.accent.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut, value: progress)
                Image(systemName: "square.and.arrow.down.on.square.fill").font(.system(size: 36)).foregroundStyle(DS.Palette.accent)
                    .symbolEffect(.pulse)
            }
            .frame(width: 140, height: 140)
            Text(title).font(DS.Font.headline).multilineTextAlignment(.center).lineLimit(2)
            Text(detail).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            Spacer()
        }
        .padding()
    }

    // MARK: 5. Done

    private func done(_ r: ImportEngine.Record) -> some View {
        ScrollView {
            VStack(spacing: DS.Space.l) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(DS.Palette.calm)
                    .symbolEffect(.bounce, value: r.id)
                    .padding(.top, DS.Space.xl)
                Text("Welcome home").font(DS.Font.hero)
                Text("\(r.noteIds.count) pages from \(r.source.label) are in Keel.").font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 8) {
                    if r.databases > 0 { Label("\(r.databases) database\(r.databases == 1 ? "" : "s") with their columns", systemImage: "tablecells") }
                    if r.images > 0 { Label("\(r.images) image\(r.images == 1 ? "" : "s")", systemImage: "photo") }
                    if r.links > 0 { Label("\(r.links) links between pages, still connected", systemImage: "link") }
                    if !r.taskIds.isEmpty { Label("\(r.taskIds.count) to-dos added as tasks", systemImage: "checklist") }
                    if r.skipped > 0 { Label("\(r.skipped) pages skipped because you already had them", systemImage: "arrow.uturn.right") }
                }
                .font(DS.Font.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.m)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DS.Palette.elevated))

                Button {
                    AppRouter.shared.tab = .notes
                    dismiss()
                } label: { Label("Open Notes", systemImage: "note.text").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).tint(DS.Palette.accent).controlSize(.large)
                Button { showBrain = true } label: { Label("See how it connects", systemImage: "brain.head.profile").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).controlSize(.large)
                HStack {
                    Button("Import more") { withAnimation { stage = .choose; record = nil; bundle = nil } }
                    Spacer()
                    Button("Undo import", role: .destructive) { confirmUndo = r }
                }
                .font(DS.Font.caption)
            }
            .padding()
        }
    }
}

// MARK: - How to export, per app

struct SourceGuideSheet: View {
    let source: ImportSource
    let pick: () -> Void
    let connect: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var steps: [String] {
        switch source {
        case .notion, .notionAPI: [
            "Fastest: tap Connect your workspace below and Keel imports straight from it, no files needed.",
            "Or export: in the workspace go to Settings → Export all workspace content (or ••• on a page → Export).",
            "Choose “Markdown & CSV”, include subpages, and turn on “Create folders for subpages”.",
            "Download the .zip to Files, then choose it here. Keel unzips it (even zips inside zips).",
        ]
        case .obsidian: [
            "Your vault is a folder of Markdown files. Choose that folder here (in iCloud Drive or On My iPhone).",
            "Or zip the vault on your computer and choose the .zip.",
            "[[Links]], embeds, images, callouts and properties all come across. Folders become folders and sub-pages.",
        ]
        case .evernote: [
            "On a computer, right-click a notebook → Export Notebook… → .enex.",
            "Save the .enex file to iCloud Drive and choose it here. Choose several to bring several notebooks.",
            "Each notebook becomes a folder. Images, to-dos, tags and dates come across.",
        ]
        case .keep: [
            "Go to takeout.google.com, deselect all, then select Keep and export.",
            "Save the downloaded .zip to Files and choose it here.",
            "Labels become folders, checklists become to-dos, and pinned notes become favorites.",
        ]
        case .textbundle: [
            "Export your notes as Markdown or TextBundle (most writing apps have File → Export).",
            "Choose the exported folder or .zip here. Images inside TextBundles come along.",
        ]
        case .markdown: [
            "In the Notes app: open a note, tap Share → Keel. It arrives as a note in Keel.",
            "For many at once: on a Mac, export or copy them as text, Markdown or HTML files into a folder, then choose the folder here.",
            "Any .md, .txt or .html files work, and any .csv becomes a database.",
        ]
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(steps.enumerated()), id: \.offset) { item in
                        let i = item.offset
                        let s = item.element
                        HStack(alignment: .top, spacing: DS.Space.m) {
                            Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(.white)
                                .frame(width: 22, height: 22).background(DS.Palette.accent, in: Circle())
                            Text(s).font(DS.Font.body)
                        }
                    }
                }
                Section {
                    if source == .notion {
                        Button { connect() } label: { Label("Connect your workspace", systemImage: "link.badge.plus").font(DS.Font.headline) }
                    }
                    Button { pick() } label: {
                        Label(source == .obsidian || source == .textbundle ? "Choose folder or .zip" : "Choose file", systemImage: "folder").font(DS.Font.headline)
                    }
                }
            }
            .navigationTitle(source == .markdown ? "Apple Notes & files" : source.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Connect a workspace with a token

struct NotionConnectSheet: View {
    let imported: (ImportBundle) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @State private var token = KeychainStore.read(NotionConnector.keychainKey) ?? ""
    @State private var workspace: String?
    @State private var busy = false
    @State private var progress = 0.0
    @State private var status = ""
    @State private var error: String?
    @State private var fetched: ImportBundle?
    @State private var result: ImportEngine.Record?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("1. Open the integrations page and create a new **internal** integration.")
                    Link(destination: URL(string: "https://www.notion.so/profile/integrations")!) {
                        Label("Open integrations page", systemImage: "arrow.up.right.square")
                    }
                    Text("2. Copy its **Internal Integration Secret** and paste it below.")
                    Text("3. In your workspace, open each top page you want → ••• → **Connections** → add the integration. Everything inside it comes too.")
                } header: { Text("Connect in three steps") }
                Section {
                    SecureField("Paste the secret (starts with ntn_ or secret_)", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if let workspace { Label("Connected to \(workspace)", systemImage: "checkmark.circle.fill").foregroundStyle(DS.Palette.calm) }
                    if let error { Text(error).font(DS.Font.caption).foregroundStyle(.red) }
                } footer: { Text("The secret is kept in the Keychain on this iPhone and only sent to the workspace's own servers. Remove the integration any time to revoke it.") }

                if busy {
                    Section {
                        ProgressView(value: progress) { Text(status).font(DS.Font.caption).lineLimit(1) }
                    }
                } else if let fetched {
                    Section {
                        Label("\(fetched.pages.count) pages, \(fetched.databases) databases and \(fetched.images) images ready.", systemImage: "tray.full")
                        Button { imported(fetched) } label: { Text("Review and import").font(DS.Font.headline) }
                    }
                } else {
                    Section {
                        Button {
                            Task { await connectAndFetch() }
                        } label: { Text(workspace == nil ? "Connect and read everything" : "Read everything").font(DS.Font.headline) }
                        .disabled(token.trimmingCharacters(in: .whitespaces).count < 20)
                        if KeychainStore.read(NotionConnector.keychainKey) != nil {
                            Button("Forget This Secret", role: .destructive) {
                                KeychainStore.delete(NotionConnector.keychainKey); token = ""; workspace = nil
                            }
                        }
                    }
                }
            }
            .navigationTitle("Connect Workspace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func connectAndFetch() async {
        error = nil
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = NotionConnector(token: t)
        busy = true; defer { busy = false }
        do {
            workspace = try await c.verify()
            KeychainStore.save(t, for: NotionConnector.keychainKey)
            status = "Looking for pages…"
            fetched = try await c.fetchAll { s, p in
                await MainActor.run { status = s; progress = p }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
