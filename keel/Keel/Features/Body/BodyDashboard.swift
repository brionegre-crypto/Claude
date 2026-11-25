import SwiftUI
import Charts

// MARK: - Body dashboard: pages, a day picker, metric tiles with your normal range, and a detail screen for every number

/// The pages along the top of Body.
enum BodyPage: String, CaseIterable, Identifiable {
    case today = "Today", food = "Food", sleep = "Sleep", effort = "Training", health = "Healthspan", habits = "Journal"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .today: "sun.horizon.fill"
        case .food: "fork.knife"
        case .sleep: "moon.zzz.fill"
        case .effort: "wind"
        case .health: "heart.text.square.fill"
        case .habits: "checklist"
        }
    }
}

/// A pill bar that stays pinned while you scroll, with a sliding highlight.
struct BodyPageBar: View {
    @Binding var page: BodyPage
    @Namespace private var pill

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(BodyPage.visible) { p in
                    Button {
                        withAnimation(.smooth(duration: 0.28)) { page = p }
                        Haptics.tap()
                    } label: {
                        Label(p.rawValue, systemImage: p.icon)
                            .font(DS.Font.caption.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .foregroundStyle(page == p ? Color.white : DS.Palette.ink)
                            .background {
                                if page == p {
                                    Capsule().fill(LinearGradient(colors: [BodyStyle.tide.mix(with: .white, by: 0.15), BodyStyle.anchor], startPoint: .leading, endPoint: .trailing))
                                        .shadow(color: BodyStyle.tide.opacity(0.4), radius: 6, y: 2)
                                        .matchedGeometryEffect(id: "pill", in: pill)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(page == p ? .isSelected : [])
                }
            }
            .padding(4)
        }
        // The capsule goes around the scroller, not the pills: five pages are wider than the screen, so a capsule
        // on the pills ran off the right edge and looked cut off.
        .background(DS.Palette.elevated, in: Capsule())
        .clipShape(Capsule())
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.canvas.opacity(0.94))
    }
}

/// The last two weeks as tappable days, each with a dot coloured by that morning's Tide.
struct BodyDayStrip: View {
    let days: [BodyDay]
    @Binding var selected: Date?

    var body: some View {
        let cal = Calendar.current
        let shown = Array(days.suffix(14))
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(shown) { d in
                        let isSel = selected.map { cal.isDate($0, inSameDayAs: d.day) } ?? cal.isDateInToday(d.day)
                        Button {
                            withAnimation(.smooth(duration: 0.25)) { selected = cal.isDateInToday(d.day) ? nil : d.day }
                            Haptics.tap()
                        } label: {
                            VStack(spacing: 4) {
                                Text(d.day.formatted(.dateTime.weekday(.abbreviated))).font(.caption2.weight(.semibold))
                                Text(d.day.formatted(.dateTime.day())).font(.callout.weight(.bold)).monospacedDigit()
                                Circle().fill(BodyDash.tideColor(d.tide)).frame(width: 6, height: 6)
                            }
                            .frame(width: 42).padding(.vertical, 8)
                            .foregroundStyle(isSel ? Color.white : DS.Palette.ink)
                            .background(isSel ? AnyShapeStyle(BodyStyle.tide.gradient) : AnyShapeStyle(DS.Palette.elevated),
                                        in: .rect(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .id(d.day)
                        .accessibilityLabel("\(d.day.formatted(date: .complete, time: .omitted)), Tide \(d.tide.map(String.init) ?? "no data")")
                    }
                }
            }
            .onAppear { if let last = shown.last { proxy.scrollTo(last.day, anchor: .trailing) } }
        }
    }
}

struct BodyPoint: Identifiable, Hashable { let day: Date; let v: Double; var id: Date { day } }
struct BodyNight: Identifiable, Hashable { let day: Date; let bed: Double; let wake: Double; var id: Date { day } }

