import SwiftUI
import SwiftData
import EventKit
import UserNotifications

// MARK: - One capture button everywhere

enum CaptureKind: String, CaseIterable, Identifiable {
    case task, event, note, reminder
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String { switch self { case .task: "checklist"; case .event: "calendar"; case .note: "doc.text"; case .reminder: "bell" } }
}

enum CaptureClassifier {
    /// What you most likely meant: a meeting-ish phrase with a time is an event, "remind me" a reminder,
    /// long or multi-line text a note, anything else a task.
    static func guess(_ text: String) -> CaptureKind {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let low = t.lowercased()
        if low.hasPrefix("note:") || low.hasPrefix("idea:") || t.contains("\n") || t.count > 160 { return .note }
        if low.hasPrefix("remind me") || low.hasPrefix("reminder:") { return .reminder }
        let eventWords = ["meeting", "lunch with", "dinner with", "coffee with", "call with", "appointment", "interview", "party", "flight", "dentist", "doctor", "standup", "1:1", "zoom with"]
        let hasTime = low.range(of: #"\b(\d{1,2})(:\d{2})?\s?(am|pm)\b|\bat \d{1,2}\b|\b(noon|tonight|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#, options: .regularExpression) != nil
        if hasTime && eventWords.contains(where: { low.contains($0) }) { return .event }
        return .task
    }
}

struct UniversalCaptureSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var kind: CaptureKind = .task
    @State private var touchedKind = false
    @State private var voice = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                TextField("Anything on your mind…", text: $text, axis: .vertical)
                    .font(.title3).lineLimit(1...8).focused($focused)
                    .onChange(of: text) { if !touchedKind { kind = CaptureClassifier.guess(text) } }
                Picker("It's a", selection: Binding(get: { kind }, set: { kind = $0; touchedKind = true })) {
                    ForEach(CaptureKind.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(hint).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                HStack {
                    Button { voice = true } label: { Label("Talk", systemImage: "mic.fill") }.buttonStyle(.bordered)
                    Button {
                        if let s = UIPasteboard.general.string { text = s }
                    } label: { Label("Paste", systemImage: "doc.on.clipboard") }.buttonStyle(.bordered)
                    Spacer()
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                Spacer()
            }
            .padding()
            .navigationTitle("Capture").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(text.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .sheet(isPresented: $voice) { VoiceNoteView() }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private var hint: String {
        switch kind {
        case .task: "Goes to Tasks. Dates and repeats are understood: “call mom friday 5pm”."
        case .event: "Goes on your calendar: “lunch with Sam tomorrow 1pm for 90 min”."
        case .note: "Lands in your capture inbox to file later (or Keel files it overnight)."
        case .reminder: "A reminder that alerts you: “remind me to water plants every other Sunday”."
        }
    }

    private func save() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .task, .reminder:
            let task = QuickAdd.create(t, in: ctx)
            if kind == .reminder, task.dueDate == nil { task.dueDate = Date().addingTimeInterval(3600) }
            UndoCenter.shared.notify("Added “\(task.title)”")
        case .event:
            do {
                if let p = try QuickEvent.create(t) { UndoCenter.shared.notify("Added \(p.title) on \(p.start.formatted(date: .abbreviated, time: .shortened))") }
                else { _ = QuickAdd.create(t, in: ctx); UndoCenter.shared.notify("Couldn't read a time, so it's a task") }
            } catch { self.error = "Couldn't add to your calendar: \(error.localizedDescription)"; return }
        case .note:
            let body = t.hasPrefix("note:") || t.hasPrefix("idea:") ? String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces) : t
            _ = CaptureInbox.add(title: String(body.split(separator: "\n").first?.prefix(60) ?? "Note"), blocks: SmartPaste.blocks(from: body), ctx: ctx)
            UndoCenter.shared.notify("Captured")
        }
        try? ctx.save()
        Haptics.success()
        dismiss()
    }
}

