import SwiftUI
import SwiftData

/// Brain map: your notes as neurons inside a brain. Links between pages are the connections (with signals
/// travelling along them), sub-pages hang off their parents, and each folder lives in its own lobe.
/// Databases sit in the cerebellum, which handles the routine. Pinch to zoom, drag to look around,
/// tap a neuron to light up everything it connects to.
struct BrainNode: Identifiable, Sendable {
    let id: UUID
    let title: String
    let icon: String
    let lobe: Int
    var degree: Int
    var pos: CGPoint                 // 0…1 brain space
}

struct BrainEdge: Sendable, Hashable {
    let a: Int
    let b: Int
    let strong: Bool                 // a real link (vs. a sub-page)
}

enum BrainLobe: Int, CaseIterable, Sendable {
    case frontal, parietal, temporal, occipital, cerebellum
    var name: String {
        switch self {
        case .frontal: "Frontal"; case .parietal: "Parietal"; case .temporal: "Temporal"
        case .occipital: "Occipital"; case .cerebellum: "Cerebellum"
        }
    }
    /// Where each lobe sits in a side view of the brain (front is on the left).
    var center: CGPoint {
        switch self {
        case .frontal: CGPoint(x: 0.27, y: 0.40)
        case .parietal: CGPoint(x: 0.56, y: 0.25)
        case .temporal: CGPoint(x: 0.46, y: 0.60)
        case .occipital: CGPoint(x: 0.80, y: 0.42)
        case .cerebellum: CGPoint(x: 0.71, y: 0.80)
        }
    }
    var color: Color {
        switch self {
        case .frontal: .orange; case .parietal: .purple; case .temporal: .teal; case .occipital: .pink; case .cerebellum: .green
        }
    }
}

/// The shape of the brain, in 0…1 space, shared by drawing and layout.
enum BrainGeometry {
    static let cortexCenter = CGPoint(x: 0.49, y: 0.44)
    static let rx = 0.43, ry = 0.33
    static let cerebellumCenter = CGPoint(x: 0.71, y: 0.80)
    static let crx = 0.15, cry = 0.085

    /// Bumpy outline: the folds (gyri) of the cortex.
    static func folds(_ a: Double) -> Double { 1 + 0.03 * sin(9 * a) + 0.018 * sin(17 * a + 1.3) + 0.012 * sin(29 * a + 0.4) }

    static func cortexPoint(_ a: Double) -> CGPoint {
        // Slightly flatter underneath, like a real brain.
        let squash = sin(a) > 0 ? 0.82 : 1.0
        let f = folds(a)
        return CGPoint(x: cortexCenter.x + rx * f * cos(a), y: cortexCenter.y + ry * f * squash * sin(a))
    }

    static func inside(_ p: CGPoint, margin: Double = 0.9) -> Bool {
        let dx = Double(p.x - cortexCenter.x), dy = Double(p.y - cortexCenter.y)
        let a = atan2(dy, dx)
        let squash = sin(a) > 0 ? 0.82 : 1.0
        let f = folds(a) * margin
        let inCortex = pow(dx / (rx * f), 2) + pow(dy / (ry * f * squash), 2) <= 1
        let cx = Double(p.x - cerebellumCenter.x), cy = Double(p.y - cerebellumCenter.y)
        let inCere = pow(cx / (crx * margin), 2) + pow(cy / (cry * margin), 2) <= 1
        return inCortex || inCere
    }

    static func cortexPath(in r: CGRect) -> Path {
        var p = Path()
        for i in 0...240 {
            let a = Double(i) / 240 * 2 * .pi
            let q = map(cortexPoint(a), r)
            i == 0 ? p.move(to: q) : p.addLine(to: q)
        }
        p.closeSubpath()
        return p
    }

    static func cerebellumPath(in r: CGRect) -> Path {
        var p = Path()
        for i in 0...120 {
            let a = Double(i) / 120 * 2 * .pi
            let f = 1 + 0.04 * sin(14 * a)
            let q = map(CGPoint(x: cerebellumCenter.x + crx * f * cos(a), y: cerebellumCenter.y + cry * f * sin(a)), r)
            i == 0 ? p.move(to: q) : p.addLine(to: q)
        }
        p.closeSubpath()
        return p
    }

