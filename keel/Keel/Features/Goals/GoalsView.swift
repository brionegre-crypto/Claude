import SwiftUI
import SwiftData
import PhotosUI

/// Ali Abdaal-style direction: a theme for the year, a few goals per life area, and tasks that move them forward.
struct GoalsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<Goal> { !$0.isArchived }, sort: \Goal.createdAt) private var goals: [Goal]
    @Query private var tasks: [TaskItem]
    @AppStorage("year.theme") private var theme = ""
    @State private var newGoalArea: LifeArea?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                GlassCard(tint: DS.Palette.accent) {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text("THEME OF THE YEAR").font(DS.Font.caption).foregroundStyle(DS.Palette.accent)
                        TextField("e.g. Year of Health, Year of Less", text: $theme)
                            .font(DS.Font.title)
                        Text("A theme is a direction, not a finish line. It guides choices when goals feel fuzzy.")
                            .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
                ForEach(LifeArea.allCases) { area in
                    let areaGoals = goals.filter { $0.area == area }
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        HStack {
                            Label(area.title, systemImage: area.icon).font(DS.Font.headline)
                            Spacer()
                            Button { newGoalArea = area } label: { Image(systemName: "plus.circle") }
                                .accessibilityLabel("Add a \(area.title) goal")
                        }
                        if areaGoals.isEmpty {
                            Button { newGoalArea = area } label: {
                                Text("Add a \(area.title.lowercased()) goal").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(DS.Space.m)
                                    .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.chip))
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(areaGoals) { g in
                            NavigationLink { GoalDetailView(goal: g) } label: { GoalCard(goal: g, tasks: tasks.filter { $0.goalId == g.id }) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Goals")
        .toolbar { NavigationLink { VisionBoardView() } label: { Label("Vision board", systemImage: "photo.on.rectangle.angled") } }
        .sheet(item: $newGoalArea) { NewGoalSheet(area: $0) }
    }
}

struct GoalCard: View {
    let goal: Goal
    let tasks: [TaskItem]
    private var done: Int { tasks.filter { $0.isDone }.count + tasks.reduce(0) { $0 + $1.completionCount } }
    private var total: Int { tasks.count + tasks.reduce(0) { $0 + $1.completionCount } }
    private var progress: Double { total == 0 ? 0 : Double(done) / Double(total) }

    var body: some View {
        HStack(spacing: DS.Space.m) {
            ZStack {
                TimeRing(progress: progress, color: DS.Palette.calm, lineWidth: 5).frame(width: 46, height: 46)
                Text(goal.emoji).font(.title3)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(goal.title).font(DS.Font.headline).foregroundStyle(DS.Palette.ink)
                if !goal.why.isEmpty {
                    Text(goal.why).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text("\(done)/\(total) done").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    if let d = goal.targetDate { Chip(text: d.formatted(.dateTime.month(.abbreviated).day()), color: DS.Palette.focus, icon: "flag") }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(DS.Palette.inkSoft)
        }
        .padding(DS.Space.m)
        .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.card))
    }
}

struct GoalDetailView: View {
    @Bindable var goal: Goal
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var allTasks: [TaskItem]
    @State private var newTask = ""
    @State private var photo: PhotosPickerItem?

    private var tasks: [TaskItem] { allTasks.filter { $0.goalId == goal.id }.sorted { !$0.isDone && $1.isDone } }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("🎯", text: $goal.emoji).frame(width: 44).font(.title)
                    TextField("Goal", text: $goal.title, axis: .vertical).font(DS.Font.title)
                }
                Picker("Life area", selection: $goal.area) {
                    ForEach(LifeArea.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                }
                Toggle("Target date", isOn: Binding(get: { goal.targetDate != nil },
                                                    set: { goal.targetDate = $0 ? Calendar.current.date(byAdding: .month, value: 3, to: Date()) : nil }))
                if goal.targetDate != nil {
                    DatePicker("By", selection: Binding(get: { goal.targetDate ?? Date() }, set: { goal.targetDate = $0 }), displayedComponents: .date)
                }
            }
            Section {
                TextField("Why does this matter to you?", text: $goal.why, axis: .vertical)
            } header: { Text("Why") } footer: { Text("Keel shows this on the goal's tasks when motivation dips.") }
            Section {
                if let data = goal.visionImage, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFill().frame(height: 180).clipShape(.rect(cornerRadius: 12))
                        .listRowInsets(EdgeInsets())
                }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label(goal.visionImage == nil ? "Add a picture" : "Change picture", systemImage: "photo")
                }
                if goal.visionImage != nil { Button("Remove picture", role: .destructive) { goal.visionImage = nil } }
            } header: { Text("Vision") } footer: { Text("A picture of what it looks like when you get there. It appears on your vision board.") }
                .onChange(of: photo) { _, item in
                    Task {
                        if let d = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                            goal.visionImage = img.jpegData(compressionQuality: 0.75)
                        }
                        photo = nil
                    }
                }
            Section("Tasks") {
                ForEach(tasks) { t in NavigationLink { TaskDetailView(task: t) } label: { TaskRow(task: t, showList: false) } }
                HStack {
                    Image(systemName: "plus.circle.fill").foregroundStyle(DS.Palette.accent)
                    TextField("Add a task for this goal", text: $newTask).onSubmit {
                        guard !newTask.isEmpty else { return }
                        QuickAdd.create(newTask, in: ctx).goalId = goal.id
                        newTask = ""
                    }
                }
            }
            Section {
                Button("Archive goal", role: .destructive) { goal.isArchived = true; dismiss() }
            }
        }
        .navigationTitle(goal.area.title)
    }
}

