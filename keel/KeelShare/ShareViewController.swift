import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Safari (or any app) → Share → Keel. Saves the link into the App Group; Keel imports it next time it opens.
final class ShareViewController: UIViewController {
    private struct Shared: Codable { var url: String; var title: String?; var date: Date }

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: SavedConfirmation())
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await save() }
    }

    private func save() async {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        var found: (url: String, title: String?)?
        for item in items {
            let title = item.attributedContentText?.string
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    found = (url.absoluteString, title); break
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
                   text.lowercased().hasPrefix("http") {
                    found = (text, title); break
                }
            }
            if found != nil { break }
        }
        if let found, let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.briangreenejr.keel") {
            let file = dir.appendingPathComponent("shared-links.json")
            var queue = (try? JSONDecoder().decode([Shared].self, from: Data(contentsOf: file))) ?? []
            queue.append(Shared(url: found.url, title: found.title, date: Date()))
            try? JSONEncoder().encode(queue).write(to: file, options: .atomic)
        }
        try? await Task.sleep(for: .milliseconds(700))
        extensionContext?.completeRequest(returningItems: nil)
    }
}

private struct SavedConfirmation: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.green)
            Text("Saved to Keel").font(.headline)
            Text("Find it in Read Later.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(28)
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
