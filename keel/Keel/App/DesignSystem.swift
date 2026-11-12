import SwiftUI

/// Keel design language: calm, premium, ADHD-friendly.
/// Principles: one focal point per screen · generous whitespace · color means something
/// (never decoration) · motion confirms actions · nothing flashes or nags.
enum DS {
    // MARK: Color — muted base, a single accent, semantic hues for time/energy
    enum Palette {
        /// Accent follows Settings → Appearance (Keel indigo by default).
        static var accent: Color { Theme.current.color }
        static let canvas = Color(uiColor: .systemBackground)
        static let elevated = Color(uiColor: .secondarySystemBackground)
        static let ink = Color.primary
        static let inkSoft = Color.secondary
        static let focus = Color(red: 0.42, green: 0.36, blue: 0.95)
        static let calm = Color(red: 0.27, green: 0.70, blue: 0.62)         // done / healthy
        static let warmth = Color(red: 0.98, green: 0.62, blue: 0.29)       // gentle attention, never red alarms
        static let meeting = Color(red: 0.33, green: 0.62, blue: 0.95)

        static func category(_ c: TriageCategory) -> Color {
            switch c {
            case .important: accent
            case .actionable: warmth
            case .calendar: meeting
            case .updates, .lowPriority: .gray
            case .newsletters: calm
            case .promotions: .pink.opacity(0.7)
            }
        }
    }

    // MARK: Type — SF Pro Rounded for warmth, big readable sizes, Dynamic Type everywhere
    enum Font {
        static let hero = SwiftUI.Font.system(.largeTitle, design: .rounded, weight: .bold)
        static let title = SwiftUI.Font.system(.title2, design: .rounded, weight: .semibold)
        static let headline = SwiftUI.Font.system(.headline, design: .rounded)
        static let body = SwiftUI.Font.system(.body, design: .default)
        static let caption = SwiftUI.Font.system(.caption, design: .rounded, weight: .medium)
        static let timer = SwiftUI.Font.system(size: 72, weight: .light, design: .rounded).monospacedDigit()
    }

    enum Space { static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 16, l: CGFloat = 24, xl: CGFloat = 40 }
    enum Radius { static let card: CGFloat = 22, chip: CGFloat = 12 }

    // MARK: Motion
    /// Smooth, critically damped motion (no wobble) for everyday state changes: lists, cards, toggles.
    static let spring = Animation.smooth(duration: 0.35)
    /// A touch of bounce, only for wins (finishing a task, a streak).
    static let celebrate = Animation.spring(duration: 0.45, bounce: 0.25)
}

// MARK: - Haptics (dopamine on completion — important for ADHD reward loops)
@MainActor enum Haptics {
    private static var off: Bool { UserDefaults.standard.bool(forKey: "haptics.off") }
    // Reused and kept warm, so a tap's haptic lands with the touch instead of a beat later.
    private static let light: UIImpactFeedbackGenerator = { let g = UIImpactFeedbackGenerator(style: .light); g.prepare(); return g }()
    private static let notify: UINotificationFeedbackGenerator = { let g = UINotificationFeedbackGenerator(); g.prepare(); return g }()
    static func tap() { guard !off else { return }; light.impactOccurred(); light.prepare() }
    static func success() { guard !off else { return }; notify.notificationOccurred(.success); notify.prepare() }
    static func milestone() {
        guard !off else { return }
        let g = UIImpactFeedbackGenerator(style: .rigid)
        g.impactOccurred()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            g.impactOccurred(intensity: 0.7)
        }
    }
}

// MARK: - Components

/// Liquid Glass card (iOS 26).
struct GlassCard<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(DS.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(tint.map { .regular.tint($0.opacity(0.18)) } ?? .regular,
                         in: .rect(cornerRadius: DS.Radius.card))
    }
}

struct Chip: View {
    let text: String
    var color: Color = DS.Palette.accent
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .font(DS.Font.caption)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(color.opacity(0.14), in: Capsule())
        .foregroundStyle(color)
    }
}

/// Satisfying check-off: haptic + bounce + strike. Completing things should *feel* good.
struct CompletionCheck: View {
    @Binding var isDone: Bool
    var body: some View {
        Button {
            withAnimation(DS.celebrate) { isDone.toggle() }
            isDone ? Haptics.success() : Haptics.tap()
        } label: {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isDone ? DS.Palette.calm : DS.Palette.inkSoft)
                .symbolEffect(.bounce, value: isDone)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDone ? "Mark not done" : "Mark done")
    }
}

