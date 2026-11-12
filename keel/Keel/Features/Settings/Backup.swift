import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Full backup of everything Keel stores (tasks, notes, habits, meds, attachments…) as a folder you
/// save to Files or iCloud Drive, and a restore that swaps it in the next time Keel opens.
/// Mail is not included: it re-syncs from your accounts.
enum KeelBackup {
    static var pendingDir: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.groupId)?
            .appendingPathComponent("restore-pending", isDirectory: true)
    }

    /// The store file plus its -wal/-shm journal and the folder of large attachments.
    static func storeItems(storeURL: URL) -> [URL] {
        let dir = storeURL.deletingLastPathComponent()
        let base = storeURL.deletingPathExtension().lastPathComponent          // "default"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasPrefix(storeURL.lastPathComponent) || $0 == ".\(base)_SUPPORT" }
            .map { dir.appendingPathComponent($0) }
    }

    @MainActor static func makeDocument() throws -> BackupDocument {
        try KeelStore.container.mainContext.save()
        guard let url = KeelStore.container.configurations.first?.url else { throw CocoaError(.fileNoSuchFile) }
        var children: [String: FileWrapper] = [:]
        for item in storeItems(storeURL: url) {
            let w = try FileWrapper(url: item, options: .immediate)
            w.preferredFilename = item.lastPathComponent
            children[item.lastPathComponent] = w
        }
        let info = "Keel backup\nCreated \(Date().formatted(date: .long, time: .shortened))\nStore: \(url.lastPathComponent)\n"
        children["Keel Backup.txt"] = FileWrapper(regularFileWithContents: Data(info.utf8))
        return BackupDocument(wrapper: FileWrapper(directoryWithFileWrappers: children))
    }

    /// Copies a chosen backup folder aside; it replaces the store before the database opens next launch.
    static func stageRestore(from folder: URL, storeName: String) throws {
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        guard names.contains(storeName) else { throw BackupError.notABackup }
        guard let pending = pendingDir else { throw CocoaError(.fileNoSuchFile) }
        try? FileManager.default.removeItem(at: pending)
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
        for n in names where n != "Keel Backup.txt" {
            try FileManager.default.copyItem(at: folder.appendingPathComponent(n), to: pending.appendingPathComponent(n))
        }
    }

    static func applyPendingRestore(storeURL: URL) {
        guard let pending = pendingDir, FileManager.default.fileExists(atPath: pending.path),
              let names = try? FileManager.default.contentsOfDirectory(atPath: pending.path),
              names.contains(storeURL.lastPathComponent) else { return }
        let fm = FileManager.default
        let dir = storeURL.deletingLastPathComponent()
        // Keep the current data one step back, in case the backup was the wrong one.
        let previous = dir.appendingPathComponent("before-restore", isDirectory: true)
        try? fm.removeItem(at: previous)
        try? fm.createDirectory(at: previous, withIntermediateDirectories: true)
        for item in storeItems(storeURL: storeURL) {
            try? fm.moveItem(at: item, to: previous.appendingPathComponent(item.lastPathComponent))
        }
        for n in names {
            try? fm.moveItem(at: pending.appendingPathComponent(n), to: dir.appendingPathComponent(n))
        }
        try? fm.removeItem(at: pending)
        UserDefaults.standard.set(true, forKey: "backup.justRestored")
    }

    enum BackupError: LocalizedError {
        case notABackup
        var errorDescription: String? { "That folder isn't a Keel backup. Pick the “Keel Backup” folder you saved." }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }
    let wrapper: FileWrapper
    init(wrapper: FileWrapper) { self.wrapper = wrapper }
    init(configuration: ReadConfiguration) throws { wrapper = configuration.file }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { wrapper }
}

struct BackupSection: View {
    @State private var document: BackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var message: String?
    @AppStorage("backup.last") private var lastBackup: Double = 0

    var body: some View {
        Section {
            Button("Back Up Now…", systemImage: "externaldrive.badge.plus") {
                do { document = try KeelBackup.makeDocument(); exporting = true } catch { message = error.localizedDescription }
            }
            Button("Restore from Backup…", systemImage: "clock.arrow.circlepath") { importing = true }
            if lastBackup > 0 {
                LabeledContent("Last backup", value: Date(timeIntervalSince1970: lastBackup).formatted(.relative(presentation: .named)))
            }
        } header: { Text("Backup") } footer: {
            Text("Saves everything Keel keeps on this iPhone (tasks, notes, habits, meds, attachments) to Files or iCloud Drive. Email re-syncs from your accounts, and you'll sign in to them again on a new iPhone.")
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .folder,
                      defaultFilename: "Keel Backup \(Date().formatted(.iso8601.year().month().day()))") { result in
            switch result {
            case .success: lastBackup = Date().timeIntervalSince1970; message = "Backup saved."
            case .failure(let e): message = e.localizedDescription
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result,
                  let name = KeelStore.container.configurations.first?.url.lastPathComponent else { return }
            do {
                try KeelBackup.stageRestore(from: url, storeName: name)
                message = "Ready to restore. Close Keel completely (swipe it away in the app switcher) and open it again to finish."
            } catch { message = error.localizedDescription }
        }
        .alert("Backup", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }
}
