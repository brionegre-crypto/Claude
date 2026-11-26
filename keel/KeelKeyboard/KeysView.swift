import UIKit

/// The keys, built to Apple's keyboard (iOS 26/27, measured from the system keyboard): white rounded keys 43 pt
/// tall, 6 pt apart, 11 pt between rows, shift and delete 45 pt, "123" and return a quarter of the width.
/// Press shows the letter above your finger; it types on release (slide to a neighbour first and that one types).
/// Slide across letters to type a word. Hold a letter for accents, hold space to move the cursor, hold delete.
final class KeysView: UIView {
    enum Kind: Equatable { case char(String), shift, delete, mode(Page), space, ret, globe }
    enum Page: Equatable { case letters, numbers, symbols }
    enum Shift { case off, once, locked }

    struct Key { let kind: Kind; var frame: CGRect; let view: UIView; let label: UILabel; let icon: UIImageView }

    // Callbacks to the controller
    var onType: ((String) -> Void)?
    var onPunctuation: ((String) -> Void)?
    var onSpace: (() -> Void)?
    var onReturn: (() -> Void)?
    var onDelete: (() -> Void)?
    var onDeleteWord: (() -> Void)?
    var onSwipe: (([CGPoint], KeysView) -> Void)?
    var onMoveCursor: ((Int) -> Void)?
    var onGlobe: ((UIView, UIEvent?) -> Void)?
    var atSentenceStart: () -> Bool = { true }

    var showsGlobe = false { didSet { if oldValue != showsGlobe { rebuild() } } }
    var returnTitle: String? { didSet { rebuild() } }        // nil = the return arrow
    var returnIsBlue = false { didSet { rebuild() } }
    private(set) var page: Page = .letters
    private(set) var shift: Shift = .off
    private var lastShiftTap = Date.distantPast
    private var keys: [Key] = []

    // Measured from the system keyboard (points).
    private let keyH: CGFloat = 43, rowGap: CGFloat = 11, gap: CGFloat = 6, side: CGFloat = 6, top: CGFloat = 8, radius: CGFloat = 8.5
    static let height: CGFloat = 8 + 43 * 4 + 11 * 3 + 6

