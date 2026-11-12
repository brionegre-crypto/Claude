import SwiftUI
import SwiftData
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

/// Photos and files on a task: the receipt to submit, the form to fill in, the screenshot of the bug.
struct TaskAttachmentsSection: View {
    let task: TaskItem
    @Environment(\.modelContext) private var ctx
    @Query private var all: [TaskAttachment]
    @State private var photos: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var preview: URL?

    private var mine: [TaskAttachment] { all.filter { $0.taskId == task.id }.sorted { $0.createdAt < $1.createdAt } }

    var body: some View {
        Section("Attachments") {
            if !mine.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(mine) { a in
                            Button { open(a) } label: { thumb(a) }
                                .buttonStyle(.plain)
                                .contextMenu { Button("Remove", systemImage: "trash", role: .destructive) { ctx.delete(a) } }
                        }
                    }
                }
            }
            HStack {
                PhotosPicker(selection: $photos, maxSelectionCount: 6, matching: .images) { Label("Photo", systemImage: "photo") }
                Spacer()
                Button { importing = true } label: { Label("File", systemImage: "doc") }
            }
            .buttonStyle(.borderless)
        }
        .onChange(of: photos) { _, items in
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data),
                       let jpg = img.jpegData(compressionQuality: 0.8) {
                        ctx.insert(TaskAttachment(taskId: task.id, data: jpg, filename: "Photo.jpg", kind: "photo"))
                    }
                }
                photos = []
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), data.count < 25_000_000 {
                    ctx.insert(TaskAttachment(taskId: task.id, data: data, filename: url.lastPathComponent, kind: "file"))
                }
            }
        }
        .quickLookPreview($preview)
    }

    @ViewBuilder private func thumb(_ a: TaskAttachment) -> some View {
        if a.kind == "photo", let img = UIImage(data: a.data) {
            Image(uiImage: img).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(.rect(cornerRadius: 8))
        } else {
            VStack(spacing: 4) {
                Image(systemName: "doc.fill").font(.title2).foregroundStyle(DS.Palette.accent)
                Text(a.filename).scaledFont(size: 9).lineLimit(2).multilineTextAlignment(.center)
            }
            .frame(width: 64, height: 64)
            .background(DS.Palette.elevated, in: .rect(cornerRadius: 8))
        }
    }

    private func open(_ a: TaskAttachment) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(a.id.uuidString)-\(a.filename)")
        if (try? a.data.write(to: url)) != nil { preview = url }
    }
}