/// The floating + that's on every main screen.
struct CaptureButton: View {
    @State private var open = false
    @AppStorage("capture.fab") private var on = true
    var body: some View {
        if on {
            Button { open = true; Haptics.tap() } label: {
                Image(systemName: "plus").font(.title2.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(DS.Palette.accent.gradient, in: Circle())
                    .shadow(color: DS.Palette.accent.opacity(0.35), radius: 12, y: 5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Capture anything")
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .sheet(isPresented: $open) { UniversalCaptureSheet() }
        }
    }
}

// MARK: - Everything links to everything

/// Links between any two things (pages, tasks, emails, events, people), kept in a hidden synced page.
@MainActor
enum KeelLinks {
    static let pageTitle = "⚙︎ Keel links"
    private static var cache: [[String]]?

    private static func page(_ ctx: ModelContext) -> Note {
        let t = pageTitle
        if let p = try? ctx.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.isTemplate && $0.title == t })).first { return p }
        let p = Note(title: pageTitle, blocks: []); p.isTemplate = true; ctx.insert(p); return p
    }
    static func all(_ ctx: ModelContext) -> [[String]] {
        if let c = cache { return c }
        let v = page(ctx).props["links"].flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode([[String]].self, from: $0) } ?? []
        cache = v; return v
    }
    static func add(_ a: String, _ b: String, ctx: ModelContext) {
        guard a != b else { return }
        var v = all(ctx)
        guard !v.contains(where: { Set($0) == Set([a, b]) }) else { return }
        v.append([a, b]); save(v, ctx)
    }
    static func remove(_ a: String, _ b: String, ctx: ModelContext) { save(all(ctx).filter { Set($0) != Set([a, b]) }, ctx) }
    private static func save(_ v: [[String]], _ ctx: ModelContext) {
        cache = v
        let p = page(ctx)
        p.props["links"] = (try? JSONEncoder().encode(v)).flatMap { String(data: $0, encoding: .utf8) }
        p.updatedAt = Date()
    }
    /// Everything linked to this key, plus the links Keel already knows (task made from an email or page, meeting notes).
    static func connected(_ key: String, ctx: ModelContext) -> [String] {
        var out = all(ctx).compactMap { pair -> String? in pair.contains(key) ? pair.first { $0 != key } : nil }
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return out }
        switch parts[0] {
        case "task":
            if let u = UUID(uuidString: parts[1]), let t = try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == u })).first {
                if let e = t.sourceEmailId { out.append("mail:" + e) }
                if let n = t.sourceNoteId { out.append("note:" + n.uuidString) }
            }
        case "note":
            if let u = UUID(uuidString: parts[1]) {
                for t in (try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.sourceNoteId == u }))) ?? [] { out.append("task:" + t.id.uuidString) }
            }
        case "mail":
            let id = parts[1]
            for t in (try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.sourceEmailId == id }))) ?? [] { out.append("task:" + t.id.uuidString) }
        default: break
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    static func describe(_ key: String, ctx: ModelContext) -> (icon: String, title: String)? {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let id = parts[1]
        switch parts[0] {
        case "note":
            guard let u = UUID(uuidString: id), let n = try? ctx.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == u })).first else { return nil }
            return ("doc.text", n.title.isEmpty ? "Untitled" : n.title)
        case "task":
            guard let u = UUID(uuidString: id), let t = try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == u })).first else { return nil }
            return (t.isDone ? "checkmark.circle.fill" : "circle", t.title)
        case "mail":
            guard let e = try? ctx.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { $0.id == id })).first else { return nil }
            return ("envelope", e.subject)
        case "person":
            guard let u = UUID(uuidString: id), let p = try? ctx.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.id == u })).first else { return nil }
            return ("person.fill", p.name)
        default: return nil
        }
    }
}

