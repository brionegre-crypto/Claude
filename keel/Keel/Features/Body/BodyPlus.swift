import SwiftUI
import SwiftData
import EventKit
import UserNotifications
#if !targetEnvironment(macCatalyst)
import AlarmKit
#endif

// MARK: - Smart wake alarm

/// A real alarm (rings through Silent and Focus) at the wake time the sleep coach planned for you.
enum SmartWake {
    static let key = "body.wakeAlarm"
    static var on: Bool { UserDefaults.standard.bool(forKey: key) }
    static let id = UUID(uuidString: "6B1D2C3E-5A1E-4000-8000-00000000A1A1")!

    @MainActor static func schedule(at wake: Date) async {
        #if !targetEnvironment(macCatalyst)
        try? AlarmManager.shared.cancel(id: id)
        guard on, wake > Date(), await TaskAlarms.authorize() else { return }
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: "Good morning"),
            stopButton: AlarmButton(text: "I'm up", textColor: .white, systemImageName: "sun.max.fill"))
        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert),
                                         metadata: KeelAlarmMetadata(taskId: "wake"),
                                         tintColor: BodyStyle.anchor)
        let config = AlarmManager.AlarmConfiguration<KeelAlarmMetadata>(
            countdownDuration: nil, schedule: .fixed(wake), attributes: attributes,
            stopIntent: nil, secondaryIntent: nil, sound: .default)
        _ = try? await AlarmManager.shared.schedule(id: id, configuration: config)
        #endif
    }

    @MainActor static func cancel() {
        #if !targetEnvironment(macCatalyst)
        try? AlarmManager.shared.cancel(id: id)
        #endif
    }
}

// MARK: - Caffeine & water

struct Drink: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: String
    var at: Date
    var caffeine: Int          // mg
    var water: Int             // ml
}

@MainActor
enum Drinks {
    static let key = "drinks.log", goalKey = "drinks.waterGoal"
    struct Preset { let kind: String; let label: String; let icon: String; let caffeine: Int; let water: Int }
    static let presets: [Preset] = [
        .init(kind: "water", label: "Water", icon: "drop.fill", caffeine: 0, water: 250),
        .init(kind: "coffee", label: "Coffee", icon: "cup.and.saucer.fill", caffeine: 95, water: 240),
        .init(kind: "espresso", label: "Espresso", icon: "cup.and.heat.waves.fill", caffeine: 65, water: 30),
        .init(kind: "tea", label: "Tea", icon: "mug.fill", caffeine: 45, water: 240),
        .init(kind: "energy", label: "Energy drink", icon: "bolt.fill", caffeine: 160, water: 250),
        .init(kind: "cola", label: "Cola", icon: "takeoutbag.and.cup.and.straw.fill", caffeine: 35, water: 330),
    ]

    static var goal: Int { let g = UserDefaults.standard.integer(forKey: goalKey); return g > 0 ? g : 2_000 }
    static var all: [Drink] {
        get { LocalLog.load(key) }
        set {
            let keep = newValue.filter { $0.at > Date().addingTimeInterval(-14 * 86_400) }
            UserDefaults.standard.set(try? JSONEncoder().encode(keep), forKey: key)
        }
    }
    static var today: [Drink] { all.filter { Calendar.current.isDateInToday($0.at) }.sorted { $0.at < $1.at } }
    static var caffeineToday: Int { today.reduce(0) { $0 + $1.caffeine } }
    static var waterToday: Int { today.reduce(0) { $0 + $1.water } }

    /// Caffeine lasts: stop about 8 hours before tonight's bedtime.
    static func cutoff(bedtime: Date) -> Date { bedtime.addingTimeInterval(-8 * 3600) }

    static func add(_ p: Preset) {
        all = all + [Drink(kind: p.kind, at: Date(), caffeine: p.caffeine, water: p.water)]
        if p.caffeine > 0, Calendar.current.component(.hour, from: Date()) >= 14 {
            let k = BodyMath.dayKey(Date())
            if !(BodyEngine.shared.journal[k] ?? []).contains("Caffeine after 2 PM") { BodyEngine.shared.toggle("Caffeine after 2 PM", on: Date()) }
        }
        Haptics.tap()
        scheduleWaterNudge()
    }
    static func undoLast() {
        guard let last = today.last else { return }
        all = all.filter { $0.id != last.id }
        scheduleWaterNudge()
    }

