import SwiftUI
import Charts

// MARK: - Body's top section, in three styles
//
// Rings (dark, sport-watch), Story (light, editorial, explains the numbers) and Control room (dense tiles with
// 14-day sparklines). Pick one with the switcher; everything below it in Body stays the same. All numbers are
// yours, from Apple Health, compared with your own 30-day normal.

enum BodyHeroStyle: String, CaseIterable, Identifiable {
    case rings, story, control
    var id: String { rawValue }
    var label: String { switch self { case .rings: "Rings"; case .story: "Story"; case .control: "Control room" } }
}

/// Today's numbers and your normal, worked out once per redraw.
struct BodySnapshot {
    let day: BodyDay?
    let tide: Int?, swell: Int, anchor: Int?
    let target: ClosedRange<Int>
    let hrv: Double?, rhr: Double?, resp: Double?, spo2: Double?, vo2: Double?
    let hrvNormal: Double?, rhrNormal: Double?
    let sleepMin: Double, needMin: Double
    let steps: Int
    let history: [BodyDay]

    init(day: BodyDay?, days: [BodyDay], steps: Int) {
        self.day = day
        tide = day?.tide; swell = day?.swell ?? 0; anchor = day?.anchor
        target = BodyMath.swellTarget(day?.tide)
        hrv = day?.hrv; rhr = day?.rhr; resp = day?.resp; spo2 = day?.spo2; vo2 = day?.vo2
        let month = days.suffix(30)
        func avg(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }
        hrvNormal = avg(month.compactMap(\.hrv)); rhrNormal = avg(month.compactMap(\.rhr))
        sleepMin = day?.asleep ?? 0
        needMin = (day?.need ?? BodyPrefs.sleepNeed) * 60
        self.steps = steps
        history = Array(days.suffix(14))
    }

    var call: (title: String, detail: String, color: Color) {
        guard let t = tide else { return ("Wear your Watch to bed", "Recovery needs a night of heart data.", .gray) }
        if t >= 67 { return ("Green light. Go hard today.", "Aim for effort \(target.lowerBound)–\(target.upperBound).", .green) }
        if t >= 34 { return ("Steady day. Train, don't strain.", "Aim for effort \(target.lowerBound)–\(target.upperBound).", .yellow) }
        return ("Recovery day. Go easy.", "Keep effort under \(target.upperBound), sleep early.", .orange)
    }

    /// One sentence explaining Tide from what moved it.
    var story: String {
        var parts: [String] = []
        if let h = hrv, let n = hrvNormal { let d = Int((h - n).rounded()); parts.append(d >= 0 ? "heart rate variability is \(d) ms above your normal" : "heart rate variability is \(-d) ms below your normal") }
        if let r = rhr, let n = rhrNormal { let d = Int((r - n).rounded()); if d != 0 { parts.append(d > 0 ? "resting heart rate is \(d) bpm higher" : "resting heart rate is \(-d) bpm lower") } }
        if sleepMin > 0 { parts.append("you slept \(Self.hm(sleepMin)) of \(Self.hm(needMin))") }
        guard !parts.isEmpty else { return "Wear your Apple Watch to bed and Keel will explain your recovery here each morning." }
        return "Your " + parts.joined(separator: ", ") + ". " + call.title
    }

    static func hm(_ m: Double) -> String { let i = Int(m.rounded()); return "\(i / 60)h \(String(format: "%02d", i % 60))m" }
}

struct BodyHero: View {
    let day: BodyDay?
    let days: [BodyDay]
    let isToday: Bool
    var steps: Int = 0
    @AppStorage("body.heroStyle") private var styleRaw = BodyHeroStyle.rings.rawValue

    var body: some View {
        let s = BodySnapshot(day: day, days: days, steps: steps)
        let style = BodyHeroStyle(rawValue: styleRaw) ?? .rings
        VStack(spacing: 12) {
            Picker("Style", selection: $styleRaw) { ForEach(BodyHeroStyle.allCases) { Text($0.label).tag($0.rawValue) } }
                .pickerStyle(.segmented)
            switch style {
            case .rings: RingsHero(s: s)
            case .story: StoryHero(s: s)
            case .control: ControlHero(s: s)
            }
        }
    }
}

// MARK: A · Rings

