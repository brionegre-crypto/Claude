import SwiftUI
import SwiftData
import UserNotifications
import TipKit

// MARK: - Hand a task to someone

/// Who a task is assigned to. Kept in a hidden synced page (no database changes), so it follows you to every device.
@MainActor
enum TaskAssign {
    static let pageTitle = "⚙︎ Keel assignments"
    struct Who: Codable, Hashable { var name: String; var email: String; var at: Double }
    private static var cache: [String: Who]?

    private static func page(_ ctx: ModelContext) -> Note {
        let t = pageTitle
        if let p = try? ctx.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.isTemplate && $0.title == t })).first { return p }
        let p = Note(title: pageTitle, blocks: []); p.isTemplate = true; ctx.insert(p); return p
    }
    static func all(_ ctx: ModelContext) -> [String: Who] {
        if let c = cache { return c }
        let v = page(ctx).props["assign"].flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode([String: Who].self, from: $0) } ?? [:]
        cache = v; return v
    }
    static func who(_ task: TaskItem, ctx: ModelContext) -> Who? { all(ctx)[task.id.uuidString] }

    static func assign(_ task: TaskItem, to name: String, email: String, ctx: ModelContext) {
        var v = all(ctx)
        v[task.id.uuidString] = Who(name: name, email: email, at: Date().timeIntervalSince1970)
        save(v, ctx)
        task.isWaitingOn = true                 // it's theirs now: out of your way, still tracked under Waiting on others
        task.updatedAt = Date()
    }
    static func unassign(_ task: TaskItem, ctx: ModelContext) {
        var v = all(ctx)
        v[task.id.uuidString] = nil
        save(v, ctx)
        task.isWaitingOn = false
        task.updatedAt = Date()
    }
    private static func save(_ v: [String: Who], _ ctx: ModelContext) {
        cache = v
        let p = page(ctx)
        p.props["assign"] = (try? JSONEncoder().encode(v)).flatMap { String(data: $0, encoding: .utf8) }
        p.updatedAt = Date()
    }

    /// A ready-to-send email handing the task over.
    static func handoffEmail(_ task: TaskItem, to who: Who) -> ComposeDraft {
        var body = "Hi \(who.name.split(separator: " ").first.map(String.init) ?? who.name),\n\nCould you take this on?\n\n• \(task.title)"
        if let d = task.dueDate { body += "\n• Needed by \(d.formatted(date: .complete, time: task.hasDueTime ? .shortened : .omitted))" }
        if !task.notes.isEmpty { body += "\n\n\(task.notes)" }
        if !task.microSteps.isEmpty { body += "\n\nSteps:\n" + task.microSteps.map { "– \($0.text)" }.joined(separator: "\n") }
        body += "\n\nThanks!"
        return ComposeDraft(to: who.email, subject: "Can you take this on: \(task.title)", body: body)
    }
}

/// The "Assigned to" section in a task.
struct AssignSection: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Person.name) private var people: [Person]
    @State private var who: TaskAssign.Who?
    @State private var askingOther = false
    @State private var otherName = ""
    @State private var otherEmail = ""
    @State private var compose: ComposeDraft?          // shown right here (a task is often already in a sheet)

    var body: some View {
        Section {
            TipView(AssignTip())
            if let who {
                LabeledContent("Assigned to") { Text(who.name) }
                if !who.email.isEmpty {
                    Button("Email it to \(who.name.split(separator: " ").first.map(String.init) ?? who.name)", systemImage: "paperplane") {
                        compose = TaskAssign.handoffEmail(task, to: who)
                    }
                    Button("Nudge them", systemImage: "hand.wave") {
                        compose = ComposeDraft(to: who.email, subject: "Quick check-in: \(task.title)",
                                                                 body: "Hi \(who.name.split(separator: " ").first.map(String.init) ?? who.name), how's “\(task.title)” going? Anything you need from me?")
                    }
                }
                Button("Take it back", systemImage: "arrow.uturn.backward", role: .destructive) {
                    TaskAssign.unassign(task, ctx: ctx); withAnimation(.snappy) { self.who = nil }
                }
            } else {
                Menu {
                    ForEach(people) { p in
                        Button(p.name) { set(p.name, p.email) }
                    }
                    if !people.isEmpty { Divider() }
                    Button("Someone else…", systemImage: "person.badge.plus") { askingOther = true }
                } label: { Label("Assign to someone", systemImage: "person.crop.circle.badge.plus") }
            }
        } header: { Text("Shared") } footer: {
            Text(who == nil ? "Hand it to someone. It moves to Waiting on others, and Keel drafts the email for you." : "Waiting on them. You'll see it under Waiting on others until it's done.")
        }
        .onAppear { who = TaskAssign.who(task, ctx: ctx) }
        .sheet(item: $compose) { ComposeView(draft: $0) }
        .alert("Assign to", isPresented: $askingOther) {
            TextField("Name", text: $otherName)
            TextField("Email (optional)", text: $otherEmail).keyboardType(.emailAddress).textInputAutocapitalization(.never)
            Button("Assign") { if !otherName.trimmingCharacters(in: .whitespaces).isEmpty { set(otherName, otherEmail) }; otherName = ""; otherEmail = "" }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func set(_ name: String, _ email: String) {
        TaskAssign.assign(task, to: name, email: email.trimmingCharacters(in: .whitespaces), ctx: ctx)
        withAnimation(.snappy) { who = TaskAssign.who(task, ctx: ctx) }
        Haptics.success()
        AssignTip().invalidate(reason: .actionPerformed)
    }
}

// MARK: - Shared spaces: know when someone else changes a page

@MainActor
enum SpaceChanges {
    static let seenKey = "spaces.seen"
    private static var seen: [String: Int] {
        get { (UserDefaults.standard.dictionary(forKey: seenKey) as? [String: Int]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: seenKey) }
    }
    static func markSeen(_ pageId: String, version: Int) {
        var s = seen; s[pageId] = max(s[pageId] ?? 0, version); seen = s
    }

    private struct Change: Decodable { let id: String; let title: String; let version: Int; let lastBy: String }

    /// Checks your spaces; for each page someone else changed since you last looked, a quiet alert.
    static func check() async {
        let spaces = Spaces.all
        guard !spaces.isEmpty else { return }
        var s = seen
        let me = SharedLists.myName
        for space in spaces {
            guard let data = try? await KeelCloud.call("space/\(space.id)/changes"),
                  let changes = try? JSONDecoder().decode([Change].self, from: data) else { continue }
            for c in changes {
                guard let last = s[c.id] else { s[c.id] = c.version; continue }          // first look: just remember
                guard c.version > last else { continue }
                s[c.id] = c.version
                guard !c.lastBy.isEmpty, c.lastBy != me else { continue }
                let n = UNMutableNotificationContent()
                n.title = "\(c.lastBy) updated “\(c.title)”"
                n.body = "In \(space.name). Tap to see what changed."
                n.threadIdentifier = "space.\(space.id)"
                try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "space.\(c.id).\(c.version)", content: n, trigger: nil))
            }
        }
        seen = s
    }
}