enum BodyDash {
    static func tideColor(_ t: Int?) -> Color {
        guard let t else { return .gray.opacity(0.35) }
        return t >= 67 ? DS.Palette.calm : t >= 34 ? .yellow : .orange
    }

    /// Your usual range for a metric: the 30 days before `day`, average ± one standard deviation.
    static func baseline(_ kind: BodyMetric, days: [BodyDay], before day: Date) -> (mean: Double, range: ClosedRange<Double>)? {
        let v = days.filter { $0.day < Calendar.current.startOfDay(for: day) }.suffix(30).compactMap { kind.value($0) }
        guard v.count >= 5 else { return nil }
        let m = v.reduce(0, +) / Double(v.count)
        let sd = sqrt(v.reduce(0) { $0 + pow($1 - m, 2) } / Double(v.count - 1))
        return (m, (m - sd)...(m + sd))
    }

    /// Average of a metric over `count` days ending `endingDaysAgo` days ago.
    static func average(_ kind: BodyMetric, days: [BodyDay], count: Int, endingDaysAgo: Int = 0) -> Double? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: -endingDaysAgo, to: today),
              let start = cal.date(byAdding: .day, value: -(count - 1), to: end) else { return nil }
        let v = days.filter { $0.day >= start && $0.day <= end }.compactMap { kind.value($0) }
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }
}

/// Every number Body can chart.
enum BodyMetric: String, CaseIterable, Identifiable, Hashable {
    case tide, swell, anchor, hrv, rhr, sleep, efficiency, deep, rem, resp, spo2, temp, vo2
    var id: String { rawValue }

    static let tiles: [BodyMetric] = [.hrv, .rhr, .sleep, .efficiency, .deep, .rem, .resp, .spo2, .temp, .vo2]

    var name: String {
        switch self {
        case .tide: "Tide · recovery"
        case .swell: "Swell · effort"
        case .anchor: "Anchor · sleep"
        case .hrv: "Heart rate variability"
        case .rhr: "Resting heart rate"
        case .sleep: "Time asleep"
        case .efficiency: "Sleep efficiency"
        case .deep: "Deep sleep"
        case .rem: "REM sleep"
        case .resp: "Breathing rate"
        case .spo2: "Blood oxygen"
        case .temp: "Wrist temperature"
        case .vo2: "Cardio fitness"
        }
    }
    var short: String {
        switch self {
        case .hrv: "HRV"
        case .rhr: "Resting HR"
        case .sleep: "Asleep"
        case .efficiency: "Efficiency"
        case .deep: "Deep"
        case .rem: "REM"
        case .resp: "Breathing"
        case .spo2: "Oxygen"
        case .temp: "Wrist temp"
        case .vo2: "VO₂ max"
        default: name
        }
    }
    var icon: String {
        switch self {
        case .tide: "water.waves"
        case .swell: "wind"
        case .anchor: "moon.zzz.fill"
        case .hrv: "waveform.path.ecg"
        case .rhr: "heart.fill"
        case .sleep: "bed.double.fill"
        case .efficiency: "gauge.with.dots.needle.67percent"
        case .deep: "moon.haze.fill"
        case .rem: "sparkles"
        case .resp: "lungs.fill"
        case .spo2: "drop.fill"
        case .temp: "thermometer.medium"
        case .vo2: "figure.run"
        }
    }
    var color: Color {
        switch self {
        case .tide: BodyStyle.tide
        case .swell: BodyStyle.swell
        case .anchor, .sleep, .efficiency, .deep, .rem: BodyStyle.anchor
        case .hrv, .rhr: .pink
        case .resp: .teal
        case .spo2: .red
        case .temp: .orange
        case .vo2: .green
        }
    }
    /// nil: neither direction is better (a change either way is worth noticing).
    var higherIsBetter: Bool? {
        switch self {
        case .rhr: false
        case .resp, .temp: nil
        default: true
        }
    }

