import SwiftUI
import UserNotifications

// MARK: - Read statuses (opt-in): know when your email was opened
//
// Off until you turn it on (Settings → Mail, or per email while writing). A tracked email goes out with a
// 1×1 image from your own Keel server; when the reader's mail app loads it, Keel counts an open and tells you.
// Opens are a hint, not proof: Apple Mail's privacy protection can load images without the person reading,
// and some apps block images.

struct TrackedMail: Codable, Identifiable, Hashable {
    var id: String
    var to: String
    var subject: String
    var sentAt: Date
    var opens: [Date] = []
    var via: [String] = []
    var notified = false
}

@MainActor
enum ReadStatus {
    static let onKey = "mail.readStatus"
    static let logKey = "mail.tracked"
    static var isOn: Bool { UserDefaults.standard.bool(forKey: onKey) }
    static var available: Bool { KeelServer.isConfigured }

    static var all: [TrackedMail] { LocalLog.load(logKey) }
    private static func save(_ list: [TrackedMail]) { LocalLog.save(Array(list.suffix(300)), logKey) }

    /// Registers a new tracked email with your Keel server and returns the image address to put in it.
    static func prepare(to: String, subject: String) async -> URL? {
        guard let base = KeelServer.baseURL, let code = KeelServer.accessCode else { return nil }
        let id = UUID().uuidString.lowercased()
        var req = URLRequest(url: base.appendingPathComponent("r/new"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(code)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["id": id])
        req.timeoutInterval = 8
        guard let (_, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        var list = all
        list.append(TrackedMail(id: id, to: to, subject: subject, sentAt: Date()))
        save(list)
        return base.appendingPathComponent("r/\(id).gif")
    }

    /// Asks your server about recent tracked emails; says so (once) the first time each is opened.
    static func refresh(force: Bool = false) async {
        guard available, !all.isEmpty else { return }
        if !force, !Throttle.due("readstatus.refresh", every: 300) { return }
        guard let base = KeelServer.baseURL, let code = KeelServer.accessCode else { return }
        let recent = all.filter { Date().timeIntervalSince($0.sentAt) < 30 * 86_400 }.suffix(100)
        guard !recent.isEmpty else { return }
        var comps = URLComponents(url: base.appendingPathComponent("r/status"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "ids", value: recent.map(\.id).joined(separator: ","))]
        guard let url = comps?.url else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(code)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return }
        var list = all
        for i in list.indices {
            guard let r = obj[list[i].id] else { continue }
            let opens = (r["opens"] as? [Double] ?? (r["opens"] as? [Int])?.map(Double.init) ?? []).map { Date(timeIntervalSince1970: $0 / 1000) }
            list[i].opens = opens
            list[i].via = r["via"] as? [String] ?? []
            if !opens.isEmpty && !list[i].notified {
                list[i].notified = true
                notify(list[i])
            }
        }
        save(list)
    }

    private static func notify(_ m: TrackedMail) {
        let c = UNMutableNotificationContent()
        c.title = "\(m.to) opened your email"
        c.body = m.subject.isEmpty ? "(no subject)" : m.subject
        c.sound = nil
        UNUserNotificationCenter.current().addKeel(UNNotificationRequest(identifier: "read.\(m.id)", content: c, trigger: nil))
    }

    /// The tracked email for a sent subject and recipient, if any (for showing "Opened" on it).
    static func status(subject: String, to: String) -> TrackedMail? {
        all.last { $0.subject == subject && $0.to.lowercased().contains(to.lowercased()) }
    }
}

struct ReadStatusView: View {
    @State private var list: [TrackedMail] = ReadStatus.all.reversed()
    @AppStorage(ReadStatus.onKey) private var on = false

    var body: some View {
        List {
            Section {
                Toggle("Track opens on emails I send", isOn: $on).disabled(!ReadStatus.available)
            } footer: {
                Text(ReadStatus.available
                     ? "Tracked emails carry an invisible image from your Keel server; when it loads, you'll see Opened here and get a quiet alert. You can switch it on or off for each email while writing. Opens are a hint: Apple Mail's privacy protection can load images without anyone reading, and some people block images."
                     : "Read statuses need your Keel server. Sign in to Keel in Settings → Account first.")
            }
            if list.isEmpty {
                Section { Text("No tracked emails yet.").foregroundStyle(DS.Palette.inkSoft) }
            }
            ForEach(list) { m in
                HStack(spacing: 12) {
                    Image(systemName: m.opens.isEmpty ? "envelope" : "envelope.open.fill")
                        .foregroundStyle(m.opens.isEmpty ? DS.Palette.inkSoft : DS.Palette.calm).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.subject.isEmpty ? "(no subject)" : m.subject).lineLimit(1)
                        Text("To \(m.to) · sent \(m.sentAt.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                        if let last = m.opens.last {
                            Text("Opened \(m.opens.count == 1 ? "once" : "\(m.opens.count) times") · last \(last.formatted(.relative(presentation: .named)))\(m.via.last.map { " in \($0)" } ?? "")")
                                .font(.caption.weight(.semibold)).foregroundStyle(DS.Palette.calm)
                        } else {
                            Text("Not opened yet").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                }
            }
        }
        .navigationTitle("Read statuses")
        .refreshable { await ReadStatus.refresh(force: true); list = ReadStatus.all.reversed() }
        .task { await ReadStatus.refresh(force: true); list = ReadStatus.all.reversed() }
    }
}
