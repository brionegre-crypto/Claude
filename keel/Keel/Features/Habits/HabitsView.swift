import SwiftUI
import SwiftData

/// Habit stacks: "After <anchor>, I will A → B → C". Chains, not checklists.
struct HabitsView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var stacks: [HabitStack]
    @Query private var habits: [Habit]
    @Query(sort: \HabitLog.day, order: .reverse) private var logs: [HabitLog]
    @State private var showNew = false

    var body: some View {
            ScrollView {
                VStack(spacing: DS.Space.m) {
                    if stacks.isEmpty {
                        ContentUnavailableView {
                            Label("Stack your first habits", systemImage: "link")
                        } description: {
                            Text("Attach tiny habits to things you already do. “After my morning coffee → take meds → 2-min plan.”")
                        } actions: {
                            Button("Use a starter stack") { seedStarter() }.buttonStyle(.borderedProminent).tint(DS.Palette.accent)
                        }
                    }
                    ForEach(stacks) { stack in stackCard(stack) }
                }
                .padding()
            }
            .navigationTitle("Habits")
            .toolbar { Button { showNew = true } label: { Image(systemName: "plus") } }
            .sheet(isPresented: $showNew) { NewStackView() }
            .onAppear { HabitEngine.scheduleEventAnchoredStacks(stacks, habits: habits) }
    }

    private func stackCard(_ stack: HabitStack) -> some View {
        let chain = habits.filter { $0.stackId == stack.id }.sorted { $0.orderInStack < $1.orderInStack }
        let today = Calendar.current.startOfDay(for: Date())
        return GlassCard {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(stack.name).font(DS.Font.title)
                        Label(stack.anchor.label, systemImage: "bolt.horizontal").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                    Spacer()
                    Text("\(chain.reduce(0) { $0 + $1.minutes }) min").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                ForEach(Array(chain.enumerated()), id: \.element.id) { i, h in
                    let doneToday = logs.contains { $0.habitId == h.id && $0.day == today }
                    HStack(spacing: DS.Space.m) {
                        CompletionCheck(isDone: Binding(get: { doneToday }, set: { done in
                            guard done, !doneToday else { return }
                            let last = logs.first { $0.habitId == h.id }?.day
                            HabitEngine.complete(h, lastCompletedDay: last, ctx: ctx)
                        }))
                        Image(systemName: h.icon).frame(width: 22)
                        Text(h.name)
                        Spacer()
                        if h.currentStreak > 0 { Chip(text: "\(h.currentStreak)🔥", color: DS.Palette.warmth) }
                        if h.graceTokens > 0 { Text(String(repeating: "◇", count: h.graceTokens)).font(.caption).foregroundStyle(DS.Palette.calm).accessibilityLabel("\(h.graceTokens) grace days") }
                    }
                    if i < chain.count - 1 { Image(systemName: "arrow.down").font(.caption).foregroundStyle(DS.Palette.inkSoft).padding(.leading, 6) }
                }
                HabitHeatmap(habitIds: chain.map(\.id), logs: logs)
                    .padding(.top, DS.Space.xs)
            }
        }
    }

    private func seedStarter() {
        let s = HabitStack(name: "Launch sequence", anchor: .manual(label: "pour my coffee"))
        ctx.insert(s)
        for (i, (name, icon, min)) in [("Take meds", "pills", 1), ("Drink water", "drop", 1), ("Pick today's ONE thing", "scope", 2)].enumerated() {
            let h = Habit(name: name, icon: icon, minutes: min); h.stackId = s.id; h.orderInStack = i; ctx.insert(h)
        }
        let s2 = HabitStack(name: "Post-focus reset", anchor: .afterFocusSession)
        ctx.insert(s2)
        for (i, (name, icon, min)) in [("Stand + stretch", "figure.walk", 2), ("Refill water", "drop", 1)].enumerated() {
            let h = Habit(name: name, icon: icon, minutes: min); h.stackId = s2.id; h.orderInStack = i; ctx.insert(h)
        }
    }
}

struct NewStackView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var anchorKind = 0
    @State private var anchorText = ""
    @State private var time = Date()
    @State private var habitNames: [String] = [""]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Stack name", text: $name)
                Section("After…") {
                    Picker("Anchor", selection: $anchorKind) {
                        Text("Something I do").tag(0); Text("A time").tag(1); Text("A calendar event").tag(2)
                        Text("A focus session").tag(3); Text("Inbox zero").tag(4)
                    }
                    switch anchorKind {
                    case 0: TextField("e.g. brush my teeth", text: $anchorText)
                    case 1: DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    case 2: TextField("Event title contains… e.g. standup", text: $anchorText)
                    default: EmptyView()
                    }
                }
                Section("…I will (keep each one tiny)") {
                    ForEach(habitNames.indices, id: \.self) { i in TextField("Habit \(i + 1)", text: $habitNames[i]) }
                    Button("Add another") { habitNames.append("") }
                }
            }
            .navigationTitle("New stack")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(name.isEmpty) } }
        }
    }

    private func save() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        let anchor: StackAnchor = switch anchorKind {
        case 1: .time(hour: c.hour ?? 8, minute: c.minute ?? 0)
        case 2: .afterEvent(keyword: anchorText)
        case 3: .afterFocusSession
        case 4: .afterInboxZero
        default: .manual(label: anchorText)
        }
        let s = HabitStack(name: name, anchor: anchor)
        ctx.insert(s)
        for (i, n) in habitNames.filter({ !$0.isEmpty }).enumerated() {
            let h = Habit(name: n); h.stackId = s.id; h.orderInStack = i; ctx.insert(h)
        }
        dismiss()
    }
}

/// 12-week heatmap for a habit stack: darker = more of the stack done that day.
struct HabitHeatmap: View {
    let habitIds: [UUID]
    let logs: [HabitLog]
    private let weeks = 12
    private let cal = Calendar.current

    var body: some View {
        let today = cal.startOfDay(for: Date())
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let start = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek)!
        let ids = Set(habitIds)
        var perDay: [Date: Int] = [:]
        for l in logs where ids.contains(l.habitId) && l.day >= start { perDay[l.day, default: 0] += 1 }
        let total = max(1, habitIds.count)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                            let done = perDay[day] ?? 0
                            RoundedRectangle(cornerRadius: 3)
                                .fill(day > today ? Color.clear
                                      : done == 0 ? DS.Palette.inkSoft.opacity(0.12)
                                      : DS.Palette.calm.opacity(0.3 + 0.7 * Double(done) / Double(total)))
                                .frame(width: 14, height: 14)
                        }
                    }
                }
            }
            Text("Last 12 weeks").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
        }
        .accessibilityElement()
        .accessibilityLabel("\(perDay.count) active days in the last 12 weeks")
    }
}