/// "Connected" strip: what this thing is linked to, one tap away, and + to link something new.
struct ConnectedStrip: View {
    let key: String
    @Environment(\.modelContext) private var ctx
    struct Item: Identifiable { let id: String; let icon: String; let title: String }
    @State private var items: [Item] = []
    @State private var linking = false
    @State private var open: CanvasRefTarget?
    @State private var openNote: Note?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CONNECTED").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                Spacer()
                Button { linking = true } label: { Label("Link", systemImage: "link.badge.plus").font(DS.Font.caption) }.buttonStyle(.borderless)
            }
            if items.isEmpty {
                Text("Link this to a page, task, email or person.").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(items) { it in
                        Button { openItem(it.id) } label: {
                            Label(it.title, systemImage: it.icon).font(.caption).lineLimit(1)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(DS.Palette.elevated, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("Unlink", systemImage: "link.badge.minus", role: .destructive) { KeelLinks.remove(key, it.id, ctx: ctx); refresh() } }
                    }
                }
            }
        }
        .task { refresh() }
        .sheet(isPresented: $linking) {
            LinkAnythingPicker { k in KeelLinks.add(key, k, ctx: ctx); refresh(); linking = false }
        }
        .sheet(item: $open) { CanvasRefSheet(target: $0) }
        .sheet(item: $openNote) { n in NavigationStack { NoteOrCanvas(note: n) } }
    }

    /// Looked up once (not on every redraw).
    private func refresh() {
        items = KeelLinks.connected(key, ctx: ctx).compactMap { k in KeelLinks.describe(k, ctx: ctx).map { Item(id: k, icon: $0.icon, title: $0.title) } }
    }
    private func openItem(_ k: String) {
        if k.hasPrefix("note:"), let u = UUID(uuidString: String(k.dropFirst(5))),
           let n = try? ctx.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.id == u })).first { openNote = n }
        else { open = CanvasRefTarget(ref: k) }
    }
}

struct LinkAnythingPicker: View {
    var pick: (String) -> Void
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var choosingOther = false
    var body: some View {
        NavigationStack {
            List {
                Section { Button("A task, email, person or PDF…", systemImage: "square.stack.3d.up") { choosingOther = true } }
                Section("Pages") {
                    ForEach(notes.filter { !$0.isTemplate && !$0.isLocked }.prefix(60)) { n in
                        Button { pick("note:" + n.id.uuidString) } label: { Label(n.title.isEmpty ? "Untitled" : n.title, systemImage: "doc.text") }
                    }
                }
            }
            .navigationTitle("Link to…").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $choosingOther) { CanvasAnythingPicker { ref, _ in choosingOther = false; pick(ref) } }
        }
    }
}

// MARK: - Smart handoffs: the natural next step, suggested at the right moment

@MainActor @Observable
final class Handoff {
    static let shared = Handoff()
    struct Suggestion: Identifiable { let id = UUID(); let text: String; let action: String; let run: () -> Void }
    var current: Suggestion?
    private var hide: Task<Void, Never>?

    func suggest(_ text: String, action: String, run: @escaping () -> Void) {
        current = Suggestion(text: text, action: action, run: run)
        hide?.cancel()
        hide = Task { try? await Task.sleep(for: .seconds(7)); if !Task.isCancelled { withAnimation(DS.spring) { self.current = nil } } }
    }

