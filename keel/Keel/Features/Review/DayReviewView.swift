import SwiftUI
import SwiftData
import UserNotifications

/// Which part of the day it is; Today reorders itself around this.
enum DayPhase {
    case morning, day, evening
    static var now: DayPhase {
        switch Calendar.current.component(.hour, from: Date()) {
        case ..<11: .morning
        case ..<18: .day
        default: .evening
        }
    }
}

/// Evening wind-down: what you finished, what carries over, tomorrow's first thing, then shut down.
struct DayReviewView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var tasks: [TaskItem]
    @Query private var sessions: [FocusSession]
    @Query private var logs: [HabitLog]
    @State private var carried = false
    @State private var firstThing: UUID?
    @State private var showRitual = false

    private let cal = Calendar.current
    private var doneToday: [TaskItem] {
        tasks.filter { ($0.completedAt.map { cal.isDateInToday($0) } ?? false) || ($0.lastCompletedOccurrence.map { cal.isDateInToday($0) } ?? false) }
    }
    private var leftToday: [TaskItem] {
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        return tasks.filter { !$0.isDone && ($0.dueDate ?? .distantFuture) < end }
    }
    private var focusMinutes: Int {
        sessions.filter { $0.endedAt.map { cal.isDateInToday($0) } ?? false }
            .reduce(0) { $0 + Int((($1.endedAt ?? $1.startedAt).timeIntervalSince($1.startedAt)) / 60) }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: DS.Space.l) {
                    stat("\(doneToday.count)", "done")
                    stat(focusMinutes >= 60 ? "\(focusMinutes / 60)h \(focusMinutes % 60)m" : "\(focusMinutes)m", "focused")
                    stat("\(logs.filter { cal.isDateInToday($0.day) }.count)", "habits")
                }
                .padding(.vertical, 6)
            }
            if !doneToday.isEmpty {
                Section("You did this 🎉") {
                    ForEach(doneToday) { t in Label(t.title, systemImage: "checkmark.circle.fill").foregroundStyle(DS.Palette.calm) }
                }
            }
            if !leftToday.isEmpty {
                Section {
                    ForEach(leftToday) { t in
                        Button { firstThing = t.id; Haptics.tap() } label: {
                            HStack {
                                Image(systemName: firstThing == t.id ? "star.fill" : "circle").foregroundStyle(firstThing == t.id ? .yellow : DS.Palette.inkSoft)
                                Text(t.title).foregroundStyle(DS.Palette.ink)
                            }
                        }
                    }
                    Button(carried ? "Moved to tomorrow" : "Move all to tomorrow, no guilt") {
                        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
                        for t in leftToday { TaskActions.reschedule(t, to: tomorrow) }
                        if let id = firstThing, let t = tasks.first(where: { $0.id == id }) {
                            t.priority = .high
                            t.dueDate = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
                            t.alertOffsetMinutes = 0
                            TaskAlerts.schedule(t)
                        }
                        withAnimation { carried = true }
                        Haptics.success()
                    }
                    .disabled(carried)
                } header: { Text("Still open") } footer: {
                    Text("Tap ☆ to pick tomorrow's first thing; it becomes a 9 AM high-priority task.")
                }
            }
            Section {
                Button { showRitual = true } label: { Label("Shut down for the day", systemImage: "moon.stars") }
            }
        }
        .navigationTitle("Day in review")
        .sheet(isPresented: $showRitual) { ShutdownRitualView() }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack {
            Text(value).font(DS.Font.title)
            Text(label).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }

    /// A gentle 8:30 PM nudge, every day (can be turned off in Settings → Notifications).
    static func scheduleReminder() {
        let c = UNMutableNotificationContent()
        c.title = "Day in review"
        c.body = "Two minutes to see what you did and set up tomorrow."
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "day.review", content: c,
            trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 20, minute: 30), repeats: true)))
    }
}
