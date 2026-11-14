import SwiftUI
import SwiftData
import EventKit

// MARK: - Horizon: Keel's signature look
//
// Every main screen opens on a living horizon: the sky follows the real time of day, a sun (or moon) arc shows how
// much daylight is left, and calm water sits below. What needs you is above the waterline; what can wait sits below it.

enum HorizonSky {
    /// Sky colors for this moment: dawn, day, golden hour, dusk, night.
    static func colors(at d: Date = Date()) -> [Color] {
        let h = Double(Calendar.current.component(.hour, from: d)) + Double(Calendar.current.component(.minute, from: d)) / 60
        switch h {
        case 5..<7.5: return [Color(red: 0.36, green: 0.42, blue: 0.70), Color(red: 0.96, green: 0.66, blue: 0.56), Color(red: 1.0, green: 0.85, blue: 0.66)]
        case 7.5..<16: return [Color(red: 0.30, green: 0.58, blue: 0.93), Color(red: 0.55, green: 0.76, blue: 0.97), Color(red: 0.86, green: 0.93, blue: 1.0)]
        case 16..<18.5: return [Color(red: 0.34, green: 0.46, blue: 0.86), Color(red: 0.98, green: 0.62, blue: 0.40), Color(red: 1.0, green: 0.82, blue: 0.55)]
        case 18.5..<20.5: return [Color(red: 0.16, green: 0.18, blue: 0.42), Color(red: 0.55, green: 0.32, blue: 0.56), Color(red: 0.95, green: 0.52, blue: 0.45)]
        default: return [Color(red: 0.04, green: 0.06, blue: 0.16), Color(red: 0.09, green: 0.12, blue: 0.28), Color(red: 0.17, green: 0.20, blue: 0.40)]
        }
    }
    static func isNight(_ d: Date = Date()) -> Bool { let h = Calendar.current.component(.hour, from: d); return h >= 21 || h < 5 }

    /// 0 at 6 AM, 1 at 9 PM: where the sun is on its arc. Nil at night.
    static func dayFraction(_ d: Date = Date()) -> Double? {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        let m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        let f = (m - 360) / (1_260 - 360)
        return (0...1).contains(f) ? f : nil
    }
    static func daylightLeft(_ d: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        let left = 1_260 - ((c.hour ?? 0) * 60 + (c.minute ?? 0))
        guard left > 0, (c.hour ?? 0) >= 5 else { return "Night · time to rest" }
        return left >= 60 ? "\(left / 60)h \(left % 60 > 0 ? "\(left % 60)m " : "")of daylight left" : "\(left) min of daylight left"
    }
}

/// A gentle moving swell for the water.
struct WaveShape: Shape {
    var phase: Double
    var amplitude: CGFloat = 4
    var animatableData: Double { get { phase } set { phase = newValue } }
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: r.midY))
        let steps = 40
        for i in 0...steps {
            let x = r.width * CGFloat(i) / CGFloat(steps)
            let y = r.midY + sin(Double(i) / Double(steps) * .pi * 4 + phase) * amplitude
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: r.width, y: r.maxY)); p.addLine(to: CGPoint(x: 0, y: r.maxY)); p.closeSubpath()
        return p
    }
}

