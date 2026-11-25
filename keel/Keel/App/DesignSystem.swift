import SwiftUI

/// Keel design language: calm, premium, ADHD-friendly.
/// Principles: one focal point per screen · generous whitespace · color means something
/// (never decoration) · motion confirms actions · nothing flashes or nags.
enum DS {
    // MARK: Color — muted base, a single accent, semantic hues for time/energy
    enum Palette {
        /// Accent follows Settings → Appearance (Keel indigo by default).
        // These are read thousands of times per screen (every label and card), so they come from a cache in
        // memory, not from settings storage on each read. The cache follows Settings → Appearance (see PaletteCache).
        static var accent: Color { PaletteCache.accent }
        // Follow Settings → Look & Feel → Theme (Standard, Paper, Midnight, High contrast).
        static var canvas: Color { PaletteCache.canvas }
        static var elevated: Color { PaletteCache.elevated }
        static var ink: Color { PaletteCache.ink }
        static var inkSoft: Color { PaletteCache.inkSoft }
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

    // MARK: Type — an editorial serif (New York) for display, crisp SF Pro for reading. Dynamic Type everywhere.
    enum Font {
        // Display type follows the theme (serif for most; heavy sans for Signal Flags). Cached per theme.
        static var hero: SwiftUI.Font { SwiftUI.Font.system(.largeTitle, design: PaletteCache.look.display, weight: PaletteCache.look.displayWeight) }
        static var title: SwiftUI.Font { SwiftUI.Font.system(.title2, design: PaletteCache.look.display, weight: PaletteCache.look.displayWeight) }
        /// A navigator's mono for times, coordinates and counts (Chart Table and Logbook).
        static let mono = SwiftUI.Font.system(.caption2, design: .monospaced).weight(.medium)
        static let headline = SwiftUI.Font.system(.headline, design: .default, weight: .semibold)
        static let body = SwiftUI.Font.system(.body, design: .default)
        static let caption = SwiftUI.Font.system(.caption, design: .default, weight: .medium)
        static let timer = SwiftUI.Font.system(size: 72, weight: .thin, design: .default).monospacedDigit()
    }

    enum Space { static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 16, l: CGFloat = 24, xl: CGFloat = 40 }
    enum Radius { static let card: CGFloat = 24, chip: CGFloat = 12 }

    // MARK: Motion
    /// Quick and settled, like Apple's own apps: everyday state changes (lists, cards, toggles).
    /// (Was a 0.35 s glide, which made every tap feel a beat behind.)
    static let spring = Animation.snappy(duration: 0.24)
    /// A touch of bounce, only for wins (finishing a task, a streak).
    static let celebrate = Animation.spring(duration: 0.32, bounce: 0.22)
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
/// A content card. Solid on purpose: Liquid Glass is for floating controls (toolbars, toasts), not content.
/// Glass on every card re-renders what's behind it every frame and plays its "materialize" animation each time
/// a screen appears, which made switching tabs and scrolling lag. This keeps the same shape, padding and tint.
struct GlassCard<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(DS.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { PremiumSurface(tint: tint) }
    }
}

/// Keel's card surface: lit softly from above, a hairline highlight on the top edge, a tint wash when the card
/// has a color, and a gentle lift off the page. All solid shapes, so it stays fast while scrolling.
struct PremiumSurface: View {
    var tint: Color? = nil
    var radius: CGFloat = DS.Radius.card
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            surface
        }
    }

    @ViewBuilder private var surface: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let dark = scheme == .dark
        // A soft edge underneath instead of a blurred shadow: looks lifted, costs nothing to draw while scrolling.
        shape.fill(Color.black.opacity(dark ? 0.45 : 0.045)).offset(y: dark ? 1.5 : 1)
        face(shape, dark: dark)
            // One flattened image per card: the gradients and the gradient edge are drawn once, not composited
            // layer by layer (with an off-screen pass for the edge) on every scroll frame.
            .drawingGroup()
    }

    private func face(_ shape: RoundedRectangle, dark: Bool) -> some View {
        shape.fill(LinearGradient(colors: [DS.Palette.elevated.mix(with: .white, by: dark ? 0.035 : 0.5), DS.Palette.elevated],
                                  startPoint: .top, endPoint: .bottom))
            .overlay {
                if let tint {
                    shape.fill(LinearGradient(colors: [tint.opacity(dark ? 0.18 : 0.10), tint.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .overlay {
                switch PaletteCache.look {
                case .chart, .logbook:          // a printed, inked edge
                    shape.strokeBorder(DS.Palette.ink.opacity(dark ? 0.22 : 0.16), lineWidth: 0.6)
                case .helm:                     // brass trim
                    shape.strokeBorder(Color(red: 0.85, green: 0.71, blue: 0.42).opacity(0.32), lineWidth: 0.8)
                case .lighthouse:               // a faint amber rim
                    shape.strokeBorder(Color(red: 1, green: 0.77, blue: 0.33).opacity(0.2), lineWidth: 0.6)
                case .flags:                    // flat and graphic
                    EmptyView()
                default:
                    shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(dark ? 0.12 : 0.95), Color.primary.opacity(dark ? 0.04 : 0.07)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 0.5)
                }
            }
    }
}

/// A page background with depth: the theme's canvas with a soft glow of the screen's color from the top.
/// Lists drop their flat gray so the glow shows through.
struct PremiumBackdrop: ViewModifier {
    let tint: Color
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background {
                ZStack {
                    DS.Palette.canvas
                    if EveningCalm.isEvening { Color(red: 1, green: 0.55, blue: 0.2).opacity(0.05) }    // warmer after sunset
                    ThemeBackdrop(tint: tint)
                }
                .ignoresSafeArea()
            }
    }
}

extension View {
    func premiumBackground(_ tint: Color = DS.Palette.accent) -> some View { modifier(PremiumBackdrop(tint: tint)) }
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
        .background(color.opacity(0.11), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 0.5))
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
                .modifier(RippleOnDone(done: isDone))           // Horizon: finishing sends a small ripple
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
    case indigo, champagne, onyx, ocean, forest, sunset, rose, graphite
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .indigo: Color(red: 0.33, green: 0.36, blue: 0.88)          // royal indigo
        case .champagne: Color(red: 0.72, green: 0.58, blue: 0.36)       // brushed gold
        case .onyx: Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.92, alpha: 1) : UIColor(white: 0.12, alpha: 1) })
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

