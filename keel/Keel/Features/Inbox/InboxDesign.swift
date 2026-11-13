import SwiftUI
import SwiftData
import Contacts

// MARK: - Avatars

/// Sender avatar: the contact's photo when you've allowed Contacts, otherwise colored initials.
struct SenderAvatar: View {
    let name: String
    let email: String
    var size: CGFloat = 38
    @State private var photo: UIImage?

    private static var cache: [String: UIImage] = [:]
    private static var misses: Set<String> = []

    private var initials: String {
        let parts = (name.isEmpty ? email : name).split(whereSeparator: { $0 == " " || $0 == "." || $0 == "@" })
        return parts.prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
    }
    private var color: Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .green, .indigo, .red, .mint, .brown]
        return palette[abs(email.lowercased().unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % palette.count]
    }

    var body: some View {
        Group {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                Text(initials.isEmpty ? "?" : initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(color.gradient)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: email) { photo = await Self.lookup(email.lowercased()) }
        .accessibilityHidden(true)
    }

    /// Contacts photo by email address; only when access was already granted (never prompts from Inbox).
    @MainActor
    static func lookup(_ email: String) async -> UIImage? {
        if let hit = cache[email] { return hit }
        guard !misses.contains(email), CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return nil }
        let result: UIImage? = await Task.detached(priority: .utility) {
            let store = CNContactStore()
            let pred = CNContact.predicateForContacts(matchingEmailAddress: email)
            let keys = [CNContactThumbnailImageDataKey as CNKeyDescriptor]
            guard let c = try? store.unifiedContacts(matching: pred, keysToFetch: keys).first, let data = c.thumbnailImageData else { return nil }
            return UIImage(data: data)
        }.value
        if let result { cache[email] = result } else { misses.insert(email) }
        return result
    }
}

// MARK: - Chips on a row

struct MailChip: View {
    let text: String
    let icon: String
    var color: Color = DS.Palette.inkSoft
    var body: some View {
        Label(text, systemImage: icon)
            .scaledFont(size: 11, weight: .medium)
            .lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Tab bar

struct InboxTabBar: View {
    let items: [MailTabItem]
    @Binding var selected: String
    let counts: [String: Int]
    var hideCounts = false

    var body: some View {
        // Bigger text, Display Zoom or many tabs: the tabs scroll sideways instead of running off the screen.
        ViewThatFits(in: .horizontal) {
            bar
            ScrollView(.horizontal, showsIndicators: false) { bar }
        }
    }

    private var bar: some View {
        HStack(spacing: 6) {
            ForEach(items) { t in
                let on = selected == t.id
                Button { withAnimation(DS.spring) { selected = t.id }; Haptics.tap() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: t.icon).scaledFont(size: 11, weight: .semibold)
                        Text(t.title).scaledFont(size: 13, weight: .semibold).lineLimit(1)
                        if !hideCounts, let n = counts[t.id], n > 0 {
                            Text("\(n)").scaledFont(size: 11, weight: .bold).monospacedDigit()
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background((on ? Color.white : DS.Palette.accent).opacity(on ? 0.25 : 0.15), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(on ? .white : DS.Palette.ink)
                    .background(on ? AnyShapeStyle(DS.Palette.accent.gradient) : AnyShapeStyle(DS.Palette.elevated), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(t.title)\(counts[t.id].map { ", \($0) unread" } ?? "")")
            }
        }
    }
}

// MARK: - Bundles

/// Several emails from one sender folded into one row.
struct SenderBundle: Identifiable {
    var id: String { sender }
    let sender: String
    let name: String
    let emails: [EmailMessage]
    var unread: Int { emails.filter { !$0.isRead }.count }
    var latest: EmailMessage { emails.max { $0.receivedAt < $1.receivedAt }! }

    static func group(_ emails: [EmailMessage]) -> [SenderBundle] {
        Dictionary(grouping: emails) { $0.from.lowercased() }
            .map { k, v in SenderBundle(sender: k, name: v.first { !$0.fromName.isEmpty }?.fromName ?? k, emails: v.sorted { $0.receivedAt > $1.receivedAt }) }
            .sorted { $0.latest.receivedAt > $1.latest.receivedAt }
    }
}

struct SenderBundleRow: View {
    let bundle: SenderBundle
    var body: some View {
        HStack(spacing: DS.Space.m) {
            SenderAvatar(name: bundle.name, email: bundle.sender, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(bundle.name).font(DS.Font.headline).lineLimit(1)
                    if bundle.emails.count > 1 {
                        Text("\(bundle.emails.count)").font(.caption2.weight(.bold)).foregroundStyle(DS.Palette.inkSoft)
                    }
                    Spacer()
                    Text(bundle.latest.receivedAt, format: .relative(presentation: .named)).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                Text(bundle.latest.subject).font(DS.Font.caption).foregroundStyle(bundle.unread > 0 ? DS.Palette.ink : DS.Palette.inkSoft).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// All mail from one sender, with one-tap archive.
struct SenderBundleView: View {
    let bundle: SenderBundle
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [MailAccount]

    var body: some View {
        List {
            Section {
                ForEach(bundle.emails.filter { !$0.isArchived }) { e in
                    NavigationLink { EmailDetailView(email: e) } label: { EmailRow(email: e) }
                }
            } header: {
                HStack {
                    SenderAvatar(name: bundle.name, email: bundle.sender, size: 28)
                    Text(bundle.sender).textCase(nil)
                }
            }
        }
        .navigationTitle(bundle.name)
        .toolbar {
            Button("Archive all") {
                for e in bundle.emails where !e.isArchived {
                    e.isArchived = true
                    if !e.isRead { InboxBrain.record(.ignored, sender: e.from, name: e.fromName, ctx: ctx) }
                    if let a = accounts.first(where: { $0.id == e.accountId }) {
                        let p = MailProviderFactory.make(for: a); let id = e.providerMessageId
                        Task { try? await p.archive(id) }
                    }
                }
                Haptics.success()
                dismiss()
            }
        }
    }
}

// MARK: - Batched delivery banner

struct BatchBanner: View {
    let waiting: Int
    var onReveal: () -> Void
    var body: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "tray.and.arrow.down").foregroundStyle(DS.Palette.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(waiting) email\(waiting == 1 ? "" : "s") arriving at \(InboxBrain.nextDelivery().formatted(date: .omitted, time: .shortened))")
                    .font(DS.Font.caption.weight(.semibold))
                Text("VIPs and urgent mail still come straight through.").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
            }
            Spacer()
            Button("Show now", action: onReveal).font(DS.Font.caption).buttonStyle(.bordered)
        }
        .padding(10)
        .background(DS.Palette.accent.opacity(0.08), in: .rect(cornerRadius: 12))
    }
}
