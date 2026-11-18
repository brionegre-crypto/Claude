import SwiftUI
import Charts

// MARK: - A guide for every Body metric
//
// Every score and measurement in Body has its own page: what it is, how Keel tracks it (which sensor, when, and
// where it comes from), how it's worked out, what's a typical range, what moves it up or down, how to improve it,
// how much to trust it, and your own recent numbers. Open one from the ⓘ on any Body card, from a metric's detail
// page, or browse them all from "Metric guides".

struct MetricGuide: Identifiable {
    enum Series { case none, tide, swell, anchor, sleepHours, health(String) }
    let id: String
    let name: String
    let icon: String
    let color: Color
    let category: String
    let what: String
    let tracking: [String]
    var calculation: String? = nil
    let normal: String
    let moves: [String]
    let improve: [String]
    var accuracy: String = "Wrist sensors are very good at trends over days and weeks and less exact for any single reading. Watch your own pattern rather than one number."
    var series: Series = .none
}

@MainActor
enum MetricGuides {
    static let categories = ["Keel scores", "Sleep", "Training & recovery", "Energy & daily life", "Heart", "Activity", "Body",
                             "Vitals", "Walking & mobility", "Running", "Hearing", "Nutrition"]

    static func guide(_ id: String) -> MetricGuide? { all.first { $0.id == id } }

    static var all: [MetricGuide] { keel + HealthMetricCatalog.all.map(fromHealth) }

    // MARK: Keel's own scores and cards

