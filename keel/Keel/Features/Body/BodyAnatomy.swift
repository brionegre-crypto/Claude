import SwiftUI

// MARK: - Anatomical figure for the Recovery map
//
// A real body instead of boxes: each muscle group is a smooth shape (deltoids, pecs, abs, obliques, biceps/triceps,
// forearms, quads, hamstrings, glutes, traps, lats, calves…), drawn on a continuous silhouette with fine seams
// between muscles. Same region ids as before, so readiness, soreness and tapping to log all work unchanged.

enum Anatomy {
    /// Drawn in a 200 × 440 space; x < 100 is the figure's left as you look at it.
    static let size = CGSize(width: 200, height: 440)

    enum Part {
        case poly([CGPoint])
        case oval(CGRect)
        case rounded(CGRect, CGFloat)
    }

    private static func p(_ xy: [(CGFloat, CGFloat)]) -> Part { .poly(xy.map { CGPoint(x: $0.0, y: $0.1) }) }
    private static func mirror(_ part: Part) -> Part {
        switch part {
        case .poly(let pts): return .poly(pts.map { CGPoint(x: 200 - $0.x, y: $0.y) })
        case .oval(let r): return .oval(CGRect(x: 200 - r.maxX, y: r.minY, width: r.width, height: r.height))
        case .rounded(let r, let c): return .rounded(CGRect(x: 200 - r.maxX, y: r.minY, width: r.width, height: r.height), c)
        }
    }

    // Shared left-side shapes (front and back mostly share the limbs).
    private static let delt = p([(78, 66), (66, 65), (55, 73), (50, 88), (51, 102), (59, 105), (67, 93), (76, 80)])
    private static let upperArm = p([(53, 106), (62, 109), (63, 128), (59, 150), (50, 153), (45, 137), (46, 119)])
    private static let forearm = p([(48, 157), (59, 155), (57, 177), (49, 206), (42, 208), (39, 187), (41, 169)])
    private static let knee = Part.oval(CGRect(x: 73, y: 304, width: 18, height: 16))
    private static let foot = p([(75, 406), (88, 406), (91, 419), (85, 431), (74, 429), (71, 418)])

    /// The shapes for one region (empty for an unknown id).
    static func parts(_ id: String) -> [Part] {
        let left: [Part]
        switch id {
        case "f.head", "b.head": return [.oval(CGRect(x: 83, y: 6, width: 34, height: 42))]
        case "f.neck": return [p([(90, 46), (110, 46), (113, 62), (100, 67), (87, 62)])]
        case "b.neck": return [p([(89, 46), (111, 46), (114, 60), (100, 63), (86, 60)])]
        case "f.shoulderL", "b.shoulderL": return [delt]
        case "f.shoulderR", "b.shoulderR": return [mirror(delt)]
        case "f.armL", "b.armL": return [upperArm]
        case "f.armR", "b.armR": return [mirror(upperArm)]
        case "f.forearmL", "b.forearmL": return [forearm]
        case "f.forearmR", "b.forearmR": return [mirror(forearm)]
        case "f.kneeL", "b.kneeL": return [knee]
        case "f.kneeR", "b.kneeR": return [mirror(knee)]
        case "f.footL", "b.footL": return [foot]
        case "f.footR", "b.footR": return [mirror(foot)]

        // Front
        case "f.chest":
            left = [p([(99, 71), (81, 69), (70, 79), (66, 95), (73, 109), (89, 114), (99, 110)])]
            return left + left.map(mirror)
        case "f.abs":
            var out: [Part] = []
            for (i, y) in [118.0, 139.0, 160.0].enumerated() {
                let h: CGFloat = i == 2 ? 22 : 19
                out.append(.rounded(CGRect(x: 89.5, y: y, width: 9.6, height: h), 4))
                out.append(.rounded(CGRect(x: 100.9, y: y, width: 9.6, height: h), 4))
            }
            out.append(p([(90, 185), (110, 185), (106, 203), (100, 209), (94, 203)]))
            return out
        case "f.hips":
            left = [p([(73, 114), (87, 118), (87, 180), (92, 203), (84, 208), (76, 188), (71, 150)])]
            return left + left.map(mirror)
        case "f.quadL": return [p([(78, 207), (97, 210), (96, 242), (92, 288), (87, 302), (76, 302), (71, 270), (71, 236)])]
        case "f.quadR": return [mirror(p([(78, 207), (97, 210), (96, 242), (92, 288), (87, 302), (76, 302), (71, 270), (71, 236)]))]
        case "f.shinL": return [p([(76, 322), (88, 322), (90, 350), (87, 388), (82, 402), (78, 400), (74, 370), (73, 345)])]
        case "f.shinR": return [mirror(p([(76, 322), (88, 322), (90, 350), (87, 388), (82, 402), (78, 400), (74, 370), (73, 345)]))]

        // Back
        case "b.upperback": return [p([(91, 52), (109, 52), (125, 67), (119, 90), (100, 119), (81, 90), (75, 67)])]
        case "b.lats":
            left = [p([(80, 93), (98, 121), (98, 165), (86, 170), (76, 151), (70, 119), (70, 101)])]
            return left + left.map(mirror)
        case "b.lowerback": return [p([(87, 169), (113, 169), (115, 196), (100, 203), (85, 196)])]
        case "b.glutes":
            left = [p([(99, 205), (84, 201), (74, 213), (73, 236), (83, 251), (99, 247)])]
            return left + left.map(mirror)
        case "b.hamL": return [p([(75, 253), (98, 253), (96, 287), (90, 302), (80, 302), (73, 280)])]
        case "b.hamR": return [mirror(p([(75, 253), (98, 253), (96, 287), (90, 302), (80, 302), (73, 280)]))]
        case "b.calfL": return [p([(75, 322), (89, 322), (92, 346), (88, 372), (84, 400), (78, 400), (73, 372), (72, 344)])]
        case "b.calfR": return [mirror(p([(75, 322), (89, 322), (92, 346), (88, 372), (84, 400), (78, 400), (73, 372), (72, 344)]))]
        default: return []
        }
    }

