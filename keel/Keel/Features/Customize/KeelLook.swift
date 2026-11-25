import SwiftUI
import UIKit

// MARK: - Themes and fonts

/// The overall look. Read live from settings, so changing it redraws the app at once.
enum KeelLook: String, CaseIterable, Identifiable {
    // Nautical themes (Chart Table is Keel's own look), then the original four.
    case chart, helm, tide, logbook, flags, lighthouse, panel
    case standard, paper, midnight, contrast
    static let key = "look.theme", fontKey = "look.font"
    var id: String { rawValue }

    /// Chart Table, unless you picked another theme.
    static var current: KeelLook { KeelLook(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .chart }

    var name: String {
        switch self {
        case .chart: "Chart Table"; case .helm: "The Helm"; case .tide: "Living Tide"; case .logbook: "Logbook"
        case .flags: "Signal Flags"; case .lighthouse: "Lighthouse"; case .panel: "Instrument Panel"
        case .standard: "Standard"; case .paper: "Paper"; case .midnight: "Midnight"; case .contrast: "High contrast"
        }
    }
    var blurb: String {
        switch self {
        case .chart: "Keel's own: warm chart paper, depth contours and a navigator's type. Light by day, night chart in dark mode."
        case .helm: "Navy and brass, like a ship's wheelhouse. Always dark."
        case .tide: "The sea at the top of every screen, its sky following the time of day."
        case .logbook: "An editorial captain's log: cream pages and quiet serif type. The calmest."
        case .flags: "Bold maritime signal colours and big confident type."
        case .lighthouse: "True black with a warm amber beam. For evenings and OLED screens. Always dark."
        case .panel: "A ship's bridge in light porcelain: precise, like a luxury watch face."
        case .standard: "Follows light and dark mode."
        case .paper: "Warm, soft page tones that are easy on the eyes. Always light."
        case .midnight: "True black for OLED screens and late nights. Always dark."
        case .contrast: "Stronger text and edges for easier reading."
        }
    }
    var isNautical: Bool { ![.standard, .paper, .midnight, .contrast].contains(self) }

    /// Some themes pick light or dark for you.
    var scheme: ColorScheme? { switch self { case .paper: .light; case .midnight, .helm, .lighthouse: .dark; default: nil } }

    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        func c(_ v: UInt32) -> UIColor { UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1) }
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? c(dark) : c(light) })
    }
    private static func hex(_ v: UInt32) -> Color { dyn(v, v) }

    var canvas: Color {
        switch self {
        case .chart: Self.dyn(0xF3EEE2, 0x0F1A28)
        case .helm: Self.hex(0x0B1626)
        case .tide: Self.dyn(0xF6F8FB, 0x0A1422)
        case .logbook: Self.dyn(0xFBF8F1, 0x17140F)
        case .flags: Self.dyn(0xFFFFFF, 0x000000)
        case .lighthouse: Self.hex(0x000000)
        case .panel: Self.dyn(0xE6EAF0, 0x0E141D)
        case .paper: Color(red: 0.98, green: 0.965, blue: 0.94)
        case .midnight: .black
        case .contrast: Color(uiColor: .systemBackground)
        case .standard: Self.dyn(0xF8F6F4, 0x0E0F11)
        }
    }
    var elevated: Color {
        switch self {
        case .chart: Self.dyn(0xFBF8F0, 0x172334)
        case .helm: Self.hex(0x142640)
        case .tide: Self.dyn(0xFFFFFF, 0x12213A)
        case .logbook: Self.dyn(0xFFFDF8, 0x201C16)
        case .flags: Self.dyn(0xF4F5F7, 0x1A1A1C)
        case .lighthouse: Self.hex(0x111112)
        case .panel: Self.dyn(0xFFFFFF, 0x18212D)
        case .paper: Color(red: 0.95, green: 0.93, blue: 0.89)
        case .midnight: Color(white: 0.09)
        case .contrast: Color(uiColor: .tertiarySystemFill)
        case .standard: Self.dyn(0xFFFFFF, 0x1B1C20)
        }
    }
    var ink: Color {
        switch self {
        case .chart: Self.dyn(0x1D2B3F, 0xEDE6D6)
        case .helm: Self.hex(0xF4EAD6)
        case .tide: Self.dyn(0x0E1A2B, 0xEAF1F8)
        case .logbook: Self.dyn(0x24201A, 0xEFE7D8)
        case .flags: Self.dyn(0x0B0B0C, 0xFFFFFF)
        case .lighthouse: Self.hex(0xE9E6DF)
        case .panel: Self.dyn(0x142033, 0xE3EAF3)
        case .paper: Color(red: 0.16, green: 0.14, blue: 0.12)
        default: .primary
        }
    }
    var inkSoft: Color {
        switch self {
        case .chart: Self.dyn(0x6E6450, 0xA79D88)
        case .helm: Self.hex(0xB9A887)
        case .tide: Self.dyn(0x5E6B7D, 0x9AA9BC)
        case .logbook: Self.dyn(0x8A7B62, 0xA89A80)
        case .flags: Self.dyn(0x6B6B70, 0x9A9AA0)
        case .lighthouse: Self.hex(0x8F897C)
        case .panel: Self.dyn(0x6B7A90, 0x8B98AB)
        case .contrast: Color.primary.opacity(0.78)
        case .paper: Color(red: 0.42, green: 0.38, blue: 0.33)
        default: .secondary
        }
    }
    /// The accent when you haven't picked one in Appearance.
    var accent: Color? {
        switch self {
        case .chart: Self.dyn(0x1D3B66, 0xD8B46A)          // chart navy; brass at night
        case .helm: Self.hex(0xD8B46A)                      // brass
        case .tide: Self.dyn(0x3D77B0, 0x6FA8E0)
        case .logbook: Self.dyn(0x7A4E2D, 0xC99A6B)         // saddle leather
        case .flags: Self.dyn(0x0B3D91, 0x4C8DFF)           // signal blue
        case .lighthouse: Self.hex(0xFFC454)                // lamp amber
        case .panel: Self.dyn(0x2A9FD0, 0x4FB8E6)           // instrument blue
        default: nil
        }
    }
    /// Display type for titles and big numbers.
    var display: Font.Design { self == .flags ? .default : .serif }
    var displayWeight: Font.Weight { self == .flags ? .heavy : .semibold }
}

