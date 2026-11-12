import SwiftUI
import SwiftData
import FoundationModels

/// The Sunday AI recap: what you finished, what slipped and why, who you owe replies to,
/// and a suggested plan for next week that you approve in one tap.
@MainActor
enum WeeklyRecap {
    struct Slip: Identifiable {
        let task: TaskItem
        let reason: String
        var id: UUID { task.id }
    }

    struct Owed: Identifiable {
        let id: String
        let name: String
        let what: String
        let since: Date
    }

    struct PlanItem: Identifiable {
        let task: TaskItem
        var day: Date
        var isTop: Bool
        var id: UUID { task.id }
    }

    static func weekStart(_ now: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: now)) ?? now
    }

    static func finished(_ tasks: [TaskItem], since start: Date) -> [TaskItem] {
        tasks.filter { ($0.completedAt ?? .distantPast) >= start || ($0.lastCompletedOccurrence ?? .distantPast) >= start }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    /// Due this week (or earlier) and still open, with the most likely reason it slipped.
    static func slipped(_ tasks: [TaskItem]) -> [Slip] {
        let today = Calendar.current.startOfDay(for: Date())
        let open = tasks.filter { !$0.isDone && !$0.isSomeday }
        return open.filter { ($0.dueDate ?? .distantFuture) < today }
            .sorted { $0.timesRescheduled > $1.timesRescheduled }
            .prefix(12)
            .map { t in Slip(task: t, reason: reason(t, all: open)) }
    }

    static func reason(_ t: TaskItem, all: [TaskItem]) -> String {
        if let b = t.blockedById, all.contains(where: { $0.id == b }) { return "Waiting on another task first" }
        if t.isWaitingOn { return "Waiting on someone else" }
        if t.timesRescheduled >= 3 { return "Moved \(t.timesRescheduled) times. Too big, or not really yours?" }
        if t.microSteps.isEmpty && (t.estimatedMinutes ?? 0) >= 60 { return "Big with no first step" }
        if t.energy == .high { return "Needs high energy" }
        return "No time was set aside for it"
    }

    /// People waiting on you: emails from real people over 2 days old, and promises you made.
    static func owed(mail: [EmailMessage], promises: [Commitment], accounts: [MailAccount]) -> [Owed] {
        let mine = Set(accounts.map { $0.address.lowercased() })
        let cutoff = Date().addingTimeInterval(-2 * 86_400)
        let emails = mail.filter { MailNoise.needsYou($0, myAddresses: mine) && $0.receivedAt < cutoff }
            .prefix(8)
            .map { Owed(id: $0.id, name: $0.fromName.isEmpty ? $0.from : $0.fromName, what: "Reply: \($0.subject)", since: $0.receivedAt) }
        let promised = promises.filter { $0.status == .open }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(6)
            .map { Owed(id: $0.id, name: $0.recipientName.isEmpty ? $0.recipient : $0.recipientName, what: "You promised: \($0.promise)", since: $0.sentAt) }
        return Array(emails) + Array(promised)
    }

    /// Next week's weekdays, Monday to Friday.
    static func nextWeekdays(from now: Date = Date()) -> [Date] {
        let cal = Calendar.current
        var monday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        while cal.component(.weekday, from: monday) != 2 { monday = cal.date(byAdding: .day, value: 1, to: monday) ?? monday }
        return (0..<5).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }

    /// Slipped work first, then what's due next week, then important undated tasks. At most 3 a day.
    static func plan(tasks: [TaskItem], slipped: [Slip], top: [String]) -> [PlanItem] {
        let days = nextWeekdays()
        guard !days.isEmpty else { return [] }
        let horizon = Calendar.current.date(byAdding: .day, value: 1, to: days.last!) ?? days.last!
        let open = tasks.filter { !$0.isDone && !$0.isSomeday && !$0.isWaitingOn }
        var picked: [TaskItem] = slipped.map(\.task).filter { s in open.contains { $0.id == s.id } }
        picked += open.filter { t in (t.dueDate.map { $0 >= days[0] && $0 < horizon } ?? false) && !picked.contains { $0.id == t.id } }
        picked += open.filter { t in t.dueDate == nil && t.priority == .high && !picked.contains { $0.id == t.id } }
        picked = Array(picked.prefix(12))
        let topSet = Set(top.map { $0.lowercased() })
        // Top three first, then high priority, so they land early in the week.
        picked.sort { a, b in
            let ta = topSet.contains(a.title.lowercased()), tb = topSet.contains(b.title.lowercased())
            if ta != tb { return ta }
            return a.priority.rawValue > b.priority.rawValue
        }
        var out: [PlanItem] = []
        var perDay = [Int](repeating: 0, count: days.count)
        for t in picked {
            // Keep a task on its own day if it's already due next week; otherwise the lightest day.
            var idx = days.firstIndex { Calendar.current.isDate($0, inSameDayAs: t.dueDate ?? .distantPast) }
                ?? perDay.enumerated().min { $0.element < $1.element }!.offset
            if perDay[idx] >= 3, let lighter = perDay.enumerated().first(where: { $0.element < 3 })?.offset { idx = lighter }
            perDay[idx] += 1
            out.append(PlanItem(task: t, day: days[idx], isTop: topSet.contains(t.title.lowercased())))
        }
        return out.sorted { $0.day < $1.day }
    }

    /// Applies the plan: due dates move to the planned day (keeping any time), and the top three are pinned.
    static func apply(_ plan: [PlanItem], ctx: ModelContext) {
        let cal = Calendar.current
        for p in plan {
            let t = p.task
            if let d = t.dueDate, t.hasDueTime {
                let c = cal.dateComponents([.hour, .minute], from: d)
                t.dueDate = cal.date(bySettingHour: c.hour ?? 9, minute: c.minute ?? 0, second: 0, of: p.day)
            } else {
                t.dueDate = p.day
            }
            if p.isTop { t.isPinned = true }
            t.updatedAt = Date()
            TaskAlerts.schedule(t)
        }
        try? ctx.save()
        UserDefaults.standard.set(Date(), forKey: "recap.appliedAt")
    }

    // MARK: AI

    @Generable
    struct Insight {
        @Guide(description: "Exactly three task titles, copied exactly from the list, that matter most next week")
        var topThree: [String]
        @Guide(description: "One kind, specific sentence about why things slipped this week and what to try next week")
        var pattern: String
    }

    static func insight(finished: [TaskItem], slipped: [Slip], candidates: [TaskItem]) async -> (top: [String], pattern: String) {
        let fallbackTop = candidates.sorted { $0.priority.rawValue > $1.priority.rawValue }.prefix(3).map(\.title)
        let commonReason = Dictionary(grouping: slipped, by: \.reason).max { $0.value.count < $1.value.count }?.key
        let fallback = slipped.isEmpty ? "Nothing slipped this week. Keep the same rhythm."
            : "Most slips were “\(commonReason ?? "no time set aside")”. Next week, give each top task a time on your calendar."
        guard AIRouter.shared.onDeviceAvailable, !candidates.isEmpty else { return (Array(fallbackTop), fallback) }
        let session = LanguageModelSession(instructions: "You help someone with ADHD plan their week kindly and realistically.\n" + KeelMemory.shared.context)
        let prompt = """
        Finished this week: \(finished.prefix(15).map(\.title).joined(separator: "; "))
        Slipped (with likely reason): \(slipped.prefix(10).map { "\($0.task.title) — \($0.reason)" }.joined(separator: "; "))
        Candidates for next week: \(candidates.prefix(20).map(\.title).joined(separator: "; "))
        """
        guard let r = try? await session.respond(to: prompt, generating: Insight.self).content else { return (Array(fallbackTop), fallback) }
        let titles = Set(candidates.map { $0.title.lowercased() })
        let top = r.topThree.filter { titles.contains($0.lowercased()) }
        return (top.isEmpty ? Array(fallbackTop) : Array(top.prefix(3)), r.pattern.isEmpty ? fallback : r.pattern)
    }
}

