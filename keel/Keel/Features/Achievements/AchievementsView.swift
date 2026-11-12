import SwiftUI
import SwiftData

/// Momentum: a kind daily score (it only goes up during the day) and long-term achievements.
/// Built for ADHD brains: celebrates what you did, never counts what you didn't.
@MainActor
enum Momentum {
    struct Score { var total: Int; var tasks: Int; var focus: Int; var habits: Int; var checkIn: Int }

    static func recordInboxZero() {
        let key = "stats.inboxZeroDays", dayKey = "stats.inboxZeroLast"
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        guard UserDefaults.standard.double(forKey: dayKey) != today else { return }
        UserDefaults.standard.set(today, forKey: dayKey)
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
    }
    static var inboxZeroDays: Int { UserDefaults.standard.integer(forKey: "stats.inboxZeroDays") }

    /// 0–100: tasks up to 40, focus up to 30, habits up to 20, check-in 10.
    static func today(ctx: ModelContext) -> Score {
        let cal = Calendar.current
        let tasks = ((try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []).filter {
            ($0.completedAt.map(cal.isDateInToday) ?? false) || ($0.lastCompletedOccurrence.map(cal.isDateInToday) ?? false)
        }.count
        let focus = ((try? ctx.fetch(FetchDescriptor<FocusSession>())) ?? []).filter { cal.isDateInToday($0.startedAt) && $0.endedAt != nil }
            .reduce(0) { $0 + Int(($1.endedAt!.timeIntervalSince($1.startedAt)) / 60) }
        let habits = ((try? ctx.fetch(FetchDescriptor<HabitLog>())) ?? []).filter { cal.isDateInToday($0.day) }.count
        let checked = ((try? ctx.fetch(FetchDescriptor<CheckIn>())) ?? []).contains { cal.isDateInToday($0.day) }
        let s = Score(total: 0, tasks: min(40, tasks * 10), focus: min(30, focus / 2), habits: min(20, habits * 5), checkIn: checked ? 10 : 0)
        return Score(total: s.tasks + s.focus + s.habits + s.checkIn, tasks: s.tasks, focus: s.focus, habits: s.habits, checkIn: s.checkIn)
    }

    struct Achievement: Identifiable {
        let id: String
        let title: String
        let icon: String
        let detail: String
        let current: Int
        let target: Int
        var unlocked: Bool { current >= target }
    }

    static func achievements(ctx: ModelContext) -> [Achievement] {
        let tasks = ((try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? [])
        let done = tasks.filter(\.isDone).count + tasks.reduce(0) { $0 + $1.completionCount }
        let focusHours = ((try? ctx.fetch(FetchDescriptor<FocusSession>())) ?? [])
            .reduce(0) { $0 + Int((($1.endedAt ?? $1.startedAt).timeIntervalSince($1.startedAt)) / 60) } / 60
        let bestStreak = ((try? ctx.fetch(FetchDescriptor<Habit>())) ?? []).map(\.bestStreak).max() ?? 0
        let checkIns = ((try? ctx.fetch(FetchDescriptor<CheckIn>())) ?? []).count
        let medDoses = ((try? ctx.fetch(FetchDescriptor<MedDose>())) ?? []).count
        let notes = ((try? ctx.fetch(FetchDescriptor<Note>())) ?? []).count
        func tier(_ id: String, _ icon: String, _ name: String, _ unit: String, _ value: Int, _ targets: [Int]) -> [Achievement] {
            targets.map { t in Achievement(id: "\(id).\(t)", title: "\(name) · \(t)", icon: icon, detail: "\(t) \(unit)", current: value, target: t) }
        }
        return tier("tasks", "checkmark.seal.fill", "Finisher", "tasks completed", done, [1, 10, 50, 100, 500, 1000])
            + tier("focus", "moon.zzz.fill", "Deep diver", "hours of focus", focusHours, [1, 10, 25, 50, 100])
            + tier("streak", "flame.fill", "On a roll", "day habit streak", bestStreak, [3, 7, 30, 100])
            + tier("zero", "tray.fill", "Inbox zero", "days at inbox zero", inboxZeroDays, [1, 10, 50])
            + tier("checkin", "face.smiling.inverse", "Self-aware", "check-ins", checkIns, [7, 30, 100])
            + tier("notes", "note.text", "Thinker", "notes written", notes, [10, 50, 200])
            + tier("meds", "pills.fill", "Consistent", "doses logged", medDoses, [7, 30, 100])
    }

    /// Celebrate anything unlocked since last time (called when Today or Achievements appears).
    static func newlyUnlocked(ctx: ModelContext) -> [Achievement] {
        let seen = Set(UserDefaults.standard.stringArray(forKey: "achievements.seen") ?? [])
        let unlocked = achievements(ctx: ctx).filter(\.unlocked)
        UserDefaults.standard.set(unlocked.map(\.id), forKey: "achievements.seen")
        return seen.isEmpty ? [] : unlocked.filter { !seen.contains($0.id) }   // first run: no flood
    }
}

struct AchievementsView: View {
    @Environment(\.modelContext) private var ctx
    @State private var score = Momentum.Score(total: 0, tasks: 0, focus: 0, habits: 0, checkIn: 0)
    @State private var items: [Momentum.Achievement] = []

    var body: some View {
        List {
            Section {
                HStack(spacing: DS.Space.l) {
                    ZStack {
                        Circle().stroke(DS.Palette.accent.opacity(0.15), lineWidth: 10)
                        Circle().trim(from: 0, to: CGFloat(score.total) / 100)
                            .stroke(DS.Palette.accent.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(score.total)").font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                    }
                    .frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today's momentum").font(DS.Font.headline)
                        part("Tasks", score.tasks, 40); part("Focus", score.focus, 30)
                        part("Habits", score.habits, 20); part("Check-in", score.checkIn, 10)
                    }
                }
                .padding(.vertical, 4)
            } footer: { Text("Momentum only goes up. Every bit counts, and tomorrow starts fresh.") }

            let unlocked = items.filter(\.unlocked)
            Section("Unlocked · \(unlocked.count) of \(items.count)") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 12) {
                    ForEach(items) { a in
                        VStack(spacing: 4) {
                            Image(systemName: a.icon).font(.title)
                                .foregroundStyle(a.unlocked ? AnyShapeStyle(DS.Palette.accent.gradient) : AnyShapeStyle(Color.secondary.opacity(0.3)))
                            Text(a.title).font(.caption2.weight(.semibold)).multilineTextAlignment(.center)
                            if a.unlocked {
                                Text(a.detail).font(.system(size: 9)).foregroundStyle(DS.Palette.inkSoft)
                            } else {
                                ProgressView(value: Double(min(a.current, a.target)), total: Double(a.target)).tint(DS.Palette.accent)
                                Text("\(a.current)/\(a.target)").font(.system(size: 9)).foregroundStyle(DS.Palette.inkSoft).monospacedDigit()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Achievements")
        .onAppear {
            score = Momentum.today(ctx: ctx)
            items = Momentum.achievements(ctx: ctx)
            if !Momentum.newlyUnlocked(ctx: ctx).isEmpty { Haptics.milestone() }
        }
    }

    private func part(_ label: String, _ value: Int, _ max: Int) -> some View {
        HStack {
            Text(label).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).frame(width: 64, alignment: .leading)
            ProgressView(value: Double(value), total: Double(max)).tint(DS.Palette.accent)
        }
    }
}

/// Pinned tasks at the top of Today.
struct PinnedTasksCard: View {
    @Query(filter: #Predicate<TaskItem> { $0.isPinned && !$0.isDone }) private var pinned: [TaskItem]

    var body: some View {
        if !pinned.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Label("Pinned", systemImage: "pin.fill").font(DS.Font.headline).foregroundStyle(DS.Palette.accent)
                    ForEach(pinned.prefix(5)) { t in
                        NavigationLink { TaskDetailView(task: t) } label: { TaskRow(task: t) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
