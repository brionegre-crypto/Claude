import SwiftUI
import SwiftData
import Charts
import EventKit
import UserNotifications

/// Focus Forecast: an hour-by-hour guess at when your brain is sharpest today, from when you take your
/// medication (and how it usually works for you), last night's sleep, the time of day, and when your past
/// focus sessions went well. It's your pattern, not medical advice, and it stays on this iPhone.
@MainActor
enum FocusForecast {
    /// How a medication tends to work for you. You choose it; Keel never guesses a drug's effect.
    enum Profile: String, CaseIterable, Identifiable, Codable {
        case none, shortStimulant, longStimulant, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: "Doesn't affect focus"
            case .shortStimulant: "Short-acting focus med (about 4 h)"
            case .longStimulant: "Long-acting focus med (about 10 h)"
            case .custom: "Custom timing"
            }
        }
    }

    struct Timing: Codable, Equatable {
        var profile: Profile = .none
        var onsetMinutes = 45            // starts working
        var hours = 4.0                  // total time it helps
    }

    struct Hour: Identifiable {
        let date: Date
        let score: Double                // 0…1
        var id: Date { date }
    }

    struct Window: Identifiable {
        let start: Date
        let end: Date
        var id: Date { start }
        var label: String { "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))" }
    }

    struct Forecast {
        var hours: [Hour]
        var peaks: [Window]
        var dips: [Window]
        var reasons: [String]
        var best: Window? { peaks.first }
    }

    static let onKey = "forecast.on"
    static var isOn: Bool { UserDefaults.standard.object(forKey: onKey) as? Bool ?? true }

    static func timing(for med: Medication) -> Timing {
        guard let d = UserDefaults.standard.data(forKey: "forecast.med.\(med.id)"),
              let t = try? JSONDecoder().decode(Timing.self, from: d) else { return Timing() }
        return t
    }

    static func setTiming(_ t: Timing, for med: Medication) {
        if let d = try? JSONEncoder().encode(t) { UserDefaults.standard.set(d, forKey: "forecast.med.\(med.id)") }
    }

    static func preset(_ p: Profile) -> Timing {
        switch p {
        case .none: Timing(profile: .none, onsetMinutes: 0, hours: 0)
        case .shortStimulant: Timing(profile: .shortStimulant, onsetMinutes: 30, hours: 4)
        case .longStimulant: Timing(profile: .longStimulant, onsetMinutes: 60, hours: 10)
        case .custom: Timing(profile: .custom, onsetMinutes: 45, hours: 6)
        }
    }

    /// Builds today's forecast, 7 AM to 11 PM.
    static func build(meds: [Medication], doses: [MedDose], sleepHours: Double?, sessions: [FocusSession], now: Date = Date()) -> Forecast {
        let cal = Calendar.current
        let day = cal.startOfDay(for: now)
        var reasons: [String] = []

        // When each focus med takes effect today: the dose you logged, or the scheduled time if not yet taken.
        var curves: [(start: Date, timing: Timing)] = []
        for m in meds where m.isActive {
            let t = timing(for: m)
            guard t.profile != .none, t.hours > 0 else { continue }
            let taken = doses.filter { $0.medicationId == m.id && cal.isDate($0.day, inSameDayAs: day) }.map(\.takenAt)
            let times = taken.isEmpty ? m.times.compactMap { cal.date(byAdding: .minute, value: $0, to: day) } : taken
            for d in times { curves.append((d, t)) }
            if let first = times.min() {
                reasons.append("\(m.name) \(taken.isEmpty ? "planned" : "taken") at \(first.formatted(date: .omitted, time: .shortened))")
            }
        }

        // When your past focus went well: sessions finished (not quit) by hour of day.
        var good = [Int: Int](), total = [Int: Int]()
        for s in sessions.suffix(200) where s.endedAt != nil {
            let h = cal.component(.hour, from: s.startedAt)
            total[h, default: 0] += 1
            if !s.brokeEarly { good[h, default: 0] += 1 }
        }
        if total.values.reduce(0, +) >= 8 { reasons.append("your past focus sessions") }

        let sleepFactor: Double
        if let s = sleepHours {
            sleepFactor = s < 5.5 ? 0.75 : s < 6.5 ? 0.87 : 1
            reasons.append(String(format: "%.1f h of sleep", s))
        } else { sleepFactor = 1 }

        var hours: [Hour] = []
        for h in 7...22 {
            for half in [0, 30] {
                guard let t = cal.date(bySettingHour: h, minute: half, second: 0, of: day) else { continue }
                // Gentle daily rhythm: rises through the morning, dips after lunch, fades in the evening.
                let x = Double(h) + Double(half) / 60
                var base = 0.45 + 0.25 * exp(-pow((x - 10.5) / 2.2, 2)) + 0.15 * exp(-pow((x - 16.5) / 1.8, 2))
                base -= 0.12 * exp(-pow((x - 14) / 1.0, 2))
                base -= x > 20 ? (x - 20) * 0.08 : 0
                // Medication: ramps up to its onset, holds, then tapers off (with a small dip as it wears off).
                var med = 0.0
                for c in curves {
                    let mins = t.timeIntervalSince(c.start) / 60
                    let onset = Double(max(1, c.timing.onsetMinutes)), dur = c.timing.hours * 60
                    let v: Double
                    if mins < 0 || mins > dur + 90 { v = 0 }
                    else if mins < onset { v = mins / onset }
                    else if mins < dur * 0.8 { v = 1 }
                    else if mins < dur { v = 1 - (mins - dur * 0.8) / (dur * 0.2) }
                    else { v = -0.25 * (1 - (mins - dur) / 90) }        // wear-off dip
                    med = max(med, v) + (v < 0 ? v : 0)
                }
                var score = base + med * 0.35
                if let tot = total[h], tot >= 2 {
                    score += (Double(good[h] ?? 0) / Double(tot) - 0.6) * 0.15
                }
                hours.append(Hour(date: t, score: min(1, max(0, score * sleepFactor))))
            }
        }

        func windows(_ test: (Double) -> Bool) -> [Window] {
            var out: [Window] = [], start: Date?
            for (i, h) in hours.enumerated() {
                if test(h.score) { if start == nil { start = h.date } }
                if let s = start, !test(h.score) || i == hours.count - 1 {
                    let end = test(h.score) ? h.date.addingTimeInterval(1800) : h.date
                    if end.timeIntervalSince(s) >= 3600 { out.append(Window(start: s, end: end)) }
                    start = nil
                }
            }
            return out
        }
        let sorted = hours.map(\.score).sorted()
        let high = max(0.6, sorted[Int(Double(sorted.count) * 0.75)])
        let low = min(0.45, sorted[Int(Double(sorted.count) * 0.2)])
        let peaks = windows { $0 >= high }.sorted { a, b in
            avg(hours, a) > avg(hours, b)
        }
        return Forecast(hours: hours, peaks: peaks, dips: windows { $0 <= low && $0 > 0 }, reasons: reasons)
    }

    private static func avg(_ hours: [Hour], _ w: Window) -> Double {
        let inW = hours.filter { $0.date >= w.start && $0.date < w.end }
        return inW.isEmpty ? 0 : inW.map(\.score).reduce(0, +) / Double(inW.count)
    }

    /// Meetings that land in your best window (with other people, so you might move them).
    static func meetingsInPeak(_ f: Forecast) -> [EKEvent] {
        guard let best = f.best else { return [] }
        return CalendarService.shared.events(from: best.start, to: best.end)
            .filter { !$0.isAllDay && $0.attendees?.isEmpty == false }
    }

    /// The hardest thing worth doing today: high priority or high energy, due soon.
    static func hardestTask(_ tasks: [TaskItem]) -> TaskItem? {
        let soon = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
        return tasks.filter { !$0.isDone && !$0.isSomeday && !$0.isWaitingOn && ($0.dueDate ?? soon) <= soon }
            .max { a, b in
                (a.priority.rawValue * 2 + a.energy.rawValue) < (b.priority.rawValue * 2 + b.energy.rawValue)
            }
    }

    /// A tap on the wrist when your window opens: "Your focus window starts now. Top task: …"
    static func refresh(ctx: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["forecast.window"])
        guard isOn else { return }
        let meds = (try? ctx.fetch(FetchDescriptor<Medication>())) ?? []
        guard meds.contains(where: { timing(for: $0).profile != .none }) else { return }
        let doses = (try? ctx.fetch(FetchDescriptor<MedDose>())) ?? []
        let sessions = (try? ctx.fetch(FetchDescriptor<FocusSession>(sortBy: [SortDescriptor(\.startedAt)]))) ?? []
        let sleep = ((try? ctx.fetch(FetchDescriptor<CheckIn>())) ?? []).first { Calendar.current.isDateInToday($0.day) }?.sleepHours
        let f = build(meds: meds, doses: doses, sleepHours: sleep, sessions: sessions)
        guard let best = f.best, best.start > Date() else { return }
        let tasks = (try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? []
        let c = UNMutableNotificationContent()
        c.title = "Your focus window starts now"
        c.body = hardestTask(tasks).map { "Until \(best.end.formatted(date: .omitted, time: .shortened)). Top task: \($0.title)." }
            ?? "Until \(best.end.formatted(date: .omitted, time: .shortened)). Save it for your hardest work."
        c.sound = .default
        c.interruptionLevel = .timeSensitive
        c.userInfo = ["deeplink": "com.keel.app://focus"]
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: best.start)
        try? await center.add(UNNotificationRequest(identifier: "forecast.window", content: c,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        UserDefaults.standard.set(best.label, forKey: "forecast.bestLabel")
    }
}

