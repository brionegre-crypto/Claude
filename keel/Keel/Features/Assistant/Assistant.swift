import SwiftUI
import SwiftData
import EventKit
import FoundationModels

// "Ask Keel": a chat assistant on Apple Intelligence (on-device, free, private) that can read your day
// and take real actions through tools: add/complete tasks, create events, search mail, start focus.
// The same brain answers Siri via AskKeelIntent.

// MARK: - Tools

@MainActor
private enum Store {
    static var ctx: ModelContext { KeelStore.container.mainContext }
}

struct AgendaTool: Tool {
    let name = "getAgenda"
    let description = "Get the user's calendar events, due tasks, open promises and important unread email for a day."

    @Generable
    struct Arguments {
        @Guide(description: "Days from today: 0 = today, 1 = tomorrow, -1 = yesterday")
        var dayOffset: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            let cal = Calendar.current
            let day = cal.date(byAdding: .day, value: arguments.dayOffset, to: cal.startOfDay(for: Date()))!
            let next = cal.date(byAdding: .day, value: 1, to: day)!
            let events = CalendarService.shared.events(from: day, to: next)
                .map { "\($0.isAllDay ? "all day" : $0.startDate.formatted(date: .omitted, time: .shortened)) \($0.title ?? "")" }
            let tasks = ((try? Store.ctx.fetch(FetchDescriptor<TaskItem>())) ?? [])
                .filter { !$0.isDone && ($0.dueDate.map { $0 < next } ?? false) }
                .map { "\($0.title)\($0.hasDueTime ? " at \($0.dueDate!.formatted(date: .omitted, time: .shortened))" : "")\($0.dueDate! < day ? " (overdue)" : "")" }
            let mail = ((try? Store.ctx.fetch(FetchDescriptor<EmailMessage>())) ?? [])
                .filter { !$0.isRead && !$0.isArchived && ($0.category == .important || $0.category == .actionable) }
                .prefix(5).map { "\($0.fromName.isEmpty ? $0.from : $0.fromName): \($0.aiSummary ?? $0.subject)" }
            let promises = ((try? Store.ctx.fetch(FetchDescriptor<Commitment>())) ?? [])
                .filter { $0.status == .open && $0.effectiveDue < next }.map { "\($0.promise) (to \($0.displayName))" }
            return """
            Date: \(day.formatted(date: .complete, time: .omitted))
            Events: \(events.isEmpty ? "none" : events.joined(separator: "; "))
            Tasks due: \(tasks.isEmpty ? "none" : tasks.joined(separator: "; "))
            Important unread email: \(mail.isEmpty ? "none" : mail.joined(separator: "; "))
            Promises due: \(promises.isEmpty ? "none" : promises.joined(separator: "; "))
            """
        }
    }
}

struct AddTaskTool: Tool {
    let name = "addTask"
    let description = "Add a task. Write it naturally, including date, time and repeat if given, e.g. 'Call mom tomorrow 5pm' or 'Gym every Monday 7am'."

    @Generable
    struct Arguments {
        @Guide(description: "The task in natural language, including any date/time/repeat")
        var text: String
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            let t = QuickAdd.create(arguments.text, in: Store.ctx)
            try? Store.ctx.save()
            let when = t.dueDate.map { " due \($0.formatted(date: .abbreviated, time: t.hasDueTime ? .shortened : .omitted))" } ?? ""
            return "Added task “\(t.title)”\(when)\(t.recurrence.map { ", \($0.label.lowercased())" } ?? "")."
        }
    }
}

struct CompleteTaskTool: Tool {
    let name = "completeTask"
    let description = "Mark an existing open task as done by (part of) its title."

    @Generable
    struct Arguments {
        @Guide(description: "Words from the task's title")
        var title: String
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            let q = arguments.title.lowercased()
            let open = ((try? Store.ctx.fetch(FetchDescriptor<TaskItem>())) ?? []).filter { !$0.isDone }
            guard let t = open.first(where: { $0.title.lowercased() == q }) ?? open.first(where: { $0.title.lowercased().contains(q) }) else {
                return "No open task matches “\(arguments.title)”."
            }
            let next = TaskActions.setDone(t, true)
            try? Store.ctx.save()
            return "Completed “\(t.title)”\(next.map { "; it repeats, next on \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")."
        }
    }
}

