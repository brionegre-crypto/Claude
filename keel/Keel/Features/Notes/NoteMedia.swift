import SwiftUI
import SwiftData
import PhotosUI
import PencilKit
import VisionKit
import Vision

/// A photo, sketch or scanned page inside a note.
struct ImageBlockView: View {
    let attachmentId: String?
    @Query private var attachments: [NoteAttachment]
    @State private var expanded = false

    private var attachment: NoteAttachment? {
        guard let s = attachmentId, let id = UUID(uuidString: s) else { return nil }
        return attachments.first { $0.id == id }
    }

    var body: some View {
        if let a = attachment, let img = UIImage(data: a.data) {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 320)
                .clipShape(.rect(cornerRadius: DS.Radius.chip))
                .background(a.kind == "sketch" ? Color.white : .clear, in: .rect(cornerRadius: DS.Radius.chip))
                .onTapGesture { expanded = true }
                .fullScreenCover(isPresented: $expanded) {
                    ZStack(alignment: .topTrailing) {
                        Color.black.ignoresSafeArea()
                        Image(uiImage: img).resizable().scaledToFit()
                        Button { expanded = false } label: { Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.white) }.accessibilityLabel("Close")
                            .padding()
                    }
                }
                .accessibilityLabel(a.kind == "scan" ? "Scanned page" : a.kind == "sketch" ? "Sketch" : "Photo")
        } else {
            Label("Image unavailable", systemImage: "photo").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
        }
    }
}

@MainActor
enum NoteMedia {
    /// Saves image data as an attachment and appends an image block to the note.
    static func add(_ data: Data, kind: String, to note: Note, ctx: ModelContext, text: String = "") {
        let a = NoteAttachment(noteId: note.id, data: data, kind: kind)
        a.recognizedText = text
        ctx.insert(a)
        note.blocks.append(NoteBlock(kind: .image, text: "", refId: a.id.uuidString))
        if !text.isEmpty {
            note.blocks.append(NoteBlock(kind: .quote, text: text))   // scanned text, editable and searchable
        }
        note.updatedAt = Date()
        Haptics.success()
    }

    /// Downscales big photos so notes stay fast.
    static func jpeg(_ image: UIImage, maxSide: CGFloat = 2048) -> Data? {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.8)
    }

    /// On-device text recognition for scanned pages.
    static func recognizeText(_ image: UIImage) async -> String {
        guard let cg = image.cgImage else { return "" }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: cg).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }
}

/// Finger or Apple Pencil sketch.
struct SketchSheet: View {
    var onSave: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var canvas = PKCanvasView()

    var body: some View {
        NavigationStack {
            CanvasRepresentable(canvas: canvas)
                .background(Color.white)
                .navigationTitle("Sketch")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            let bounds = canvas.drawing.bounds.insetBy(dx: -20, dy: -20)
                            let image = canvas.drawing.image(from: bounds.isEmpty ? canvas.bounds : bounds, scale: 2)
                            let renderer = UIGraphicsImageRenderer(size: image.size)
                            let flattened = renderer.image { ctx in
                                UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: image.size))
                                image.draw(at: .zero)
                            }
                            if let data = flattened.pngData() { onSave(data) }
                            dismiss()
                        }
                    }
                }
        }
    }
}

private struct CanvasRepresentable: UIViewRepresentable {
    let canvas: PKCanvasView
    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .white
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        let picker = PKToolPicker()
        picker.setVisible(true, forFirstResponder: canvas)
        picker.addObserver(canvas)
        context.coordinator.picker = picker
        canvas.becomeFirstResponder()
        return canvas
    }
    func updateUIView(_ view: PKCanvasView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var picker: PKToolPicker? }
}

/// Apple's document camera: finds page edges, flattens and cleans up the scan.
struct DocumentScanner: UIViewControllerRepresentable {
    var onScan: ([UIImage]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: ([UIImage]) -> Void
        init(onScan: @escaping ([UIImage]) -> Void) { self.onScan = onScan }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onScan((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
            controller.dismiss(animated: true)
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { controller.dismiss(animated: true) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { controller.dismiss(animated: true) }
    }
}
