import SwiftUI
import SwiftData
import Observation

/// One running task timer at a time. It survives closing Keel; stopping it adds the minutes to
/// the task's actual time (which teaches Keel your real estimates) and logs it in the Time audit.
@MainActor @Observable
final class TaskTimer {
    static let shared = TaskTimer()
    private(set) var taskId: UUID?
    private(set) var startedAt: Date?

    init() {
        if let s = UserDefaults.standard.string(forKey: "timer.taskId") { taskId = UUID(uuidString: s) }
        let t = UserDefaults.standard.double(forKey: "timer.start")
        startedAt = t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    func isRunning(_ t: TaskItem) -> Bool { taskId == t.id }

    func start(_ t: TaskItem, ctx: ModelContext) {
        if taskId != nil { stop(ctx: ctx) }
        taskId = t.id
        startedAt = Date()
        UserDefaults.standard.set(t.id.uuidString, forKey: "timer.taskId")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "timer.start")
        if t.stage == "todo" { t.stage = "doing" }
        Haptics.tap()
    }

    func stop(ctx: ModelContext) {
        guard let id = taskId, let start = startedAt else { return }
        let minutes = max(1, Int(Date().timeIntervalSince(start) / 60))
        if let t = try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first {
            t.actualMinutes = (t.actualMinutes ?? 0) + minutes
            let entry = TimeEntry(title: t.title, area: .work, start: start, end: Date())
            entry.source = "task"
            ctx.insert(entry)
        }
        taskId = nil; startedAt = nil
        UserDefaults.standard.removeObject(forKey: "timer.taskId")
        UserDefaults.standard.removeObject(forKey: "timer.start")
        try? ctx.save()
        Haptics.success()
    }
}

struct TaskTimerSection: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var ctx
    @State private var timer = TaskTimer.shared

    var body: some View {
        Section {
            HStack {
                if timer.isRunning(task), let start = timer.startedAt {
                    Image(systemName: "stopwatch.fill").foregroundStyle(DS.Palette.accent)
                    Text(timerInterval: start...Date.distantFuture, countsDown: false).monospacedDigit().font(DS.Font.headline)
                    Spacer()
                    Button("Stop") { timer.stop(ctx: ctx) }.buttonStyle(.borderedProminent).tint(DS.Palette.warmth)
                } else {
                    Image(systemName: "stopwatch").foregroundStyle(DS.Palette.inkSoft)
                    VStack(alignment: .leading) {
                        Text("Time spent")
                        Text(spentLabel).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                    Spacer()
                    Button("Start") { timer.start(task, ctx: ctx) }.buttonStyle(.bordered).tint(DS.Palette.accent)
                }
            }
        } footer: {
            if let est = task.estimatedMinutes, let actual = task.actualMinutes, actual > 0 {
                Text("Estimated \(est) min, actually \(actual) min. Keel uses this to plan more realistically.")
            }
        }
    }

    private var spentLabel: String {
        guard let m = task.actualMinutes, m > 0 else { return "Not tracked yet" }
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m) min"
    }
}