struct CreateEventTool: Tool {
    let name = "createEvent"
    let description = "Create a calendar event."

    @Generable
    struct Arguments {
        var title: String
        @Guide(description: "Start as yyyy-MM-dd HH:mm in the user's local time")
        var start: String
        @Guide(description: "Length in minutes", .range(5...600))
        var minutes: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm"
            guard let start = f.date(from: arguments.start) else { return "Couldn't understand the time “\(arguments.start)”." }
            let store = CalendarService.shared.store
            let e = EKEvent(eventStore: store)
            e.title = arguments.title
            e.startDate = start
            e.endDate = start.addingTimeInterval(Double(arguments.minutes * 60))
            e.calendar = store.defaultCalendarForNewEvents
            do {
                try store.save(e, span: .thisEvent)
                return "Created “\(arguments.title)” on \(start.formatted(date: .abbreviated, time: .shortened))."
            } catch {
                return "Couldn't create the event: \(error.localizedDescription)"
            }
        }
    }
}

struct SearchMailTool: Tool {
    let name = "searchMail"
    let description = "Search the user's synced email by keyword or sender."

    @Generable
    struct Arguments {
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            let q = arguments.query.lowercased()
            let hits = ((try? Store.ctx.fetch(FetchDescriptor<EmailMessage>(sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]))) ?? [])
                .filter { [$0.subject, $0.fromName, $0.from, $0.bodyPlain].contains { $0.lowercased().contains(q) } }
                .prefix(5)
            guard !hits.isEmpty else { return "No email matches “\(arguments.query)”." }
            return hits.map { "\($0.receivedAt.formatted(date: .abbreviated, time: .omitted)) from \($0.fromName.isEmpty ? $0.from : $0.fromName): \($0.subject). \($0.aiSummary ?? String($0.snippet.prefix(120)))" }
                .joined(separator: "\n")
        }
    }
}

struct StartFocusTool: Tool {
    let name = "startFocus"
    let description = "Start a focus session that hides the inbox and holds Keel's alerts."

    @Generable
    struct Arguments {
        @Guide(description: "Minutes", .range(5...180))
        var minutes: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            Store.ctx.insert(ShutdownManager.shared.start(minutes: arguments.minutes, level: .soft, task: nil))
            return "Started a \(arguments.minutes)-minute focus session."
        }
    }
}

struct MedsTool: Tool {
    let name = "medications"
    let description = "Check whether the user already took their medication today, or log a dose as taken."

    @Generable
    struct Arguments {
        @Guide(description: "check or take")
        var action: String
        @Guide(description: "Medication name to log as taken; empty for check or for the next due dose")
        var name: String
    }

    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            let ctx = Store.ctx
            if arguments.action.lowercased() == "take" {
                return MedsLogger.logNext(name: arguments.name, ctx: ctx)
            }
            return MedEngine.statusSentence(ctx: ctx)
        }
    }
}

// MARK: - Assistant brain

@MainActor @Observable
final class KeelAssistant {
    static let shared = KeelAssistant()

    struct Message: Identifiable {
        let id = UUID()
        let fromUser: Bool
        var text: String
    }

    var messages: [Message] = []
    var isThinking = false
    private var session: LanguageModelSession?

    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    private func makeSession() -> LanguageModelSession {
        let now = Date().formatted(.dateTime.weekday(.wide).month().day().year().hour().minute())
        return LanguageModelSession(
            tools: [AgendaTool(), AddTaskTool(), CompleteTaskTool(), CreateEventTool(), SearchMailTool(), StartFocusTool(), MedsTool()],
            instructions: """
            You are Keel, a warm, concise assistant for someone with ADHD. It is \(now).
            Use the tools to look things up and to take actions. Never invent tasks, events or emails.
            Keep answers short: one or two sentences, or a tight bullet list. Suggest one clear next step when helpful.
            """)
    }