struct HorizonHeader: View {
    let title: String
    var detail: String? = nil
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.periodic(from: .now, by: reduceMotion ? 3_600 : 60)) { ctx in
            let now = ctx.date
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: HorizonSky.colors(at: now), startPoint: .top, endPoint: .bottom)
                // Stars at night
                if HorizonSky.isNight(now) {
                    Canvas { c, size in
                        var rng = SeededRandom(seed: 7)
                        for _ in 0..<26 {
                            let pt = CGPoint(x: rng.next() * size.width, y: rng.next() * size.height * 0.6)
                            c.fill(Path(ellipseIn: CGRect(x: pt.x, y: pt.y, width: 1.6, height: 1.6)), with: .color(.white.opacity(0.7)))
                        }
                    }
                }
                sunArc(now)
                water
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(compact ? .title3.weight(.bold) : .title.weight(.bold)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
                    Text(detail ?? HorizonSky.daylightLeft(now)).font(DS.Font.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.88))
                }
                .padding(.horizontal, 18).padding(.bottom, compact ? 22 : 30)
            }
        }
        .frame(height: compact ? 104 : 150)
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(detail ?? HorizonSky.daylightLeft())")
    }

    private func sunArc(_ now: Date) -> some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let center = CGPoint(x: w * 0.5, y: h * (compact ? 0.92 : 0.86))
            let r = min(w * 0.36, h * 0.7)
            ZStack {
                Path { p in p.addArc(center: center, radius: r, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false) }
                    .stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [3, 5]))
                if let f = HorizonSky.dayFraction(now) {
                    let a = Double.pi * (1 - f)
                    Circle().fill(RadialGradient(colors: [.white, Color(red: 1, green: 0.88, blue: 0.55)], center: .center, startRadius: 1, endRadius: 12))
                        .frame(width: 18, height: 18)
                        .shadow(color: .yellow.opacity(0.7), radius: 10)
                        .position(x: center.x + r * cos(a), y: center.y - r * sin(a))
                } else {
                    Image(systemName: "moon.fill").foregroundStyle(.white.opacity(0.9)).font(.callout)
                        .position(x: w * 0.8, y: h * 0.25)
                }
            }
        }
    }

    /// The water drifts by sliding a pre-drawn wave sideways (cheap for the GPU), instead of redrawing it every frame.
    private var water: some View {
        GeometryReader { g in
            ZStack(alignment: .bottom) {
                DriftingWave(width: g.size.width, height: compact ? 26 : 34, amplitude: 3, duration: 9, reverse: false)
                    .foregroundStyle(.white.opacity(0.10))
                DriftingWave(width: g.size.width, height: compact ? 20 : 26, amplitude: 4, duration: 6, reverse: true)
                    .foregroundStyle(LinearGradient(colors: [Color(red: 0.10, green: 0.30, blue: 0.48).opacity(0.75), Color(red: 0.05, green: 0.18, blue: 0.32).opacity(0.85)], startPoint: .top, endPoint: .bottom))
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(Double(state >> 33) / Double(1 << 31))
    }
}

/// The water: drawn once and still. (A forever-running animation kept the main thread busy on every screen.)
struct DriftingWave: View {
    let width: CGFloat
    let height: CGFloat
    let amplitude: CGFloat
    let duration: Double
    let reverse: Bool
    var body: some View {
        WaveShape(phase: reverse ? .pi / 2 : 0, amplitude: amplitude)
            .frame(width: max(1, width), height: height)
            .drawingGroup()
    }
}

/// The line between what needs you now and what can wait.
struct Waterline: View {
    var label = "Below the waterline · can wait"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 4) {
            WaveLine(phase: 0).stroke(DS.Palette.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(height: 10)          // still, so long lists never redraw it
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft).textCase(.uppercase)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

struct WaveLine: Shape {
    var phase: Double
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 0...60 {
            let x = r.width * CGFloat(i) / 60
            let y = r.midY + sin(Double(i) / 60 * .pi * 8 + phase) * 3
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}

/// A soft ripple from the checkbox when something gets done.
struct RippleOnDone: ViewModifier {
    let done: Bool
    @State private var ripple = false
    func body(content: Content) -> some View {
        content
            .background {
                Circle().stroke(DS.Palette.calm.opacity(ripple ? 0 : 0.55), lineWidth: 2)
                    .scaleEffect(ripple ? 2.6 : 0.6)
                    .allowsHitTesting(false)
            }
            .onChange(of: done) { _, now in
                guard now else { return }
                ripple = false
                withAnimation(.easeOut(duration: 0.7)) { ripple = true }
            }
    }
}

// MARK: - Today: The Voyage

struct VoyageStop: Identifiable {
    enum Kind { case port, waypoint, water, anchor }
    let id: String
    let kind: Kind
    let time: Date
    let title: String
    var detail: String = ""
    var task: TaskItem?
    var gapEnd: Date?
}

/// Your day as a route: now at the bow, meetings as ports, timed tasks as waypoints, free time as open water, bedtime as the anchor.
struct VoyageView: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }, animation: .snappy) private var open: [TaskItem]
    @AppStorage("energy") private var energyRaw = 2
    @AppStorage("voyage.bedtime") private var bedtime = 22 * 60 + 30
    @State private var addingInto: VoyageStop?
    @State private var newTask = ""

    private func stops(next: TaskItem?, live: [TaskItem]) -> [VoyageStop] {
        let cal = Calendar.current, now = Date()
        let anchor = cal.date(bySettingHour: bedtime / 60, minute: bedtime % 60, second: 0, of: now) ?? now.addingTimeInterval(4 * 3600)
        var out: [VoyageStop] = []
        for e in CalendarService.shared.todaysEvents() where !e.isAllDay && e.endDate > now && e.startDate < anchor {
            out.append(VoyageStop(id: "e" + (e.calendarItemIdentifier) + "\(e.startDate.timeIntervalSince1970)", kind: .port, time: e.startDate,
                                  title: e.title ?? "Event", detail: "\(e.startDate.formatted(date: .omitted, time: .shortened))–\(e.endDate.formatted(date: .omitted, time: .shortened))", gapEnd: e.endDate))
        }
        for t in live where t.hasDueTime && t.id != next?.id {
            if let d = t.dueDate, cal.isDateInToday(d), d >= now.addingTimeInterval(-3600), d < anchor {
                out.append(VoyageStop(id: "t" + t.id.uuidString, kind: .waypoint, time: d, title: t.title, task: t))
            }
        }
        out.sort { $0.time < $1.time }
        // Open water: free stretches of 45 minutes or more.
        var withWater: [VoyageStop] = []
        var cursor = now
        for s in out {
            if s.time.timeIntervalSince(cursor) >= 45 * 60 {
                withWater.append(VoyageStop(id: "w\(cursor.timeIntervalSince1970)", kind: .water, time: cursor, title: Self.span(cursor, s.time), gapEnd: s.time))
            }
            withWater.append(s)
            cursor = max(cursor, s.gapEnd ?? s.time.addingTimeInterval(15 * 60))
        }
        if anchor.timeIntervalSince(cursor) >= 45 * 60 {
            withWater.append(VoyageStop(id: "w\(cursor.timeIntervalSince1970)", kind: .water, time: cursor, title: Self.span(cursor, anchor), gapEnd: anchor))
        }
        withWater.append(VoyageStop(id: "anchor", kind: .anchor, time: anchor, title: "Drop anchor", detail: "Bedtime \(anchor.formatted(date: .omitted, time: .shortened))"))
        return withWater
    }

    static func span(_ a: Date, _ b: Date) -> String {
        let m = Int(b.timeIntervalSince(a) / 60)
        return "Open water · " + (m >= 60 ? "\(m / 60)h\(m % 60 >= 15 ? " \(m % 60)m" : "")" : "\(m) min")
    }

    var body: some View {
        // Worked out once per redraw (it was twice), skipping anything just deleted by a sync.
        let live = open.filter { !$0.isDeleted && $0.modelContext != nil }
        let next = ADHDCoach.nextThing(tasks: live, energy: EnergyLevel(rawValue: energyRaw) ?? .medium)
        VStack(alignment: .leading, spacing: 0) {
            bow(next)
            ForEach(stops(next: next, live: live)) { s in stopRow(s) }
        }
        .padding(DS.Space.m)
        .background(DS.Palette.elevated, in: .rect(cornerRadius: 22, style: .continuous))
        .sheet(item: $addingInto) { s in
            NavigationStack {
                Form {
                    TextField("What do you want to get done?", text: $newTask)
                    Text("It goes into the open water at \(s.time.formatted(date: .omitted, time: .shortened)).").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                .navigationTitle("Use this time").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { addingInto = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            let start = max(s.time, Date()).addingTimeInterval(5 * 60)
                            _ = QuickAdd.create(newTask, in: ctx, defaultDue: start)
                            newTask = ""; addingInto = nil; Haptics.success()
                        }
                        .disabled(newTask.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .presentationDetents([.height(240)])
        }
    }

    /// The bow: your one next step, right now.
    private func bow(_ next: TaskItem?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text("⛵").font(.title2)
                Rectangle().fill(DS.Palette.accent.opacity(0.35)).frame(width: 2).frame(maxHeight: .infinity)
            }
            .frame(width: 30)
            VStack(alignment: .leading, spacing: 6) {
                Text("NOW").font(.caption2.weight(.bold)).foregroundStyle(DS.Palette.accent)
                if let t = next {
                    Text(t.title).font(.title3.weight(.semibold)).foregroundStyle(DS.Palette.ink)
                    if let step = t.microSteps.first(where: { !$0.done })?.text { Text("First: \(step)").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft) }
                    HStack {
                        Button { NowTimer.start(t, ctx: ctx); try? ctx.save() } label: { Label("Start", systemImage: "play.fill") }
                            .buttonStyle(.borderedProminent).tint(DS.Palette.accent)
                        Button("Later") {
                            t.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))
                            t.updatedAt = Date(); Haptics.tap()
                        }
                        .buttonStyle(.bordered)
                    }
                    .font(DS.Font.caption.weight(.semibold))
                } else {
                    Text("Clear sailing. Nothing waiting.").font(.title3.weight(.semibold))
                }
            }
            .padding(.bottom, 14)
        }
        .accessibilityElement(children: .contain)
    }

    private func stopRow(_ s: VoyageStop) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Rectangle().fill(DS.Palette.accent.opacity(0.35)).frame(width: 2)
                marker(s.kind)
            }
            .frame(width: 30)
            Group {
                switch s.kind {
                case .water:
                    Button { addingInto = s } label: {
                        HStack {
                            Text("≈ \(s.title) ≈").font(DS.Font.caption.weight(.medium)).foregroundStyle(Color(red: 0.2, green: 0.5, blue: 0.75))
                            Spacer()
                            Image(systemName: "plus.circle").foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Add something to do in this free time")
                case .anchor:
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.title).font(DS.Font.body.weight(.medium))
                        Text(s.detail).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                default:
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.title).font(DS.Font.body.weight(s.kind == .port ? .semibold : .regular)).lineLimit(2)
                            Text(s.detail.isEmpty ? s.time.formatted(date: .omitted, time: .shortened) : s.detail).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        if let t = s.task, !t.isDeleted { Button { TaskActions.setDone(t, true) } label: { Image(systemName: "circle").font(.title3).foregroundStyle(DS.Palette.inkSoft) }.buttonStyle(.plain).accessibilityLabel("Mark \(t.title) done") }
                    }
                }
            }
            .padding(.vertical, s.kind == .water ? 10 : 8)
        }
    }

    @ViewBuilder private func marker(_ k: VoyageStop.Kind) -> some View {
        switch k {
        case .port: Circle().fill(DS.Palette.meeting).frame(width: 14, height: 14).overlay(Circle().stroke(DS.Palette.canvas, lineWidth: 3))
        case .waypoint: Image(systemName: "diamond.fill").font(.caption2).foregroundStyle(DS.Palette.warmth).background(DS.Palette.elevated)
        case .water: Image(systemName: "water.waves").font(.caption2).foregroundStyle(Color(red: 0.2, green: 0.5, blue: 0.75)).background(DS.Palette.elevated)
        case .anchor: Text("⚓").font(.callout).background(DS.Palette.elevated)
        }
    }
}
