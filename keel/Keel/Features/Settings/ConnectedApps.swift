import SwiftUI
import Photos
import Contacts
import EventKit
import UserNotifications

/// Settings → Connected Apps: everything Keel can connect to, its status, and one-tap setup.
struct ConnectedAppsView: View {
    @State private var photos = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var contacts = CNContactStore.authorizationStatus(for: .contacts)
    @State private var healthOn = HealthService.shared.isAuthorizedHint
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                row("Calendar", "calendar", .red, EKEventStore.authorizationStatus(for: .event) == .fullAccess ? "Connected" : "Not allowed") { openSettings() }
                row("Reminders", "checklist", .orange, EKEventStore.authorizationStatus(for: .reminder) == .fullAccess ? "Connected" : "Not allowed") { openSettings() }
                row("Photos", "photo.fill", .pink, label(photos)) {
                    Task { photos = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
                }
                row("Contacts", "person.crop.circle.fill", .gray, label(contacts)) {
                    Task { _ = try? await CNContactStore().requestAccess(for: .contacts); contacts = CNContactStore.authorizationStatus(for: .contacts) }
                }
                row("Health (sleep)", "heart.fill", .red, healthOn ? "Connected" : "Connect") {
                    Task { await HealthService.shared.requestAccess(); healthOn = HealthService.shared.isAuthorizedHint }
                }
            } header: { Text("Allowed with your permission") } footer: {
                Text("Photos: turns recent screenshots into task suggestions. Contacts: birthdays become countdowns. Health: last night's sleep sets your suggested energy. Everything stays on this iPhone.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Apple Notes", systemImage: "note.text").font(DS.Font.headline)
                    Text("Apple doesn't let any app read Notes directly, so you bring them in yourself:").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    step(1, "In any note, tap Share → Keel. Done.")
                    step(2, "To import many: in Shortcuts, make a shortcut with “Find Notes” → “Repeat with Each” → Keel “Save to Keel Notes”. Shortcuts asks your permission, then copies them in.")
                }
                .padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Messages", systemImage: "message.fill").font(DS.Font.headline)
                    Text("No app can read your texts. You can send messages to Keel instead:").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    step(1, "Long-press a message → Share → Keel.")
                    step(2, "Automatic: Shortcuts → Automation → New → Message. Choose a sender or words like “can you”, then add Keel’s “Add Message to Keel” action. Each matching message becomes a task.")
                }
                .padding(.vertical, 4)
                Button { if let url = URL(string: "shortcuts://") { openURL(url) } } label: {
                    Label("Open Shortcuts", systemImage: "square.2.layers.3d")
                }
            } header: { Text("Bring in yourself") } footer: {
                Text("Apple keeps Notes and Messages private from every app. These routes only ever send what you choose.")
            }

            Section("Already connected") {
                Label("Email accounts (Settings → Mail Accounts)", systemImage: "envelope")
                Label("Files and photos in notes and email", systemImage: "folder")
                Label("Location reminders through Reminders", systemImage: "location")
                Label("Siri, Shortcuts and Spotlight", systemImage: "waveform")
            }
            .font(DS.Font.body)
        }
        .navigationTitle("Connected Apps")
    }

    private func label(_ s: PHAuthorizationStatus) -> String {
        switch s { case .authorized: "Connected"; case .limited: "Some photos"; case .denied, .restricted: "Not allowed"; default: "Connect" }
    }
    private func label(_ s: CNAuthorizationStatus) -> String {
        switch s { case .authorized, .limited: "Connected"; case .denied, .restricted: "Not allowed"; default: "Connect" }
    }

    private func row(_ title: String, _ symbol: String, _ color: Color, _ status: String, action: @escaping () -> Void) -> some View {
        Button {
            if status == "Not allowed" { openSettings() } else { action() }
        } label: {
            HStack(spacing: 12) {
                SettingsIcon(symbol: symbol, color: color)
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(status).foregroundStyle(status == "Connected" ? DS.Palette.calm : .secondary)
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)").font(.caption.weight(.bold)).frame(width: 18, height: 18).background(DS.Palette.accent.opacity(0.15), in: Circle())
            Text(text).font(DS.Font.caption)
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}
