import Foundation

/// Learns how you write from your sent mail (greeting, sign-off, length, tone markers) so AI drafts sound like you.
/// Only short statistics and a few anonymised openers are kept, on this iPhone.
@MainActor
enum WritingStyle {
    struct Profile: Codable, Equatable {
        var samples = 0
        var greeting = ""            // e.g. "Hi {name},"  ("" = you usually skip greetings)
        var signoff = ""             // e.g. "Thanks,"
        var medianWords = 0
        var exclamationRate = 0.0     // share of emails with "!"
        var emojiRate = 0.0
        var lowercaseRate = 0.0       // share starting with a lowercase letter
        var learnedAt: Date?
    }

    static let key = "style.profile"
    static let samplesKey = "style.samples"
    static var isOn: Bool { UserDefaults.standard.object(forKey: "style.on") as? Bool ?? true }

    static var profile: Profile {
        guard let d = UserDefaults.standard.data(forKey: key), let p = try? JSONDecoder().decode(Profile.self, from: d) else { return Profile() }
        return p
    }

    /// Adds newly sent emails (already stripped of quoted replies) and re-learns. Keeps the latest 60.
    static func observe(_ bodies: [String]) {
        let clean = bodies.map { stripSignatureNoise($0) }.filter { $0.split(separator: " ").count >= 3 }
        guard !clean.isEmpty else { return }
        var samples = UserDefaults.standard.stringArray(forKey: samplesKey) ?? []
        samples += clean.map { String($0.prefix(800)) }
        samples = Array(samples.suffix(60))
        UserDefaults.standard.set(samples, forKey: samplesKey)
        learn(samples)
    }

    /// Re-reads the last 30 days of sent mail from every account.
    static func relearn(accounts: [MailAccount]) async {
        var bodies: [String] = []
        for a in accounts where a.isEnabled {
            let sent = (try? await MailProviderFactory.make(for: a).fetchSent(since: Date().addingTimeInterval(-30 * 86_400))) ?? []
            bodies += sent.map(\.body)
        }
        UserDefaults.standard.removeObject(forKey: samplesKey)
        observe(bodies)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: samplesKey)
    }

    static func learn(_ samples: [String]) {
        var p = Profile()
        p.samples = samples.count
        guard samples.count >= 3 else { save(p); return }
        var greetings: [String: Int] = [:], signoffs: [String: Int] = [:]
        var words: [Int] = [], excl = 0, emoji = 0, lower = 0
        for s in samples {
            let lines = s.split(separator: "\n", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let first = lines.first else { continue }
            if let g = greetingPattern(first) { greetings[g, default: 0] += 1 } else { greetings["", default: 0] += 1 }
            if let so = lines.dropFirst().reversed().prefix(3).first(where: { isSignoff($0) }) {
                signoffs[normalizeSignoff(so), default: 0] += 1
            }
            words.append(s.split(whereSeparator: { $0.isWhitespace }).count)
            if s.contains("!") { excl += 1 }
            if s.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) { emoji += 1 }
            if let c = first.first, c.isLetter, c.isLowercase { lower += 1 }
        }
        let n = Double(samples.count)
        p.greeting = greetings.max { $0.value < $1.value }?.key ?? ""
        p.signoff = signoffs.max { $0.value < $1.value }.flatMap { $0.value * 3 >= samples.count ? $0.key : nil } ?? ""
        p.medianWords = words.sorted()[words.count / 2]
        p.exclamationRate = Double(excl) / n
        p.emojiRate = Double(emoji) / n
        p.lowercaseRate = Double(lower) / n
        p.learnedAt = Date()
        save(p)
    }

    private static func save(_ p: Profile) {
        if let d = try? JSONEncoder().encode(p) { UserDefaults.standard.set(d, forKey: key) }
    }

    /// "Hi Sam," → "Hi {name},"   "Hey!" → "Hey!"
    static func greetingPattern(_ line: String) -> String? {
        let words = line.split(separator: " ")
        guard let w = words.first, words.count <= 4, line.count <= 40 else { return nil }
        let word = w.trimmingCharacters(in: .punctuationCharacters).lowercased()
        guard ["hi", "hey", "hello", "dear", "morning", "good", "yo", "hiya", "heya"].contains(word) else { return nil }
        let end = line.hasSuffix(",") ? "," : line.hasSuffix("!") ? "!" : ""
        let opener = String(w).trimmingCharacters(in: .punctuationCharacters)
        if word == "good", words.count >= 2 { return "\(opener) \(words[1].trimmingCharacters(in: .punctuationCharacters))\(end)" }
        return words.count >= 2 ? "\(opener) {name}\(end)" : "\(opener)\(end)"
    }

    static func isSignoff(_ line: String) -> Bool {
        let l = line.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        let known = ["thanks", "thank you", "best", "cheers", "regards", "best regards", "kind regards", "warmly", "talk soon",
                     "thx", "ty", "many thanks", "all the best", "take care", "speak soon", "warm regards", "sincerely"]
        return known.contains(l) || (l.hasPrefix("thanks") && l.count < 20)
    }

    static func normalizeSignoff(_ line: String) -> String {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasSuffix(",") || t.hasSuffix("!") || t.hasSuffix(".") ? t : t + ","
    }

    /// Drops "Sent from my iPhone" and similar footers before learning.
    static func stripSignatureNoise(_ s: String) -> String {
        var lines = s.components(separatedBy: "\n")
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty || last.lowercased().contains("sent from") || last.hasPrefix("--") {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Instructions added to every AI reply so it sounds like you.
    static var instruction: String {
        let p = profile
        guard isOn, p.samples >= 3 else { return "" }
        var parts: [String] = []
        parts.append(p.greeting.isEmpty ? "Don't start with a greeting line; get straight to the point."
                                         : "Start with a greeting in this form: \"\(p.greeting)\" (replace {name} with their first name).")
        if !p.signoff.isEmpty { parts.append("End with \"\(p.signoff)\" on its own line, then nothing else.") }
        let target = max(15, min(200, p.medianWords))
        parts.append("Keep it around \(target) words; the user writes \(target < 50 ? "short, punchy" : target < 120 ? "medium-length" : "fuller") emails.")
        if p.exclamationRate > 0.4 { parts.append("Warm and upbeat; an exclamation mark is fine.") }
        else if p.exclamationRate < 0.1 { parts.append("Calm tone, avoid exclamation marks.") }
        if p.emojiRate > 0.3 { parts.append("A single emoji is fine where natural.") }
        if p.lowercaseRate > 0.5 { parts.append("Casual: lowercase sentence starts are fine.") }
        return "Match the user's writing style. " + parts.joined(separator: " ")
    }

    /// "Hi Sam," for the reply, using your usual greeting.
    static func greeting(for name: String) -> String {
        let p = profile
        let first = name.split(separator: " ").first.map(String.init) ?? ""
        guard !p.greeting.isEmpty else { return first.isEmpty ? "" : "Hi \(first),\n\n" }
        let g = p.greeting.replacingOccurrences(of: "{name}", with: first)
            .replacingOccurrences(of: "  ", with: " ").replacingOccurrences(of: " ,", with: ",")
        return g + "\n\n"
    }

    static var signoffBlock: String {
        let s = profile.signoff
        let name = TemplateFill.myName
        guard !s.isEmpty else { return "" }
        return "\n\(s)" + (name.isEmpty ? "" : "\n\(name)")
    }

    /// A ready reply offering your free times, in your style.
    static func availabilityReply(to name: String) -> String {
        greeting(for: name) + "Happy to find a time. " + Availability.text() + "\nLet me know what suits you." + "\n" + signoffBlock
    }
}
