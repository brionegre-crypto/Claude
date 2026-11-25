import SwiftUI
import SwiftData

// MARK: - Themed layouts
//
// Each theme lays its lists out differently, not just in different colours: Chart Table, Logbook and Signal Flags
// use full-width ruled lists (a chart margin, a log page, a flag hoist); Helm, Living Tide, Lighthouse and Instrument
// Panel keep grouped cards. Everything in the lists works the same way in every theme.

extension View {
    /// Ruled, full-width rows on chart paper, in the log and on the flags; grouped cards elsewhere.
    @ViewBuilder func themedListStyle() -> some View {
        switch PaletteCache.look {
        case .chart, .logbook, .flags: listStyle(.plain)
        default: listStyle(.insetGrouped)
        }
    }

    /// A list title: serif on chart paper and in the log, heavy on the flags, the usual weight elsewhere.
    func themedRowTitle(emphasised: Bool = false) -> some View {
        font(ThemedLayout.rowTitleFont(emphasised: emphasised))
    }
}

enum ThemedLayout {
    static func rowTitleFont(emphasised: Bool) -> Font {
        switch PaletteCache.look {
        case .chart, .logbook: .system(.body, design: .serif).weight(emphasised ? .semibold : .regular)
        case .flags: .body.weight(emphasised ? .heavy : .bold)
        default: emphasised ? DS.Font.headline : DS.Font.body
        }
    }

    /// Logbook-style time column on the left of a row (Chart Table and Logbook).
    static var usesTimeColumn: Bool { Nautical.usesMono }

    /// Themes whose Tasks Today opens with one big "Now" card (Helm, Living Tide, Lighthouse, Instrument Panel).
    static var usesNowCard: Bool {
        switch PaletteCache.look {
        case .helm, .tide, .lighthouse, .panel: true
        default: false
        }
    }
}

/// The time a task or entry is due, in a fixed-width column like a ship's log.
struct ThemedTimeColumn: View {
    let date: Date?
    var body: some View {
        Text(date.map { $0.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) } ?? "—")
            .font(DS.Font.mono)
            .foregroundStyle(date == nil ? DS.Palette.inkSoft.opacity(0.5) : DS.Palette.inkSoft)
            .frame(width: 44, alignment: .leading)
            .accessibilityHidden(date == nil)
    }
}

/// The next thing to do, big, with Start and Later: the top of Tasks Today on the Helm, Tide, Lighthouse and Panel.
struct TasksNowCard: View {
    let task: TaskItem
    @Environment(\.modelContext) private var ctx

    var body: some View {
        let look = PaletteCache.look
        let lead: Color = look == .helm ? Nautical.brass : look == .lighthouse ? Nautical.amber : DS.Palette.accent
        VStack(alignment: .leading, spacing: 10) {
            Text(look == .helm ? "ON COURSE" : look == .lighthouse ? "IN THE BEAM" : look == .panel ? "NEXT READING" : "NEXT WAVE")
                .font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(lead)
            Text(task.title).font(DS.Font.title).foregroundStyle(DS.Palette.ink).lineLimit(3)
            HStack(spacing: 6) {
                if let d = task.dueDate, task.hasDueTime { Text(d.formatted(date: .omitted, time: .shortened)).themedTime() }
                Text("~\(ADHDCoach.minutes(task)) min").font(.caption)
            }
            .foregroundStyle(DS.Palette.inkSoft)
            HStack(spacing: 10) {
                Button {
                    NowTimer.start(task, ctx: ctx); try? ctx.save()
                    AppRouter.shared.showFocus = true
                    Haptics.tap()
                } label: {
                    Label("Start", systemImage: "play.fill").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(lead, in: Capsule())
                        .foregroundStyle(look == .helm || look == .lighthouse ? .black : .white)
                }
                Button {
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                    TaskActions.reschedule(task, to: tomorrow); try? ctx.save()
                    Haptics.tap()
                } label: {
                    Text("Later").font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .overlay(Capsule().strokeBorder(lead.opacity(0.5), lineWidth: 1))
                        .foregroundStyle(DS.Palette.ink)
                }
                Spacer()
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { PremiumSurface(tint: lead) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Next: \(task.title)")
    }
}

/// An hour line in the day grid: dashed ink on the chart, a ruled line in the log, faint brass at the helm,
/// an amber thread in the lighthouse, the usual hairline elsewhere.
struct ThemedHourLine: View {
    var body: some View {
        switch PaletteCache.look {
        case .chart:
            Line().stroke(DS.Palette.ink.opacity(0.22), style: StrokeStyle(lineWidth: 0.6, dash: [3, 3])).frame(height: 0.6)
        case .logbook:
            Rectangle().fill(DS.Palette.ink.opacity(0.2)).frame(height: 0.7)
        case .helm:
            Rectangle().fill(Nautical.brass.opacity(0.16)).frame(height: 0.5)
        case .lighthouse:
            Rectangle().fill(Nautical.amber.opacity(0.14)).frame(height: 0.5)
        case .flags:
            Rectangle().fill(DS.Palette.ink.opacity(0.18)).frame(height: 1)
        default:
            Rectangle().fill(DS.Palette.inkSoft.opacity(0.14)).frame(height: 0.5)
        }
    }

    private struct Line: Shape {
        func path(in r: CGRect) -> Path { Path { $0.move(to: CGPoint(x: r.minX, y: r.midY)); $0.addLine(to: CGPoint(x: r.maxX, y: r.midY)) } }
    }
}

/// A page's icon in Notes: inked frame on the chart, bare in the log, a signal square on the flags, a tinted tile elsewhere.
struct ThemedNoteIcon: View {
    let icon: String
    let isDatabase: Bool
    var body: some View {
        let tint = isDatabase ? Color.purple : DS.Palette.accent
        let glyph = Text(icon).font(.system(size: 18)).frame(width: 34, height: 34)
        switch PaletteCache.look {
        case .chart:
            glyph.background(DS.Palette.elevated, in: .rect(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(DS.Palette.ink.opacity(0.3), lineWidth: 0.7))
        case .logbook:
            glyph.frame(width: 26)
        case .flags:
            glyph.background(tint.opacity(0.85), in: .rect(cornerRadius: 3))
        case .helm:
            glyph.overlay(Circle().strokeBorder(Nautical.brass.opacity(0.5), lineWidth: 0.8))
        case .lighthouse:
            glyph.overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Nautical.amber.opacity(0.35), lineWidth: 0.8))
        default:
            glyph.background(tint.opacity(0.1), in: .rect(cornerRadius: 9))
        }
    }
}
