import SwiftUI
import SwiftData
import Charts
import UserNotifications

// Small personal health logs, kept as settings (so they follow you to your other devices) rather than in the
// synced database. Each one has its own screen, all reachable from Body.

enum LocalLog {
    // Decoded lists are kept until their saved bytes change, so screens that read the same log several
    // times while drawing don't decode it again each time.
    nonisolated(unsafe) private static var memo: [String: (data: Data, value: Any)] = [:]
    private static let lock = NSLock()

    static func load<T: Codable>(_ key: String, as: T.Type = T.self) -> [T] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        lock.lock()
        if let m = memo[key], m.data == data, let v = m.value as? [T] { lock.unlock(); return v }
        lock.unlock()
        let value = (try? JSONDecoder().decode([T].self, from: data)) ?? []
        lock.lock(); memo[key] = (data, value); lock.unlock()
        return value
    }
    static func save<T: Codable>(_ items: [T], _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: key)
    }
}

// MARK: - Symptoms

struct SymptomEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var severity: Int          // 1 mild … 5 severe
    var at: Date
    var note: String = ""
}

enum Symptoms {
    static let key = "health.symptoms"
    static let common = ["Headache", "Migraine", "Tired", "Brain fog", "Anxious", "Low mood", "Nausea", "Stomach ache",
                         "Back pain", "Joint pain", "Dizzy", "Cold or flu", "Allergies", "Trouble sleeping", "Restless", "Heart racing"]
    static var all: [SymptomEntry] {
        get { LocalLog.load(key) }
        set { LocalLog.save(Array(newValue.suffix(800)), key) }
    }
    /// "Headache: 5 times in 30 days, usually moderate".
    static func summary(_ entries: [SymptomEntry], days: Int = 30) -> [(name: String, count: Int, avg: Double)] {
        let since = Date().addingTimeInterval(-Double(days) * 86_400)
        let recent = entries.filter { $0.at > since }
        return Dictionary(grouping: recent, by: \.name).map { (name: $0.key, count: $0.value.count, avg: Double($0.value.reduce(0) { $0 + $1.severity }) / Double($0.value.count)) }
            .sorted { $0.count > $1.count }
    }
}

struct SymptomsView: View {
    @State private var entries = Symptoms.all
    @State private var logging: String?
    @State private var severity = 3
    @State private var note = ""
    @State private var custom = ""

