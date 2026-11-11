import SwiftUI
import SwiftData
import EventKit

/// Home screen. ADHD rule: ONE focal point. The "Just One Thing" card dominates; everything else is quieter.
struct TodayView: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var tasks: [TaskItem]
    @Query(sort: \EmailMessage.priorityScore, order: .reverse) private var emails: [EmailMessage]
    @Query private var stacks: [HabitStack]
    @AppStorage("energy") private var energyRaw = EnergyLevel.medium.rawValue
    @State private var plan: DayPlan?
    @State private var planning = false
    @State private var showSettings = false
    @State private var showBrainDump = false

    private var energy: EnergyLevel { EnergyLevel(rawValue: energyRaw) ?? .medium }
    private var nextThing: TaskItem? { ADHDCoach.nextThing(tasks: tasks, energy: energy) }
    private var events: [EKEvent] { CalendarService.shared.todaysEvents().filter { $0.endDate > Date() } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    greeting
                    energyPicker
                    justOneThing
                    if !events.isEmpty { upNext }
                    planCard
                    attentionCard
                    avoidedCard
                }
                .padding(DS.Space.m)
            }
            .background(DS.Palette.canvas)
            .refreshable { await SyncEngine.shared.syncAll() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showBrainDump = true } label: { Image(systemName: "brain.head.profile") }
                        .accessibilityLabel("Brain dump")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { HabitsView() } label: { Image(systemName: "link") }
                        .accessibilityLabel("Habit stacks")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "person.crop.circle") }
                }
            }
            .sheet(isPresented: $showSettings) { AccountsView() }
            .sheet(isPresented: $showBrainDump) { BrainDumpView() }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).textCase(.uppercase)
            Text(greetingText).font(DS.Font.hero)
        }
    }

    private var greetingText: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case ..<12: "Good morning"
        case ..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private var energyPicker: some View {
        HStack(spacing: DS.Space.s) {
            Text("Energy").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            ForEach(EnergyLevel.allCases) { level in
                Button {
                    withAnimation(DS.spring) { energyRaw = level.rawValue }; Haptics.tap()
                } label: {
                    Label(level.label, systemImage: level.icon).font(DS.Font.caption)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(energy == level ? DS.Palette.accent.opacity(0.16) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(energy == level ? DS.Palette.accent : DS.Palette.inkSoft)
            }
        }
    }

    private var justOneThing: some View {
        GlassCard(tint: DS.Palette.focus) {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Text("JUST ONE THING").font(DS.Font.caption).foregroundStyle(DS.Palette.focus)
                if let t = nextThing {
                    Text(t.title).font(DS.Font.title)
                    if let step = t.microSteps.first(where: { !$0.done }) {
                        Label("Start with: \(step.text)", systemImage: "arrow.turn.down.right")
                            .font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
                    }
                    HStack {
                        Chip(text: "~\(ADHDCoach.calibratedMinutes(t)) min", color: DS.Palette.focus, icon: "clock")
                        if let due = t.dueDate { Chip(text: due.formatted(.relative(presentation: .named)), color: DS.Palette.warmth) }
                        Spacer()
                        NavigationLink { FocusView(preselected: t) } label: {
                            Label("Start", systemImage: "play.fill").font(DS.Font.headline)
                                .padding(.horizontal, DS.Space.m).padding(.vertical, DS.Space.s)
                                .background(DS.Palette.focus, in: Capsule()).foregroundStyle(.white)
                        }
                    }
                } else {
                    Text("Nothing urgent. Enjoy the space — or pick a habit stack.").font(DS.Font.body)
                }
            }
        }
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            SectionHeader(title: "Up next", trailing: "all calendars")
            ForEach(events.prefix(3), id: \.eventIdentifier) { e in
                HStack(spacing: DS.Space.m) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(cgColor: e.calendar.cgColor)).frame(width: 4, height: 34)
                    VStack(alignment: .leading) {
                        Text(e.title ?? "Event").font(DS.Font.headline)
                        Text("\(e.startDate.formatted(date: .omitted, time: .shortened)) · \(e.calendar.source.title)")
                            .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                    Spacer()
                    // Time-blindness aid: countdown, not a timestamp
                    Text(e.startDate, style: .relative).font(DS.Font.caption).foregroundStyle(DS.Palette.meeting)
                }
            }
        }
    }

    private var planCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack {
                    Text("Today's plan").font(DS.Font.headline)
                    Spacer()
                    Button("Reset my day") {
                        ADHDCoach.resetDay(tasks: tasks); Haptics.success()
                        Task { await makePlan() }
                    }.font(DS.Font.caption)
                }
                if planning { ProgressView().frame(maxWidth: .infinity) }
                else if let plan {
                    Text(plan.headline).font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
                    ForEach(plan.blocks) { b in
                        HStack {
                            Text(b.start).font(DS.Font.caption.monospacedDigit()).frame(width: 48, alignment: .leading)
                            Text(b.title).font(DS.Font.body)
                            Spacer()
                            Image(systemName: icon(for: b.kind)).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                } else {
                    Button { Task { await makePlan() } } label: {
                        Label("Plan my day with AI", systemImage: "sparkles").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(DS.Palette.accent)
                }
            }
        }
    }

    private var attentionCard: some View {
        let top = emails.filter { !$0.isArchived && ($0.category == .important || $0.category == .actionable) }.prefix(3)
        return Group {
            if !top.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    SectionHeader(title: "Needs you", trailing: "from all inboxes")
                    ForEach(Array(top)) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.fromName.isEmpty ? e.from : e.fromName).font(DS.Font.headline)
                            Text(e.aiSummary ?? e.snippet).font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    private var avoidedCard: some View {
        let avoided = ADHDCoach.avoidedTasks(tasks)
        return Group {
            if let t = avoided.first {
                GlassCard(tint: DS.Palette.warmth) {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text("“\(t.title)” keeps sliding. That's normal.").font(DS.Font.headline)
                        Text("Want to shrink it, do it together for 10 minutes, or let it go?").font(DS.Font.body)
                        HStack {
                            NavigationLink("Shrink it") { TaskDetailView(task: t) }
                            Spacer()
                            NavigationLink("Body double") { FocusView(preselected: t, bodyDouble: true) }
                            Spacer()
                            Button("Let it go") { t.listName = "Someday"; t.dueDate = nil }
                        }.font(DS.Font.caption)
                    }
                }
            }
        }
    }

    private func icon(for kind: String) -> String {
        ["focus": "scope", "meeting": "person.2", "email": "tray", "habit": "link", "break": "cup.and.saucer", "shutdown": "moon.zzz"][kind] ?? "circle"
    }

    private func makePlan() async {
        planning = true; defer { planning = false }
        let ctxData = DayContext(
            now: Date().formatted(date: .abbreviated, time: .shortened),
            events: events.map { "\($0.startDate.formatted(date: .omitted, time: .shortened))-\($0.endDate.formatted(date: .omitted, time: .shortened)) \($0.title ?? "")" },
            tasks: tasks.prefix(20).map { "\($0.title) [~\(ADHDCoach.calibratedMinutes($0))m, energy \($0.energy.label)]" },
            importantEmails: emails.filter { $0.category == .important }.prefix(5).map { $0.subject },
            habitStacks: stacks.map { "\($0.name): \($0.anchor.label)" })
        plan = await AIRouter.shared.planDay(context: ctxData)
    }
}

struct BrainDumpView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                Text("Empty your head. One thing per line. Don't organize — Keel will.")
                    .font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
                TextEditor(text: $text)   // Apple Intelligence Writing Tools + dictation work here for free
                    .scrollContentBackground(.hidden)
                    .padding(DS.Space.s)
                    .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.chip))
            }
            .padding()
            .navigationTitle("Brain dump")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sort it") {
                        ADHDCoach.parseBrainDump(text).forEach { ctx.insert($0) }
                        Haptics.success(); dismiss()
                    }.disabled(text.isEmpty)
                }
            }
        }
    }
}
