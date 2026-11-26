import UIKit

/// The writing help Apple's keyboard gives: suggestions for the word you're typing, autocorrect when you finish a
/// word (Delete straight after puts back what you typed), a period on double space, capitals at the start of a
/// sentence, and a space between words you slide.
@MainActor
final class TextAssist {
    weak var proxy: UITextDocumentProxy?
    private let checker = UITextChecker()
    private var language: String { (Locale.preferredLanguages.first ?? "en_US").replacingOccurrences(of: "-", with: "_") }

    /// The correction just made, so Delete right after can undo it.
    private var lastCorrection: (typed: String, corrected: String)?
    /// The last thing typed was a slid word (the next word, slid or tapped, gets a space first).
    private(set) var afterSwipe = false
    private var lastSpaceAt = Date.distantPast

    private var before: String { proxy?.documentContextBeforeInput ?? "" }

    /// The letters just before the cursor (the word being typed).
    var currentWord: String {
        var w = ""
        for ch in before.reversed() { if ch.isLetter || ch == "'" { w.insert(ch, at: w.startIndex) } else { break } }
        return w
    }

    var atSentenceStart: Bool {
        let b = before
        let t = b.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression)
        return t.isEmpty || b.hasSuffix("\n") || ((t.hasSuffix(".") || t.hasSuffix("?") || t.hasSuffix("!")) && b.hasSuffix(" "))
    }

    // MARK: Typing

    func type(_ s: String) {
        if afterSwipe, s.first?.isLetter == true, let last = before.last, !last.isWhitespace { proxy?.insertText(" ") }
        afterSwipe = false
        lastCorrection = nil
        proxy?.insertText(s)
    }

    /// Space: finish the word (autocorrect), or a period after a double space.
    func space() {
        afterSwipe = false
        let b = before
        if Date().timeIntervalSince(lastSpaceAt) < 0.45, b.hasSuffix(" "), let prev = b.dropLast().last, prev.isLetter || prev.isNumber {
            proxy?.deleteBackward(); proxy?.insertText(". ")
            lastSpaceAt = .distantPast; lastCorrection = nil
            return
        }
        lastSpaceAt = Date()
        autocorrect()
        proxy?.insertText(" ")
    }

    func newline() { afterSwipe = false; autocorrect(); proxy?.insertText("\n") }

    /// Punctuation finishes a word too (autocorrect first), like Apple's keyboard.
    func punctuation(_ s: String) {
        afterSwipe = false
        autocorrect()
        if (s == "." || s == "," || s == "?" || s == "!") && before.hasSuffix(" ") && lastSpaceWasOurs { proxy?.deleteBackward() }
        proxy?.insertText(s)
    }
    private var lastSpaceWasOurs: Bool { Date().timeIntervalSince(lastSpaceAt) < 3 }

    func delete() {
        afterSwipe = false
        if let c = lastCorrection, before.hasSuffix(c.corrected + " ") {
            for _ in 0..<(c.corrected.count + 1) { proxy?.deleteBackward() }
            proxy?.insertText(c.typed)                         // Delete straight after a correction undoes it
            lastCorrection = nil
            return
        }
        lastCorrection = nil
        proxy?.deleteBackward()
    }

    /// Hold Delete long enough and it goes a word at a time.
    func deleteWord() {
        afterSwipe = false; lastCorrection = nil
        let b = before
        var n = 0
        var seenLetter = false
        for ch in b.reversed() {
            if ch.isLetter || ch.isNumber { seenLetter = true; n += 1 } else if seenLetter { break } else { n += 1 }
        }
        for _ in 0..<max(1, n) { proxy?.deleteBackward() }
    }

    /// A slid word: a space before it if needed, capitalised at a sentence start.
    func insertSwiped(_ word: String, capitalise: Bool) {
        let b = before
        if let last = b.last, !last.isWhitespace, !"([{\"“".contains(last) { proxy?.insertText(" ") }
        let w = capitalise ? word.prefix(1).uppercased() + word.dropFirst() : word
        proxy?.insertText(w)
        afterSwipe = true
        lastCorrection = nil
    }

    /// Replace the slid word with another candidate (tapped in the bar).
    func replaceSwiped(_ old: String, with new: String) {
        guard before.hasSuffix(old) else { return }
        for _ in 0..<old.count { proxy?.deleteBackward() }
        proxy?.insertText(new)
    }

    /// A suggestion tapped in the bar: replaces the word being typed, then a space.
    func accept(_ suggestion: String) {
        let w = currentWord
        for _ in 0..<w.count { proxy?.deleteBackward() }
        proxy?.insertText(suggestion + " ")
        afterSwipe = false; lastCorrection = nil
    }

    // MARK: Suggestions and corrections

    /// Up to three: what you typed (quoted when it would be corrected), the correction, completions.
    func suggestions() -> [String] {
        let w = currentWord
        guard !w.isEmpty else { return [] }
        let ns = w as NSString
        var out: [String] = []
        if isMisspelled(w), let fix = correction(for: w) {
            out = ["“\(w)”", fix]
        }
        let completions = checker.completions(forPartialWordRange: NSRange(location: 0, length: ns.length), in: w, language: language) ?? []
        for c in completions where !out.contains(c) && c.lowercased() != w.lowercased() {
            out.append(matchCase(c, like: w))
            if out.count >= 3 { break }
        }
        if out.isEmpty || (!out.contains(w) && !isMisspelled(w)) { out.insert(w, at: 0) }
        return Array(out.prefix(3))
    }

    private func isMisspelled(_ w: String) -> Bool {
        guard w.count > 1, w.first?.isUppercase != true || w.count > 1 else { return false }
        let r = checker.rangeOfMisspelledWord(in: w, range: NSRange(location: 0, length: (w as NSString).length), startingAt: 0, wrap: false, language: language)
        return r.location != NSNotFound
    }

    /// A confident fix only: one letter off, or two transposed.
    private func correction(for w: String) -> String? {
        let guesses = checker.guesses(forWordRange: NSRange(location: 0, length: (w as NSString).length), in: w, language: language) ?? []
        return guesses.first { g in Self.distance(g.lowercased(), w.lowercased()) <= 1 }.map { matchCase($0, like: w) }
    }

    private func autocorrect() {
        let w = currentWord
        guard w.count >= 3, isMisspelled(w), let fix = correction(for: w), fix != w else { return }
        for _ in 0..<w.count { proxy?.deleteBackward() }
        proxy?.insertText(fix)
        lastCorrection = (w, fix)
    }

    private func matchCase(_ s: String, like w: String) -> String {
        if w.count > 1, w == w.uppercased() { return s.uppercased() }
        if w.first?.isUppercase == true { return s.prefix(1).uppercased() + s.dropFirst() }
        return s
    }

    /// Edit distance with transposition counted as one.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard abs(a.count - b.count) <= 2, !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1) }
            }
        }
        return d[a.count][b.count]
    }
}
