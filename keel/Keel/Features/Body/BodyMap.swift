import SwiftUI

// MARK: - Body map: muscles you've worked, and where it hurts

struct SoreSpot: Codable, Identifiable, Hashable {
    var id = UUID()
    var region: String
    var level: Int             // 1 a bit sore, 2 sore, 3 pain or injury
    var at: Date
    var note: String = ""
}

enum BodyRegions {
    /// A region of the figure, in a 100 × 182 grid (x from the figure's left edge, y from the top).
    struct Region: Identifiable, Hashable {
        let id: String
        let name: String
        let back: Bool
        let rect: CGRect
        let round: CGFloat
    }

    private static func r(_ id: String, _ name: String, _ back: Bool, _ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ round: CGFloat = 0.35) -> Region {
        Region(id: id, name: name, back: back, rect: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0), round: round)
    }

    static let all: [Region] = {
        var out: [Region] = []
        for back in [false, true] {
            let s = back ? "b." : "f."
            out += [
                r(s + "head", "Head", back, 42, 2, 58, 20, 0.5), r(s + "neck", "Neck", back, 46, 20, 54, 26),
                r(s + "shoulderL", "Left shoulder", back, 26, 26, 37, 36, 0.5), r(s + "shoulderR", "Right shoulder", back, 63, 26, 74, 36, 0.5),
                r(s + "armL", back ? "Left triceps" : "Left biceps", back, 22, 36, 32, 62), r(s + "armR", back ? "Right triceps" : "Right biceps", back, 68, 36, 78, 62),
                r(s + "forearmL", "Left forearm", back, 18, 62, 28, 90), r(s + "forearmR", "Right forearm", back, 72, 62, 82, 90),
                r(s + "kneeL", "Left knee", back, 38, 124, 48, 134, 0.5), r(s + "kneeR", "Right knee", back, 52, 124, 62, 134, 0.5),
                r(s + "footL", "Left foot", back, 36, 170, 48, 180, 0.4), r(s + "footR", "Right foot", back, 52, 170, 64, 180, 0.4),
            ]
            if back {
                out += [
                    r("b.upperback", "Upper back", true, 36, 27, 64, 46, 0.2), r("b.lats", "Middle back", true, 37, 46, 63, 60, 0.2),
                    r("b.lowerback", "Lower back", true, 38, 60, 62, 72, 0.2), r("b.glutes", "Glutes", true, 36, 72, 64, 88, 0.3),
                    r("b.hamL", "Left hamstring", true, 37, 88, 49, 124), r("b.hamR", "Right hamstring", true, 51, 88, 63, 124),
                    r("b.calfL", "Left calf", true, 38, 134, 48, 170), r("b.calfR", "Right calf", true, 52, 134, 62, 170),
                ]
            } else {
                out += [
                    r("f.chest", "Chest", false, 36, 27, 64, 46, 0.2), r("f.abs", "Stomach", false, 38, 46, 62, 72, 0.2),
                    r("f.hips", "Hips", false, 36, 72, 64, 86, 0.3),
                    r("f.quadL", "Left thigh", false, 37, 86, 49, 124), r("f.quadR", "Right thigh", false, 51, 86, 63, 124),
                    r("f.shinL", "Left shin", false, 38, 134, 48, 170), r("f.shinR", "Right shin", false, 52, 134, 62, 170),
                ]
            }
        }
        return out
    }()

    static func region(_ id: String) -> Region? { all.first { $0.id == id } }

    /// Which regions each kind of workout uses most.
    static func worked(by workout: String) -> [String] {
        let legs = ["f.quadL", "f.quadR", "b.hamL", "b.hamR", "b.calfL", "b.calfR", "b.glutes", "f.hips"]
        let core = ["f.abs", "b.lowerback"]
        let push = ["f.chest", "f.shoulderL", "f.shoulderR", "b.armL", "b.armR"]
        let pull = ["b.upperback", "b.lats", "f.armL", "f.armR", "b.shoulderL", "b.shoulderR"]
        switch workout {
        case "Run": return legs + ["f.shinL", "f.shinR", "f.kneeL", "f.kneeR"]
        case "Walk", "Hike": return ["b.calfL", "b.calfR", "f.quadL", "f.quadR", "b.glutes"] + (workout == "Hike" ? ["b.hamL", "b.hamR"] : [])
        case "Cycle", "Elliptical": return ["f.quadL", "f.quadR", "b.glutes", "b.calfL", "b.calfR"]
        case "Swim", "Rowing": return pull + ["f.chest", "f.shoulderL", "f.shoulderR"] + (workout == "Rowing" ? legs : [])
        case "Strength", "Functional strength", "HIIT", "Mixed cardio": return push + pull + legs + core
        case "Yoga", "Pilates", "Cooldown": return core + ["b.hamL", "b.hamR", "f.hips"]
        case "Tennis": return ["f.shoulderR", "f.armR", "f.forearmR"] + legs
        case "Basketball", "Soccer", "Dance": return legs + core
        default: return legs
        }
    }
}