/// The recap card at the top of Weekly review.
struct WeeklyRecapSection: View {
    @Environment(\.modelContext) private var ctx
    @Query private var tasks: [TaskItem]
    @Query(filter: #Predicate<EmailMessage> { !$0.isArchived }) private var mail: [EmailMessage]
    @Query private var promises: [Commitment]
    @Query private var accounts: [MailAccount]
    @State private var plan: [WeeklyRecap.PlanItem] = []
    @State private var pattern: String?
    @State private var thinking = false
    @State private var applied = false
    @State private var showAllDone = false

    var body: some View {
        let start = WeeklyRecap.weekStart()
        let done = WeeklyRecap.finished(tasks, since: start)
        let slips = WeeklyRecap.slipped(tasks)
        let owed = WeeklyRecap.owed(mail: mail, promises: promises, accounts: accounts)
        GlassCard(tint: DS.Palette.calm) {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Label("Your week, recapped", systemImage: "sparkles").font(DS.Font.headline)

                group("Finished", "checkmark.circle.fill", DS.Palette.calm, done.isEmpty ? "Nothing ticked off, and that's OK. Rest weeks count." : "\(done.count) things done") {
                    ForEach(done.prefix(showAllDone ? 30 : 4)) { t in bullet(t.title) }
                    if done.count > 4 && !showAllDone { Button("Show all \(done.count)") { showAllDone = true }.font(DS.Font.caption) }
                }

                if !slips.isEmpty {
                    group("Slipped", "arrow.uturn.right.circle.fill", DS.Palette.warmth, "\(slips.count) moved past their date") {
                        ForEach(slips.prefix(5)) { s in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.task.title).font(DS.Font.body).lineLimit(1)
                                Text(s.reason).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                            }
                        }
                        if let pattern { Label(pattern, systemImage: "lightbulb.fill").font(DS.Font.caption).foregroundStyle(DS.Palette.ink) }
                    }
                }

                if !owed.isEmpty {
                    group("People waiting on you", "person.2.fill", .pink, "\(owed.count) waiting") {
                        ForEach(owed.prefix(6)) { o in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(o.name).font(DS.Font.body.weight(.semibold)).lineLimit(1)
                                Text("\(o.what) · \(o.since.formatted(.relative(presentation: .named)))")
                                    .font(.caption2).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                            }
                        }
                    }
                }

