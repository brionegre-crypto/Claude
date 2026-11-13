import SwiftUI
import SwiftData

// MARK: - Inbox tabs: order, hide, and your own (by sender, by words, or described in plain words for the AI)

struct CustomMailTab: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var icon: String = "tag"
    var senders: [String] = []           // addresses or domains, e.g. "dana@acme.com", "@acme.com"
    var keywords: [String] = []          // words in the subject or preview
    var aiRule: String = ""              // "anything from investors or about the fundraise"
    var key: String { "c:" + id.uuidString }
}

struct MailTabItem: Identifiable, Hashable {
    let id: String                       // InboxTab rawValue or "c:<uuid>"
    let title: String
    let icon: String
}

@MainActor
enum MailTabs {
    static let orderKey = "mail.tabs.order", hiddenKey = "mail.tabs.hidden", customKey = "mail.tabs.custom"

    static var custom: [CustomMailTab] {
        get { UserDefaults.standard.data(forKey: customKey).flatMap { try? JSONDecoder().decode([CustomMailTab].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: customKey) }
    }
    static var hidden: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: hiddenKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: hiddenKey) }
    }
    static var order: [String] {
        get { UserDefaults.standard.stringArray(forKey: orderKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: orderKey) }
    }

    /// Every tab in your order (built-in and your own), including hidden ones.
    static var allItems: [MailTabItem] {
        let builtIn = InboxTab.allCases.map { MailTabItem(id: $0.rawValue, title: $0 == .quick ? "Quick" : $0.title, icon: $0.icon) }
        let mine = custom.map { MailTabItem(id: $0.key, title: $0.name, icon: $0.icon) }
        let pool = builtIn + mine
        let ordered = order.compactMap { id in pool.first { $0.id == id } }
        return ordered + pool.filter { p in !ordered.contains { $0.id == p.id } }
    }
    /// The tabs shown above the inbox. All always stays, so nothing can disappear.
    static var visibleItems: [MailTabItem] {
        let h = hidden
        return allItems.filter { $0.id == InboxTab.all.rawValue || !h.contains($0.id) }
    }

    static func tab(for key: String) -> CustomMailTab? {
        guard key.hasPrefix("c:") else { return nil }
        return custom.first { $0.key == key }
    }

    static func matches(_ e: EmailMessage, _ t: CustomMailTab) -> Bool {
        let from = e.from.lowercased()
        if t.senders.contains(where: { s in let x = s.lowercased().trimmingCharacters(in: .whitespaces); return !x.isEmpty && from.contains(x) }) { return true }
        if !t.keywords.isEmpty {
            let hay = (e.subject + " " + e.snippet).lowercased()
            if t.keywords.contains(where: { k in let x = k.lowercased().trimmingCharacters(in: .whitespaces); return !x.isEmpty && hay.contains(x) }) { return true }
        }
        if !t.aiRule.isEmpty, aiCache[e.id]?.contains(t.id.uuidString) == true { return true }
        return false
    }

    // MARK: AI sorting (described in plain words)

    private static var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("mail-ai-tabs.json")
    }
    private static var _cache: [String: [String]]?
    /// email id → custom tab ids the AI put it in.
    static var aiCache: [String: [String]] {
        get {
            if let c = _cache { return c }
            let c = (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
            _cache = c
            return c
        }
        set {
            var v = newValue
            if v.count > 6_000 { v = Dictionary(uniqueKeysWithValues: v.suffix(4_000).map { ($0.key, $0.value) }) }
            _cache = v
            try? JSONEncoder().encode(v).write(to: cacheURL, options: .atomic)
        }
    }

    /// Sorts new mail into tabs that have a plain-words rule. Runs quietly after each sync.
    static func classifyInBackground(_ fresh: [EmailMessage]) {
        let rules = custom.filter { !$0.aiRule.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !rules.isEmpty, !fresh.isEmpty, AIRouter.shared.onDeviceAvailable || AIRouter.shared.cloudEnabled else { return }
        let items = fresh.prefix(36).map { (id: $0.id, line: "\($0.fromName.isEmpty ? $0.from : $0.fromName) <\($0.from)> | \($0.subject) | \($0.snippet.prefix(120))") }
        Task { await classify(Array(items), rules: rules) }
    }

    /// Re-sort recent mail after you add or change a rule.
    static func resort(_ emails: [EmailMessage], rule: CustomMailTab) async -> Int {
        let items = emails.prefix(120).map { (id: $0.id, line: "\($0.fromName.isEmpty ? $0.from : $0.fromName) <\($0.from)> | \($0.subject) | \($0.snippet.prefix(120))") }
        return await classify(Array(items), rules: [rule])
    }

    @discardableResult
    private static func classify(_ items: [(id: String, line: String)], rules: [CustomMailTab]) async -> Int {
        var cache = aiCache
        var hits = 0
        for rule in rules {
            for start in stride(from: 0, to: items.count, by: 12) {
                let batch = Array(items[start..<min(start + 12, items.count)])
                let list = batch.enumerated().map { "\($0.offset + 1). \($0.element.line)" }.joined(separator: "\n")
                let prompt = """
                Inbox tab "\(rule.name)" holds: \(rule.aiRule)
                Which of these emails belong in it? Reply with only their numbers, comma-separated, or NONE.

                \(list)
                """
                guard let r = await AIRouter.shared.write(prompt) else { continue }
                let picked = Set(r.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init))
                for (i, item) in batch.enumerated() {
                    var tabs = cache[item.id] ?? []
                    tabs.removeAll { $0 == rule.id.uuidString }
                    if picked.contains(i + 1) { tabs.append(rule.id.uuidString); hits += 1 }
                    cache[item.id] = tabs.isEmpty ? nil : tabs
                }
            }
        }
        aiCache = cache
        return hits
    }
}

