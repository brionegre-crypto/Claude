import SwiftUI
import UIKit

// MARK: - Themes and fonts

/// The overall look. Read live from settings, so changing it redraws the app at once.
enum KeelLook: String, CaseIterable, Identifiable {
    case standard, paper, midnight, contrast
    static let key = "look.theme", fontKey = "look.font"
    var id: String { rawValue }

    static var current: KeelLook { KeelLook(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .standard }

    var name: String {
        switch self { case .standard: "Standard"; case .paper: "Paper"; case .midnight: "Midnight"; case .contrast: "High contrast" }
    }
    var blurb: String {
        switch self {
        case .standard: "Follows light and dark mode."
        case .paper: "Warm, soft page tones that are easy on the eyes. Always light."
        case .midnight: "True black for OLED screens and late nights. Always dark."
        case .contrast: "Stronger text and edges for easier reading."
        }
    }
    /// Paper and Midnight pick light or dark for you.
    var scheme: ColorScheme? { switch self { case .paper: .light; case .midnight: .dark; default: nil } }

    var canvas: Color {
        switch self {
        case .paper: Color(red: 0.98, green: 0.965, blue: 0.94)
        case .midnight: .black
        default: Color(uiColor: .systemBackground)
        }
    }
    var elevated: Color {
        switch self {
        case .paper: Color(red: 0.95, green: 0.93, blue: 0.89)
        case .midnight: Color(white: 0.09)
        case .contrast: Color(uiColor: .tertiarySystemFill)
        default: Color(uiColor: .secondarySystemBackground)
        }
    }
    var inkSoft: Color {
        switch self {
        case .contrast: Color.primary.opacity(0.78)
        case .paper: Color(red: 0.42, green: 0.38, blue: 0.33)
        default: .secondary
        }
    }
    var ink: Color { self == .paper ? Color(red: 0.16, green: 0.14, blue: 0.12) : .primary }
}

enum KeelFontStyle: String, CaseIterable, Identifiable {
    case system, serif, rounded, mono
    var id: String { rawValue }
    var name: String { switch self { case .system: "Default"; case .serif: "Serif"; case .rounded: "Rounded"; case .mono: "Monospaced" } }
    var design: Font.Design { switch self { case .system: .default; case .serif: .serif; case .rounded: .rounded; case .mono: .monospaced } }
    static var current: KeelFontStyle { KeelFontStyle(rawValue: UserDefaults.standard.string(forKey: KeelLook.fontKey) ?? "") ?? .system }
}

struct LookSettingsSection: View {
    @AppStorage(KeelLook.key) private var lookRaw = KeelLook.standard.rawValue
    @AppStorage(KeelLook.fontKey) private var fontRaw = KeelFontStyle.system.rawValue