    /// One question in, one answer out (used by the chat screen and by Siri).
    func ask(_ question: String) async -> String {
        guard isAvailable else {
            return "Ask Keel needs Apple Intelligence. Turn it on in Settings → Apple Intelligence & Siri (iPhone 15 Pro or newer)."
        }
        if session == nil { session = makeSession() }
        do {
            return try await session!.respond(to: question).content
        } catch {
            session = makeSession()                      // e.g. the conversation got too long: start fresh
            return (try? await session!.respond(to: question).content) ?? "Sorry, I couldn't do that. Try asking another way."
        }
    }

    func send(_ text: String) async {
        messages.append(Message(fromUser: true, text: text))
        isThinking = true
        let answer = await ask(text)
        isThinking = false
        messages.append(Message(fromUser: false, text: answer))
    }

    func reset() {
        messages = []
        session = nil
    }
}

// MARK: - Chat screen

struct AssistantView: View {
    @State private var assistant = KeelAssistant.shared
    @State private var input = ""
    @FocusState private var focused: Bool

    private let suggestions = ["What's on today?", "Plan my afternoon", "Add “call the bank tomorrow 10am”",
                               "What did Jordan email about?", "Start a 25 minute focus", "What's overdue?"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.m) {
                        if assistant.messages.isEmpty { intro }
                        ForEach(assistant.messages) { m in bubble(m).id(m.id) }
                        if assistant.isThinking {
                            HStack(spacing: 6) { ProgressView(); Text("Thinking…").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft) }
                                .id("thinking")
                        }
                    }
                    .padding()
                }
                .onChange(of: assistant.messages.count) {
                    if let last = assistant.messages.last?.id { withAnimation { proxy.scrollTo(last, anchor: .bottom) } }
                }
            }
            HStack(spacing: DS.Space.s) {
                TextField("Ask or tell Keel anything…", text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focused)
                    .onSubmit(send)
                    .padding(.horizontal, DS.Space.m).padding(.vertical, 10)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)).foregroundStyle(DS.Palette.accent)
                }
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || assistant.isThinking)
                .accessibilityLabel("Send")
            }
            .padding()
        }
        .navigationTitle("Ask Keel")
        .toolbar {
            if !assistant.messages.isEmpty {
                Button("New chat") { assistant.reset() }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(DS.Palette.accent.gradient)
            Text("Ask Keel").font(DS.Font.hero)
            Text(assistant.isAvailable
                 ? "Runs on Apple Intelligence, on this iPhone. It can check your day, add and complete tasks, create events, find emails and start focus."
                 : "Turn on Apple Intelligence in iPhone Settings → Apple Intelligence & Siri to use Ask Keel (iPhone 15 Pro or newer).")
                .font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
            Text("You can also say “Hey Siri, ask Keel …”.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            FlowChips(items: suggestions) { s in input = s; send() }
        }
    }

    private func bubble(_ m: KeelAssistant.Message) -> some View {
        HStack {
            if m.fromUser { Spacer(minLength: 40) }
            Text(m.text)
                .font(DS.Font.body)
                .textSelection(.enabled)
                .padding(.horizontal, DS.Space.m).padding(.vertical, 10)
                .background(m.fromUser ? DS.Palette.accent : DS.Palette.elevated, in: .rect(cornerRadius: 18))
                .foregroundStyle(m.fromUser ? .white : DS.Palette.ink)
            if !m.fromUser { Spacer(minLength: 40) }
        }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        Haptics.tap()
        Task { await assistant.send(text) }
    }
}

/// Wrapping row of suggestion chips.
struct FlowChips: View {
    let items: [String]
    var onTap: (String) -> Void
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { ForEach(items, id: \.self, content: chip) }
            VStack(alignment: .leading, spacing: DS.Space.s) { ForEach(items, id: \.self, content: chip) }
        }
    }
    private func chip(_ s: String) -> some View {
        Button { onTap(s) } label: {
            Text(s).font(DS.Font.caption).padding(.horizontal, 12).padding(.vertical, 8)
                .background(DS.Palette.accent.opacity(0.12), in: Capsule()).foregroundStyle(DS.Palette.accent)
        }
        .buttonStyle(.plain)
    }
}
