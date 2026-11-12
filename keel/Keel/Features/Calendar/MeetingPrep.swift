import SwiftUI
import SwiftData
import EventKit
import UserNotifications

/// Everything you need before a meeting, on one screen: who's coming, your recent emails with them,
/// linked notes, open tasks and promises, plus a one-tap Apple Intelligence brief.
@MainActor
enum MeetingPrep {
    struct Pack {
        var attendees: [(name: String, email: String)]
        var emails: [EmailMessage]
        var notes: [Note]
        var tasks: [TaskItem]
        var promises: [Commitment]
        var isEmpty: Bool { emails.isEmpty && notes.isEmpty && tasks.isEmpty && promises.isEmpty }
    }

    static func attendees(_ e: EKEvent) -> [(name: String, email: String)] {
        (e.attendees ?? []).filter { !$0.isCurrentUser }.map { p in
            let email = p.url.absoluteString.replacingOccurrences(of: "mailto:", with: "").lowercased()
            return (p.name ?? email, email)
        }
    }

    static func build(_ e: EKEvent, ctx: ModelContext) -> Pack {
        let people = attendees(e)
        let emails = Set(people.map(\.email).filter { !$0.isEmpty })
        let names = people.map(\.name).compactMap { $0.split(separator: " ").first.map { String($0).lowercased() } }.filter { $0.count > 2 }
        let titleWords = (e.title ?? "").lowercased().split(separator: " ").map(String.init).filter { $0.count > 3 }
        let since = Date().addingTimeInterval(-45 * 86_400)
        let mail = ((try? ctx.fetch(FetchDescriptor<EmailMessage>(sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]))) ?? [])
            .filter { $0.receivedAt > since && emails.contains($0.from.lowercased()) }
            .prefix(6)
        let eventId = e.eventIdentifier
        let notes = ((try? ctx.fetch(FetchDescriptor<Note>())) ?? []).filter { n in
            !n.isLocked && (n.linkedEventId == eventId || (!titleWords.isEmpty && titleWords.allSatisfy { n.title.lowercased().contains($0) }))
        }
        let tasks = ((try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []).filter { t in
            !t.isDone && (names.contains { t.title.lowercased().contains($0) } || titleWords.contains { t.title.lowercased().contains($0) })
        }
        let promises = ((try? ctx.fetch(FetchDescriptor<Commitment>())) ?? []).filter { $0.status == .open && emails.contains($0.recipient.lowercased()) }
        return Pack(attendees: people, emails: Array(mail), notes: notes, tasks: Array(tasks.prefix(6)), promises: promises)
    }

