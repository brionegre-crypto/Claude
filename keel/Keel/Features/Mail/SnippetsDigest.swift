import SwiftUI
import SwiftData

// MARK: - Snippets (saved replies)

struct SnippetsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Snippet.uses, order: .reverse) private var snippets: [Snippet]
    @State private var editing: Snippet?
    @State private var showNew = false

    var body: some View {
        List {
            if snippets.isEmpty {
                ContentUnavailableView("No templates", systemImage: "text.badge.plus",
                                       description: Text("Save replies you send often. Add fill-ins like {name} and Keel completes them for you."))
                    .listRowBackground(Color.clear)
            }
            ForEach(snippets) { s in
                Button { editing = s } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name).font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                        Text(s.body).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                    }
                }
            }
            .onDelete { $0.map { snippets[$0] }.forEach(ctx.delete) }
        }
        .navigationTitle("Templates")
        .toolbar { Button { showNew = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add") }
        .sheet(isPresented: $showNew) { SnippetEditor(snippet: nil) }
        .sheet(item: $editing) { SnippetEditor(snippet: $0) }
        .onAppear { Snippets.seedIfNeeded(ctx) }
    }
}

struct SnippetEditor: View {
    let snippet: Snippet?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Section {
                    TextEditor(text: $text).frame(minHeight: 160)
                } header: { Text("Text") } footer: {
                    Text("Fill-ins are replaced when you insert it. Tap one to add it. Any other word in braces, like {amount}, is asked for each time.")
                }
                Section("Fill-ins") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(TemplateFill.automatic, id: \.0) { f in
                                Button(f.0) { text += f.0 }
                                    .buttonStyle(.bordered).font(.system(.caption, design: .monospaced))
                                    .accessibilityHint(f.1)
                            }
                        }
                    }
                }
            }
            .navigationTitle(snippet == nil ? "New Template" : "Edit Template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let s = snippet { s.name = name; s.body = text } else { ctx.insert(Snippet(name: name, body: text)) }
                        dismiss()
                    }
                    .disabled(name.isEmpty || text.isEmpty)
                }
            }
            .onAppear { if let s = snippet { name = s.name; text = s.body } }
        }
    }
}

@MainActor
enum Snippets {
    static func seedIfNeeded(_ ctx: ModelContext) {
        defer { seedFillInsIfNeeded(ctx) }
        guard ((try? ctx.fetchCount(FetchDescriptor<Snippet>())) ?? 0) == 0 else { return }
        for (n, b) in [
            ("Thanks!", "Thanks so much, I really appreciate it."),
            ("Let me check", "Good question. Let me check and get back to you by tomorrow."),
            ("Running late", "Running about 10 minutes late, sorry! See you shortly."),
            ("Not right now", "Thanks for thinking of me. I can't take this on right now, but please keep me in mind for the future."),
            ("Book a time", "Happy to chat. What times work for you this week?"),
        ] { ctx.insert(Snippet(name: n, body: b)) }
    }

    /// Adds two example templates with fill-ins, once, for people who already had snippets.
    static func seedFillInsIfNeeded(_ ctx: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: "templates.fillins.seeded") else { return }
        UserDefaults.standard.set(true, forKey: "templates.fillins.seeded")
        ctx.insert(Snippet(name: "Follow up", body: "Hi {name},\n\nJust following up on {subject}. Any update on your side?\n\nThanks,\n{me}"))
        ctx.insert(Snippet(name: "Invoice sent", body: "Hi {name},\n\nI've sent invoice {invoice number} for {amount}, due {due date}. Let me know if you need anything else.\n\nThanks,\n{me}"))
    }
}

/// Fill-ins for templates: {name}, {firstname}, {company}, {date}, {tomorrow}, {weekday}, {subject}, {me}.
/// Anything else in braces, like {amount}, is asked for when you insert the template.
@MainActor
enum TemplateFill {
    static let automatic: [(String, String)] = [
        ("{name}", "Their first name"), ("{fullname}", "Their full name"), ("{company}", "Their company, from their email"),
        ("{date}", "Today's date"), ("{tomorrow}", "Tomorrow's date"), ("{weekday}", "Today's weekday"),
        ("{subject}", "The email's subject"), ("{me}", "Your name"),
    ]

