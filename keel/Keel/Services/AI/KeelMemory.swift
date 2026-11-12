import Foundation
import Observation

/// What Keel knows about you: short facts you teach it ("My manager is Dana", "I'm sharpest before noon").
/// Stored only on this iPhone. Every AI feature reads them, so plans, drafts and answers fit your life.
@MainActor @Observable
final class KeelMemory {
    static let shared = KeelMemory()
    private static let key = "memory.facts"

    private(set) var facts: [String] = UserDefaults.standard.stringArray(forKey: KeelMemory.key) ?? []

    func add(_ fact: String) {
        let f = fact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty, !facts.contains(where: { $0.caseInsensitiveCompare(f) == .orderedSame }) else { return }
        facts.append(f)
        save()
    }

    func remove(at offsets: IndexSet) { facts.remove(atOffsets: offsets); save() }
    func update(_ index: Int, _ text: String) { guard facts.indices.contains(index) else { return }; facts[index] = text; save() }
    func clear() { facts = []; save() }
    private func save() { UserDefaults.standard.set(facts, forKey: Self.key) }

    /// A compact block for AI instructions; empty when nothing's saved.
    var context: String {
        guard !facts.isEmpty else { return "" }
        return "What you know about the user (use when relevant, never recite it):\n" + facts.suffix(40).map { "- \($0)" }.joined(separator: "\n")
    }
}