    func value(_ d: BodyDay) -> Double? {
        switch self {
        case .tide: d.tide.map(Double.init)
        case .swell: d.hasSleep || d.swell > 0 ? Double(d.swell) : nil
        case .anchor: d.anchor.map(Double.init)
        case .hrv: d.hrv
        case .rhr: d.rhr
        case .sleep: d.hasSleep ? d.asleep / 60 : nil
        case .efficiency: d.hasSleep && d.inBed > 0 ? min(100, d.asleep / d.inBed * 100) : nil
        case .deep: d.hasSleep && d.deep > 0 ? d.deep : nil
        case .rem: d.hasSleep && d.rem > 0 ? d.rem : nil
        case .resp: d.resp
        case .spo2: d.spo2
        case .temp: d.temp
        case .vo2: d.vo2
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .tide: "\(Int(v.rounded()))%"
        case .swell, .anchor: "\(Int(v.rounded()))"
        case .hrv: "\(Int(v.rounded())) ms"
        case .rhr: "\(Int(v.rounded())) bpm"
        case .sleep: { let m = Int((v * 60).rounded()); return "\(m / 60)h \(String(format: "%02d", m % 60))m" }()
        case .efficiency, .spo2: "\(Int(v.rounded()))%"
        case .deep, .rem: "\(Int(v.rounded())) min"
        case .resp: String(format: "%.1f /min", v)
        case .temp: String(format: "%+.1f°C", v)
        case .vo2: String(format: "%.1f", v)
        }
    }

    /// How big a change is worth a word, in this metric's units.
    var noticeable: Double {
        switch self {
        case .tide, .swell, .anchor: 5
        case .hrv: 3
        case .rhr: 1.5
        case .sleep: 0.25
        case .efficiency: 2
        case .deep, .rem: 8
        case .resp: 0.5
        case .spo2: 1
        case .temp: 0.2
        case .vo2: 0.5
        }
    }

    var about: String {
        switch self {
        case .tide: "How ready your body is today, from last night's heart rate variability and resting heart rate compared with your own normal, plus how well you slept."
        case .swell: "How hard your heart worked today, counting time in each heart-rate zone. Harder zones count more, and each point is harder to earn than the last."
        case .anchor: "How well you slept: how much compared with what you needed, how much of your time in bed you were asleep, deep and REM sleep, and how regular your bedtime was."
        case .hrv: "The tiny variation between heartbeats while you sleep. Higher than your normal usually means you've recovered well; a drop can mean stress, a hard day, alcohol or getting ill."
        case .rhr: "Your heart rate at rest. Lower than your normal is a good sign. A rise of a few beats can mean you're tired, stressed, dehydrated or coming down with something."
        case .sleep: "Time actually asleep, not just in bed. Most adults need 7–9 hours; Keel works out what you need each night."
        case .efficiency: "How much of your time in bed you were asleep. Above 85% is good."
        case .deep: "Deep sleep repairs your body and is when most physical recovery happens. It's mostly early in the night."
        case .rem: "REM sleep helps memory, learning and mood. It's mostly in the second half of the night, so short nights cut it first."
        case .resp: "Breaths per minute while asleep. It stays very steady; a rise compared with your normal can be an early sign of illness."
        case .spo2: "How much oxygen your blood carries overnight. Usually 95–100%. Ask a doctor if it's often below 90%."
        case .temp: "Your sleeping wrist temperature compared with your own baseline. A rise can come before you feel ill, and it follows the menstrual cycle."
        case .vo2: "An estimate of your cardio fitness from walks and runs with your Apple Watch. It's one of the strongest predictors of long-term health."
        }
    }
    var helps: String {
        switch self {
        case .tide, .hrv, .rhr: "What helps: a regular bedtime, no alcohol late, easy days after hard ones, and enough water."
        case .swell, .vo2: "What helps: some time in zones 2–3 most days, and harder efforts only when your Tide is up."
        case .anchor, .sleep, .efficiency, .deep, .rem: "What helps: the same bedtime every night, a cool dark room, no caffeine after early afternoon, and screens off before bed."
        case .resp, .spo2, .temp: "Watch for a change from your normal several nights in a row, rather than a single night."
        }
    }
}

