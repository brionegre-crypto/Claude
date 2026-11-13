import SafariServices
import Foundation

/// "Save to Keel" in Safari: the page goes to your reading list, highlights go with it.
/// Items wait in the App Group until Keel opens (same queue as the share sheet).
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private struct Shared: Codable { var url: String; var title: String?; var date: Date }
    private struct Highlight: Codable { var url: String; var title: String; var text: String; var date: Date }
    private let group = "group.com.briangreenejr.keel"

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any] ?? [:]
        let url = message["url"] as? String ?? ""
        let title = message["title"] as? String ?? ""
        let highlight = (message["highlight"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var ok = false
        if let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group), !url.isEmpty {
            let links = dir.appendingPathComponent("shared-links.json")
            var list = (try? Data(contentsOf: links)).flatMap { try? JSONDecoder().decode([Shared].self, from: $0) } ?? []
            if !list.contains(where: { $0.url == url }) { list.append(Shared(url: url, title: title, date: Date())) }
            ok = (try? JSONEncoder().encode(list).write(to: links, options: .atomic)) != nil
            if !highlight.isEmpty {
                let hl = dir.appendingPathComponent("safari-highlights.json")
                var h = (try? Data(contentsOf: hl)).flatMap { try? JSONDecoder().decode([Highlight].self, from: $0) } ?? []
                h.append(Highlight(url: url, title: title, text: highlight, date: Date()))
                ok = (try? JSONEncoder().encode(h).write(to: hl, options: .atomic)) != nil
            }
        }
        let reply = NSExtensionItem()
        reply.userInfo = [SFExtensionMessageKey: ["ok": ok]]
        context.completeRequest(returningItems: [reply], completionHandler: nil)
    }
}
