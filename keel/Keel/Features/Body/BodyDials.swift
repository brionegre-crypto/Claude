import SwiftUI

// MARK: - Body home: Tide · Swell · Anchor
//
// One big dial at a time (swipe between them), like a premium health dashboard: the score, what it means in a
// word, how it compares with your own normal, and your last 7 days. Tap a dial for the full story.

struct BodyDials: View {
    let day: BodyDay?
    let days: [BodyDay]
    @State private var page = 0

    var body: some View {
        let target = BodyMath.swellTarget(day?.tide)
        VStack(spacing: 10) {
            TabView(selection: $page) {
                dial(.tide, value: day?.tide, color: BodyStyle.tide, max: 100, suffix: "%",
                     word: tideWord(day?.tide), sub: "Recovery").tag(0)
                dial(.swell, value: day?.swell, color: BodyStyle.swell, max: 100, suffix: "",
                     word: "Target \(target.lowerBound)–\(target.upperBound)", sub: "Effort").tag(1)
                dial(.anchor, value: day?.anchor, color: BodyStyle.anchor, max: 100, suffix: "",
                     word: anchorWord(day), sub: "Sleep").tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 300)
            HStack(spacing: 18) {
                chip("Tide", day?.tide.map { "\($0)%" }, BodyStyle.tide, 0)
                chip("Swell", day.map { "\($0.swell)" }, BodyStyle.swell, 1)
                chip("Anchor", day?.anchor.map { "\($0)" }, BodyStyle.anchor, 2)
            }
        }
        .padding(.vertical, 12)
        .background { PremiumSurface(tint: [BodyStyle.tide, BodyStyle.swell, BodyStyle.anchor][page]) }
    }

    private func chip(_ name: String, _ v: String?, _ c: Color, _ i: Int) -> some View {
        Button { withAnimation(DS.spring) { page = i } } label: {
            VStack(spacing: 2) {
                Text(v ?? "–").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(page == i ? c : DS.Palette.ink)
                Text(name.uppercased()).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(page == i ? c : DS.Palette.inkSoft)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(page == i ? c.opacity(0.12) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func dial(_ m: BodyMetric, value: Int?, color: Color, max: Int, suffix: String, word: String, sub: String) -> some View {
        let normal = BodyDash.average(m, days: days, count: 30)
        let last7 = days.suffix(7).map { m.value($0) }
        return NavigationLink { LazyView(BodyMetricDetailView(metric: m)) } label: {
            VStack(spacing: 12) {
                ZStack {
                    Circle().stroke(color.opacity(0.12), lineWidth: 16)
                    Circle().trim(from: 0, to: CGFloat(Swift.min(1, Double(value ?? 0) / Double(max))))
                        .stroke(AngularGradient(colors: [color.opacity(0.55), color], center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                                style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text(m == .tide ? "TIDE" : m == .swell ? "SWELL" : "ANCHOR").font(.caption.weight(.bold)).tracking(2).foregroundStyle(color)
                        Text(value.map { "\($0)\(suffix)" } ?? "–")
                            .font(.system(size: 58, weight: .light)).monospacedDigit().foregroundStyle(DS.Palette.ink)
                            .contentTransition(.numericText())
                        Text(word).font(.footnote.weight(.medium)).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
                .frame(width: 190, height: 190)
                HStack(spacing: 14) {
                    if let n = normal, let v = value {
                        let diff = Double(v) - n
                        Label(abs(diff) < 2 ? "At your normal" : "\(diff > 0 ? "+" : "−")\(Int(abs(diff).rounded())) vs normal",
                              systemImage: abs(diff) < 2 ? "equal.circle" : diff > 0 ? "arrow.up.right.circle" : "arrow.down.right.circle")
                            .font(.caption.weight(.medium)).foregroundStyle(DS.Palette.inkSoft)
                    }
                    // Last 7 days at a glance.
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(Array(last7.enumerated()), id: \.offset) { i, v in
                            Capsule().fill(i == last7.count - 1 ? color : color.opacity(0.35))
                                .frame(width: 5, height: CGFloat(4 + Swift.min(1, (v ?? 0) / Double(max)) * 22))
                        }
                    }
                    .frame(height: 26, alignment: .bottom)
                    .accessibilityHidden(true)
                }
                Text(sub + " · tap for the full story").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func tideWord(_ t: Int?) -> String {
        guard let t else { return "Needs a night with your Watch" }
        return t >= 67 ? "Primed" : t >= 34 ? "Steady" : "Recover"
    }

    private func anchorWord(_ d: BodyDay?) -> String {
        guard let d, d.hasSleep else { return "No sleep recorded" }
        let h = Int(d.asleep) / 60, m = Int(d.asleep) % 60
        return "\(h)h \(m)m asleep"
    }
}