    /// After you finish a task: the next best thing, ready to start.
    func taskDone(_ t: TaskItem, ctx: ModelContext?) {
        guard let ctx else { return }
        let open = (try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? []
        let energy = EnergyLevel(rawValue: UserDefaults.standard.integer(forKey: "energy")) ?? .medium
        guard let next = ADHDCoach.nextThing(tasks: open.filter { $0.id != t.id }, energy: energy) else { return }
        suggest("Nice. Next: \(next.title)", action: "Start") { NowTimer.start(next, ctx: ctx); try? ctx.save() }
    }
}

struct HandoffBanner: View {
    @State private var h = Handoff.shared
    var body: some View {
        if let s = h.current {
            HStack(spacing: 10) {
                Image(systemName: "arrow.turn.down.right").foregroundStyle(DS.Palette.accent)
                Text(s.text).font(DS.Font.caption.weight(.medium)).lineLimit(2)
                Spacer()
                Button(s.action) { s.run(); withAnimation { h.current = nil } }.font(DS.Font.caption.weight(.semibold)).buttonStyle(.borderedProminent).tint(DS.Palette.accent)
                Button { withAnimation { h.current = nil } } label: { Image(systemName: "xmark").font(.caption) }.buttonStyle(.plain).accessibilityLabel("Dismiss")
            }
            .padding(12)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
            .padding(.horizontal).padding(.bottom, 80)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Projects that run themselves

@MainActor
enum ProjectPilot {
    struct Report { var emails: [EmailMessage]; var notes: [Note]; var events: [EKEvent]; var done: Int; var total: Int; var stuck: [TaskItem]; var quiet: Bool }

    static func report(_ p: Project, tasks: [TaskItem], ctx: ModelContext) -> Report {
        let words = p.name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 3 }
        func matches(_ s: String) -> Bool { let l = s.lowercased(); return !words.isEmpty && words.allSatisfy { l.contains($0) } }
        var md = FetchDescriptor<EmailMessage>(sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]); md.fetchLimit = 1_500
        let emails = ((try? ctx.fetch(md)) ?? []).filter { matches($0.subject + " " + $0.snippet) }.prefix(8)
        let linked = Set(KeelLinks.connected("project:" + p.id.uuidString, ctx: ctx))
        let notes = ((try? ctx.fetch(FetchDescriptor<Note>())) ?? []).filter { n in !n.isTemplate && (matches(n.title + " " + (n.folder ?? "")) || linked.contains("note:" + n.id.uuidString)) }.prefix(8)
        let events = CalendarService.shared.events(from: Date().addingTimeInterval(-14 * 86_400), to: Date().addingTimeInterval(30 * 86_400)).filter { matches($0.title ?? "") }
        let open = tasks.filter { !$0.isDone }
        let stuck = open.filter { ($0.dueDate ?? .distantFuture) < Date() || Date().timeIntervalSince($0.updatedAt) > 10 * 86_400 }
        let lastActivity = ([tasks.map(\.updatedAt).max(), notes.map(\.updatedAt).max(), emails.map(\.receivedAt).max()].compactMap { $0 }).max() ?? p.createdAt
        return Report(emails: Array(emails), notes: Array(notes), events: Array(events.prefix(6)), done: tasks.filter(\.isDone).count, total: tasks.count,
                      stuck: Array(stuck.prefix(5)), quiet: Date().timeIntervalSince(lastActivity) > 7 * 86_400)
    }

    static func weeklyStatus(_ p: Project, r: Report, tasks: [TaskItem]) async -> String {
        let since = Date().addingTimeInterval(-7 * 86_400)
        let doneWeek = tasks.filter { ($0.completedAt ?? .distantPast) > since }.map(\.title)
        let next = tasks.filter { !$0.isDone }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }.prefix(5).map(\.title)
        let prompt = """
        Write a short weekly status update for the project "\(p.name)" that I can send to others: 1 line overall status (on track / at risk), \
        then Done this week, Next, and Blockers as short bullet lists. Plain and specific.
        DONE THIS WEEK: \(doneWeek.joined(separator: "; "))
        NEXT: \(next.joined(separator: "; "))
        STUCK: \(r.stuck.map(\.title).joined(separator: "; "))
        PROGRESS: \(r.done) of \(r.total) tasks done\(p.deadline.map { ", deadline \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")
        RECENT EMAIL: \(r.emails.prefix(3).map(\.subject).joined(separator: "; "))
        """
        return await AIRouter.shared.write(prompt) ?? "Done: \(doneWeek.joined(separator: ", "))\nNext: \(next.joined(separator: ", "))"
    }
}

struct ProjectPilotSection: View {
    let project: Project
    let tasks: [TaskItem]
    @Environment(\.modelContext) private var ctx
    @State private var status: String?
    @State private var working = false
    @State private var compose: ComposeDraft?
    @State private var report: ProjectPilot.Report?

