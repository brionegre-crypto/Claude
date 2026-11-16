import SwiftUI
import SwiftData
import EventKit

// MARK: - Nutrition score: the quality of the whole day's food, not just calories

struct NutritionScoreResult: Hashable { let score: Int; let notes: [String] }

enum NutritionScore {
    /// 0–100 for a day's food: protein, fibre, added sugar, salt, how much fits your diet, and brain foods.
    static func score(_ entries: [FoodEntry], proteinGoal: Double = 90) -> NutritionScoreResult? {
        guard !entries.isEmpty else { return nil }
        let protein = entries.reduce(0) { $0 + ($1.facts.protein ?? 0) }
        let fiber = entries.reduce(0) { $0 + ($1.facts.fiber ?? 0) }
        let sugar = entries.reduce(0) { $0 + ($1.facts.addedSugar ?? ($1.facts.sugar ?? 0) * 0.5) }
        let sodium = entries.reduce(0) { $0 + ($1.facts.sodiumMg ?? 0) }
        let green = Double(entries.filter { $0.verdict == .green }.count) / Double(entries.count)
        let red = Double(entries.filter { $0.verdict == .red }.count) / Double(entries.count)
        let brain = entries.contains { !$0.tags.isEmpty }
        var s = 45.0
        var notes: [String] = []
        s += min(15, protein / proteinGoal * 15)
        if protein < proteinGoal * 0.7 { notes.append("Protein \(Int(protein)) g: add some at your next meal (aim for about \(Int(proteinGoal)) g).") }
        s += min(15, fiber / 25 * 15)
        if fiber < 15 { notes.append("Fibre \(Int(fiber)) g: fruit, beans, oats or vegetables would lift it (aim for 25 g).") }
        if sugar <= 25 { s += 10 } else { s -= min(15, (sugar - 25) / 2); notes.append("Sugar about \(Int(sugar)) g: over the 25 g a day guide.") }
        if sodium > 0 { if sodium <= 2300 { s += 5 } else { s -= 5; notes.append("Salt is high today (\(Int(sodium)) mg sodium).") } }
        s += green * 15 - red * 20
        if brain { s += 5 } else { notes.append("No brain foods logged yet: oily fish, nuts, seeds or leafy greens.") }
        if notes.isEmpty { notes.append("A well-balanced day. Nice.") }
        return NutritionScoreResult(score: Int(min(100, max(0, s)).rounded()), notes: notes)
    }
}

struct NutritionScoreCard: View {
    @Query(NutritionScoreCard.today) private var entries: [FoodEntry]
    static var today: FetchDescriptor<FoodEntry> {
        let start = Calendar.current.startOfDay(for: Date())
        return FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.date >= start })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Nutrition score", systemImage: "leaf.fill").font(DS.Font.headline).foregroundStyle(.green)
                Spacer()
                if let r = NutritionScore.score(entries) {
                    Text("\(r.score)").font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(r.score >= 70 ? .green : r.score >= 45 ? .orange : .red)
                }
            }
            if let r = NutritionScore.score(entries) {
                ForEach(r.notes.prefix(3), id: \.self) { Text("• \($0)").font(DS.Font.caption) }
            } else {
                Text("Log a meal (from a photo, a description or a barcode) and Keel scores the quality of your whole day's food.")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            HStack {
                NavigationLink { LazyView(LogFoodView()) } label: { Label("Log a meal", systemImage: "fork.knife") }
                NavigationLink { LazyView(NutritionView()) } label: { Label("Food today", systemImage: "fork.knife") }
            }
            .font(.caption).buttonStyle(.bordered)
        }
        .bodyCard()
    }
}

// MARK: - Timeline: everything about your body today, in order

struct BodyTimelineItem: Identifiable, Hashable {
    let id: String
    let at: Date
    let icon: String
    let color: Color
    let title: String
    let detail: String
}

struct BodyTimelineCard: View {
    let day: BodyDay?
    var date: Date = Date()
    @Query(BodyTimelineCard.recentDoses) private var doses: [MedDose]      // the last 2 days only, not years of history
    @Query private var meds: [Medication]
    static var recentDoses: FetchDescriptor<MedDose> {
        let since = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-86_400)
        return FetchDescriptor<MedDose>(predicate: #Predicate { $0.takenAt >= since })
    }
    @Query(NutritionScoreCard.today) private var food: [FoodEntry]
    @State private var expanded = false

