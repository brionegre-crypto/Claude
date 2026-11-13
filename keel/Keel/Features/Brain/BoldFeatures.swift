import SwiftUI
import SwiftData
import EventKit
import Photos
import HealthKit
import AppIntents
import UserNotifications
import UniformTypeIdentifiers

// MARK: - 1. Keel works while you sleep

struct AgentItem: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case draft, filed, meeting, plan, followUp, digest }
    var id = UUID()
    var kind: Kind
    var title: String
    var detail: String
    var ref: String?            // email id, note id…
    var undo: String?           // filed: the previous folder
    var approved: Bool = false
}

/// Runs once a night (first chance after midnight, or when you first open Keel in the morning). Does the prep work and
/// leaves a short "done for you" list. It never sends anything or deletes anything on its own.
@MainActor
enum OvernightAgent {
    static let lastKey = "agent.last", itemsKey = "agent.items", onKey = "agent.on"
    static var isOn: Bool { UserDefaults.standard.object(forKey: onKey) as? Bool ?? true }
    static var items: [AgentItem] {
        get { UserDefaults.standard.data(forKey: itemsKey).flatMap { try? JSONDecoder().decode([AgentItem].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: itemsKey) }
    }
    private static var running = false

    static func runIfDue(ctx: ModelContext) {
        guard isOn, !running else { return }
        let cal = Calendar.current
        let last = UserDefaults.standard.object(forKey: lastKey) as? Date ?? .distantPast
        guard !cal.isDateInToday(last), cal.component(.hour, from: Date()) < 12 || last < Date().addingTimeInterval(-30 * 3600) else { return }
        running = true
        UserDefaults.standard.set(Date(), forKey: lastKey)
        Task { await run(ctx: ctx); running = false }
    }

    static func run(ctx: ModelContext) async {
        var out: [AgentItem] = []
        let accounts = (try? ctx.fetch(FetchDescriptor<MailAccount>())) ?? []
        // Replies for real people who wrote overnight.
        var md = FetchDescriptor<EmailMessage>(predicate: #Predicate { !$0.isRead && !$0.isArchived }, sortBy: [SortDescriptor(\.receivedAt, order: .reverse)])
        md.fetchLimit = 60
        let unread = (try? ctx.fetch(md)) ?? []
        let mine = Set(accounts.map { $0.address.lowercased() })
        for e in unread.filter({ AutoDrafts.needsReply($0, mine: mine) }).prefix(6) {
            if AutoDrafts.draft(for: e.id) == nil, let d = await AIRouter.shared.draftReply(to: e, intent: "Write the reply I'd most likely send, in my voice. Use [brackets] for anything only I know.") {
                AutoDrafts.setDraft(e.id, d)
            }
            if AutoDrafts.has(e.id) { out.append(AgentItem(kind: .draft, title: "Reply ready for \(e.fromName.isEmpty ? e.from : e.fromName)", detail: e.subject, ref: e.id)) }
        }
        // File the capture inbox.
        let notes = (try? ctx.fetch(FetchDescriptor<Note>())) ?? []
        let pending = notes.filter(CaptureInbox.isPending)
        if !pending.isEmpty {
            let picks = await NotesOrganizer.propose(for: Array(pending.prefix(15)), all: notes, allowNew: true) { _, _ in }
            for p in picks {
                guard let n = notes.first(where: { $0.id == p.id }) else { continue }
                out.append(AgentItem(kind: .filed, title: "Filed “\(n.title.isEmpty ? "Untitled" : n.title)”", detail: "into \(p.folder.replacingOccurrences(of: "/", with: " › "))", ref: n.id.uuidString, undo: n.folder ?? ""))
                n.folder = p.folder
                CaptureInbox.done(n)
            }
        }
        // Prep today's meetings.
        let events = CalendarService.shared.todaysEvents().filter { !$0.isAllDay && MeetingAutopilot.isMeeting($0) && $0.endDate > Date() }
        for e in events.prefix(5) {
            let pack = MeetingPrep.build(e, ctx: ctx)
            guard !pack.isEmpty else { continue }
            var bits: [String] = []
            if !pack.emails.isEmpty { bits.append("\(pack.emails.count) recent emails") }
            if !pack.notes.isEmpty { bits.append("\(pack.notes.count) notes") }
            if !pack.promises.isEmpty { bits.append("\(pack.promises.count) promises you made") }
            out.append(AgentItem(kind: .meeting, title: "Prepped \(e.title ?? "a meeting") at \(e.startDate.formatted(date: .omitted, time: .shortened))", detail: bits.joined(separator: " · "), ref: e.calendarItemIdentifier))
        }
        // Who owes you a reply.
        let follow = ((try? ctx.fetch(FetchDescriptor<FollowUp>())) ?? []).filter { $0.resolvedAt == nil && $0.remindAt <= Date() }
        if !follow.isEmpty { out.append(AgentItem(kind: .followUp, title: "\(follow.count) people haven't replied", detail: follow.prefix(3).map { $0.recipientName.isEmpty ? $0.recipient : $0.recipientName }.joined(separator: ", "))) }
        // A plan for the day.
        out.append(AgentItem(kind: .plan, title: "Your day is ready to plan", detail: "\(events.count) meetings · \(((try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? []).filter { ($0.dueDate ?? .distantFuture) < Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400) }.count) tasks due"))
        BrainIndex.shared.refresh(ctx: ctx, force: true)
        try? ctx.save()
        items = out
    }
}

struct DoneForYouView: View {
    @Environment(\.modelContext) private var ctx
    @State private var items = OvernightAgent.items
    @State private var working = false

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView("Nothing yet", systemImage: "moon.stars", description: Text("Overnight, Keel drafts replies, files your captures, preps meetings and gets your day ready. Check back in the morning, or run it now."))
            }
            ForEach($items) { $it in
                HStack(alignment: .top, spacing: DS.Space.m) {
                    Image(systemName: icon(it.kind)).foregroundStyle(DS.Palette.accent).frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(it.title).font(DS.Font.headline).strikethrough(it.approved)
                        Text(it.detail).font(.caption).foregroundStyle(DS.Palette.inkSoft)
                        HStack {
                            switch it.kind {
                            case .draft:
                                if let id = it.ref, let e = try? ctx.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { $0.id == id })).first {
                                    NavigationLink("Review & send") { EmailDetailView(email: e) }
                                }
                            case .filed:
                                Button("Undo") { undo(it) }
                            case .meeting:
                                Button("Open Calendar") { AppRouter.shared.tab = .calendar }
                            case .plan:
                                Button("Plan my day") { AppRouter.shared.showPlan = true }
                            case .followUp:
                                NavigationLink("See who") { FollowUpsView() }
                            case .digest:
                                EmptyView()
                            }
                            Spacer()
                            if !it.approved { Button("Looks good") { it.approved = true; OvernightAgent.items = items; Haptics.tap() } }
                        }
                        .font(.caption).buttonStyle(.borderless).padding(.top, 2)
                    }
                }
            }
            Section {
                Button(working ? "Working…" : "Run it now", systemImage: "wand.and.stars") {
                    Task { working = true; await OvernightAgent.run(ctx: ctx); items = OvernightAgent.items; working = false }
                }
                .disabled(working)
                Toggle("Do this every night", isOn: Binding(get: { OvernightAgent.isOn }, set: { UserDefaults.standard.set($0, forKey: OvernightAgent.onKey) }))
            } footer: { Text("Keel never sends, deletes or accepts anything on its own. Drafts wait for you; filing can be undone.") }
        }
        .navigationTitle("Done for you")
    }

    private func icon(_ k: AgentItem.Kind) -> String {
        switch k { case .draft: "pencil.line"; case .filed: "tray.and.arrow.down"; case .meeting: "person.2"; case .plan: "list.bullet.clipboard"; case .followUp: "bubble.left.and.exclamationmark.bubble.right"; case .digest: "doc.text" }
    }
    private func undo(_ it: AgentItem) {
        guard let id = it.ref.flatMap(UUID.init(uuidString:)), let n = try? ctx.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })).first else { return }
        n.folder = (it.undo ?? "").isEmpty ? nil : it.undo
        n.props[CaptureInbox.flag] = "1"
        items.removeAll { $0.id == it.id }; OvernightAgent.items = items
    }
}