@MainActor
enum BodyMapData {
    static let key = "health.soreness"
    static var spots: [SoreSpot] {
        get { LocalLog.load(key) }
        set { LocalLog.save(Array(newValue.suffix(400)), key) }
    }

    /// How hard each region worked in the last 3 days (0–1), fading as it recovers: workouts plus logged strength sets.
    static func load(days: [BodyDay], now: Date = Date()) -> [String: Double] {
        cardioLoad(days: days, now: now).merging(StrengthStore.regionLoad(now: now)) { max($0, $1) }
    }

    /// From workouts recorded in Apple Health only.
    static func cardioLoad(days: [BodyDay], now: Date = Date()) -> [String: Double] {
        var out: [String: Double] = [:]
        for d in days.suffix(4) {
            for w in d.workouts {
                let age = now.timeIntervalSince(w.start) / 86_400
                guard age >= 0, age < 3 else { continue }
                let fade = 1 - age / 3
                let strength = min(1, Double(max(w.swell, 15)) / 70) * fade
                for id in BodyRegions.worked(by: w.name) { out[id] = min(1, (out[id] ?? 0) + strength) }
            }
        }
        return out
    }

    /// Sore or painful in the last week, newest first per region.
    static func current(now: Date = Date()) -> [String: SoreSpot] {
        var out: [String: SoreSpot] = [:]
        for s in spots.filter({ now.timeIntervalSince($0.at) < 7 * 86_400 }).sorted(by: { $0.at < $1.at }) { out[s.region] = s }
        return out
    }

    /// For the workout pick: "Go easy on your legs" when they're sore.
    static func caution(now: Date = Date()) -> String? {
        let sore = current(now: now).values.filter { $0.level >= 2 && now.timeIntervalSince($0.at) < 2 * 86_400 }
        guard !sore.isEmpty else { return nil }
        let names = sore.compactMap { BodyRegions.region($0.region)?.name.lowercased() }.prefix(3)
        return "Go easy on your \(names.joined(separator: ", ")): you logged \(sore.contains { $0.level == 3 } ? "pain" : "soreness") there."
    }
}

/// The Recovery map: one picture of how ready each part of your body is to train.
/// Muscles colour from fresh (green) through recovering (yellow) to worked hard (orange), using your strength sets
/// and the workouts Apple Health recorded. Sore spots and pain you log show on top. Use it to pick today's workout
/// (train what's fresh, rest what isn't) and to keep an eye on a niggle before it becomes an injury.
struct BodyMapView: View {
    @State private var engine = BodyEngine.shared
    @State private var picked: BodyRegions.Region?
    @State private var spots = BodyMapData.spots

