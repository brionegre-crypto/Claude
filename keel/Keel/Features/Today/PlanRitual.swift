import SwiftUI
import SwiftData

/// A 3-minute morning ritual: deal with yesterday's leftovers, pick today's tasks,
/// check them against the time you actually have, then put them on your calendar.
struct PlanRitualView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var tasks: [TaskItem]
    @State private var step = 0
    @State private var picked: Set<UUID> = []
    @State private var blocked: AutoScheduler.Result?
    @AppStorage("plan.endHour") private var endHour = 18

    private let cal = Calendar.current
    private var startOfToday: Date { cal.startOfDay(for: Date()) }
    private var endOfToday: Date { cal.date(byAdding: .day, value: 1, to: startOfToday)! }
    private var open: [TaskItem] { tasks.filter { !$0.isDone && !$0.isSomeday } }
    private var leftovers: [TaskItem] { open.filter { ($0.dueDate ?? .distantFuture) < startOfToday } }
    private var candidates: [TaskItem] {
        let week = cal.date(byAdding: .day, value: 7, to: endOfToday)!
        return open.filter { ($0.dueDate ?? .distantPast) < week || $0.dueDate == nil }
            .sorted { ($0.dueDate ?? .distantFuture, -$0.priority.rawValue) < ($1.dueDate ?? .distantFuture, -$1.priority.rawValue) }
    }
    private var plannedMinutes: Int { open.filter { picked.contains($0.id) }.reduce(0) { $0 + ADHDCoach.calibratedMinutes($1) } }
    private var freeMinutes: Int {
        Int(CalendarService.shared.freeSlots(minMinutes: 15, from: Date(), until: endHour).reduce(0) { $0 + $1.duration } / 60)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: 4).tint(DS.Palette.accent).padding(.horizontal)
                Group {
                    switch step {
                    case 0: leftoversStep
                    case 1: pickStep
                    case 2: capacityStep
                    default: blockStep
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle(["Yesterday", "Today", "Reality check", "Lock it in"][step])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if step < 3 { Button("Next") { withAnimation(DS.spring) { step += 1 } } }
                    else { Button("Done") { finish() } }
                }
            }
            .onAppear {
                if leftovers.isEmpty { step = 1 }
                picked = Set(open.filter { ($0.dueDate ?? .distantFuture) < endOfToday && ($0.dueDate ?? .distantPast) >= startOfToday }.map(\.id))
            }
        }
    }

    // 1. Leftovers: decide, don't drag.
    private var leftoversStep: some View {
        List {
            Section { } footer: { Text("These slipped. No guilt: pick one move for each.") }
            ForEach(leftovers) { t in
                VStack(alignment: .leading, spacing: 6) {
                    Text(t.title).font(DS.Font.headline)
                    HStack {
                        Button("Today") { move(t, days: 0); picked.insert(t.id) }
                        Button("Tomorrow") { move(t, days: 1) }
                        Button("Someday") { t.isSomeday = true; t.dueDate = nil }
                        Button("Done") { TaskActions.setDone(t, true) }
                    }
                    .font(DS.Font.caption).buttonStyle(.bordered)
                }
            }
            if leftovers.isEmpty { Text("All handled ✨").foregroundStyle(DS.Palette.calm) }
        }
    }

    // 2. Pick: what would make today a good day?
    private var pickStep: some View {
        List {
            Section { } footer: { Text("Tick what you'll do today. Fewer is better: 3 to 5 things is a great day.") }
            ForEach(candidates.prefix(40)) { t in
                Button {
                    if picked.contains(t.id) { picked.remove(t.id) } else { picked.insert(t.id) }
                    Haptics.tap()
                } label: {
                    HStack {
                        Image(systemName: picked.contains(t.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(picked.contains(t.id) ? DS.Palette.accent : .secondary)
                        VStack(alignment: .leading) {
                            Text(t.title).foregroundStyle(DS.Palette.ink)
                            Text("~\(ADHDCoach.calibratedMinutes(t)) min" + (t.dueDate.map { " · due \($0.formatted(.dateTime.weekday(.abbreviated)))" } ?? ""))
                                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                }
            }
        }
    }

    // 3. Capacity: time blindness, made visible.
    private var capacityStep: some View {
        List {
            Section {
                let ratio = Double(plannedMinutes) / Double(max(freeMinutes, 1))
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(hm(plannedMinutes)) planned · \(hm(freeMinutes)) free until \(endHour > 12 ? endHour - 12 : endHour) \(endHour >= 12 ? "PM" : "AM")")
                        .font(DS.Font.headline)
                    ProgressView(value: min(ratio, 1)).tint(ratio > 1 ? DS.Palette.warmth : ratio > 0.8 ? .yellow : DS.Palette.calm)
                    Text(ratio > 1 ? "That's more than you have. Untick something below, it'll still be there tomorrow."
                         : ratio > 0.8 ? "Tight but doable. Leave room for surprises." : "Realistic. Nice.")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                Stepper("Work until \(endHour > 12 ? endHour - 12 : endHour) \(endHour >= 12 ? "PM" : "AM")", value: $endHour, in: 12...23)
            } footer: { Text("Estimates use how long things really take you, not how long you hope.") }
            Section("Today") {
                ForEach(open.filter { picked.contains($0.id) }) { t in
                    HStack {
                        Text(t.title)
                        Spacer()
                        Text("\(ADHDCoach.calibratedMinutes(t))m").foregroundStyle(DS.Palette.inkSoft)
                    }
                    .swipeActions { Button("Not today") { picked.remove(t.id) }.tint(DS.Palette.warmth) }
                }
            }
        }
    }

    // 4. Lock it in: time blocks on the calendar.
    private var blockStep: some View {
        VStack(spacing: DS.Space.l) {
            Image(systemName: "calendar.badge.clock").font(.system(size: 48)).foregroundStyle(DS.Palette.accent).padding(.top, 40)
            Text("Put these on your calendar?").font(DS.Font.title)
            Text("Keel fits them into your free gaps, hardest first while you're fresh, with breaks between.")
                .multilineTextAlignment(.center).foregroundStyle(DS.Palette.inkSoft).padding(.horizontal)
            if let r = blocked {
                Label("\(r.scheduled) blocked" + (r.unscheduled.isEmpty ? "" : " · \(r.unscheduled.count) didn't fit"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(DS.Palette.calm)
            } else {
                Button("Time-block my day") { applyPicks(); blocked = AutoScheduler.scheduleToday(tasks: open.filter { picked.contains($0.id) }, endHour: endHour) }
                    .buttonStyle(.borderedProminent).tint(DS.Palette.accent).controlSize(.large)
                Button("Skip, just make the list") { finish() }
            }
        }
        .padding()
    }

    private func move(_ t: TaskItem, days: Int) {
        TaskActions.reschedule(t, to: cal.date(byAdding: .day, value: days, to: startOfToday)!)
    }

    /// Picked tasks become due today; unpicked ones that were due today move to tomorrow.
    private func applyPicks() {
        for t in open {
            let dueToday = t.dueDate.map { $0 >= startOfToday && $0 < endOfToday } ?? false
            if picked.contains(t.id) && !dueToday && !t.hasDueTime { TaskActions.reschedule(t, to: startOfToday) }
            if !picked.contains(t.id) && dueToday && !t.hasDueTime { TaskActions.reschedule(t, to: cal.date(byAdding: .day, value: 1, to: startOfToday)!) }
        }
    }

    private func finish() {
        if blocked == nil { applyPicks() }
        UserDefaults.standard.set(startOfToday.timeIntervalSince1970, forKey: "plan.lastDay")
        try? ctx.save()
        Haptics.success()
        dismiss()
    }

    private func hm(_ m: Int) -> String { m >= 60 ? "\(m / 60)h\(m % 60 == 0 ? "" : " \(m % 60)m")" : "\(m)m" }
}

/// Morning prompt on Today until you've planned.
struct PlanRitualPrompt: View {
    @State private var show = false
    @AppStorage("plan.lastDay") private var lastDay: Double = 0

    var body: some View {
        if lastDay < Calendar.current.startOfDay(for: Date()).timeIntervalSince1970 {
            Button { show = true } label: {
                GlassCard(tint: DS.Palette.accent) {
                    HStack {
                        Image(systemName: "list.bullet.clipboard").font(.title2).foregroundStyle(DS.Palette.accent)
                        VStack(alignment: .leading) {
                            Text("Plan your day").font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                            Text("3 minutes: leftovers, picks, a reality check.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(DS.Palette.inkSoft)
                    }
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $show) { PlanRitualView() }
        }
    }
}
