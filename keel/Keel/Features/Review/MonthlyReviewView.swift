import SwiftUI
import SwiftData
import Charts

/// End-of-month review: the month at a glance, how you felt, goal progress, and a short reflection.
struct MonthlyReviewView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var tasks: [TaskItem]
    @Query private var sessions: [FocusSession]
    @Query private var logs: [HabitLog]
    @Query(sort: \CheckIn.day) private var checkIns: [CheckIn]
    @Query(filter: #Predicate<Goal> { !$0.isArchived }) private var goals: [Goal]
    @State private var proud = ""
    @State private var change = ""
    @State private var focusNext = ""
    @State private var saved = false

    private let cal = Calendar.current
    private var start: Date { cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: Date()))! }
    private func inMonth(_ d: Date?) -> Bool { d.map { $0 >= start } ?? false }
    private var done: [TaskItem] { tasks.filter { inMonth($0.completedAt) || inMonth($0.lastCompletedOccurrence) } }
    private var focusHours: Double {
        Double(sessions.filter { inMonth($0.endedAt) }.reduce(0) { $0 + Int((($1.endedAt ?? $1.startedAt).timeIntervalSince($1.startedAt)) / 60) }) / 60
    }
    private var moods: [CheckIn] { checkIns.filter { $0.day >= start } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                Text("Last 30 days").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).textCase(.uppercase)
                FlexGrid(columns: 2, spacing: DS.Space.s) {
                    tile("\(done.count)", "tasks done")
                    tile(String(format: "%.1fh", focusHours), "focused")
                    tile("\(logs.filter { $0.day >= start }.count)", "habit check-ins")
                    tile(moods.isEmpty ? "—" : CheckIn.faces[min(4, max(0, Int((Double(moods.map(\.mood).reduce(0, +)) / Double(moods.count)).rounded()) - 1))], "average mood")
                }
                if !moods.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading) {
                            Text("Mood").font(DS.Font.headline)
                            Chart(moods) { c in
                                LineMark(x: .value("Day", c.day, unit: .day), y: .value("Mood", c.mood)).interpolationMethod(.catmullRom).foregroundStyle(.pink)
                            }
                            .chartYScale(domain: 1...5).chartYAxis(.hidden).frame(height: 100)
                        }
                    }
                }
                if !goals.isEmpty {
                    SectionHeader(title: "Goals")
                    ForEach(goals) { g in
                        let n = done.filter { $0.goalId == g.id }.count
                        HStack { Text("\(g.emoji) \(g.title)"); Spacer(); Text(n == 0 ? "untouched" : "+\(n)").foregroundStyle(n == 0 ? DS.Palette.warmth : DS.Palette.calm) }
                            .font(DS.Font.body)
                    }
                }
                let highlights = moods.map(\.highlight).filter { !$0.isEmpty }
                if !highlights.isEmpty {
                    SectionHeader(title: "Highlights")
                    ForEach(highlights.suffix(6), id: \.self) { Text("• \($0)").font(DS.Font.body) }
                }
                SectionHeader(title: "Reflect")
                field("What am I proud of this month?", $proud)
                field("What do I want to change?", $change)
                field("One focus for next month", $focusNext)
                Button { save() } label: {
                    Label(saved ? "Saved to Notes" : "Save monthly review", systemImage: saved ? "checkmark" : "square.and.arrow.down")
                        .font(DS.Font.headline).frame(maxWidth: .infinity).padding(.vertical, DS.Space.m)
                        .background(DS.Palette.accent, in: Capsule()).foregroundStyle(.white)
                }
                .disabled(saved)
            }
            .padding()
        }
        .navigationTitle("Monthly review")
    }

    private func tile(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading) { Text(v).font(DS.Font.title); Text(l).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(DS.Space.m)
            .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.card))
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            TextField("", text: text, axis: .vertical).lineLimit(2...5).padding(DS.Space.s)
                .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.chip))
        }
    }

    private func save() {
        var blocks: [NoteBlock] = [.init(kind: .text, text: "\(done.count) tasks · \(String(format: "%.1f", focusHours))h focused · \(moods.count) check-ins")]
        for (t, v) in [("Proud of", proud), ("Want to change", change), ("Focus for next month", focusNext)] where !v.isEmpty {
            blocks += [.init(kind: .heading, text: t), .init(kind: .text, text: v)]
        }
        ctx.insert(Note(title: "Monthly review · \(Date().formatted(.dateTime.month(.wide).year()))", blocks: blocks))
        if !focusNext.isEmpty { UserDefaults.standard.set(focusNext, forKey: "month.focus") }
        withAnimation { saved = true }
        Haptics.milestone()
    }
}
