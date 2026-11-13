import SwiftUI
import SwiftData

// MARK: - Auto-drafts: replies written before you open the email

/// After each sync, Keel writes a reply in your voice for new mail from real people that needs one.
/// It's waiting when you open the email; nothing is ever sent without you.
@MainActor
enum AutoDrafts {
    static let onKey = "mail.autodrafts"
    static var isOn: Bool { UserDefaults.standard.object(forKey: onKey) as? Bool ?? AIRouter.shared.onDeviceAvailable }

    private static var url: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("mail-autodrafts.json") }
    private static var _store: [String: String]?
    private static var store: [String: String] {
        get {
            if let s = _store { return s }
            let s = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
            _store = s
            return s
        }
        set {
            var v = newValue
            if v.count > 300 { v = Dictionary(uniqueKeysWithValues: v.suffix(200).map { ($0.key, $0.value) }) }
            _store = v
            try? JSONEncoder().encode(v).write(to: url, options: .atomic)
        }
    }
    private static var working = false

    static func draft(for id: String) -> String? { store[id] }
    static func has(_ id: String) -> Bool { store[id] != nil }
    static func clear(_ id: String) { store[id] = nil }
    static func setDraft(_ id: String, _ text: String) { store[id] = text }

    /// Only real people: never companies, shops, newsletters, notifications or no-reply addresses.
    static func isRealPerson(_ e: EmailMessage) -> Bool {
        if MailNoise.isAutomated(e) || e.unsubscribeHeader != nil { return false }
        if [.newsletters, .promotions, .updates, .lowPriority].contains(e.category) { return false }
        let addr = e.from.lowercased()
        let local = String(addr.split(separator: "@").first ?? "")
        let businessBoxes = ["info", "hello", "hi", "support", "help", "team", "contact", "sales", "billing", "accounts", "admin", "office",
                             "service", "services", "customerservice", "care", "orders", "order", "shop", "store", "marketing", "news",
                             "newsletter", "notifications", "notification", "alerts", "updates", "mail", "mailer", "bounce", "reply",
                             "noreply", "no-reply", "donotreply", "do-not-reply", "feedback", "jobs", "careers", "hr", "events", "membership", "booking", "reservations"]
        if businessBoxes.contains(local) || local.contains("noreply") || local.contains("no-reply") || local.contains("notify") { return false }
        // A business name shown instead of a person's ("Acme Inc", "The Shop Team").
        let name = e.fromName.lowercased()
        if ["inc", "llc", "ltd", "corp", "company", "team", "support", "store", "shop", "bank", "services", "group", "official", "hq", "app"]
            .contains(where: { name.split(separator: " ").map(String.init).contains($0) }) { return false }
        return true
    }

    static func needsReply(_ e: EmailMessage, mine: Set<String>) -> Bool {
        guard !e.isRead, !e.isArchived, !mine.contains(e.from.lowercased()), isRealPerson(e) else { return false }
        guard e.category == .important || e.category == .actionable || e.category == nil else { return false }
        let text = (e.subject + " " + e.bodyPlain.prefix(1_500)).lowercased()
        return text.contains("?") || ["can you", "could you", "would you", "let me know", "please", "thoughts", "are you", "do you"].contains { text.contains($0) }
    }

    static func generate(_ fresh: [EmailMessage], accounts: [MailAccount]) {
        guard isOn, !working, AIRouter.shared.onDeviceAvailable || AIRouter.shared.cloudEnabled else { return }
        let mine = Set(accounts.map { $0.address.lowercased() })
        let picks = fresh.filter { needsReply($0, mine: mine) && store[$0.id] == nil }.prefix(6)
        guard !picks.isEmpty else { return }
        working = true
        Task {
            defer { working = false }
            for e in picks {
                // Drafts are always written by Apple Intelligence on this device when it's available (free, private).
                let intent = "Write the reply I'd most likely send, in my usual voice. If it needs a decision or a fact only I know, leave a short [bracketed] placeholder instead of guessing."
                if let d = await AIRouter.shared.draftReply(to: e, intent: intent), !d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    store[e.id] = d
                }
            }
        }
    }
}

// MARK: - Ask your inbox

/// Questions answered from your own mail, with the emails it used.
@MainActor
enum MailAsk {
    private static let stop: Set<String> = ["the", "and", "for", "what", "when", "where", "who", "did", "does", "about", "with", "from", "that", "this", "have", "has", "was", "were", "are", "is", "my", "me", "you", "your", "say", "said", "tell", "any", "how", "much", "many", "which", "there", "their", "they", "email", "emails", "mail"]

