import SwiftUI
import SwiftData

/// "Promises": every commitment you made in sent email, in one calm list.
/// ADHD design: grouped by when they're owed, one obvious action per row, no red alarms —
/// overdue items get a warm color and a ready-made "sorry for the delay" draft.
struct PromisesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Commitment.sentAt, order: .reverse) private var all: [Commitment]
    @State private var showKept = false
    @State private var followUp: Commitment?

    private var open: [Commitment] { all.filter { $0.status == .open } }
    private var likelyKept: [Commitment] { open.filter(\.likelyKept) }
    private var owed: [Commitment] { open.filter { !$0.likelyKept }.sorted { $0.effectiveDue < $1.effectiveDue } }

    private var groups: [(title: String, items: [Commitment])] {
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: Date())
        let endWeek = cal.date(byAdding: .day, value: 7, to: startToday)!
        return [
            ("Overdue", owed.filter { $0.effectiveDue < startToday }),
            ("Today", owed.filter { cal.isDateInToday($0.effectiveDue) }),
            ("This week", owed.filter { $0.effectiveDue >= cal.date(byAdding: .day, value: 1, to: startToday)! && $0.effectiveDue < endWeek }),
            ("Later", owed.filter { $0.effectiveDue >= endWeek }),
        ].filter { !$0.items.isEmpty }
    }

    var body: some View {
        List {
            Section { header }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())

            if !likelyKept.isEmpty {
                Section {
                    ForEach(likelyKept) { c in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.promise).font(DS.Font.headline)
                                Text("You replied to \(c.displayName) after this — looks delivered.")
                                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                            }
                            Spacer()
                            Button("Yes") { close(c, as: .done) }.buttonStyle(.borderedProminent).tint(DS.Palette.calm)
                            Button("No") { c.likelyKept = false }.buttonStyle(.bordered)
                        }
                    }
                } header: { Label("Did you keep these?", systemImage: "sparkles") }
            }

            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items) { c in
                        PromiseRow(commitment: c)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button { close(c, as: .done) } label: { Label("Kept", systemImage: "checkmark") }.tint(DS.Palette.calm)
                            }
                            .swipeActions(edge: .leading) {
                                Button { makeTask(c) } label: { Label("Task", systemImage: "checklist") }.tint(DS.Palette.accent)
                                Button { close(c, as: .dismissed) } label: { Label("Not a promise", systemImage: "xmark") }.tint(.gray)
                            }
                            .contextMenu {
                                Button("Mark kept", systemImage: "checkmark") { close(c, as: .done) }
                                Button("Make it a task", systemImage: "checklist") { makeTask(c) }
                                Button("Draft a follow-up", systemImage: "envelope") { followUp = c }
                                Button("Not a promise", systemImage: "xmark") { close(c, as: .dismissed) }
                            }
                            .onTapGesture { followUp = c }
                    }
                }
            }

            if owed.isEmpty && likelyKept.isEmpty {
                ContentUnavailableView("No open promises", systemImage: "hand.thumbsup",
                                       description: Text("When you write “I'll send it Friday” in an email, it shows up here so you never have to remember."))
                    .listRowBackground(Color.clear)
            }

            if showKept {
                Section("Kept") {
                    ForEach(all.filter { $0.status == .done }) { c in
                        Label(c.promise, systemImage: "checkmark.circle.fill").foregroundStyle(DS.Palette.inkSoft)
                    }
                }
            }
        }
        .navigationTitle("Promises")
        .toolbar { Toggle(isOn: $showKept) { Image(systemName: "checkmark.seal") }.toggleStyle(.button) }
        .refreshable { await SyncEngine.shared.syncAll() }
        .sheet(item: $followUp) { FollowUpSheet(commitment: $0) }
    }

    private var header: some View {
        let kept = all.filter { $0.status == .done }.count
        let made = all.filter { $0.status != .dismissed }.count
        return GlassCard(tint: DS.Palette.accent) {
            HStack(spacing: DS.Space.l) {
                stat("\(owed.count)", "open")
                stat("\(owed.filter { $0.effectiveDue < Calendar.current.startOfDay(for: Date()) }.count)", "overdue", color: DS.Palette.warmth)
                stat(made == 0 ? "—" : "\(Int(Double(kept) / Double(made) * 100))%", "kept")
                Spacer()
                Image(systemName: "hand.raised.fingers.spread").font(.largeTitle).foregroundStyle(DS.Palette.accent.opacity(0.6))
            }
        }
        .padding(.horizontal).padding(.top, DS.Space.s)
    }

    private func stat(_ value: String, _ label: String, color: Color = DS.Palette.ink) -> some View {
        VStack(alignment: .leading) {
            Text(value).font(DS.Font.title).foregroundStyle(color).contentTransition(.numericText())
            Text(label).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
        }
    }

    private func close(_ c: Commitment, as status: CommitmentStatus) {
        withAnimation(DS.spring) {
            c.status = status
            c.completedAt = Date()
        }
        status == .done ? Haptics.success() : Haptics.tap()
        if let id = c.taskId, let task = try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first {
            task.isDone = status == .done; task.updatedAt = Date(); try? CalendarService.shared.push(task)
        }
        Task { await PromiseTracker.scheduleNudges(ctx: ctx) }
    }

    private func makeTask(_ c: Commitment) {
        guard c.taskId == nil else { return }
        let t = TaskItem(title: c.promise, dueDate: c.effectiveDue, priority: .medium)
        t.notes = "Promised to \(c.displayName) in “\(c.subject)”:\n“\(c.quote)”"
        ctx.insert(t)
        c.taskId = t.id
        try? CalendarService.shared.push(t)          // shows up in Apple Reminders too
        Haptics.success()
    }
}

