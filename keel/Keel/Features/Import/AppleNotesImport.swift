import Foundation

// MARK: - Apple Notes, all at once (Keel on Mac)
//
// Apple doesn't offer a sign-in or any way for an app to read Apple Notes on iPhone or iPad. On a Mac it does:
// after you allow it once, Keel can ask the Notes app for every note. So "Import all of Apple Notes" lives in
// Keel on your Mac: one tap, one "Allow" from macOS, and every note comes in with its folder, dates and pictures.
// They then sync to Keel on your iPhone through iCloud like everything else.

enum AppleNotesImport {
    /// True where Keel can read Apple Notes itself (Keel on Mac).
    static var available: Bool {
        #if targetEnvironment(macCatalyst)
        return NSClassFromString("NSAppleScript") != nil
        #else
        return false
        #endif
    }

    enum Failure: LocalizedError {
        case notAllowed, unavailable
        var errorDescription: String? {
            switch self {
            case .notAllowed: "Keel isn't allowed to read Notes yet. Open System Settings → Privacy & Security → Automation, turn on Notes under Keel, then try again."
            case .unavailable: "Importing straight from Apple Notes works in Keel on your Mac."
            }
        }
    }

    private static let unit = "\u{1F}", record = "\u{1E}"

    /// Reads every note (except Recently Deleted) into an import, ready to preview. Locked notes can't be read
    /// by any app; they're counted and listed as a note in the preview.
    @MainActor
    static func read(progress: @escaping (Int, Int) -> Void) async throws -> ImportBundle {
        guard available else { throw Failure.unavailable }
        guard let total = run("tell application \"Notes\" to return (count of notes) as string").flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) else {
            throw Failure.notAllowed
        }
        var pages: [ImportedPage] = []
        var locked: [String] = []
        let batch = 20
        var start = 1
        while start <= total {
            let end = min(start + batch - 1, total)
            guard let raw = run(script(from: start, to: end)) else { throw Failure.notAllowed }
            for rec in raw.components(separatedBy: record) where !rec.isEmpty {
                let f = rec.components(separatedBy: unit)
                guard f.count >= 3 else { continue }
                let folder = f[2]
                if folder == "Recently Deleted" { continue }
                if f[0] == "L" { locked.append(f[1]); continue }
                guard f.count >= 6 else { continue }
                pages.append(page(index: pages.count, title: f[1], folder: folder, created: f[3], modified: f[4], html: f[5...].joined(separator: unit)))
            }
            progress(end, total)
            start = end + 1
            await Task.yield()
        }
        var warnings: [String] = []
        if !locked.isEmpty {
            warnings.append("\(locked.count) locked note\(locked.count == 1 ? "" : "s") can't be read by any app (\(locked.prefix(3).joined(separator: ", "))\(locked.count > 3 ? "…" : "")). Unlock them in Notes to bring them in.")
        }
        warnings.append("Checklists come in as lists, since Notes doesn't share which items are ticked.")
        return ImportBundle(source: .markdown, name: "Apple Notes", pages: pages, warnings: warnings)
    }

    @MainActor private static func page(index: Int, title: String, folder: String, created: String, modified: String, html: String) -> ImportedPage {
        let r = MarkdownImport.parse(HTMLImport.toMarkdown(html), dir: "")
        var blocks = r.blocks
        // Notes repeats the title as the first line of the body.
        if let first = blocks.first, RichText.plain(first.text).trimmingCharacters(in: .whitespaces) == title.trimmingCharacters(in: .whitespaces) {
            blocks.removeFirst()
        }
        var p = ImportedPage(key: "applenotes:\(index)", title: title.isEmpty ? "Untitled" : title, blocks: blocks)
        // Pictures in Notes come inside the note as data; keep them, drop any that can't be read.
        for (id, ref) in r.images where ref.hasPrefix("data:") {
            if let comma = ref.firstIndex(of: ","), let d = Data(base64Encoded: String(ref[ref.index(after: comma)...]), options: .ignoreUnknownCharacters) {
                p.imageData[id] = d
            }
        }
        p.blocks.removeAll { $0.kind == .image && p.imageData[$0.id] == nil }
        p.folder = folder == "Notes" ? nil : folder
        p.created = ImportDates.parse(created)
        p.updated = ImportDates.parse(modified)
        return p
    }

    private static func script(from a: Int, to b: Int) -> String {
        """
        set US to character id 31
        set RS to character id 30
        set out to ""
        tell application "Notes"
            set allNotes to notes
            repeat with i from \(a) to \(b)
                set n to item i of allNotes
                set f to ""
                try
                    set f to name of container of n
                end try
                set isLocked to false
                try
                    set isLocked to password protected of n
                end try
                if isLocked then
                    set out to out & "L" & US & (name of n) & US & f & RS
                else
                    set c to ""
                    set m to ""
                    try
                        set c to (creation date of n) as «class isot» as string
                        set m to (modification date of n) as «class isot» as string
                    end try
                    set out to out & "N" & US & (name of n) & US & f & US & c & US & m & US & (body of n) & RS
                end if
            end repeat
        end tell
        return out
        """
    }

    /// Runs an AppleScript through macOS's script support, looked up at run time so the iPhone app doesn't
    /// depend on it. Returns nil if macOS refused (Keel not allowed to control Notes) or it failed.
    @MainActor
    private static func run(_ source: String) -> String? {
        guard let cls = NSClassFromString("NSAppleScript") as AnyObject?,
              let made = cls.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              let script = made.perform(NSSelectorFromString("initWithSource:"), with: source)?.takeUnretainedValue(),
              let result = script.perform(NSSelectorFromString("executeAndReturnError:"), with: nil)?.takeUnretainedValue()
        else { return nil }
        return (result as? NSObject)?.value(forKey: "stringValue") as? String
    }
}