    static let keel: [MetricGuide] = [
        .init(id: "tide", name: "Tide · recovery", icon: "water.waves", color: BodyStyle.tide, category: "Keel scores",
              what: "How recovered your body is this morning, from 0 to 100%. High Tide means you're ready to push; low Tide means today is better for easier work and rest.",
              tracking: ["Your Apple Watch measures heart rate variability (HRV) and resting heart rate while you sleep.",
                         "It also records breathing rate, blood oxygen and wrist temperature overnight.",
                         "Keel reads these from Apple Health each morning, along with last night's sleep.",
                         "It needs about a week of nights to learn your normal; until then the score says it's still calibrating."],
              calculation: "Last night's HRV and resting heart rate are compared with your own 30-day normal: HRV above your normal and a lower resting heart rate raise Tide. Good sleep adds to it. A faster breathing rate or a raised wrist temperature lowers it, because they're early signs of illness or strain.",
              normal: "Most mornings land between 50 and 80%. Above 80% is a great day to train hard; under 40% means go easy.",
              moves: ["Up: a good night's sleep, an easy day yesterday, staying hydrated, time outdoors.",
                      "Down: alcohol (often the biggest single drop), late meals, poor or short sleep, a very hard workout, illness coming on, stress, travel."],
              improve: ["Keep a steady bedtime and get your sleep need (see Anchor).",
                        "Skip alcohol, especially in the 3 hours before bed.",
                        "Alternate hard and easy days instead of training hard every day.",
                        "Wear your Watch to bed every night so Keel can see the trend."],
              accuracy: "Tide is a guide built from your own baseline, so it's most useful compared with yourself over time. One low morning matters less than several in a row.",
              series: .tide),
        .init(id: "swell", name: "Swell · effort", icon: "wind", color: BodyStyle.swell, category: "Keel scores",
              what: "How much strain you've put on your heart today, from 0 to 100. Workouts count, and so do busy days on your feet.",
              tracking: ["Your Apple Watch records heart rate throughout the day and during workouts.",
                         "Keel reads every heart-rate reading and works out how long you spent in each heart-rate zone.",
                         "Workouts recorded in Apple Health (from the Workout app or other fitness apps) are listed with their own Swell."],
              calculation: "Time in each zone is weighted, harder zones much more than easy ones, and added up through the day. The scale curves: getting from 10 to 20 is easy, from 80 to 90 takes a very hard effort.",
              normal: "A typical active day is 30–60. Over 70 is a hard training day. Your target range adjusts to your Tide each morning.",
              moves: ["Up: workouts, brisk walking, climbing stairs, heat and stress (they raise heart rate too).",
                      "Down: rest days and gentle movement."],
              improve: ["Aim for the target range Keel shows: more on high-Tide days, less on low ones.",
                        "Mix easy days (under 40) with a few harder ones each week.",
                        "If Swell stays high while Tide keeps dropping, you're doing more than you're recovering from."],
              series: .swell),
        .init(id: "anchor", name: "Anchor · sleep", icon: "moon.zzz.fill", color: BodyStyle.anchor, category: "Keel scores",
              what: "How well you slept last night, from 0 to 100, compared with what you needed.",
              tracking: ["Your Apple Watch (or iPhone sleep schedule, or another sleep app) records when you were asleep and in which sleep stage.",
                         "Keel reads the night from Apple Health each morning. When several apps record sleep, Keel prefers the Watch."],
              calculation: "Hours slept against your sleep need (55 points), how much of your time in bed you were actually asleep (15), deep and REM sleep (15), and how close your bedtime was to your usual one (15).",
              normal: "80+ is a strong night; 60–80 is fine; under 60 means you're running short.",
              moves: ["Up: enough hours, a regular bedtime, a dark, cool room, no caffeine after midday.",
                      "Down: going to bed late, alcohol, screens and work late at night, a warm room, caffeine in the afternoon."],
              improve: ["Use the bedtime Keel suggests under Anchor (\"Lights out by…\").",
                        "Keep bedtime within about 30 minutes of your usual, weekends included.",
                        "Stop caffeine 8–10 hours before bed (see the caffeine curve)."],
              series: .anchor),
        .init(id: "sleepNeed", name: "Sleep need", icon: "bed.double.fill", color: BodyStyle.anchor, category: "Sleep",
              what: "How much sleep you need tonight, and the bedtime that gets you there before you have to wake.",
              tracking: ["Starts from your base need (8 hours unless you change it in Body settings).",
                         "Adds a little after a high-Swell day, and part of any sleep debt from recent nights."],
              calculation: "Base need + extra for today's effort + a third of the sleep you've missed over the last few nights. Bedtime = your usual wake time minus that need.",
              normal: "Most adults need 7–9 hours. The extra for a hard day is usually 15–40 minutes.",
              moves: ["Up: hard training, sleep debt, illness.", "Down: easy days and paying back debt."],
              improve: ["Set your real base need in Body settings if 8 hours isn't right for you.", "Go to bed at the time Keel suggests a few nights in a row to clear debt."],
              series: .sleepHours),
        .init(id: "sleepStages", name: "Sleep stages", icon: "chart.bar.fill", color: BodyStyle.anchor, category: "Sleep",
              what: "How your night split between deep, core (light), REM sleep and time awake.",
              tracking: ["Your Apple Watch estimates stages from movement and heart rate while you sleep, and saves them to Apple Health."],
              normal: "Typical adult nights: deep 10–20%, REM 20–25%, core about half, and a few short wakings (normal, you won't remember most).",
              moves: ["Deep sleep is higher early in the night and after hard exercise; alcohol cuts REM; a late bedtime shortens REM, which comes mostly near morning."],
              improve: ["Regular sleep times protect REM.", "Avoid alcohol before bed.", "Exercise earlier in the day helps deep sleep."],
              accuracy: "Stage estimates from a wrist are approximate; total sleep time is much more reliable than the split between stages."),
        .init(id: "sleepDebt", name: "Sleep debt", icon: "hourglass.bottomhalf.filled", color: BodyStyle.anchor, category: "Sleep",
              what: "How much sleep you've missed recently compared with your need.",
              tracking: ["Adds up the gap between sleep need and sleep you got over the last 7 nights, from Apple Health."],
              normal: "Under 2 hours is fine. Over 5 hours and most people notice it in focus and mood.",
              moves: ["Up: short nights.", "Down: nights longer than your need, naps."],
              improve: ["Pay it back gradually: 30–60 minutes earlier to bed for a few nights works better than one long lie-in."]),
        .init(id: "stress", name: "Stress through the day", icon: "waveform.path.ecg", color: .orange, category: "Energy & daily life",
              what: "When your body showed signs of stress during the day, hour by hour.",
              tracking: ["Uses your heart rate while you're not exercising, compared with your resting heart rate, from your Apple Watch."],
              calculation: "An hour is marked when your heart rate stays well above resting without a workout or much movement explaining it.",
              normal: "A few stressed hours on a busy day is normal; many days in a row with a lot of them is worth noticing.",
              moves: ["Up: deadlines, conflict, caffeine, poor sleep, illness, heat.", "Down: breaks, breathing exercises, walks, time outside."],
              improve: ["Try a 2-minute Breathe session when you see stressed hours stacking up.", "Plan breaks after long meetings."],
              accuracy: "It can't tell excitement from stress, and any heart-rate rise without movement looks the same."),
        .init(id: "energyBank", name: "Energy bank", icon: "battery.75percent", color: .green, category: "Energy & daily life",
              what: "How much energy you have left for the day, like a battery: it starts from your Tide and drains with effort and stress.",
              tracking: ["Starts each morning from Tide (recovery) and Anchor (sleep).", "Drains with Swell (effort) and stressed hours, through the day."],
              normal: "Above 50% you have room to spare; below 25%, protect the evening.",
              moves: ["Up: a good night.", "Down: hard workouts, long stressed stretches, short sleep."],
              improve: ["Put demanding work where your energy is highest (often late morning).", "On low-bank days, choose easier tasks and an earlier night."]),
        .init(id: "cardioLoad", name: "Cardio load", icon: "heart.circle.fill", color: .pink, category: "Training & recovery",
              what: "How your training this week compares with what you've been doing over the last month.",
              tracking: ["Built from daily Swell (heart-rate effort) from your Apple Watch."],
              calculation: "This week's average daily load divided by your 4-week average. Around 1.0 is steady; 0.8–1.3 is a healthy build; above 1.5 is a sharp jump.",
              normal: "Most training sits between 0.8 and 1.3.",
              moves: ["Up: adding sessions or intensity quickly.", "Down: rest weeks, illness, travel."],
              improve: ["Build gradually: about 10% more each week.", "After a sharp jump, plan an easier week."]),
        .init(id: "zones", name: "Heart-rate zones", icon: "heart.text.square.fill", color: .red, category: "Training & recovery",
              what: "How long you spent at each intensity today, from easy (zone 1) to all-out (zone 5).",
              tracking: ["Heart rate from your Apple Watch, compared with your maximum heart rate (from your age, or the number you set)."],
              calculation: "Zone 1: 50–60% of max, zone 2: 60–70%, zone 3: 70–80%, zone 4: 80–90%, zone 5: 90%+.",
              normal: "Most fitness gains come from lots of zone 2 and a little zone 4–5 each week.",
              moves: ["Heat, dehydration, caffeine and tiredness push you into higher zones at the same pace."],
              improve: ["Do most cardio at a pace where you can still talk (zone 2).", "Set your real max heart rate in Body settings if you know it."]),
        .init(id: "recovery", name: "Muscle readiness", icon: "figure.stand", color: .green, category: "Training & recovery",
              what: "How ready each muscle is to train, shown on the Recovery map.",
              tracking: ["Strength sets you log in Keel (which muscles each exercise uses, and how hard).",
                         "Workouts from Apple Health (a run works your legs, a swim your back and shoulders).",
                         "Soreness or pain you log by tapping the map."],
              calculation: "Each workout adds fatigue to the muscles it uses, fading over about 2–3 days. Logged soreness caps readiness until it's gone.",
              normal: "Fresh (80–100%) muscles are ready for hard work; 50–80% are recovering; under 50% need rest or light work.",
              moves: ["Down: training that muscle, logging soreness.", "Up: rest days, sleep."],
              improve: ["Train fresh muscle groups and rest tired ones.", "Log soreness and pain so Keel can steer your workout picks."]),
        .init(id: "bioAge", name: "Biological age", icon: "hourglass.circle.fill", color: .purple, category: "Training & recovery",
              what: "An estimate of how old your body seems from your fitness and health measures, compared with your actual age.",
              tracking: ["Uses cardio fitness (VO₂ max), resting heart rate, heart rate variability, sleep, activity and, if you've added them, body measurements and lab results from Apple Health."],
              calculation: "Each measure is compared with typical values for people of different ages, weighted by how strongly it relates to long-term health.",
              normal: "Within a few years of your real age is typical. Lower is better.",
              moves: ["Down (younger): better cardio fitness, regular exercise, good sleep, healthy weight.", "Up: inactivity, poor sleep, smoking."],
              improve: ["Cardio fitness has the biggest effect: regular brisk walks, runs or rides.", "Strength training twice a week.", "Steady sleep."],
              accuracy: "A motivating estimate, not a medical test. Watch whether it moves over months."),
        .init(id: "illness", name: "Illness warning", icon: "thermometer.medium", color: .orange, category: "Training & recovery",
              what: "A heads-up when your overnight body signals look like the start of an illness.",
              tracking: ["Overnight resting heart rate, heart rate variability, breathing rate and wrist temperature from your Apple Watch."],
              calculation: "When several of these move away from your normal at the same time (higher heart rate and breathing, lower HRV, warmer wrist), Keel flags it.",
              normal: "Most weeks show no warning.",
              moves: ["Alcohol, a very hard workout, heat and travel can trigger a false alarm."],
              improve: ["If you get a warning, take it easy, drink water and sleep more; check again tomorrow."],
              accuracy: "An early nudge, not a diagnosis."),
        .init(id: "nutritionScore", name: "Nutrition score", icon: "leaf.fill", color: .green, category: "Nutrition",
              what: "How well what you ate today fits your goals and a balanced diet.",
              tracking: ["Meals you log in Keel (search, scan or photo), and food logged in other apps through Apple Health."],
              calculation: "Protein, fibre, fruit and vegetables, added sugar and calories are compared with your targets.",
              normal: "70+ is a well-balanced day.",
              moves: ["Up: protein at each meal, vegetables, whole foods.", "Down: lots of added sugar or ultra-processed food, skipping meals."],
              improve: ["Add a protein and a vegetable to each meal.", "Log while you eat; it's easier than remembering later."]),
        .init(id: "caffeine", name: "Caffeine curve", icon: "cup.and.saucer.fill", color: .brown, category: "Nutrition",
              what: "How much caffeine is still in your system now and at bedtime.",
              tracking: ["Drinks you log in Keel (or caffeine logged in other apps through Apple Health)."],
              calculation: "Caffeine halves about every 5 hours, so Keel adds up each drink and fades it over time.",
              normal: "Under 50 mg at bedtime is best for sleep. Most adults do well under 400 mg a day.",
              moves: ["Up: coffee, tea, energy drinks, cola, some pre-workouts."],
              improve: ["Have your last caffeine 8–10 hours before bed."]),
        .init(id: "activity", name: "Activity today", icon: "figure.walk", color: .green, category: "Energy & daily life",
              what: "Steps, exercise minutes and active energy so far today.",
              tracking: ["Your iPhone counts steps; your Apple Watch adds exercise minutes, stand time and active energy. Keel reads them from Apple Health."],
              normal: "7,000–10,000 steps and 30 exercise minutes a day is a solid target.",
              moves: ["Up: walks, stairs, workouts.", "Down: long sitting stretches."],
              improve: ["A 10-minute walk after meals adds up fast and helps blood sugar."]),
        .init(id: "cycle", name: "Cycle", icon: "drop.fill", color: .pink, category: "Energy & daily life",
              what: "Where you are in your menstrual cycle and how it may affect energy, sleep and training.",
              tracking: ["Cycle data logged in the Health app or a cycle-tracking app, read from Apple Health. Wrist temperature can help estimate ovulation."],
              normal: "Cycles of 21–35 days are typical.",
              moves: ["Many people notice lower Tide and higher resting heart rate in the days before a period."],
              improve: ["Plan harder training earlier in your cycle if you notice a pattern."]),
    ]

