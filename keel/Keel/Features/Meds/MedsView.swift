import SwiftUI
import SwiftData

/// Medications: today's doses with one-tap logging, refill counts, and 2 weeks of history.
struct MedsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Medication.createdAt) private var meds: [Medication]
    @Query(sort: \MedDose.takenAt, order: .reverse) private var doses: [MedDose]
    @State private var editing: Medication?
    @State private var adding = false

    var body: some View {
        List {
            if meds.isEmpty {
                ContentUnavailableView {
                    Label("No medications", systemImage: "pills")
                } description: {
                    Text("Add a medication to get reminders with a Taken button, and always know whether you already took it.")
                } actions: {
                    Button("Add medication") { adding = true }.buttonStyle(.borderedProminent).tint(DS.Palette.accent)
                }
            } else {
                Section { Text(MedEngine.statusSentence(ctx: ctx)).font(.callout) } header: { Text("Did I take it?") }
                Section("Today") {
                    ForEach(meds.filter(\.isActive)) { m in
                        ForEach(m.times.sorted(), id: \.self) { slot in MedDoseRow(med: m, slot: slot, doses: doses) }
                    }
                }
                Section("Medications") {
                    ForEach(meds) { m in
                        Button { editing = m } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(m.name) \(m.dose)").foregroundStyle(DS.Palette.ink)
                                HStack(spacing: 8) {
                                    Text(m.times.sorted().map(MedEngine.timeLabel).joined(separator: ", "))
                                    if let left = m.pillsLeft {
                                        Text("· \(left) left").foregroundStyle(left <= m.refillAt ? .orange : DS.Palette.inkSoft)
                                    }
                                    if !m.isActive { Text("· paused") }
                                }
                                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                            }
                        }
                    }
                    .onDelete { for i in $0 { ctx.delete(meds[i]) }; MedEngine.scheduleAll(ctx: ctx) }
                }
                Section("Last 14 days") { history }
            }
        }
        .navigationTitle("Medications")
        .toolbar { Button("Add", systemImage: "plus") { adding = true } }
        .sheet(isPresented: $adding) { MedEditor(med: nil) }
        .sheet(item: $editing) { MedEditor(med: $0) }
    }

    private var history: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let active = meds.filter(\.isActive)
        let perDay = max(1, active.reduce(0) { $0 + $1.times.count })
        return HStack(spacing: 4) {
            ForEach((0..<14).reversed(), id: \.self) { i in
                let d = cal.date(byAdding: .day, value: -i, to: today)!
                let n = doses.filter { $0.day == d }.count
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(n >= perDay ? DS.Palette.calm : n > 0 ? DS.Palette.warmth : Color.secondary.opacity(0.2))
                        .frame(height: 22)
                    Text(d.formatted(.dateTime.weekday(.narrow))).font(.system(size: 9)).foregroundStyle(DS.Palette.inkSoft)
                }
                .accessibilityLabel("\(d.formatted(date: .abbreviated, time: .omitted)): \(n) of \(perDay)")
            }
        }
    }
}

struct MedDoseRow: View {
    let med: Medication
    let slot: Int
    let doses: [MedDose]
    @Environment(\.modelContext) private var ctx

    var body: some View {
        let dose = MedEngine.taken(med, slot: slot, doses: doses)
        HStack {
            Image(systemName: "pills.fill").foregroundStyle(dose == nil ? DS.Palette.accent : DS.Palette.calm)
            VStack(alignment: .leading) {
                Text("\(med.name) \(med.dose)")
                Text(dose.map { "Taken at \($0.takenAt.formatted(date: .omitted, time: .shortened))" } ?? "Due \(MedEngine.timeLabel(slot))")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
            Spacer()
            if let dose {
                Button("Undo") { MedEngine.undo(dose, med: med, ctx: ctx) }.font(DS.Font.caption)
            } else {
                Button("Taken") { MedEngine.take(med, slot: slot, ctx: ctx) }
                    .buttonStyle(.borderedProminent).tint(DS.Palette.accent)
            }
        }
    }
}

struct MedEditor: View {
    var med: Medication?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var dose = ""
    @State private var times: [Date] = [Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!]
    @State private var remind = true
    @State private var active = true
    @State private var track = false
    @State private var pillsLeft = 30
    @State private var refillAt = 7

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Dose (e.g. 20 mg)", text: $dose)
                }
                Section("Times") {
                    ForEach(times.indices, id: \.self) { i in
                        DatePicker("Dose \(i + 1)", selection: $times[i], displayedComponents: .hourAndMinute)
                    }
                    .onDelete { if times.count > 1 { times.remove(atOffsets: $0) } }
                    Button("Add a time", systemImage: "plus") { times.append(times.last!.addingTimeInterval(4 * 3600)) }
                }
                Section {
                    Toggle("Remind me", isOn: $remind)
                    Toggle("Active", isOn: $active)
                } footer: { Text("If you don't tap Taken, Keel nudges you once more 30 minutes later.") }
                Section("Refills") {
                    Toggle("Count pills", isOn: $track)
                    if track {
                        Stepper("\(pillsLeft) left", value: $pillsLeft, in: 0...999)
                        Stepper("Warn at \(refillAt)", value: $refillAt, in: 1...60)
                    }
                }
            }
            .navigationTitle(med == nil ? "New Medication" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let m = med else { return }
        name = m.name; dose = m.dose; remind = m.remind; active = m.isActive
        times = m.times.sorted().map { Calendar.current.date(bySettingHour: $0 / 60, minute: $0 % 60, second: 0, of: Date())! }
        if let p = m.pillsLeft { track = true; pillsLeft = p }
        refillAt = m.refillAt
    }

    private func save() {
        let mins = Array(Set(times.map { Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) })).sorted()
        let m = med ?? Medication(name: name)
        if med == nil { ctx.insert(m) }
        m.name = name; m.dose = dose; m.times = mins; m.remind = remind; m.isActive = active
        m.pillsLeft = track ? pillsLeft : nil; m.refillAt = refillAt
        try? ctx.save()
        MedEngine.scheduleAll(ctx: ctx)
        Haptics.success()
        dismiss()
    }
}

/// Today card: shows only when a dose is due or overdue and not yet taken.
struct MedsTodayCard: View {
    @Query private var meds: [Medication]
    @Query private var doses: [MedDose]

    var body: some View {
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let nowMin = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        let due = meds.filter(\.isActive).flatMap { m in m.times.sorted().map { (m, $0) } }
            .filter { $0.1 <= nowMin + 60 && MedEngine.taken($0.0, slot: $0.1, doses: doses) == nil }
        if !due.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    NavigationLink { MedsView() } label: {
                        Label("Medication", systemImage: "pills.fill").font(DS.Font.headline)
                    }.buttonStyle(.plain)
                    ForEach(Array(due.enumerated()), id: \.offset) { item in
                        MedDoseRow(med: item.element.0, slot: item.element.1, doses: doses)
                    }
                }
            }
        }
    }
}
