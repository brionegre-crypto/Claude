import SwiftUI
import SwiftData

/// Finds senders you never read and offers to unsubscribe: one gentle card at the top of Inbox,
/// plus a review sheet for all of them. "Keep" means Keel never asks about that sender again.
@MainActor
enum UnsubscribeSuggestions {
    struct Candidate: Identifiable {
        var id: String { sender }
        let sender: String
        let name: String
        let count: Int
        let opened: Int
        let latest: EmailMessage
        var oneTap: Bool { latest.unsubscribeOneClick || Unsubscribe.links(latest.unsubscribeHeader).mail != nil }
    }

    static let keptKey = "unsubscribe.kept", doneKey = "unsubscribe.done"
    static var kept: Set<String> { Set(UserDefaults.standard.stringArray(forKey: keptKey) ?? []) }
    static func keep(_ sender: String) {
        UserDefaults.standard.set(Array(kept.union([sender])), forKey: keptKey)
    }
    static func markDone(_ sender: String) {
        UserDefaults.standard.set(Array(Set(UserDefaults.standard.stringArray(forKey: doneKey) ?? []).union([sender])), forKey: doneKey)
    }

    /// Bulk senders with 3+ emails in 60 days that you open less than a quarter of the time.
    static func candidates(_ emails: [EmailMessage]) -> [Candidate] {
        let since = Date().addingTimeInterval(-60 * 86_400)
        let skip = kept.union(UserDefaults.standard.stringArray(forKey: doneKey) ?? [])
        let bulk = emails.filter {
            $0.receivedAt > since && ($0.unsubscribeHeader != nil || $0.category == .newsletters || $0.category == .promotions)
        }
        return Dictionary(grouping: bulk) { $0.from.lowercased() }
            .compactMap { sender, msgs -> Candidate? in
                guard msgs.count >= 3, !skip.contains(sender) else { return nil }
                let opened = msgs.filter(\.isRead).count
                guard Double(opened) / Double(msgs.count) < 0.25,
                      let latest = msgs.max(by: { $0.receivedAt < $1.receivedAt }),
                      Unsubscribe.canUnsubscribe(latest) || latest.unsubscribeHeader == nil else { return nil }
                return Candidate(sender: sender, name: latest.fromName.isEmpty ? sender : latest.fromName,
                                 count: msgs.count, opened: opened, latest: latest)
            }
            .sorted { $0.count > $1.count }
    }
}

/// The card at the top of Inbox.
struct UnsubscribeBanner: View {
    let candidates: [UnsubscribeSuggestions.Candidate]
    let provider: (EmailMessage) -> MailProvider?
    var onChange: () -> Void
    @Environment(\.modelContext) private var ctx
    @State private var working = false
    @State private var reviewing = false

    var body: some View {
        if let c = candidates.first {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack(alignment: .top, spacing: DS.Space.m) {
                    Image(systemName: "hand.raised.slash.fill").font(.title3).foregroundStyle(DS.Palette.warmth)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You never open \(c.name)").font(DS.Font.headline).lineLimit(1)
                        Text("\(c.count) emails in 2 months, \(c.opened == 0 ? "none" : "\(c.opened)") opened. Unsubscribe and clear them out?")
                            .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
                HStack(spacing: DS.Space.s) {
                    Button {
                        Task {
                            working = true
                            _ = await Unsubscribe.run(c.latest, provider: provider(c.latest), ctx: ctx)
                            UnsubscribeSuggestions.markDone(c.sender)
                            working = false
                            Haptics.success()
                            UndoCenter.shared.notify("Unsubscribed from \(c.name)")
                            onChange()
                        }
                    } label: {
                        if working { ProgressView().frame(maxWidth: .infinity) } else { Text("Unsubscribe").frame(maxWidth: .infinity) }
                    }
                    .buttonStyle(.borderedProminent).tint(DS.Palette.warmth)
                    Button("Keep") { UnsubscribeSuggestions.keep(c.sender); Haptics.tap(); onChange() }
                        .buttonStyle(.bordered)
                    if candidates.count > 1 {
                        Button("Review \(candidates.count)") { reviewing = true }.buttonStyle(.bordered)
                    }
                }
                .font(DS.Font.caption)
                .disabled(working)
            }
            .padding(DS.Space.m)
            .background(DS.Palette.warmth.opacity(0.08), in: .rect(cornerRadius: DS.Radius.card))
            .sheet(isPresented: $reviewing, onDismiss: onChange) {
                UnsubscribeReviewView(candidates: candidates, provider: provider)
            }
        }
    }
}

/// Every sender worth leaving, with one-by-one and all-at-once options.
struct UnsubscribeReviewView: View {
    let candidates: [UnsubscribeSuggestions.Candidate]
    let provider: (EmailMessage) -> MailProvider?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var handled: [String: String] = [:]          // sender → "Unsubscribed" | "Kept" | "Open their page"
    @State private var busy = false

    private var remaining: [UnsubscribeSuggestions.Candidate] { candidates.filter { handled[$0.sender] == nil } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task { await unsubscribeAll() }
                    } label: {
                        Label(busy ? "Unsubscribing…" : "Unsubscribe from all \(remaining.filter(\.oneTap).count)", systemImage: "hand.raised.slash")
                    }
                    .disabled(busy || remaining.filter(\.oneTap).isEmpty)
                } footer: {
                    Text("Keel unsubscribes from senders that support it right away and archives what they've sent. Senders that only offer a web page are left for you to tap one at a time.")
                }
                ForEach(candidates) { c in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).font(DS.Font.headline).lineLimit(1)
                            Text("\(c.count) emails · \(c.opened) opened\(c.oneTap ? "" : " · opens their page")")
                                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        if let state = handled[c.sender] {
                            Text(state).font(DS.Font.caption).foregroundStyle(DS.Palette.calm)
                        } else {
                            Button("Unsubscribe") { Task { await one(c, allowWeb: true) } }
                                .buttonStyle(.bordered).tint(DS.Palette.warmth).font(DS.Font.caption)
                        }
                    }
                    .swipeActions {
                        Button("Keep") { UnsubscribeSuggestions.keep(c.sender); handled[c.sender] = "Kept" }.tint(.gray)
                    }
                }
            }
            .navigationTitle("Clean Up Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func one(_ c: UnsubscribeSuggestions.Candidate, allowWeb: Bool) async {
        let outcome = await Unsubscribe.run(c.latest, provider: provider(c.latest), ctx: ctx, allowWebPage: allowWeb)
        switch outcome {
        case .done: handled[c.sender] = "Unsubscribed"; UnsubscribeSuggestions.markDone(c.sender)
        case .openedWebPage: handled[c.sender] = "Finish on their page"; UnsubscribeSuggestions.markDone(c.sender)
        case .unavailable: if allowWeb { handled[c.sender] = "Not available" }
        }
    }

    private func unsubscribeAll() async {
        busy = true; defer { busy = false }
        for c in remaining where c.oneTap { await one(c, allowWeb: false) }
        Haptics.success()
    }
}