    static func search(_ q: String, in mail: [EmailMessage], limit: Int = 12) -> [EmailMessage] {
        let words = q.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 && !stop.contains($0) }
        guard !words.isEmpty else { return Array(mail.prefix(limit)) }
        let scored = mail.compactMap { e -> (EmailMessage, Double)? in
            let subj = e.subject.lowercased(), who = (e.fromName + " " + e.from).lowercased(), body = e.bodyPlain.prefix(4_000).lowercased()
            var s = 0.0
            for w in words {
                if subj.contains(w) { s += 3 }
                if who.contains(w) { s += 2.5 }
                if body.contains(w) { s += 1 }
            }
            guard s > 0 else { return nil }
            s += max(0, 1 - Date().timeIntervalSince(e.receivedAt) / (60 * 86_400))   // newer wins ties
            return (e, s)
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    static func answer(_ q: String, sources: [EmailMessage]) async -> String {
        guard !sources.isEmpty else { return "I couldn't find any emails about that." }
        let ctx = sources.enumerated().map { i, e in
            "[\(i + 1)] From \(e.fromName.isEmpty ? e.from : e.fromName), \(e.receivedAt.formatted(date: .abbreviated, time: .shortened)), subject “\(e.subject)”:\n\(GmailProvider.stripQuotedReply(e.bodyPlain).prefix(700))"
        }.joined(separator: "\n\n")
        let prompt = """
        Answer the question using only these emails. Be brief and specific (names, dates, numbers, addresses). \
        Cite the emails you used like [1] or [2]. If they don't contain the answer, say so.

        QUESTION: \(q)

        EMAILS:
        \(ctx.prefix(9_000))
        """
        return await AIRouter.shared.write(prompt) ?? "Keel's AI isn't available right now. The closest emails are below."
    }
}

struct AskInboxView: View {
    @Query(InboxView.recentMail) private var mail: [EmailMessage]
    @State private var question = ""
    @State private var answer: String?
    @State private var sources: [EmailMessage] = []
    @State private var working = false
    @FocusState private var focused: Bool

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("e.g. What's the address for Saturday's party?", text: $question, axis: .vertical)
                        .focused($focused).onSubmit { Task { await ask() } }
                    Button { Task { await ask() } } label: {
                        if working { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    }
                    .disabled(question.trimmingCharacters(in: .whitespaces).count < 3 || working)
                }
            } footer: { Text("Keel searches your mail on this device and answers from it, citing the emails it used.") }
            if let answer {
                Section("Answer") { Text(answer).textSelection(.enabled) }
            }
            if !sources.isEmpty {
                Section("From these emails") {
                    ForEach(Array(sources.enumerated()), id: \.element.id) { i, e in
                        NavigationLink { EmailDetailView(email: e) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("[\(i + 1)] \(e.subject)").font(DS.Font.body).lineLimit(1)
                                Text("\(e.fromName.isEmpty ? e.from : e.fromName) · \(e.receivedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption).foregroundStyle(DS.Palette.inkSoft)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Ask your inbox")
        .onAppear { focused = true }
    }

    private func ask() async {
        let q = question.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3 else { return }
        working = true; defer { working = false }
        sources = MailAsk.search(q, in: Array(mail))
        answer = await MailAsk.answer(q, sources: sources)
    }
}

// MARK: - Best time to send

@MainActor
enum BestSendTime {
    /// When this person usually writes (and so reads) mail: their most common weekday hour, next time it comes round.
    static func suggest(for recipient: String) -> Date? {
        let addr = recipient.lowercased().trimmingCharacters(in: .whitespaces)
        guard addr.contains("@") else { return nil }
        let ctx = KeelStore.container.mainContext
        var d = FetchDescriptor<EmailMessage>(predicate: #Predicate { $0.from == addr }, sortBy: [SortDescriptor(\.receivedAt, order: .reverse)])
        d.fetchLimit = 60
        let theirs = (try? ctx.fetch(d)) ?? []
        guard theirs.count >= 4 else { return nil }
        let cal = Calendar.current
        let hours = theirs.map { cal.component(.hour, from: $0.receivedAt) }.filter { (6...21).contains($0) }
        guard let best = Dictionary(grouping: hours, by: { $0 }).max(by: { $0.value.count < $1.value.count })?.key else { return nil }
        var day = Date()
        for _ in 0..<8 {
            if let t = cal.date(bySettingHour: best, minute: 5, second: 0, of: day), t > Date().addingTimeInterval(30 * 60), !cal.isDateInWeekend(t) { return t }
            day = cal.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return nil
    }
}

// MARK: - Follow-up nudges 2.0

@MainActor
enum SmartNudge {
    /// A short, natural bump written for this thread (falls back to the simple one).
    static func draft(_ f: FollowUp) async -> ComposeDraft {
        var d = FollowUps.nudgeDraft(f)
        let days = max(1, Int(Date().timeIntervalSince(f.sentAt) / 86_400))
        let prompt = """
        Write a short, friendly follow-up email (2 or 3 sentences) to \(f.recipientName.isEmpty ? f.recipient : f.recipientName) \
        about "\(f.subject)", which I sent \(days) day\(days == 1 ? "" : "s") ago without a reply. Warm, not pushy, \
        make it easy to answer (offer a simple yes/no or next step). Start with a greeting, end with a thanks. Reply with only the email body.
        """
        if let body = await AIRouter.shared.write(prompt), body.count > 20 { d.body = body.trimmingCharacters(in: .whitespacesAndNewlines) }
        return d
    }
}