    var body: some View {
        List {
            Section("How are you feeling?") {
                FlowLayout(spacing: 8) {
                    ForEach(Symptoms.common, id: \.self) { s in
                        Button { logging = s; severity = 3; note = "" } label: {
                            Text(s).font(.caption).padding(.horizontal, 10).padding(.vertical, 6).background(Color.pink.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Something else…", text: $custom)
                    Button("Log") { logging = custom; severity = 3; note = ""; custom = "" }.disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            let summary = Symptoms.summary(entries)
            if !summary.isEmpty {
                Section("Last 30 days") {
                    ForEach(summary, id: \.name) { s in
                        HStack {
                            Text(s.name)
                            Spacer()
                            Text("\(s.count)× · \(s.avg < 2.5 ? "mild" : s.avg < 3.5 ? "moderate" : "strong")").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                }
            }
            Section("Recent") {
                if entries.isEmpty { Text("Nothing logged yet.").foregroundStyle(DS.Palette.inkSoft) }
                ForEach(entries.sorted { $0.at > $1.at }.prefix(40)) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(e.name) · \(String(repeating: "●", count: e.severity))\(String(repeating: "○", count: 5 - e.severity))")
                        Text(e.at.formatted(date: .abbreviated, time: .shortened) + (e.note.isEmpty ? "" : " · \(e.note)")).font(.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                    .swipeActions { Button("Delete", role: .destructive) { entries.removeAll { $0.id == e.id }; Symptoms.all = entries } }
                }
            }
        }
        .navigationTitle("Symptoms")
        .sheet(item: Binding(get: { logging.map { IdentifiedString(value: $0) } }, set: { logging = $0?.value })) { s in
            NavigationStack {
                Form {
                    Picker("How strong?", selection: $severity) { ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.segmented)
                    TextField("Note (optional)", text: $note)
                }
                .navigationTitle(s.value).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { logging = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Log") {
                            entries.append(SymptomEntry(name: s.value, severity: severity, at: Date(), note: note))
                            Symptoms.all = entries; logging = nil; Haptics.tap()
                        }
                    }
                }
            }
            .presentationDetents([.height(260)])
        }
    }
}

struct IdentifiedString: Identifiable { var id: String { value }; let value: String }

// MARK: - As-needed medicines (with a safe-interval check)

struct PRNMed: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var dose: String
    var minHours: Double        // at least this long between doses
    var maxPerDay: Int
}
struct PRNDose: Codable, Identifiable, Hashable { var id = UUID(); var medId: UUID; var at: Date }

enum PRN {
    static let medsKey = "health.prn.meds", dosesKey = "health.prn.doses"
    static var meds: [PRNMed] { get { LocalLog.load(medsKey) } set { LocalLog.save(newValue, medsKey) } }
    static var doses: [PRNDose] { get { LocalLog.load(dosesKey) } set { LocalLog.save(Array(newValue.suffix(500)), dosesKey) } }

    /// Nil when it's fine to take now; otherwise why not yet.
    static func check(_ m: PRNMed, doses: [PRNDose], now: Date = Date()) -> String? {
        let mine = doses.filter { $0.medId == m.id }.sorted { $0.at > $1.at }
        if let last = mine.first, now.timeIntervalSince(last.at) < m.minHours * 3600 {
            let ok = last.at.addingTimeInterval(m.minHours * 3600)
            return "Last dose at \(last.at.formatted(date: .omitted, time: .shortened)). Wait until \(ok.formatted(date: .omitted, time: .shortened))."
        }
        let today = mine.filter { Calendar.current.isDate($0.at, inSameDayAs: now) }.count
        if today >= m.maxPerDay { return "You've had \(today) today, your daily limit." }
        return nil
    }
}

struct PRNView: View {
    @State private var meds = PRN.meds
    @State private var doses = PRN.doses
    @State private var adding = false
    @State private var warn: (PRNMed, String)?
    @State private var name = ""
    @State private var dose = ""
    @State private var minHours = 4.0
    @State private var maxPerDay = 4

    var body: some View {
        List {
            Section {
                if meds.isEmpty { Text("Add medicines you take only when needed, like pain relief or an inhaler. Keel tells you when it's safe to take the next one.").foregroundStyle(DS.Palette.inkSoft) }
                ForEach(meds) { m in
                    let todays = doses.filter { $0.medId == m.id && Calendar.current.isDateInToday($0.at) }.count
                    let last = doses.filter { $0.medId == m.id }.map(\.at).max()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(m.name) \(m.dose)")
                            Text("\(todays) of \(m.maxPerDay) today" + (last.map { " · last \($0.formatted(.relative(presentation: .named)))" } ?? "")).font(.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        Button("Take") {
                            if let why = PRN.check(m, doses: doses) { warn = (m, why) } else { take(m) }
                        }
                        .buttonStyle(.borderedProminent).tint(DS.Palette.accent)
                    }
                    .swipeActions { Button("Delete", role: .destructive) { meds.removeAll { $0.id == m.id }; PRN.meds = meds } }
                }
            } footer: { Text("Follow the label or your doctor's advice for the right gap and daily limit.") }
        }
        .navigationTitle("As-needed medicines")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add") }
        .alert("Not yet", isPresented: Binding(get: { warn != nil }, set: { if !$0 { warn = nil } })) {
            Button("Take anyway", role: .destructive) { if let m = warn?.0 { take(m) }; warn = nil }
            Button("OK", role: .cancel) { warn = nil }
        } message: { Text(warn?.1 ?? "") }
        .sheet(isPresented: $adding) {
            NavigationStack {
                Form {
                    TextField("Name, e.g. Ibuprofen", text: $name)
                    TextField("Dose, e.g. 400 mg", text: $dose)
                    Stepper("At least \(minHours.formatted()) h between doses", value: $minHours, in: 1...24, step: 0.5)
                    Stepper("Up to \(maxPerDay) a day", value: $maxPerDay, in: 1...12)
                }
                .navigationTitle("As-needed medicine").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { adding = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") { meds.append(PRNMed(name: name, dose: dose, minHours: minHours, maxPerDay: maxPerDay)); PRN.meds = meds; adding = false; name = ""; dose = "" }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func take(_ m: PRNMed) {
        doses.append(PRNDose(medId: m.id, at: Date())); PRN.doses = doses
        Haptics.done()
        // A heads-up when it's OK to take the next one.
        let c = UNMutableNotificationContent()
        c.title = "\(m.name): OK to take again if you need it"
        c.body = "It's been \(m.minHours.formatted()) hours since your last dose."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "prn.\(m.id)", content: c,
                                                                     trigger: UNTimeIntervalNotificationTrigger(timeInterval: m.minHours * 3600, repeats: false)))
    }
}

// MARK: - How did it work? (scheduled medication check-ins)

enum DoseEffect {
    static let key = "health.doseEffect"       // [dose id: rating 1–5]
    static var ratings: [String: Int] {
        get { (UserDefaults.standard.dictionary(forKey: key) as? [String: Int]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    static func rate(_ dose: MedDose, _ r: Int) { var all = ratings; all[dose.id.uuidString] = r; ratings = all }
    /// Average rating for a medication over the last 14 days.
    static func average(_ med: Medication, doses: [MedDose]) -> Double? {
        let since = Date().addingTimeInterval(-14 * 86_400)
        let r = ratings
        let vals = doses.filter { $0.medicationId == med.id && $0.takenAt > since }.compactMap { r[$0.id.uuidString] }
        return vals.count >= 3 ? Double(vals.reduce(0, +)) / Double(vals.count) : nil
    }
}

// MARK: - Medical card

struct MedicalCardData: Codable, Hashable {
    var bloodType = ""
    var allergies = ""
    var conditions = ""
    var notes = ""
    var emergencyName = ""
    var emergencyPhone = ""
    var doctor = ""
    static let key = "health.medicalCard"
    static var current: MedicalCardData {
        get { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(MedicalCardData.self, from: $0) } ?? MedicalCardData() }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }
}

struct MedicalCardView: View {
    @Query(sort: \Medication.name) private var meds: [Medication]
    @State private var card = MedicalCardData.current
    @State private var showing = false
    var body: some View {
        Form {
            Section { Button("Show my card", systemImage: "person.text.rectangle") { showing = true } }
            Section("Health") {
                TextField("Blood type", text: $card.bloodType)
                TextField("Allergies", text: $card.allergies, axis: .vertical)
                TextField("Conditions", text: $card.conditions, axis: .vertical)
                TextField("Other notes", text: $card.notes, axis: .vertical)
            }
            Section("Contacts") {
                TextField("Emergency contact", text: $card.emergencyName)
                TextField("Their phone", text: $card.emergencyPhone).keyboardType(.phonePad)
                TextField("Doctor", text: $card.doctor)
            }
            Section { } footer: { Text("For emergencies, also fill in Medical ID in Apple's Health app: it can be shown on the Lock Screen without unlocking.") }
        }
        .navigationTitle("Medical card")
        .onChange(of: card) { MedicalCardData.current = card }
        .fullScreenCover(isPresented: $showing) {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Label("Medical card", systemImage: "staroflife.fill").font(.title2.weight(.bold)).foregroundStyle(.red); Spacer(); Button("Done") { showing = false } }
                Group {
                    line("Blood type", card.bloodType); line("Allergies", card.allergies); line("Conditions", card.conditions)
                    line("Medications", meds.filter(\.isActive).map { "\($0.name) \($0.dose)" }.joined(separator: ", "))
                    line("Emergency contact", [card.emergencyName, card.emergencyPhone].filter { !$0.isEmpty }.joined(separator: " · "))
                    line("Doctor", card.doctor); line("Notes", card.notes)
                }
                Spacer()
            }
            .padding(24)
        }
    }
    @ViewBuilder private func line(_ name: String, _ value: String) -> some View {
        if !value.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(name.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(value).font(.title3)
            }
        }
    }
}

// MARK: - Blood pressure

struct BPReading: Codable, Identifiable, Hashable { var id = UUID(); var systolic: Int; var diastolic: Int; var pulse: Int?; var at: Date }

enum BloodPressure {
    static let key = "health.bp"
    static var all: [BPReading] { get { LocalLog.load(key) } set { LocalLog.save(Array(newValue.suffix(500)), key) } }
    /// The usual categories (American Heart Association).
    static func category(_ s: Int, _ d: Int) -> (String, Color) {
        if s >= 180 || d >= 120 { return ("Very high: get medical advice now", .red) }
        if s >= 140 || d >= 90 { return ("High (stage 2)", .red) }
        if s >= 130 || d >= 80 { return ("High (stage 1)", .orange) }
        if s >= 120 { return ("Elevated", .yellow) }
        return ("Normal", .green)
    }
}

struct BloodPressureView: View {
    @State private var readings = BloodPressure.all
    @State private var sys = 120
    @State private var dia = 80
    @State private var pulse = 70
    @State private var adding = false
    var body: some View {
        List {
            if !readings.isEmpty {
                Section("Last 30 days") {
                    Chart(readings.filter { $0.at > Date().addingTimeInterval(-30 * 86_400) }) { r in
                        PointMark(x: .value("Day", r.at), y: .value("Systolic", r.systolic)).foregroundStyle(.red)
                        PointMark(x: .value("Day", r.at), y: .value("Diastolic", r.diastolic)).foregroundStyle(.blue)
                    }
                    .frame(height: 160)
                }
            }
            Section("Readings") {
                if readings.isEmpty { Text("Add a reading from your cuff. Keel shows the trend and what the numbers mean.").foregroundStyle(DS.Palette.inkSoft) }
                ForEach(readings.sorted { $0.at > $1.at }.prefix(50)) { r in
                    let c = BloodPressure.category(r.systolic, r.diastolic)
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(r.systolic)/\(r.diastolic)" + (r.pulse.map { " · pulse \($0)" } ?? "")).font(.headline).monospacedDigit()
                            Text(r.at.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        Text(c.0).font(.caption.weight(.semibold)).foregroundStyle(c.1)
                    }
                    .swipeActions { Button("Delete", role: .destructive) { readings.removeAll { $0.id == r.id }; BloodPressure.all = readings } }
                }
            }
        }
        .navigationTitle("Blood pressure")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add reading") }
        .sheet(isPresented: $adding) {
            NavigationStack {
                Form {
                    Stepper("Top (systolic): \(sys)", value: $sys, in: 70...250)
                    Stepper("Bottom (diastolic): \(dia)", value: $dia, in: 40...150)
                    Stepper("Pulse: \(pulse)", value: $pulse, in: 30...200)
                    Text(BloodPressure.category(sys, dia).0).foregroundStyle(BloodPressure.category(sys, dia).1)
                }
                .navigationTitle("New reading").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { adding = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { readings.append(BPReading(systolic: sys, diastolic: dia, pulse: pulse, at: Date())); BloodPressure.all = readings; adding = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

// MARK: - Fasting timer

enum Fasting {
    static let startKey = "health.fast.start", goalKey = "health.fast.goal", historyKey = "health.fast.history"
    static var start: Date? {
        get { let t = UserDefaults.standard.double(forKey: startKey); return t > 0 ? Date(timeIntervalSince1970: t) : nil }
        set { UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: startKey) }
    }
    static var goal: Int { let g = UserDefaults.standard.integer(forKey: goalKey); return g > 0 ? g : 14 }
    struct Past: Codable, Hashable { var start: Date; var end: Date }
    static var history: [Past] { get { LocalLog.load(historyKey) } set { LocalLog.save(Array(newValue.suffix(60)), historyKey) } }
}

struct FastingView: View {
    @State private var start = Fasting.start
    @AppStorage(Fasting.goalKey) private var goal = 14
    @State private var history = Fasting.history

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let hours = start.map { ctx.date.timeIntervalSince($0) / 3600 } ?? 0
            List {
                Section {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle().stroke(Color.green.opacity(0.15), lineWidth: 16)
                            Circle().trim(from: 0, to: min(1, hours / Double(goal))).stroke(Color.green.gradient, style: StrokeStyle(lineWidth: 16, lineCap: .round)).rotationEffect(.degrees(-90))
                            VStack {
                                Text(start == nil ? "Not fasting" : String(format: "%d:%02d", Int(hours), Int((hours - Double(Int(hours))) * 60))).font(.title.weight(.bold)).monospacedDigit()
                                Text(start == nil ? "Goal \(goal) h" : hours >= Double(goal) ? "Goal reached 🎉" : "of \(goal) h").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                            }
                        }
                        .frame(width: 180, height: 180)
                        Button(start == nil ? "Start fasting" : "End fast") { toggle() }.buttonStyle(.borderedProminent).tint(.green)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    Picker("Goal", selection: $goal) { ForEach([12, 14, 16, 18, 20], id: \.self) { Text("\($0) h").tag($0) } }.pickerStyle(.segmented)
                } footer: { Text("Keel lets you know when you reach your goal. If you have diabetes, take medication with food or are pregnant, check with your doctor before fasting.") }
                if !history.isEmpty {
                    Section("Recent fasts") {
                        ForEach(history.reversed(), id: \.self) { p in
                            HStack { Text(p.start.formatted(date: .abbreviated, time: .shortened)); Spacer(); Text(String(format: "%.1f h", p.end.timeIntervalSince(p.start) / 3600)).monospacedDigit() }
                        }
                    }
                }
            }
        }
        .navigationTitle("Fasting")
    }

    private func toggle() {
        let center = UNUserNotificationCenter.current()
        if let s = start {
            history.append(.init(start: s, end: Date())); Fasting.history = history
            start = nil; Fasting.start = nil
            center.removePendingNotificationRequests(withIdentifiers: ["fast.goal"])
            Haptics.done()
        } else {
            let now = Date(); start = now; Fasting.start = now
            let c = UNMutableNotificationContent()
            c.title = "Fasting goal reached"; c.body = "\(goal) hours. Nice work: eat when you're ready."
            center.add(UNNotificationRequest(identifier: "fast.goal", content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: Double(goal) * 3600, repeats: false)))
            Haptics.start()
        }
    }
}

// MARK: - Doctor visit summary

@MainActor
enum DoctorSummary {
    /// The last 30 days in one page to show or send your doctor.
    static func text(ctx: ModelContext) -> String {
        let since = Date().addingTimeInterval(-30 * 86_400)
        var out = "Health summary · \(Date().formatted(date: .long, time: .omitted)) · last 30 days\n\n"
        let meds = ((try? ctx.fetch(FetchDescriptor<Medication>())) ?? []).filter(\.isActive)
        let doses = ((try? ctx.fetch(FetchDescriptor<MedDose>())) ?? []).filter { $0.takenAt > since }
        if !meds.isEmpty {
            out += "MEDICATIONS\n"
            for m in meds {
                let expected = max(1, m.times.count * 30), taken = doses.filter { $0.medicationId == m.id }.count
                out += "• \(m.name) \(m.dose), \(m.times.count)× a day: taken \(taken) of \(expected) (\(Int(Double(taken) / Double(expected) * 100))%)"
                if let a = DoseEffect.average(m, doses: doses) { out += String(format: ", rated %.1f/5 for how well it worked", a) }
                out += "\n"
            }
            out += "\n"
        }
        let prnDoses = PRN.doses.filter { $0.at > since }
        if !prnDoses.isEmpty {
            out += "AS-NEEDED MEDICINES\n"
            for m in PRN.meds { let n = prnDoses.filter { $0.medId == m.id }.count; if n > 0 { out += "• \(m.name) \(m.dose): \(n) times\n" } }
            out += "\n"
        }
        let sym = Symptoms.summary(Symptoms.all)
        if !sym.isEmpty {
            out += "SYMPTOMS\n" + sym.map { String(format: "• %@: %d times, average strength %.1f/5", $0.name, $0.count, $0.avg) }.joined(separator: "\n") + "\n\n"
        }
        let days = BodyEngine.shared.days.filter { $0.day > since }
        let sleep = days.filter(\.hasSleep).map { $0.asleep / 60 }
        let rhr = days.compactMap(\.rhr), hrv = days.compactMap(\.hrv)
        if !sleep.isEmpty || !rhr.isEmpty {
            out += "SLEEP & HEART (Apple Health)\n"
            if !sleep.isEmpty { out += String(format: "• Sleep: %.1f h a night on average (%d nights)\n", sleep.reduce(0, +) / Double(sleep.count), sleep.count) }
            if !rhr.isEmpty { out += String(format: "• Resting heart rate: %.0f bpm average\n", rhr.reduce(0, +) / Double(rhr.count)) }
            if !hrv.isEmpty { out += String(format: "• Heart rate variability: %.0f ms average\n", hrv.reduce(0, +) / Double(hrv.count)) }
            out += "\n"
        }
        let bp = BloodPressure.all.filter { $0.at > since }
        if !bp.isEmpty {
            let s = bp.reduce(0) { $0 + $1.systolic } / bp.count, d = bp.reduce(0) { $0 + $1.diastolic } / bp.count
            out += "BLOOD PRESSURE\n• \(bp.count) readings, average \(s)/\(d)\n\n"
        }
        let labs = Biomarkers.latest()
        if !labs.isEmpty {
            out += "LAB RESULTS (latest)\n"
            for d in Biomarkers.defs { if let r = labs[d.id] { out += "• \(d.name): \(r.value.formatted()) \(d.unit) (\(r.date.formatted(date: .abbreviated, time: .omitted)), \(Biomarkers.status(d, r.value).0.lowercased()))\n" } }
            out += "\n"
        }
        let lifts = StrengthStore.sessions.filter { $0.start > since }
        if !lifts.isEmpty || !days.isEmpty {
            out += "ACTIVITY\n"
            if !days.isEmpty { out += "• Workouts recorded: \(days.reduce(0) { $0 + $1.workouts.count }) in 30 days\n" }
            if !lifts.isEmpty { out += "• Strength sessions: \(lifts.count)\n" }
            if let vo2 = days.compactMap(\.vo2).last { out += String(format: "• Cardio fitness (VO2 max): %.1f\n", vo2) }
            out += "\n"
        }
        let card = MedicalCardData.current
        if !card.allergies.isEmpty || !card.conditions.isEmpty {
            out += "ALSO\n" + (card.allergies.isEmpty ? "" : "• Allergies: \(card.allergies)\n") + (card.conditions.isEmpty ? "" : "• Conditions: \(card.conditions)\n")
        }
        return out
    }
}

struct DoctorSummaryView: View {
    @Environment(\.modelContext) private var ctx
    @State private var text = ""
    var body: some View {
        ScrollView {
            Text(text).font(.system(.callout, design: .monospaced)).textSelection(.enabled).padding()
        }
        .navigationTitle("For my doctor")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share") }
            ToolbarItem(placement: .secondaryAction) {
                Button("Save as a page", systemImage: "doc.badge.plus") {
                    let n = Note(title: "Health summary \(Date().formatted(date: .abbreviated, time: .omitted))", blocks: SmartPaste.blocks(from: text))
                    n.icon = "🩺"; ctx.insert(n); try? ctx.save(); UndoCenter.shared.notify("Saved to Notes")
                }
            }
        }
        .task { text = DoctorSummary.text(ctx: ctx) }
    }
}
