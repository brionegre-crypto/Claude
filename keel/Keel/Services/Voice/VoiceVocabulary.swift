import Foundation
import SwiftData
import NaturalLanguage
import UIKit

/// The names and words Keel Voice listens for, so "Priya" isn't heard as "pre ah": people, projects, lists and
/// the people who email you, plus words you add yourself (Settings → Keel Voice). Kept on this iPhone.
@MainActor
enum VoiceVocabulary {
    static let customKey = "voice.vocabulary"
    static let workKey = "voice.work"                    // "Pastor and men's coach", "ICU nurse", "tax attorney"…
    static let fieldTermsKey = "voice.fieldTerms"        // jargon for that field (generated once, editable)
    static let minedKey = "voice.mined"                  // terms found in your own notes, tasks, calendar and mail
    static let minedAtKey = "voice.minedAt"

    /// What you do, in your words. Also kept in Keel's memory, so every AI feature knows it.
    static var work: String {
        get { UserDefaults.standard.string(forKey: workKey) ?? "" }
        set {
            let w = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(w, forKey: workKey)
            if !w.isEmpty { KeelMemory.shared.add("I work as / in: \(w)") }
            cache = nil
        }
    }

    /// A line about your work already in Keel's memory (from onboarding or "Remember…"), to offer as a start.
    static var workFromMemory: String? {
        let cues = ["i work", "i'm a ", "i am a ", "my job", "my work", "i run ", "my business", "my company", "i lead", "i teach", "i own"]
        return KeelMemory.shared.facts.first { f in cues.contains { f.lowercased().contains($0) } }
    }

    static var fieldTerms: [String] {
        get { UserDefaults.standard.stringArray(forKey: fieldTermsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: fieldTermsKey); cache = nil }
    }
    static var mined: [String] { UserDefaults.standard.stringArray(forKey: minedKey) ?? [] }

    /// Asks Apple Intelligence (Claude if it can't) for the words people in your field say: terms, names, acronyms.
    static func generateFieldTerms() async -> [String] {
        let w = work
        guard !w.isEmpty else { return [] }
        let prompt = """
        List 60 words and short phrases that someone who works as or in "\(w)" often says out loud and that speech \
        recognition tends to get wrong: field-specific terms, acronyms, proper names, titles and spellings. \
        One per line, no numbering, no explanations, most common first.
        """
        guard let raw = await AIRouter.shared.write(prompt) else { return [] }
        var seen = Set<String>()
        let terms = raw.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"^[\s\-•*\d.)]+"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count <= 40 && $0.split(separator: " ").count <= 4 && seen.insert($0.lowercased()).inserted }
        fieldTerms = Array(terms.prefix(80))
        return fieldTerms
    }

    /// Reads your notes, tasks, calendar and email subjects (on this iPhone, in the background) for the names and
    /// terms you actually use: people, places and organisations, and words the dictionary doesn't know (usually
    /// jargon and names), ranked by how often they come up. Runs at most once a day.
    static func mine(_ ctx: ModelContext, force: Bool = false) async {
        if !force, let at = UserDefaults.standard.object(forKey: minedAtKey) as? Date, Date().timeIntervalSince(at) < 86_400 { return }
        var texts: [String] = []
        for n in (try? ctx.fetch(FetchDescriptor<Note>())) ?? [] where !n.isLocked { texts.append(n.title); texts.append(String(n.plainText.prefix(4_000))) }
        var td = FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]); td.fetchLimit = 1_000
        texts += ((try? ctx.fetch(td)) ?? []).map { $0.title + ". " + $0.notes.prefix(300) }
        var md = FetchDescriptor<EmailMessage>(sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]); md.fetchLimit = 800
        texts += ((try? ctx.fetch(md)) ?? []).map(\.subject)
        let cal = Calendar.current, now = Date()
        if let from = cal.date(byAdding: .day, value: -60, to: now), let to = cal.date(byAdding: .day, value: 30, to: now) {
            texts += CalendarService.shared.events(from: from, to: to).compactMap(\.title)
        }
        let counts = await Task.detached(priority: .utility) { VocabularyMiner.candidates(in: texts) }.value
        let found = VocabularyMiner.terms(from: counts)
        UserDefaults.standard.set(found, forKey: minedKey)
        UserDefaults.standard.set(Date(), forKey: minedAtKey)
        cache = nil
    }

    static var custom: [String] {
        get { UserDefaults.standard.stringArray(forKey: customKey) ?? [] }
        set { UserDefaults.standard.set(newValue.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, forKey: customKey) }
    }

    private static var cache: (at: Date, words: [String])?

    /// Your words first, then names from your data, most useful first; at most 100.
    static func words(_ ctx: ModelContext) -> [String] {
        if let c = cache, Date().timeIntervalSince(c.at) < 600 { return mergeCustom(c.words) }
        var found: [String] = []
        found += ((try? ctx.fetch(FetchDescriptor<Person>())) ?? []).map(\.name)
        found += ((try? ctx.fetch(FetchDescriptor<Project>())) ?? []).map(\.name)
        let open = (try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? []
        found += Set(open.map(\.listName)).sorted()
        var md = FetchDescriptor<EmailMessage>(sortBy: [SortDescriptor(\.receivedAt, order: .reverse)])
        md.fetchLimit = 400
        let senders = ((try? ctx.fetch(md)) ?? []).map(\.fromName)
        let counted = Dictionary(senders.map { ($0, 1) }, uniquingKeysWith: +).sorted { $0.value > $1.value }.map(\.key)
        found += counted.prefix(50)
        let words = clean(found)
        cache = (Date(), words)
        return mergeCustom(words)
    }

    static func forget() { cache = nil }

    /// Your own words first, then what you use most (mined), people and projects, then your field's terms.
    private static func mergeCustom(_ words: [String]) -> [String] {
        var seen = Set<String>()
        let ordered = custom + Array(mined.prefix(40)) + words + Array(fieldTerms.prefix(40))
        return ordered.filter { seen.insert($0.lowercased()).inserted }.prefix(100).map { $0 }
    }

    /// Only names worth priming: not empty, not an email address, not a common word.
    private static func clean(_ names: [String]) -> [String] {
        let common: Set<String> = ["inbox", "work", "home", "personal", "reminders", "errands", "someday", "today", "calendar", "the", "team"]
        var seen = Set<String>()
        return names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 40 && !$0.contains("@") && !common.contains($0.lowercased()) && seen.insert($0.lowercased()).inserted }
    }

    /// Your Snippets, for "insert my address".
    static func snippets(_ ctx: ModelContext) -> [(name: String, body: String)] {
        ((try? ctx.fetch(FetchDescriptor<Snippet>())) ?? []).map { (name: $0.name, body: $0.body) }
    }
}