    // MARK: Apple Health measurements

    private static func fromHealth(_ m: HealthMetric) -> MetricGuide {
        let x = extra[m.id]
        let source: [String] = x?.source.map { [$0] } ?? [defaultSource(m)]
        return MetricGuide(id: "h." + m.id, name: m.name, icon: icon(m.category), color: .red, category: m.category,
                           what: m.about,
                           tracking: source + ["Keel reads it from Apple Health and keeps it on this device."],
                           normal: x?.normal ?? "Compare with your own recent average: a steady trend matters more than one reading.",
                           moves: x?.moves ?? [],
                           improve: x?.improve ?? [],
                           series: .health(m.id))
    }

    private static func defaultSource(_ m: HealthMetric) -> String {
        switch m.category {
        case "Nutrition": "Logged by you, in Keel or another app that saves to Apple Health."
        case "Body": "From a smart scale, another app, or entered by you in the Health app."
        case "Walking & mobility": "Measured by your iPhone in your pocket (or Apple Watch) as you walk."
        case "Running": "Measured by your Apple Watch during outdoor and indoor runs."
        case "Hearing": "Measured by your Apple Watch microphone (surroundings) or your AirPods/headphones."
        default: "Measured by your Apple Watch."
        }
    }

    private static func icon(_ category: String) -> String {
        switch category {
        case "Heart": "heart.fill"
        case "Activity": "flame.fill"
        case "Body": "figure.arms.open"
        case "Vitals": "waveform.path.ecg"
        case "Walking & mobility": "figure.walk"
        case "Running": "figure.run"
        case "Hearing": "ear.fill"
        case "Nutrition": "fork.knife"
        default: "heart.text.clipboard"
        }
    }