    /// Hands: drawn as part of the silhouette, not tappable regions.
    static let hands: [Part] = [.oval(CGRect(x: 35, y: 208, width: 13, height: 26)), mirror(.oval(CGRect(x: 35, y: 208, width: 13, height: 26)))]

    /// A smooth closed curve through the points (Catmull–Rom), so muscles look organic, not polygonal.
    static func path(_ parts: [Part], in rect: CGRect) -> Path {
        let s = min(rect.width / size.width, rect.height / size.height)
        let ox = rect.minX + (rect.width - size.width * s) / 2
        let oy = rect.minY + (rect.height - size.height * s) / 2
        func t(_ p: CGPoint) -> CGPoint { CGPoint(x: ox + p.x * s, y: oy + p.y * s) }
        func tr(_ r: CGRect) -> CGRect { CGRect(x: ox + r.minX * s, y: oy + r.minY * s, width: r.width * s, height: r.height * s) }
        var path = Path()
        for part in parts {
            switch part {
            case .oval(let r): path.addEllipse(in: tr(r))
            case .rounded(let r, let c): path.addRoundedRect(in: tr(r), cornerSize: CGSize(width: c * s, height: c * s), style: .continuous)
            case .poly(let raw):
                let pts = raw.map(t)
                guard pts.count > 2 else { continue }
                let n = pts.count
                path.move(to: pts[0])
                for i in 0..<n {
                    let p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n]
                    let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                    let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
                    path.addCurve(to: p2, control1: c1, control2: c2)
                }
                path.closeSubpath()
            }
        }
        return path
    }
}

struct AnatomyShape: Shape {
    let parts: [Anatomy.Part]
    func path(in rect: CGRect) -> Path { Anatomy.path(parts, in: rect) }
}

/// One side of the figure (front or back), every muscle coloured by readiness, with logged soreness on top.
struct AnatomyFigure: View {
    let back: Bool
    let fill: (String) -> Color
    let sore: [String: SoreSpot]
    let selected: String?
    let onTap: (BodyRegions.Region) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let regions = BodyRegions.all.filter { $0.back == back }
        let all = regions.flatMap { Anatomy.parts($0.id) } + Anatomy.hands
        let dark = scheme == .dark
        let seam = DS.Palette.canvas
        ZStack {
            // Silhouette: every shape slightly thickened so the body reads as one form; muscles sit on top with seams.
            AnatomyShape(parts: all)
                .stroke(Color.primary.opacity(dark ? 0.16 : 0.10), style: StrokeStyle(lineWidth: 7, lineJoin: .round))
            AnatomyShape(parts: all).fill(Color.primary.opacity(dark ? 0.16 : 0.10))
            AnatomyShape(parts: Anatomy.hands).fill(Color.primary.opacity(dark ? 0.2 : 0.13))

            ForEach(regions) { r in
                let shape = AnatomyShape(parts: Anatomy.parts(r.id))
                let c = fill(r.id)
                shape
                    .fill(LinearGradient(colors: [c.mix(with: .white, by: dark ? 0.08 : 0.22), c], startPoint: .top, endPoint: .bottom))
                    .overlay { shape.stroke(seam, lineWidth: 1.1) }                       // the seams between muscles
                    .overlay {
                        if let s = sore[r.id] {
                            shape.stroke(s.level >= 3 ? Color.red : .orange,
                                         style: StrokeStyle(lineWidth: s.level >= 3 ? 2.4 : 1.8, dash: s.level >= 3 ? [] : [3, 2]))
                        }
                    }
                    .overlay { if selected == r.id { shape.stroke(DS.Palette.accent, lineWidth: 2.4) } }
                    .contentShape(shape)
                    .onTapGesture { onTap(r); Haptics.tap() }
                    .accessibilityElement()
                    .accessibilityLabel(r.name)
                    .accessibilityAddTraits(.isButton)
            }
        }
        .aspectRatio(Anatomy.size, contentMode: .fit)
        .drawingGroup(opaque: false)          // one image while scrolling; taps still work
    }
}
