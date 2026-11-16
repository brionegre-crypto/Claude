import SwiftUI
import Charts

enum BodyStyle {
    static let tide = Color(red: 0.16, green: 0.62, blue: 0.80)      // sea blue
    static let swell = Color(red: 0.98, green: 0.52, blue: 0.36)     // breaking-wave coral
    static let anchor = Color(red: 0.42, green: 0.40, blue: 0.86)    // night indigo
    static func stressColor(_ v: Int?) -> Color {
        switch v { case 0: Color(red: 0.36, green: 0.75, blue: 0.62); case 1: .orange; case 2: .red; default: Color.gray.opacity(0.18) }
    }
}

/// A ring with a number in the middle.
struct ScoreRing: View {
    let title: String
    let value: Int?
    let max: Int
    let color: Color
    var suffix = ""
    var size: CGFloat = 92

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(color.opacity(0.16), lineWidth: size * 0.11)
                Circle().trim(from: 0, to: CGFloat(Swift.min(1, Double(value ?? 0) / Double(max))))
                    .stroke(color.gradient, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.6), value: value)
                VStack(spacing: 0) {
                    Text(value.map { "\($0)" } ?? "–").font(.system(size: size * 0.28, weight: .bold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    if !suffix.isEmpty { Text(suffix).font(.system(size: size * 0.12, weight: .semibold)).foregroundStyle(.secondary) }
                }
            }
            .frame(width: size, height: size)
            Text(title).font(DS.Font.caption.weight(.semibold)).foregroundStyle(color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value.map { "\($0)\(suffix == "%" ? " percent" : "")" } ?? "no data")")
    }
}

// MARK: - Today card

struct BodyTodayCard: View {
    @State private var engine = BodyEngine.shared
    var body: some View {
        NavigationLink { LazyView(BodyView()) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Body", systemImage: "water.waves").font(DS.Font.headline)
                    Spacer()
                    if engine.loading { ProgressView().controlSize(.small) }
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                if !BodyHealth.available {
                    if let s = BodyScores.fromYourIPhone() {
                        HStack(spacing: 0) {
                            ScoreRing(title: "Tide", value: s.tide, max: 100, color: BodyStyle.tide, suffix: "%", size: 64).frame(maxWidth: .infinity)
                            ScoreRing(title: "Swell", value: s.swell, max: 100, color: BodyStyle.swell, size: 64).frame(maxWidth: .infinity)
                            ScoreRing(title: "Anchor", value: s.anchor, max: 100, color: BodyStyle.anchor, size: 64).frame(maxWidth: .infinity)
                        }
                        Text("From your iPhone. " + BodyEngine.advice(s.tide)).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                    } else {
                        Text("Body tracking uses Apple Health on your iPhone. Today's scores show here once your iPhone has them.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                } else if !engine.connected {
                    Text("See how recovered you are, how hard your body worked and how well you slept. Tap to connect Apple Health.")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                } else {
                    let t = engine.today
                    HStack(spacing: 0) {
                        ScoreRing(title: "Tide", value: t?.tide, max: 100, color: BodyStyle.tide, suffix: "%", size: 64).frame(maxWidth: .infinity)
                        ScoreRing(title: "Swell", value: t?.swell, max: 100, color: BodyStyle.swell, size: 64).frame(maxWidth: .infinity)
                        ScoreRing(title: "Anchor", value: t?.anchor, max: 100, color: BodyStyle.anchor, size: 64).frame(maxWidth: .infinity)
                    }
                    Text(BodyEngine.advice(t?.tide)).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                }
            }
            .padding(DS.Space.m)
            .background { PremiumSurface() }
        }
        .buttonStyle(.plain)
        .task { await engine.refresh() }
    }
}

// MARK: - Body screen

struct BodyView: View {
    @State private var engine = BodyEngine.shared
    @State private var journalTick = 0
    @AppStorage(BodyPrefs.needKey) private var need = 8.0
    @AppStorage(BodyPrefs.maxHRKey) private var maxHR = 0
    @AppStorage(BodyPrefs.morningKey) private var morning = true
    @AppStorage(BodyPrefs.windDownKey) private var windDown = true
    @AppStorage(SmartWake.key) private var wakeAlarm = false
    @AppStorage(Drinks.goalKey) private var waterGoal = 2_000
    @AppStorage("drinks.nudge") private var waterNudge = true
    @State private var extras = HealthExtras()
    @AppStorage("body.page") private var pageRaw = BodyPage.today.rawValue
    @State private var selectedDay: Date?
    @State private var logDose = false
    @State private var logDest: BodyLogDest?

