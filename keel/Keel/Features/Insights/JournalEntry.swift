import SwiftUI
import SwiftData
import UserNotifications

/// The 1-minute evening journal: how today felt, one prompt, one good thing. Saved with today's check-in.
struct JournalEntryView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CheckIn.day, order: .reverse) private var checkIns: [CheckIn]
    @State private var mood: Int?
    @State private var text = ""
    @State private var good = ""
    @State private var prompt = Journal.prompt()
    @State private var startedAt = Date()
    @FocusState private var writing: Bool

    private var today: CheckIn? { checkIns.first { Calendar.current.isDateInToday($0.day) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text("How did today feel?").font(DS.Font.headline)
                        HStack {
                            ForEach(1...5, id: \.self) { m in
                                Button { withAnimation(DS.spring) { mood = m }; Haptics.tap() } label: {
                                    Text(CheckIn.faces[m - 1]).font(.system(size: 34))
                                        .scaleEffect(mood == m ? 1.25 : 1).opacity(mood == nil || mood == m ? 1 : 0.4)
                                }
                                .buttonStyle(.plain).frame(maxWidth: .infinity)
                                .accessibilityLabel("Mood \(m) of 5")
                                .accessibilityAddTraits(mood == m ? .isSelected : [])
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        HStack {
                            Text(prompt).font(DS.Font.title)
                            Spacer()
                            Button { withAnimation { prompt = Journal.prompt(excluding: prompt) } } label: { Image(systemName: "shuffle") }
                                .accessibilityLabel("Different question")
                        }
                        TextEditor(text: $text)
                            .focused($writing)
                            .frame(minHeight: 140)
                            .scrollContentBackground(.hidden).padding(8)
                            .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.card))
                            .overlay(alignment: .topLeading) {
                                if text.isEmpty {
                                    Text("A sentence or two is plenty. Tap the mic on the keyboard to talk instead.")
                                        .font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft).padding(14).allowsHitTesting(false)
                                }
                            }
                        TimelineView(.periodic(from: startedAt, by: 1)) { tl in
                            let s = Int(tl.date.timeIntervalSince(startedAt))
                            ProgressView(value: Double(min(60, s)), total: 60) {
                                Text(s >= 60 ? "That's your minute. Write more if you like." : "\(60 - s)s").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                            }
                            .tint(s >= 60 ? DS.Palette.calm : DS.Palette.accent)
                        }
                    }

                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text("One good thing from today").font(DS.Font.headline)
                        TextField("Even tiny. Especially tiny.", text: $good).textFieldStyle(.roundedBorder)
                    }
                }
                .padding()
            }
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(mood == nil && text.isEmpty && good.isEmpty)
                }
            }
            .onAppear {
                if let t = today {
                    mood = t.mood
                    if !t.journal.isEmpty { text = t.journal; prompt = t.prompt.isEmpty ? prompt : t.prompt }
                    good = t.highlight
                }
                startedAt = Date()
            }
        }
    }

    private func save() {
        let c: CheckIn
        if let t = today { c = t } else {
            c = CheckIn(day: Calendar.current.startOfDay(for: Date()), mood: mood ?? 3)
            ctx.insert(c)
        }
        if let mood { c.mood = mood }
        c.journal = text.trimmingCharacters(in: .whitespacesAndNewlines)
        c.prompt = c.journal.isEmpty ? "" : prompt
        if !good.isEmpty { c.highlight = good }
        try? ctx.save()
        Haptics.success()
        dismiss()
    }
}

@MainActor
enum Journal {
    static let prompts = [
        "What took more energy than expected today?", "What gave you energy today?", "What are you glad you did?",
        "What's still on your mind?", "When did you feel most like yourself?", "What would make tomorrow 10% easier?",
        "What did you avoid, and why?", "Who made today better?", "What surprised you?", "What did you learn today?",
        "What can you let go of tonight?", "What went better than you feared?", "Where did your time actually go?",
        "What's one thing you handled well?", "How did your body feel today?", "What do you want to remember about today?",
    ]

    /// A different question each day, so it doesn't get stale.
    static func prompt(excluding current: String? = nil) -> String {
        if let current {
            return prompts.filter { $0 != current }.randomElement() ?? prompts[0]
        }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return prompts[day % prompts.count]
    }

    static let reminderOnKey = "journal.reminder.on"
    static let reminderTimeKey = "journal.reminder.minutes"
    /// Off by default: Day in Review already nudges each evening, and one evening ping is enough.
    static var reminderOn: Bool { UserDefaults.standard.object(forKey: reminderOnKey) as? Bool ?? false }
    static var reminderMinutes: Int { UserDefaults.standard.object(forKey: reminderTimeKey) as? Int ?? 21 * 60 }