// MARK: - 2. Your life on one timeline

struct LifeMoment: Identifiable {
    let id: String
    let date: Date
    let kind: String            // mail | sent | event | note | task | photo | workout | journal
    let title: String
    let detail: String
    var noteId: UUID?
    var emailId: String?
    var assetId: String?
}

@MainActor
enum LifeTimeline {
    static func moments(month: Date, ctx: ModelContext, photos: Bool, workouts: [HKWorkout]) -> [LifeMoment] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        let (s, e) = (interval.start, interval.end)
        var out: [LifeMoment] = []
        let mail = (try? ctx.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { $0.receivedAt >= s && $0.receivedAt < e }))) ?? []
        for m in mail where !MailNoise.isAutomated(m) && m.unsubscribeHeader == nil {
            out.append(LifeMoment(id: "m" + m.id, date: m.receivedAt, kind: "mail", title: m.fromName.isEmpty ? m.from : m.fromName, detail: m.subject, emailId: m.id))
        }
        for ev in CalendarService.shared.events(from: s, to: e) where !ev.isAllDay {
            out.append(LifeMoment(id: "e" + (ev.calendarItemIdentifier) + "\(ev.startDate.timeIntervalSince1970)", date: ev.startDate, kind: "event", title: ev.title ?? "Event", detail: ev.location ?? ""))
        }
        for n in (try? ctx.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.createdAt >= s && $0.createdAt < e }))) ?? [] where !n.isTemplate && !n.isLocked {
            out.append(LifeMoment(id: "n" + n.id.uuidString, date: n.createdAt, kind: "note", title: n.title.isEmpty ? "Untitled" : n.title, detail: String(n.plainText.prefix(80)), noteId: n.id))
        }
        for t in (try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isDone }))) ?? [] {
            if let d = t.completedAt, d >= s, d < e { out.append(LifeMoment(id: "t" + t.id.uuidString, date: d, kind: "task", title: t.title, detail: "Done")) }
        }
        for c in (try? ctx.fetch(FetchDescriptor<CheckIn>(predicate: #Predicate { $0.day >= s && $0.day < e }))) ?? [] where !c.highlight.isEmpty {
            out.append(LifeMoment(id: "j" + c.id.uuidString, date: c.day.addingTimeInterval(20 * 3600), kind: "journal", title: ["", "😞", "🙁", "😐", "🙂", "😄"][max(0, min(5, c.mood))] + " " + c.highlight, detail: c.gratitude))
        }
        for w in workouts where w.startDate >= s && w.startDate < e {
            out.append(LifeMoment(id: "w" + w.uuid.uuidString, date: w.startDate, kind: "workout", title: w.workoutActivityType.keelName, detail: "\(Int(w.duration / 60)) min"))
        }
        if photos, PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized || PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited {
            let o = PHFetchOptions()
            o.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", s as NSDate, e as NSDate)
            o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let r = PHAsset.fetchAssets(with: .image, options: o)
            // One photo per day keeps the timeline readable.
            var days = Set<Date>()
            r.enumerateObjects { a, _, _ in
                guard let d = a.creationDate, days.insert(cal.startOfDay(for: d)).inserted else { return }
                out.append(LifeMoment(id: "p" + a.localIdentifier, date: d, kind: "photo", title: "Photos", detail: a.location.map { _ in "with location" } ?? "", assetId: a.localIdentifier))
            }
        }
        return out.sorted { $0.date > $1.date }
    }
}

