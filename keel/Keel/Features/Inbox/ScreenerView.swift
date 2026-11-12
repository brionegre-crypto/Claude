import SwiftUI
import SwiftData

/// Screener: the first time someone emails you, you decide whether they get into your inbox.
/// Approve once and they're in for good; block once and their mail is archived automatically from then on.
@MainActor
enum Screener {
    static var enabled: Bool { !UserDefaults.standard.bool(forKey: "screener.off") }

    /// Only mail that arrives after Screener was first used is screened; existing senders are left alone.
    static var since: Date {
        if let d = UserDefaults.standard.object(forKey: "screener.since") as? Date { return d }
        let now = Date()
        UserDefaults.standard.set(now, forKey: "screener.since")
        return now
    }

    /// Senders who have emailed you but you haven't decided on yet (newest first).
    static func pending(emails: [EmailMessage], rules: [SenderRule]) -> [(address: String, name: String, latest: EmailMessage, count: Int)] {
        let decided = Set(rules.map(\.address))
        let start = since
        let known = Set(emails.filter { $0.receivedAt < start }.map { $0.from.lowercased() })   // people who emailed before
        let groups = Dictionary(grouping: emails.filter {
            !$0.isArchived && $0.receivedAt >= start && !decided.contains($0.from.lowercased()) && !known.contains($0.from.lowercased())
        }) { $0.from.lowercased() }
        return groups.compactMap { addr, mails in
            guard let latest = mails.max(by: { $0.receivedAt < $1.receivedAt }) else { return nil }
            return (addr, latest.fromName, latest, mails.count)
        }
        .sorted { $0.latest.receivedAt > $1.latest.receivedAt }
    }

    static func decide(_ address: String, name: String, allow: Bool, ctx: ModelContext) {
        ctx.insert(SenderRule(address: address, allowed: allow, name: name))
        if !allow { archiveBlocked(ctx: ctx) }
        Haptics.success()
    }

    /// Runs after each sync: anything from a blocked sender is archived (on the server too).
    static func archiveBlocked(ctx: ModelContext) {
        let blocked = Set(((try? ctx.fetch(FetchDescriptor<SenderRule>())) ?? []).filter { !$0.allowed }.map(\.address))
        guard !blocked.isEmpty else { return }
        let accounts = (try? ctx.fetch(FetchDescriptor<MailAccount>())) ?? []
        for e in ((try? ctx.fetch(FetchDescriptor<EmailMessage>())) ?? []) where !e.isArchived && blocked.contains(e.from.lowercased()) {
            e.isArchived = true
            if let a = accounts.first(where: { $0.id == e.accountId }) {
                let id = e.providerMessageId
                Task { try? await MailProviderFactory.make(for: a).archive(id) }
            }
        }
    }
}

struct ScreenerView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \EmailMessage.receivedAt, order: .reverse) private var emails: [EmailMessage]
    @Query(sort: \SenderRule.decidedAt, order: .reverse) private var rules: [SenderRule]
    @State private var showDecided = false

    var body: some View {
        let pending = Screener.pending(emails: emails, rules: rules)
        List {
            if pending.isEmpty {
                ContentUnavailableView("No one to screen", systemImage: "person.crop.circle.badge.checkmark",
                                       description: Text("New senders appear here the first time they email you."))
                    .listRowBackground(Color.clear)
            }
            ForEach(pending, id: \.address) { p in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name.isEmpty ? p.address : p.name).font(DS.Font.headline)
                            Text(p.address).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        if p.count > 1 { Chip(text: "\(p.count) emails", color: .gray) }
                    }
                    Text(p.latest.subject).font(DS.Font.body).lineLimit(1)
                    Text(p.latest.aiSummary ?? p.latest.snippet).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                    HStack {
                        Button { withAnimation { Screener.decide(p.address, name: p.name, allow: true, ctx: ctx) } } label: {
                            Label("Let in", systemImage: "checkmark").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(DS.Palette.calm)
                        Button { withAnimation { Screener.decide(p.address, name: p.name, allow: false, ctx: ctx) } } label: {
                            Label("Block", systemImage: "hand.raised").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).tint(.red)
                    }
                }
                .padding(.vertical, 6)
            }
            if !rules.isEmpty {
                Section {
                    DisclosureGroup("Decided (\(rules.count))", isExpanded: $showDecided) {
                        ForEach(rules) { r in
                            HStack {
                                Image(systemName: r.allowed ? "checkmark.circle.fill" : "hand.raised.fill")
                                    .foregroundStyle(r.allowed ? DS.Palette.calm : .red)
                                Text(r.name.isEmpty ? r.address : r.name)
                                Spacer()
                            }
                            .swipeActions { Button("Undo", role: .destructive) { ctx.delete(r) } }
                        }
                    }
                }
            }
        }
        .navigationTitle("Screener")
    }
}
