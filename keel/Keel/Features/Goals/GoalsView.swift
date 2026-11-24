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
                            NavigationLink { LazyView(GoalDetailView(goal: g)) } label: { GoalCard(goal: g, tasks: tasks.filter { $0.goalId == g.id }) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Archive goal", systemImage: "archivebox") {
                                        withAnimation(DS.spring) { g.isArchived = true }
                                        Haptics.success()
                                        UndoCenter.shared.offer("Archived “\(g.title)”", undo: { withAnimation(DS.spring) { g.isArchived = false } })
                                    }
                                }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Goals")
        .toolbar { NavigationLink { LazyView(VisionBoardView()) } label: { Label("Vision board", systemImage: "photo.on.rectangle.angled") } }
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
        .background { PremiumSurface() }
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
                    BufferedTextField("Goal", text: $goal.title, axis: .vertical).font(DS.Font.title)
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
                BufferedTextField("Why does this matter to you?", text: $goal.why, axis: .vertical)
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
                ForEach(tasks) { t in NavigationLink { LazyView(TaskDetailView(task: t)) } label: { TaskRow(task: t, showList: false) } }
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

/// A SMART goal, step by step: Specific, Measurable, Achievable, Relevant, Time-bound. Type a rough idea and
/// "Make it SMART" fills the steps in with AI; then Keel can break it into a few first tasks linked to the goal.
struct NewGoalSheet: View {
    @State var area: LifeArea
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var idea = ""
    @State private var title = ""              // Specific
    @State private var measure = ""            // Measurable
    @State private var achievable = ""         // Achievable
    @State private var why = ""                // Relevant
    @State private var hasDate = true          // Time-bound
    @State private var date = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var emoji = "🎯"
    @State private var makeTasks = true
    @State private var working = false
    @State private var aiNote: String?

