import SwiftUI
import SwiftData
import UserNotifications

// MARK: - "…when I leave work" / "…when I get home" in any reminder

@MainActor
enum LocationPhrase {
    /// Matches a saved place (Settings → Tasks → Places) and turns the phrase into an arrive/leave alert.
    static func apply(to t: TaskItem, ctx: ModelContext) {
        let title = t.title
        let pattern = #"\b(when|once|as soon as) i (leave|get to|get home|arrive at|arrive home|arrive|am at|reach)\s*(the )?([a-z' ]{0,24})$"#
        guard let r = title.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return }
        let phrase = title[r].lowercased()
        let leaving = phrase.contains("leave")
        var placeName = phrase
        for w in ["as soon as", "when", "once", "i ", "leave", "get to", "get", "arrive at", "arrive", "am at", "reach", "the "] {
            placeName = placeName.replacingOccurrences(of: w, with: " ")
        }
        placeName = placeName.trimmingCharacters(in: .whitespaces)
        if phrase.contains("home") { placeName = "home" }
        guard let place = LocationReminders.places.first(where: { $0.name.lowercased() == placeName || (!placeName.isEmpty && $0.name.lowercased().contains(placeName)) }) else { return }
        t.title = String(title[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
        t.latitude = place.latitude
        t.longitude = place.longitude
        t.locationName = place.name
        t.remindOnArrive = !leaving
        Task { await LocationReminders.refresh(ctx: ctx) }
    }
}

// MARK: - Ask all my notes

@MainActor
enum NotesAsk {
    static func search(_ q: String, in notes: [Note], limit: Int = 8) -> [Note] {
        let stop: Set<String> = ["the", "and", "for", "what", "when", "where", "who", "did", "does", "about", "with", "from", "that", "this", "have", "has", "was", "were", "are", "my", "me", "how", "which", "notes", "note", "page", "pages"]
        let words = q.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 && !stop.contains($0) }
        let pool = notes.filter { !$0.isLocked && !$0.isTemplate }
        guard !words.isEmpty else { return Array(pool.prefix(limit)) }
        return pool.compactMap { n -> (Note, Double)? in
            let title = n.title.lowercased(), body = n.plainText.prefix(8_000).lowercased(), folder = (n.folder ?? "").lowercased()
            var s = 0.0
            for w in words {
                if title.contains(w) { s += 4 }
                if folder.contains(w) { s += 1.5 }
                s += min(Double(body.components(separatedBy: w).count - 1), 5)
            }
            return s > 0 ? (n, s + max(0, 1 - Date().timeIntervalSince(n.updatedAt) / (90 * 86_400))) : nil
        }
        .sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    static func answer(_ q: String, sources: [Note]) async -> String {
        guard !sources.isEmpty else { return "None of your pages mention that yet." }
        let ctx = sources.enumerated().map { i, n in "[\(i + 1)] \(n.title.isEmpty ? "Untitled" : n.title)\(n.folder.map { " (in \($0))" } ?? ""):\n\(n.plainText.prefix(1_200))" }
            .joined(separator: "\n\n")
        let prompt = """
        Answer the question using only these pages from my notes. Be brief and specific, and cite pages like [1] or [2]. \
        If they don't answer it, say what's missing.

        QUESTION: \(q)

        PAGES:
        \(ctx.prefix(10_000))
        """
        return await AIRouter.shared.write(prompt) ?? "Keel's AI isn't available right now. The closest pages are below."
    }
}

struct AskNotesView: View {
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var question = ""
    @State private var answer: String?
    @State private var sources: [Note] = []
    @State private var working = false
    @FocusState private var focused: Bool

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("e.g. What did we decide about the launch date?", text: $question, axis: .vertical)
                        .focused($focused).onSubmit { Task { await ask() } }
                    Button { Task { await ask() } } label: {
                        if working { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    }
                    .disabled(question.trimmingCharacters(in: .whitespaces).count < 3 || working)
                }
            } footer: { Text("Answers come from your own pages, with links to each one it used. Locked pages are never read.") }
            if let answer { Section("Answer") { Text(answer).textSelection(.enabled) } }
            if !sources.isEmpty {
                Section("From these pages") {
                    ForEach(Array(sources.enumerated()), id: \.element.id) { i, n in
                        NavigationLink { NoteOrCanvas(note: n) } label: {
                            HStack {
                                Text(n.icon ?? "📄")
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("[\(i + 1)] \(n.title.isEmpty ? "Untitled" : n.title)").lineLimit(1)
                                    if let f = n.folder { Text(f.replacingOccurrences(of: "/", with: " › ")).font(.caption).foregroundStyle(DS.Palette.inkSoft) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Ask my notes")
        .onAppear { focused = true }
    }

    private func ask() async {
        let q = question.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3 else { return }
        working = true; defer { working = false }
        sources = NotesAsk.search(q, in: Array(notes))
        answer = await NotesAsk.answer(q, sources: sources)
    }
}

// MARK: - AI autofill for database properties

@MainActor
enum DBAutofill {
    /// Fills an AI property for every row (or only empty ones) from each row's title and content.
    static func fill(_ p: DBProperty, in db: Note, rows: [Note], onlyEmpty: Bool, progress: @escaping (Int, Int) -> Void) async {
        let instruction = p.options.first ?? "A one-line summary"
        let todo = rows.filter { !onlyEmpty || (($0.props[p.id] ?? "").isEmpty) }
        for (i, r) in todo.enumerated() {
            progress(i, todo.count)
            let others = db.schema.filter { $0.id != p.id && $0.kind != .ai }.compactMap { q -> String? in
                guard let v = r.props[q.id], !v.isEmpty else { return nil }
                return "\(q.name): \(v)"
            }.joined(separator: "; ")
            let prompt = """
            Fill in "\(p.name)" for this item. Instruction: \(instruction)
            Reply with only the value, as short as possible (a few words or one sentence).

            ITEM: \(r.title)
            \(others.isEmpty ? "" : "PROPERTIES: \(others)\n")CONTENT: \(r.plainText.prefix(2_500))
            """
            if let v = await AIRouter.shared.write(prompt) {
                let clean = v.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
                r.props[p.id] = clean.isEmpty ? nil : String(clean.prefix(300))
            }
        }
        progress(todo.count, todo.count)
    }
}

struct DBAutofillButton: View {
    let property: DBProperty
    @Bindable var db: Note
    @Query private var notes: [Note]
    @State private var working = false
    @State private var progress = (0, 0)

    var body: some View {
        let rows = NotesDatabase.rows(of: db, in: notes)
        HStack {
            Button(working ? "Filling \(progress.0) of \(progress.1)…" : "Fill empty rows") { run(rows, onlyEmpty: true) }
            Spacer()
            Button("Refill all") { run(rows, onlyEmpty: false) }.foregroundStyle(DS.Palette.inkSoft)
        }
        .disabled(working || rows.isEmpty)
        .buttonStyle(.borderless).font(DS.Font.caption)
    }

    private func run(_ rows: [Note], onlyEmpty: Bool) {
        working = true
        Task {
            await DBAutofill.fill(property, in: db, rows: rows, onlyEmpty: onlyEmpty) { done, total in progress = (done, total) }
            working = false
            Haptics.success()
        }
    }
}

// MARK: - "Remind me…" lines in notes

@MainActor
enum NoteReminders {
    /// A note line that starts with "remind me" (or "todo:") becomes a real reminder when you press Return,
    /// with its date, repeat and place understood ("remind me to call mom every other Sunday 5pm").
    static func capture(_ text: String, in note: Note, ctx: ModelContext) -> TaskItem? {
        let t = text.trimmingCharacters(in: .whitespaces)
        let low = t.lowercased()
        guard low.hasPrefix("remind me") || low.hasPrefix("todo:") || low.hasPrefix("reminder:") else { return nil }
        let input = low.hasPrefix("todo:") ? String(t.dropFirst(5)) : low.hasPrefix("reminder:") ? String(t.dropFirst(9)) : t
        guard input.trimmingCharacters(in: .whitespaces).count > 3 else { return nil }
        let task = QuickAdd.create(input.trimmingCharacters(in: .whitespaces), in: ctx)
        task.sourceNoteId = note.id
        return task
    }
}

// MARK: - Weekly digest (Sunday evening)

@MainActor
enum WeeklyDigest {
    static let onKey = "digest.weekly.on", lastKey = "digest.weekly.last"
    static var isOn: Bool { UserDefaults.standard.object(forKey: onKey) as? Bool ?? true }

    /// From Sunday 4 PM (or any time Monday), writes last week's digest once and lets you know.
    static func makeIfDue(ctx: ModelContext) {
        guard isOn else { return }
        let cal = Calendar.current
        let now = Date()
        let wd = cal.component(.weekday, from: now)
        guard (wd == 1 && cal.component(.hour, from: now) >= 16) || wd == 2 else { return }
        let weekKey = "\(cal.component(.yearForWeekOfYear, from: now.addingTimeInterval(wd == 2 ? -86_400 : 0)))-\(cal.component(.weekOfYear, from: now.addingTimeInterval(wd == 2 ? -86_400 : 0)))"
        guard UserDefaults.standard.string(forKey: lastKey) != weekKey else { return }
        UserDefaults.standard.set(weekKey, forKey: lastKey)
        let note = make(ctx: ctx)
        let c = UNMutableNotificationContent()
        c.title = "Your week, in one page"
        c.body = "What you finished, what moved, and what's coming up. Tap to read it."
        c.sound = .default
        c.userInfo = ["deeplink": "com.keel.app://note/\(note.id.uuidString)"]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "digest.\(weekKey)", content: c, trigger: nil))
    }

    static func make(ctx: ModelContext) -> Note {
        let cal = Calendar.current
        let since = Date().addingTimeInterval(-7 * 86_400)
        let nextWeek = Date().addingTimeInterval(7 * 86_400)
        let tasks = (try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []
        let done = tasks.filter { ($0.completedAt ?? .distantPast) > since }
        let dueNext = tasks.filter { !$0.isDone && ($0.dueDate.map { $0 < nextWeek } ?? false) }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        let deadlines = tasks.compactMap { t in TaskMeta.deadline(t).flatMap { $0 < nextWeek && !t.isDone ? (t.title, $0) : nil } }
        let notes = ((try? ctx.fetch(FetchDescriptor<Note>())) ?? []).filter { $0.createdAt > since && !$0.isTemplate && !$0.isLocked }
        let habits = ((try? ctx.fetch(FetchDescriptor<HabitLog>())) ?? []).filter { $0.completedAt > since }.count
        let focus = ((try? ctx.fetch(FetchDescriptor<FocusSession>())) ?? []).filter { $0.startedAt > since }
            .reduce(0) { $0 + Int((($1.endedAt ?? $1.startedAt).timeIntervalSince($1.startedAt)) / 60) }
        let events = CalendarService.shared.events(from: Date(), to: nextWeek).filter { !$0.isAllDay }

        var b: [NoteBlock] = []
        var stats = NoteBlock(kind: .callout, text: "✅ \(done.count) tasks done · 🔁 \(habits) habit check-ins · 🎯 \(focus / 60)h \(focus % 60)m focused · 📝 \(notes.count) new pages")
        stats.icon = "📊"
        b.append(stats)
        if !done.isEmpty {
            b.append(.init(kind: .heading2, text: "Finished"))
            b += done.prefix(15).map { NoteBlock(kind: .bullet, text: $0.title) }
        }
        if !notes.isEmpty {
            b.append(.init(kind: .heading2, text: "New pages"))
            b += notes.prefix(10).map { NoteBlock(kind: .bullet, text: "[\($0.title.isEmpty ? "Untitled" : $0.title)](\(RichText.pageURL($0.id)))") }
        }
        if !deadlines.isEmpty {
            b.append(.init(kind: .heading2, text: "Deadlines this week"))
            b += deadlines.prefix(8).map { NoteBlock(kind: .bullet, text: "**\($0.1.formatted(.dateTime.weekday(.wide)))**: \($0.0)") }
        }
        if !events.isEmpty {
            b.append(.init(kind: .heading2, text: "Coming up"))
            let byDay = Dictionary(grouping: events.prefix(30)) { cal.startOfDay(for: $0.startDate) }
            for day in byDay.keys.sorted() {
                b.append(.init(kind: .heading3, text: day.formatted(.dateTime.weekday(.wide).month().day())))
                b += (byDay[day] ?? []).map { NoteBlock(kind: .bullet, text: "\($0.startDate.formatted(date: .omitted, time: .shortened)) \($0.title ?? "Event")") }
            }
        }
        if !dueNext.isEmpty {
            b.append(.init(kind: .heading2, text: "On your list"))
            b += dueNext.prefix(12).map { var x = NoteBlock(kind: .todo, text: $0.title); x.checked = false; return x }
        }
        let n = Note(title: "Week of \(since.formatted(.dateTime.month().day()))", blocks: b)
        n.icon = "🗓️"
        n.folder = NotePath.make("Personal", "Weekly digests")
        ctx.insert(n)
        try? ctx.save()
        return n
    }
}

/// Today → ⊞ → This week's digest: make one now (it also arrives by itself on Sunday evening).
struct WeeklyDigestView: View {
    @Environment(\.modelContext) private var ctx
    @State private var made: Note?
    @AppStorage(WeeklyDigest.onKey) private var on = true

    var body: some View {
        Group {
            if let made {
                NoteEditor(note: made)
            } else {
                Form {
                    Section {
                        Button("Write this week's digest now", systemImage: "sparkles") { made = WeeklyDigest.make(ctx: ctx); Haptics.success() }
                    } footer: { Text("One page with what you finished, new pages, deadlines and the week ahead. Saved in Notes → Personal → Weekly digests.") }
                    Section {
                        Toggle("Every Sunday evening", isOn: $on)
                    } footer: { Text("Keel writes it at 4 PM on Sunday (or when you first open Keel after that) and lets you know.") }
                }
                .navigationTitle("Weekly digest")
            }
        }
    }
}