extension HKWorkoutActivityType {
    var keelName: String {
        switch self {
        case .running: "Run"; case .walking: "Walk"; case .cycling: "Ride"; case .swimming: "Swim"; case .yoga: "Yoga"; case .hiking: "Hike"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Strength training"; case .highIntensityIntervalTraining: "HIIT"
        default: "Workout"
        }
    }
}

struct LifeTimelineView: View {
    @Environment(\.modelContext) private var ctx
    @State private var month = Date()
    @State private var moments: [LifeMoment] = []
    @State private var search = ""
    @State private var photos = PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
    @State private var workouts: [HKWorkout] = []
    @State private var loading = false

    var body: some View {
        let shown = search.isEmpty ? moments : moments.filter { ($0.title + " " + $0.detail).localizedCaseInsensitiveContains(search) }
        let days = Dictionary(grouping: shown) { Calendar.current.startOfDay(for: $0.date) }
        List {
            Section {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(month.formatted(.dateTime.month(.wide).year())).font(DS.Font.headline)
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }.disabled(Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month))
                }
                .buttonStyle(.borderless)
                if !photos {
                    Button("Include photos", systemImage: "photo.on.rectangle") {
                        Task { photos = await PHPhotoLibrary.requestAuthorization(for: .readWrite) != .denied; await load() }
                    }
                }
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
            ForEach(days.keys.sorted(by: >), id: \.self) { day in
                Section(day.formatted(.dateTime.weekday(.wide).month().day())) {
                    ForEach(days[day] ?? []) { m in row(m) }
                }
            }
        }
        .searchable(text: $search, prompt: "Search this month")
        .navigationTitle("Life timeline")
        .task(id: month) { await load() }
    }

    @ViewBuilder private func row(_ m: LifeMoment) -> some View {
        let label = HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(m.kind)).foregroundStyle(color(m.kind)).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.title).lineLimit(2)
                if !m.detail.isEmpty { Text(m.detail).font(.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2) }
            }
            Spacer()
            Text(m.date.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
        }
        if let id = m.noteId, let n = try? ctx.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })).first {
            NavigationLink { NoteOrCanvas(note: n) } label: { label }
        } else if let id = m.emailId, let e = try? ctx.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { $0.id == id })).first {
            NavigationLink { EmailDetailView(email: e) } label: { label }
        } else {
            label
        }
    }

    private func icon(_ k: String) -> String {
        ["mail": "envelope", "event": "calendar", "note": "doc.text", "task": "checkmark.circle", "photo": "photo", "workout": "figure.run", "journal": "book"][k] ?? "circle"
    }
    private func color(_ k: String) -> Color {
        ["mail": .blue, "event": .red, "note": .orange, "task": .green, "photo": .pink, "workout": .mint, "journal": .purple][k] ?? .gray
    }
    private func shift(_ n: Int) { month = Calendar.current.date(byAdding: .month, value: n, to: month) ?? month }

    private func load() async {
        loading = true; defer { loading = false }
        workouts = await Self.fetchWorkouts(month)
        moments = LifeTimeline.moments(month: month, ctx: ctx, photos: photos, workouts: workouts)
    }

    static func fetchWorkouts(_ month: Date) async -> [HKWorkout] {
        guard HKHealthStore.isHealthDataAvailable(), let interval = Calendar.current.dateInterval(of: .month, for: month) else { return [] }
        let store = HKHealthStore()
        try? await store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType()])
        let pred = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
        let d = HKSampleQueryDescriptor(predicates: [.workout(pred)], sortDescriptors: [SortDescriptor(\.startDate)], limit: 200)
        return (try? await d.result(for: store)) ?? []
    }
}