/// Finds the names and terms in your writing. The text analysis runs off the main thread; the dictionary check
/// (UIKit's, which must run on the main thread) only sees the distinct candidate words.
enum VocabularyMiner {
    struct Counts: Sendable {
        var names: [String: Int] = [:]
        var words: [String: Int] = [:]
        var midCaps: [String: Int] = [:]           // capitalised mid-sentence: a name or a term, not just a sentence start
    }

    /// "ICU", "Q4", "CPA", "401k": acronyms and codes are vocabulary whatever the dictionary says.
    nonisolated static func isAcronym(_ w: String) -> Bool {
        let letters = w.filter(\.isLetter)
        guard w.count >= 2, w.count <= 8, !letters.isEmpty else { return false }
        return (letters.count >= 2 && letters.allSatisfy(\.isUppercase)) || (w.contains(where: \.isNumber) && w.contains(where: \.isLetter))
    }

    nonisolated static func candidates(in texts: [String]) -> Counts {
        var c = Counts()
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        let stop: Set<String> = ["the", "and", "for", "with", "your", "today", "tomorrow", "this", "that", "from", "have", "will"]
        for text in texts where !text.isEmpty {
            tagger.string = text
            // People, places and organisations, as written.
            tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                                 options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, r in
                if let tag, [.personalName, .placeName, .organizationName].contains(tag) {
                    let w = String(text[r]).trimmingCharacters(in: .whitespaces)
                    if w.count > 2 { c.names[w, default: 0] += 1 }
                }
                return true
            }
            // Every other word, counted, for the dictionary check.
            tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
                                 options: [.omitWhitespace, .omitPunctuation, .omitOther]) { _, r in
                let w = String(text[r])
                guard (w.count > 2 || isAcronym(w)), w.count <= 30, !stop.contains(w.lowercased()), w.rangeOfCharacter(from: .letters) != nil else { return true }
                c.words[w, default: 0] += 1
                // Mid-sentence capital: the last non-space character before it isn't a sentence end (or the start).
                if let first = w.first, first.isUppercase, w != "I" {
                    let before = text[..<r.lowerBound].last { !$0.isWhitespace }
                    if let b = before, !".!?:\n\"“(".contains(b) { c.midCaps[w, default: 0] += 1 }
                }
                return true
            }
        }
        return c
    }

    /// Names said at least twice, and words the dictionary doesn't know (jargon, acronyms, brands) said at least
    /// twice; one spelling each (the most common), most used first.
    @MainActor static func terms(from c: Counts, limit: Int = 80) -> [String] {
        let checker = UITextChecker()
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        var scored: [String: Int] = [:]
        for (w, n) in c.names { scored[w, default: 0] += n * 2 }
        for (w, n) in c.words.sorted(by: { $0.value > $1.value }).prefix(3_000) where n >= 2 {
            if isAcronym(w) || (c.midCaps[w] ?? 0) >= 1 { scored[w, default: 0] += n; continue }
            let len = (w as NSString).length
            let miss = checker.rangeOfMisspelledWord(in: w, range: NSRange(location: 0, length: len), startingAt: 0, wrap: false, language: lang)
            if miss.location != NSNotFound { scored[w, default: 0] += n }
        }
        var best: [String: (String, Int)] = [:]
        for (w, n) in scored {
            let k = w.lowercased()
            if let cur = best[k] { best[k] = n > cur.1 ? (w, n + cur.1) : (cur.0, cur.1 + n) } else { best[k] = (w, n) }
        }
        return best.values.filter { $0.1 >= 2 }.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
}