    static func stemPath(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: map(CGPoint(x: 0.55, y: 0.70), r))
        p.addQuadCurve(to: map(CGPoint(x: 0.58, y: 0.98), r), control: map(CGPoint(x: 0.53, y: 0.86), r))
        p.addLine(to: map(CGPoint(x: 0.64, y: 0.98), r))
        p.addQuadCurve(to: map(CGPoint(x: 0.62, y: 0.70), r), control: map(CGPoint(x: 0.60, y: 0.84), r))
        p.closeSubpath()
        return p
    }

    /// Decorative grooves: the central and lateral sulci, plus a few smaller folds.
    static func sulciPath(in r: CGRect) -> Path {
        var p = Path()
        func curve(_ pts: [CGPoint]) {
            guard let first = pts.first else { return }
            p.move(to: map(first, r))
            for i in stride(from: 1, to: pts.count - 1, by: 2) {
                p.addQuadCurve(to: map(pts[i + 1], r), control: map(pts[i], r))
            }
        }
        curve([CGPoint(x: 0.47, y: 0.13), CGPoint(x: 0.43, y: 0.30), CGPoint(x: 0.46, y: 0.45)])           // central sulcus
        curve([CGPoint(x: 0.24, y: 0.57), CGPoint(x: 0.42, y: 0.47), CGPoint(x: 0.66, y: 0.50)])           // lateral sulcus
        curve([CGPoint(x: 0.18, y: 0.30), CGPoint(x: 0.26, y: 0.24), CGPoint(x: 0.34, y: 0.27)])
        curve([CGPoint(x: 0.62, y: 0.16), CGPoint(x: 0.66, y: 0.28), CGPoint(x: 0.74, y: 0.31)])
        curve([CGPoint(x: 0.36, y: 0.66), CGPoint(x: 0.47, y: 0.70), CGPoint(x: 0.56, y: 0.64)])
        curve([CGPoint(x: 0.80, y: 0.26), CGPoint(x: 0.86, y: 0.40), CGPoint(x: 0.84, y: 0.54)])
        return p
    }

    static func map(_ p: CGPoint, _ r: CGRect) -> CGPoint {
        CGPoint(x: r.minX + p.x * r.width, y: r.minY + p.y * r.height)
    }
}

enum BrainLayout {
    /// Force layout: links pull neurons together, everything repels a little, each neuron drifts
    /// toward its lobe, and nothing leaves the brain.
    static func run(_ nodesIn: [BrainNode], _ edges: [BrainEdge]) -> [BrainNode] {
        var nodes = nodesIn
        let n = nodes.count
        guard n > 0 else { return nodes }
        var rng = SystemRandomNumberGenerator()
        for i in 0..<n {
            let c = BrainLobe(rawValue: nodes[i].lobe)?.center ?? BrainGeometry.cortexCenter
            nodes[i].pos = CGPoint(x: c.x + .random(in: -0.08...0.08, using: &rng), y: c.y + .random(in: -0.06...0.06, using: &rng))
        }
        let iterations = n > 120 ? 220 : 320
        let repulse = 0.00028 * (60.0 / Double(max(n, 20))).squareRoot()
        for step in 0..<iterations {
            let cool = 1 - Double(step) / Double(iterations)
            var force = [CGVector](repeating: .zero, count: n)
            for i in 0..<n {
                for j in (i + 1)..<n {
                    var dx = Double(nodes[i].pos.x - nodes[j].pos.x), dy = Double(nodes[i].pos.y - nodes[j].pos.y)
                    var d2 = dx * dx + dy * dy
                    if d2 < 1e-6 { dx = 0.001 * Double(i - j); dy = 0.001; d2 = 1e-4 }
                    let f = repulse / d2
                    let d = d2.squareRoot()
                    force[i].dx += f * dx / d; force[i].dy += f * dy / d
                    force[j].dx -= f * dx / d; force[j].dy -= f * dy / d
                }
            }
            for e in edges {
                let dx = Double(nodes[e.b].pos.x - nodes[e.a].pos.x), dy = Double(nodes[e.b].pos.y - nodes[e.a].pos.y)
                let d = max(0.001, (dx * dx + dy * dy).squareRoot())
                let rest = e.strong ? 0.07 : 0.05
                let k = (d - rest) * (e.strong ? 0.06 : 0.04)
                force[e.a].dx += k * dx / d; force[e.a].dy += k * dy / d
                force[e.b].dx -= k * dx / d; force[e.b].dy -= k * dy / d
            }
            for i in 0..<n {
                let c = BrainLobe(rawValue: nodes[i].lobe)?.center ?? BrainGeometry.cortexCenter
                force[i].dx += Double(c.x - nodes[i].pos.x) * 0.012
                force[i].dy += Double(c.y - nodes[i].pos.y) * 0.012
                let maxStep = 0.02 * cool + 0.002
                let fx = max(-maxStep, min(maxStep, force[i].dx)), fy = max(-maxStep, min(maxStep, force[i].dy))
                var p = CGPoint(x: Double(nodes[i].pos.x) + fx, y: Double(nodes[i].pos.y) + fy)
                // Stay inside the brain: step back toward the lobe until inside.
                var tries = 0
                while !BrainGeometry.inside(p, margin: 0.88) && tries < 12 {
                    p = CGPoint(x: p.x + (c.x - p.x) * 0.25, y: p.y + (c.y - p.y) * 0.25)
                    tries += 1
                }
                nodes[i].pos = p
            }
        }
        return nodes
    }
}

