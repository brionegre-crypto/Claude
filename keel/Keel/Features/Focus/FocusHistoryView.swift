import SwiftUI
import SwiftData
import Charts

/// 30 days of focus: minutes per day, best day, average session, and every session.
struct FocusHistoryView: View {
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var sessions: [FocusSession]
    @Query private var tasks: [TaskItem]

    private var recent: [FocusSession] {
        let since = Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: Date()))!
        return sessions.filter { $0.startedAt >= since && $0.endedAt != nil }
    }
    private func minutes(_ s: FocusSession) -> Int {
        Int((s.endedAt ?? s.startedAt).timeIntervalSince(s.startedAt) / 60)
    }
    private var perDay: [(day: Date, minutes: Int)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let grouped = Dictionary(grouping: recent) { cal.startOfDay(for: $0.startedAt) }
        return (0..<30).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -i, to: today)!
            return (d, (grouped[d] ?? []).reduce(0) { $0 + minutes($1) })
        }
    }

    var body: some View {
        List {
            Section {
                let total = recent.reduce(0) { $0 + minutes($1) }
                let best = perDay.max { $0.minutes < $1.minutes }
                HStack {
                    stat("\(total / 60)h \(total % 60)m", "last 30 days")
                    stat(recent.isEmpty ? "–" : "\(total / max(1, recent.count))m", "avg session")
                    stat(best.map { $0.minutes > 0 ? $0.day.formatted(.dateTime.weekday(.abbreviated).day()) : "–" } ?? "–", "best day")
                }
                Chart(perDay, id: \.day) { d in
                    BarMark(x: .value("Day", d.day, unit: .day), y: .value("Minutes", d.minutes))
                        .foregroundStyle(DS.Palette.accent.gradient)
                        .cornerRadius(3)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .frame(height: 160)
                if let bestHour {
                    Label("You focus best around \(bestHour).", systemImage: "sparkles")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
            }
            Section("Sessions") {
                if recent.isEmpty {
                    Text("No finished focus sessions yet. Start one from the Focus bar.").foregroundStyle(DS.Palette.inkSoft)
                }
                ForEach(recent) { s in
                    HStack {
                        Image(systemName: s.brokeEarly ? "pause.circle" : "checkmark.circle.fill")
                            .foregroundStyle(s.brokeEarly ? DS.Palette.inkSoft : DS.Palette.calm)
                        VStack(alignment: .leading) {
                            Text(tasks.first { $0.id == s.taskId }?.title ?? (s.mode == "shutdown" ? "Shutdown" : "Deep focus"))
                            Text(s.startedAt.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute()))
                                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        Text("\(minutes(s)) / \(s.plannedMinutes)m").monospacedDigit().foregroundStyle(DS.Palette.inkSoft)
                    }
                }
            }
        }
        .navigationTitle("Focus History")
    }

    private var bestHour: String? {
        guard recent.count >= 5 else { return nil }
        let byHour = Dictionary(grouping: recent) { Calendar.current.component(.hour, from: $0.startedAt) }
            .mapValues { $0.reduce(0) { $0 + minutes($1) } }
        guard let h = byHour.max(by: { $0.value < $1.value })?.key,
              let d = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) else { return nil }
        return d.formatted(date: .omitted, time: .shortened)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(DS.Font.headline).monospacedDigit()
            Text(label).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
        }.frame(maxWidth: .infinity)
    }
}
