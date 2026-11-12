import SwiftUI
import SwiftData

/// Kanban board for a list: To do → Doing → Done. Drag cards between columns.
struct BoardView: View {
    let tasks: [TaskItem]          // open + done tasks for the current list/filter
    private let stages: [(key: String, title: String, color: Color)] = [
        ("todo", "To do", DS.Palette.inkSoft), ("doing", "Doing", DS.Palette.accent), ("done", "Done", DS.Palette.calm),
    ]

    private func items(_ stage: String) -> [TaskItem] {
        switch stage {
        case "done": tasks.filter(\.isDone).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }.prefix(20).map { $0 }
        case "doing": tasks.filter { !$0.isDone && $0.stage == "doing" }
        default: tasks.filter { !$0.isDone && $0.stage != "doing" }
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.Space.m) {
                ForEach(stages, id: \.key) { stage in
                    let list = items(stage.key)
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        HStack {
                            Circle().fill(stage.color).frame(width: 8, height: 8)
                            Text(stage.title).font(DS.Font.headline)
                            Text("\(list.count)").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        ScrollView {
                            VStack(spacing: DS.Space.s) {
                                ForEach(list) { t in
                                    NavigationLink { TaskDetailView(task: t) } label: { BoardCard(task: t) }
                                        .buttonStyle(.plain)
                                        .draggable(t.id.uuidString)
                                }
                                Color.clear.frame(height: 60)   // room to drop at the bottom
                            }
                        }
                    }
                    .padding(DS.Space.s)
                    .frame(width: 280)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(DS.Palette.elevated.opacity(0.6), in: .rect(cornerRadius: DS.Radius.card))
                    .dropDestination(for: String.self) { ids, _ in
                        for id in ids { move(id, to: stage.key) }
                        return true
                    }
                }
            }
            .padding()
        }
    }

    private func move(_ id: String, to stage: String) {
        guard let t = tasks.first(where: { $0.id.uuidString == id }) else { return }
        if stage == "done" {
            if !t.isDone { TaskActions.setDone(t, true) }
        } else {
            if t.isDone { TaskActions.setDone(t, false) }
            t.stage = stage
            t.updatedAt = Date()
            Haptics.tap()
        }
    }
}

struct BoardCard: View {
    let task: TaskItem
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title).font(DS.Font.body).foregroundStyle(task.isDone ? DS.Palette.inkSoft : DS.Palette.ink)
                .strikethrough(task.isDone).lineLimit(3)
            HStack(spacing: 6) {
                if task.priority != .none { Image(systemName: "flag.fill").foregroundStyle(task.priority.color) }
                if let d = task.dueDate { Text(d, format: .dateTime.month(.abbreviated).day()) }
                if !task.microSteps.isEmpty { Text("\(task.microSteps.filter(\.done).count)/\(task.microSteps.count)") }
                ForEach(task.tags.prefix(2), id: \.self) { Text("#\($0)").foregroundStyle(DS.Palette.accent) }
            }
            .font(.caption2).foregroundStyle(DS.Palette.inkSoft)
        }
        .padding(DS.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.canvas, in: .rect(cornerRadius: 10))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
}

/// Lists shared in Apple Reminders sync to Keel automatically; sharing itself happens in Reminders.
struct ShareListSheet: View {
    let listName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Image(systemName: "person.2.fill").font(.system(size: 40)).foregroundStyle(DS.Palette.accent)
                Text("Share “\(listName)”").font(DS.Font.title)
                Text("Keel lists are Apple Reminders lists, so sharing works the Apple way: share the list in Reminders and everyone you invite sees the same tasks, live, here in Keel and on their own devices.")
                    .font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
                VStack(alignment: .leading, spacing: 6) {
                    Label("Open Reminders", systemImage: "1.circle.fill")
                    Label("Long-press “\(listName)” → Share List", systemImage: "2.circle.fill")
                    Label("Invite your partner, family or team", systemImage: "3.circle.fill")
                }
                .font(DS.Font.body)
                Spacer()
                Button {
                    if let url = URL(string: "x-apple-reminderkit://") { openURL(url) }
                } label: {
                    Text("Open Reminders").font(DS.Font.headline).frame(maxWidth: .infinity).padding(.vertical, DS.Space.m)
                        .background(DS.Palette.accent, in: Capsule()).foregroundStyle(.white)
                }
            }
            .padding()
            .toolbar { Button("Done") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }
}