// MARK: - Screen

struct BrainMapView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var allNotes: [Note]
    @State private var nodes: [BrainNode] = []
    @State private var edges: [BrainEdge] = []
    @State private var folders: [String] = []           // folder → lobe, in lobe order
    @State private var building = true
    @State private var selected: Int?
    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero
    @State private var showTree = true
    @State private var lobeFilter: Int?
    @State private var opened: Note?
    @State private var find = ""

    private var neighbors: Set<Int> {
        guard let s = selected else { return [] }
        return Set(edges.compactMap { $0.a == s ? $0.b : ($0.b == s ? $0.a : nil) })
    }
    private var shownEdges: [BrainEdge] { showTree ? edges : edges.filter(\.strong) }

    var body: some View {
        GeometryReader { geo in
            let rect = brainRect(geo.size)
            ZStack {
                background
                TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || building)) { tl in
                    Canvas { ctx, _ in draw(ctx: ctx, rect: rect, time: tl.date.timeIntervalSinceReferenceDate) }
                }
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { v in tap(v.location, rect: rect) })
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { zoom = min(5, max(0.8, zoomBase * $0.magnification)) }
                    .onEnded { _ in zoomBase = zoom })
                .simultaneousGesture(DragGesture(minimumDistance: 8)
                    .onChanged { pan = CGSize(width: panBase.width + $0.translation.width, height: panBase.height + $0.translation.height) }
                    .onEnded { _ in panBase = pan })
                .accessibilityElement()
                .accessibilityLabel("Brain map of \(nodes.count) notes and \(edges.filter(\.strong).count) links")
                .accessibilityHint("Pinch to zoom, drag to look around, tap a neuron to select a note")

                if building {
                    VStack(spacing: 8) { ProgressView(); Text("Growing your brain…").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft) }
                } else if nodes.count < 2 {
                    ContentUnavailableView("Your brain is quiet", systemImage: "brain",
                                           description: Text("Write a few pages and link them with @ or [[Page name]]. Each page becomes a neuron; each link, a connection."))
                }
            }
            .overlay(alignment: .top) { topBar }
            .overlay(alignment: .bottom) { if let s = selected, s < nodes.count { detailCard(s) } }
        }
        .navigationTitle("Brain Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Show sub-page connections", isOn: $showTree)
                    Button("Reset view", systemImage: "arrow.counterclockwise") { withAnimation(.spring) { zoom = 1; zoomBase = 1; pan = .zero; panBase = .zero } }
                    Button("Rearrange", systemImage: "sparkles") { Task { await build() } }
                } label: { Image(systemName: "slider.horizontal.3") }
                .accessibilityLabel("Map options")
            }
        }
        .navigationDestination(item: $opened) { NoteEditor(note: $0) }
        .task { await build() }
    }

    // MARK: Look

    private var background: some View {
        RadialGradient(colors: scheme == .dark
                       ? [Color(red: 0.16, green: 0.06, blue: 0.12), Color(red: 0.05, green: 0.03, blue: 0.06)]
                       : [Color(red: 1.0, green: 0.95, blue: 0.94), Color(red: 0.97, green: 0.93, blue: 0.96)],
                       center: .center, startRadius: 40, endRadius: 520)
            .ignoresSafeArea()
    }

    private func brainRect(_ size: CGSize) -> CGRect {
        let w = min(size.width * 0.96, (size.height - 180) * 1.3)
        let h = w / 1.3
        let base = CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2 + 10, width: w, height: h)
        let c = CGPoint(x: base.midX + pan.width, y: base.midY + pan.height)
        return CGRect(x: c.x - base.width * zoom / 2, y: c.y - base.height * zoom / 2, width: base.width * zoom, height: base.height * zoom)
    }

    private func screen(_ i: Int, _ rect: CGRect) -> CGPoint { BrainGeometry.map(nodes[i].pos, rect) }

    private func draw(ctx: GraphicsContext, rect: CGRect, time: Double) {
        let dark = scheme == .dark
        let tissue = dark ? Color(red: 0.42, green: 0.18, blue: 0.30) : Color(red: 0.98, green: 0.78, blue: 0.80)
        let tissueEdge = dark ? Color(red: 0.75, green: 0.38, blue: 0.55) : Color(red: 0.88, green: 0.55, blue: 0.62)

        // The brain itself: stem, cerebellum, cortex, then its folds.
        let stem = BrainGeometry.stemPath(in: rect), cere = BrainGeometry.cerebellumPath(in: rect), cortex = BrainGeometry.cortexPath(in: rect)
        ctx.fill(stem, with: .color(tissue.opacity(0.7)))
        ctx.fill(cere, with: .linearGradient(Gradient(colors: [tissue, tissue.opacity(0.75)]), startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        ctx.stroke(cere, with: .color(tissueEdge.opacity(0.6)), lineWidth: 1.5)
        var glow = ctx
        glow.addFilter(.shadow(color: tissueEdge.opacity(dark ? 0.6 : 0.35), radius: 24))
        glow.fill(cortex, with: .radialGradient(Gradient(colors: [tissue.opacity(0.95), tissue.opacity(0.75)]),
                                                center: BrainGeometry.map(CGPoint(x: 0.42, y: 0.32), rect), startRadius: 0, endRadius: rect.width * 0.55))
        ctx.stroke(cortex, with: .color(tissueEdge.opacity(0.8)), lineWidth: 2)
        ctx.stroke(BrainGeometry.sulciPath(in: rect), with: .color(tissueEdge.opacity(0.45)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

        // Lobe names, faint, when zoomed in a little.
        if zoom >= 1.2 {
            for l in BrainLobe.allCases {
                let label = l.rawValue < folders.count ? folders[l.rawValue] : (l == .cerebellum ? "Databases" : l.name)
                ctx.draw(Text(label.uppercased()).font(.system(size: 9, weight: .heavy, design: .rounded)).foregroundColor(l.color.opacity(0.55)),
                         at: CGPoint(x: BrainGeometry.map(l.center, rect).x, y: BrainGeometry.map(l.center, rect).y - 0.13 * rect.height))
            }
        }

        guard !nodes.isEmpty else { return }
        let hot = neighbors
        let anySelection = selected != nil

        // Connections: curved like axons, brighter for real links.
        for (k, e) in shownEdges.enumerated() {
            guard e.a < nodes.count, e.b < nodes.count else { continue }
            let p = screen(e.a, rect), q = screen(e.b, rect)
            let mid = CGPoint(x: (p.x + q.x) / 2 + (q.y - p.y) * 0.18, y: (p.y + q.y) / 2 - (q.x - p.x) * 0.18)
            var path = Path(); path.move(to: p); path.addQuadCurve(to: q, control: mid)
            let lit = anySelection && (e.a == selected || e.b == selected)
            let dim = (anySelection && !lit) || (lobeFilter != nil && nodes[e.a].lobe != lobeFilter && nodes[e.b].lobe != lobeFilter)
            let color = lit ? Color.white : (dark ? Color.white : Color(red: 0.55, green: 0.2, blue: 0.35))
            ctx.stroke(path, with: .color(color.opacity(dim ? 0.07 : (e.strong ? 0.5 : 0.22))),
                       style: StrokeStyle(lineWidth: lit ? 2.4 : (e.strong ? 1.4 : 0.8), lineCap: .round, dash: e.strong ? [] : [3, 3]))
            // A signal travelling along each real link.
            if e.strong && !reduceMotion && !dim && k < 160 {
                let t = (time * 0.35 + Double(k) * 0.137).truncatingRemainder(dividingBy: 1)
                let x = (1 - t) * (1 - t) * p.x + 2 * (1 - t) * t * mid.x + t * t * q.x
                let y = (1 - t) * (1 - t) * p.y + 2 * (1 - t) * t * mid.y + t * t * q.y
                var spark = ctx
                spark.addFilter(.shadow(color: .white, radius: 4))
                spark.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)), with: .color(.white.opacity(lit ? 1 : 0.85)))
            }
        }

        // Neurons: glowing cells, bigger the more they connect.
        for i in nodes.indices {
            let n = nodes[i]
            let c = screen(i, rect)
            let lobeColor = BrainLobe(rawValue: n.lobe)?.color ?? DS.Palette.accent
            let isSel = selected == i, isHot = hot.contains(i)
            let dim = (anySelection && !isSel && !isHot) || (lobeFilter != nil && n.lobe != lobeFilter)
            let r = (4 + min(9, Double(n.degree) * 1.4)) * Double(min(zoom, 2.2)) * (isSel ? 1.5 : 1)
            let pulse = reduceMotion ? 1 : 1 + 0.12 * sin(time * 2 + Double(i))
            var g = ctx
            if !dim { g.addFilter(.shadow(color: lobeColor.opacity(0.9), radius: isSel ? 14 : 7)) }
            g.fill(Path(ellipseIn: CGRect(x: c.x - r * pulse, y: c.y - r * pulse, width: 2 * r * pulse, height: 2 * r * pulse)),
                   with: .color(lobeColor.opacity(dim ? 0.18 : 0.95)))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.4, y: c.y - r * 0.4, width: r * 0.8, height: r * 0.8)), with: .color(.white.opacity(dim ? 0.1 : 0.8)))
            let showLabel = isSel || isHot || (!anySelection && (n.degree >= 3 || zoom >= 1.8)) || (!find.isEmpty && n.title.localizedCaseInsensitiveContains(find))
            if showLabel && !dim {
                ctx.draw(Text(n.title.isEmpty ? "Untitled" : n.title)
                            .font(.system(size: isSel ? 13 : 11, weight: isSel ? .bold : .semibold, design: .rounded))
                            .foregroundColor(dark ? .white : Color(red: 0.25, green: 0.1, blue: 0.18)),
                         at: CGPoint(x: c.x, y: c.y + r + 9))
            }
        }
    }

    // MARK: Controls

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(DS.Palette.inkSoft)
                TextField("Find a note", text: $find).submitLabel(.search).onSubmit(focusFind)
                if !find.isEmpty { Button { find = "" } label: { Image(systemName: "xmark.circle.fill") }.foregroundStyle(DS.Palette.inkSoft).accessibilityLabel("Clear") }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(BrainLobe.allCases, id: \.rawValue) { l in
                        let name: String? = l.rawValue < folders.count ? folders[l.rawValue] : (l == .cerebellum ? "Databases" : nil)
                        if let name {
                            let on = lobeFilter == l.rawValue
                            Button { withAnimation { lobeFilter = on ? nil : l.rawValue }; Haptics.tap() } label: {
                                HStack(spacing: 5) {
                                    Circle().fill(l.color).frame(width: 8, height: 8)
                                    Text(name).font(.caption.weight(.semibold))
                                    Text(l.name).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(on ? AnyShapeStyle(l.color.opacity(0.25)) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
            }
            if !building && nodes.count >= 2 {
                Text("\(nodes.count) neurons · \(edges.filter(\.strong).count) connections" + (mostConnected.map { " · busiest: \($0)" } ?? ""))
                    .font(.caption2).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
            }
        }
        .padding(.horizontal).padding(.top, 6)
    }

    private var mostConnected: String? {
        nodes.max { $0.degree < $1.degree }.flatMap { $0.degree >= 2 ? ($0.title.isEmpty ? "Untitled" : $0.title) : nil }
    }

    private func detailCard(_ i: Int) -> some View {
        let n = nodes[i]
        let linked = neighbors.sorted().map { nodes[$0] }
        let lobe = BrainLobe(rawValue: n.lobe) ?? .frontal
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(spacing: DS.Space.m) {
                Text(n.icon).font(.title2)
                    .frame(width: 44, height: 44).background(lobe.color.opacity(0.18), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(n.title.isEmpty ? "Untitled" : n.title).font(DS.Font.headline).lineLimit(2)
                    Text("\(lobe.name) lobe · \(linked.count) connection\(linked.count == 1 ? "" : "s")").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                Spacer()
                Button { withAnimation { selected = nil } } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                    .foregroundStyle(DS.Palette.inkSoft).accessibilityLabel("Close")
            }
            if !linked.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(linked) { m in
                            Button { if let j = nodes.firstIndex(where: { $0.id == m.id }) { withAnimation { selected = j } } } label: {
                                Text("\(m.icon) \(m.title.isEmpty ? "Untitled" : m.title)").font(.caption).lineLimit(1)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background((BrainLobe(rawValue: m.lobe)?.color ?? .gray).opacity(0.15), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Button {
                opened = allNotes.first { $0.id == n.id }
            } label: { Label("Open page", systemImage: "arrow.up.right").frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent).tint(lobe.color)
        }
        .padding(DS.Space.m)
        .background(.regularMaterial, in: .rect(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
        .padding()
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: Actions

    private func tap(_ location: CGPoint, rect: CGRect) {
        var best: (Int, CGFloat)?
        for i in nodes.indices {
            let p = screen(i, rect)
            let d = hypot(p.x - location.x, p.y - location.y)
            if d < 26, d < (best?.1 ?? .infinity) { best = (i, d) }
        }
        withAnimation(.spring(duration: 0.35)) { selected = best?.0 }
        if best != nil { Haptics.tap() }
    }

    private func focusFind() {
        guard !find.isEmpty, let i = nodes.firstIndex(where: { $0.title.localizedCaseInsensitiveContains(find) }) else { return }
        withAnimation(.spring) {
            selected = i
            zoom = 2; zoomBase = 2
            // Bring it to the middle.
            let p = nodes[i].pos
            pan = CGSize(width: (0.5 - p.x) * 2 * 300, height: (0.5 - p.y) * 2 * 230)
            panBase = pan
        }
    }

    /// Reads the notes (on the main thread), then lays them out in the background.
    private func build() async {
        building = true
        let notes = allNotes.filter { !$0.isTemplate }.sorted { $0.updatedAt > $1.updatedAt }.prefix(220)
        let index = Dictionary(uniqueKeysWithValues: notes.enumerated().map { ($1.id, $0) })
        let byTitle = Dictionary(notes.enumerated().compactMap { i, n in n.title.isEmpty ? nil : (n.title.lowercased(), i) }, uniquingKeysWith: { a, _ in a })

        // Folders by size become lobes; the cerebellum holds databases.
        let folderCounts = Dictionary(grouping: notes.compactMap(\.folder), by: { $0 }).mapValues(\.count)
        let topFolders = folderCounts.sorted { $0.value > $1.value }.map(\.key).prefix(4)
        let lobeOf: [String: Int] = Dictionary(uniqueKeysWithValues: topFolders.enumerated().map { ($1, $0) })

        var edgeSet = Set<BrainEdge>()
        var list: [BrainNode] = []
        for (i, n) in notes.enumerated() {
            let lobe: Int
            if n.isDatabase || (n.parentId.flatMap { p in notes.first { $0.id == p }?.isDatabase } ?? false) { lobe = BrainLobe.cerebellum.rawValue }
            else if let f = n.folder, let l = lobeOf[f] { lobe = l }
            else { lobe = Int(n.id.uuid.0) % 4 }        // unfiled pages spread across the cortex, the same way every time
            list.append(BrainNode(id: n.id, title: n.title, icon: n.icon ?? (n.isDatabase ? "🗃️" : "📄"), lobe: lobe, degree: 0, pos: .zero))

            func add(_ j: Int, strong: Bool) {
                guard j != i else { return }
                let e = BrainEdge(a: min(i, j), b: max(i, j), strong: strong)
                if strong { edgeSet.remove(BrainEdge(a: e.a, b: e.b, strong: false)) }
                if !edgeSet.contains(BrainEdge(a: e.a, b: e.b, strong: true)) { edgeSet.insert(e) }
            }
            if let p = n.parentId, let j = index[p] { add(j, strong: false) }
            guard !n.isLocked else { continue }
            let text = n.plainText
            for t in NoteLinksSection.linkTitles(in: text) { if let j = byTitle[t.lowercased()] { add(j, strong: true) } }
            for b in n.blocks where b.kind == .page { if let r = b.refId, let id = UUID(uuidString: r), let j = index[id] { add(j, strong: true) } }
            if text.contains("://note/") {
                for (id, j) in index where text.contains(id.uuidString) { add(j, strong: true) }
            }
        }
        let edges = Array(edgeSet)
        for e in edges { list[e.a].degree += 1; list[e.b].degree += 1 }
        let laid = await Task.detached(priority: .userInitiated) { BrainLayout.run(list, edges) }.value
        withAnimation(.easeOut(duration: 0.6)) {
            self.nodes = laid
            self.edges = edges
            self.folders = Array(topFolders)
            self.building = false
            self.selected = nil
        }
    }
}