    /// One gentle "drink some water" nudge at the next even hour (10 AM–6 PM) if you're behind your pace.
    static func scheduleWaterNudge(now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["drinks.water"])
        guard UserDefaults.standard.object(forKey: "drinks.nudge") as? Bool ?? true else { return }
        let cal = Calendar.current
        let h = cal.component(.hour, from: now)
        let nextHour = h % 2 == 0 ? h + 2 : h + 1
        guard nextHour >= 10, nextHour <= 18, let at = cal.date(bySettingHour: nextHour, minute: 0, second: 0, of: now) else { return }
        let pace = Double(goal) * Double(nextHour - 8) / 12            // spread across 8 AM–8 PM
        guard Double(waterToday) < pace * 0.8 else { return }
        let c = UNMutableNotificationContent()
        c.title = "Time for some water"
        c.body = "\(waterToday) of \(goal) ml so far today. Tap + in Keel → Body when you've had a glass."
        c.userInfo = ["deeplink": "com.keel.app://tool/body"]
        center.add(UNNotificationRequest(identifier: "drinks.water", content: c,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: at), repeats: false)))
    }
}

struct DrinksCard: View {
    @State private var tick = 0
    @AppStorage(Drinks.goalKey) private var goal = 2_000
    var body: some View {
        let _ = tick
        let tn = BodyMath.tonight(BodyEngine.shared.days, base: BodyPrefs.sleepNeed)
        let cutoff = Drinks.cutoff(bedtime: tn.bedtime)
        let caffeine = Drinks.caffeineToday, water = Drinks.waterToday
        VStack(alignment: .leading, spacing: 10) {
            Label("Caffeine & water", systemImage: "cup.and.saucer.fill").font(DS.Font.headline).foregroundStyle(.brown)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Drinks.presets, id: \.kind) { p in
                        Button { Drinks.add(p); tick += 1 } label: {
                            VStack(spacing: 4) {
                                Image(systemName: p.icon).font(.title3)
                                Text(p.label).font(.caption2)
                            }
                            .frame(width: 70, height: 58)
                            .background(DS.Palette.canvas, in: .rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Log \(p.label)")
                    }
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Water").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                    ProgressView(value: min(1, Double(water) / Double(max(1, goal)))).tint(.cyan)
                    Text("\(water) of \(goal) ml").font(.caption2).monospacedDigit()
                }
                Spacer(minLength: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Caffeine").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                    Text("\(caffeine) mg").font(DS.Font.headline).monospacedDigit().foregroundStyle(caffeine > 400 ? .red : DS.Palette.ink)
                }
            }
            Text(Date() < cutoff
                 ? "Last caffeine by \(cutoff.formatted(date: .omitted, time: .shortened)) to sleep well by \(tn.bedtime.formatted(date: .omitted, time: .shortened))."
                 : "Past your caffeine cut-off for tonight. Water or decaf from here.")
                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            if !Drinks.today.isEmpty {
                Button("Undo last", systemImage: "arrow.uturn.backward") { Drinks.undoLast(); tick += 1 }.font(.caption)
            }
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { PremiumSurface() }
    }
}

// MARK: - Today's workout pick

enum WorkoutPick {
    struct Pick { let title: String; let detail: String; let minutes: Int; let icon: String }

    static func pick(tide: Int?, swell: Int) -> Pick {
        let target = BodyMath.swellTarget(tide)
        if swell > target.upperBound {
            return Pick(title: "You've done enough today", detail: "Swell is already above your target. Stretch, walk and rest so tomorrow's Tide stays high.", minutes: 15, icon: "figure.cooldown")
        }
        guard let t = tide else {
            return Pick(title: "Easy movement", detail: "A brisk walk or light ride, 20–30 minutes. Keel will tailor this once it knows your Tide.", minutes: 30, icon: "figure.walk")
        }
        if t >= 67 { return Pick(title: "Push day", detail: "Intervals, a hard run or heavy strength work, 40–60 minutes. Your body is ready for it.", minutes: 50, icon: "figure.run") }
        if t >= 34 { return Pick(title: "Steady day", detail: "Moderate cardio or strength, 30–45 minutes, at a pace where you could still talk.", minutes: 40, icon: "figure.strengthtraining.traditional") }
        return Pick(title: "Recovery day", detail: "Rest, or something gentle: a walk, stretching or yoga, 20–30 minutes.", minutes: 25, icon: "figure.yoga")
    }

    /// Puts it in your first free slot today that's long enough (before 8 PM).
    @MainActor static func block(_ p: Pick) -> Date? {
        let svc = CalendarService.shared
        guard let slot = svc.freeSlots(minMinutes: p.minutes + 10, from: Date().addingTimeInterval(15 * 60), until: 20).first else { return nil }
        let e = EKEvent(eventStore: svc.store)
        e.calendar = svc.store.defaultCalendarForNewEvents
        e.title = "\(p.title)"
        e.startDate = slot.start
        e.endDate = slot.start.addingTimeInterval(Double(p.minutes * 60))
        e.notes = p.detail
        guard (try? svc.store.save(e, span: .thisEvent)) != nil else { return nil }
        svc.invalidateEvents()
        return slot.start
    }
}

