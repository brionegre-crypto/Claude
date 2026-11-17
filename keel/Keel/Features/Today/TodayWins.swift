import SwiftUI
import SwiftData

// MARK: - Today's progress ring

/// "3 of 7" for today: tasks finished today against what's due today (overdue included).
struct TodayProgressRing: View {
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var open: [TaskItem]
    @Query private var done: [TaskItem]
    @AppStorage("custom.today.progress") private var on = true

    init() {
        var d = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isDone }, sortBy: [SortDescriptor(\.completedAt, order: .reverse)])
        d.fetchLimit = 80                          // today's finished tasks are always among the most recent
        _done = Query(d)
    }

    var body: some View {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        let finished = done.filter { $0.completedAt.map { cal.isDateInToday($0) } ?? false }.count
        let left = open.filter { ($0.dueDate ?? .distantFuture) < end }.count
        let total = finished + left
        if on && total > 0 {
            HStack(spacing: 8) {
                ZStack {
                    Circle().stroke(DS.Palette.calm.opacity(0.18), lineWidth: 4)
                    Circle().trim(from: 0, to: CGFloat(finished) / CGFloat(total))
                        .stroke(DS.Palette.calm.gradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(DS.spring, value: finished)
                    if left == 0 { Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(DS.Palette.calm) }
                }
                .frame(width: 22, height: 22)
                Text(left == 0 ? "All done today" : "\(finished) of \(total) done").font(DS.Font.caption.weight(.semibold))
                    .foregroundStyle(left == 0 ? DS.Palette.calm : DS.Palette.inkSoft).contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Pinned emails on Today

struct PinnedEmailsCard: View {
    @Query(filter: #Predicate<EmailMessage> { $0.isPinned && !$0.isArchived }, sort: \EmailMessage.receivedAt, order: .reverse) private var pinned: [EmailMessage]
    @AppStorage("custom.today.pinnedMail") private var on = true
    @State private var open: EmailMessage?

    var body: some View {
        if on && !pinned.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Pinned emails", systemImage: "pin.fill").font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft)
                ForEach(pinned.prefix(3)) { e in
                    Button { open = e } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "envelope.fill").foregroundStyle(DS.Palette.meeting)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(e.subject.isEmpty ? "(no subject)" : e.subject).font(DS.Font.body).foregroundStyle(DS.Palette.ink).lineLimit(1)
                                Text(e.fromName.isEmpty ? e.from : e.fromName).font(.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DS.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { PremiumSurface(tint: DS.Palette.meeting) }
            .sheet(item: $open) { e in NavigationStack { EmailDetailView(email: e) } }
        }
    }
}

// MARK: - Your week's wins, as a card to keep or share

struct WeeklyWinsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.displayScale) private var scale
    @State private var wins = WeeklyWins()

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.l) {
                WeeklyWinsCard(wins: wins)
                if let img = rendered {
                    ShareLink(item: Image(uiImage: img), preview: SharePreview("My week", image: Image(uiImage: img))) {
                        Label("Share my week", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                }
                Text("Small wins count. Looking back at them is one of the best ways to keep going.").font(.caption)
                    .foregroundStyle(DS.Palette.inkSoft).multilineTextAlignment(.center)
            }
            .padding()
        }
        .premiumBackground(DS.Palette.calm)
        .navigationTitle("This week's wins")
        .task { wins = WeeklyWins.compute(ctx) }
    }

    private var rendered: UIImage? {
        let r = ImageRenderer(content: WeeklyWinsCard(wins: wins).frame(width: 360).padding(12).background(Color.black))
        r.scale = scale
        return r.uiImage
    }
}

struct WeeklyWins {
    var tasks = 0
    var focusMinutes = 0
    var habits = 0
    var meals = 0
    var top: [String] = []

    @MainActor static func compute(_ ctx: ModelContext) -> WeeklyWins {
        let since = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        var w = WeeklyWins()
        let done = ((try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isDone }))) ?? [])
            .filter { ($0.completedAt ?? .distantPast) >= since }
            .sorted { $0.priority.rawValue > $1.priority.rawValue }
        w.tasks = done.count
        w.top = Array(done.prefix(5).map(\.title))
        let sessions = (try? ctx.fetch(FetchDescriptor<FocusSession>(predicate: #Predicate { $0.startedAt >= since }))) ?? []
        w.focusMinutes = sessions.reduce(0) { $0 + Int((($1.endedAt ?? $1.startedAt).timeIntervalSince($1.startedAt)) / 60) }
        w.habits = ((try? ctx.fetch(FetchDescriptor<HabitLog>(predicate: #Predicate { $0.day >= since }))) ?? []).count
        w.meals = ((try? ctx.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.date >= since }))) ?? []).count
        return w
    }
}

struct WeeklyWinsCard: View {
    let wins: WeeklyWins
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("My week").font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Text("⛵ Keel").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
            }
            HStack(spacing: 10) {
                stat("\(wins.tasks)", "things done")
                stat(wins.focusMinutes >= 60 ? "\(wins.focusMinutes / 60)h \(wins.focusMinutes % 60)m" : "\(wins.focusMinutes)m", "focused")
                stat("\(wins.habits)", "habits")
            }
            if !wins.top.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(wins.top, id: \.self) { t in
                        Label(t, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.white).lineLimit(1)
                    }
                }
            } else {
                Text("A quiet week. Rest is part of it.").foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [DS.Palette.calm, DS.Palette.accent, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(.white).monospacedDigit()
            Text(l).font(.caption).foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.15), in: .rect(cornerRadius: 14))
    }
}
