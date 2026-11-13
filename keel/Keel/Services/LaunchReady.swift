import SwiftUI
import SwiftData
import MetricKit

// MARK: - Crash & performance reports (opt-in)

/// Apple's MetricKit hands Keel crash, hang and slowness reports from this device (never your content).
/// They're kept on the device; with “Share crash reports” on, they're also sent to your Keel server.
final class KeelDiagnostics: NSObject, MXMetricManagerSubscriber {
    static let shared = KeelDiagnostics()
    static let shareKey = "diagnostics.share"

    static var folder: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func start() { MXMetricManager.shared.add(self) }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads {
            let data = p.jsonRepresentation()
            let url = Self.folder.appendingPathComponent("report-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(4)).json")
            try? data.write(to: url)
            if UserDefaults.standard.bool(forKey: Self.shareKey), let text = String(data: data, encoding: .utf8) {
                Task { @MainActor in _ = try? await KeelCloud.call("diagnostics", method: "POST", body: ["report": text, "version": Self.version], auth: true) }
            }
        }
        // Keep the newest 20.
        let files = ((try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in files.dropFirst(20) { try? FileManager.default.removeItem(at: old) }
    }

    static var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    static var reports: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}

struct DiagnosticsSection: View {
    @AppStorage(KeelDiagnostics.shareKey) private var share = false
    @State private var count = KeelDiagnostics.reports.count

    var body: some View {
        Section {
            Toggle("Share crash reports", isOn: $share)
            LabeledContent("Reports on this device", value: "\(count)")
            if let latest = KeelDiagnostics.reports.first {
                ShareLink(item: latest) { Label("Send the latest report", systemImage: "square.and.arrow.up") }
            }
        } header: { Text("Crash reports") } footer: {
            Text("When Keel crashes or freezes, Apple gives it a technical report (what code was running, never your notes, mail or tasks). With sharing on, reports go to your Keel server so problems get fixed fast.")
        }
    }
}

// MARK: - Email to Keel

/// Forward or send any email to yourname+keel@yourdomain (Gmail and Outlook deliver “+” addresses to your own inbox).
/// Keel turns it into a task (or a note when the subject starts with “Note:”) and archives the email.
/// Sending yourself an email with a subject starting “Task:” or “Note:” works with any provider.
@MainActor
enum EmailToKeel {
    static func address(for a: MailAccount) -> String? {
        guard a.provider == .gmail || a.provider == .outlook, let at = a.address.firstIndex(of: "@") else { return nil }
        return String(a.address[..<at]) + "+keel" + String(a.address[at...])
    }