    var body: some View {
        let r = report ?? ProjectPilot.Report(emails: [], notes: [], events: [], done: tasks.filter(\.isDone).count, total: tasks.count, stuck: [], quiet: false)
        Section {
            if r.total > 0 {
                ProgressView(value: Double(r.done), total: Double(max(1, r.total))) {
                    Text("\(r.done) of \(r.total) done").font(DS.Font.caption)
                }
                .tint(DS.Palette.calm)
            }
            if r.quiet { Label("No movement in a week. Pick one small next step?", systemImage: "tortoise.fill").font(DS.Font.caption).foregroundStyle(DS.Palette.warmth) }
            ForEach(r.stuck) { t in Label(t.title, systemImage: "exclamationmark.circle").font(DS.Font.caption).foregroundStyle(.orange) }
            ForEach(r.events, id: \.calendarItemIdentifier) { e in Label("\(e.title ?? "") · \(e.startDate.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar").font(DS.Font.caption) }
            ForEach(r.notes) { n in NavigationLink { NoteOrCanvas(note: n) } label: { Label(n.title, systemImage: "doc.text").font(DS.Font.caption) } }
            ForEach(r.emails) { e in NavigationLink { EmailDetailView(email: e) } label: { Label(e.subject, systemImage: "envelope").font(DS.Font.caption).lineLimit(1) } }
            Button(working ? "Writing…" : "Write this week's status", systemImage: "doc.text.magnifyingglass") {
                Task { working = true; status = await ProjectPilot.weeklyStatus(project, r: r, tasks: tasks); working = false }
            }
            if let status {
                Text(status).font(DS.Font.caption).textSelection(.enabled)
                Button("Email it", systemImage: "paperplane") { var d = ComposeDraft(); d.subject = "\(project.name): weekly status"; d.body = status; compose = d }
            }
        } header: { Text("Autopilot") } footer: { Text("Gathered automatically: emails, pages and meetings about “\(project.name)”, plus what's stuck.") }
        .sheet(item: $compose) { ComposeView(draft: $0) }
        .task(id: tasks.count) { report = ProjectPilot.report(project, tasks: tasks, ctx: ctx) }      // gathered once, not every redraw
    }
}

// MARK: - Memory of every conversation

@MainActor
enum ConversationMemory {
    /// "Last time": what you talked about, what you promised, what they care about.
    static func brief(email: String, name: String, ctx: ModelContext) async -> String? {
        let addr = email.lowercased()
        var md = FetchDescriptor<EmailMessage>(predicate: #Predicate { $0.from == addr }, sortBy: [SortDescriptor(\.receivedAt, order: .reverse)])
        md.fetchLimit = 6
        let theirs = (try? ctx.fetch(md)) ?? []
        let promises = ((try? ctx.fetch(FetchDescriptor<Commitment>())) ?? []).filter { $0.recipient.lowercased() == addr && $0.status == .open }.prefix(4)
        let first = name.split(separator: " ").first.map(String.init) ?? name
        let notes = first.count < 3 ? [] : ((try? ctx.fetch(FetchDescriptor<Note>())) ?? []).filter { !$0.isLocked && $0.plainText.localizedCaseInsensitiveContains(name.isEmpty ? first : name) }.prefix(4)
        guard !theirs.isEmpty || !notes.isEmpty || !promises.isEmpty else { return nil }
        let ctxText = theirs.map { "EMAIL \($0.receivedAt.formatted(date: .abbreviated, time: .omitted)): \($0.subject) · \($0.aiSummary ?? String($0.snippet.prefix(160)))" }.joined(separator: "\n")
            + "\n" + notes.map { "NOTE \($0.title): \($0.plainText.prefix(300))" }.joined(separator: "\n")
            + (promises.isEmpty ? "" : "\nYOU PROMISED: " + promises.map(\.promise).joined(separator: "; "))
        let prompt = """
        In 3 short bullets, remind me about \(name.isEmpty ? email : name) before I reply: what we last talked about, anything I promised them, \
        and what they seem to care about. Only from below; be specific.

        \(ctxText.prefix(4_000))
        """
        return await AIRouter.shared.write(prompt)
    }
}

struct ConversationMemoryCard: View {
    let email: String
    let name: String
    @Environment(\.modelContext) private var ctx
    @State private var text: String?
    @State private var open = false
    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            if let text { Text(text).font(DS.Font.caption).textSelection(.enabled) } else { ProgressView().frame(maxWidth: .infinity) }
        } label: {
            Label("What you two last talked about", systemImage: "brain.head.profile").font(DS.Font.caption.weight(.semibold))
        }
        .onChange(of: open) { _, o in if o && text == nil { Task { text = await ConversationMemory.brief(email: email, name: name, ctx: ctx) ?? "Nothing earlier with them yet." } } }
        .padding(10).background(DS.Palette.elevated, in: .rect(cornerRadius: 12))
    }
}

// MARK: - Decision journal

@MainActor
enum Decisions {
    static let folder = "Areas/Decisions"
    static func log(_ title: String, why: String, expect: String, reviewIn days: Int, ctx: ModelContext) -> Note {
        let review = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        let n = Note(title: title, blocks: [NoteBlock(kind: .heading3, text: "Why"), NoteBlock(kind: .text, text: why),
                                            NoteBlock(kind: .heading3, text: "What I expect"), NoteBlock(kind: .text, text: expect),
                                            NoteBlock(kind: .heading3, text: "How it turned out"), NoteBlock(kind: .text, text: "")])
        n.icon = "⚖️"; n.folder = folder
        n.props["decision.review"] = String(review.timeIntervalSince1970)
        ctx.insert(n)
        let c = UNMutableNotificationContent()
        c.title = "How did it turn out?"; c.body = "You decided: \(title). Look back and grade the call."
        c.userInfo = ["deeplink": "com.keel.app://note/\(n.id.uuidString)"]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "decision.\(n.id)", content: c,
            trigger: UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day], from: review).merging(hour: 9), repeats: false)))
        try? ctx.save()
        return n
    }
    static func isDecision(_ n: Note) -> Bool { n.props["decision.review"] != nil }
    static func reviewDate(_ n: Note) -> Date? { n.props["decision.review"].flatMap(Double.init).map { Date(timeIntervalSince1970: $0) } }
    static func grade(_ n: Note) -> Int? { n.props["decision.grade"].flatMap(Int.init) }
}

