import SwiftUI
import Network
import UserNotifications
import TipKit
import WatchConnectivity

// MARK: - Offline banner

/// Says so when there's no internet, instead of AI and mail silently failing.
@MainActor @Observable
final class NetworkStatus {
    static let shared = NetworkStatus()
    private(set) var online = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { path in
            let ok = path.status == .satisfied
            Task { @MainActor in if NetworkStatus.shared.online != ok { withAnimation(.snappy) { NetworkStatus.shared.online = ok } } }
        }
        monitor.start(queue: DispatchQueue(label: "keel.network"))
    }
}

struct OfflineBanner: View {
    @State private var net = NetworkStatus.shared
    var body: some View {
        if !net.online {
            Label("Offline. Your changes are saved and will sync when you're back.", systemImage: "wifi.slash")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .padding(.top, 2)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

// MARK: - Keel status: is everything connected?

/// One screen that answers "why isn't X working?": iCloud, settings sync, notifications, instant mail alerts,
/// Apple Health, your Keel server, AI and Apple Watch.
struct KeelStatusView: View {
    @State private var notifications = "Checking…"
    @State private var push = "Checking…"
    @State private var resetTips = UserDefaults.standard.bool(forKey: "tips.reset")

    var body: some View {
        List {
            Section {
                row("iCloud", FileManager.default.ubiquityIdentityToken != nil ? "Signed in" : "Not signed in", FileManager.default.ubiquityIdentityToken != nil)
                row("Data sync", KeelStore.syncState == "on" ? "On" : KeelStore.syncState == "off" ? "Off" : "Problem", KeelStore.syncState == "on")
                row("Settings & keys sync", SettingsSync.lastSync.map { "Last \($0.formatted(.relative(presentation: .named)))" } ?? "Waiting", SettingsSync.lastSync != nil)
            } header: { Text("Sync") } footer: {
                if KeelStore.syncState != "on" && KeelStore.syncState != "off" { Text(KeelStore.syncState) }
                else { Text("Data sync moves your tasks and notes; settings sync moves your settings, AI keys and sign-ins through iCloud Keychain.") }
            }
            Section("Alerts") {
                row("Notifications", notifications, notifications == "Allowed")
                if notifications != "Allowed" {
                    Button("Open Settings to allow notifications") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
                }
                row("Instant mail alerts", push, push.hasPrefix("On"))
            }
            Section("Connections") {
                row("Keel server", KeelServer.isConfigured ? "Connected" : "Not connected", KeelServer.isConfigured)
                row("Apple Health", !BodyHealth.available ? "Not on this device" : BodyEngine.shared.connected ? "Connected" : "Not connected", BodyEngine.shared.connected)
                row("AI", AIWriter.defaultModel?.label ?? "None available", AIWriter.defaultModel != nil)
                row("Apple Watch", watch, watch == "Connected")
            }
            Section {
                Button(resetTips ? "Tips will show again after you restart Keel" : "Show all tips again") {
                    UserDefaults.standard.set(true, forKey: "tips.reset"); resetTips = true
                }
                .disabled(resetTips)
            } footer: { Text("Brings back the one-time tips that explain features where you use them.") }
        }
        .navigationTitle("Keel status")
        .task { await check() }
    }

    private var watch: String {
        guard WCSession.isSupported() else { return "Not on this device" }
        let s = WCSession.default
        return !s.isPaired ? "No watch paired" : !s.isWatchAppInstalled ? "Keel not installed on watch" : "Connected"
    }

    private func row(_ name: String, _ value: String, _ ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(ok ? .green : .orange)
            Text(name)
            Spacer()
            Text(value).foregroundStyle(DS.Palette.inkSoft).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func check() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notifications = switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: "Allowed"
        case .denied: "Turned off"
        default: "Not asked yet"
        }
        let registered = UserDefaults.standard.string(forKey: MailPush.tokenKey) != nil
        if !KeelServer.isConfigured { push = "Needs your Keel server"; return }
        guard let data = try? await KeelCloud.call("push/config", auth: true),
              let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { push = "Couldn't reach your server"; return }
        let ready = cfg["ready"] as? Bool == true
        push = !ready ? "Server needs its Apple push key" : !registered ? "Waiting for this device" : "On (Gmail \((cfg["gmailTopic"] as? String) == nil ? "needs setup" : "ready"), Outlook ready)"
    }
}

// MARK: - Support messages (what people sent from your support page)

struct SupportMessagesView: View {
    struct Message: Decodable, Identifiable { var id: Double { at }; let email: String; let message: String; let at: Double }
    @State private var messages: [Message] = []
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        List {
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            if !loading && messages.isEmpty && error == nil { Text("No messages yet.").foregroundStyle(DS.Palette.inkSoft) }
            ForEach(messages.sorted { $0.at > $1.at }) { m in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(m.email.isEmpty ? "No email given" : m.email).font(DS.Font.caption.weight(.semibold))
                        Spacer()
                        Text(Date(timeIntervalSince1970: m.at / 1000).formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                    }
                    Text(m.message).font(.callout).textSelection(.enabled)
                    if !m.email.isEmpty {
                        Link("Reply by email", destination: URL(string: "mailto:\(m.email)?subject=Keel%20support") ?? URL(string: "mailto:")!).font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Support messages")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            let data = try await KeelCloud.call("support/messages", auth: true)
            messages = try JSONDecoder().decode([Message].self, from: data)
            error = nil
        } catch { self.error = "Couldn't load messages from your Keel server." }
    }
}

enum TipsReset {
    /// Called before tips are set up at launch: "Show all tips again" takes effect here.
    static func applyIfAsked() {
        guard UserDefaults.standard.bool(forKey: "tips.reset") else { return }
        try? Tips.resetDatastore()
        UserDefaults.standard.set(false, forKey: "tips.reset")
    }
}