    private let popup = KeyPopup()
    private let trail = CAShapeLayer()
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private static let letters: [[String]] = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { $0.map { String($0) } }
    private static let numbers: [[String]] = [Array("1234567890").map(String.init), ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""], [".", ",", "?", "!", "'"]]
    private static let symbols: [[String]] = [["[", "]", "{", "}", "#", "%", "^", "*", "+", "="], ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"], [".", ",", "?", "!", "'"]]
    static let accents: [String: [String]] = [
        "a": ["à", "á", "â", "ä", "æ", "ã", "å", "ā"], "e": ["è", "é", "ê", "ë", "ē", "ė", "ę"], "i": ["î", "ï", "í", "ī", "į", "ì"],
        "o": ["ô", "ö", "ò", "ó", "œ", "ø", "ō", "õ"], "u": ["û", "ü", "ù", "ú", "ū"], "n": ["ñ", "ń"], "c": ["ç", "ć", "č"],
        "s": ["ß", "ś", "š"], "y": ["ÿ"], "z": ["ž", "ź", "ż"], "l": ["ł"],
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        clipsToBounds = false                 // the top row's popups rise into the bar above
        // Apple's slide-to-type trail: a soft neutral stroke (grey on the light keyboard, white on the dark one),
        // only the last stretch of the path, fading away when you lift.
        trail.strokeColor = Self.trailColor.resolvedColor(with: traitCollection).cgColor
        trail.fillColor = nil
        trail.lineWidth = 7
        trail.lineCap = .round
        trail.lineJoin = .round
        layer.addSublayer(trail)
        addSubview(popup)
        popup.isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        if keys.isEmpty || keys.first.map({ abs($0.frame.minX - side) > 0.5 }) == true || lastWidth != bounds.width { rebuild() }
    }
    private var lastWidth: CGFloat = 0

    // MARK: Layout

    func setPage(_ p: Page) { page = p; rebuild() }
    func autoShift() {
        guard page == .letters, shift != .locked else { return }
        let s: Shift = atSentenceStart() ? .once : .off
        if s != shift { shift = s; refreshLabels(); buildAccessibility() }
    }

    private func rebuild() {
        keys.forEach { $0.view.removeFromSuperview() }
        keys = []
        let W = bounds.width
        guard W > 0 else { return }
        lastWidth = W
        let keyW = (W - 2 * side - 9 * gap) / 10
        let rows: [[String]] = page == .letters ? Self.letters : page == .numbers ? Self.numbers : Self.symbols
        var y = top
        // Row 1: ten keys
        var x = side
        for c in rows[0] { add(.char(c), CGRect(x: x, y: y, width: keyW, height: keyH)); x += keyW + gap }
        y += keyH + rowGap
        // Row 2: nine letters, centred (numbers and symbols: ten)
        if rows[1].count == 9 {
            x = side + (keyW + gap) / 2
            for c in rows[1] { add(.char(c), CGRect(x: x, y: y, width: keyW, height: keyH)); x += keyW + gap }
        } else {
            x = side
            for c in rows[1] { add(.char(c), CGRect(x: x, y: y, width: keyW, height: keyH)); x += keyW + gap }
        }
        y += keyH + rowGap
        // Row 3: shift (or #+= / 123), the letters, delete
        let sideKey: CGFloat = 45
        add(page == .letters ? .shift : .mode(page == .numbers ? .symbols : .numbers), CGRect(x: side, y: y, width: sideKey, height: keyH))
        add(.delete, CGRect(x: W - side - sideKey, y: y, width: sideKey, height: keyH))
        let middle = W - 2 * side - 2 * sideKey
        if page == .letters {
            let span = CGFloat(rows[2].count) * keyW + CGFloat(rows[2].count - 1) * gap
            x = side + sideKey + (middle - span) / 2
            for c in rows[2] { add(.char(c), CGRect(x: x, y: y, width: keyW, height: keyH)); x += keyW + gap }
        } else {
            let inner = middle - 2 * 13.7
            let w5 = (inner - 4 * gap) / 5
            x = side + sideKey + 13.7
            for c in rows[2] { add(.char(c), CGRect(x: x, y: y, width: w5, height: keyH)); x += w5 + gap }
        }
        y += keyH + rowGap
        // Row 4: 123 / ABC, (globe), space, return
        let quarter = (W - 2 * side - 2 * gap) * 0.2385
        x = side
        let modeW = showsGlobe ? (quarter - gap) / 2 : quarter
        add(.mode(page == .letters ? .numbers : .letters), CGRect(x: x, y: y, width: modeW, height: keyH)); x += modeW + gap
        if showsGlobe { add(.globe, CGRect(x: x, y: y, width: modeW, height: keyH)); x += modeW + gap }
        let spaceW = W - side - quarter - gap - x
        add(.space, CGRect(x: x, y: y, width: spaceW, height: keyH))
        add(.ret, CGRect(x: W - side - quarter, y: y, width: quarter, height: keyH))
        refreshLabels()
        bringSubviewToFront(popup)
        buildAccessibility()
    }

    /// Each key is a VoiceOver key (and findable by UI tests), named like Apple's.
    private func buildAccessibility() {
        accessibilityElements = keys.map { k in
            let e = KeyElement(accessibilityContainer: self)
            e.accessibilityFrameInContainerSpace = k.frame
            e.accessibilityTraits = .keyboardKey
            switch k.kind {
            case .char(let c): e.accessibilityLabel = page == .letters && shift != .off ? c.uppercased() : c
            case .shift: e.accessibilityLabel = "shift"; e.accessibilityValue = shift == .locked ? "caps lock" : shift == .once ? "on" : nil
            case .delete: e.accessibilityLabel = "delete"
            case .mode(let p): e.accessibilityLabel = p == .letters ? "letters" : p == .numbers ? "numbers" : "symbols"
            case .space: e.accessibilityLabel = "space"
            case .ret: e.accessibilityLabel = returnTitle ?? "return"
            case .globe: e.accessibilityLabel = "Next keyboard"
            }
            let kind = k.kind
            e.activate = { [weak self] in self?.activate(kind) }
            return e
        }
    }

    /// VoiceOver double-tap: the same as tapping the key.
    private func activate(_ kind: Kind) {
        switch kind {
        case .char(let c):
            let s = page == .letters && shift != .off ? c.uppercased() : c
            if [".", ",", "?", "!"].contains(s) { onPunctuation?(s) } else { onType?(s) }
            if page == .letters { afterLetter() }
        case .shift: shift = shift == .off ? .once : .off; refreshLabels(); buildAccessibility()
        case .delete: onDelete?()
        case .mode(let p): setPage(p)
        case .space: onSpace?(); autoShift()
        case .ret: onReturn?()
        case .globe: break
        }
    }

    private func add(_ kind: Kind, _ frame: CGRect) {
        let v = UIView(frame: frame)
        v.layer.cornerRadius = radius
        v.layer.cornerCurve = .continuous
        v.isUserInteractionEnabled = false
        let l = UILabel(frame: v.bounds)
        l.textAlignment = .center
        l.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let i = UIImageView(frame: v.bounds)
        i.contentMode = .center
        i.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        v.addSubview(l); v.addSubview(i)
        addSubview(v)
        keys.append(Key(kind: kind, frame: frame, view: v, label: l, icon: i))
    }

    /// Colours and labels, per light/dark mode, shift and page.
    private func refreshLabels() {
        let dark = traitCollection.userInterfaceStyle == .dark
        let keyColor = dark ? UIColor(white: 1, alpha: 0.30) : .white
        let ink: UIColor = dark ? .white : .black
        let sym = UIImage.SymbolConfiguration(pointSize: 19, weight: .regular)
        for k in keys {
            k.view.backgroundColor = keyColor
            k.label.textColor = ink
            k.icon.tintColor = ink
            k.label.text = nil; k.icon.image = nil
            switch k.kind {
            case .char(let c):
                k.label.font = .systemFont(ofSize: page == .letters ? 25 : 24, weight: .regular)
                k.label.text = page == .letters && shift != .off ? c.uppercased() : c
            case .shift:
                k.icon.image = UIImage(systemName: shift == .locked ? "capslock.fill" : shift == .once ? "shift.fill" : "shift", withConfiguration: sym)
            case .delete:
                k.icon.image = UIImage(systemName: "delete.left", withConfiguration: sym)
            case .mode(let p):
                k.label.font = .systemFont(ofSize: 17, weight: .regular)
                k.label.text = p == .letters ? "ABC" : p == .numbers ? "123" : "#+="
            case .space:
                k.label.text = nil                              // iOS 26/27: the space bar is blank
            case .ret:
                if let t = returnTitle { k.label.font = .systemFont(ofSize: 17, weight: .regular); k.label.text = t }
                else { k.icon.image = UIImage(systemName: "return", withConfiguration: sym) }
                if returnIsBlue { k.view.backgroundColor = .systemBlue; k.label.textColor = .white; k.icon.tintColor = .white }
            case .globe:
                k.icon.image = UIImage(systemName: "globe", withConfiguration: sym)
            }
        }
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        refreshLabels()
        trail.strokeColor = Self.trailColor.resolvedColor(with: traitCollection).cgColor
    }

    // MARK: Finding keys

    private func key(at p: CGPoint) -> Key? {
        if let k = keys.first(where: { $0.frame.insetBy(dx: -gap / 2, dy: -rowGap / 2).contains(p) }) { return k }
        return keys.min { dist($0.frame, p) < dist($1.frame, p) }
    }
    private func dist(_ r: CGRect, _ p: CGPoint) -> CGFloat { hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY)) }

    var keyWidth: CGFloat { (bounds.width - 2 * side - 9 * gap) / 10 }
    func centre(of c: Character) -> CGPoint? {
        keys.first { if case .char(let s) = $0.kind { return s.lowercased() == String(c).lowercased() }; return false }.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) }
    }
    func nearestLetters(_ p: CGPoint, _ n: Int) -> [Character] {
        keys.compactMap { k -> (Character, CGFloat)? in
            if case .char(let s) = k.kind, let c = s.first, c.isLetter { return (c, hypot(k.frame.midX - p.x, k.frame.midY - p.y)) }
            return nil
        }.sorted { $0.1 < $1.1 }.prefix(n).map(\.0)
    }

    // MARK: Touches

    private final class Track {
        var key: Key; let start: CGPoint; var path: [CGPoint]; var swiping = false
        var accents: [String]? ; var accentIndex = 0
        var trackpad = false; var trackpadX: CGFloat = 0
        var timer: Timer?; var repeats = 0
        init(key: Key, start: CGPoint) { self.key = key; self.start = start; self.path = [start] }
    }
    private var tracks: [ObjectIdentifier: Track] = [:]

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let p = t.location(in: self)
            guard let k = key(at: p) else { continue }
            // A new tap finishes any other finger's pending letter first (fast typing rolls over).
            for (id, other) in tracks where other.timer == nil && !other.swiping && other.accents == nil && !other.trackpad {
                release(other); tracks[id] = nil
            }
            let tr = Track(key: k, start: p)
            tracks[ObjectIdentifier(t)] = tr
            haptic.impactOccurred(intensity: 0.6)
            UIDevice.current.playInputClick()
            highlight(k, true)
            switch k.kind {
            case .char(let c):
                popup.show(over: k.frame, text: k.label.text ?? c, in: self)
                if let acc = Self.accents[c.lowercased()] {
                    tr.timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self, weak tr] _ in
                        MainActor.assumeIsolated { guard let self, let tr, !tr.swiping else { return }; self.openAccents(tr, acc) }
                    }
                }
            case .shift:
                if shift == .off { shift = Date().timeIntervalSince(lastShiftTap) < 0.35 ? .locked : .once }
                else if shift == .once && Date().timeIntervalSince(lastShiftTap) < 0.35 { shift = .locked }
                else { shift = .off }
                lastShiftTap = Date()
                refreshLabels(); buildAccessibility()
            case .delete:
                onDelete?()
                tr.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self, weak tr] _ in
                    MainActor.assumeIsolated { guard let self, let tr else { return }; self.startRepeat(tr) }
                }
            case .space:
                tr.timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self, weak tr] _ in
                    MainActor.assumeIsolated { guard let self, let tr else { return }; tr.trackpad = true; tr.trackpadX = tr.path.last?.x ?? 0; self.setTrackpad(true) }
                }
            case .globe:
                onGlobe?(k.view, event)
            default: break
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            guard let tr = tracks[ObjectIdentifier(t)] else { continue }
            let p = t.location(in: self)
            tr.path.append(p)
            if tr.trackpad {
                let step = keyWidth * 0.55
                let dx = p.x - tr.trackpadX
                if abs(dx) >= step { let n = Int(dx / step); onMoveCursor?(n); tr.trackpadX += CGFloat(n) * step; UIDevice.current.playInputClick() }
                continue
            }
            if let acc = tr.accents { tr.accentIndex = popup.accentIndex(at: convert(p, to: popup), count: acc.count); continue }
            guard case .char = tr.key.kind else { continue }
            // Slide to type: far enough across the letters, on the letters page.
            if !tr.swiping, page == .letters, hypot(p.x - tr.start.x, p.y - tr.start.y) > keyWidth * 1.15 {
                tr.swiping = true
                trail.removeAnimation(forKey: "fade")
                tr.timer?.invalidate(); tr.timer = nil
                popup.isHidden = true
                highlight(tr.key, false)
            }
            if tr.swiping {
                let path = UIBezierPath()
                let pts = tr.path.suffix(28)
                if let f = pts.first { path.move(to: f); pts.dropFirst().forEach { path.addLine(to: $0) } }
                trail.path = path.cgPath
            } else if let k = key(at: p), k.frame != tr.key.frame {
                // Before a swipe starts, sliding onto a neighbour changes which letter types (as on Apple's keyboard).
                highlight(tr.key, false); tr.key = k; highlight(k, true)
                if case .char(let c) = k.kind { popup.show(over: k.frame, text: k.label.text ?? c, in: self) } else { popup.isHidden = true }
                tr.timer?.invalidate(); tr.timer = nil
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            guard let tr = tracks.removeValue(forKey: ObjectIdentifier(t)) else { continue }
            release(tr)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            guard let tr = tracks.removeValue(forKey: ObjectIdentifier(t)) else { continue }
            tr.timer?.invalidate()
            highlight(tr.key, false); popup.isHidden = true; trail.path = nil
            if tr.trackpad { setTrackpad(false) }
        }
    }

    static let trailColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.42) : UIColor(white: 0.25, alpha: 0.26) }

    private func fadeTrail() {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0; fade.duration = 0.18
        fade.fillMode = .forwards; fade.isRemovedOnCompletion = false
        trail.add(fade, forKey: "fade")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.tracks.values.allSatisfy({ !$0.swiping }) else { return }
            self.trail.path = nil
            self.trail.removeAnimation(forKey: "fade")
        }
    }

    private func release(_ tr: Track) {
        tr.timer?.invalidate(); tr.timer = nil
        highlight(tr.key, false)
        popup.isHidden = true
        if tr.trackpad { setTrackpad(false); return }
        if tr.swiping {
            fadeTrail()
            onSwipe?(tr.path, self)
            if shift == .once { shift = .off; refreshLabels() }
            return
        }
        if let acc = tr.accents {
            popup.closeAccents()
            let s = acc[min(max(tr.accentIndex, 0), acc.count - 1)]
            onType?(shift != .off ? s.uppercased() : s)
            afterLetter()
            return
        }
        switch tr.key.kind {
        case .char(let c):
            let s = page == .letters && shift != .off ? c.uppercased() : c
            if [".", ",", "?", "!"].contains(s) { onPunctuation?(s) } else { onType?(s) }
            if page == .letters { afterLetter() }
            else if s == "'" { setPage(.letters) }                  // like Apple: apostrophe goes back to letters
        case .space:
            onSpace?()
            if page != .letters { setPage(.letters) }
            autoShift()
        case .ret: onReturn?(); autoShift()
        case .mode(let p): setPage(p); if p == .letters { autoShift() }
        case .delete: autoShift()
        default: break
        }
    }

    private func afterLetter() {
        if shift == .once { shift = .off; refreshLabels(); buildAccessibility() }
    }

    private func startRepeat(_ tr: Track) {
        tr.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self, weak tr] _ in
            MainActor.assumeIsolated {
                guard let self, let tr else { return }
                tr.repeats += 1
                if tr.repeats > 12 { self.onDeleteWord?() } else { self.onDelete?() }       // speeds up to whole words
            }
        }
    }

    private func openAccents(_ tr: Track, _ acc: [String]) {
        let list = shift != .off ? acc.map { $0.uppercased() } : acc
        tr.accents = list
        popup.openAccents(list, over: tr.key.frame, in: self)
        haptic.impactOccurred(intensity: 0.8)
    }

    private func highlight(_ k: Key, _ on: Bool) {
        let dark = traitCollection.userInterfaceStyle == .dark
        if case .char = k.kind { return }                            // letters show the popup instead
        if case .ret = k.kind, returnIsBlue { k.view.alpha = on ? 0.7 : 1; return }
        k.view.backgroundColor = on ? (dark ? UIColor(white: 1, alpha: 0.5) : UIColor(white: 0.82, alpha: 1)) : (dark ? UIColor(white: 1, alpha: 0.30) : .white)
    }

    /// Hold space: the keys go blank and the keyboard becomes a trackpad for the cursor (like Apple's).
    private func setTrackpad(_ on: Bool) {
        UIView.animate(withDuration: 0.15) { self.keys.forEach { $0.label.alpha = on ? 0 : 1; $0.icon.alpha = on ? 0 : 1 } }
        if on { haptic.impactOccurred(intensity: 0.8) }
    }
}

