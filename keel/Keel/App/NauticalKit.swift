import SwiftUI

// MARK: - Nautical kit
//
// The building blocks every screen uses, each drawn differently per theme, so a theme changes the structure and feel of
// the whole app (headers, section labels, icons, list marks, calendar blocks), not just its colours. Classic looks keep
// the original components.

enum Nautical {
    static var look: KeelLook { PaletteCache.look }
    static let brass = Color(red: 0.85, green: 0.71, blue: 0.42)
    static let amber = Color(red: 1, green: 0.77, blue: 0.33)
    static let chartRed = Color(red: 0.75, green: 0.22, blue: 0.17)
    static let signalBlue = Color(red: 0.04, green: 0.24, blue: 0.57)
    static let signalYellow = Color(red: 1, green: 0.8, blue: 0)
    static let signalRed = Color(red: 0.84, green: 0.16, blue: 0.16)

    /// Times and small counts: a navigator's mono on Chart Table and Logbook.
    static var usesMono: Bool { look == .chart || look == .logbook }
}

/// A tool or setting icon, in the theme's language: inked square on chart paper, brass ring at the helm, solid signal
/// square, amber lamp outline, a raised instrument button, a bare inked glyph in the log.
struct ThemedGlyph: View {
    let icon: String
    let color: Color
    var size: CGFloat = 32

    var body: some View {
        let symbol = Image(systemName: icon).font(.system(size: size * 0.45, weight: .semibold))
        switch Nautical.look {
        case .chart:
            symbol.foregroundStyle(DS.Palette.ink)
                .frame(width: size, height: size)
                .background(DS.Palette.elevated, in: .rect(cornerRadius: size * 0.22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).strokeBorder(DS.Palette.ink.opacity(0.35), lineWidth: 0.8))
                .overlay(alignment: .bottomTrailing) { Circle().fill(color).frame(width: size * 0.2, height: size * 0.2).offset(x: 2, y: 2) }
        case .helm:
            symbol.foregroundStyle(Nautical.brass)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.04)))
                .overlay(Circle().strokeBorder(Nautical.brass.opacity(0.6), lineWidth: 1))
        case .flags:
            symbol.foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(color, in: .rect(cornerRadius: 4))
        case .lighthouse:
            symbol.foregroundStyle(Nautical.amber)
                .frame(width: size, height: size)
                .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(Nautical.amber.opacity(0.45), lineWidth: 1))
        case .panel:
            symbol.foregroundStyle(color)
                .frame(width: size, height: size)
                .background(Circle().fill(RadialGradient(colors: [.white, Color(white: 0.9)], center: .init(x: 0.5, y: 0.3), startRadius: 0, endRadius: size)))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
        case .logbook:
            symbol.foregroundStyle(DS.Palette.ink).frame(width: size, height: size)
        case .tide:
            symbol.foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .top, endPoint: .bottom), in: Circle())
        default:
            symbol.foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(color.gradient, in: .rect(cornerRadius: size * 0.32, style: .continuous))
        }
    }
}

/// A section heading: mono small caps on the chart and in the log, brass on the helm, heavy on the flags.
struct ThemedSectionHeader: View {
    let title: String
    var body: some View {
        switch Nautical.look {
        case .chart, .logbook:
            Text(title.uppercased()).font(DS.Font.mono).tracking(1.2).foregroundStyle(DS.Palette.inkSoft)
        case .helm:
            Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(Nautical.brass)
        case .lighthouse:
            Text(title.uppercased()).font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(Nautical.amber.opacity(0.85))
        case .flags:
            Text(title).font(.headline.weight(.heavy)).foregroundStyle(DS.Palette.ink).textCase(nil)
        case .panel, .tide:
            Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(DS.Palette.inkSoft)
        default:
            Text(title)
        }
    }
}

/// "Unread" / "new": a chart-red fix, a brass rivet, a signal pennant, a lamp.
struct ThemedUnreadMark: View {
    var size: CGFloat = 9
    var body: some View {
        switch Nautical.look {
        case .chart: Circle().fill(Nautical.chartRed).frame(width: size, height: size).overlay(Circle().stroke(Nautical.chartRed.opacity(0.35), lineWidth: 1).frame(width: size * 2, height: size * 2))
        case .helm: Circle().fill(Nautical.brass).frame(width: size, height: size)
        case .flags: Triangle().fill(Nautical.signalRed).frame(width: size * 1.4, height: size)
        case .lighthouse: Circle().fill(Nautical.amber).frame(width: size, height: size).shadow(color: Nautical.amber, radius: 4)
        default: Circle().fill(DS.Palette.accent).frame(width: size, height: size)
        }
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path { Path { $0.move(to: CGPoint(x: r.minX, y: r.minY)); $0.addLine(to: CGPoint(x: r.maxX, y: r.midY)); $0.addLine(to: CGPoint(x: r.minX, y: r.maxY)); $0.closeSubpath() } }
}

/// A calendar block, per theme: inked chart note, brass-trimmed navy plate, solid signal colour, amber-rimmed black.
struct ThemedEventBackground: ViewModifier {
    let color: Color
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Nautical.look == .flags ? 4 : 8, style: .continuous)
        switch Nautical.look {
        case .chart:
            // Tide chart: meetings are soft shaded bands, so your own tasks (bold, outlined) stand out.
            content.background(DS.Palette.ink.opacity(scheme == .dark ? 0.16 : 0.07)).clipShape(shape)
        case .logbook:
            content.background(DS.Palette.elevated.opacity(0.95)).clipShape(shape)
                .overlay(shape.strokeBorder(DS.Palette.ink.opacity(0.3), lineWidth: 0.7))
        case .helm:
            content.background(Color(red: 0.08, green: 0.15, blue: 0.25)).clipShape(shape)
                .overlay(shape.strokeBorder(Nautical.brass.opacity(0.45), lineWidth: 0.8))
        case .flags:
            content.background(color.opacity(scheme == .dark ? 0.55 : 0.32)).clipShape(shape)
        case .lighthouse:
            content.background(Color(white: 0.07)).clipShape(shape)
                .overlay(shape.strokeBorder(Nautical.amber.opacity(0.3), lineWidth: 0.7))
        case .panel:
            content.background(.white.opacity(scheme == .dark ? 0.08 : 1)).clipShape(shape)
                .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
        default:
            content.background(color.opacity(scheme == .dark ? 0.30 : 0.16)).clipShape(shape)
        }
    }
}

/// Times in lists: mono on the chart and in the log.
extension View {
    func themedTime() -> some View { font(Nautical.usesMono ? DS.Font.mono : .caption) }
}
