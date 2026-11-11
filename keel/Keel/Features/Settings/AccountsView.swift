import SwiftUI
import SwiftData
import StoreKit

/// Connect Gmail / Outlook / iCloud, see every synced calendar & Reminders list, AI privacy, subscription.
struct AccountsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [MailAccount]
    @State private var error: String?
    @State private var showICloud = false
    @State private var showPaywall = false
    @AppStorage("ai.privateMode") private var privateMode = false

    var body: some View {
        NavigationStack {
            List {
                Section("Email accounts") {
                    ForEach(accounts) { a in
                        HStack {
                            Image(systemName: "envelope.fill").foregroundStyle(Color(hex: a.colorHex))
                            VStack(alignment: .leading) {
                                Text(a.address)
                                Text("\(a.provider.displayName) · \(a.lastSyncedAt.map { "synced \($0.formatted(.relative(presentation: .named)))" } ?? "not synced yet")")
                                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                            }
                        }
                    }
                    .onDelete { $0.map { accounts[$0] }.forEach(ctx.delete) }
                    Button("Add Gmail") { Task { await connect(.gmail) } }
                    Button("Add Outlook / Microsoft 365") { Task { await connect(.outlook) } }
                    Button("Add iCloud Mail") { showICloud = true }
                }

                Section {
                    ForEach(CalendarService.shared.calendarsBySource, id: \.source) { group in
                        DisclosureGroup(group.source) {
                            ForEach(group.calendars, id: \.calendarIdentifier) { c in
                                Label(c.title, systemImage: "circle.fill").foregroundStyle(Color(cgColor: c.cgColor))
                            }
                        }
                    }
                    ForEach(CalendarService.shared.reminderLists, id: \.calendarIdentifier) { l in
                        Label(l.title, systemImage: "checklist").foregroundStyle(Color(cgColor: l.cgColor))
                    }
                } header: { Text("Calendars & Reminders") } footer: {
                    Text("Keel syncs every calendar on this iPhone — iCloud, Google, Outlook, Exchange, subscribed — and every Apple Reminders list, both ways. Add more in Settings → Apps → Calendar → Accounts.")
                }

                Section {
                    Toggle("Private mode (on-device AI only)", isOn: $privateMode)
                    LabeledContent("Apple Intelligence", value: AIRouter.shared.onDeviceAvailable ? "Available" : "Not on this device")
                } header: { Text("AI") } footer: {
                    Text("Sorting and summaries run on your iPhone with Apple Intelligence. Day planning and long drafts use Claude unless Private mode is on.")
                }

                if Entitlements.paywallEnabled {
                    Section { Button("Keel Pro") { showPaywall = true } }
                }

                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Accounts")
            .toolbar { Button("Done") { dismiss() } }
            .sheet(isPresented: $showICloud) { ICloudSetupView() }
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    private func connect(_ kind: MailProviderKind) async {
        do {
            let cfg = kind == .gmail ? OAuthManager.google : OAuthManager.microsoft
            let tokens = try await OAuthManager.shared.signIn(cfg)
            let email = try await fetchAddress(kind, token: tokens.access)
            let a = MailAccount(provider: kind, address: email, displayName: email,
                                colorHex: kind == .gmail ? "#EA4335" : "#0A64D6")
            KeychainStore.saveTokens(tokens, account: a.id)
            ctx.insert(a)
            await SyncEngine.shared.syncAll()
        } catch { self.error = error.localizedDescription }
    }

    private func fetchAddress(_ kind: MailProviderKind, token: String) async throws -> String {
        var req = URLRequest(url: URL(string: kind == .gmail ? "https://gmail.googleapis.com/gmail/v1/users/me/profile" : "https://graph.microsoft.com/v1.0/me")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return (j["emailAddress"] ?? j["mail"] ?? j["userPrincipalName"]) as? String ?? "unknown"
    }
}

struct ICloudSetupView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var checking = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("you@icloud.com", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("App-specific password (xxxx-xxxx-xxxx-xxxx)", text: $password)
                } footer: {
                    Text("Apple doesn't offer a mail API, so Keel connects to iCloud the standard way (IMAP and SMTP) using an app-specific password, not your Apple Account password. Create one at account.apple.com → Sign-In and Security → App-Specific Passwords. It's stored only in this iPhone's Keychain.")
                }
                if checking { Section { ProgressView("Checking with iCloud…") } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("iCloud Mail")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") { Task { await connect() } }
                        .disabled(email.isEmpty || password.isEmpty || checking)
                }
            }
        }
    }

    private func connect() async {
        checking = true; error = nil
        defer { checking = false }
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        let pass = password.trimmingCharacters(in: .whitespaces)
        do {
            try await ICloudMailProvider.verify(address: address, password: pass)
            let a = MailAccount(provider: .icloud, address: address, displayName: address, colorHex: "#3E8EF7")
            KeychainStore.save(pass, for: "imap.\(a.id)")
            ctx.insert(a)
            Haptics.success()
            dismiss()
            await SyncEngine.shared.syncAll()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Keel Pro (StoreKit 2). OFF while Keel is personal-use only.

enum Entitlements {
    /// Flip to true when you ship to the App Store. While false, every feature is unlocked.
    static let paywallEnabled = false
    static let productIds = ["keel.pro.monthly", "keel.pro.yearly"]

    static func isPro() async -> Bool {
        guard paywallEnabled else { return true }
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, productIds.contains(t.productID), t.revocationDate == nil { return true }
        }
        return false
    }
}

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        // Apple's built-in StoreKit view — handles pricing, trials, purchase and restore, localized.
        SubscriptionStoreView(productIDs: Entitlements.productIds) {
            VStack(spacing: DS.Space.m) {
                Image(systemName: "sailboat.fill").font(.system(size: 56)).foregroundStyle(DS.Palette.accent)
                Text("Keel Pro").font(DS.Font.hero)
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Label("Unlimited email accounts", systemImage: "tray.2")
                    Label("AI day planning with Claude", systemImage: "sparkles")
                    Label("App blocking & Locked focus", systemImage: "lock.shield")
                    Label("Promise tracker & body doubling", systemImage: "person.2.wave.2")
                }.font(DS.Font.body)
            }.padding()
        }
        .subscriptionStoreControlStyle(.prominentPicker)
        .storeButton(.visible, for: .restorePurchases)
        .tint(DS.Palette.accent)
    }
}

extension Color {
    init(hex: String) {
        let v = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x5B8DEF
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