    private var done: Int { [title, measure, achievable, why].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count + (hasDate ? 1 : 0) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("A rough idea, e.g. get fitter", text: $idea, axis: .vertical)
                    Button { Task { await smartify() } } label: {
                        Label(working ? "Thinking…" : "Make it SMART", systemImage: "sparkles")
                    }.disabled(idea.trimmingCharacters(in: .whitespaces).isEmpty || working)
                    if let aiNote { Text(aiNote).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft) }
                    ProgressView(value: Double(done), total: 5) { Text("\(done) of 5 SMART steps").font(DS.Font.caption) }
                } footer: { Text("Or fill in each step yourself. A SMART goal is clear enough that you'll know when you've done it.") }
                Section {
                    HStack {
                        TextField("🎯", text: $emoji).frame(width: 44).font(.title)
                        TextField("Run a half marathon", text: $title)
                    }
                    Picker("Life area", selection: $area) { ForEach(LifeArea.allCases) { Label($0.title, systemImage: $0.icon).tag($0) } }
                } header: { Text("S · Specific") } footer: { Text("Exactly what you'll achieve.") }
                Section { TextField("e.g. finish 21 km in under 2 h 15", text: $measure, axis: .vertical) } header: { Text("M · Measurable") } footer: { Text("The number or sign that tells you it's done.") }
                Section { TextField("e.g. 3 runs a week, building 10% a week", text: $achievable, axis: .vertical) } header: { Text("A · Achievable") } footer: { Text("How you'll get there, and why it's realistic for you.") }
                Section { TextField("Because…", text: $why, axis: .vertical) } header: { Text("R · Relevant") } footer: { Text("Why it matters to you. Keel shows this when motivation dips.") }
                Section {
                    Toggle("By a date", isOn: $hasDate)
                    if hasDate { DatePicker("Target date", selection: $date, in: Date()..., displayedComponents: .date) }
                } header: { Text("T · Time-bound") }
                Section { Toggle("Create the first tasks for it", isOn: $makeTasks) } footer: { Text("AI suggests 3–5 first steps, linked to this goal so they count toward it.") }
            }
            .navigationTitle("New SMART goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    // Works with just the rough idea too: it becomes the goal's title.
                    Button("Add") { save() }.disabled(goalTitle.isEmpty || working)
                }
            }
        }
    }

    private func smartify() async {
        working = true; defer { working = false }
        let prompt = """
        Turn this rough goal into a SMART goal. Reply with exactly five lines, no extra text:
        SPECIFIC: <short goal title, under 8 words>
        MEASURABLE: <the measurable target>
        ACHIEVABLE: <how, realistically, e.g. weekly plan>
        RELEVANT: <why it could matter, one sentence>
        MONTHS: <number of months to give it, 1-24>
        Goal: \(idea)
        """
        aiNote = nil
        guard let out = await AIRouter.shared.write(prompt), !out.isEmpty else {
            // No AI on this device (or it didn't answer): still move forward instead of doing nothing.
            if title.isEmpty { title = String(idea.prefix(60)) }
            aiNote = "Apple Intelligence isn't available right now, so your idea is the goal's title. Fill in the steps below and tap Add."
            return
        }
        var filled = 0
        for line in out.split(whereSeparator: \.isNewline) {
            // Accepts "SPECIFIC: …", "**Specific:** …", "1. Specific - …" and similar.
            let clean = line.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "#", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t-•0123456789."))
            guard let sep = clean.firstIndex(where: { $0 == ":" || $0 == "–" || $0 == "-" }) else { continue }
            let key = clean[..<sep].trimmingCharacters(in: .whitespaces).uppercased()
            let value = clean[clean.index(after: sep)...].trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }
            if key.hasPrefix("SPECIFIC") || key == "S" { title = value; filled += 1 }
            else if key.hasPrefix("MEASURABLE") || key == "M" { measure = value; filled += 1 }
            else if key.hasPrefix("ACHIEVABLE") || key == "A" { achievable = value; filled += 1 }
            else if key.hasPrefix("RELEVANT") || key == "R" { if why.isEmpty { why = value }; filled += 1 }
            else if key.hasPrefix("MONTH") || key.hasPrefix("TIME") || key == "T" {
                if let m = Int(value.prefix { $0.isNumber || $0 == " " }.filter(\.isNumber)), m > 0 {
                    hasDate = true; date = Calendar.current.date(byAdding: .month, value: min(24, m), to: Date()) ?? date
                }
            }
        }
        if filled == 0 {
            if title.isEmpty { title = String(idea.prefix(60)) }
            aiNote = "Couldn't shape that one. Your idea is the title; fill in the steps below."
        } else {
            Haptics.success()
        }
    }

    private var goalTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? String(idea.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)) : t
    }

    private func save() {
        let g = Goal(title: goalTitle, area: area)
        // Kept in the goal's "why" so nothing about how goals are stored (and synced) changes.
        var lines = [why]
        if !measure.isEmpty { lines.append("Measure: \(measure)") }
        if !achievable.isEmpty { lines.append("Plan: \(achievable)") }
        g.why = lines.filter { !$0.isEmpty }.joined(separator: "\n")
        g.emoji = emoji.isEmpty ? "🎯" : String(emoji.prefix(2))
        g.targetDate = hasDate ? date : nil
        ctx.insert(g)
        try? ctx.save()
        Haptics.success()
        dismiss()                                 // the goal is saved now; first tasks follow a moment later
        guard makeTasks else { return }
        let ctx = ctx, goalId = g.id
        let prompt = "List 3 to 5 concrete first tasks (one per line, no numbering, under 10 words each) for this goal: \(goalTitle). Measure: \(measure). Plan: \(achievable)."
        Task { @MainActor in
            guard let out = await AIRouter.shared.write(prompt) else { return }
            let lines = out.split(whereSeparator: \.isNewline)
                .map { $0.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: CharacterSet(charactersIn: " -•0123456789.)")) }
                .filter { !$0.isEmpty && !$0.hasSuffix(":") }
            for line in lines.prefix(5) {
                let t = TaskItem(title: String(line.prefix(80)))
                t.goalId = goalId
                ctx.insert(t)
                try? CalendarService.shared.push(t)
            }
            try? ctx.save()
        }
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
                    NavigationLink { LazyView(GoalDetailView(goal: g)) } label: {
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