/// The letter that pops up above your finger, and the accent menu.
final class KeyPopup: UIView {
    private let label = UILabel()
    private var accentLabels: [UILabel] = []
    private let shape = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.addSublayer(shape)
        shape.shadowColor = UIColor.black.cgColor
        shape.shadowOpacity = 0.25
        shape.shadowRadius = 3
        shape.shadowOffset = CGSize(width: 0, height: 1)
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 36, weight: .regular)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var fill: UIColor { traitCollection.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white }

    /// The balloon: the key widened above it, joined to the key.
    func show(over key: CGRect, text: String, in host: UIView) {
        closeAccents()
        let w = key.width + 20, h = key.height * 2.25
        let x = max(0, min(host.bounds.width - w, key.midX - w / 2))
        frame = CGRect(x: x, y: key.maxY - h, width: w, height: h)
        let k = CGRect(x: key.minX - x, y: h - key.height, width: key.width, height: key.height)
        let top = CGRect(x: 0, y: 0, width: w, height: h - key.height - 6)
        let p = UIBezierPath(roundedRect: top, cornerRadius: 10)
        p.append(UIBezierPath(roundedRect: k.insetBy(dx: 0, dy: 0), cornerRadius: 8.5))
        p.append(UIBezierPath(rect: CGRect(x: k.minX, y: top.maxY - 10, width: k.width, height: k.minY - top.maxY + 20)))
        shape.path = p.cgPath
        shape.fillColor = fill.cgColor
        label.frame = top
        label.textColor = traitCollection.userInterfaceStyle == .dark ? .white : .black
        label.text = text
        isHidden = false
    }

    func openAccents(_ list: [String], over key: CGRect, in host: UIView) {
        closeAccents()
        label.text = nil
        let cell: CGFloat = 36, w = cell * CGFloat(list.count) + 12, h: CGFloat = 54
        let x = max(2, min(host.bounds.width - w - 2, key.midX - cell / 2 - 6))
        frame = CGRect(x: x, y: key.minY - h - 4, width: w, height: h + key.height + 4)
        let p = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: 10)
        p.append(UIBezierPath(roundedRect: CGRect(x: key.minX - x, y: h + 4, width: key.width, height: key.height), cornerRadius: 8.5))
        shape.path = p.cgPath
        shape.fillColor = fill.cgColor
        for (i, s) in list.enumerated() {
            let l = UILabel(frame: CGRect(x: 6 + CGFloat(i) * cell, y: 6, width: cell, height: h - 12))
            l.text = s; l.textAlignment = .center; l.font = .systemFont(ofSize: 24)
            l.layer.cornerRadius = 7; l.clipsToBounds = true
            addSubview(l); accentLabels.append(l)
        }
        highlightAccent(0)
        isHidden = false
    }

    func accentIndex(at p: CGPoint, count: Int) -> Int {
        let i = Int((p.x - 6) / 36)
        let c = min(max(i, 0), count - 1)
        highlightAccent(c)
        return c
    }

    private func highlightAccent(_ i: Int) {
        for (j, l) in accentLabels.enumerated() {
            l.backgroundColor = j == i ? .systemBlue : .clear
            l.textColor = j == i ? .white : (traitCollection.userInterfaceStyle == .dark ? .white : .black)
        }
    }

    func closeAccents() { accentLabels.forEach { $0.removeFromSuperview() }; accentLabels = [] }
}

/// A key for VoiceOver.
final class KeyElement: UIAccessibilityElement {
    var activate: (() -> Void)?
    override func accessibilityActivate() -> Bool { activate?(); return true }
}