extension DateComponents {
    func merging(hour: Int) -> DateComponents { var c = self; c.hour = hour; c.minute = 0; return c }
}

struct DecisionJournalView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @State private var adding = false
    @State private var title = ""
    @State private var why = ""
    @State private var expect = ""
    @State private var days = 30

    var body: some View {
        let ds = notes.filter(Decisions.isDecision)
        let graded = ds.compactMap(Decisions.grade)
        List {
            if !graded.isEmpty {
                Section("Your track record") {
                    LabeledContent("Good calls", value: "\(graded.filter { $0 >= 4 }.count) of \(graded.count)")
                    LabeledContent("Average", value: String(format: "%.1f / 5", Double(graded.reduce(0, +)) / Double(graded.count)))
                }
            }
            let due = ds.filter { (Decisions.reviewDate($0) ?? .distantFuture) <= Date() && Decisions.grade($0) == nil }
            if !due.isEmpty {
                Section("Ready to look back on") { ForEach(due) { n in decisionRow(n, review: true) } }
            }
            Section("Decisions") {
                if ds.isEmpty { Text("Log a decision and why you made it. Keel asks how it turned out later, so you learn which calls you get right.").foregroundStyle(DS.Palette.inkSoft) }
                ForEach(ds) { n in decisionRow(n, review: false) }
            }
        }
        .navigationTitle("Decisions")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Log a decision") } }
        .sheet(isPresented: $adding) {
            NavigationStack {
                Form {
                    TextField("The decision", text: $title)
                    TextField("Why (your reasons, what you knew)", text: $why, axis: .vertical)
                    TextField("What you expect to happen", text: $expect, axis: .vertical)
                    Picker("Look back in", selection: $days) { Text("2 weeks").tag(14); Text("1 month").tag(30); Text("3 months").tag(90); Text("6 months").tag(180) }
                }
                .navigationTitle("Log a decision").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { adding = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { _ = Decisions.log(title, why: why, expect: expect, reviewIn: days, ctx: ctx); title = ""; why = ""; expect = ""; adding = false }
                            .disabled(title.isEmpty)
                    }
                }
            }
        }
    }

    private func decisionRow(_ n: Note, review: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NavigationLink { NoteEditor(note: n) } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(n.title).font(DS.Font.headline)
                    Text(n.createdAt.formatted(date: .abbreviated, time: .omitted) + (Decisions.grade(n).map { " · graded \($0)/5" } ?? "")).font(.caption).foregroundStyle(DS.Palette.inkSoft)
                }
            }
            if review {
                HStack {
                    Text("How good was the call?").font(.caption)
                    ForEach(1...5, id: \.self) { g in
                        Button("\(g)") { n.props["decision.grade"] = String(g); n.updatedAt = Date(); Haptics.tap() }.buttonStyle(.bordered).font(.caption)
                    }
                }
            }
        }
    }
}

// MARK: - Life areas balance

enum LifeBalance {
    static let words: [LifeArea: [String]] = [
        .health: ["gym", "run", "doctor", "dentist", "therapy", "yoga", "walk", "workout", "meds", "sleep", "health"],
        .wealth: ["bank", "budget", "tax", "invoice", "bill", "pay", "money", "invest", "finance", "insurance"],
        .relationships: ["mom", "dad", "family", "date", "dinner with", "lunch with", "birthday", "friend", "kids", "wife", "husband", "partner"],
        .growth: ["read", "course", "learn", "study", "class", "book", "practice", "journal"],
        .fun: ["movie", "game", "concert", "trip", "vacation", "party", "hike", "beach", "fun"],
    ]
    /// Which area a title belongs to (work is the default for meetings and most tasks).
    static func area(for title: String) -> LifeArea {
        let l = title.lowercased()
        for (a, ws) in words where ws.contains(where: { l.contains($0) }) { return a }
        return .work
    }
}

