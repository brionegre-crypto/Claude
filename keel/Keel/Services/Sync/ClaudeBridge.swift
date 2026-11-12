import Foundation
import SwiftData

/// Keeps the Keel backend's Claude connector (MCP) in step with the phone:
/// uploads a small snapshot after each sync and applies actions Claude queued.
/// This is how Claude (and Claude Duet, once it supports custom connectors) works with Keel.
@MainActor
enum ClaudeBridge {
    private static var base: URL? { KeelServer.baseURL }

    private static func request(_ path: String, method: String, body: Data? = nil) -> URLRequest? {
        guard let base, let token = KeychainStore.read("keel.session") else { return nil }
        var r = URLRequest(url: base.appendingPathComponent(path))
        r.httpMethod = method
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = body
        return r
    }

    static func uploadSnapshot(ctx: ModelContext) async {
        guard !AIRouter.shared.privateMode else { return }   // private mode: nothing leaves the phone
        let tasks = (try? ctx.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isDone }))) ?? []
        let notes = ((try? ctx.fetch(FetchDescriptor<Note>())) ?? []).filter { !$0.isLocked }
        let promises = ((try? ctx.fetch(FetchDescriptor<Commitment>())) ?? []).filter { $0.status == .open }
        let energy = EnergyLevel(rawValue: UserDefaults.standard.integer(forKey: "energy")) ?? .medium
        let snapshot: [String: Any] = [
            "today": [
                "nextThing": ADHDCoach.nextThing(tasks: tasks, energy: energy)?.title ?? "",
                "events": CalendarService.shared.todaysEvents().map { "\($0.startDate.formatted(date: .omitted, time: .shortened)) \($0.title ?? "")" },
            ] as [String: Any],
            "tasks": tasks.prefix(200).map { t in [
                "title": t.title, "list": t.listName, "due": t.dueDate?.ISO8601Format() ?? "",
                "energy": t.energy.label, "steps": t.microSteps.map(\.text),
            ] as [String: Any] },
            "promises": promises.prefix(100).map { [
                "promise": $0.promise, "to": $0.displayName, "quote": $0.quote,
                "due": $0.dueDate?.ISO8601Format() ?? "", "overdue": $0.isOverdue,
            ] as [String: Any] },
            "notes": notes.prefix(200).map { ["title": $0.title, "text": String($0.plainText.prefix(4_000))] },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: snapshot),
              let req = request("snapshot", method: "POST", body: data) else { return }
        _ = try? await URLSession.shared.data(for: req)
    }

    static func applyQueuedActions(ctx: ModelContext) async {
        guard let req = request("actions", method: "GET"),
              let (data, _) = try? await URLSession.shared.data(for: req),
              let actions = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        for a in actions {
            let args = a["args"] as? [String: Any] ?? [:]
            switch a["type"] as? String {
            case "add_task":
                let t = TaskItem(title: args["title"] as? String ?? "From Claude",
                                 dueDate: (args["due"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) })
                t.listName = args["list"] as? String ?? "Inbox"
                ctx.insert(t)
                try? CalendarService.shared.push(t)
            case "start_focus":
                // Never start blocking apps silently — ask the user with a notification instead.
                UserDefaults.standard.set(args["minutes"] as? Int ?? 25, forKey: "claude.suggestedFocus")
            default: break
            }
        }
    }
}