// MARK: - App chrome

/// Navigation titles: an editorial serif for large titles, crisp SF for inline ones. Set once for every screen.
/// Only the title font changes; bar backgrounds and Liquid Glass stay as the system draws them.
@MainActor enum KeelChrome {
    static func apply() {
        func designed(_ style: UIFont.TextStyle, _ weight: UIFont.Weight, _ design: UIFontDescriptor.SystemDesign?) -> UIFont {
            let base = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize, weight: weight)
            let desc = design.flatMap { base.fontDescriptor.withDesign($0) } ?? base.fontDescriptor
            return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: desc, size: 0))
        }
        let nav = UINavigationBar.appearance()
        let look = PaletteCache.look
        nav.largeTitleTextAttributes = [.font: look == .flags ? designed(.largeTitle, .heavy, nil) : designed(.largeTitle, .semibold, .serif)]
        nav.titleTextAttributes = [.font: designed(.headline, .semibold, nil)]
    }
}


/// The current accent and theme colors, worked out once and kept in memory.
/// Refreshed when the app starts and whenever the accent or theme changes (RootView calls `sync`).
enum PaletteCache {
    nonisolated(unsafe) private static var key = ""
    nonisolated(unsafe) private(set) static var look: KeelLook = .chart
    nonisolated(unsafe) private(set) static var accent: Color = Theme.indigo.color
    nonisolated(unsafe) private(set) static var canvas: Color = KeelLook.standard.canvas
    nonisolated(unsafe) private(set) static var elevated: Color = KeelLook.standard.elevated
    nonisolated(unsafe) private(set) static var ink: Color = KeelLook.standard.ink
    nonisolated(unsafe) private(set) static var inkSoft: Color = KeelLook.standard.inkSoft

    /// Call with the stored accent and theme names; cheap when nothing changed.
    @MainActor static func sync(accent a: String, look l: String) {
        // An accent you picked yourself wins; otherwise the theme brings its own (brass, signal blue, amber…).
        let chosen = UserDefaults.standard.string(forKey: "accent")
        let k = a + "|" + l + "|" + (chosen ?? "-")
        guard k != key else { return }
        key = k
        let theme = Theme(rawValue: a) ?? .indigo
        let look = KeelLook(rawValue: l) ?? .chart
        let changedLook = look != Self.look
        Self.look = look
        accent = (chosen == nil ? look.accent : nil) ?? theme.color
        if changedLook { KeelChrome.apply() }
        canvas = look.canvas; elevated = look.elevated; ink = look.ink; inkSoft = look.inkSoft
    }