    struct Context {
        var to = ""
        var recipientName = ""
        var subject = ""
    }

    static func autoValues(_ c: Context) -> [String: String] {
        let address = ComposeDraft.addressList(c.to).first ?? ""
        var full = c.recipientName.trimmingCharacters(in: .whitespaces)
        if full.isEmpty || full.contains("@") {
            // sam.lee@acme.com → "Sam Lee"
            let local = address.split(separator: "@").first.map(String.init) ?? ""
            full = local.split(whereSeparator: { ".-_".contains($0) }).map { $0.capitalized }.joined(separator: " ")
        }
        let first = full.split(separator: " ").first.map(String.init) ?? ""
        let domain = address.split(separator: "@").last.map(String.init) ?? ""
        let personal = ["gmail", "icloud", "me", "mac", "outlook", "hotmail", "live", "yahoo", "aol", "proton", "protonmail", "fastmail"]
        let root = domain.split(separator: ".").dropLast().last.map(String.init) ?? ""
        let company = personal.contains(root.lowercased()) ? "" : root.capitalized
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let subject = c.subject.replacingOccurrences(of: #"^((re|fwd?):\s*)+"#, with: "", options: [.regularExpression, .caseInsensitive])
        return [
            "{name}": first, "{firstname}": first, "{fullname}": full, "{company}": company,
            "{date}": Date().formatted(date: .long, time: .omitted),
            "{tomorrow}": tomorrow.formatted(date: .long, time: .omitted),
            "{weekday}": Date().formatted(.dateTime.weekday(.wide)),
            "{subject}": subject, "{me}": myName,
        ]
    }

    static var myName: String {
        if let saved = UserDefaults.standard.string(forKey: "profile.name"), !saved.isEmpty { return saved }
        let fact = KeelMemory.shared.facts.first { $0.lowercased().hasPrefix("call me ") }
        return fact.map { String($0.dropFirst(8)).trimmingCharacters(in: .whitespaces) } ?? ""
    }

    /// Placeholders that still need you after the automatic ones are filled (in order, no repeats).
    static func blanks(in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"\{[^{}\n]{1,30}\}"#) else { return [] }
        let ns = text as NSString
        var seen = Set<String>(), out: [String] = []
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: m.range)
            if seen.insert(token.lowercased()).inserted { out.append(token) }
        }
        return out
    }

    /// Fills automatic values; empty ones (e.g. no recipient yet) are left as blanks to ask about.
    static func fillAutomatic(_ text: String, _ c: Context) -> String {
        var out = text
        for (k, v) in autoValues(c) where !v.isEmpty {
            out = out.replacingOccurrences(of: k, with: v, options: .caseInsensitive)
        }
        return out
    }

    static func label(for token: String) -> String {
        let inner = token.dropFirst().dropLast()
        return inner.prefix(1).uppercased() + inner.dropFirst()
    }
}

/// Compose-screen menu that inserts a template (saved reply), filling in names, dates and blanks.
struct SnippetMenu: View {
    @Binding var text: String
    var to: String = ""
    var recipientName: String = ""
    var subject: String = ""
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Snippet.uses, order: .reverse) private var snippets: [Snippet]
    @State private var asking: PendingFill?

    struct PendingFill: Identifiable {
        let id = UUID()
        var body: String
        var blanks: [String]
    }

    private func insert(_ body: String) {
        if let r = text.range(of: "\n\nOn ") ?? text.range(of: "\n\n---------- Forwarded") {
            text.insert(contentsOf: body, at: r.lowerBound)
        } else {
            text = body + text
        }
        Haptics.tap()
    }

    private func use(_ s: Snippet) {
        s.uses += 1
        let filled = TemplateFill.fillAutomatic(s.body, .init(to: to, recipientName: recipientName, subject: subject))
        let blanks = TemplateFill.blanks(in: filled)
        if blanks.isEmpty { insert(filled) } else { asking = PendingFill(body: filled, blanks: blanks) }
    }

    var body: some View {
        Menu {
            ForEach(snippets) { s in
                Button { use(s) } label: {
                    Label(s.name, systemImage: s.body.contains("{") ? "curlybraces" : "text.quote")
                }
            }
            Divider()
            Button("Insert my availability", systemImage: "calendar.badge.clock") { insert(Availability.text()) }
            NavigationLink { SnippetsView() } label: { Label("Edit templates", systemImage: "pencil") }
        } label: { Image(systemName: "text.badge.plus") }
        .accessibilityLabel("Insert template")
        .onAppear { Snippets.seedIfNeeded(ctx) }
        .sheet(item: $asking) { p in
            FillBlanksSheet(pending: p) { insert($0) }
        }
    }
}

