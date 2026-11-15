import SwiftUI

// MARK: - How long a task takes: quick choices, fine-tuning, and the default for new tasks

enum TaskDuration {
    static let presets = [5, 10, 15, 25, 30, 45, 60, 90, 120]

    static func label(_ m: Int) -> String {
        m >= 60 ? (m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min") : "\(m) min"
    }

    /// Small steps for short tasks, bigger ones for long tasks.
    static func step(up m: Int) -> Int { m < 15 ? m + 1 : m < 60 ? m + 5 : m + 15 }
    static func step(down m: Int) -> Int { m <= 15 ? m - 1 : m <= 60 ? m - 5 : m - 15 }
}

/// In a task's details: tap a length, or use − / + to fine-tune. Shows when Keel pads it from what it's learned.
struct TaskDurationEditor: View {
    @Bindable var task: TaskItem

    var body: some View {
        let m = ADHDCoach.minutes(task)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Duration", systemImage: "clock")
                Spacer()
                Button { set(max(1, TaskDuration.step(down: m))) } label: { Image(systemName: "minus.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(DS.Palette.accent).disabled(m <= 1)
                    .accessibilityLabel("Shorter")
                Text(TaskDuration.label(m)).font(.body.weight(.semibold)).monospacedDigit().frame(minWidth: 70)
                    .contentTransition(.numericText())
                Button { set(min(600, TaskDuration.step(up: m))) } label: { Image(systemName: "plus.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(DS.Palette.accent)
                    .accessibilityLabel("Longer")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(TaskDuration.presets, id: \.self) { p in
                        Button(TaskDuration.label(p)) { set(p) }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(p == m ? AnyShapeStyle(DS.Palette.accent) : AnyShapeStyle(DS.Palette.accent.opacity(0.12)), in: Capsule())
                            .foregroundStyle(p == m ? Color.white : DS.Palette.accent)
                            .buttonStyle(.plain)
                    }
                }
            }
            if task.estimatedMinutes == nil {
                Text("Using your default (\(TaskDuration.label(ADHDCoach.defaultMinutes))). Change it in Settings → Tasks.")
                    .font(.caption2).foregroundStyle(DS.Palette.inkSoft)
            } else if ADHDCoach.calibratedMinutes(task) != m {
                Text("From the tasks you've timed, this usually takes you about \(TaskDuration.label(ADHDCoach.calibratedMinutes(task))). Keel plans with that.")
                    .font(.caption2).foregroundStyle(DS.Palette.inkSoft)
            }
        }
    }

    private func set(_ m: Int) {
        withAnimation(.snappy) { task.estimatedMinutes = m }
        task.updatedAt = Date()
        Haptics.tap()
    }
}

/// Settings → Tasks: the default length and whether Keel pads times from what it has learned.
struct TaskDurationSettings: View {
    @AppStorage(ADHDCoach.defaultMinutesKey) private var defaultMinutes = 5
    @AppStorage(ADHDCoach.padKey) private var pad = true

    var body: some View {
        Section {
            Stepper("Default length: \(TaskDuration.label(defaultMinutes))",
                    onIncrement: { defaultMinutes = min(240, TaskDuration.step(up: defaultMinutes)) },
                    onDecrement: { defaultMinutes = max(1, TaskDuration.step(down: defaultMinutes)) })
            Toggle("Pad times from what I've timed", isOn: $pad)
        } header: { Text("Task length") } footer: {
            Text("Tasks without their own length count as \(TaskDuration.label(defaultMinutes)). When you time tasks with Start now, Keel learns whether things take you longer than planned and, if padding is on, plans with the real time. It only starts after 3 timed tasks.")
        }
    }
}