struct PromiseRow: View {
    let commitment: Commitment
    var body: some View {
        let c = commitment
        HStack(alignment: .top, spacing: DS.Space.m) {
            Circle()
                .fill(c.isOverdue ? DS.Palette.warmth : DS.Palette.accent.opacity(0.5))
                .frame(width: 10, height: 10).padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(c.promise).font(DS.Font.headline)
                Text("To \(c.displayName) · “\(c.quote)”")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2)
                HStack(spacing: 6) {
                    if let due = c.dueDate {
                        Chip(text: due.formatted(.relative(presentation: .named)), color: c.isOverdue ? DS.Palette.warmth : DS.Palette.focus, icon: "clock")
                    } else {
                        Chip(text: "no date · sent \(c.sentAt.formatted(.relative(presentation: .named)))", color: .gray)
                    }
                    if c.taskId != nil { Chip(text: "task", color: DS.Palette.accent, icon: "checklist") }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Tap to draft a follow-up. Swipe for more actions.")
    }
}

/// One tap from "I forgot" to "sent": an AI draft that delivers or buys time, gracefully.
struct FollowUpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [MailAccount]
    let commitment: Commitment
    @State private var draft = ""
    @State private var loading = false
    @State private var mode = 0

    private let modes = ["Here it is", "Need a bit more time", "Quick update"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Text("You told \(commitment.displayName):").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                Text("“\(commitment.quote)”").font(DS.Font.body).italic()
                Picker("Reply type", selection: $mode) { ForEach(modes.indices, id: \.self) { Text(modes[$0]).tag($0) } }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { Task { await makeDraft() } }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                TextEditor(text: $draft)
                    .padding(DS.Space.s)
                    .background(DS.Palette.elevated, in: .rect(cornerRadius: DS.Radius.chip))
                Button { send() } label: { Label("Send", systemImage: "paperplane.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(DS.Palette.accent).disabled(draft.isEmpty)
            }
            .padding()
            .navigationTitle(commitment.subject)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Close") { dismiss() } }
            .task { await makeDraft() }
        }
        .presentationDetents([.medium, .large])
    }

    private func makeDraft() async {
        loading = true; defer { loading = false }
        let intent: String = switch mode {
        case 0: "I'm delivering what I promised (\(commitment.promise)). Keep it short; mention it's attached or below."
        case 1: "I need a little more time on \(commitment.promise). Apologize briefly, no over-explaining, and give a new specific day."
        default: "Give a short progress update on \(commitment.promise) and when it'll be done."
        }
        let stub = EmailMessage(accountId: commitment.accountId, providerMessageId: commitment.sourceMessageId,
                                threadId: commitment.threadId, from: commitment.recipient, fromName: commitment.recipientName,
                                subject: commitment.subject, snippet: "", bodyPlain: "My earlier message said: \(commitment.quote)",
                                receivedAt: commitment.sentAt, isRead: true)
        draft = await AIRouter.shared.draftReply(to: stub, intent: intent) ?? ""
    }

    private func send() {
        guard let a = accounts.first(where: { $0.id == commitment.accountId }) else { return }
        Task {
            try? await MailProviderFactory.make(for: a).send(to: commitment.recipient, subject: "Re: \(commitment.subject)",
                                                             body: draft, inReplyTo: nil)
            if mode == 0 { commitment.status = .done; commitment.completedAt = Date() }
            // "More time": your follow-up states a new date, so the next sent-mail scan creates the
            // updated promise from it. Retire this one so it doesn't show twice.
            if mode == 1 { commitment.status = .dismissed; commitment.completedAt = Date() }
            Haptics.success()
            dismiss()
        }
    }
}

extension Commitment {
    var displayName: String { recipientName.isEmpty ? recipient : recipientName }
}
