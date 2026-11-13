import SwiftUI
import AuthenticationServices
import CloudKit
#if DEBUG
import CoreData
import SwiftData
#endif

/// Your Keel account: Sign in with Apple. The same Apple Account on any iPhone, iPad or Mac is the same Keel:
/// your content syncs through your own iCloud, and your Keel server recognises you, so Claude works everywhere
/// without typing an access code.
@MainActor @Observable
final class KeelAccount {
    static let shared = KeelAccount()

    private static let userKey = "keel.apple.user"
    private(set) var userID: String?
    private(set) var name: String
    private(set) var email: String
    var serverMessage: String?
    var iCloudStatus: String = "Checking…"

    var isSignedIn: Bool { userID != nil }

    private init() {
        userID = KeychainStore.read(Self.userKey)
        name = UserDefaults.standard.string(forKey: "keel.account.name") ?? ""
        email = UserDefaults.standard.string(forKey: "keel.account.email") ?? ""
    }

    /// Called by the Sign in with Apple button.
    func handle(_ result: Result<ASAuthorization, Error>) async {
        guard case .success(let auth) = result, let cred = auth.credential as? ASAuthorizationAppleIDCredential else {
            if case .failure(let e) = result, (e as? ASAuthorizationError)?.code != .canceled {
                serverMessage = "Sign in didn't finish: \(e.localizedDescription)"
            }
            return
        }
        userID = cred.user
        KeychainStore.save(cred.user, for: Self.userKey)
        // Apple shares the name and email only the first time; keep them.
        let full = [cred.fullName?.givenName, cred.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
        if !full.isEmpty { name = full; UserDefaults.standard.set(full, forKey: "keel.account.name") }
        if let e = cred.email, !e.isEmpty { email = e; UserDefaults.standard.set(e, forKey: "keel.account.email") }
        // Turn on iCloud sync; it starts the next time Keel opens.
        UserDefaults.standard.set(true, forKey: KeelStore.syncKey)
        Haptics.success()
        if let tokenData = cred.identityToken, let token = String(data: tokenData, encoding: .utf8) {
            await connectServer(identityToken: token)
        }
    }

    /// Your Keel server checks the Apple sign-in and hands this device its own access key.
    func connectServer(identityToken: String) async {
        guard let url = KeelServer.baseURL?.appendingPathComponent("auth/apple") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["identityToken": identityToken, "device": UIDevice.current.name])
        req.timeoutInterval = 20
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if code == 200, let token = json?["token"] as? String, let base = KeelServer.baseURL {
                KeelServer.save(address: base.absoluteString, accessCode: token)
                serverMessage = (json?["claimed"] as? Bool == true)
                    ? "You're the owner of this Keel server. Claude now works on every device you sign in on."
                    : "Connected to your Keel server. Claude works on this device."
            } else if code == 403 {
                serverMessage = "Signed in. Claude on this Keel server belongs to its owner; you can add your own AI key in AI & Privacy."
            } else {
                serverMessage = "Signed in. The Keel server didn't answer (\(code)); Claude can be connected later in AI & Privacy."
            }
        } catch {
            serverMessage = "Signed in. Couldn't reach the Keel server right now; try again from Account."
        }
    }

    /// If you stop using Sign in with Apple for Keel (Settings → Apple Account), sign out here too.
    func checkCredential() async {
        guard let id = userID else { return }
        let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: id)
        if state == .revoked || state == .notFound { signOut() }
    }

    func refreshICloudStatus() async {
        let s = try? await CKContainer(identifier: KeelStore.cloudID).accountStatus()
        iCloudStatus = switch s {
        case .available: "Signed in to iCloud"
        case .noAccount: "Not signed in to iCloud on this device"
        case .restricted: "iCloud is restricted on this device"
        case .temporarilyUnavailable: "iCloud is temporarily unavailable"
        default: "iCloud status unknown"
        }
    }

    /// Signs this device out of the account. Your data stays on the device; sync stops after Keel restarts.
    func signOut() {
        userID = nil
        KeychainStore.delete(Self.userKey)
        UserDefaults.standard.set(false, forKey: KeelStore.syncKey)
    }

    #if DEBUG
    /// Developer-only: creates the iCloud record types for every synced model in the Development environment,
    /// so they can be deployed to Production in the CloudKit Console (TestFlight and App Store use Production).
    static func initializeCloudSchema() throws {
        let url = URL.temporaryDirectory.appendingPathComponent("keel-schema.store")
        let desc = NSPersistentStoreDescription(url: url)
        desc.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: KeelStore.cloudID)
        desc.shouldAddStoreAsynchronously = false
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: KeelStore.syncedTypes) else { return }
        let c = NSPersistentCloudKitContainer(name: "KeelSchema", managedObjectModel: model)
        c.persistentStoreDescriptions = [desc]
        var loadError: Error?
        c.loadPersistentStores { _, e in loadError = e }
        if let loadError { throw loadError }
        try c.initializeCloudKitSchema()
        if let store = c.persistentStoreCoordinator.persistentStores.first { try c.persistentStoreCoordinator.remove(store) }
    }
    #endif
}