// MARK: - 3. A coach that knows your goals

@MainActor
enum Coach {
    static let lastKey = "coach.last", textKey = "coach.text"
    static var latest: String? { UserDefaults.standard.string(forKey: textKey) }

    static func checkIn(ctx: ModelContext) async -> String {
        let since = Date().addingTimeInterval(-7 * 86_400)
        let goals = ((try? ctx.fetch(FetchDescriptor<Goal>())) ?? []).map { "\($0.emoji) \($0.title)\($0.why.isEmpty ? "" : " (why: \($0.why))")" }
        let tasks = (try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []
        let done = tasks.filter { ($0.completedAt ?? .distantPast) > since }.map(\.title)
        let overdue = tasks.filter { !$0.isDone && ($0.dueDate ?? .distantFuture) < since }.map(\.title)
        let checkins = ((try? ctx.fetch(FetchDescriptor<CheckIn>())) ?? []).filter { $0.day > since }
        let mood = checkins.isEmpty ? "no check-ins" : String(format: "average mood %.1f/5", Double(checkins.map(\.mood).reduce(0, +)) / Double(checkins.count))
        let energy = checkins.compactMap(\.energy)
        let focus = ((try? ctx.fetch(FetchDescriptor<FocusSession>())) ?? []).filter { $0.startedAt > since }
            .reduce(0) { $0 + Int((($1.endedAt ?? $1.startedAt).timeIntervalSince($1.startedAt)) / 60) }
        let habits = ((try? ctx.fetch(FetchDescriptor<HabitLog>())) ?? []).filter { $0.completedAt > since }.count
        let meetings = CalendarService.shared.events(from: since, to: Date()).filter { !$0.isAllDay && MeetingAutopilot.isMeeting($0) }
        let meetingHours = meetings.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 3600
        let about = KeelMemory.shared.facts.suffix(10).joined(separator: "; ")
        let prompt = """
        You're my warm, honest coach (I have ADHD; be kind but direct, no fluff). Using this past week, write a short check-in with exactly three parts:
        1. Moving you forward: what actually advanced my goals (be specific).
        2. Quietly draining you: a pattern that's costing me, said honestly.
        3. One change to try this week: one small, concrete experiment.
        Keep it under 140 words.

        MY GOALS: \(goals.isEmpty ? "none set" : goals.joined(separator: "; "))
        ABOUT ME: \(about)
        DONE THIS WEEK (\(done.count)): \(done.prefix(15).joined(separator: "; "))
        OVERDUE: \(overdue.prefix(8).joined(separator: "; "))
        FOCUS: \(focus) minutes · HABIT CHECK-INS: \(habits) · MEETINGS: \(String(format: "%.1f", meetingHours)) hours
        MOOD: \(mood)\(energy.isEmpty ? "" : " · energy average \(String(format: "%.1f", Double(energy.reduce(0, +)) / Double(energy.count)))/3")
        """
        let r = await AIRouter.shared.write(prompt) ?? "Not enough to go on yet. Set a goal or two, check in a few times this week, and I'll have something useful for you."
        UserDefaults.standard.set(r, forKey: textKey)
        UserDefaults.standard.set(Date(), forKey: lastKey)
        return r
    }
}

struct CoachView: View {
    @Environment(\.modelContext) private var ctx
    @State private var text = Coach.latest
    @State private var working = false
    @State private var newValue = ""
    @Query private var goals: [Goal]

