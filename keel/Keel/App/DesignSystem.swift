import SwiftUI

/// Keel design language: calm, premium, ADHD-friendly.
/// Principles: one focal point per screen · generous whitespace · color means something
/// (never decoration) · motion confirms actions · nothing flashes or nags.
enum DS {
    // MARK: Color — muted base, a single accent, semantic hues for time/energy
    enum Palette {
        static let accent = Color(red: 0.36, green: 0.42, blue: 0.98)       // Keel indigo
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
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let celebrate = Animation.spring(response: 0.5, dampingFraction: 0.55)
}

// MARK: - Haptics (dopamine on completion — important for ADHD reward loops)
@MainActor enum Haptics {
    private static var off: Bool { UserDefaults.standard.bool(forKey: "haptics.off") }
    static func tap() { guard !off else { return }; UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { guard !off else { return }; UINotificationFeedbackGenerator().notificationOccurred(.success) }
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
