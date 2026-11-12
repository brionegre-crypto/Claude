import SwiftUI
import SwiftData
import Charts

/// Mood, energy and sleep over time, with every highlight. Spots patterns like "bad sleep → low mood".
struct JournalTimelineView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \CheckIn.day, order: .reverse) private var checkIns: [CheckIn]
    @State private var range = 30
    @State private var writing = false
    @State private var summaries: [Date: String] = [:]

    private var shown: [CheckIn] {
        let since = Calendar.current.date(byAdding: .day, value: -range, to: Date())!
        return checkIns.filter { $0.day >= since }
    }

    var body: some View {
        List {
            Section {
                Picker("Range", selection: $range) {
                    Text("2 weeks").tag(14); Text("Month").tag(30); Text("3 months").tag(90)
                }.pickerStyle(.segmented)
                if shown.count >= 2 {
                    Chart {
                        ForEach(shown) { c in
                            LineMark(x: .value("Day", c.day, unit: .day), y: .value("Score", c.mood), series: .value("", "Mood"))
                                .foregroundStyle(by: .value("", "Mood")).interpolationMethod(.catmullRom)
                            if let e = c.energy {
                                LineMark(x: .value("Day", c.day, unit: .day), y: .value("Score", Double(e) * 5 / 3), series: .value("", "Energy"))
                                    .foregroundStyle(by: .value("", "Energy")).interpolationMethod(.catmullRom)
                            }
                            if let s = c.sleepHours {
                                BarMark(x: .value("Day", c.day, unit: .day), y: .value("Score", min(5, s / 2)))
                                    .foregroundStyle(by: .value("", "Sleep")).opacity(0.25)
                            }
                        }
                    }
                    .chartForegroundStyleScale(["Mood": DS.Palette.accent, "Energy": DS.Palette.warmth, "Sleep": DS.Palette.meeting])
                    .chartYScale(domain: 0...5)
                    .chartYAxis(.hidden)
                    .frame(height: 180)
                    if let insight { Label(insight, systemImage: "lightbulb").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft) }
                } else {
                    Text("Check in on Today for a few days to see your trends.").foregroundStyle(DS.Palette.inkSoft)
                }
            }
            Section {
                NavigationLink { DayLogView() } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Today's log", systemImage: "list.bullet.rectangle").font(DS.Font.headline)
                        let s = DailyLog.summary(for: Date(), ctx: ctx)
                        Text(s.isEmpty ? "Breathing, focus, tasks, meds and more, as they happen." : s)
                            .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
            }
            MoodPatternsSection(checkIns: shown)
            Section("Entries") {
                ForEach(shown) { c in
                    HStack(alignment: .top, spacing: DS.Space.m) {
                        Text(CheckIn.faces[max(0, min(4, c.mood - 1))]).font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.day.formatted(.dateTime.weekday(.wide).month().day())).font(DS.Font.headline)
                            HStack(spacing: 8) {
                                if let e = c.energy { Label(["Low", "OK", "High"][max(0, min(2, e - 1))] + " energy", systemImage: "bolt") }
                                if let s = c.sleepHours { Label(String(format: "%.1fh sleep", s), systemImage: "bed.double") }
                            }.font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                            if !c.highlight.isEmpty { Text("“\(c.highlight)”").font(.callout) }
                            if !c.gratitude.isEmpty { Text("Grateful for: \(c.gratitude)").font(.callout).foregroundStyle(DS.Palette.inkSoft) }
                            if !c.journal.isEmpty {
                                if !c.prompt.isEmpty { Text(c.prompt).font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft) }
                                Text(c.journal).font(.callout)
                            }
                            if let log = summaries[c.day], !log.isEmpty {
                                NavigationLink { DayLogView(day: c.day) } label: {
                                    Label(log, systemImage: "list.bullet.rectangle").font(DS.Font.caption).foregroundStyle(DS.Palette.accent)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Mood Journal")
        .toolbar {
            Button { writing = true } label: { Label("Write today's journal", systemImage: "square.and.pencil") }
        }
        .sheet(isPresented: $writing) { JournalEntryView() }
        .task(id: shown.count) {
            // Built once per change, not on every redraw.
            var d: [Date: String] = [:]
            for c in shown.prefix(45) { d[c.day] = DailyLog.summary(for: c.day, ctx: ctx) }
            summaries = d
        }
    }

    /// A simple, honest correlation note: mood after short vs long sleep.
    private var insight: String? {
        let withSleep = shown.filter { $0.sleepHours != nil }
        let short = withSleep.filter { $0.sleepHours! < 6.5 }, long = withSleep.filter { $0.sleepHours! >= 7 }
        guard short.count >= 3, long.count >= 3 else { return nil }
        let a = Double(short.map(\.mood).reduce(0, +)) / Double(short.count)
        let b = Double(long.map(\.mood).reduce(0, +)) / Double(long.count)
        guard abs(b - a) >= 0.5 else { return nil }
        return b > a ? "Your mood averages \(String(format: "%.1f", b - a)) points higher after 7+ hours of sleep."
                     : "Interesting: sleep length doesn't seem to lift your mood much."
    }
}
