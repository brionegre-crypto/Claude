import SwiftUI
import SwiftData

/// Ten-second daily check-in: how you feel and one good thing. Feeds the weekly review's mood trend.
struct CheckInCard: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \CheckIn.day, order: .reverse) private var checkIns: [CheckIn]
    @State private var highlight = ""
    @State private var picked: Int?

    private var today: CheckIn? { checkIns.first { Calendar.current.isDateInToday($0.day) } }

    var body: some View {
        GlassCard {
            if let t = today {
                HStack(spacing: DS.Space.m) {
                    Text(CheckIn.faces[max(0, min(4, t.mood - 1))]).font(.largeTitle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Checked in").font(DS.Font.headline)
                        Text(t.highlight.isEmpty ? "Add a highlight later if something good happens." : "“\(t.highlight)”")
                            .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                    }
                    Spacer()
                    Text("\(streak) day\(streak == 1 ? "" : "s") 🔥").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
            } else {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text("How are you, really?").font(DS.Font.headline)
                    HStack {
                        ForEach(1...5, id: \.self) { m in
                            Button { withAnimation(DS.spring) { picked = m }; Haptics.tap() } label: {
                                Text(CheckIn.faces[m - 1]).font(.system(size: 30))
                                    .scaleEffect(picked == m ? 1.25 : 1)
                                    .opacity(picked == nil || picked == m ? 1 : 0.4)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Mood \(m) of 5")
                        }
                    }
                    if picked != nil {
                        TextField("One good thing today (optional)", text: $highlight)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(save)
                        Button("Save", action: save).font(DS.Font.headline).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var streak: Int {
        let cal = Calendar.current
        let days = Set(checkIns.map { cal.startOfDay(for: $0.day) })
        var d = cal.startOfDay(for: Date())
        var n = 0
        while days.contains(d) { n += 1; d = cal.date(byAdding: .day, value: -1, to: d)! }
        return n
    }

    private func save() {
        guard let m = picked else { return }
        let c = CheckIn(day: Calendar.current.startOfDay(for: Date()), mood: m)
        c.highlight = highlight
        ctx.insert(c)
        Haptics.success()
        highlight = ""; picked = nil
    }
}