    var body: some View {
        List {
            Section {
                if let text { Text(text).textSelection(.enabled) } else { Text("Your first check-in is one tap away.").foregroundStyle(DS.Palette.inkSoft) }
                Button(working ? "Thinking…" : "Check in now", systemImage: "figure.mind.and.body") {
                    Task { working = true; text = await Coach.checkIn(ctx: ctx); working = false }
                }
                .disabled(working)
            } header: { Text("This week") } footer: { Text("Every Sunday Keel looks at your goals, what you finished, focus, habits, meetings and mood, and gives you one honest check-in.") }
            Section("Your goals") {
                ForEach(goals) { g in Text("\(g.emoji) \(g.title)") }
                NavigationLink("Edit goals") { GoalsView() }
            }
            Section {
                ForEach(KeelMemory.shared.facts.filter { $0.hasPrefix("I value ") }, id: \.self) { Text($0) }
                HStack {
                    TextField("e.g. time with my kids", text: $newValue)
                    Button("Add") { KeelMemory.shared.add("I value \(newValue)"); newValue = "" }.disabled(newValue.isEmpty)
                }
            } header: { Text("What matters to you") } footer: { Text("Keel keeps these in mind when it plans your days and coaches you.") }
        }
        .navigationTitle("Coach")
    }
}

// MARK: - 4. Talk to Keel all day, hands-free

struct TalkToKeelIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to Keel"
    static let description: IntentDescription = "Hands-free conversation: ask what's next, add things, hear your important email."
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult { AppRouter.shared.openTool = ToolRoute(id: "talk"); return .result() }
}