struct LifeBalanceView: View {
    @Query(filter: #Predicate<TaskItem> { $0.isDone }) private var done: [TaskItem]
    var body: some View {
        let since = Date().addingTimeInterval(-7 * 86_400)
        var minutes: [LifeArea: Double] = [:]
        for e in CalendarService.shared.events(from: since, to: Date()) where !e.isAllDay {
            minutes[LifeBalance.area(for: e.title ?? ""), default: 0] += e.endDate.timeIntervalSince(e.startDate) / 60
        }
        for t in done where (t.completedAt ?? .distantPast) > since { minutes[LifeBalance.area(for: t.title + " " + t.listName), default: 0] += 20 }
        let total = max(1, minutes.values.reduce(0, +))
        let neglected = LifeArea.allCases.filter { (minutes[$0] ?? 0) / total < 0.04 && $0 != .work }
        return List {
            Section {
                ForEach(LifeArea.allCases) { a in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Label(a.title, systemImage: a.icon); Spacer(); Text("\(Int(((minutes[a] ?? 0) / total) * 100))%").monospacedDigit().foregroundStyle(DS.Palette.inkSoft) }
                        ProgressView(value: (minutes[a] ?? 0) / total).tint(a == .work ? DS.Palette.accent : DS.Palette.calm)
                    }
                }
            } header: { Text("This week") } footer: { Text("From your calendar and the tasks you finished. Keel guesses the area from each title.") }
            if let n = neglected.first {
                Section { Label("\(n.title) has had almost no time this week. One small thing for it?", systemImage: "leaf.fill").foregroundStyle(DS.Palette.calm) }
            }
        }
        .navigationTitle("Life balance")
    }
}

// MARK: - One bar: find, ask, do

struct SearchAction: Identifiable {
    let id: String
    let icon: String
    let title: (String) -> String
    let run: (String) -> Void
}

@MainActor
enum SearchActions {
    static let all: [SearchAction] = [
        SearchAction(id: "task", icon: "plus.circle", title: { "Add task: \($0)" }) { q in
            _ = QuickAdd.create(q, in: KeelStore.container.mainContext); UndoCenter.shared.notify("Added to Tasks"); Haptics.success()
        },
        SearchAction(id: "note", icon: "square.and.pencil", title: { "New page: \($0)" }) { q in
            let n = Note(title: q); KeelStore.container.mainContext.insert(n); AppRouter.shared.openNoteId = n.id
        },
        SearchAction(id: "focus", icon: "moon.zzz", title: { _ in "Start focus" }) { _ in AppRouter.shared.showFocus = true },
        SearchAction(id: "plan", icon: "list.bullet.clipboard", title: { _ in "Plan my day" }) { _ in AppRouter.shared.showPlan = true },
        SearchAction(id: "record", icon: "waveform.badge.mic", title: { _ in "Record a meeting" }) { _ in AppRouter.shared.showRecorder = true },
        SearchAction(id: "journal", icon: "book", title: { _ in "Write in my journal" }) { _ in AppRouter.shared.showJournal = true },
    ]
    /// Commands that fit what you typed ("add milk", "focus", "plan"), task and page creation always offered.
    static func matching(_ q: String) -> [SearchAction] {
        let l = q.lowercased()
        let named = all.filter { a in ["focus": ["focus", "concentrate"], "plan": ["plan"], "record": ["record", "meeting"], "journal": ["journal"]][a.id]?.contains { l.contains($0) } ?? false }
        let isQuestion = l.hasSuffix("?") || ["what", "when", "where", "who", "how", "why", "did", "do i", "is "].contains { l.hasPrefix($0) }
        return named + (isQuestion ? [] : all.filter { $0.id == "task" || $0.id == "note" })
    }
}

/// "Has it been long enough since this last ran?" (and marks it as run).
enum Throttle {
    static func due(_ key: String, every seconds: TimeInterval) -> Bool {
        let k = "throttle." + key
        let last = UserDefaults.standard.double(forKey: k)
        guard Date().timeIntervalSince1970 - last > seconds else { return false }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: k)
        return true
    }
}