struct WorkoutPickCard: View {
    let tide: Int?
    let swell: Int
    @State private var message: String?
    var body: some View {
        let p = WorkoutPick.pick(tide: tide, swell: swell)
        VStack(alignment: .leading, spacing: 8) {
            Label("Today's workout", systemImage: p.icon).font(DS.Font.headline).foregroundStyle(BodyStyle.swell)
            Text(p.title).font(DS.Font.body.weight(.semibold))
            Text(p.detail).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            Button {
                if let at = WorkoutPick.block(p) { message = "Added at \(at.formatted(date: .omitted, time: .shortened))."; Haptics.success() }
                else { message = "No free \(p.minutes)-minute slot left today." }
            } label: { Label("Put it on my calendar", systemImage: "calendar.badge.plus") }
                .buttonStyle(.bordered).font(DS.Font.caption)
            if let c = BodyMapData.caution() { Label(c, systemImage: "figure.stand").font(.caption).foregroundStyle(.orange) }
            if let message { Text(message).font(.caption2).foregroundStyle(DS.Palette.inkSoft) }
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { PremiumSurface() }
    }
}

// MARK: - Mood × body

extension BodyMath {
    /// Plain-language links between your mood, focus, sleep and Tide (only when there's enough to say something).
    static func moodInsights(moods: [(day: Date, mood: Int)], focus: [(day: Date, finished: Bool)], days: [BodyDay]) -> [String] {
        let cal = Calendar.current
        var byDay: [Date: BodyDay] = [:]
        for d in days { byDay[cal.startOfDay(for: d.day)] = d }
        func avg(_ v: [Int]) -> Double { Double(v.reduce(0, +)) / Double(max(1, v.count)) }
        var out: [String] = []

        let short = moods.filter { m in byDay[cal.startOfDay(for: m.day)].map { $0.hasSleep && $0.asleep < 360 } ?? false }.map(\.mood)
        let rested = moods.filter { m in byDay[cal.startOfDay(for: m.day)].map { $0.asleep >= 420 } ?? false }.map(\.mood)
        if short.count >= 3, rested.count >= 3 {
            let diff = avg(rested) - avg(short)
            if abs(diff) >= 0.3 {
                out.append(String(format: "After nights under 6 hours your mood is %.1f points %@ (%.1f vs %.1f after 7+ hours).",
                                  abs(diff), diff > 0 ? "lower" : "higher", avg(short), avg(rested)))
            }
        }
        let high = moods.filter { m in (byDay[cal.startOfDay(for: m.day)]?.tide ?? 0) >= 67 }.map(\.mood)
        let low = moods.filter { m in (byDay[cal.startOfDay(for: m.day)]?.tide ?? 100) < 34 }.map(\.mood)
        if high.count >= 3, low.count >= 3 {
            out.append(String(format: "On high-Tide days your mood averages %.1f; on low-Tide days %.1f.", avg(high), avg(low)))
        }
        let fHigh = focus.filter { f in (byDay[cal.startOfDay(for: f.day)]?.tide ?? 0) >= 67 }
        let fLow = focus.filter { f in (byDay[cal.startOfDay(for: f.day)]?.tide ?? 100) < 34 }
        if fHigh.count >= 4, fLow.count >= 4 {
            let a = Double(fHigh.filter(\.finished).count) / Double(fHigh.count) * 100
            let b = Double(fLow.filter(\.finished).count) / Double(fLow.count) * 100
            out.append(String(format: "You finish %.0f%% of focus sessions on high-Tide days and %.0f%% on low-Tide days.", a, b))
        }
        return out
    }
}

struct MoodBodyCard: View {
    @Query(sort: \CheckIn.day, order: .reverse) private var checkIns: [CheckIn]
    @Query(sort: \FocusSession.startedAt, order: .reverse) private var sessions: [FocusSession]
    var body: some View {
        let insights = BodyMath.moodInsights(
            moods: checkIns.prefix(90).filter { $0.mood > 0 }.map { (day: $0.day, mood: $0.mood) },
            focus: sessions.prefix(300).filter { $0.endedAt != nil }.map { (day: $0.startedAt, finished: !$0.brokeEarly) },
            days: BodyEngine.shared.days)
        VStack(alignment: .leading, spacing: 8) {
            Label("Mood & focus", systemImage: "face.smiling").font(DS.Font.headline).foregroundStyle(.yellow)
            if insights.isEmpty {
                Text("Do your mood check-ins and focus sessions for a couple of weeks; Keel will show how your sleep and Tide affect them.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            } else {
                ForEach(insights, id: \.self) { Text("• \($0)").font(DS.Font.caption) }
            }
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { PremiumSurface() }
    }
}