    /// A nightly nudge to journal (one minute, then bed).
    static func scheduleReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["journal.nightly"])
        guard reminderOn else { return }
        let c = UNMutableNotificationContent()
        c.title = "One-minute journal"
        c.body = prompt()
        c.sound = .default
        c.userInfo = ["deeplink": "com.keel.app://journal"]
        let m = reminderMinutes
        center.add(UNNotificationRequest(identifier: "journal.nightly", content: c,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: m / 60, minute: m % 60), repeats: true)))
    }
}

/// Spots patterns between your mood and your days: sleep, meetings, meds, focus and getting things done.
@MainActor
enum MoodPatterns {
    struct Finding: Identifiable {
        let id = UUID()
        let icon: String
        let text: String
        let effect: Double
    }

    static func find(checkIns: [CheckIn], tasks: [TaskItem], sessions: [FocusSession], doses: [MedDose], hasMeds: Bool) -> [Finding] {
        let cal = Calendar.current
        var out: [Finding] = []

        func compare(_ icon: String, _ split: (CheckIn) -> Bool?, yes: String, no: String) {
            var a: [Int] = [], b: [Int] = []
            for c in checkIns {
                guard let v = split(c) else { continue }
                if v { a.append(c.mood) } else { b.append(c.mood) }
            }
            guard a.count >= 3, b.count >= 3 else { return }
            let ma = Double(a.reduce(0, +)) / Double(a.count), mb = Double(b.reduce(0, +)) / Double(b.count)
            let diff = ma - mb
            guard abs(diff) >= 0.4 else { return }
            let text = diff > 0
                ? "Your mood is \(String(format: "%.1f", diff)) points higher \(yes) than \(no)."
                : "Your mood is \(String(format: "%.1f", -diff)) points lower \(yes) than \(no)."
            out.append(Finding(icon: icon, text: text, effect: abs(diff)))
        }

        compare("bed.double.fill", { c in c.sleepHours.map { $0 >= 7 } }, yes: "after 7+ hours of sleep", no: "after less sleep")

        let meetingsByDay = Dictionary(checkIns.map { c -> (Date, Int) in
            let end = cal.date(byAdding: .day, value: 1, to: c.day) ?? c.day
            return (c.day, CalendarService.shared.events(from: c.day, to: end).filter { !$0.isAllDay && $0.attendees?.isEmpty == false }.count)
        }, uniquingKeysWith: { a, _ in a })
        compare("person.3.fill", { c in
            guard let n = meetingsByDay[c.day] else { return nil }
            return n >= 4 ? true : (n <= 1 ? false : nil)
        }, yes: "on days with 4+ meetings", no: "on light meeting days")

        if hasMeds {
            let medDays = Set(doses.map { cal.startOfDay(for: $0.day) })
            compare("pills.fill", { c in medDays.contains(c.day) }, yes: "on days you logged your meds", no: "on days you didn't")
        }

        let focusByDay = Dictionary(grouping: sessions.filter { $0.endedAt != nil }, by: { cal.startOfDay(for: $0.startedAt) })
            .mapValues { $0.reduce(0) { $0 + Int((($1.endedAt ?? $1.startedAt).timeIntervalSince($1.startedAt)) / 60) } }
        compare("moon.zzz.fill", { c in
            let m = focusByDay[c.day] ?? 0
            return m >= 45 ? true : (m < 15 ? false : nil)
        }, yes: "on days with 45+ minutes of focus", no: "on days with little focus")

        let doneByDay = Dictionary(grouping: tasks.compactMap { $0.completedAt }, by: { cal.startOfDay(for: $0) }).mapValues(\.count)
        compare("checkmark.circle.fill", { c in
            let n = doneByDay[c.day] ?? 0
            return n >= 3 ? true : (n <= 1 ? false : nil)
        }, yes: "on days you finish 3+ tasks", no: "on days you finish 0–1")

        return out.sorted { $0.effect > $1.effect }
    }
}

/// "Patterns" section for the Mood Journal.
struct MoodPatternsSection: View {
    let checkIns: [CheckIn]
    @Query private var tasks: [TaskItem]
    @Query private var sessions: [FocusSession]
    @Query private var doses: [MedDose]
    @Query private var meds: [Medication]
    @State private var findings: [MoodPatterns.Finding]?

    var body: some View {
        Section {
            if let findings {
                if findings.isEmpty {
                    Text(checkIns.count < 10 ? "Keep journaling. After about two weeks, Keel can spot what lifts or drains your mood."
                                             : "No strong patterns yet. Your mood looks steady across sleep, meetings and focus.")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                ForEach(findings) { f in
                    Label(f.text, systemImage: f.icon).font(DS.Font.body)
                }
            } else {
                ProgressView()
            }
        } header: { Text("Patterns") } footer: {
            Text("Patterns, not proof. They need at least 3 days on each side and stay on this iPhone.")
        }
        .task(id: checkIns.count) {
            findings = MoodPatterns.find(checkIns: checkIns, tasks: tasks, sessions: sessions, doses: doses, hasMeds: !meds.isEmpty)
        }
    }
}