struct ReadImportantMailIntent: AppIntent {
    static let title: LocalizedStringResource = "Read My Important Email"
    static let description: IntentDescription = "Hear who needs you and what they said, briefly."
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        var d = FetchDescriptor<EmailMessage>(predicate: #Predicate { !$0.isRead && !$0.isArchived }, sortBy: [SortDescriptor(\.receivedAt, order: .reverse)])
        d.fetchLimit = 40
        let mail = ((try? KeelStore.container.mainContext.fetch(d)) ?? []).filter { AutoDrafts.isRealPerson($0) && ($0.category == .important || $0.category == .actionable) }.prefix(3)
        guard !mail.isEmpty else { return .result(dialog: "Nothing important waiting. You're clear.") }
        let lines = mail.map { e in "From \(e.fromName.isEmpty ? e.from : e.fromName): \(e.subject). \(e.aiSummary ?? String(e.snippet.prefix(140)))" }
        return .result(dialog: "\(lines.joined(separator: " Next. "))")
    }
}

// MARK: - 6. Shared brains (family or team spaces through your Keel server)

struct SpaceRef: Codable, Identifiable, Hashable { var id: String; var name: String; var url: String }
struct SharedPageInfo: Codable, Identifiable, Hashable { var id: String; var title: String }
struct SpaceData: Codable { var name: String; var pages: [SharedPageInfo]; var lists: [SharedListRef]; var members: [String] }
struct SharedPageData: Codable { var title: String; var blocks: [NoteBlock]; var version: Int; var viewers: [String] }

@MainActor
enum Spaces {
    static let key = "spaces"
    static var all: [SpaceRef] {
        get { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([SpaceRef].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    static func create(_ name: String) async throws -> SpaceRef {
        let d = try await KeelCloud.call("space", method: "POST", body: ["name": name, "by": SharedLists.myName], auth: true)
        let j = try JSONSerialization.jsonObject(with: d) as? [String: Any]
        guard let id = j?["id"] as? String, let url = j?["url"] as? String else { throw KeelCloud.Failure.http(500) }
        let r = SpaceRef(id: id, name: name, url: url)
        all = [r] + all.filter { $0.id != id }
        return r
    }
    static func join(_ link: String) -> SpaceRef? {
        guard let id = link.split(separator: "/").last.map(String.init), id.count == 32 else { return nil }
        let r = SpaceRef(id: id, name: "Shared space", url: link)
        all = [r] + all.filter { $0.id != id }
        return r
    }
    static func load(_ id: String) async throws -> SpaceData {
        try JSONDecoder().decode(SpaceData.self, from: try await KeelCloud.call("space/\(id)"))
    }
    static func addPage(space: String, title: String, blocks: [NoteBlock]) async throws -> String {
        let body: [String: Any] = ["title": title, "blocks": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(blocks))) ?? [], "by": SharedLists.myName]
        let d = try await KeelCloud.call("space/\(space)/page", method: "POST", body: body)
        return ((try JSONSerialization.jsonObject(with: d) as? [String: Any])?["id"] as? String) ?? ""
    }
    static func addList(space: String, list: SharedListRef) async throws {
        _ = try await KeelCloud.call("space/\(space)/list", method: "POST", body: ["id": list.id, "title": list.title, "url": list.url])
    }
    static func page(_ id: String) async throws -> SharedPageData {
        _ = try? await KeelCloud.call("spage/\(id)/here", method: "POST", body: ["by": SharedLists.myName])   // who's here now
        return try JSONDecoder().decode(SharedPageData.self, from: try await KeelCloud.call("spage/\(id)"))
    }
    /// Saves your version; if someone else saved in between, their new lines are kept and yours win where you both edited.
    static func save(_ id: String, title: String, blocks: [NoteBlock], base: Int) async throws -> SharedPageData {
        let body: [String: Any] = ["title": title, "blocks": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(blocks))) ?? [], "base": base, "by": SharedLists.myName]
        return try JSONDecoder().decode(SharedPageData.self, from: try await KeelCloud.call("spage/\(id)", method: "PUT", body: body))
    }
}