struct InboxTabsSettings: View {
    @State private var items = MailTabs.allItems
    @State private var hidden = MailTabs.hidden
    @State private var editing: CustomMailTab?

    var body: some View {
        List {
            Section {
                ForEach(items) { item in
                    HStack {
                        Label(item.title, systemImage: item.icon)
                        Spacer()
                        if item.id.hasPrefix("c:"), let t = MailTabs.tab(for: item.id) {
                            Button("Edit") { editing = t }.buttonStyle(.borderless).font(.caption)
                        }
                        if item.id != InboxTab.all.rawValue {
                            Toggle("", isOn: Binding(get: { !hidden.contains(item.id) }, set: { on in
                                if on { hidden.remove(item.id) } else { hidden.insert(item.id) }
                                MailTabs.hidden = hidden
                            })).labelsHidden()
                        }
                    }
                }
                .onMove { from, to in
                    items.move(fromOffsets: from, toOffset: to)
                    MailTabs.order = items.map(\.id)
                }
            } header: { Text("Tabs") } footer: {
                Text("Drag to reorder (tap Edit at the top), switch off the ones you don't use. All always stays so no email is ever out of reach.")
            }
            Section {
                Button("New tab", systemImage: "plus") { editing = CustomMailTab(name: "") }
            } footer: {
                Text("Make a tab for clients, family, a project or anything else. Pick senders, words, or just describe it and Keel's AI sorts mail into it.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Inbox tabs")
        .sheet(item: $editing, onDismiss: { items = MailTabs.allItems }) { CustomMailTabEditor(tab: $0) }
    }
}

struct CustomMailTabEditor: View {
    @State var tab: CustomMailTab
    @Environment(\.dismiss) private var dismiss
    @Query(InboxView.recentMail) private var mail: [EmailMessage]
    @State private var senders = ""
    @State private var keywords = ""
    @State private var sorting = false
    private let icons = ["tag", "briefcase", "person.2", "house", "dollarsign.circle", "airplane", "graduationcap", "heart", "cart", "star", "hammer", "chart.line.uptrend.xyaxis"]

    private var isNew: Bool { !MailTabs.custom.contains { $0.id == tab.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Clients", text: $tab.name)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(icons, id: \.self) { i in
                                Button { tab.icon = i } label: {
                                    Image(systemName: i).frame(width: 34, height: 34)
                                        .background(tab.icon == i ? DS.Palette.accent.opacity(0.2) : DS.Palette.elevated, in: .rect(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Section {
                    TextField("Describe it, e.g. anything from investors or about the fundraise", text: $tab.aiRule, axis: .vertical)
                } header: { Text("In plain words (AI)") } footer: {
                    Text("Keel's AI reads each new email and puts matching ones here. Optional.")
                }
                Section {
                    TextField("dana@acme.com, @acme.com", text: $senders, axis: .vertical).textInputAutocapitalization(.never).keyboardType(.emailAddress)
                    TextField("invoice, contract, Project Atlas", text: $keywords, axis: .vertical)
                } header: { Text("Exact rules") } footer: { Text("Senders (addresses or @domains) and words, separated by commas. Any match counts.") }
                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            MailTabs.custom.removeAll { $0.id == tab.id }
                            dismiss()
                        } label: { Text("Delete tab") }
                    }
                }
            }
            .navigationTitle(isNew ? "New tab" : tab.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sorting ? "Sorting…" : "Save") { Task { await save() } }
                        .disabled(tab.name.trimmingCharacters(in: .whitespaces).isEmpty || sorting)
                }
            }
            .onAppear { senders = tab.senders.joined(separator: ", "); keywords = tab.keywords.joined(separator: ", ") }
        }
    }

    private func save() async {
        func split(_ s: String) -> [String] { s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        tab.senders = split(senders)
        tab.keywords = split(keywords)
        var all = MailTabs.custom
        if let i = all.firstIndex(where: { $0.id == tab.id }) { all[i] = tab } else { all.append(tab) }
        MailTabs.custom = all
        if !tab.aiRule.trimmingCharacters(in: .whitespaces).isEmpty {
            sorting = true
            _ = await MailTabs.resort(Array(mail.filter { !$0.isArchived }.prefix(120)), rule: tab)
            sorting = false
        }
        Haptics.success()
        dismiss()
    }
}