    private struct Extra { var source: String? = nil; var normal: String? = nil; var moves: [String]? = nil; var improve: [String]? = nil }

    private static let extra: [String: Extra] = [
        "hr": .init(normal: "Through the day, 60–100 bpm at rest is typical; it rises with any activity.",
                    moves: ["Up: exercise, caffeine, stress, heat, illness, dehydration.", "Down: rest, fitness, sleep."]),
        "rhr": .init(source: "Measured by your Apple Watch when you've been still for a while, mostly overnight.",
                     normal: "60–100 bpm is the usual adult range; fit people are often 50–60.",
                     moves: ["Up: poor sleep, alcohol, illness, stress, heat, overtraining.", "Down: regular cardio, good sleep."],
                     improve: ["Regular zone-2 cardio lowers it over weeks.", "Cut alcohol and late meals."]),
        "walkhr": .init(normal: "Typically 90–120 bpm; it drops as fitness improves.", improve: ["Walk more, and briskly."]),
        "hrv": .init(source: "Measured by your Apple Watch in short readings through the day and while you sleep.",
                     normal: "Varies hugely between people (about 20–100 ms); only your own trend is meaningful.",
                     moves: ["Up: rest, good sleep, fitness, relaxation.", "Down: stress, alcohol, illness, hard training, poor sleep."],
                     improve: ["Sleep, steady routines, slow breathing (Breathe), and cutting alcohol."]),
        "hrrec": .init(source: "Measured by your Apple Watch in the minute after you end a hard workout.",
                       normal: "A drop of more than 20 bpm in the first minute is good; under 12 is worth noticing.",
                       improve: ["Regular cardio improves it."]),
        "vo2": .init(source: "Estimated by your Apple Watch during outdoor walks, runs and hikes with enough effort.",
                     normal: "Depends on age and sex; higher is better. Apple Health shows where you sit for your age.",
                     moves: ["Up: regular cardio, especially some harder efforts.", "Down: weeks of inactivity."],
                     improve: ["Walk briskly uphill, run or cycle 3+ times a week, with one harder session."]),
        "afib": .init(normal: "Ask your doctor what your number means for you.", improve: ["Share it with your doctor; Keel can include it in For my doctor."]),
        "steps": .init(source: "Counted by your iPhone and Apple Watch.", normal: "7,000–10,000 a day is a good target.",
                       improve: ["Walk while on calls.", "Take the stairs.", "A walk after each meal."]),
        "dist": .init(source: "Measured by your iPhone and Apple Watch as you walk and run."),
        "flights": .init(source: "Counted by your iPhone's barometer as you climb.", normal: "10+ floors a day is a great everyday habit."),
        "active": .init(normal: "Depends on your size and goals; the Move ring target in the Fitness app is a good guide."),
        "resting": .init(source: "Estimated by your Apple Watch from your size, age and sex.", normal: "Usually 1,200–2,000 kcal a day."),
        "exercise": .init(source: "Counted by your Apple Watch for any movement at brisk-walk intensity or above.", normal: "30 minutes a day / 150 a week."),
        "stand": .init(source: "Counted by your Apple Watch when you stand and move around."),
        "effort": .init(source: "Measured by your Apple Watch from movement and heart rate.", normal: "Under 3 is light, 3–6 moderate, above 6 vigorous."),
        "daylight": .init(source: "Measured by your Apple Watch's light sensor.", normal: "At least 20–30 minutes a day, ideally in the morning.",
                          improve: ["Take calls or a coffee outside in the morning."]),
        "weight": .init(normal: "Day-to-day swings of 1–2 kg (2–4 lb) are mostly water and food; watch the weekly average.",
                        improve: ["Weigh at the same time each morning for a clean trend."]),
        "bmi": .init(normal: "18.5–24.9 is the usual healthy range, but it doesn't account for muscle."),
        "fat": .init(normal: "Healthy ranges are roughly 10–20% for men and 18–28% for women, varying with age."),
        "resp": .init(source: "Measured by your Apple Watch while you sleep.", normal: "12–20 breaths a minute is typical; your own number is usually very steady.",
                      moves: ["Up: illness, alcohol, heat, stress."]),
        "spo2": .init(source: "Measured by your Apple Watch's blood oxygen sensor, mostly at rest and overnight.", normal: "95–100%. Short dips during sleep can be normal."),
        "wristtemp": .init(source: "Measured by your Apple Watch overnight (shown as a change from your normal).",
                           moves: ["Up: illness, alcohol, a warm room, the second half of a menstrual cycle."]),
        "sys": .init(source: "From a connected blood pressure cuff, or entered by you in Keel or the Health app.",
                     normal: "Under 120/80 is normal; 130/80 or more is high. Take readings at the same time, seated, after resting 5 minutes.",
                     improve: ["Less salt, more walking, less alcohol, good sleep."]),
        "dia": .init(source: "From a connected blood pressure cuff, or entered by you.", normal: "Under 80 is normal."),
        "glucose": .init(source: "From a glucose meter or continuous glucose monitor that saves to Apple Health.",
                         normal: "Fasting 70–100 mg/dL (3.9–5.6 mmol/L) is typical. Follow your doctor's targets if you have diabetes."),
        "breathing": .init(source: "Measured by your Apple Watch's motion sensor while you sleep.",
                           normal: "Apple marks readings as elevated when they're consistently high; talk to a doctor if they are."),
        "wspeed": .init(normal: "Around 4–5 km/h (2.5–3 mph) is typical."),
        "wasym": .init(normal: "Under 10% is typical."),
        "steady": .init(source: "Estimated by your iPhone from how you walk, and updated weekly.", normal: "\"OK\" is above 40%.",
                        improve: ["Balance and leg-strength exercises help; your iPhone suggests some in the Health app."]),
        "sixmin": .init(source: "Estimated weekly by your Apple Watch from your everyday walking."),
        "envaudio": .init(normal: "Under 80 dB is safe for long periods; over 90 dB, limit time."),
        "headphone": .init(normal: "Under 80 dB keeps your hearing safe.", improve: ["Turn on Reduce Loud Audio in Settings → Sounds & Haptics."]),
        "water": .init(normal: "About 2–3 litres a day from drinks, more when it's hot or you exercise.", improve: ["Turn on water nudges in Body settings."]),
        "protein": .init(normal: "About 1.2–1.6 g per kg of body weight a day if you train."),
        "caffeine": .init(normal: "Under 400 mg a day; none after early afternoon."),
    ]

