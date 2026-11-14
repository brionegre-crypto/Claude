import SwiftUI
import SwiftData
import UserNotifications

// MARK: - Log a dose: any medication, any time (earlier today, yesterday, an extra dose, or something new)

enum MedLog {
    /// Slots at or above this are extra doses, not one of the scheduled times.
    static let extraBase = 1440

    static func isExtra(_ d: MedDose) -> Bool { d.slot >= extraBase }

    /// Scheduled times on that day that don't have a dose yet.
    static func openSlots(_ m: Medication, on day: Date, doses: [MedDose]) -> [Int] {
        m.times.sorted().filter { MedEngine.taken(m, slot: $0, on: day, doses: doses) == nil }
    }

    /// The scheduled time closest to when you took it, so a 7:40 dose counts as the 8:00 one.
    static func bestSlot(_ open: [Int], at time: Date) -> Int? {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        let minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return open.min { abs($0 - minute) < abs($1 - minute) }
    }

    /// A unique slot number for an extra dose on that day.
    static func extraSlot(at time: Date, existing: [MedDose], medId: UUID, day: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        var slot = extraBase + (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let used = Set(existing.filter { $0.medicationId == medId && $0.day == day }.map(\.slot))
        while used.contains(slot) { slot += 1 }
        return slot
    }

    /// Records a dose of a scheduled medication. `slot` nil means an extra dose.
    @discardableResult
    static func log(_ m: Medication, slot: Int?, at time: Date, ctx: ModelContext) -> MedDose {
        let day = Calendar.current.startOfDay(for: time)
        let all = (try? ctx.fetch(FetchDescriptor<MedDose>())) ?? []
        let s: Int
        if let slot, MedEngine.taken(m, slot: slot, on: day, doses: all) == nil { s = slot }
        else { s = extraSlot(at: time, existing: all, medId: m.id, day: day) }
        let dose = MedDose(medicationId: m.id, slot: s, day: day)
        dose.takenAt = time
        ctx.insert(dose)
        if let left = m.pillsLeft { m.pillsLeft = max(0, left - 1) }
        if s < extraBase, Calendar.current.isDateInToday(day) {
            let center = UNUserNotificationCenter.current()
            center.removeDeliveredNotifications(withIdentifiers: ["med.\(m.id).\(s)"])
            center.removePendingNotificationRequests(withIdentifiers: ["med.nag.\(m.id).\(s).\(Int(day.timeIntervalSince1970))"])
        }
        try? ctx.save()
        WidgetSync.update(ctx)
        return dose
    }
}

struct LogDoseSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Medication.createdAt) private var meds: [Medication]
    @Query(sort: \MedDose.takenAt, order: .reverse) private var doses: [MedDose]

    private enum Pick: Hashable { case scheduled(UUID), prn(UUID), new }
    @State private var pick: Pick?
    @State private var when = Date()
    @State private var countsAs: Int = -1          // -1 = closest open time, -2 = extra dose, else a slot
    @State private var newName = ""
    @State private var newDose = ""
    @State private var saveAsNeeded = true
    @State private var prnMeds = PRN.meds
    @State private var warning: String?
    @State private var confirmAnyway = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Medication", selection: $pick) {
                        Text("Choose…").tag(Pick?.none)
                        ForEach(meds.filter(\.isActive)) { m in Text("\(m.name) \(m.dose)").tag(Pick?.some(.scheduled(m.id))) }
                        ForEach(prnMeds) { m in Text("\(m.name) \(m.dose) · as needed").tag(Pick?.some(.prn(m.id))) }
                        Text("Something else…").tag(Pick?.some(.new))
                    }
                    if pick == .new {
                        TextField("Name, like Ibuprofen", text: $newName)
                        TextField("Dose, like 200 mg (optional)", text: $newDose)
                        Toggle("Keep it in my as-needed list", isOn: $saveAsNeeded)
                    }
                } footer: {
                    Text("Log anything you took: a dose from earlier, one you forgot to tap, an extra dose, or a medicine that isn't in your list.")
                }

                Section {
                    DatePicker("Taken", selection: $when, in: Date().addingTimeInterval(-3 * 86400)...Date())
                    HStack(spacing: 8) {
                        ForEach([0, 30, 60, 120], id: \.self) { m in
                            Button(m == 0 ? "Now" : m < 60 ? "\(m) min ago" : "\(m / 60) h ago") {
                                when = Date().addingTimeInterval(-Double(m) * 60)
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }

                if let m = scheduledMed {
                    let open = MedLog.openSlots(m, on: when, doses: doses)
                    Section {
                        Picker("Counts as", selection: $countsAs) {
                            if !open.isEmpty { Text("Closest time (\(MedEngine.timeLabel(MedLog.bestSlot(open, at: when) ?? open[0])))").tag(-1) }
                            ForEach(open, id: \.self) { s in Text("The \(MedEngine.timeLabel(s)) dose").tag(s) }
                            Text("An extra dose").tag(-2)
                        }
                    } footer: {
                        Text(open.isEmpty ? "Every scheduled dose that day is already logged, so this is saved as an extra dose." : "Pick which scheduled dose this was, so Keel stops reminding you about it.")
                    }
                }

                if let warning {
                    Section { Label(warning, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                }
            }
            .navigationTitle("Log a dose")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Log") { save() }.disabled(!canSave) }
            }
            .onChange(of: pick) { warning = nil; confirmAnyway = false; countsAs = -1 }
            .onChange(of: when) { warning = nil; confirmAnyway = false }
            .alert("Log it anyway?", isPresented: $confirmAnyway) {
                Button("Log it", role: .destructive) { save(force: true) }
                Button("Cancel", role: .cancel) {}
            } message: { Text(warning ?? "") }
        }
    }

    private var scheduledMed: Medication? {
        if case .scheduled(let id) = pick { return meds.first { $0.id == id } }
        return nil
    }

    private var canSave: Bool {
        switch pick {
        case .none: return false
        case .new: return !newName.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }

    private func save(force: Bool = false) {
        switch pick {
        case .scheduled(let id):
            guard let m = meds.first(where: { $0.id == id }) else { return }
            let open = MedLog.openSlots(m, on: when, doses: doses)
            let slot: Int? = countsAs == -2 ? nil : countsAs == -1 ? MedLog.bestSlot(open, at: when) : countsAs
            MedLog.log(m, slot: slot, at: when, ctx: ctx)
            UndoCenter.shared.notify("Logged \(m.name) at \(when.formatted(date: .omitted, time: .shortened))")
        case .prn(let id):
            guard let m = prnMeds.first(where: { $0.id == id }) else { return }
            if !force, let why = PRN.check(m, doses: PRN.doses, now: when) { warning = why; confirmAnyway = true; return }
            PRN.doses = PRN.doses + [PRNDose(medId: m.id, at: when)]
            UndoCenter.shared.notify("Logged \(m.name)")
        case .new:
            let name = newName.trimmingCharacters(in: .whitespaces)
            var m = PRN.meds.first { $0.name.lowercased() == name.lowercased() }
            if m == nil {
                let made = PRNMed(name: name, dose: newDose, minHours: 0, maxPerDay: 99)
                if saveAsNeeded { PRN.meds = PRN.meds + [made] }
                m = made
            }
            if let m { PRN.doses = PRN.doses + [PRNDose(medId: m.id, at: when)] }
            if !saveAsNeeded { MedLog.noteOneOff(name: name, dose: newDose, at: when) }
            UndoCenter.shared.notify("Logged \(name)")
        case .none: return
        }
        Haptics.success()
        dismiss()
    }
}

extension MedLog {
    struct OneOff: Codable, Identifiable, Hashable { var id = UUID(); var name: String; var dose: String; var at: Date }
    static let oneOffKey = "health.meds.oneoff"
    static var oneOffs: [OneOff] { get { LocalLog.load(oneOffKey) } set { LocalLog.save(Array(newValue.suffix(300)), oneOffKey) } }
    static func noteOneOff(name: String, dose: String, at: Date) { oneOffs = oneOffs + [OneOff(name: name, dose: dose, at: at)] }

    /// Everything logged in the last day across scheduled, as-needed, and one-off medicines, newest first.
    struct Recent: Identifiable, Hashable { let id: String; let title: String; let at: Date }

    static func recent(meds: [Medication], doses: [MedDose], hours: Double = 24, now: Date = Date()) -> [Recent] {
        let since = now.addingTimeInterval(-hours * 3600)
        var out: [Recent] = []
        for d in doses where d.takenAt >= since {
            if let m = meds.first(where: { $0.id == d.medicationId }) {
                out.append(Recent(id: d.id.uuidString, title: "\(m.name) \(m.dose)\(isExtra(d) ? " · extra" : "")", at: d.takenAt))
            }
        }
        let prn = PRN.meds
        for d in PRN.doses where d.at >= since {
            if let m = prn.first(where: { $0.id == d.medId }) { out.append(Recent(id: d.id.uuidString, title: "\(m.name) \(m.dose)", at: d.at)) }
        }
        for o in oneOffs where o.at >= since { out.append(Recent(id: o.id.uuidString, title: "\(o.name) \(o.dose)", at: o.at)) }
        return out.sorted { $0.at > $1.at }
    }
}

/// "Logged in the last day" list with the times, shown on Body and in Medications.
struct RecentDosesList: View {
    let meds: [Medication]
    let doses: [MedDose]
    var body: some View {
        let items = MedLog.recent(meds: meds, doses: doses)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Logged in the last day").font(.caption.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft)
                ForEach(Array(items.prefix(6))) { i in
                    HStack {
                        Text(i.title.trimmingCharacters(in: .whitespaces)).font(.caption)
                        Spacer()
                        Text(i.at.formatted(date: Calendar.current.isDateInToday(i.at) ? .omitted : .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(DS.Palette.inkSoft).monospacedDigit()
                    }
                }
            }
        }
    }
}