    enum BodyLogDest: Hashable { case symptoms, bp, sore, prn, fasting }

    private var page: Binding<BodyPage> {
        Binding(get: { BodyPage(rawValue: pageRaw) ?? .today }, set: { pageRaw = $0.rawValue })
    }
    private var live: Bool { BodyHealth.available && engine.connected }
    private var isToday: Bool { selectedDay == nil }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Space.m, pinnedViews: [.sectionHeaders]) {
                if !BodyHealth.available { iPhoneScores }
                Section {
                    Group {
                        switch page.wrappedValue {
                        case .today: todayPage
                        case .sleep: sleepPage
                        case .effort: effortPage
                        case .health: healthPage
                        case .habits: habitsPage
                        }
                    }
                    .transition(.opacity.combined(with: .offset(y: 6)))
                } header: {
                    BodyPageBar(page: page)
                }
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.bottom, DS.Space.l)
            .animation(.smooth(duration: 0.28), value: pageRaw)
        }
        .premiumBackground(BodyStyle.tide)
        .navigationTitle("Body")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { logMenu } }
        .sheet(isPresented: $logDose) { LogDoseSheet() }
        .navigationDestination(item: $logDest) { d in
            switch d {
            case .symptoms: SymptomsView()
            case .bp: BloodPressureView()
            case .sore: BodyMapView()
            case .prn: PRNView()
            case .fasting: FastingView()
            }
        }
        .refreshable { await engine.refresh(force: true); if engine.connected { extras = await HealthExtras.load() } }
        .task {
            await engine.refresh()
            if engine.connected { extras = await HealthExtras.load() }
        }
    }

    /// One menu for everything you might log, plus jumping between pages.
    private var logMenu: some View {
        Menu {
            Section("Log") {
                Button("Medication dose", systemImage: "pills.fill") { logDose = true }
                Button("As-needed medicine", systemImage: "cross.case.fill") { logDest = .prn }
                Button("Symptom", systemImage: "thermometer.medium") { logDest = .symptoms }
                Button("Blood pressure", systemImage: "heart.text.square.fill") { logDest = .bp }
                Button("Sore spot", systemImage: "figure.stand") { logDest = .sore }
                Button("Fast", systemImage: "timer") { logDest = .fasting }
            }
            Section("Go to") {
                ForEach(BodyPage.allCases) { p in
                    Button(p.rawValue, systemImage: p.icon) { withAnimation(.smooth) { pageRaw = p.rawValue } }
                }
            }
            if live {
                Button("Refresh from Apple Health", systemImage: "arrow.clockwise") {
                    Task { await engine.refresh(force: true); extras = await HealthExtras.load() }
                }
            }
        } label: {
            Label("Log", systemImage: "plus.circle.fill").symbolRenderingMode(.hierarchical)
        }
        .accessibilityLabel("Log or go to")
    }

    @ViewBuilder private var iPhoneScores: some View {
        // On Mac and iPad: today's scores from your iPhone.
        if let sc = BodyScores.fromYourIPhone() {
            HStack(spacing: 0) {
                ScoreRing(title: "Tide", value: sc.tide, max: 100, color: BodyStyle.tide, suffix: "%").frame(maxWidth: .infinity)
                ScoreRing(title: "Swell", value: sc.swell, max: 100, color: BodyStyle.swell).frame(maxWidth: .infinity)
                ScoreRing(title: "Anchor", value: sc.anchor, max: 100, color: BodyStyle.anchor).frame(maxWidth: .infinity)
            }
            Text("From your iPhone. " + BodyEngine.advice(sc.tide)).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
        } else {
            Text("Recovery, effort and sleep scores come from Apple Health on your iPhone and show here once it has them.")
                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
        }
    }

    @ViewBuilder private var todayPage: some View {
        if live {
            BodyDayStrip(days: engine.days, selected: $selectedDay)
            BodyHeroCard(day: t, days: engine.days, isToday: isToday)
            if engine.loading { ProgressView("Reading Apple Health…").font(DS.Font.caption).frame(maxWidth: .infinity) }
            if t?.calibrating ?? true {
                Label("Learning your normal: Tide gets accurate after about 5 nights with your Apple Watch.", systemImage: "hourglass")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            if !engine.loading, engine.days.suffix(3).allSatisfy({ !$0.hasSleep && $0.hrv == nil && $0.swell == 0 }) { noDataCard }
            if isToday { IllnessWarningCard(days: engine.days) }
            if isToday { adviceCard }
            EnergyBankCard(day: t, days: engine.days)
            BodyMetricsGrid(day: t, days: engine.days)
            BodyTimelineCard(day: t, date: t?.day ?? Date())
            NavigationLink { LazyView(AskBodyView()) } label: {
                Label("Ask about my body", systemImage: "sparkles").font(DS.Font.headline).frame(maxWidth: .infinity, alignment: .leading).bodyCard()
            }
            .buttonStyle(.plain)
            if isToday {
                stressCard
                NapAdvisorCard(tide: t?.tide)
                WorkoutPickCard(tide: t?.tide, swell: t?.swell ?? 0)
            } else {
                stressCard
            }
            BodyWeekCard(days: engine.days)
            RecoveryDriversCard(days: engine.days)
            BodyGoalsCard(days: engine.days)
        } else if BodyHealth.available {
            connectCard
        }
        EnergyCheckCard()
        if !live { DrinksCard() }
    }

    @ViewBuilder private var sleepPage: some View {
        if live {
            BodyDayStrip(days: engine.days, selected: $selectedDay)
            anchorCard
            BodyMetricsGrid(day: t, days: engine.days, metrics: [.sleep, .efficiency, .deep, .rem], title: "Sleep metrics")
            SleepScheduleCard(days: engine.days)
            SleepDebtCard(days: engine.days, base: need)
            tideCard
        } else if BodyHealth.available {
            BodyNeedsHealthCard(what: "your sleep stages, schedule and sleep debt") { Task { await engine.connect() } }
        }
        NavigationLink { LazyView(SleepSoundsView()) } label: {
            Label("Sleep sounds", systemImage: "moon.zzz.fill").font(DS.Font.headline).frame(maxWidth: .infinity, alignment: .leading).bodyCard()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var effortPage: some View {
        if live {
            BodyDayStrip(days: engine.days, selected: $selectedDay)
            if isToday { BuildWorkoutCard(tide: t?.tide, extras: extras) }
            swellCard
            if isToday {
                ActivityTodayCard(x: extras)
                if extras.zoneMinutes.reduce(0, +) > 0 { ZonesCard(minutes: extras.zoneMinutes) }
                WorkoutPickCard(tide: t?.tide, swell: t?.swell ?? 0)
            }
            CardioLoadCard(days: engine.days)
            BodyMetricsGrid(day: t, days: engine.days, metrics: [.vo2, .rhr], title: "Fitness")
        } else if BodyHealth.available {
            BodyNeedsHealthCard(what: "your effort, heart-rate zones and workouts") { Task { await engine.connect() } }
        }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            NavigationLink { LazyView(StrengthHomeView()) } label: { linkTile("Strength", "dumbbell.fill", BodyStyle.swell) }
            NavigationLink { LazyView(MuscleFreshnessView()) } label: { linkTile("Muscle freshness", "figure.stand", .green) }
            NavigationLink { LazyView(CardioChartsView()) } label: { linkTile("Cardio", "heart.circle.fill", .pink) }
            NavigationLink { LazyView(WorkoutHistoryView()) } label: { linkTile("Workouts", "figure.run", BodyStyle.swell) }
            NavigationLink { LazyView(BodyTrendsView()) } label: { linkTile("90-day trends", "chart.xyaxis.line", .purple) }
            NavigationLink { LazyView(BodyMapView()) } label: { linkTile("Body map", "figure.stand.line.dotted.figure.stand", .orange) }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var healthPage: some View {
        BodyMedsCard()
        if BodyHealth.available { BioAgeCard() }
        NutritionScoreCard()
        HStack(spacing: 10) {
            NavigationLink { LazyView(HealthRecordsView()) } label: { linkTile("Health records", "cross.vial.fill", .red) }
            NavigationLink { LazyView(BiologyView()) } label: { linkTile("Biology", "drop.fill", .red) }
        }
        .buttonStyle(.plain)
        if live {
            vitalsCard
            CycleCard(x: extras)
        }
        HealthTilesSection(extras: extras)
        DrinksCard()
        MoodBodyCard()
    }

    @ViewBuilder private var habitsPage: some View {
        if live {
            journalCard
            settingsCard
            explainer
        } else if BodyHealth.available {
            BodyNeedsHealthCard(what: "which habits raise or lower your recovery") { Task { await engine.connect() } }
        }
        EnergyCheckCard()
    }

    private func linkTile(_ title: String, _ icon: String, _ color: Color) -> some View {
        HStack {
            // Fixed icon width and one line of text, so titles line up and every tile in the grid is the same height.
            Image(systemName: icon).foregroundStyle(color).frame(width: 24)
            Text(title).font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.ink)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
        }
        .padding(14)
        .background { PremiumSurface(radius: 16) }
    }

    /// The day you're looking at: today unless you picked an earlier day in the strip.
    private var t: BodyDay? {
        guard let d = selectedDay else { return engine.today }
        return engine.days.first { Calendar.current.isDate($0.day, inSameDayAs: d) } ?? engine.today
    }
    private var recent: [BodyDay] { Array(engine.days.suffix(30)) }

    private func card<C: View>(_ title: String, _ icon: String, _ color: Color, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(DS.Font.headline).foregroundStyle(color)
            content()
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { PremiumSurface() }
    }

    /// Connected, but Health is giving Keel nothing: usually permissions were left off.
    private var noDataCard: some View {
        card("No Health data yet", "exclamationmark.heart", .orange) {
            Text("Keel can't see any sleep, heart or workout data for the last few days. In the Health app, tap your picture → Apps → Keel and turn on every category. Wearing an Apple Watch (also to bed) gives Keel what it needs.")
                .font(DS.Font.caption)
            Button("Open the Health app") { if let u = URL(string: "x-apple-health://") { UIApplication.shared.open(u) } }
                .font(DS.Font.caption)
        }
    }

    private var connectCard: some View {
        card("Body", "water.waves", BodyStyle.tide) {
            Text("Keel reads Apple Health to show three scores each day, all worked out privately on this iPhone:")
            VStack(alignment: .leading, spacing: 6) {
                Label("Tide: how recovered you are", systemImage: "water.waves").foregroundStyle(BodyStyle.tide)
                Label("Swell: how hard your body worked", systemImage: "wind").foregroundStyle(BodyStyle.swell)
                Label("Anchor: how well you slept", systemImage: "moon.zzz.fill").foregroundStyle(BodyStyle.anchor)
            }
            .font(DS.Font.caption.weight(.semibold))
            Text("Wearing an Apple Watch (also to bed) makes them much more accurate.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            Button { Task { await engine.connect() } } label: { Label("Connect Apple Health", systemImage: "heart.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).tint(BodyStyle.tide)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                ScoreRing(title: "Tide", value: t?.tide, max: 100, color: BodyStyle.tide, suffix: "%").frame(maxWidth: .infinity)
                ScoreRing(title: "Swell", value: t?.swell, max: 100, color: BodyStyle.swell).frame(maxWidth: .infinity)
                ScoreRing(title: "Anchor", value: t?.anchor, max: 100, color: BodyStyle.anchor).frame(maxWidth: .infinity)
            }
            if engine.loading { ProgressView("Reading Apple Health…").font(DS.Font.caption) }
            if t?.calibrating ?? true {
                Label("Learning your normal: Tide gets accurate after about 5 nights with your Apple Watch.", systemImage: "hourglass")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
        }
        .padding(.vertical, 6)
    }

    private var adviceCard: some View {
        let target = BodyMath.swellTarget(t?.tide)
        let swell = t?.swell ?? 0
        return card("Today", "sun.horizon.fill", DS.Palette.accent) {
            Text(BodyEngine.advice(t?.tide))
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(BodyStyle.swell.opacity(0.12))
                        Capsule().fill(BodyStyle.swell.opacity(0.25))
                            .frame(width: g.size.width * CGFloat(target.upperBound - target.lowerBound) / 100)
                            .offset(x: g.size.width * CGFloat(target.lowerBound) / 100)
                        Capsule().fill(BodyStyle.swell.gradient).frame(width: max(6, g.size.width * CGFloat(swell) / 100))
                    }
                }
                .frame(height: 10)
                Text(swell < target.lowerBound ? "Swell \(swell): room to do more today (aim for \(target.lowerBound)–\(target.upperBound))."
                     : swell > target.upperBound ? "Swell \(swell): you've done plenty. Ease off and recover."
                     : "Swell \(swell): right in your target range.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
        }
    }

    private var tideCard: some View {
        card("Tide · recovery", "water.waves", BodyStyle.tide) {
            if let notes = t?.tideNotes, !notes.isEmpty {
                ForEach(notes, id: \.self) { Text("• \($0)").font(DS.Font.caption) }
            } else {
                Text("No overnight heart data yet. Wear your Apple Watch to bed.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            trend(\.tide, color: BodyStyle.tide, max: 100)
        }
    }

    private var anchorCard: some View {
        let tn = BodyMath.tonight(engine.days, base: need)
        return card("Anchor · sleep", "moon.zzz.fill", BodyStyle.anchor) {
            if let d = t, d.hasSleep {
                HStack(alignment: .firstTextBaseline) {
                    Text(hm(d.asleep)).font(.title2.weight(.bold)).monospacedDigit()
                    Text("of \(hm((d.need ?? need) * 60)) you needed").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                if d.deep + d.rem + d.core > 0 {
                    GeometryReader { g in
                        let total = max(1, d.deep + d.rem + d.core + d.awake)
                        HStack(spacing: 2) {
                            stage(g.size.width * d.deep / total, Color(red: 0.25, green: 0.25, blue: 0.70))
                            stage(g.size.width * d.core / total, BodyStyle.anchor.opacity(0.7))
                            stage(g.size.width * d.rem / total, Color(red: 0.55, green: 0.70, blue: 1))
                            stage(g.size.width * d.awake / total, Color.orange.opacity(0.6))
                        }
                    }
                    .frame(height: 12)
                    Text("Deep \(hm(d.deep)) · Core \(hm(d.core)) · REM \(hm(d.rem)) · Awake \(hm(d.awake))")
                        .font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                }
                if let b = d.bedtime, let w = d.wake {
                    Text("Asleep \(b.formatted(date: .omitted, time: .shortened)) – \(w.formatted(date: .omitted, time: .shortened))")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
            } else {
                Text("No sleep recorded for last night.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            Divider()
            Label {
                Text("Tonight: about \(hm(tn.need * 60)). Lights out by **\(tn.bedtime.formatted(date: .omitted, time: .shortened))** to wake at \(tn.wake.formatted(date: .omitted, time: .shortened)).")
                    .font(DS.Font.caption)
            } icon: { Image(systemName: "bed.double.fill").foregroundStyle(BodyStyle.anchor) }
            trend(\.anchor, color: BodyStyle.anchor, max: 100)
        }
    }

    private func stage(_ w: CGFloat, _ c: Color) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(c).frame(width: max(0, w - 2))
    }

    private var swellCard: some View {
        card("Swell · effort", "wind", BodyStyle.swell) {
            if let w = t?.workouts, !w.isEmpty {
                ForEach(w) { x in
                    HStack {
                        Text(x.name).font(DS.Font.body.weight(.medium))
                        Text("\(x.minutes) min" + (x.kcal.map { " · \($0) kcal" } ?? "")).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        Spacer()
                        Text("Swell \(x.swell)").font(DS.Font.caption.weight(.semibold)).foregroundStyle(BodyStyle.swell)
                    }
                }
            } else {
                Text("No workouts today. Everyday movement still counts toward Swell.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            trendInt(\.swell, color: BodyStyle.swell)
        }
    }

    private var stressCard: some View {
        card("Stress through the day", "waveform.path.ecg", .orange) {
            if let s = t?.stress, s.contains(where: { $0 != nil }) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(s.enumerated()), id: \.offset) { i, v in
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 3).fill(BodyStyle.stressColor(v)).frame(height: CGFloat(14 + (v ?? 0) * 14))
                            if i % 3 == 0 { Text(hourLabel(8 + i)).font(.system(size: 8)).foregroundStyle(DS.Palette.inkSoft) } else { Text(" ").font(.system(size: 8)) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 50, alignment: .bottom)
                let high = s.compactMap { $0 }.filter { $0 == 2 }.count
                Text(high == 0 ? "A calm day so far." : "\(high) hour\(high == 1 ? "" : "s") of high stress. A 2-minute breather can help (Compass → Breathe).")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            } else {
                Text("Shows when you wear your Apple Watch during the day.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
        }
    }

    private var vitalsCard: some View {
        card("Vital signs", "heart.text.square.fill", .pink) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                vital("Heart rate variability", t?.hrv.map { "\(Int($0)) ms" }, normal(\.hrv), higherIsBetter: true, value: t?.hrv)
                vital("Resting heart rate", t?.rhr.map { "\(Int($0)) bpm" }, normal(\.rhr), higherIsBetter: false, value: t?.rhr)
                vital("Breathing rate", t?.resp.map { String(format: "%.1f /min", $0) }, normal(\.resp), higherIsBetter: nil, value: t?.resp)
                vital("Blood oxygen", t?.spo2.map { String(format: "%.0f%%", $0) }, normal(\.spo2), higherIsBetter: true, value: t?.spo2)
                vital("Wrist temperature", t?.temp.map { String(format: "%+.1f°C", $0) }, nil, higherIsBetter: nil, value: t?.temp)
                vital("Cardio fitness (VO₂ max)", t?.vo2.map { String(format: "%.1f", $0) }, nil, higherIsBetter: true, value: t?.vo2)
            }
        }
    }

    /// Your usual range: average ± one standard deviation over the last 30 days.
    private func normal(_ kp: KeyPath<BodyDay, Double?>) -> ClosedRange<Double>? {
        let v = engine.days.dropLast().suffix(30).compactMap { $0[keyPath: kp] }
        guard v.count >= 5 else { return nil }
        let m = v.reduce(0, +) / Double(v.count)
        let sd = sqrt(v.reduce(0) { $0 + pow($1 - m, 2) } / Double(v.count - 1))
        return (m - sd)...(m + sd)
    }

    private func vital(_ name: String, _ shown: String?, _ range: ClosedRange<Double>?, higherIsBetter: Bool?, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption2).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
            Text(shown ?? "–").font(DS.Font.headline).monospacedDigit()
            if let r = range, let v = value {
                let out = v < r.lowerBound || v > r.upperBound
                Text(out ? (v > r.upperBound ? "Above your normal" : "Below your normal") : "Normal for you")
                    .font(.caption2).foregroundStyle(out ? .orange : .green)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var journalCard: some View {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let logged = Set(engine.journal[BodyMath.dayKey(yesterday)] ?? [])
        let impact = BodyMath.habitImpact(journal: engine.journal, days: engine.days)
        _ = journalTick
        return card("Habit impact", "checklist", .green) {
            Text("What did you do yesterday? Keel learns which habits raise or lower your Tide the next morning.")
                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            FlowLayout(spacing: 8) {
                ForEach(BodyEngine.journalTags, id: \.self) { tag in
                    let on = logged.contains(tag)
                    Button { engine.toggle(tag, on: yesterday); journalTick += 1; Haptics.tap() } label: {
                        Text(tag).font(DS.Font.caption).padding(.horizontal, 10).padding(.vertical, 6)
                            .background(on ? Color.green.opacity(0.22) : DS.Palette.canvas, in: Capsule())
                            .overlay(Capsule().strokeBorder(on ? Color.green : Color.gray.opacity(0.3)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if impact.isEmpty {
                Text("Log a few days (at least 3 with and 3 without a habit) to see its effect.").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
            } else {
                ForEach(impact.prefix(6), id: \.tag) { i in
                    HStack {
                        Text(i.tag).font(DS.Font.caption)
                        Spacer()
                        Text("\(i.delta > 0 ? "+" : "")\(i.delta)% Tide").font(DS.Font.caption.weight(.semibold))
                            .foregroundStyle(i.delta > 0 ? .green : i.delta < 0 ? .red : DS.Palette.inkSoft)
                    }
                }
            }
        }
    }

    private var settingsCard: some View {
        card("Settings", "slider.horizontal.3", DS.Palette.inkSoft) {
            Stepper("Sleep you need: \(need.formatted(.number.precision(.fractionLength(0...2)))) h", value: $need, in: 6...10, step: 0.25)
                .onChange(of: need) { Task { await engine.refresh(force: true) } }
            Stepper(maxHR == 0 ? "Max heart rate: automatic" : "Max heart rate: \(maxHR)", value: $maxHR, in: 0...220, step: 1)
                .onChange(of: maxHR) { if maxHR > 0 && maxHR < 120 { maxHR = 120 } }
            Toggle("Morning readiness alert", isOn: $morning)
            Toggle("Wind-down reminder before bed", isOn: $windDown)
                .onChange(of: windDown) { engine.scheduleWindDown() }
            Toggle("Wake me with an alarm at my planned time", isOn: $wakeAlarm)
                .onChange(of: wakeAlarm) {
                    Task { if wakeAlarm { await SmartWake.schedule(at: BodyMath.tonight(engine.days, base: need).wake) } else { SmartWake.cancel() } }
                }
            Stepper("Water goal: \(waterGoal) ml", value: $waterGoal, in: 1_000...4_000, step: 250)
            Toggle("Remind me to drink water", isOn: $waterNudge)
                .onChange(of: waterNudge) { Drinks.scheduleWaterNudge() }
        }
        .font(DS.Font.caption)
    }

    private var explainer: some View {
        DisclosureGroup("How the scores work") {
            VStack(alignment: .leading, spacing: 8) {
                Text("**Tide (0–100%)** compares last night's heart rate variability and resting heart rate with your own normal over the last 30 days, then adds how well you slept. Faster breathing or a raised wrist temperature overnight lowers it, since they can be early signs of illness or stress.")
                Text("**Swell (0–100)** counts time spent in each heart-rate zone today, weighting harder zones more. It rises quickly at first and levels off, so going from 80 to 90 takes much more than going from 10 to 20.")
                Text("**Anchor (0–100)** is your sleep: how much you got compared with what you needed (55 points), how much of your time in bed you were asleep (15), deep and REM sleep (15), and how close your bedtime was to your usual one (15).")
                Text("**Sleep need** is your base (\(need.formatted(.number.precision(.fractionLength(0...2)))) h) plus a little after a hard day, plus a third of any sleep debt from the last few nights.")
                Text("Everything is worked out on this iPhone from Apple Health. Keel doesn't send any of it anywhere. These scores are for everyday wellbeing, not medical advice.")
            }
            .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).padding(.top, 6)
        }
        .padding(DS.Space.m)
        .background { PremiumSurface() }
    }

    // MARK: Charts

    private func trend(_ kp: KeyPath<BodyDay, Int?>, color: Color, max: Int) -> some View {
        Chart(recent) { d in
            if let v = d[keyPath: kp] {
                LineMark(x: .value("Day", d.day, unit: .day), y: .value("Score", v)).foregroundStyle(color).interpolationMethod(.catmullRom)
                PointMark(x: .value("Day", d.day, unit: .day), y: .value("Score", v)).foregroundStyle(color).symbolSize(14)
            }
        }
        .chartYScale(domain: 0...max)
        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
        .frame(height: 110)
        .accessibilityLabel("Last 30 days")
    }

    private func trendInt(_ kp: KeyPath<BodyDay, Int>, color: Color) -> some View {
        Chart(Array(engine.days.suffix(14))) { d in
            BarMark(x: .value("Day", d.day, unit: .day), y: .value("Swell", d[keyPath: kp])).foregroundStyle(color.gradient).cornerRadius(3)
        }
        .chartYScale(domain: 0...100)
        .frame(height: 90)
        .accessibilityLabel("Last 14 days")
    }

    private func hm(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return "\(m / 60)h \(String(format: "%02d", m % 60))m"
    }
    private func hourLabel(_ h: Int) -> String { h == 12 ? "12p" : h > 12 ? "\(h - 12)p" : "\(h)a" }
}