// MARK: - Screen

struct FocusForecastView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var meds: [Medication]
    @Query private var doses: [MedDose]
    @Query(sort: \FocusSession.startedAt) private var sessions: [FocusSession]
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var tasks: [TaskItem]
    @Query(sort: \CheckIn.day, order: .reverse) private var checkIns: [CheckIn]
    @State private var sleep: Double?
    @State private var tick = 0
    @State private var planned: String?

    private var forecast: FocusForecast.Forecast {
        _ = tick
        return FocusForecast.build(meds: meds, doses: doses, sleepHours: sleep, sessions: sessions)
    }
    private var hasFocusMed: Bool { meds.contains { FocusForecast.timing(for: $0).profile != .none } }

    var body: some View {
        let f = forecast
        List {
            Section {
                Chart {
                    ForEach(f.hours) { h in
                        AreaMark(x: .value("Time", h.date), y: .value("Focus", h.score))
                            .foregroundStyle(LinearGradient(colors: [DS.Palette.focus.opacity(0.5), DS.Palette.focus.opacity(0.05)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Time", h.date), y: .value("Focus", h.score))
                            .foregroundStyle(DS.Palette.focus).interpolationMethod(.catmullRom)
                    }
                    ForEach(f.peaks) { w in
                        RectangleMark(xStart: .value("Start", w.start), xEnd: .value("End", w.end))
                            .foregroundStyle(DS.Palette.calm.opacity(0.15))
                    }
                    RuleMark(x: .value("Now", Date())).foregroundStyle(DS.Palette.warmth).lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                }
                .chartYScale(domain: 0...1)
                .chartYAxis(.hidden)
                .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 3)) { AxisValueLabel(format: .dateTime.hour()) } }
                .frame(height: 170)
                .accessibilityLabel("Focus forecast chart. " + (f.best.map { "Best window \($0.label)." } ?? ""))
                if let best = f.best {
                    Label("Best focus: \(best.label)", systemImage: "sparkles").font(DS.Font.headline).foregroundStyle(DS.Palette.calm)
                }
                if let dip = f.dips.first(where: { $0.end > Date() }) {
                    Label("Low point: \(dip.label). Good for email and admin.", systemImage: "tray").font(DS.Font.caption)
                }
                if !f.reasons.isEmpty {
                    Text("Based on " + f.reasons.joined(separator: ", ") + ".").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                }
            } footer: { Text("A forecast from your own patterns, not medical advice.") }

            if let best = f.best, best.end > Date() {
                Section("Make the most of it") {
                    if let t = FocusForecast.hardestTask(tasks) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Hardest task: \(t.title)").font(DS.Font.body)
                            Button(planned == t.title ? "Planned for \(best.start.formatted(date: .omitted, time: .shortened)) ✓" : "Put it in your best window") {
                                t.dueDate = max(best.start, Date())
                                t.isPinned = true
                                t.updatedAt = Date()
                                TaskAlerts.schedule(t)
                                planned = t.title
                                Haptics.success()
                            }
                            .buttonStyle(.borderless).disabled(planned == t.title)
                        }
                    }
                    ForEach(FocusForecast.meetingsInPeak(f), id: \.eventIdentifier) { e in
                        Label("“\(e.title ?? "Meeting")” at \(e.startDate.formatted(date: .omitted, time: .shortened)) uses your best focus time. Could it move to your low point?",
                              systemImage: "exclamationmark.bubble")
                            .font(DS.Font.caption).foregroundStyle(DS.Palette.warmth)
                    }
                }
            }

            Section {
                if meds.isEmpty {
                    Text("Add medications in Today → ⊞ → Medications to include them. Without them, the forecast uses your daily rhythm, sleep and focus history.")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                ForEach(meds.filter(\.isActive)) { m in
                    MedTimingRow(med: m) { tick += 1; Task { await FocusForecast.refresh(ctx: ctx) } }
                }
            } header: { Text("How your meds work for you") } footer: {
                Text(hasFocusMed ? "Logged doses are used when you've taken them; otherwise your scheduled times." :
                        "Tell Keel which medications help you focus, and roughly how long they last for you.")
            }
        }
        .navigationTitle("Focus Forecast")
        .task {
            sleep = checkIns.first { Calendar.current.isDateInToday($0.day) }?.sleepHours
            if sleep == nil { sleep = await HealthService.shared.lastNightSleepHours() }
        }
    }
}

