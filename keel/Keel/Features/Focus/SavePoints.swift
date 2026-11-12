import SwiftUI
import SwiftData
import EventKit
import UserNotifications
import Observation

/// Save Points: when you're pulled away (a meeting, a call, switching apps), Keel remembers what you were in
/// the middle of: the reply you were writing, the page you were editing, the task and its next step.
/// When you come back, or the moment a meeting ends, it hands your train of thought back in one tap.
struct SavePoint: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case draft, note, task }
    var id = UUID()
    var kind: Kind
    var title: String              // "Replying to Sam: Budget"
    var detail: String             // the last line you wrote
    var next: String?              // the next step, if known
    var refId: String              // draft / note / task id
    var createdAt = Date()
    // Drafts
    var accountId: String?
    var to: String?
    var subject: String?
    var body: String?
    var emailId: String?

    var icon: String { kind == .draft ? "envelope.open" : kind == .note ? "doc.text" : "checklist" }
}

@MainActor @Observable
final class SavePointCenter {
    static let shared = SavePointCenter()
    var showing: SavePoint?
}

@MainActor
enum SavePoints {
    static let key = "savepoints.v1"
    static let awayKey = "savepoints.backgroundAt"
    static let onKey = "savepoints.on"
    static let returnNotification = "savepoint.return"
    static var isOn: Bool { UserDefaults.standard.object(forKey: onKey) as? Bool ?? true }
    /// Away at least this long before Keel offers to resume (a quick glance elsewhere doesn't count).
    static let minAway: TimeInterval = 3 * 60

    static var all: [SavePoint] {
        get {
            guard let d = UserDefaults.standard.data(forKey: key), let p = try? JSONDecoder().decode([SavePoint].self, from: d) else { return [] }
            return p
        }
        set { if let d = try? JSONEncoder().encode(Array(newValue.prefix(12))) { UserDefaults.standard.set(d, forKey: key) } }
    }

    static var latest: SavePoint? { all.first }

    static func save(_ p: SavePoint) {
        guard isOn else { return }
        var list = all.filter { !($0.kind == p.kind && $0.refId == p.refId) }
        list.insert(p, at: 0)
        all = list
    }

    static func remove(refId: String) {
        all = all.filter { $0.refId != refId }
    }

    static func remove(_ p: SavePoint) {
        all = all.filter { $0.id != p.id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [returnNotification])
    }

    /// The last line with words in it, trimmed for a card.
    static func lastLine(_ text: String) -> String {
        let line = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty && !$0.hasPrefix(">") } ?? ""
        return line.count > 120 ? "…" + line.suffix(117) : line
    }

    // MARK: Leaving and coming back

    static func didEnterBackground() {
        UserDefaults.standard.set(Date(), forKey: awayKey)
        scheduleAfterMeeting()
    }

    /// The save point to offer when you come back, if you were away long enough and it's fresh.
    static func pendingResume(now: Date = Date()) -> SavePoint? {
        guard isOn, let away = UserDefaults.standard.object(forKey: awayKey) as? Date,
              now.timeIntervalSince(away) >= minAway, let p = latest,
              p.createdAt >= away.addingTimeInterval(-60), now.timeIntervalSince(p.createdAt) < 12 * 3600 else { return nil }
        return p
    }

    /// If you left for a meeting, a nudge (and a watch tap) right after it ends: "You were: …"
    static func scheduleAfterMeeting() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [returnNotification])
        guard isOn, let p = latest, Date().timeIntervalSince(p.createdAt) < 10 * 60 else { return }
        let now = Date()
        guard let meeting = CalendarService.shared.events(from: now.addingTimeInterval(-3 * 3600), to: now.addingTimeInterval(15 * 60))
            .filter({ !$0.isAllDay && $0.endDate > now && $0.startDate <= now.addingTimeInterval(15 * 60) && $0.attendees?.isEmpty == false })
            .sorted(by: { $0.startDate < $1.startDate }).first else { return }
        let c = UNMutableNotificationContent()
        c.title = "\(meeting.title ?? "Meeting") is over. Pick up where you left off?"
        c.body = p.title + (p.detail.isEmpty ? "" : ": “\(p.detail)”") + (p.next.map { " Next: \($0)" } ?? "")
        c.sound = .default
        c.userInfo = ["deeplink": "com.keel.app://resume"]
        c.interruptionLevel = .timeSensitive
        center.add(UNNotificationRequest(identifier: returnNotification, content: c,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(60, meeting.endDate.timeIntervalSince(now) + 60), repeats: false)))
    }

    /// Opens exactly where you were.
    static func resume(_ p: SavePoint, ctx: ModelContext) {
        remove(p)
        switch p.kind {
        case .note:
            if let id = UUID(uuidString: p.refId) { AppRouter.shared.openNoteId = id }
        case .task:
            if let id = UUID(uuidString: p.refId) { AppRouter.shared.openTaskId = id }
        case .draft:
            let accounts = (try? ctx.fetch(FetchDescriptor<MailAccount>())) ?? []
            var d: ComposeDraft
            if let eid = p.emailId, let e = try? ctx.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { $0.id == eid })).first {
                d = ComposeDraft.reply(to: e, all: false, accounts: accounts)
            } else {
                d = ComposeDraft(accountId: p.accountId)
            }
            d.to = p.to ?? d.to
            d.subject = p.subject ?? d.subject
            d.body = p.body ?? d.body
            AppRouter.shared.tab = .inbox
            MailRouter.shared.pending = d
        }
        Haptics.success()
    }

    // MARK: Builders used by the screens

    static func draft(_ d: ComposeDraft, accountId: String) -> SavePoint? {
        let typed = d.body.components(separatedBy: "\n\nOn ").first ?? d.body
        guard !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let who = d.original.map { $0.fromName.isEmpty ? $0.from : $0.fromName } ?? (ComposeDraft.addressList(d.to).first ?? "someone")
        return SavePoint(kind: .draft, title: (d.replyTo != nil ? "Replying to " : "Writing to ") + who + (d.subject.isEmpty ? "" : ": \(d.subject)"),
                         detail: lastLine(typed), next: "Finish and send", refId: d.id.uuidString,
                         accountId: accountId, to: d.to, subject: d.subject, body: d.body, emailId: d.original?.id)
    }

    static func note(_ n: Note, focusedBlock: UUID?) -> SavePoint? {
        guard !n.isLocked else { return nil }               // locked pages never leave a trace
        let block = focusedBlock.flatMap { id in n.blocks.first { $0.id == id } } ?? n.blocks.last { !$0.text.isEmpty }
        let text = block?.text ?? ""
        guard !n.title.isEmpty || !text.isEmpty else { return nil }
        return SavePoint(kind: .note, title: "Editing “\(n.title.isEmpty ? "Untitled" : n.title)”", detail: lastLine(text),
                         next: nil, refId: n.id.uuidString)
    }

    static func task(_ t: TaskItem) -> SavePoint? {
        guard !t.isDone else { return nil }
        let step = t.microSteps.first { !$0.done }?.text
        return SavePoint(kind: .task, title: "Working on “\(t.title)”", detail: t.notes.isEmpty ? "" : lastLine(t.notes),
                         next: step, refId: t.id.uuidString)
    }
}