                Divider()
                planSection(slips: slips, done: done)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func planSection(slips: [WeeklyRecap.Slip], done: [TaskItem]) -> some View {
        Label("Next week", systemImage: "calendar.badge.checkmark").font(DS.Font.headline)
        if applied {
            Label("Plan applied. Your top three are pinned on Today.", systemImage: "checkmark.seal.fill")
                .font(DS.Font.body).foregroundStyle(DS.Palette.calm)
        } else if plan.isEmpty {
            Button(thinking ? "Planning…" : "Suggest a plan") { Task { await suggest(slips: slips, done: done) } }
                .buttonStyle(.borderedProminent).tint(DS.Palette.calm).disabled(thinking)
        } else {
            let days = Dictionary(grouping: plan, by: { Calendar.current.startOfDay(for: $0.day) })
            ForEach(days.keys.sorted(), id: \.self) { d in
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.formatted(.dateTime.weekday(.wide))).font(DS.Font.caption.weight(.semibold)).foregroundStyle(DS.Palette.inkSoft)
                    ForEach(days[d] ?? []) { p in
                        HStack(spacing: 6) {
                            Image(systemName: p.isTop ? "star.fill" : "circle").font(.caption2)
                                .foregroundStyle(p.isTop ? .yellow : DS.Palette.inkSoft)
                            Text(p.task.title).font(DS.Font.body).lineLimit(1)
                        }
                    }
                }
            }
            HStack {
                Button { WeeklyRecap.apply(plan, ctx: ctx); withAnimation { applied = true }; Haptics.milestone() } label: {
                    Label("Approve plan", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(DS.Palette.calm)
                Button("Not now") { plan = [] }.buttonStyle(.bordered)
            }
            Text("Approving moves these to their days and pins the ★ top three to Today. Nothing else changes.")
                .font(.caption2).foregroundStyle(DS.Palette.inkSoft)
        }
    }

    private func suggest(slips: [WeeklyRecap.Slip], done: [TaskItem]) async {
        thinking = true; defer { thinking = false }
        let candidates = WeeklyRecap.plan(tasks: tasks, slipped: slips, top: []).map(\.task)
        let r = await WeeklyRecap.insight(finished: done, slipped: slips, candidates: candidates)
        pattern = r.pattern
        withAnimation { plan = WeeklyRecap.plan(tasks: tasks, slipped: slips, top: r.top) }
        if plan.isEmpty { pattern = (pattern ?? "") + " Nothing is scheduled for next week yet, so you start with a clean slate." }
    }

    private func group<C: View>(_ title: String, _ icon: String, _ color: Color, _ subtitle: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: icon).font(DS.Font.body.weight(.semibold)).foregroundStyle(color)
                Spacer()
                Text(subtitle).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
            }
            content()
        }
    }

    private func bullet(_ text: String) -> some View {
        Text("• " + text).font(DS.Font.body).lineLimit(1)
    }
}