    var body: some View {
        Section {
            ForEach(KeelLook.allCases) { l in
                Button { lookRaw = l.rawValue; Haptics.tap() } label: {
                    HStack(spacing: DS.Space.m) {
                        RoundedRectangle(cornerRadius: 8).fill(l.canvas)
                            .overlay(RoundedRectangle(cornerRadius: 8).fill(l.elevated).padding(8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                            .frame(width: 44, height: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(l.name).foregroundStyle(DS.Palette.ink)
                            Text(l.blurb).font(.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        if lookRaw == l.rawValue { Image(systemName: "checkmark").foregroundStyle(DS.Palette.accent) }
                    }
                }
            }
        } header: { Text("Theme") }
        Section {
            Picker("Font", selection: $fontRaw) {
                ForEach(KeelFontStyle.allCases) { f in Text(f.name).fontDesign(f.design).tag(f.rawValue) }
            }
            .pickerStyle(.inline).labelsHidden()
        } header: { Text("Font") } footer: { Text("Changes the typeface everywhere: notes, mail, tasks and Today.") }
        Section {
            NavigationLink { MailLayoutSettings() } label: { Label("Mail layout", systemImage: "list.bullet.rectangle") }
            NavigationLink { InboxTabsSettings() } label: { Label("Inbox tabs", systemImage: "rectangle.split.3x1") }
            NavigationLink { TabBarSettings() } label: { Label("Tab bar", systemImage: "dock.rectangle") }
            Toggle(isOn: Binding(get: { UserDefaults.standard.object(forKey: "capture.fab") as? Bool ?? true }, set: { UserDefaults.standard.set($0, forKey: "capture.fab") })) {
                Label("Capture button on every screen", systemImage: "plus.circle")
            }
        } header: { Text("Layout") }
    }
}

// MARK: - Mail layout

struct MailLayout: Equatable {
    enum Density: String, CaseIterable, Identifiable { case compact, comfortable, spacious; var id: String { rawValue } }
    var density: Density = .compact            // Superhuman-dense by default; roomier in Settings → Mail → Layout
    var previewLines: Int = 1
    var avatars = true
    var aiSummary = true

    static let densityKey = "mail.layout.density", linesKey = "mail.layout.lines", avatarsKey = "mail.layout.avatars", summaryKey = "mail.layout.summary"
    var rowPadding: CGFloat { switch density { case .compact: 1; case .comfortable: 4; case .spacious: 9 } }
    var avatarSize: CGFloat { switch density { case .compact: 30; case .comfortable: 38; case .spacious: 44 } }
}

private struct MailLayoutKey: EnvironmentKey { static let defaultValue = MailLayout() }
extension EnvironmentValues {
    var mailLayout: MailLayout {
        get { self[MailLayoutKey.self] }
        set { self[MailLayoutKey.self] = newValue }
    }
}

/// Reads the mail layout settings once for the whole list (instead of in every row).
struct MailLayoutReader: ViewModifier {
    @AppStorage(MailLayout.densityKey) private var density = MailLayout.Density.compact.rawValue
    @AppStorage(MailLayout.linesKey) private var lines = 1
    @AppStorage(MailLayout.avatarsKey) private var avatars = true
    @AppStorage(MailLayout.summaryKey) private var summary = true
    func body(content: Content) -> some View {
        content.environment(\.mailLayout, MailLayout(density: MailLayout.Density(rawValue: density) ?? .compact,
                                                     previewLines: lines, avatars: avatars, aiSummary: summary))
    }
}

struct MailLayoutSettings: View {
    @AppStorage(MailLayout.densityKey) private var density = MailLayout.Density.compact.rawValue
    @AppStorage(MailLayout.linesKey) private var lines = 1
    @AppStorage(MailLayout.avatarsKey) private var avatars = true
    @AppStorage(MailLayout.summaryKey) private var summary = true

    var body: some View {
        Form {
            Section {
                Picker("Density", selection: $density) {
                    ForEach(MailLayout.Density.allCases) { Text($0.rawValue.capitalized).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Stepper("Preview: \(lines == 0 ? "none" : "\(lines) line\(lines == 1 ? "" : "s")")", value: $lines, in: 0...3)
                Toggle("Sender pictures", isOn: $avatars)
                Toggle("Show AI summary instead of the first lines", isOn: $summary)
            } header: { Text("Email list") }
            Section("Preview") {
                SampleMailRow(layout: MailLayout(density: MailLayout.Density(rawValue: density) ?? .compact, previewLines: lines, avatars: avatars, aiSummary: summary))
            }
            Section {
                Text("On iPad and Mac, Inbox shows the list and the email side by side. Rotate your iPad or widen the window to see both.")
                    .font(.caption).foregroundStyle(DS.Palette.inkSoft)
            }
        }
        .navigationTitle("Mail layout")
    }
}

private struct SampleMailRow: View {
    let layout: MailLayout
    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            if layout.avatars { SenderAvatar(name: "Dana Lee", email: "dana@example.com", size: layout.avatarSize) }
            VStack(alignment: .leading, spacing: 3) {
                HStack { Text("Dana Lee").font(DS.Font.headline); Spacer(); Text("9:41 AM").font(DS.Font.caption).foregroundStyle(DS.Palette.accent) }
                Text("Q3 budget: final numbers").font(DS.Font.body)
                if layout.previewLines > 0 {
                    Text(layout.aiSummary ? "Dana shared the final Q3 numbers and needs your sign-off by Friday." : "Hi! Attached are the final numbers for Q3. Can you take a look before Friday and let me know if anything looks off?")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(layout.previewLines)
                }
            }
        }
        .padding(.vertical, layout.rowPadding)
    }
}