enum KeelFontStyle: String, CaseIterable, Identifiable {
    case system, serif, rounded, mono
    var id: String { rawValue }
    var name: String { switch self { case .system: "Default"; case .serif: "Serif"; case .rounded: "Rounded"; case .mono: "Monospaced" } }
    var design: Font.Design { switch self { case .system: .default; case .serif: .serif; case .rounded: .rounded; case .mono: .monospaced } }
    static var current: KeelFontStyle { KeelFontStyle(rawValue: UserDefaults.standard.string(forKey: KeelLook.fontKey) ?? "") ?? .system }
}

struct LookSettingsSection: View {
    @AppStorage(KeelLook.key) private var lookRaw = KeelLook.chart.rawValue
    @AppStorage(KeelLook.fontKey) private var fontRaw = KeelFontStyle.system.rawValue

    var body: some View {
        Section {
            ForEach(KeelLook.allCases.filter(\.isNautical)) { l in row(l) }
        } header: { Text("Nautical themes") } footer: { Text("Chart Table is Keel's own look. Every theme keeps every feature.") }
        Section {
            ForEach(KeelLook.allCases.filter { !$0.isNautical }) { l in row(l) }
        } header: { Text("Classic") }
        Section {
            Picker("Font", selection: $fontRaw) {
                ForEach(KeelFontStyle.allCases) { f in Text(f.name).fontDesign(f.design).tag(f.rawValue) }
            }
            .pickerStyle(.inline).labelsHidden()
        } header: { Text("Font") } footer: { Text("Changes the typeface everywhere: notes, mail, tasks and Today.") }
        layoutSection
    }

    private func row(_ l: KeelLook) -> some View {
        Button { lookRaw = l.rawValue; Haptics.tap() } label: {
            HStack(spacing: DS.Space.m) {
                ThemeSwatch(look: l)
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.name).foregroundStyle(DS.Palette.ink)
                    Text(l.blurb).font(.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                Spacer()
                if lookRaw == l.rawValue { Image(systemName: "checkmark").foregroundStyle(DS.Palette.accent) }
            }
        }
    }

    private var layoutSection: some View {
        Group {
        Section {
            NavigationLink { LazyView(MailLayoutSettings()) } label: { Label("Mail layout", systemImage: "list.bullet.rectangle") }
            NavigationLink { LazyView(InboxTabsSettings()) } label: { Label("Inbox tabs", systemImage: "rectangle.split.3x1") }
            NavigationLink { LazyView(TabBarSettings()) } label: { Label("Tab bar", systemImage: "dock.rectangle") }
            Toggle(isOn: Binding(get: { UserDefaults.standard.object(forKey: "capture.fab") as? Bool ?? true }, set: { UserDefaults.standard.set($0, forKey: "capture.fab") })) {
                Label("Capture button on every screen", systemImage: "plus.circle")
            }
        } header: { Text("Layout") }
        }
    }
}

/// A tiny preview of a theme: its page, a card and its accent.
struct ThemeSwatch: View {
    let look: KeelLook
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 8).fill(look.canvas)
            RoundedRectangle(cornerRadius: 5).fill(look.elevated).padding(7)
            Circle().fill(look.accent ?? DS.Palette.accent).frame(width: 9, height: 9).padding(4)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
        .frame(width: 44, height: 32)
        .environment(\.colorScheme, look.scheme ?? .light)
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