    @MainActor static func syncFromSettings() {
        sync(accent: UserDefaults.standard.string(forKey: "accent") ?? "", look: UserDefaults.standard.string(forKey: KeelLook.key) ?? "")
    }
}


// MARK: - Theme backdrops (all static: drawn once per screen size, nothing animates while you scroll)

struct ThemeBackdrop: View {
    let tint: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        switch PaletteCache.look {
        case .chart:
            // Chart paper: depth contours, a faint grid and the screen's colour as a soft wash.
            ZStack {
                ChartContours(ink: DS.Palette.ink.opacity(dark ? 0.10 : 0.075), grid: DS.Palette.inkSoft.opacity(dark ? 0.08 : 0.06))
                EllipticalGradient(colors: [tint.opacity(0.08), .clear], center: .top, startRadiusFraction: 0, endRadiusFraction: 0.8)
                    .frame(maxHeight: 520).frame(maxHeight: .infinity, alignment: .top)
            }
        case .helm:
            RadialGradient(colors: [Color(red: 0.12, green: 0.23, blue: 0.36), .clear], center: .top, startRadius: 0, endRadius: 560)
        case .tide:
            SeaBand()
        case .lighthouse:
            // A still, warm beam from the top corner.
            AngularGradient(colors: [.clear, Color(red: 1, green: 0.77, blue: 0.33).opacity(0.16), .clear], center: .topLeading,
                            startAngle: .degrees(20), endAngle: .degrees(70))
                .blur(radius: 18)
        case .panel:
            LinearGradient(colors: [Color.white.opacity(dark ? 0.04 : 0.5), .clear], startPoint: .top, endPoint: .center)
        case .logbook, .flags:
            Color.clear
        default:
            EllipticalGradient(colors: [tint.opacity(0.16), tint.opacity(0.05), .clear], center: .top, startRadiusFraction: 0, endRadiusFraction: 0.85)
                .frame(maxHeight: 560).frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

/// Nautical-chart depth lines and a light grid.
struct ChartContours: View {
    let ink: Color
    let grid: Color
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            for (i, base) in [0.16, 0.2, 0.24, 0.62, 0.66, 0.7].enumerated() {
                var p = Path()
                let y = h * base
                p.move(to: CGPoint(x: -20, y: y))
                p.addCurve(to: CGPoint(x: w + 20, y: y - 18 + CGFloat(i % 3) * 6),
                           control1: CGPoint(x: w * 0.3, y: y - 46), control2: CGPoint(x: w * 0.6, y: y + 44))
                ctx.stroke(p, with: .color(ink), lineWidth: 0.8)
            }
            var g = Path()
            stride(from: 0.0, through: Double(w), by: Double(w) / 3).forEach { x in g.move(to: CGPoint(x: x, y: 0)); g.addLine(to: CGPoint(x: x, y: h)) }
            stride(from: 0.0, through: Double(h), by: Double(h) / 5).forEach { y in g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: w, y: y)) }
            ctx.stroke(g, with: .color(grid), lineWidth: 0.5)
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

/// Living Tide: the sky at this time of day over a gentle swell at the top of the page.
struct SeaBand: View {
    var body: some View {
        let sky = HorizonSky.colors(at: Date())
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                LinearGradient(colors: sky, startPoint: .top, endPoint: .bottom)
                Canvas { ctx, size in
                    for (i, (y, a)) in [(0.55, 0.22), (0.7, 0.35), (0.84, 1.0)].enumerated() {
                        var p = Path()
                        let base = size.height * y
                        p.move(to: CGPoint(x: 0, y: base))
                        p.addCurve(to: CGPoint(x: size.width, y: base + CGFloat(i) * 2),
                                   control1: CGPoint(x: size.width * 0.33, y: base - 18), control2: CGPoint(x: size.width * 0.66, y: base + 18))
                        p.addLine(to: CGPoint(x: size.width, y: size.height)); p.addLine(to: CGPoint(x: 0, y: size.height)); p.closeSubpath()
                        ctx.fill(p, with: .color(i == 2 ? DS.Palette.canvas : .white.opacity(a)))
                    }
                }
            }
            .frame(height: 230)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
    }
}
