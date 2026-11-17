import SwiftUI

// MARK: - After a session: how did it go?

struct FocusReflection: Codable, Identifiable, Hashable {
    var id = UUID()
    var sessionId: UUID?
    var at = Date()
    var minutes: Int
    var rating: Int            // 1 scattered · 2 okay · 3 locked in
    var note: String
}

@MainActor
enum FocusReflections {
    static let key = "focus.reflections"
    static let askKey = "custom.focus.reflect"
    static var asks: Bool { UserDefaults.standard.object(forKey: askKey) as? Bool ?? true }
    static var all: [FocusReflection] { LocalLog.load(key) }
    static func add(_ r: FocusReflection) { LocalLog.save(Array((all + [r]).suffix(400)), key) }

    /// When your sessions go best, from your own ratings (needs 6+).
    static func bestTime(_ list: [FocusReflection] = all) -> String? {
        guard list.count >= 6 else { return nil }
        func bucket(_ d: Date) -> String {
            let h = Calendar.current.component(.hour, from: d)
            return h < 12 ? "mornings" : h < 17 ? "afternoons" : "evenings"
        }
        let groups = Dictionary(grouping: list, by: { bucket($0.at) }).filter { $0.value.count >= 2 }
        guard groups.count >= 2 else { return nil }
        let avg = groups.mapValues { Double($0.map(\.rating).reduce(0, +)) / Double($0.count) }
        guard let best = avg.max(by: { $0.value < $1.value }), let worst = avg.min(by: { $0.value < $1.value }), best.value - worst.value >= 0.4 else { return nil }
        return best.key
    }
}

struct FocusReflectionSheet: View {
    let sessionId: UUID?
    let minutes: Int
    let early: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var rating = 0
    @State private var note = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                Text(early ? "Stopped after \(minutes) min. That still counts." : "\(minutes) minutes of focus. Nice.").font(DS.Font.title)
                Text("How did it go?").font(DS.Font.headline).foregroundStyle(DS.Palette.inkSoft)
                HStack(spacing: 10) {
                    choice(1, "🌀", "Scattered"); choice(2, "🙂", "Okay"); choice(3, "🔥", "Locked in")
                }
                TextField("What did you get done? (optional)", text: $note, axis: .vertical).lineLimit(1...4)
                    .padding(12).background { PremiumSurface(radius: 14) }
                Spacer()
                Button {
                    if rating > 0 { FocusReflections.add(FocusReflection(sessionId: sessionId, minutes: minutes, rating: rating, note: note)) }
                    Haptics.success(); dismiss()
                } label: { Text(rating == 0 ? "Skip" : "Save").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(DS.Palette.focus)
            }
            .padding()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }

    private func choice(_ v: Int, _ emoji: String, _ label: String) -> some View {
        Button { withAnimation(DS.spring) { rating = v }; Haptics.tap() } label: {
            VStack(spacing: 6) { Text(emoji).font(.largeTitle); Text(label).font(.caption.weight(.semibold)) }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background { PremiumSurface(tint: rating == v ? DS.Palette.focus : nil, radius: 16) }
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(rating == v ? DS.Palette.focus : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .foregroundStyle(DS.Palette.ink)
    }
}

/// Focus history: how your sessions felt, and when they go best.
struct FocusReflectionsSection: View {
    private let list = FocusReflections.all.reversed().prefix(30).map { $0 }
    var body: some View {
        if !list.isEmpty {
            Section {
                if let best = FocusReflections.bestTime() {
                    Label("Your best sessions are in the \(best).", systemImage: "sparkles").font(DS.Font.headline).foregroundStyle(DS.Palette.focus)
                }
                let avg = Double(list.map(\.rating).reduce(0, +)) / Double(list.count)
                Text("Lately: \(avg >= 2.5 ? "mostly locked in 🔥" : avg >= 1.7 ? "mostly okay 🙂" : "often scattered 🌀. Shorter sessions or a body double may help.")")
                    .font(.caption).foregroundStyle(DS.Palette.inkSoft)
                ForEach(list.prefix(8)) { r in
                    HStack(alignment: .top) {
                        Text(r.rating == 3 ? "🔥" : r.rating == 2 ? "🙂" : "🌀")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.note.isEmpty ? "\(r.minutes) min" : r.note).lineLimit(2)
                            Text(r.at.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                }
            } header: { Text("How sessions felt") }
        }
    }
}