    var body: some View {
        let items = build()
        VStack(alignment: .leading, spacing: 10) {
            Label("Timeline", systemImage: "list.bullet.below.rectangle").font(DS.Font.headline)
            if items.isEmpty {
                Text("Sleep, workouts, meals, medication, drinks and symptoms show up here through the day.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            ForEach(expanded ? items : Array(items.prefix(6))) { i in
                HStack(alignment: .top, spacing: 10) {
                    Text(i.at.formatted(date: .omitted, time: .shortened)).font(.caption.monospacedDigit()).foregroundStyle(DS.Palette.inkSoft)
                        .frame(width: 64, alignment: .trailing)
                    Image(systemName: i.icon).foregroundStyle(i.color).frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(i.title).font(.callout)
                        if !i.detail.isEmpty { Text(i.detail).font(.caption).foregroundStyle(DS.Palette.inkSoft) }
                    }
                }
            }
            if items.count > 6 {
                Button(expanded ? "Show less" : "Show all \(items.count)") { withAnimation(.snappy) { expanded.toggle() } }.font(.caption)
            }
        }
        .bodyCard()
    }

    private func build() -> [BodyTimelineItem] {
        let cal = Calendar.current
        var out: [BodyTimelineItem] = []
        if let d = day {
            if let w = d.wake, d.hasSleep {
                out.append(.init(id: "wake", at: w, icon: "sunrise.fill", color: BodyStyle.anchor, title: "Woke up",
                                 detail: "Slept \(Int(d.asleep) / 60)h \(Int(d.asleep) % 60)m" + (d.anchor.map { " · Anchor \($0)" } ?? "")))
            }
            for w in d.workouts {
                out.append(.init(id: "w\(w.start.timeIntervalSince1970)", at: w.start, icon: "figure.run", color: BodyStyle.swell,
                                 title: w.name, detail: "\(w.minutes) min · Swell \(w.swell)" + (w.kcal.map { " · \($0) kcal" } ?? "")))
            }
        }
        for s in StrengthStore.sessions where cal.isDate(s.start, inSameDayAs: date) {
            out.append(.init(id: "s\(s.id)", at: s.start, icon: "dumbbell.fill", color: BodyStyle.swell, title: s.name,
                             detail: "\(s.setCount) sets · strain \(StrengthStore.strain(s))"))
        }
        let names = Dictionary(meds.map { ($0.id, "\($0.name) \($0.dose)") }, uniquingKeysWith: { a, _ in a })
        for dose in doses where cal.isDate(dose.takenAt, inSameDayAs: date) {
            out.append(.init(id: "m\(dose.id)", at: dose.takenAt, icon: "pills.fill", color: .mint, title: names[dose.medicationId] ?? "Medication", detail: "Taken"))
        }
        for p in PRN.doses where cal.isDate(p.at, inSameDayAs: date) {
            out.append(.init(id: "p\(p.id)", at: p.at, icon: "cross.case.fill", color: .mint, title: PRN.meds.first { $0.id == p.medId }?.name ?? "As-needed medicine", detail: "Taken"))
        }
        if cal.isDateInToday(date) {
            for f in food {
                out.append(.init(id: "f\(f.id)", at: f.date, icon: "fork.knife", color: .green, title: f.name,
                                 detail: [f.meal.capitalized, f.facts.calories.map { "\(Int($0)) kcal" }].compactMap { $0 }.joined(separator: " · ")))
            }
        }
        for d in Drinks.all where cal.isDate(d.at, inSameDayAs: date) {
            out.append(.init(id: "d\(d.id)", at: d.at, icon: d.caffeine > 0 ? "cup.and.saucer.fill" : "drop.fill", color: d.caffeine > 0 ? .brown : .blue,
                             title: d.kind.capitalized, detail: d.caffeine > 0 ? "\(d.caffeine) mg caffeine" : "\(d.water) ml"))
        }
        for s in Symptoms.all where cal.isDate(s.at, inSameDayAs: date) {
            out.append(.init(id: "y\(s.id)", at: s.at, icon: "thermometer.medium", color: .pink, title: s.name, detail: "Severity \(s.severity)/5"))
        }
        return out.sorted { $0.at < $1.at }
    }
}