/// Visual time remaining — a shrinking ring beats a number for time blindness.
struct TimeRing: View {
    let progress: Double   // 0…1 remaining
    var color: Color = DS.Palette.focus
    var lineWidth: CGFloat = 14
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
        }
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title).font(DS.Font.headline)
            Spacer()
            if let trailing { Text(trailing).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft) }
        }
        .padding(.horizontal, DS.Space.xs)
    }
}

/// Accent color choices (Settings → Appearance).
enum Theme: String, CaseIterable, Identifiable {
    case indigo, ocean, forest, sunset, rose, graphite
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .indigo: Color(red: 0.36, green: 0.42, blue: 0.98)
        case .ocean: Color(red: 0.12, green: 0.55, blue: 0.86)
        case .forest: Color(red: 0.20, green: 0.62, blue: 0.42)
        case .sunset: Color(red: 0.96, green: 0.50, blue: 0.25)
        case .rose: Color(red: 0.90, green: 0.33, blue: 0.52)
        case .graphite: Color(red: 0.38, green: 0.40, blue: 0.46)
        }
    }
    static var current: Theme { Theme(rawValue: UserDefaults.standard.string(forKey: "accent") ?? "") ?? .indigo }
}

/// Alternate app icons (Settings → Appearance).
enum AppIconChoice: String, CaseIterable, Identifiable {
    case standard = "Default", steady = "Steady", oneThing = "OneThing", checkK = "CheckK", sunset = "Sunset"
    var id: String { rawValue }
    var label: String {
        switch self { case .standard: "Sailboat"; case .steady: "Steady keel"; case .oneThing: "One thing"; case .checkK: "Check-K"; case .sunset: "Shutdown sun" }
    }
    var iconName: String? { self == .standard ? nil : "AppIcon-\(rawValue)" }
    var preview: String { "IconPreview-\(rawValue)" }
}

// MARK: - Larger text & Display Zoom

/// A fixed point size that still follows the person's text size setting (Settings → Display & Brightness → Text Size,
/// or Accessibility → Larger Text), up to a ceiling so small labels stay readable without breaking their layout.
struct ScaledFont: ViewModifier {
    @ScaledMetric private var scaled: CGFloat
    private let base: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design
    private let maxScale: CGFloat

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, maxScale: CGFloat?) {
        base = size
        self.weight = weight
        self.design = design
        self.maxScale = maxScale ?? (size >= 28 ? 1.3 : 1.8)
        let style: Font.TextStyle = size <= 11 ? .caption2 : size <= 13 ? .footnote : size <= 17 ? .body : size <= 22 ? .title3 : size <= 28 ? .title : .largeTitle
        _scaled = ScaledMetric(wrappedValue: size, relativeTo: style)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: min(scaled, base * maxScale), weight: weight, design: design))
    }
}

extension View {
    /// Use instead of `.font(.system(size:))` for anything people read.
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, maxScale: CGFloat? = nil) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design, maxScale: maxScale))
    }
}

/// A card grid that drops columns as text gets bigger: 3 → 2 at large sizes, and 1 column at accessibility sizes,
/// so titles never get squeezed into a sliver (also helps with Display Zoom on smaller iPhones).
struct FlexGrid<Content: View>: View {
    let columns: Int
    var spacing: CGFloat = 10
    var alignment: HorizontalAlignment = .center
    @ViewBuilder let content: () -> Content
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var hSize

    private var count: Int {
        if typeSize.isAccessibilitySize { return hSize == .regular ? min(2, columns) : 1 }
        if typeSize >= .xxLarge && columns > 2 { return 2 }
        return columns
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: max(1, count)), alignment: alignment, spacing: spacing) {
            content()
        }
    }
}

/// Settings → Appearance → Text Size: follow the iPhone, or pick a size just for Keel.
enum KeelTextSize {
    static let key = "appearance.textSize"
    static let choices: [(String, DynamicTypeSize?)] = [
        ("Use iPhone Setting", nil), ("Smaller", .medium), ("Default", .large), ("Large", .xLarge), ("Larger", .xxLarge),
        ("Extra Large", .xxxLarge), ("Huge", .accessibility1), ("Biggest", .accessibility3),
    ]
}

struct KeelTextSizeModifier: ViewModifier {
    @AppStorage(KeelTextSize.key) private var index = 0
    func body(content: Content) -> some View {
        let picked = KeelTextSize.choices.indices.contains(index) ? KeelTextSize.choices[index].1 : nil
        if let picked {
            content.dynamicTypeSize(picked)
        } else {
            // Follows the iPhone all the way into the larger accessibility sizes; the top two are capped so layouts hold.
            content.dynamicTypeSize(...DynamicTypeSize.accessibility3)
        }
    }
}
