import SwiftUI
import SwiftData

// Mail power features: Instant Intro, Get Me to Zero, mute a conversation, a sender profile, share a conversation,
// plus Keel's own: a tone check before you send, and a kinder send time late at night.

// MARK: - Mute a conversation (new replies skip the inbox)

@MainActor
enum MutedThreads {
    private static let key = "mail.mutedThreads"
    static var all: Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
    static func isMuted(_ threadId: String) -> Bool { !threadId.isEmpty && all.contains(threadId) }
    static func set(_ threadId: String, muted: Bool) {
        guard !threadId.isEmpty else { return }
        var s = all
        if muted { s.insert(threadId) } else { s.remove(threadId) }
        UserDefaults.standard.set(Array(s.suffix(500)), forKey: key)
    }

    /// New mail in a muted conversation is archived straight away (here and on the server).
    static func apply(to fresh: [EmailMessage], accounts: [MailAccount]) async {
        let muted = all
        guard !muted.isEmpty else { return }
        for e in fresh where muted.contains(e.threadId) && !e.isArchived {
            e.isArchived = true
            if let a = accounts.first(where: { $0.id == e.accountId }) {
                try? await MailProviderFactory.make(for: a).archive(e.providerMessageId)
            }
        }
    }
}

// MARK: - Instant Intro

enum InstantIntro {
    /// Someone introduced you: reply to the person they introduced, thank the introducer and move them to Bcc.
    static func canApply(_ d: ComposeDraft) -> Bool {
        guard let o = d.original else { return false }
        return !ComposeDraft.addressList(o.ccLine).isEmpty || ComposeDraft.addressList(o.toLine).count > 1
    }

    static func apply(_ d: inout ComposeDraft, myAddresses: Set<String>) {
        guard let o = d.original else { return }
        let introducer = o.from
        let people = (ComposeDraft.addressList(o.toLine) + ComposeDraft.addressList(o.ccLine))
            .filter { !myAddresses.contains($0.lowercased()) && $0.lowercased() != introducer.lowercased() }
        guard !people.isEmpty else { return }
        d.to = people.joined(separator: ", ")
        d.cc = ""
        d.bcc = ([d.bcc].filter { !$0.isEmpty } + [introducer]).joined(separator: ", ")
        let first = o.fromName.split(separator: " ").first.map(String.init) ?? "for the intro"
        let thanks = o.fromName.isEmpty ? "Thanks for the intro (moving you to bcc)!" : "Thanks \(first) (moving you to bcc)!"
        d.body = thanks + "\n\n" + d.body
    }
}

// MARK: - Tone check (before you send)

@MainActor
enum ToneCheck {
    /// Quick checks on this device, no AI needed.
    static func flags(_ body: String) -> [String] {
        let text = body.components(separatedBy: "\n>").first ?? body           // your words, not the quoted email
        let low = text.lowercased()
        var out: [String] = []
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let shouting = words.filter { $0.count > 2 && $0 == $0.uppercased() && $0.contains(where: \.isLetter) }.count
        if shouting >= 2 { out.append("Several words in capitals can read as shouting.") }
        if text.filter({ $0 == "!" }).count >= 4 { out.append("Lots of exclamation marks.") }
        for phrase in ["per my last email", "as i said", "as previously stated", "as i already", "obviously", "just to be clear", "not sure why", "i don't understand why", "asap"]
        where low.contains(phrase) { out.append("“\(phrase)” can come across as sharp.") }
        if words.count > 250 { out.append("It's long (\(words.count) words). The ask may get lost; consider leading with it.") }
        if !low.contains("?") && ["can you", "could you", "please"].allSatisfy({ !low.contains($0) }) && words.count > 60 {
            out.append("There's no clear ask. Say what you need from them.")
        }
        return out
    }

    /// Apple Intelligence (or your AI) reads it the way the recipient might, and offers a calmer version.
    static func review(_ body: String) async -> (note: String, softer: String?)? {
        let text = body.components(separatedBy: "\n>").first ?? body
        guard let r = await AIRouter.shared.write("""
        Read this email the way the recipient might. In one or two short sentences, say how it comes across (warm, neutral, curt, anxious, demanding) and anything likely to be misread. Then write SOFTER: followed by a version that keeps the meaning but reads calm and friendly. Reply with only that.

        \(text.prefix(4_000))
        """) else { return nil }
        let parts = r.components(separatedBy: "SOFTER:")
        let note = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? r
        let softer = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil
        return (note, softer?.isEmpty == true ? nil : softer)
    }
}

// MARK: - A kinder send time

enum KindTime {
    /// Late at night or very early, the next 8 AM (so you're not training people to expect midnight replies).
    static func suggestion(now: Date = Date()) -> Date? {
        let cal = Calendar.current
        let h = cal.component(.hour, from: now)
        guard h >= 21 || h < 6 else { return nil }
        let base = h >= 21 ? (cal.date(byAdding: .day, value: 1, to: now) ?? now) : now
        return cal.date(bySettingHour: 8, minute: 0, second: 0, of: base)
    }
}

// MARK: - Share a conversation