/// Settings → Account.
struct AccountView: View {
    @State private var account = KeelAccount.shared
    @AppStorage(KeelStore.syncKey) private var syncOn = false
    @State private var bridge = RemindersBridge.isThisDevice
    @State private var schemaResult: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        List {
            Section {
                if account.isSignedIn {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 44)).foregroundStyle(DS.Palette.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name.isEmpty ? "Your Keel account" : account.name).font(DS.Font.headline)
                            Text(account.email.isEmpty ? "Signed in with Apple" : account.email).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("One Keel on every device").font(DS.Font.title)
                        Text("Sign in with your Apple Account on your iPhone, iPad and Mac. Your tasks, notes, habits and everything you make stay the same everywhere, synced privately through your own iCloud.")
                            .font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
                    }
                    .padding(.vertical, 6)
                    SignInWithAppleButton(.signIn) { req in
                        req.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        Task { await account.handle(result) }
                    }
                    .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                    .frame(height: 48)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            } footer: {
                if let m = account.serverMessage { Text(m) }
            }

            Section {
                Toggle("iCloud Sync", isOn: $syncOn)
                LabeledContent("This device", value: KeelStore.syncState == "on" ? "Syncing" : KeelStore.syncState == "off" ? "Not syncing" : "Problem")
                LabeledContent("iCloud", value: account.iCloudStatus)
                if KeelStore.syncState != "on" && KeelStore.syncState != "off" {
                    Text(KeelStore.syncState).font(DS.Font.caption).foregroundStyle(.orange)
                }
                if syncOn != (KeelStore.syncState == "on") {
                    Label("Close and reopen Keel to \(syncOn ? "start" : "stop") syncing.", systemImage: "arrow.clockwise")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.accent)
                }
            } header: { Text("Sync") } footer: {
                Text("Syncs tasks, notes, habits, goals, people, medications, food and focus history through your private iCloud. Email isn't copied to iCloud: each device fetches it from your mail accounts. Add your mail accounts on each device in Settings → Mail Accounts.")
            }

            Section {
                Toggle("Link Apple Reminders on this device", isOn: Binding(get: { bridge }, set: { bridge = $0; RemindersBridge.isThisDevice = $0 }))
            } footer: {
                Text("Keep this on for one device only (your iPhone by default). Reminders already syncs through iCloud, so linking it on every device would create copies.")
            }

            if account.isSignedIn {
                Section {
                    Button("Reconnect to Keel server", systemImage: "server.rack") {
                        account.serverMessage = "Sign out and sign back in to reconnect; Apple only shares the sign-in proof at sign in."
                    }
                    Button("Sign Out on This Device", role: .destructive) { account.signOut() }
                } footer: {
                    Text("Signing out keeps everything on this device and stops syncing after Keel restarts. Your iCloud copy is untouched.")
                }
            }

            #if DEBUG
            Section {
                Button("Create iCloud schema (Development)") {
                    do { try KeelAccount.initializeCloudSchema(); schemaResult = "Done. Deploy it to Production in the CloudKit Console." }
                    catch { schemaResult = error.localizedDescription }
                }
                if let schemaResult { Text(schemaResult).font(DS.Font.caption) }
            } header: { Text("Developer") }
            #endif
        }
        .navigationTitle("Account")
        .task {
            await account.refreshICloudStatus()
            await account.checkCredential()
        }
    }
}
