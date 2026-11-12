import SwiftUI
import SwiftData
import Photos
import FoundationModels

/// Screenshots → tasks: Keel reads text in your recent screenshots (on-device) and suggests tasks.
struct ScreenshotTasksView: View {
    @Environment(\.modelContext) private var ctx
    @State private var suggestions: [Suggestion] = []
    @State private var scanning = false
    @State private var status = ""

    struct Suggestion: Identifiable {
        let id = UUID()
        let image: UIImage
        var tasks: [String]
        var added: Set<String> = []
    }

    var body: some View {
        List {
            Section {
                Button(scanning ? "Reading screenshots…" : "Scan recent screenshots") { Task { await scan() } }
                    .disabled(scanning)
            } footer: {
                Text(status.isEmpty ? "Looks at screenshots from the last 7 days. Everything happens on this iPhone." : status)
            }
            ForEach($suggestions) { $s in
                Section {
                    HStack(alignment: .top, spacing: DS.Space.m) {
                        Image(uiImage: s.image).resizable().scaledToFill().frame(width: 60, height: 100).clipShape(.rect(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(s.tasks, id: \.self) { t in
                                HStack {
                                    Text(t).font(DS.Font.body)
                                    Spacer()
                                    Button {
                                        QuickAdd.create(t, in: ctx)
                                        s.added.insert(t)
                                        Haptics.success()
                                    } label: {
                                        Image(systemName: s.added.contains(t) ? "checkmark.circle.fill" : "plus.circle")
                                            .foregroundStyle(s.added.contains(t) ? DS.Palette.calm : DS.Palette.accent)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(s.added.contains(t))
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("From Screenshots")
    }

    private func scan() async {
        scanning = true; defer { scanning = false }
        let auth = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard auth == .authorized || auth == .limited else { status = "Keel needs Photos access (Settings → Keel → Photos)."; return }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0 AND creationDate > %@",
                                        PHAssetMediaSubtype.photoScreenshot.rawValue, Date().addingTimeInterval(-7 * 86_400) as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 15
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        var found: [Suggestion] = []
        var images: [UIImage] = []
        assets.enumerateObjects { asset, _, _ in
            let opts = PHImageRequestOptions()
            opts.isSynchronous = true
            opts.deliveryMode = .highQualityFormat
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 1200, height: 2600), contentMode: .aspectFit, options: opts) { img, _ in
                if let img { images.append(img) }
            }
        }
        for img in images {
            let text = await NoteMedia.recognizeText(img)
            guard text.count > 20 else { continue }
            let tasks = await ScreenshotAI.tasks(from: text)
            if !tasks.isEmpty { found.append(Suggestion(image: img, tasks: tasks)) }
        }
        suggestions = found
        status = found.isEmpty ? "No tasks found in recent screenshots." : "Tap + to add a suggestion."
    }
}

enum ScreenshotAI {
    @Generable
    struct Found {
        @Guide(description: "Concrete to-dos or plans found in the text, written as short tasks with any date or time, e.g. 'Pay electric bill Friday'. Empty if none.", .maximumCount(5))
        var tasks: [String]
    }

    @MainActor
    static func tasks(from text: String) async -> [String] {
        guard AIRouter.shared.onDeviceAvailable else { return [] }
        let session = LanguageModelSession(instructions: "You find actionable tasks, deadlines and plans in text from phone screenshots. Ignore ads, menus and UI labels.")
        return (try? await session.respond(to: String(text.prefix(4_000)), generating: Found.self).content.tasks) ?? []
    }
}
