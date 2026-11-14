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

    /// How hard each region worked in the last 3 days (0–1), fading as it recovers.
    static func load(days: [BodyDay], now: Date = Date()) -> [String: Double] {
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

struct BodyMapView: View {
    @State private var engine = BodyEngine.shared
    @State private var back = false
    @State private var picked: BodyRegions.Region?
    @State private var spots = BodyMapData.spots

    var body: some View {
        let load = BodyMapData.load(days: engine.days)
        let sore = BodyMapData.current()
        ScrollView {
            VStack(spacing: 16) {
                Picker("Side", selection: $back) { Text("Front").tag(false); Text("Back").tag(true) }.pickerStyle(.segmented)
                GeometryReader { g in
                    let scale = min(g.size.width / 100, g.size.height / 182)
                    let xOff = (g.size.width - 100 * scale) / 2
                    ZStack(alignment: .topLeading) {
                        ForEach(BodyRegions.all.filter { $0.back == back }) { r in
                            let rect = CGRect(x: xOff + r.rect.minX * scale, y: r.rect.minY * scale, width: r.rect.width * scale, height: r.rect.height * scale)
                            let worked = load[r.id] ?? 0
                            let s = sore[r.id]
                            RoundedRectangle(cornerRadius: min(rect.width, rect.height) * r.round, style: .continuous)
                                .fill(fill(worked: worked, sore: s))
                                .overlay(RoundedRectangle(cornerRadius: min(rect.width, rect.height) * r.round, style: .continuous)
                                    .strokeBorder(picked?.id == r.id ? DS.Palette.accent : Color.primary.opacity(0.12), lineWidth: picked?.id == r.id ? 2 : 0.6))
                                .frame(width: rect.width - 1.5, height: rect.height - 1.5)
                                .position(x: rect.midX, y: rect.midY)
                                .onTapGesture { picked = r; Haptics.tap() }
                                .accessibilityElement()
                                .accessibilityLabel(r.name + (s.map { ", \(level($0.level))" } ?? "") + (worked > 0.1 ? ", worked recently" : ""))
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                }
                .frame(height: 420)
                .animation(.snappy, value: back)
                legend
                Text("Tap a part of the body to log soreness or pain. Muscles you've worked in the last three days glow and fade as they recover.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                if let c = BodyMapData.caution() { Label(c, systemImage: "exclamationmark.triangle").font(DS.Font.caption).foregroundStyle(.orange) }
            }
            .padding(DS.Space.m)
        }
        .background(DS.Palette.canvas)
        .navigationTitle("Body map")
        .sheet(item: $picked) { r in RegionSheet(region: r, load: load[r.id] ?? 0, days: engine.days) { spots = BodyMapData.spots } }
    }

    private func fill(worked: Double, sore: SoreSpot?) -> Color {
        if let s = sore { return (s.level >= 3 ? Color.red : Color.orange).opacity(s.level >= 3 ? 0.75 : 0.35 + 0.15 * Double(s.level)) }
        if worked > 0.05 { return BodyStyle.swell.opacity(0.18 + 0.6 * worked) }
        return Color.primary.opacity(0.08)
    }
    private func level(_ l: Int) -> String { l >= 3 ? "pain" : l == 2 ? "sore" : "a bit sore" }

    private var legend: some View {
        HStack(spacing: 14) {
            dot(BodyStyle.swell.opacity(0.7), "Worked")
            dot(.orange.opacity(0.6), "Sore")
            dot(.red.opacity(0.75), "Pain")
        }
        .font(.caption2)
    }
    private func dot(_ c: Color, _ t: String) -> some View { HStack(spacing: 4) { Circle().fill(c).frame(width: 10, height: 10); Text(t) } }
}

private struct RegionSheet: View {
    let region: BodyRegions.Region
    let load: Double
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