/// A small tile: today's value, how it compares with your normal, and the last two weeks as a line.
struct BodyMetricTile: View {
    let metric: BodyMetric
    let day: BodyDay?
    let days: [BodyDay]

    var body: some View {
        let v = day.flatMap { metric.value($0) }
        let base = BodyDash.baseline(metric, days: days, before: day?.day ?? Date())
        let spark = days.suffix(14).compactMap { d in metric.value(d).map { BodyPoint(day: d.day, v: $0) } }
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: metric.icon).font(.caption2).foregroundStyle(metric.color)
                Text(metric.short).font(.caption2.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(v.map(metric.format) ?? "–").font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            BodyDeltaBadge(metric: metric, value: v, base: base)
            if spark.count >= 3 {
                Chart(spark) { p in
                    AreaMark(x: .value("Day", p.day), y: .value("Value", p.v))
                        .foregroundStyle(LinearGradient(colors: [metric.color.opacity(0.35), metric.color.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Day", p.day), y: .value("Value", p.v))
                        .foregroundStyle(metric.color.gradient).interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 26)
                .accessibilityHidden(true)
            } else {
                Color.clear.frame(height: 26)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { PremiumSurface(tint: metric.color, radius: 18) }
        .accessibilityElement(children: .combine)
    }
}

/// "▲ 6 ms above normal" in green, orange or grey.
struct BodyDeltaBadge: View {
    let metric: BodyMetric
    let value: Double?
    let base: (mean: Double, range: ClosedRange<Double>)?

    var body: some View {
        if let value, let base {
            let diff = value - base.mean
            let within = base.range.contains(value) || abs(diff) < metric.noticeable
            let good: Bool? = within ? nil : metric.higherIsBetter.map { $0 == (diff > 0) }
            let color: Color = good == nil ? (within ? DS.Palette.inkSoft : .orange) : (good! ? DS.Palette.calm : .orange)
            HStack(spacing: 3) {
                if !within { Image(systemName: diff > 0 ? "arrow.up" : "arrow.down").font(.system(size: 9, weight: .bold)) }
                Text(within ? "Normal for you" : "\(metric.format(abs(diff)).replacingOccurrences(of: "+", with: "")) \(diff > 0 ? "above" : "below")")
                    .font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(color)
        } else {
            Text(value == nil ? "No data" : "Learning your normal").font(.caption2).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
        }
    }
}

/// The big three on a sky-coloured card. Tap a ring for its full history.
struct BodyHeroCard: View {
    let day: BodyDay?
    let days: [BodyDay]
    let isToday: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isToday ? "Today" : (day?.day ?? Date()).formatted(.dateTime.weekday(.wide).month().day()))
                        .font(DS.Font.title).foregroundStyle(.white)
                    Text(BodyEngine.advice(day?.tide)).font(DS.Font.caption).foregroundStyle(.white.opacity(0.88)).lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 0) {
                ring(.tide, day?.tide, suffix: "%")
                ring(.swell, day?.swell, suffix: "")
                ring(.anchor, day?.anchor, suffix: "")
            }
        }
        .padding(DS.Space.m)
        .background {
            LinearGradient(colors: [BodyStyle.anchor.opacity(0.95), BodyStyle.tide.opacity(0.9), BodyDash.tideColor(day?.tide).opacity(0.75)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .overlay {                                              // a soft sheen from the top, like light on water
            LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center).allowsHitTesting(false)
        }
        .clipShape(.rect(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 0.75) }
        .shadow(color: BodyStyle.tide.opacity(0.35), radius: 20, y: 10)
    }

    private func ring(_ m: BodyMetric, _ v: Int?, suffix: String) -> some View {
        NavigationLink { LazyView(BodyMetricDetailView(metric: m)) } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle().stroke(.white.opacity(0.22), lineWidth: 9)
                    Circle().trim(from: 0, to: CGFloat(min(1, Double(v ?? 0) / 100)))
                        .stroke(AngularGradient(colors: [.white.opacity(0.75), .white], center: .center),
                                style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: .white.opacity(0.55), radius: 6)
                        .animation(.smooth(duration: 0.6), value: v)
                    Text(v.map { "\($0)\(suffix)" } ?? "–").font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white).contentTransition(.numericText())
                }
                .frame(width: 84, height: 84)
                HStack(spacing: 3) {
                    Text(m == .tide ? "Tide" : m == .swell ? "Swell" : "Anchor").font(DS.Font.caption.weight(.semibold))
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(.white.opacity(0.92))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(m.name): \(v.map { "\($0)" } ?? "no data"). Opens its history.")
    }
}

/// This week against last week, one line per score.
struct BodyWeekCard: View {
    let days: [BodyDay]
    var body: some View {
        let rows: [BodyMetric] = [.tide, .anchor, .swell, .sleep, .hrv, .rhr]
        VStack(alignment: .leading, spacing: 10) {
            Label("This week vs last week", systemImage: "calendar").font(DS.Font.headline)
            ForEach(rows) { m in
                let now = BodyDash.average(m, days: days, count: 7)
                let before = BodyDash.average(m, days: days, count: 7, endingDaysAgo: 7)
                HStack {
                    Image(systemName: m.icon).foregroundStyle(m.color).frame(width: 20)
                    Text(m.short == m.name ? m.name.components(separatedBy: " · ").first ?? m.name : m.short).font(DS.Font.caption)
                    Spacer()
                    Text(now.map(m.format) ?? "–").font(DS.Font.caption.weight(.semibold)).monospacedDigit()
                    if let now, let before, abs(now - before) >= m.noticeable {
                        let up = now > before
                        let good = m.higherIsBetter.map { $0 == up }
                        Image(systemName: up ? "arrow.up.right" : "arrow.down.right").font(.caption2.weight(.bold))
                            .foregroundStyle(good == nil ? DS.Palette.inkSoft : good! ? DS.Palette.calm : .orange)
                    } else {
                        Image(systemName: "equal").font(.caption2.weight(.bold)).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
            }
            // The report in words: your biggest win and one thing to work on next week.
            let r = report(rows)
            if let win = r.win { Label(win, systemImage: "hands.clap.fill").font(DS.Font.caption).foregroundStyle(DS.Palette.calm) }
            if let focus = r.focus { Label(focus, systemImage: "scope").font(DS.Font.caption).foregroundStyle(.orange) }
            ShareLink(item: r.text) { Label("Share my week", systemImage: "square.and.arrow.up").font(DS.Font.caption.weight(.semibold)) }
        }
        .bodyCard()
    }

    private func report(_ rows: [BodyMetric]) -> (win: String?, focus: String?, text: String) {
        var best: (String, Double)?, worst: (String, Double)?
        var lines = ["My week in Keel"]
        for m in rows {
            guard let now = BodyDash.average(m, days: days, count: 7) else { continue }
            let name = m.short == m.name ? (m.name.components(separatedBy: " · ").first ?? m.name) : m.short
            lines.append("\(name): \(m.format(now))")
            guard let before = BodyDash.average(m, days: days, count: 7, endingDaysAgo: 7), before != 0,
                  abs(now - before) >= m.noticeable, let higher = m.higherIsBetter else { continue }
            let change = (now - before) / abs(before) * (higher ? 1 : -1)      // + is better
            if change > (best?.1 ?? 0) { best = ("Biggest win: \(name) \(m.format(before)) → \(m.format(now))", change) }
            if change < (worst?.1 ?? 0) { worst = ("Work on next week: \(name) (\(m.format(before)) → \(m.format(now)))", change) }
        }
        if let b = best { lines.append(b.0) }
        if let w = worst { lines.append(w.0) }
        return (best?.0, worst?.0, lines.joined(separator: "\n"))
    }
}

/// When you fell asleep and woke up, each night for two weeks. Straighter bars mean a steadier body clock.
struct SleepScheduleCard: View {
    let days: [BodyDay]
    var body: some View {
        let nights = days.suffix(14).compactMap { d -> BodyNight? in
            guard let b = d.bedtime, let w = d.wake else { return nil }
            return BodyNight(day: d.day, bed: Self.hoursFrom6pm(b), wake: Self.hoursFrom6pm(w))
        }
        VStack(alignment: .leading, spacing: 10) {
            Label("Sleep schedule", systemImage: "clock.arrow.circlepath").font(DS.Font.headline).foregroundStyle(BodyStyle.anchor)
            if nights.count < 3 {
                Text("Shows once you have a few nights of sleep in Apple Health.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            } else {
                Chart(nights) { n in
                    BarMark(x: .value("Night", n.day, unit: .day), yStart: .value("Asleep", n.bed), yEnd: .value("Awake", n.wake), width: .ratio(0.55))
                        .foregroundStyle(BodyStyle.anchor.gradient).cornerRadius(4)
                }
                .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                .chartYAxis {
                    AxisMarks(values: .stride(by: 2)) { v in
                        AxisGridLine()
                        AxisValueLabel { if let h = v.as(Double.self) { Text(Self.clock(h)) } }
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 3)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                .frame(height: 170)
                let beds = nights.map(\.bed)
                let mean = beds.reduce(0, +) / Double(beds.count)
                let spread = sqrt(beds.reduce(0) { $0 + pow($1 - mean, 2) } / Double(beds.count)) * 60
                Text(spread < 30 ? "Very regular: your bedtime varies by about \(Int(spread)) minutes. Keep it up."
                     : spread < 60 ? "Fairly regular: bedtime varies by about \(Int(spread)) minutes. Within 30 minutes is ideal."
                     : "Irregular: bedtime varies by about \(Int(spread)) minutes. A steadier bedtime is one of the quickest ways to raise your Anchor.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
        }
        .bodyCard()
    }

    static func hoursFrom6pm(_ d: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        let h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        return h >= 18 ? h - 18 : h + 6
    }
    static func clock(_ fromSix: Double) -> String {
        let h = (Int(fromSix.rounded()) + 18) % 24
        return h == 0 ? "12a" : h == 12 ? "12p" : h > 12 ? "\(h - 12)p" : "\(h)a"
    }
}

/// Full history of one number: range picker, your normal band, average, best and lowest, and what it means.
struct BodyMetricDetailView: View {
    let metric: BodyMetric
    @State private var engine = BodyEngine.shared
    @State private var span = 30
    @State private var picked: Date?

    var body: some View {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -(span - 1), to: cal.startOfDay(for: Date())) ?? Date()
        let points = engine.days.filter { $0.day >= start }.compactMap { d in metric.value(d).map { BodyPoint(day: d.day, v: $0) } }
        let base = BodyDash.baseline(metric, days: engine.days, before: Date().addingTimeInterval(86_400))
        let vals = points.map(\.v)
        let avg = vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
        let shown = picked.flatMap { p in points.first { cal.isDate($0.day, inSameDayAs: p) } } ?? points.last

        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(shown.map { $0.day.formatted(.dateTime.weekday(.wide).month().day()) } ?? "No data yet")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    Text(shown.map { metric.format($0.v) } ?? "–").font(DS.Font.hero).monospacedDigit().contentTransition(.numericText())
                    BodyDeltaBadge(metric: metric, value: shown?.v, base: base)
                }
                Picker("Range", selection: $span.animation(.smooth)) {
                    Text("7 days").tag(7); Text("30 days").tag(30); Text("90 days").tag(90)
                }
                .pickerStyle(.segmented)

                if points.count >= 2 {
                    Chart {
                        if let base {
                            ForEach(points, id: \.day) { p in
                                AreaMark(x: .value("Day", p.day, unit: .day),
                                         yStart: .value("Low", base.range.lowerBound), yEnd: .value("High", base.range.upperBound))
                                    .foregroundStyle(metric.color.opacity(0.12))
                            }
                        }
                        ForEach(points, id: \.day) { p in
                            LineMark(x: .value("Day", p.day, unit: .day), y: .value(metric.short, p.v))
                                .foregroundStyle(metric.color.gradient).interpolationMethod(.catmullRom)
                            PointMark(x: .value("Day", p.day, unit: .day), y: .value(metric.short, p.v))
                                .foregroundStyle(metric.color).symbolSize(span > 30 ? 8 : 22)
                        }
                        if let s = shown {
                            RuleMark(x: .value("Picked", s.day, unit: .day)).foregroundStyle(DS.Palette.inkSoft.opacity(0.4))
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: metric == .swell))
                    .chartXSelection(value: $picked)
                    .frame(height: 220)
                    if base != nil {
                        Label("The shaded band is your normal range (your last 30 days).", systemImage: "square.fill")
                            .font(.caption2).foregroundStyle(metric.color.opacity(0.7))
                    }
                } else {
                    ContentUnavailableView("Not enough data yet", systemImage: metric.icon,
                                           description: Text("Wear your Apple Watch, day and night, and this fills in over the next few days."))
                }

                HStack(spacing: 10) {
                    stat("Average", avg)
                    stat(metric.higherIsBetter == false ? "Lowest (best)" : "Best", metric.higherIsBetter == false ? vals.min() : vals.max())
                    stat(metric.higherIsBetter == false ? "Highest" : "Lowest", metric.higherIsBetter == false ? vals.max() : vals.min())
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("What it is", systemImage: "info.circle").font(DS.Font.headline)
                    Text(metric.about).font(DS.Font.caption)
                    Text(metric.helps).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    if metric == .tide, let notes = engine.today?.tideNotes, !notes.isEmpty {
                        Divider()
                        Text("Today").font(DS.Font.caption.weight(.semibold))
                        ForEach(notes, id: \.self) { Text("• \($0)").font(DS.Font.caption) }
                    }
                }
                .bodyCard()
                Text("For everyday wellbeing, not medical advice.").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
            }
            .padding(DS.Space.m)
        }
        .premiumBackground(BodyStyle.tide)
        .navigationTitle(metric.name)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: picked)
    }

    private func stat(_ title: String, _ v: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
            Text(v.map(metric.format) ?? "–").font(DS.Font.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { PremiumSurface(radius: 16) }
    }
}

/// Grid of tiles; each opens its full history.
struct BodyMetricsGrid: View {
    let day: BodyDay?
    let days: [BodyDay]
    var metrics: [BodyMetric] = BodyMetric.tiles
    var title = "Key metrics"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(DS.Font.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(metrics) { m in
                    NavigationLink { LazyView(BodyMetricDetailView(metric: m)) } label: { BodyMetricTile(metric: m, day: day, days: days) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            NavigationLink { LazyView(BodyMetricDetailView(metric: m)) } label: { Label("Show history", systemImage: "chart.xyaxis.line") }
                        } preview: {
                            BodyMetricTile(metric: m, day: day, days: days).frame(width: 220)
                        }
                }
            }
        }
    }
}

/// Something to point at when Health isn't connected on a page that needs it.
struct BodyNeedsHealthCard: View {
    let what: String
    let connect: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Connect Apple Health", systemImage: "heart.fill").font(DS.Font.headline).foregroundStyle(.pink)
            Text("Keel reads Apple Health to show \(what). It's all worked out privately on this iPhone.").font(DS.Font.caption)
            Button(action: connect) { Label("Connect", systemImage: "heart.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).tint(.pink)
        }
        .bodyCard()
    }
}