/// Saves a save point when the app goes to the background from this screen.
private struct SavePointOnLeave: ViewModifier {
    let make: () -> SavePoint?
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content.onChange(of: phase) { _, p in
            if p == .background, let sp = make() { SavePoints.save(sp) }
        }
    }
}

extension View {
    func savePoint(_ make: @escaping () -> SavePoint?) -> some View { modifier(SavePointOnLeave(make: make)) }
}

/// The card that greets you when you come back: "You were replying to Sam…"
struct SavePointBanner: View {
    let point: SavePoint
    let resume: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Label("Pick up where you left off", systemImage: "bookmark.fill").font(DS.Font.caption.weight(.semibold))
                .foregroundStyle(DS.Palette.accent)
            HStack(alignment: .top, spacing: DS.Space.m) {
                Image(systemName: point.icon).font(.title3).foregroundStyle(DS.Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(point.title).font(DS.Font.headline).lineLimit(2)
                    if !point.detail.isEmpty { Text("“\(point.detail)”").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2) }
                    if let n = point.next { Text("Next: \(n)").font(DS.Font.caption.weight(.medium)) }
                }
            }
            HStack {
                Button(action: resume) { Text("Resume").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(DS.Palette.accent)
                Button("Not now", action: dismiss).buttonStyle(.bordered)
            }
        }
        .padding(DS.Space.m)
        .background(.regularMaterial, in: .rect(cornerRadius: DS.Radius.card))
        .shadow(color: .black.opacity(0.15), radius: 18, y: 6)
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
    }
}

/// Today → ⊞ → Save points: your recent places, to jump back into any of them.
struct SavePointsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var points = SavePoints.all
    @AppStorage(SavePoints.onKey) private var on = true

    var body: some View {
        List {
            if points.isEmpty {
                ContentUnavailableView("No save points", systemImage: "bookmark",
                                       description: Text("When you leave Keel mid-reply, mid-page or mid-task, it remembers where you were."))
                    .listRowBackground(Color.clear)
            }
            ForEach(points) { p in
                Button { SavePoints.resume(p, ctx: ctx); points = SavePoints.all } label: {
                    HStack(alignment: .top, spacing: DS.Space.m) {
                        Image(systemName: p.icon).foregroundStyle(DS.Palette.accent).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.title).font(DS.Font.headline).foregroundStyle(DS.Palette.ink).lineLimit(2)
                            if !p.detail.isEmpty { Text("“\(p.detail)”").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(2) }
                            Text(p.createdAt.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                }
            }
            .onDelete { idx in idx.map { points[$0] }.forEach { SavePoints.remove($0) }; points = SavePoints.all }
            Section {
                Toggle("Remember Where I Was", isOn: $on)
            } footer: { Text("Kept on this iPhone. Locked notes are never saved. After a meeting, Keel reminds you what you were doing.") }
        }
        .navigationTitle("Save Points")
    }
}
