import Foundation
import Speech
import UIKit

/// "Keel, make this shorter": dictation that starts with Keel's name is an instruction, not words to type.
/// With text in the field it edits that text; in an empty field it writes what you ask for.
@MainActor
enum VoiceCommandMode {
    /// Speech engines hear "Keel" a few ways; all count, but only at the very start.
    private static let wake = #"^\s*((?:hey|hi|okay|ok)[,\s]+)?(?:keel|kiel|keal|keil|kheel)\b([\s,.:!-]*)(.+)$"#
    /// Without a pause after "Keel", the instruction must start like one ("Keel boats are fast" is just words).
    private static let verbs: Set<String> = ["make", "rewrite", "change", "translate", "shorten", "write", "turn", "fix", "add", "remove",
        "delete", "summarize", "summarise", "format", "put", "use", "replace", "expand", "polish", "edit", "draft", "reply", "convert",
        "capitalize", "sort", "list", "clean", "tidy", "simplify", "lengthen", "soften", "tighten", "proofread", "correct", "bullet", "number"]

    /// The instruction, if this was one ("Keel, make it friendlier" → "Make it friendlier").
    nonisolated static func instruction(in raw: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: wake, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let m = re.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let r = Range(m.range(at: 3), in: raw) else { return nil }
        let instr = raw[r].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let greeted = Range(m.range(at: 1), in: raw) != nil
        let paused = Range(m.range(at: 2), in: raw).map { raw[$0].contains(where: { ",.:!-".contains($0) }) } ?? false
        let firstWord = instr.split(separator: " ").first.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) } ?? ""
        guard instr.split(separator: " ").count >= 2, greeted || paused || verbs.contains(firstWord) else { return nil }
        return instr.prefix(1).uppercased() + instr.dropFirst()
    }

    /// Edits `text` as asked, or writes something new when it's empty. Nil if the AI can't or the result is unusable.
    static func apply(_ instruction: String, to text: String, context: VoiceContext) async -> String? {
        let current = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let work = VoiceVocabulary.work
        let about = work.isEmpty ? "" : " I work as / in: \(work)."
        let prompt: String
        if current.isEmpty {
            // Drafting from nothing: an email opens with a short greeting to whoever I named.
            let rule = context == .email
                ? "This is an email. Start with a short greeting to the person I named, then clear, friendly sentences. No sign-off."
                : context.styleRule
            prompt = """
            Write this for me: \(instruction)
            \(rule)\(about) Write it as I would, plainly, ready to use. Reply with only the text.
            """
        } else {
            prompt = """
            Edit my text as I ask. Change only what the instruction asks for and keep everything else as I wrote it, \
            including the greeting and sign-off.
            Instruction: \(instruction)
            \(context.styleRule)\(about)
            Reply with only the edited text.

            My text:
            \"\"\"
            \(current)
            \"\"\"
            """
        }
        guard let raw = await AIRouter.shared.write(prompt) else { return nil }
        var out = VoiceCleanup.stripChatter(raw)
        out = out.replacingOccurrences(of: #"^\"\"\"\s*|\s*\"\"\"$"#, with: "", options: .regularExpression)
        out = VoiceCleanup.finish(out, context)
        guard !out.isEmpty, out != current, out.count <= max(4_000, current.count * 3) else { return nil }
        // Small models drop an email's greeting when shortening (seen in testing): put it back.
        if let g = greeting(in: current), !out.lowercased().hasPrefix(g.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",")) ) {
            out = g + "\n\n" + out
        }
        return out
    }

    /// "Hi Marcus," on the first line of an email, if it opens with one.
    nonisolated static func greeting(in text: String) -> String? {
        guard let first = text.split(separator: "\n", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespaces),
              first.split(separator: " ").count <= 4, first.hasSuffix(",") else { return nil }
        let opener = first.lowercased()
        let starts = ["hi", "hello", "hey", "dear", "good morning", "good afternoon", "morning", "greetings"]
        return starts.contains { opener.hasPrefix($0) } ? first : nil
    }
}

/// Learns from your fixes, like Flow: if you type over a word Keel Voice put in ("Shal" → "Shah"), the new
/// spelling joins your vocabulary. Only one replaced word (or a two-word name), close in spelling, and only
/// something that looks like a name or term, so ordinary rewording doesn't teach it anything.
@MainActor
enum VoiceLearning {
    static let key = "voice.learned"
    static var learned: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    static func add(_ w: String) {
        var l = learned.filter { $0.lowercased() != w.lowercased() }
        l.insert(w, at: 0)
        UserDefaults.standard.set(Array(l.prefix(200)), forKey: key)
        VoiceVocabulary.forget()
    }

    static func forget(_ w: String) {
        UserDefaults.standard.set(learned.filter { $0 != w }, forKey: key)
        VoiceVocabulary.forget()
    }

    /// The corrected spelling, if `after` is `before` with one dictated word (or two-word name) fixed.
    static func correction(dictated: String, before: String, after: String) -> String? {
        func words(_ s: String) -> [String] { s.components(separatedBy: CharacterSet.whitespacesAndNewlines).filter { !$0.isEmpty } }
        let strip = CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "'-"))
        let b = words(before), a = words(after)
        guard !b.isEmpty, !a.isEmpty, abs(a.count - b.count) <= 1 else { return nil }
        var p = 0
        while p < min(a.count, b.count), a[p] == b[p] { p += 1 }
        var s = 0
        while s < min(a.count, b.count) - p, a[a.count - 1 - s] == b[b.count - 1 - s] { s += 1 }
        let removed = b[p..<(b.count - s)].map { $0.trimmingCharacters(in: strip) }
        let added = a[p..<(a.count - s)].map { $0.trimmingCharacters(in: strip) }
        guard (1...2).contains(removed.count), removed.count == added.count else { return nil }
        let old = removed.joined(separator: " "), new = added.joined(separator: " ")
        guard old != new, new.count >= 3, dictated.localizedCaseInsensitiveContains(old) else { return nil }
        // Close in spelling: a fix, not a different word.
        guard VoiceCleanup.distance(old.lowercased(), new.lowercased()) <= max(2, new.count / 3), old.lowercased() != new.lowercased() else { return nil }
        guard looksLikeTerm(new) else { return nil }
        return new
    }

    /// A name, acronym or word the dictionary doesn't know.
    static func looksLikeTerm(_ w: String) -> Bool {
        if VocabularyMiner.isAcronym(w) { return true }
        if w.split(separator: " ").allSatisfy({ $0.first?.isUppercase == true }) { return true }
        let lang = VoiceLanguage.locale.language.languageCode?.identifier ?? "en"
        let miss = UITextChecker().rangeOfMisspelledWord(in: w, range: NSRange(location: 0, length: (w as NSString).length),
                                                          startingAt: 0, wrap: false, language: lang)
        return miss.location != NSNotFound
    }
}

/// Which language Keel Voice listens in: your iPhone's, or one you choose (Settings → Keel Voice).
@MainActor
enum VoiceLanguage {
    static let key = "voice.locale"          // "" = the iPhone's language

    static var chosen: String {
        get { UserDefaults.standard.string(forKey: key) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var locale: Locale { chosen.isEmpty ? Locale.current : Locale(identifier: chosen) }

    /// Languages Apple's on-device engine supports here, by name.
    static func available() async -> [Locale] {
        let all = await SpeechTranscriber.supportedLocales
        return all.sorted { name($0) < name($1) }
    }

    static func name(_ l: Locale) -> String {
        Locale.current.localizedString(forIdentifier: l.identifier) ?? l.identifier
    }
}