    static func process(_ fresh: [EmailMessage], accounts: [MailAccount], ctx: ModelContext) {
        let mine = Set(accounts.map { $0.address.lowercased() })
        for e in fresh {
            let to = e.toLine.lowercased()
            var subject = e.subject.trimmingCharacters(in: .whitespaces)
            let lower = subject.lowercased()
            let toKeel = to.contains("+keel@")
            let selfCommand = mine.contains(e.from.lowercased()) && (lower.hasPrefix("task:") || lower.hasPrefix("note:") || lower.hasPrefix("keel:"))
            guard toKeel || selfCommand else { continue }
            let asNote = lower.hasPrefix("note:")
            for p in ["task:", "note:", "keel:", "fwd:", "fw:"] where subject.lowercased().hasPrefix(p) {
                subject = String(subject.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
            }
            let body = GmailProvider.stripQuotedReply(e.bodyPlain).trimmingCharacters(in: .whitespacesAndNewlines)
            if asNote {
                let n = Note(title: subject.isEmpty ? "From email" : subject,
                             blocks: body.split(separator: "\n", omittingEmptySubsequences: false).prefix(400).map { NoteBlock(kind: .text, text: String($0)) })
                n.folder = "Inbox notes"
                ctx.insert(n)
            } else {
                let t = QuickAdd.create(subject.isEmpty ? "Follow up on email" : subject, in: ctx, defaultDue: nil)
                t.sourceEmailId = e.id
                if !body.isEmpty { t.notes = String(body.prefix(2_000)) }
            }
            e.isArchived = true
        }
    }
}

struct EmailToKeelView: View {
    @Query private var accounts: [MailAccount]
    var body: some View {
        List {
            Section {
                ForEach(accounts) { a in
                    if let addr = EmailToKeel.address(for: a) {
                        HStack {
                            Text(addr).font(.callout.monospaced()).textSelection(.enabled)
                            Spacer()
                            Button { UIPasteboard.general.string = addr; Haptics.tap() } label: { Image(systemName: "doc.on.doc") }
                                .buttonStyle(.borderless).accessibilityLabel("Copy address")
                        }
                    }
                }
            } header: { Text("Your Keel addresses") } footer: {
                Text("Forward any email to one of these and it becomes a task, with the email attached. Start the subject with “Note:” to save it as a note instead. Save the address as a contact named Keel to forward faster.")
            }
            Section("Works with any email account") {
                Label("Email yourself with a subject starting “Task:” or “Note:”", systemImage: "envelope.badge")
            }
        }
        .navigationTitle("Email to Keel")
    }
}

// MARK: - Export everything

/// One ZIP with every note as Markdown (in its folders), and tasks, habits, journal and food as spreadsheets.
@MainActor
enum ExportAll {
    static func make(ctx: ModelContext) throws -> URL {
        var zip = ZipWriter()
        func csv(_ rows: [[String]]) -> Data {
            Data(rows.map { $0.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") }.joined(separator: "\n").utf8)
        }
        func safe(_ s: String) -> String {
            let t = s.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-").trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? "Untitled" : String(t.prefix(80))
        }
        var used = Set<String>()
        for n in (try? ctx.fetch(FetchDescriptor<Note>())) ?? [] where !n.isLocked && !n.isTemplate {
            let folder = n.folder.map { $0.split(separator: "/").map { safe(String($0)) }.joined(separator: "/") + "/" } ?? ""
            var path = "Notes/\(folder)\(safe(n.title)).md"
            var i = 2
            while used.contains(path) { path = "Notes/\(folder)\(safe(n.title)) \(i).md"; i += 1 }
            used.insert(path)
            zip.add(path, Data(NoteExport.markdown(n).utf8))
        }
        let iso = ISO8601DateFormatter()
        let tasks = (try? ctx.fetch(FetchDescriptor<TaskItem>())) ?? []
        zip.add("Tasks.csv", csv([["Title", "List", "Due", "Done", "Priority", "Tags", "Notes"]] + tasks.map {
            [$0.title, $0.listName, $0.dueDate.map { iso.string(from: $0) } ?? "", $0.isDone ? "yes" : "no", "\($0.priority.rawValue)", TaskMeta.visibleTags($0).joined(separator: " "), $0.notes]
        }))
        let habits = (try? ctx.fetch(FetchDescriptor<Habit>())) ?? []
        let logs = (try? ctx.fetch(FetchDescriptor<HabitLog>())) ?? []
        zip.add("Habits.csv", csv([["Habit", "Completed"]] + logs.map { l in [habits.first { $0.id == l.habitId }?.name ?? "", iso.string(from: l.completedAt)] }))
        let checkins = (try? ctx.fetch(FetchDescriptor<CheckIn>())) ?? []
        zip.add("Journal.csv", csv([["Day", "Mood", "Energy", "Highlight"]] + checkins.map { [iso.string(from: $0.day), "\($0.mood)", $0.energy.map { String($0) } ?? "", $0.highlight] }))
        let food = (try? ctx.fetch(FetchDescriptor<FoodEntry>())) ?? []
        zip.add("Food.csv", csv([["Date", "Food", "Meal", "Calories", "Protein g", "Verdict"]] + food.map {
            [iso.string(from: $0.date), $0.name, $0.meal, $0.facts.calories.map { String(Int($0)) } ?? "", $0.facts.protein.map { String(Int($0)) } ?? "", $0.verdictRaw]
        }))
        zip.add("README.txt", Data("Exported from Keel on \(Date().formatted()).\nNotes are Markdown files in their folders. Locked notes are not included.\n".utf8))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Keel Export \(Date().formatted(.iso8601.year().month().day())).zip")
        try zip.finish().write(to: url)
        return url
    }
}

/// A minimal ZIP writer (stored, no compression): enough for an export anyone can open.
struct ZipWriter {
    private var out = Data()
    private var central = Data()
    private var count: UInt16 = 0

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }
    private static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in d { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
    private static func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    mutating func add(_ path: String, _ data: Data) {
        let name = Data(path.utf8)
        let crc = Self.crc32(data)
        let offset = UInt32(out.count)
        var local = Data()
        local += Self.le32(0x0403_4B50); local += Self.le16(20); local += Self.le16(0x0800); local += Self.le16(0)
        local += Self.le16(0); local += Self.le16(0x21)                       // time, date (1980-01-01)
        local += Self.le32(crc); local += Self.le32(UInt32(data.count)); local += Self.le32(UInt32(data.count))
        local += Self.le16(UInt16(name.count)); local += Self.le16(0)
        out += local; out += name; out += data
        var c = Data()
        c += Self.le32(0x0201_4B50); c += Self.le16(20); c += Self.le16(20); c += Self.le16(0x0800); c += Self.le16(0)
        c += Self.le16(0); c += Self.le16(0x21)
        c += Self.le32(crc); c += Self.le32(UInt32(data.count)); c += Self.le32(UInt32(data.count))
        c += Self.le16(UInt16(name.count)); c += Self.le16(0); c += Self.le16(0); c += Self.le16(0); c += Self.le16(0)
        c += Self.le32(0); c += Self.le32(offset)
        central += c; central += name
        count += 1
    }

    func finish() -> Data {
        var d = out
        let start = UInt32(d.count)
        d += central
        d += Self.le32(0x0605_4B50); d += Self.le16(0); d += Self.le16(0)
        d += Self.le16(count); d += Self.le16(count)
        d += Self.le32(UInt32(central.count)); d += Self.le32(start); d += Self.le16(0)
        return d
    }
}
