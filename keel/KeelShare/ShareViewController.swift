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

    private struct SharedNote: Codable { var text: String; var images: [String]; var date: Date }

    /// Links go to Read Later; text (from Notes, Messages, anywhere) and images become a Keel note.
    private func save() async {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        var url: String?
        var texts: [String] = []
        var images: [UIImage] = []
        for item in items {
            if let t = item.attributedContentText?.string, !t.isEmpty { texts.append(t) }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let u = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL, !u.isFileURL {
                    url = u.absoluteString
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier)
                    if let img = loaded as? UIImage { images.append(img) }
                    else if let u = loaded as? URL, let d = try? Data(contentsOf: u), let img = UIImage(data: d) { images.append(img) }
                    else if let d = loaded as? Data, let img = UIImage(data: d) { images.append(img) }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let t = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    if t.lowercased().hasPrefix("http"), !t.contains(" ") { url = t } else { texts.append(t) }
                }
            }
        }
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.briangreenejr.keel") else { return finish() }

        if let url, texts.isEmpty || texts.allSatisfy({ $0.contains(url) || $0.count < 200 }), images.isEmpty {
            let file = dir.appendingPathComponent("shared-links.json")
            var queue = (try? JSONDecoder().decode([Shared].self, from: Data(contentsOf: file))) ?? []
            queue.append(Shared(url: url, title: texts.first, date: Date()))
            try? JSONEncoder().encode(queue).write(to: file, options: .atomic)
        } else {
            let imageDir = dir.appendingPathComponent("shared-images", isDirectory: true)
            try? FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
            var names: [String] = []
            for img in images {
                let name = UUID().uuidString + ".jpg"
                if let data = img.jpegData(compressionQuality: 0.8), (try? data.write(to: imageDir.appendingPathComponent(name))) != nil {
                    names.append(name)
                }
            }
            var text = texts.joined(separator: "\n\n")
            if let url { text += (text.isEmpty ? "" : "\n") + url }
            let file = dir.appendingPathComponent("shared-notes.json")
            var queue = (try? JSONDecoder().decode([SharedNote].self, from: Data(contentsOf: file))) ?? []
            queue.append(SharedNote(text: text, images: names, date: Date()))
            try? JSONEncoder().encode(queue).write(to: file, options: .atomic)
        }
        try? await Task.sleep(for: .milliseconds(700))
        finish()
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

private struct SavedConfirmation: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.green)
            Text("Saved to Keel").font(.headline)
            Text("Links go to Read Later; everything else to Notes.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(28)
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