    /// The id of the guide for a Health metric shown on its detail page.
    static func healthGuideId(_ metricId: String) -> String { "h." + metricId }
}

// MARK: - Screens

struct MetricGuideView: View {
    let guide: MetricGuide
    @State private var engine = BodyEngine.shared
    @State private var health = HealthMetricStore.shared

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: guide.icon).font(.title2).foregroundStyle(guide.color)
                        .frame(width: 44, height: 44).background(guide.color.opacity(0.12), in: .rect(cornerRadius: 12))
                    Text(guide.what).font(DS.Font.body)
                }
                .padding(.vertical, 4)
            }
            yours
            Section("How Keel tracks it") { bullets(guide.tracking) }
            if let c = guide.calculation { Section("How it's worked out") { Text(c) } }
            Section("What's typical") { Text(guide.normal) }
            if !guide.moves.isEmpty { Section("What moves it") { bullets(guide.moves) } }
            if !guide.improve.isEmpty { Section("How to improve it") { bullets(guide.improve) } }
            Section("How much to trust it") {
                Text(guide.accuracy)
                Text("Everything is worked out on your iPhone from Apple Health and isn't sent anywhere. It's for everyday wellbeing, not medical advice: talk to a doctor about anything that worries you.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
        }
        .navigationTitle(guide.name)
        .task {
            if case .health = guide.series { await health.load() }
        }
    }

    private func bullets(_ items: [String]) -> some View {
        ForEach(items, id: \.self) { s in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(guide.color).frame(width: 6, height: 6)
                Text(s)
            }
        }
    }

    /// Your own recent numbers, when Keel has them.
    @ViewBuilder private var yours: some View {
        let points = series
        if !points.isEmpty {
            Section("Your last 30 days") {
                Chart(points, id: \.date) { p in
                    LineMark(x: .value("Day", p.date, unit: .day), y: .value(guide.name, p.value)).foregroundStyle(guide.color).interpolationMethod(.catmullRom)
                    PointMark(x: .value("Day", p.date, unit: .day), y: .value(guide.name, p.value)).foregroundStyle(guide.color).symbolSize(12)
                }
                .frame(height: 150)
                let avg = points.map(\.value).reduce(0, +) / Double(points.count)
                LabeledContent("Latest", value: format(points.last?.value ?? 0))
                LabeledContent("30-day average", value: format(avg))
            }
        }
    }

    private var series: [(date: Date, value: Double)] {
        let days = Array(engine.days.suffix(30))
        switch guide.series {
        case .none: return []
        case .tide: return days.compactMap { d in d.tide.map { (date: d.day, value: Double($0)) } }
        case .anchor: return days.compactMap { d in d.anchor.map { (date: d.day, value: Double($0)) } }
        case .swell: return days.map { (date: $0.day, value: Double($0.swell)) }
        case .sleepHours: return days.filter(\.hasSleep).map { (date: $0.day, value: $0.asleep / 60) }
        case .health(let id):
            guard let m = HealthMetricCatalog.all.first(where: { $0.id == id }) else { return [] }
            return Array(health.series[id]?.days.suffix(30) ?? []).map { (date: $0.date, value: $0.value * m.scale) }
        }
    }

    private func format(_ v: Double) -> String {
        switch guide.series {
        case .health(let id):
            let m = HealthMetricCatalog.all.first { $0.id == id }
            return (m.map { $0.format(v / $0.scale) } ?? "\(Int(v))") + " " + (m?.unitLabel() ?? "")
        case .sleepHours: return v.formatted(.number.precision(.fractionLength(1))) + " h"
        default: return "\(Int(v.rounded()))"
        }
    }
}

/// Every Body metric's guide, by topic.
struct MetricGuideIndex: View {
    @State private var search = ""

    var body: some View {
        let all = MetricGuides.all
        List {
            Section {
                Text("What every score and measurement in Body means, how it's tracked, what's typical and how to improve it.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            ForEach(MetricGuides.categories, id: \.self) { cat in
                let items = all.filter { $0.category == cat && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.what.localizedCaseInsensitiveContains(search)) }
                if !items.isEmpty {
                    Section(cat) {
                        ForEach(items) { g in
                            NavigationLink { MetricGuideView(guide: g) } label: {
                                Label { Text(g.name) } icon: { Image(systemName: g.icon).foregroundStyle(g.color) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Metric guides")
        .searchable(text: $search, prompt: "Search metrics")
    }
}

/// The ⓘ on a Body card: opens that metric's guide.
struct MetricInfoButton: View {
    let id: String
    var body: some View {
        if let g = MetricGuides.guide(id) {
            NavigationLink { MetricGuideView(guide: g) } label: {
                Image(systemName: "info.circle").font(.body).foregroundStyle(DS.Palette.inkSoft)
                    .padding(6).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About \(g.name)")
        }
    }
}
