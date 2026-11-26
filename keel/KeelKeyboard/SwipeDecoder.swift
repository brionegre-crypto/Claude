import UIKit

/// Slide to type: turns the path your finger drew across the letters into the most likely word.
/// Compares the path's shape with each candidate word's ideal path (key centre to key centre), keeps only words
/// whose letters the path actually passes near, and leans towards common words. Candidates share the first and
/// last keys, so the word list (most common first, built from the system dictionary) only needs to rank words
/// against others that start the same way.
final class SwipeDecoder {
    static let shared = SwipeDecoder()

    private var byFirst: [Character: [(word: String, rank: Int)]] = [:]
    private var loaded = false

    private func load() {
        guard !loaded else { return }
        guard let url = Bundle(for: SwipeDecoder.self).url(forResource: "words-en", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { loaded = true; return }
        use(text)
    }

    /// The word list (one per line, most common first). The bundled list is used unless a test supplies one.
    func use(_ text: String) {
        loaded = true
        byFirst = [:]
        for (rank, line) in text.split(separator: "\n").enumerated() {
            let w = String(line)
            guard let f = w.lowercased().first, w.count >= 1 else { continue }
            byFirst[f, default: []].append((w, rank))
        }
    }

    /// The best words for `path` (best first), or [] if nothing fits.
    /// `centre(c)` gives a letter key's centre; `keyWidth` scales distances.
    func decode(path: [CGPoint], centre: (Character) -> CGPoint?, nearest: (CGPoint, Int) -> [Character], keyWidth: CGFloat, limit: Int = 3) -> [String] {
        load()
        guard path.count >= 3, let start = path.first, let end = path.last else { return [] }
        let starts = Set(nearest(start, 2)), ends = Set(nearest(end, 3))
        let sample = Self.resample(path, 32)
        let pathLength = Self.length(path)
        var scored: [(String, Double)] = []
        for s in starts {
            for (word, rank) in byFirst[s] ?? [] {
                let lw = word.lowercased().filter(\.isLetter)
                guard lw.count >= 2, let last = lw.last, ends.contains(last) else { continue }
                // Consecutive repeated letters are one key ("hello" → h e l o).
                var keys: [CGPoint] = []
                var prev: Character?
                var ok = true
                for ch in lw where ch != prev {
                    guard let c = centre(ch) else { ok = false; break }
                    keys.append(c); prev = ch
                }
                guard ok, keys.count >= 2, passesNear(path, keys, keyWidth) else { continue }
                let ideal = Self.resample(keys, 32)
                var d: CGFloat = 0
                for i in 0..<32 { d += hypot(ideal[i].x - sample[i].x, ideal[i].y - sample[i].y) }
                let shape = Double(d / 32 / keyWidth)
                let lengthGap = Double(abs(Self.length(keys) - pathLength) / keyWidth) * 0.12     // a long slide isn't a short word
                let prior = 0.08 * log(Double(rank) + 2)            // common words win close calls
                scored.append((word, shape + lengthGap + prior))
            }
        }
        var seen = Set<String>()
        return scored.sorted { $0.1 < $1.1 }.map(\.0).filter { seen.insert($0.lowercased()).inserted }.prefix(limit).map { $0 }
    }

    /// Every letter of the word must be passed near, in order: each letter takes the first stretch of path that
    /// comes close to it (its closest point there), and the next letter is looked for after that.
    private func passesNear(_ path: [CGPoint], _ keys: [CGPoint], _ kw: CGFloat) -> Bool {
        var i = 0
        let limit = kw * 1.0
        for k in keys {
            var j = i
            while j < path.count && hypot(path[j].x - k.x, path[j].y - k.y) > limit { j += 1 }
            guard j < path.count else { return false }
            var best = hypot(path[j].x - k.x, path[j].y - k.y)
            while j + 1 < path.count {
                let d = hypot(path[j + 1].x - k.x, path[j + 1].y - k.y)
                if d > best || d > limit { break }
                best = d; j += 1
            }
            i = j
        }
        return true
    }

    private static func length(_ pts: [CGPoint]) -> CGFloat {
        guard pts.count > 1 else { return 0 }
        var t: CGFloat = 0
        for i in 1..<pts.count { t += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y) }
        return t
    }

    /// `n` points evenly spaced along the line through `pts`.
    static func resample(_ pts: [CGPoint], _ n: Int) -> [CGPoint] {
        guard pts.count > 1 else { return Array(repeating: pts.first ?? .zero, count: n) }
        var total: CGFloat = 0
        for i in 1..<pts.count { total += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y) }
        guard total > 0 else { return Array(repeating: pts[0], count: n) }
        let step = total / CGFloat(n - 1)
        var out = [pts[0]]
        var acc: CGFloat = 0
        var i = 1
        var a = pts[0]
        while out.count < n - 1 && i < pts.count {
            let b = pts[i]
            let seg = hypot(b.x - a.x, b.y - a.y)
            if acc + seg >= step && seg > 0 {
                let t = (step - acc) / seg
                let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                out.append(p); a = p; acc = 0
            } else { acc += seg; a = b; i += 1 }
        }
        while out.count < n { out.append(pts[pts.count - 1]) }
        return out
    }
}