    var body: some View {
        let load = BodyMapData.load(days: engine.days)
        let sore = BodyMapData.current()
        let ready = BodyRecovery.readiness(load: load, sore: sore)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                KitIntro(icon: "figure.stand", color: BodyStyle.swell, text: "Your recovery map. Each muscle shows how ready it is to train, from your strength sets and the workouts in Apple Health: green is fresh, yellow is still recovering, orange was worked hard. Tap anywhere that's sore or hurts to log it, so Keel steers your workouts around it.")
                todayCard(ready)
                HStack(alignment: .top, spacing: 8) {
                    figure(back: false, load: load, sore: sore, ready: ready)
                    figure(back: true, load: load, sore: sore, ready: ready)
                }
                .frame(height: 340)
                legend
                if let c = BodyMapData.caution() {
                    Label(c, systemImage: "exclamationmark.triangle.fill").font(DS.Font.caption).foregroundStyle(.orange)
                }
                muscleList(ready)
            }
            .padding(DS.Space.m)
        }
        .premiumBackground(BodyStyle.swell)
        .navigationTitle("Recovery map")
        .sheet(item: $picked) { r in
            RegionSheet(region: r, load: load[r.id] ?? 0, ready: ready.region[r.id] ?? 1, days: engine.days) { spots = BodyMapData.spots }
        }
    }

    // MARK: Today

    private func todayCard(_ r: BodyRecovery.Readiness) -> some View {
        let fresh = r.groups.filter { $0.value >= 0.8 }.map(\.name)
        let rest = r.groups.filter { $0.value < 0.5 }
        return GlassCard(tint: BodyStyle.swell) {
            VStack(alignment: .leading, spacing: 8) {
                Text("TODAY").font(DS.Font.caption.weight(.semibold)).foregroundStyle(BodyStyle.swell)
                if rest.isEmpty {
                    Text("Everything's recovered. A good day for a hard session.").font(DS.Font.headline)
                } else {
                    Text(fresh.isEmpty ? "Take it easy today: most of you is still recovering." : "Train \(ListFormatter.localizedString(byJoining: Array(fresh.prefix(3))).lowercased()).")
                        .font(DS.Font.headline)
                    Text("Rest \(ListFormatter.localizedString(byJoining: rest.prefix(3).map { $0.name.lowercased() + " (" + $0.reason + ")" })).")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Figure

    private func figure(back: Bool, load: [String: Double], sore: [String: SoreSpot], ready: BodyRecovery.Readiness) -> some View {
        VStack(spacing: 4) {
            GeometryReader { g in
                let scale = min(g.size.width / 100, g.size.height / 182)
                let xOff = (g.size.width - 100 * scale) / 2
                let regions = BodyRegions.all.filter { $0.back == back }
                ZStack(alignment: .topLeading) {
                    // The silhouette: every region slightly enlarged, so the figure reads as one body.
                    ForEach(regions) { r in
                        let rect = place(r.rect.insetBy(dx: -1.6, dy: -1.6), scale, xOff)
                        RoundedRectangle(cornerRadius: min(rect.width, rect.height) * max(r.round, 0.45), style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                    ForEach(regions) { r in
                        let rect = place(r.rect.insetBy(dx: 0.6, dy: 0.6), scale, xOff)
                        let shape = RoundedRectangle(cornerRadius: min(rect.width, rect.height) * max(r.round, 0.45), style: .continuous)
                        let s = sore[r.id]
                        let worked = load[r.id] ?? 0
                        shape
                            .fill(LinearGradient(colors: [color(ready.region[r.id] ?? 1, worked: worked), color(ready.region[r.id] ?? 1, worked: worked).opacity(0.65)],
                                                 startPoint: .top, endPoint: .bottom))
                            .overlay {
                                if let s {
                                    shape.strokeBorder(s.level >= 3 ? Color.red : .orange, style: StrokeStyle(lineWidth: s.level >= 3 ? 2.2 : 1.6, dash: s.level >= 3 ? [] : [3, 2]))
                                }
                            }
                            .overlay { if picked?.id == r.id { shape.strokeBorder(DS.Palette.accent, lineWidth: 2) } }
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .onTapGesture { picked = r; Haptics.tap() }
                            .accessibilityElement()
                            .accessibilityLabel(r.name + ", \(Int(((ready.region[r.id] ?? 1) * 100).rounded()))% ready" + (s.map { ", \(level($0.level))" } ?? ""))
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
            Text(back ? "Back" : "Front").font(.caption2.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft)
        }
    }

    private func place(_ r: CGRect, _ scale: CGFloat, _ xOff: CGFloat) -> CGRect {
        CGRect(x: xOff + r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale)
    }

    /// Green when fresh, yellow while recovering, orange when worked hard. Untouched parts stay quiet.
    private func color(_ ready: Double, worked: Double) -> Color {
        if ready >= 0.95 && worked < 0.05 { return Color.primary.opacity(0.10) }
        if ready >= 0.8 { return .green.opacity(0.55) }
        if ready >= 0.5 { return .yellow.opacity(0.75) }
        return .orange.opacity(0.85)
    }
    private func level(_ l: Int) -> String { l >= 3 ? "pain" : l == 2 ? "sore" : "a bit sore" }

    private var legend: some View {
        HStack(spacing: 12) {
            dot(.green.opacity(0.55), "Fresh")
            dot(.yellow.opacity(0.75), "Recovering")
            dot(.orange.opacity(0.85), "Worked hard")
            HStack(spacing: 4) { RoundedRectangle(cornerRadius: 3).strokeBorder(.red, lineWidth: 2).frame(width: 12, height: 12); Text("Pain") }
        }
        .font(.caption2)
        .frame(maxWidth: .infinity)
    }
    private func dot(_ c: Color, _ t: String) -> some View { HStack(spacing: 4) { Circle().fill(c).frame(width: 10, height: 10); Text(t) } }

    // MARK: Muscles

    private func muscleList(_ r: BodyRecovery.Readiness) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Muscles").font(DS.Font.headline)
            ForEach(r.muscles, id: \.muscle) { m in
                Button {
                    if let id = m.muscle.regions.first, let region = BodyRegions.region(id) { picked = region }
                } label: {
                    HStack {
                        Text(m.muscle.name).foregroundStyle(DS.Palette.ink)
                        Spacer()
                        if let note = m.note { Text(note).font(.caption2).foregroundStyle(.orange) }
                        ProgressView(value: m.ready).tint(m.ready >= 0.8 ? .green : m.ready >= 0.5 ? .yellow : .orange).frame(width: 90)
                        Text("\(Int((m.ready * 100).rounded()))%").monospacedDigit().font(.caption.weight(.semibold)).frame(width: 38, alignment: .trailing)
                            .foregroundStyle(DS.Palette.ink)
                    }
                }
                .buttonStyle(.plain)
            }
            Text("Muscles are fresh again after about 2–3 days of rest. Logged soreness lowers readiness until it's gone.")
                .font(.caption2).foregroundStyle(DS.Palette.inkSoft)
        }
        .padding(DS.Space.m)
        .background(DS.Palette.elevated, in: .rect(cornerRadius: 18, style: .continuous))
    }
}

/// How ready each muscle and body part is to train: worked load (strength + workouts) and logged soreness.
@MainActor
enum BodyRecovery {
    struct MuscleState { let muscle: Muscle; let ready: Double; let note: String? }
    struct Area { let name: String; let value: Double; let reason: String }
    struct Readiness { var region: [String: Double]; var muscles: [MuscleState]; var groups: [Area] }

    static func readiness(load: [String: Double], sore: [String: SoreSpot]) -> Readiness {
        func soreCap(_ s: SoreSpot?) -> Double { guard let s else { return 1 }; return s.level >= 3 ? 0.2 : s.level == 2 ? 0.45 : 0.7 }
        var region: [String: Double] = [:]
        for r in BodyRegions.all { region[r.id] = min(1 - (load[r.id] ?? 0), soreCap(sore[r.id])) }
        let muscles = Muscle.allCases.map { m -> MuscleState in
            let values = m.regions.compactMap { region[$0] }
            let ready = values.min() ?? 1
            let worst = m.regions.compactMap { sore[$0] }.max { $0.level < $1.level }
            return MuscleState(muscle: m, ready: max(0, ready), note: worst.map { $0.level >= 3 ? "pain" : "sore" })
        }
        let byName = Dictionary(uniqueKeysWithValues: muscles.map { ($0.muscle, $0) })
        let groups: [(String, [Muscle])] = [
            ("Legs", [.quads, .hamstrings, .calves, .glutes]), ("Chest", [.chest]), ("Back", [.upperBack, .lats, .lowerBack]),
            ("Shoulders", [.shoulders, .rearDelts]), ("Arms", [.biceps, .triceps, .forearms]), ("Core", [.abs, .hips]),
        ]
        let g = groups.map { name, ms -> Area in
            let states = ms.compactMap { byName[$0] }
            let v = states.map(\.ready).min() ?? 1
            let reason = states.contains { $0.note == "pain" } ? "pain" : states.contains { $0.note != nil } ? "sore" : "\(Int(((1 - v) * 100).rounded()))% tired"
            return Area(name: name, value: v, reason: reason)
        }
        return Readiness(region: region, muscles: muscles, groups: g)
    }

    /// Roughly how long until a part that's this tired is fresh again.
    static func hoursUntilFresh(load: Double) -> Int {
        guard load > 0.2 else { return 0 }
        return Int((36 * log(load / 0.2)).rounded(.up))
    }
}

private struct RegionSheet: View {
    let region: BodyRegions.Region
    let load: Double
    var ready: Double = 1
    let days: [BodyDay]
    var saved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var level = 1
    @State private var note = ""

    var body: some View {
        let workouts = days.suffix(4).flatMap(\.workouts).filter { BodyRegions.worked(by: $0.name).contains(region.id) }
        let history = BodyMapData.spots.filter { $0.region == region.id }.sorted { $0.at > $1.at }.prefix(8)
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Ready to train", value: "\(Int((ready * 100).rounded()))%")
                    let hours = BodyRecovery.hoursUntilFresh(load: load)
                    if hours > 0 { LabeledContent("Fresh again in", value: hours >= 24 ? "about \(Int((Double(hours) / 24).rounded())) day\(hours >= 36 ? "s" : "")" : "about \(hours) h") }
                }
                if !workouts.isEmpty {
                    Section("Worked recently") {
                        ForEach(workouts) { w in Text("\(w.name) · \(w.start.formatted(.relative(presentation: .named)))") }
                    }
                }
                Section("How does it feel?") {
                    Picker("Level", selection: $level) { Text("A bit sore").tag(1); Text("Sore").tag(2); Text("Pain").tag(3) }.pickerStyle(.segmented)
                    TextField("Note (optional), e.g. after squats", text: $note)
                    Button("Log it") {
                        var all = BodyMapData.spots
                        all.append(SoreSpot(region: region.id, level: level, at: Date(), note: note))
                        BodyMapData.spots = all; saved(); Haptics.tap(); dismiss()
                    }
                    Button("It's fine now", role: .destructive) {
                        BodyMapData.spots = BodyMapData.spots.filter { $0.region != region.id || Date().timeIntervalSince($0.at) > 7 * 86_400 }
                        saved(); dismiss()
                    }
                }
                if !history.isEmpty {
                    Section("History") {
                        ForEach(Array(history)) { s in
                            Text("\(s.level >= 3 ? "Pain" : s.level == 2 ? "Sore" : "A bit sore") · \(s.at.formatted(date: .abbreviated, time: .shortened))" + (s.note.isEmpty ? "" : " · \(s.note)"))
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle(region.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