struct SpacesView: View {
    @State private var spaces = Spaces.all
    @State private var name = ""
    @State private var link = ""
    @State private var error: String?
    var body: some View {
        List {
            Section {
                ForEach(spaces) { s in NavigationLink { SpaceView(space: s) } label: { Label(s.name, systemImage: "person.3.fill") } }
                    .onDelete { spaces.remove(atOffsets: $0); Spaces.all = spaces }
                HStack {
                    TextField("New space, e.g. Family", text: $name)
                    Button("Create") { Task { do { _ = try await Spaces.create(name); name = ""; spaces = Spaces.all } catch { self.error = error.localizedDescription } } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: { Text("A space is a shared brain for your family or team: pages you edit together and shared lists. Your own notes stay private; only what you put in a space is shared.") }
            Section("Join a space") {
                HStack {
                    TextField("Paste an invite link", text: $link).textInputAutocapitalization(.never)
                    Button("Join") { if Spaces.join(link) != nil { link = ""; spaces = Spaces.all } else { error = "That doesn't look like a Keel space link." } }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .navigationTitle("Shared spaces")
    }
}

struct SpaceView: View {
    let space: SpaceRef
    @State private var data: SpaceData?
    @State private var newPage = ""
    @State private var error: String?
    @State private var sharing: Note?
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var pickPage = false

    var body: some View {
        List {
            if let d = data {
                Section("Pages") {
                    ForEach(d.pages) { p in NavigationLink { SharedPageView(pageId: p.id, title: p.title) } label: { Label(p.title, systemImage: "doc.text") } }
                    HStack {
                        TextField("New shared page", text: $newPage)
                        Button("Add") { Task { _ = try? await Spaces.addPage(space: space.id, title: newPage, blocks: [NoteBlock(kind: .text, text: "")]); newPage = ""; await refresh() } }
                            .disabled(newPage.isEmpty)
                    }
                    Button("Share one of my pages here", systemImage: "square.and.arrow.up.on.square") { pickPage = true }
                }
                Section("Lists") {
                    ForEach(d.lists) { l in NavigationLink { SharedListView(ref: l) } label: { Label(l.title, systemImage: "checklist") } }
                }
                if !d.members.isEmpty { Section("People in this space") { ForEach(d.members, id: \.self) { Text($0) } } }
            } else if let error { Text(error).foregroundStyle(.red) } else { ProgressView() }
        }
        .navigationTitle(data?.name ?? space.name)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { if let u = URL(string: space.url) { ShareLink(item: u) { Image(systemName: "person.badge.plus") } } } }
        .task { await refresh() }
        .refreshable { await refresh() }
        .sheet(isPresented: $pickPage) {
            PagePickerSheet(title: "Share a page", exclude: nil) { n in
                Task { _ = try? await Spaces.addPage(space: space.id, title: n.title, blocks: n.blocks); await refresh() }
            }
        }
    }
    private func refresh() async {
        do {
            let d = try await Spaces.load(space.id)
            data = d
            if d.name != space.name { Spaces.all = Spaces.all.map { $0.id == space.id ? SpaceRef(id: $0.id, name: d.name, url: $0.url) : $0 } }
        } catch { self.error = error.localizedDescription }
    }
}

/// Edit a page together: changes sync every few seconds, and you see who else is here.
struct SharedPageView: View {
    let pageId: String
    let title: String
    @State private var blocks: [NoteBlock] = []
    @State private var pageTitle = ""
    @State private var version = 0
    @State private var viewers: [String] = []
    @State private var dirty = false
    @State private var error: String?
    private let tick = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            if !viewers.isEmpty {
                Label("Here now: \(viewers.joined(separator: ", "))", systemImage: "person.2.wave.2.fill").font(.caption).foregroundStyle(DS.Palette.accent)
            }
            TextField("Title", text: $pageTitle).font(DS.Font.title).onChange(of: pageTitle) { dirty = true }
            ForEach($blocks) { $b in
                HStack(alignment: .firstTextBaseline) {
                    if b.kind == .todo { Button { b.checked.toggle(); dirty = true } label: { Image(systemName: b.checked ? "checkmark.square.fill" : "square") }.buttonStyle(.plain) }
                    if b.kind == .bullet { Text("•") }
                    TextField("Write…", text: $b.text, axis: .vertical)
                        .font(b.kind == .heading || b.kind == .heading2 ? DS.Font.headline : DS.Font.body)
                        .onChange(of: b.text) { dirty = true }
                }
            }
            .onDelete { blocks.remove(atOffsets: $0); dirty = true }
            HStack {
                Button("Text") { blocks.append(NoteBlock(kind: .text, text: "")); dirty = true }
                Button("To-do") { blocks.append(NoteBlock(kind: .todo, text: "")); dirty = true }
                Button("Bullet") { blocks.append(NoteBlock(kind: .bullet, text: "")); dirty = true }
                Button("Heading") { blocks.append(NoteBlock(kind: .heading2, text: "")); dirty = true }
            }
            .buttonStyle(.bordered).font(.caption)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .navigationTitle(pageTitle.isEmpty ? title : pageTitle).navigationBarTitleDisplayMode(.inline)
        .task { await pull(force: true) }
        .onReceive(tick) { _ in Task { if dirty { await push() } else { await pull(force: false) } } }
        .onDisappear { if dirty { Task { await push() } } }
    }

    private func pull(force: Bool) async {
        guard let p = try? await Spaces.page(pageId) else { if force { error = "Couldn't open this page right now." }; return }
        viewers = p.viewers.filter { $0 != SharedLists.myName }
        if force || p.version != version { blocks = p.blocks; pageTitle = p.title; version = p.version }
    }
    private func push() async {
        dirty = false
        if let p = try? await Spaces.save(pageId, title: pageTitle, blocks: blocks, base: version) {
            version = p.version
            if p.blocks.map(\.id) != blocks.map(\.id) { blocks = p.blocks }       // someone else added lines meanwhile
            viewers = p.viewers.filter { $0 != SharedLists.myName }
        }
    }
}

extension Coach {
    /// Sunday from 10 AM: this week's check-in, once.
    static func weeklyIfDue(ctx: ModelContext) {
        let cal = Calendar.current
        guard cal.component(.weekday, from: Date()) == 1, cal.component(.hour, from: Date()) >= 10 else { return }
        let last = UserDefaults.standard.object(forKey: lastKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 5 * 86_400 else { return }
        Task {
            _ = await checkIn(ctx: ctx)
            let c = UNMutableNotificationContent()
            c.title = "Your weekly check-in"
            c.body = "What moved you forward, what's draining you, and one thing to try."
            c.userInfo = ["deeplink": "com.keel.app://tool/coach"]
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "coach.weekly", content: c, trigger: nil))
        }
    }
}

struct ReadingImportView: View {
    @Environment(\.modelContext) private var ctx
    @State private var picking = false
    @State private var message: String?
    var body: some View {
        Form {
            Section {
                Button("Choose the export file", systemImage: "doc.badge.plus") { picking = true }
                if let message { Text(message).foregroundStyle(DS.Palette.inkSoft) }
            } footer: {
                Text("Pocket: getpocket.com/export. Instapaper: Settings → Export → CSV. Highlights come along when the file includes them. Everything lands in Read Later; open any article in Keel's reader to keep highlighting.")
            }
        }
        .navigationTitle("Import reading list")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText, .html]) { r in
            guard case .success(let url) = r else { return }
            let n = url.pathExtension.lowercased() == "html" ? PocketHTML.run(url, ctx: ctx) : ReadingImport.run(url, ctx: ctx)
            message = n == 0 ? "Nothing new found in that file." : "Added \(n) article\(n == 1 ? "" : "s") to Read Later."
        }
    }
}

/// Pocket's classic export is an HTML list of links.
@MainActor
enum PocketHTML {
    static func run(_ url: URL, ctx: ModelContext) -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let html = try? String(contentsOf: url, encoding: .utf8), let re = try? NSRegularExpression(pattern: "<a href=\"([^\"]+)\"[^>]*>([^<]*)</a>", options: .caseInsensitive) else { return 0 }
        let have = Set(((try? ctx.fetch(FetchDescriptor<SavedLink>())) ?? []).map(\.url))
        let ns = html as NSString
        var n = 0
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let u = ns.substring(with: m.range(at: 1))
            guard u.hasPrefix("http"), !have.contains(u) else { continue }
            ctx.insert(SavedLink(url: u, title: ReaderStore.decode(ns.substring(with: m.range(at: 2)))))
            n += 1
        }
        try? ctx.save()
        return n
    }
}