enum ConversationText {
    static func text(_ emails: [EmailMessage]) -> String {
        emails.sorted { $0.receivedAt < $1.receivedAt }.map { e in
            "From: \(e.fromName.isEmpty ? e.from : "\(e.fromName) <\(e.from)>")\nDate: \(e.receivedAt.formatted(date: .abbreviated, time: .shortened))\nSubject: \(e.subject)\n\n\(GmailProvider.stripQuotedReply(e.bodyPlain).trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        .joined(separator: "\n\n———\n\n")
    }
}

// MARK: - Sender profile

/// Everything Keel knows about who sent this: how often they write, whether you reply, recent subjects,
/// their contact card and your notes, and one-tap VIP, block-style screening and a web search.
struct SenderProfileView: View {
    let address: String
    let name: String
    @Environment(\.modelContext) private var ctx
    @Environment(\.openURL) private var openURL
    @State private var emails: [EmailMessage] = []
    @State private var score: SenderScore?
    @State private var person: Person?

    private var domain: String { String(address.split(separator: "@").last ?? "") }
    private var company: String {
        let parts = domain.split(separator: ".")
        guard parts.count >= 2 else { return domain }
        let core = String(parts[parts.count - 2])
        return ["gmail", "icloud", "outlook", "hotmail", "yahoo", "me", "mac", "aol", "proton", "protonmail"].contains(core) ? "" : core.capitalized
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Text(initials).font(.title2.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: 56, height: 56).background(DS.Palette.accent.gradient, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name.isEmpty ? address : name).font(DS.Font.headline)
                        Text(address).font(.caption).foregroundStyle(DS.Palette.inkSoft).textSelection(.enabled)
                        if !company.isEmpty { Label(company, systemImage: "building.2").font(.caption).foregroundStyle(DS.Palette.inkSoft) }
                    }
                }
            }
            Section("Between you") {
                stat("Emails from them", "\(emails.count)")
                if let first = emails.last { stat("First email", first.receivedAt.formatted(date: .abbreviated, time: .omitted)) }
                if let last = emails.first { stat("Latest", last.receivedAt.formatted(.relative(presentation: .named))) }
                stat("You replied", "\(score?.replies ?? 0) time\((score?.replies ?? 0) == 1 ? "" : "s")")
                stat("Unread now", "\(emails.filter { !$0.isRead && !$0.isArchived }.count)")
                if MailNoise.isAutomated(emails.first ?? EmailMessage.placeholder) { Label("Looks automated (newsletters, alerts or receipts)", systemImage: "gearshape.2").font(.caption) }
            }
            if !emails.isEmpty {
                Section("Recent") {
                    ForEach(emails.prefix(6)) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.subject.isEmpty ? "(no subject)" : e.subject).lineLimit(1)
                            Text(e.receivedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                }
            }
            if let person {
                Section("In Keep in touch") {
                    stat("Last in touch", person.lastContact?.formatted(.relative(presentation: .named)) ?? "Not yet")
                    if !person.notes.isEmpty { Text(person.notes).font(.callout) }
                }
            }
            Section {
                Button(score?.isVIP == true ? "Remove VIP" : "Make VIP", systemImage: score?.isVIP == true ? "star.slash" : "star") {
                    InboxBrain.setVIP(!(score?.isVIP ?? false), sender: address, name: name, ctx: ctx); load(); Haptics.tap()
                }
                if person == nil {
                    Button("Add to Keep in touch", systemImage: "person.badge.plus") {
                        let p = Person(name: name.isEmpty ? address : name); p.email = address; ctx.insert(p); try? ctx.save(); load()
                    }
                }
                Button("Text them", systemImage: "message") { AppleMessages.compose(email: address, name: name.isEmpty ? nil : name, context: nil) }
                if !company.isEmpty || !name.isEmpty {
                    Button("Look them up on the web", systemImage: "safari") {
                        let q = [name, company].filter { !$0.isEmpty }.joined(separator: " ")
                        if let u = URL(string: "https://duckduckgo.com/?q=" + (q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) { openURL(u) }
                    }
                }
            }
        }
        .navigationTitle("Sender")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    private var initials: String {
        let n = name.isEmpty ? address : name
        return n.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private func stat(_ t: String, _ v: String) -> some View {
        HStack { Text(t); Spacer(); Text(v).foregroundStyle(DS.Palette.inkSoft).monospacedDigit() }
    }

    private func load() {
        let a = address.lowercased()
        var d = FetchDescriptor<EmailMessage>(predicate: #Predicate { $0.from == a }, sortBy: [SortDescriptor(\.receivedAt, order: .reverse)])
        d.fetchLimit = 200
        emails = (try? ctx.fetch(d)) ?? []
        if emails.isEmpty {
            let raw = address
            var d2 = FetchDescriptor<EmailMessage>(predicate: #Predicate { $0.from == raw }, sortBy: [SortDescriptor(\.receivedAt, order: .reverse)])
            d2.fetchLimit = 200
            emails = (try? ctx.fetch(d2)) ?? []
        }
        score = InboxBrain.scores(ctx)[a]
        person = ((try? ctx.fetch(FetchDescriptor<Person>())) ?? []).first { $0.email.lowercased() == a }
    }
}

extension EmailMessage {
    /// A stand-in for checks that need a message when there isn't one.
    static var placeholder: EmailMessage {
        EmailMessage(accountId: "", providerMessageId: "", threadId: "", from: "", fromName: "", subject: "", snippet: "", bodyPlain: "", receivedAt: Date(), isRead: true)
    }
}
