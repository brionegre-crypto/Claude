import SwiftUI
import SwiftData

// MARK: - Per-account mail settings: name, color, signatures, alerts, default account

enum MailAccountPrefs {
    static let defaultAccountKey = "mail.defaultAccount"
    static func replySignatureKey(_ id: String) -> String { "mail.replySignature.\(id)" }
    static func signOnRepliesKey(_ id: String) -> String { "mail.signOnReplies.\(id)" }
    static func notifyKey(_ id: String) -> String { "mail.notify.\(id)" }

    static var defaultAccountId: String? { UserDefaults.standard.string(forKey: defaultAccountKey) }
    static func notifies(_ accountId: String) -> Bool { UserDefaults.standard.object(forKey: notifyKey(accountId)) as? Bool ?? true }
    static func signsReplies(_ accountId: String) -> Bool { UserDefaults.standard.object(forKey: signOnRepliesKey(accountId)) as? Bool ?? true }
    static func replySignature(_ accountId: String) -> String { UserDefaults.standard.string(forKey: replySignatureKey(accountId)) ?? "" }

    /// The signature to add: none on replies if you turned that off, the short reply one if you set it, else the full one.
    static func signature(for account: MailAccount?, isReply: Bool) -> String {
        let full = account?.signature ?? UserDefaults.standard.string(forKey: Prefs.signature) ?? ""
        guard isReply, let id = account?.id else { return full }
        guard signsReplies(id) else { return "" }
        let short = replySignature(id)
        return short.isEmpty ? full : short
    }

    // Reading and replying (all accounts)
    static let markReadKey = "mail.markRead"                 // "open" (default), "delay", "manual"
    static let quoteKey = "mail.quoteOriginal"
    static var quotesOriginal: Bool { UserDefaults.standard.object(forKey: quoteKey) as? Bool ?? true }
    static var markReadMode: String { UserDefaults.standard.string(forKey: markReadKey) ?? "open" }
}

struct MailAccountCustomizeView: View {
    @Bindable var account: MailAccount
    @AppStorage(MailAccountPrefs.defaultAccountKey) private var defaultAccount = ""
    @State private var replySignature = ""
    @State private var signReplies = true
    @State private var notify = true
    @State private var color = Color.blue

    var body: some View {
        Form {
            Section {
                TextField("Your name", text: $account.displayName)
                ColorPicker("Account color", selection: $color, supportsOpacity: false)
                Toggle("Default for new emails", isOn: Binding(get: { defaultAccount == account.id },
                                                               set: { defaultAccount = $0 ? account.id : (defaultAccount == account.id ? "" : defaultAccount) }))
            } header: { Text(account.address) } footer: { Text("Your name is what people see in their inbox. The color marks this account's mail in Inbox.") }

            Section {
                TextEditor(text: Binding(get: { account.signature ?? "" }, set: { account.signature = $0.isEmpty ? nil : $0 }))
                    .frame(minHeight: 110)
                    .overlay(alignment: .topLeading) {
                        if (account.signature ?? "").isEmpty {
                            Text("Uses your shared signature").foregroundStyle(DS.Palette.inkSoft.opacity(0.7)).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                        }
                    }
                Menu("Start from a style") {
                    Button("Name only") { account.signature = "— \(firstName)" }
                    Button("Name and title") { account.signature = "\(account.displayName)\nTitle · Company" }
                    Button("Full contact card") { account.signature = "\(account.displayName)\nTitle · Company\n\(account.address)\n(555) 555-5555" }
                    Button("Friendly") { account.signature = "Thanks!\n\(firstName)" }
                }
            } header: { Text("Signature") } footer: { Text("Added to new emails from this account.") }

            Section {
                Toggle("Sign replies too", isOn: $signReplies)
                if signReplies {
                    TextField("Short reply signature (optional)", text: $replySignature, axis: .vertical).lineLimit(1...4)
                }
            } header: { Text("Replies") } footer: { Text("Many people use a short sign-off on replies (just your name) and the full signature on new emails.") }

            Section {
                Toggle("Alerts from this account", isOn: $notify)
                NavigationLink { LazyView(AliasesView(account: account)) } label: {
                    LabeledContent("Send as", value: MailAliases.list(account.id).isEmpty ? "None" : "\(MailAliases.list(account.id).count)")
                }
                Toggle("Sync this account", isOn: $account.isEnabled)
            }
        }
        .navigationTitle(account.displayName.isEmpty ? account.address : account.displayName)
        .onAppear {
            replySignature = MailAccountPrefs.replySignature(account.id)
            signReplies = MailAccountPrefs.signsReplies(account.id)
            notify = MailAccountPrefs.notifies(account.id)
            color = Color(hex: account.colorHex)
        }
        .onChange(of: replySignature) { _, v in UserDefaults.standard.set(v, forKey: MailAccountPrefs.replySignatureKey(account.id)) }
        .onChange(of: signReplies) { _, v in UserDefaults.standard.set(v, forKey: MailAccountPrefs.signOnRepliesKey(account.id)) }
        .onChange(of: notify) { _, v in UserDefaults.standard.set(v, forKey: MailAccountPrefs.notifyKey(account.id)) }
        .onChange(of: color) { _, c in if let hex = c.hexString { account.colorHex = hex } }
    }

    private var firstName: String { account.displayName.split(separator: " ").first.map(String.init) ?? account.displayName }
}

/// Settings → Mail: one row per account, opening its own settings.
struct MailAccountsSection: View {
    @Query(sort: \MailAccount.address) private var accounts: [MailAccount]
    var body: some View {
        if !accounts.isEmpty {
            Section {
                ForEach(accounts) { a in
                    NavigationLink { MailAccountCustomizeView(account: a) } label: {
                        HStack(spacing: 10) {
                            Circle().fill(Color(hex: a.colorHex)).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(a.displayName.isEmpty ? a.address : a.displayName)
                                Text(a.address + (MailAccountPrefs.defaultAccountId == a.id ? " · default" : "")).font(.caption).foregroundStyle(DS.Palette.inkSoft)
                            }
                        }
                    }
                }
            } header: { Text("Accounts & signatures") } footer: { Text("Each account's name, color, signature, reply signature and alerts.") }
        }
    }
}

extension Color {
    /// A color → "#RRGGBB".
    var hexString: String? {
        guard let c = UIColor(self).cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let comps = c.components, comps.count >= 3 else { return nil }
        return String(format: "#%02X%02X%02X", Int(comps[0] * 255), Int(comps[1] * 255), Int(comps[2] * 255))
    }
}