private struct MedTimingRow: View {
    let med: Medication
    let changed: () -> Void
    @State private var timing = FocusForecast.Timing()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(med.name + (med.dose.isEmpty ? "" : " \(med.dose)"), selection: Binding(get: { timing.profile }, set: { p in
                timing = FocusForecast.preset(p); save()
            })) {
                ForEach(FocusForecast.Profile.allCases) { Text($0.label).tag($0) }
            }
            if timing.profile == .custom {
                Stepper("Starts working after \(timing.onsetMinutes) min", value: Binding(get: { timing.onsetMinutes }, set: { timing.onsetMinutes = $0; save() }), in: 0...180, step: 15)
                Stepper(String(format: "Helps for about %.1f h", timing.hours), value: Binding(get: { timing.hours }, set: { timing.hours = $0; save() }), in: 1...16, step: 0.5)
            }
        }
        .onAppear { timing = FocusForecast.timing(for: med) }
    }

    private func save() { FocusForecast.setTiming(timing, for: med); changed() }
}

/// Today card: your best focus window, and what to put in it.
struct FocusForecastCard: View {
    @Query private var meds: [Medication]
    @Query private var doses: [MedDose]
    @Query(sort: \FocusSession.startedAt) private var sessions: [FocusSession]
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var tasks: [TaskItem]
    @Query(sort: \CheckIn.day, order: .reverse) private var checkIns: [CheckIn]

    var body: some View {
        let sleep = checkIns.first { Calendar.current.isDateInToday($0.day) }?.sleepHours
        let f = FocusForecast.build(meds: meds, doses: doses, sleepHours: sleep, sessions: sessions)
        // Only once it's personal: a focus med is set up, or there's enough focus history to learn from.
        let personal = meds.contains { FocusForecast.timing(for: $0).profile != .none } || sessions.count >= 8
        if FocusForecast.isOn, personal, let best = f.peaks.first(where: { $0.end > Date() }) {
            NavigationLink { FocusForecastView() } label: {
                GlassCard(tint: DS.Palette.focus) {
                    HStack(spacing: DS.Space.m) {
                        Image(systemName: best.start <= Date() ? "bolt.fill" : "sparkles").font(.title2).foregroundStyle(DS.Palette.focus)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(best.start <= Date() ? "You're in your focus window" : "Best focus today: \(best.label)")
                                .font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                            if let t = FocusForecast.hardestTask(tasks) {
                                Text("Save it for: \(t.title)").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(DS.Palette.inkSoft)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}