private struct RingsHero: View {
    let s: BodySnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ring("Recovery", s.tide, 100, BodyStyle.tide, "tide")
                ring("Effort", s.swell, 100, BodyStyle.swell, "swell")
                ring("Sleep", s.anchor, 100, BodyStyle.anchor, "anchor")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("TODAY").font(.caption.weight(.bold)).foregroundStyle(s.call.color)
                Text(s.call.title).font(.title3.weight(.bold)).foregroundStyle(.white)
                Text(s.call.detail + " · " + "Effort \(s.swell) so far").font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [s.call.color.opacity(0.35), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 18))
            VStack(spacing: 8) {
                vital("Heart rate variability", s.hrv.map { "\(Int($0)) ms" }, delta(s.hrv, s.hrvNormal, "ms", higherBetter: true))
                vital("Resting heart rate", s.rhr.map { "\(Int($0)) bpm" }, delta(s.rhr, s.rhrNormal, "bpm", higherBetter: false))
                vital("Sleep", s.sleepMin > 0 ? BodySnapshot.hm(s.sleepMin) : nil, "need \(BodySnapshot.hm(s.needMin))")
                vital("Breathing", s.resp.map { String(format: "%.1f /min", $0) }, nil)
                vital("Blood oxygen", s.spo2.map { "\(Int($0 * (($0 <= 1) ? 100 : 1)))%" }, nil)
                vital("Steps", s.steps > 0 ? s.steps.formatted() : nil, nil)
            }
        }
        .padding(18)
        .background(LinearGradient(colors: [Color(white: 0.06), Color(white: 0.11)], startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 26, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private func ring(_ title: String, _ v: Int?, _ max: Int, _ c: Color, _ guide: String) -> some View {
        NavigationLink { if let g = MetricGuides.guide(guide) { MetricGuideView(guide: g) } } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle().stroke(c.opacity(0.18), lineWidth: 10)
                    Circle().trim(from: 0, to: CGFloat(v ?? 0) / CGFloat(max)).stroke(c.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text(v.map(String.init) ?? "–").font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                }
                .frame(width: 88, height: 88)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func vital(_ name: String, _ value: String?, _ note: String?) -> some View {
        HStack {
            Text(name).font(.subheadline).foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text(value ?? "–").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.white)
            if let note { Text(note).font(.caption).foregroundStyle(.white.opacity(0.55)) }
        }
    }
}

private func delta(_ v: Double?, _ n: Double?, _ unit: String, higherBetter: Bool) -> String? {
    guard let v, let n else { return nil }
    let d = Int((v - n).rounded())
    guard d != 0 else { return "at normal" }
    return (d > 0 ? "↑\(d)" : "↓\(-d)") + " vs normal"
}

// MARK: B · Story

private struct StoryHero: View {
    let s: BodySnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recovery").font(.subheadline.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft)
                Text(s.tide.map { "\($0)%" } ?? "–").font(.system(size: 56, weight: .heavy, design: .rounded)).foregroundStyle(BodyStyle.tide)
                Text(s.story).font(.body).foregroundStyle(DS.Palette.ink)
                HStack(spacing: 6) {
                    if let d = delta(s.hrv, s.hrvNormal, "ms", higherBetter: true) { tag("HRV " + d, .green) }
                    if s.sleepMin > 0 { tag(s.sleepMin >= s.needMin - 20 ? "Sleep on target" : "Short on sleep", s.sleepMin >= s.needMin - 20 ? .indigo : .orange) }
                    tag(s.swell < s.target.lowerBound ? "Room for effort" : s.swell > s.target.upperBound ? "Effort high" : "Effort on target", BodyStyle.swell)
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [BodyStyle.tide.opacity(0.14), DS.Palette.elevated], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 24, style: .continuous))
            card {
                HStack { Text("Effort").font(.headline); Spacer(); Text("\(s.swell) of \(s.target.lowerBound)–\(s.target.upperBound)").foregroundStyle(DS.Palette.inkSoft) }
                ProgressView(value: Double(min(s.swell, s.target.upperBound)), total: Double(max(s.target.upperBound, 1))).tint(BodyStyle.swell)
                Text(s.swell < s.target.lowerBound ? "About \(max(10, (s.target.lowerBound - s.swell) / 2)) more minutes of brisk activity gets you there." : "You've done enough today. Recover well.")
                    .font(.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            card {
                HStack { Text("Sleep").font(.headline); Spacer(); Text(s.sleepMin > 0 ? "\(BodySnapshot.hm(s.sleepMin)) · \(s.anchor ?? 0)" : "–").foregroundStyle(DS.Palette.inkSoft) }
                if let d = s.day, d.deep + d.rem + d.core > 0 {
                    GeometryReader { g in
                        let total = max(1, d.deep + d.rem + d.core + d.awake)
                        HStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.25, green: 0.25, blue: 0.7)).frame(width: g.size.width * d.deep / total)
                            RoundedRectangle(cornerRadius: 3).fill(BodyStyle.anchor.opacity(0.7)).frame(width: g.size.width * d.core / total)
                            RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.55, green: 0.7, blue: 1)).frame(width: g.size.width * d.rem / total)
                            RoundedRectangle(cornerRadius: 3).fill(Color.orange.opacity(0.6)).frame(width: max(0, g.size.width * d.awake / total - 6))
                        }
                    }
                    .frame(height: 12)
                    Text("Deep \(BodySnapshot.hm(d.deep)) · Core \(BodySnapshot.hm(d.core)) · REM \(BodySnapshot.hm(d.rem))").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                let tn = BodyMath.tonight(s.history, base: BodyPrefs.sleepNeed)
                Text("Tonight: lights out by \(tn.bedtime.formatted(date: .omitted, time: .shortened)) for \(BodySnapshot.hm(tn.need * 60)).").font(.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            if let insight = insight {
                card { Label(insight, systemImage: "lightbulb.fill").font(.subheadline).foregroundStyle(DS.Palette.ink) }
            }
        }
    }

    /// A pattern from your own last two weeks.
    private var insight: String? {
        let h = s.history.filter { $0.tide != nil }
        guard h.count >= 6 else { return nil }
        let good = h.filter { $0.asleep >= s.needMin - 20 }.compactMap(\.tide), short = h.filter { $0.asleep < s.needMin - 20 }.compactMap(\.tide)
        guard !good.isEmpty, !short.isEmpty else { return nil }
        let diff = Int((Double(good.reduce(0, +)) / Double(good.count) - Double(short.reduce(0, +)) / Double(short.count)).rounded())
        return diff > 2 ? "When you sleep your full need, your recovery averages \(diff) points higher the next morning." : nil
    }

    private func tag(_ t: String, _ c: Color) -> some View {
        Text(t).font(.caption.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 4).foregroundStyle(c).background(c.opacity(0.12), in: Capsule())
    }
    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) { c() }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.elevated, in: .rect(cornerRadius: 20, style: .continuous))
    }
}

