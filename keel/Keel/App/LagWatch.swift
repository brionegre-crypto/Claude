import SwiftUI

/// Notices when the screen freezes (the main thread busy for more than a quarter second) and notes where:
/// which tab was open and whether sync was running. Kept on this device, newest 50, in Settings → Data & Storage
/// → Slow moments, so you can send the list and the exact cause gets fixed. Costs one tiny check per second.
final class LagWatch: @unchecked Sendable {
    static let shared = LagWatch()
    private let queue = DispatchQueue(label: "keel.lagwatch", qos: .utility)
    private var timer: DispatchSourceTimer?
    private static let key = "lag.moments.v1"

    struct Moment: Codable, Identifiable {
        var at: Date
        var ms: Int
        var place: String
        var syncing: Bool
        var id: Date { at }
    }

    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 5, repeating: 1.0, leeway: .milliseconds(100))
        t.setEventHandler {
            let sent = Date()
            DispatchQueue.main.async {
                let ms = Int(Date().timeIntervalSince(sent) * 1000)
                guard ms >= 250, UIApplication.shared.applicationState == .active else { return }
                MainActor.assumeIsolated {
                    LagWatch.record(Moment(at: sent, ms: ms, place: LagWatch.name(AppRouter.shared.tab), syncing: SyncEngine.shared.isSyncing))
                }
            }
        }
        t.resume()
        timer = t
    }

    @MainActor static func record(_ m: Moment) {
        var all = moments
        all.insert(m, at: 0)
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(all.prefix(50))), forKey: key)
    }

    static var moments: [Moment] {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([Moment].self, from: $0) } ?? []
    }

    @MainActor static func name(_ t: RootView.Tab) -> String {
        switch t {
        case .tool(let id): return id
        default: return String(describing: t)
        }
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }

    @MainActor static var report: String {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .medium
        return (["Keel slow moments (\(KeelDiagnostics.version))"] + moments.map {
            "\(f.string(from: $0.at)) · \($0.ms) ms · \($0.place)\($0.syncing ? " · during sync" : "")"
        }).joined(separator: "\n")
    }
}

/// Settings → Data & Storage → Slow moments.
struct LagMomentsView: View {
    @State private var moments = LagWatch.moments
    var body: some View {
        List {
            Section {
                if moments.isEmpty {
                    Text("No slow moments recorded. When the screen freezes for more than a quarter second, it shows up here.")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                ForEach(moments) { m in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(m.ms) ms on \(m.place.capitalized)").font(.subheadline.weight(.semibold))
                            Text(m.at.formatted(date: .abbreviated, time: .standard) + (m.syncing ? " · during sync" : ""))
                                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                        Spacer()
                        Circle().fill(m.ms > 1000 ? Color.red : m.ms > 500 ? .orange : .yellow).frame(width: 8, height: 8)
                    }
                }
            } footer: { Text("Kept only on this device. Share the list so the cause can be fixed.") }
            if !moments.isEmpty {
                Section {
                    ShareLink(item: LagWatch.report) { Label("Share slow moments", systemImage: "square.and.arrow.up") }
                    Button("Clear", role: .destructive) { LagWatch.clear(); moments = [] }
                }
            }
        }
        .navigationTitle("Slow moments")
        .premiumBackground(.gray)
    }
}