struct NewGoalSheet: View {
    @State var area: LifeArea
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var why = ""
    @State private var emoji = "🎯"

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    TextField("🎯", text: $emoji).frame(width: 44).font(.title)
                    TextField("e.g. Run a half marathon", text: $title)
                }
                Picker("Life area", selection: $area) { ForEach(LifeArea.allCases) { Label($0.title, systemImage: $0.icon).tag($0) } }
                Section("Why it matters") { TextField("Because…", text: $why, axis: .vertical) }
            }
            .navigationTitle("New goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let g = Goal(title: title, area: area)
                        g.why = why; g.emoji = emoji.isEmpty ? "🎯" : String(emoji.prefix(2))
                        ctx.insert(g)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Every goal's picture in one inspiring grid, with its why.
struct VisionBoardView: View {
    @Query(filter: #Predicate<Goal> { !$0.isArchived }, sort: \Goal.createdAt) private var goals: [Goal]
    @AppStorage("year.theme") private var theme = ""

    var body: some View {
        ScrollView {
            if !theme.isEmpty {
                Text(theme).font(.system(.largeTitle, design: .serif).italic()).frame(maxWidth: .infinity).padding(.top)
            }
            let withPictures = goals.filter { $0.visionImage != nil }
            if withPictures.isEmpty {
                ContentUnavailableView("Your vision board is empty", systemImage: "photo.on.rectangle.angled",
                                       description: Text("Open a goal and add a picture of what achieving it looks like."))
            }
            FlexGrid(columns: 2, spacing: 8) {
                ForEach(withPictures) { g in
                    NavigationLink { GoalDetailView(goal: g) } label: {
                        ZStack(alignment: .bottomLeading) {
                            if let img = UIImage(data: g.visionImage!) {
                                Image(uiImage: img).resizable().scaledToFill().frame(height: 200).clipped()
                            }
                            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(g.emoji) \(g.title)").font(DS.Font.headline).foregroundStyle(.white).lineLimit(2)
                                if !g.why.isEmpty { Text(g.why).font(.caption2).foregroundStyle(.white.opacity(0.85)).lineLimit(2) }
                            }
                            .padding(8)
                        }
                        .frame(height: 200)
                        .clipShape(.rect(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle("Vision Board")
    }
}