// MARK: C · Control room

private struct ControlHero: View {
    let s: BodySnapshot
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                score("Recovery", s.tide.map { "\($0)" }, BodyStyle.tide)
                score("Effort", "\(s.swell)", BodyStyle.swell)
                score("Sleep", s.anchor.map { "\($0)" }, BodyStyle.anchor)
            }
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 18))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                tile("HRV", s.hrv.map { "\(Int($0))" }, "ms", \.hrv, .green, "h.hrv")
                tile("Resting HR", s.rhr.map { "\(Int($0))" }, "bpm", \.rhr, .pink, "h.rhr")
                tile("Sleep", s.sleepMin > 0 ? BodySnapshot.hm(s.sleepMin) : nil, "", \.sleepHours, BodyStyle.anchor, "anchor")
                tile("Breathing", s.resp.map { String(format: "%.1f", $0) }, "/min", \.resp, .teal, "h.resp")
                tile("Cardio fitness", s.vo2.map { String(format: "%.1f", $0) }, "VO₂", \.vo2, .orange, "h.vo2")
                tile("Steps", s.steps > 0 ? s.steps.formatted() : nil, "today", nil, .yellow, "activity")
            }
            Text(s.call.title + " " + s.call.detail).font(.caption).foregroundStyle(.white.opacity(0.7)).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color(white: 0.07), in: .rect(cornerRadius: 26, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private func score(_ t: String, _ v: String?, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(v ?? "–").font(.system(size: 28, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(c)
            Text(t).font(.caption).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private func tile(_ name: String, _ value: String?, _ unit: String, _ kp: KeyPath<BodyDay, Double?>?, _ c: Color, _ guide: String) -> some View {
        NavigationLink { if let g = MetricGuides.guide(guide) { MetricGuideView(guide: g) } } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.caption).foregroundStyle(.white.opacity(0.6))
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value ?? "–").font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(.white)
                    Text(unit).font(.caption2).foregroundStyle(.white.opacity(0.5))
                }
                if let kp {
                    let pts = s.history.compactMap { d in d[keyPath: kp].map { (d.day, $0) } }
                    if pts.count >= 2 {
                        Chart(pts, id: \.0) { p in LineMark(x: .value("Day", p.0), y: .value(name, p.1)).foregroundStyle(c).interpolationMethod(.catmullRom) }
                            .chartXAxis(.hidden).chartYAxis(.hidden).chartYScale(domain: .automatic(includesZero: false)).frame(height: 28)
                    } else { Spacer(minLength: 28) }
                } else { Spacer(minLength: 28) }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

extension BodyDay {
    /// Hours asleep (for charts), nil when no sleep was recorded.
    var sleepHours: Double? { asleep >= 60 ? asleep / 60 : nil }
}