/// Asks for the blanks in a template, e.g. {amount} or {meeting day}, then inserts it.
struct FillBlanksSheet: View {
    let pending: SnippetMenu.PendingFill
    let done: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @FocusState private var focused: String?

    private var preview: String {
        var out = pending.body
        for b in pending.blanks {
            let v = values[b, default: ""]
            if !v.isEmpty { out = out.replacingOccurrences(of: b, with: v, options: .caseInsensitive) }
        }
        return out
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(pending.blanks, id: \.self) { b in
                        TextField(TemplateFill.label(for: b), text: Binding(get: { values[b, default: ""] }, set: { values[b] = $0 }))
                            .focused($focused, equals: b)
                            .submitLabel(b == pending.blanks.last ? .done : .next)
                            .onSubmit {
                                if let i = pending.blanks.firstIndex(of: b), i + 1 < pending.blanks.count { focused = pending.blanks[i + 1] }
                            }
                    }
                } footer: { Text("Leave one empty to keep it as a blank you can type over.") }
                Section("Preview") { Text(preview).font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft) }
            }
            .navigationTitle("Fill In").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Insert") { done(preview); dismiss() } }
            }
            .onAppear { focused = pending.blanks.first }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Newsletter digest

/// Today's newsletters and promotions in one calm screen, with a combined summary and "archive all".
struct DigestView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \EmailMessage.receivedAt, order: .reverse) private var mail: [EmailMessage]
    @Query private var accounts: [MailAccount]
    @State private var briefing: String?
    @State private var summarizing = false

    private var items: [EmailMessage] {
        mail.filter { !$0.isArchived && ($0.category == .newsletters || $0.category == .promotions || $0.category == .updates)
            && $0.receivedAt > Date().addingTimeInterval(-36 * 3600) }
    }

    var body: some View {
        List {
            Section {
                if let briefing {
                    Label(briefing, systemImage: "sparkles").font(DS.Font.body)
                } else {
                    Button(summarizing ? "Summarizing…" : "Summarize all \(items.count)") { Task { await summarize() } }
                        .disabled(summarizing || items.isEmpty)
                }
            } header: { Text("Briefing") }
            ForEach(items) { e in
                NavigationLink { EmailDetailView(email: e) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.fromName.isEmpty ? e.from : e.fromName).font(DS.Font.headline)
                        Text(e.aiSummary ?? e.subject).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(3)
                    }
                }
            }
            if !items.isEmpty {
                Section {
                    Button("Archive all \(items.count)") {
                        let list = items
                        for e in list { e.isArchived = true }
                        Haptics.success()
                        UndoCenter.shared.offer("Archived \(list.count)", undo: { list.forEach { $0.isArchived = false } }, commit: {
                            for e in list {
                                if let a = accounts.first(where: { $0.id == e.accountId }) {
                                    let id = e.providerMessageId
                                    Task { try? await MailProviderFactory.make(for: a).archive(id) }
                                }
                            }
                        })
                    }
                }
            } else {
                ContentUnavailableView("No newsletters today", systemImage: "newspaper", description: Text("Newsletters, updates and promotions from the last day show up here."))
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Digest")
    }

    private func summarize() async {
        summarizing = true; defer { summarizing = false }
        let text = items.prefix(20).map { "\($0.fromName.isEmpty ? $0.from : $0.fromName): \($0.aiSummary ?? $0.subject)" }.joined(separator: "\n")
        briefing = await AIRouter.shared.summarize("Today's newsletters and updates. Give the 3–5 most useful points:\n" + text)
    }
}