// MARK: - Ask about your body (AI coach grounded in your own data)

@MainActor
enum BodyContext {
    /// A compact summary of the last two weeks for the coach.
    static func text() -> String {
        let days = BodyEngine.shared.days.suffix(14)
        var lines: [String] = ["Today is \(Date().formatted(date: .complete, time: .shortened))."]
        for d in days {
            var parts: [String] = [d.day.formatted(.dateTime.weekday(.abbreviated).month().day())]
            if let t = d.tide { parts.append("recovery \(t)%") }
            parts.append("effort \(d.swell)")
            if let a = d.anchor { parts.append("sleep score \(a)") }
            if d.hasSleep { parts.append(String(format: "slept %.1fh", d.asleep / 60)) }
            if let h = d.hrv { parts.append("HRV \(Int(h))ms") }
            if let r = d.rhr { parts.append("RHR \(Int(r))") }
            if !d.workouts.isEmpty { parts.append("workouts: " + d.workouts.map { "\($0.name) \($0.minutes)min" }.joined(separator: ", ")) }
            lines.append(parts.joined(separator: ", "))
        }
        let week = StrengthStore.sessions.filter { $0.start > Date().addingTimeInterval(-7 * 86_400) }
        if !week.isEmpty { lines.append("Strength this week: " + week.map { "\($0.name) (\($0.setCount) sets)" }.joined(separator: ", ")) }
        let fatigue = StrengthStore.fatigue().filter { $0.value > 0.3 }.map { $0.key.name }
        if !fatigue.isEmpty { lines.append("Muscles still tired: " + fatigue.joined(separator: ", ")) }
        if let r = CardioLoad.ratio(BodyEngine.shared.days, strength: StrengthStore.sessions) { lines.append(String(format: "Training load ratio (7-day vs 28-day): %.2f", r)) }
        let bp = BloodPressure.all.suffix(1).map { "Latest blood pressure \($0.systolic)/\($0.diastolic)" }
        lines += bp
        let labs = Biomarkers.latest().compactMap { id, r in Biomarkers.def(id).map { "\($0.name) \(r.value.formatted()) \($0.unit)" } }
        if !labs.isEmpty { lines.append("Latest labs: " + labs.joined(separator: "; ")) }
        lines.append("Caffeine today \(Drinks.caffeineToday) mg, water \(Drinks.waterToday) ml.")
        return lines.joined(separator: "\n")
    }
}

struct AskBodyView: View {
    @State private var question = ""
    @State private var answer = ""
    @State private var thinking = false
    private let suggestions = ["Should I train hard today?", "Why is my recovery low?", "How can I sleep better this week?",
                               "Which muscles should I train next?", "Is my training load too high?", "What's one thing to change this week?"]

    var body: some View {
        List {
            Section {
                KitIntro(icon: "sparkles", color: .indigo, text: "Ask about your body. Keel answers from your own last two weeks: recovery, sleep, heart data, workouts, strength, training load, blood pressure and lab results. Apple Intelligence answers on this iPhone; with your Claude key it can use Claude instead.")
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section {
                TextField("Ask anything about your health data", text: $question, axis: .vertical).onSubmit { ask() }
                Button { ask() } label: { Label(thinking ? "Thinking…" : "Ask", systemImage: "paperplane.fill") }
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || thinking)
            }
            if !answer.isEmpty { Section("Answer") { Text(answer).textSelection(.enabled) } }
            Section("Try") {
                ForEach(suggestions, id: \.self) { s in Button(s) { question = s; ask() } }
            }
            Section { Text("Coaching for everyday wellbeing, not medical advice.").font(.caption).foregroundStyle(DS.Palette.inkSoft) }
        }
        .navigationTitle("Ask about my body")
    }

    private func ask() {
        let q = question.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        thinking = true; answer = ""
        Task {
            let prompt = """
            You are a friendly, practical health and fitness coach. Answer the question using the person's data below. \
            Be specific to their numbers, give at most 4 short points, and say when something is worth asking a doctor about. No diagnosis.
            Data:
            \(BodyContext.text())
            Question: \(q)
            """
            answer = await AIRouter.shared.write(prompt) ?? "Keel couldn't reach Apple Intelligence or Claude right now. Check Settings → AI."
            thinking = false
        }
    }
}