    /// A heads-up 10 minutes before meetings that have something to prep.
    static func scheduleReminders(ctx: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("prep.") }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard UserDefaults.standard.object(forKey: "prep.on") as? Bool ?? true else { return }
        let now = Date()
        for e in CalendarService.shared.events(from: now, to: now.addingTimeInterval(24 * 3600)).filter({ !$0.isAllDay && $0.attendees?.isEmpty == false }).prefix(10) {
            let p = build(e, ctx: ctx)
            guard !p.isEmpty else { continue }
            let fire = e.startDate.addingTimeInterval(-600)
            guard fire > now else { continue }
            var bits: [String] = []
            if !p.emails.isEmpty { bits.append("\(p.emails.count) recent email\(p.emails.count == 1 ? "" : "s")") }
            if !p.promises.isEmpty { bits.append("\(p.promises.count) open promise\(p.promises.count == 1 ? "" : "s")") }
            if !p.tasks.isEmpty { bits.append("\(p.tasks.count) related task\(p.tasks.count == 1 ? "" : "s")") }
            if !p.notes.isEmpty { bits.append("notes") }
            let c = UNMutableNotificationContent()
            c.title = "Prep: \(e.title ?? "Meeting") in 10 min"
            c.body = bits.joined(separator: ", ").capitalizedFirst + ". Tap to review."
            c.userInfo = ["deeplink": "com.keel.app://today"]
            KeelAlerts.urgent(c, relevance: 0.9)
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            try? await center.add(UNNotificationRequest(identifier: "prep.\(e.calendarItemIdentifier)", content: c,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

struct MeetingPrepView: View {
    let event: EKEvent
    @Environment(\.modelContext) private var ctx
    @State private var pack: MeetingPrep.Pack?
    @State private var brief: String?
    @State private var briefing = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title ?? "Meeting").font(DS.Font.title)
                    Text("\(event.startDate.formatted(date: .abbreviated, time: .shortened)) – \(event.endDate.formatted(date: .omitted, time: .shortened))")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    if let l = event.location, !l.isEmpty { Label(l, systemImage: "mappin").font(DS.Font.caption) }
                    if let leave = LeaveBy.times[event.calendarItemIdentifier] {
                        Label("Leave by \(leave.formatted(date: .omitted, time: .shortened))", systemImage: "car.fill").font(DS.Font.caption).foregroundStyle(DS.Palette.warmth)
                    }
                }
            }
            if let pack {
                if !pack.attendees.isEmpty {
                    Section("Who's coming") {
                        ForEach(pack.attendees, id: \.email) { a in
                            VStack(alignment: .leading) { Text(a.name); Text(a.email).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft) }
                        }
                    }
                }
                Section {
                    if let brief { Text(brief).font(.callout) }
                    Button { Task { await makeBrief(pack) } } label: {
                        Label(briefing ? "Thinking…" : (brief == nil ? "Brief me" : "Refresh brief"), systemImage: "sparkles")
                    }
                    .disabled(briefing || pack.isEmpty)
                } footer: { Text(pack.isEmpty ? "Nothing related found yet." : "Apple Intelligence reads the emails, notes and tasks below on this iPhone.") }
                if !pack.promises.isEmpty {
                    Section("You promised") { ForEach(pack.promises) { Label($0.promise, systemImage: "hand.raised.fill") } }
                }
                if !pack.emails.isEmpty {
                    Section("Recent emails") { ForEach(pack.emails) { e in NavigationLink { EmailDetailView(email: e) } label: { EmailRow(email: e) } } }
                }
                if !pack.tasks.isEmpty {
                    Section("Related tasks") { ForEach(pack.tasks) { t in NavigationLink { TaskDetailView(task: t) } label: { TaskRow(task: t) } } }
                }
                if !pack.notes.isEmpty {
                    Section("Notes") { ForEach(pack.notes) { n in NavigationLink(n.title) { NoteEditor(note: n) } } }
                }
            }
            Section {
                Button("Start meeting notes", systemImage: "square.and.pencil") { startNotes() }
            }
        }
        .navigationTitle("Meeting Prep")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { pack = MeetingPrep.build(event, ctx: ctx) }
    }

    private func makeBrief(_ p: MeetingPrep.Pack) async {
        briefing = true; defer { briefing = false }
        var text = "Meeting: \(event.title ?? "")\n"
        text += p.emails.map { "Email from \($0.fromName): \($0.subject). \($0.aiSummary ?? $0.snippet)" }.joined(separator: "\n")
        text += "\n" + p.promises.map { "I promised: \($0.promise)" }.joined(separator: "\n")
        text += "\n" + p.tasks.map { "Open task: \($0.title)" }.joined(separator: "\n")
        text += "\n" + p.notes.map { "Note \($0.title): \($0.plainText.prefix(600))" }.joined(separator: "\n")
        brief = await AIRouter.shared.write("Prepare me for this meeting: key context, what they may ask, and what I owe them.\n" + text)
    }

    private func startNotes() {
        let names = (pack?.attendees ?? []).map(\.name).joined(separator: ", ")
        let n = Note(title: event.title ?? "Meeting", blocks: [
            .init(kind: .text, text: "\(event.startDate.formatted()) · \(names)"),
            .init(kind: .heading, text: "Notes"), .init(kind: .bullet, text: ""),
            .init(kind: .heading, text: "Action items"), .init(kind: .todo, text: ""),
        ])
        n.linkedEventId = event.eventIdentifier
        ctx.insert(n)
        pack = MeetingPrep.build(event, ctx: ctx)
        Haptics.success()
    }
}
