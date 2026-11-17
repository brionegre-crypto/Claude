import SwiftUI
import UserNotifications

// MARK: - Toolkit: shared pieces for Keel's small everyday tools
//
// Each tool keeps its data as settings ("kit.…", which follow you to your other devices through iCloud) or, for
// longer writing and running timers, on this device only ("kitlocal.…").

enum Kit {
    static func load<T: Codable>(_ key: String, as: T.Type = T.self) -> [T] { LocalLog.load(key, as: T.self) }
    static func save<T: Codable>(_ items: [T], _ key: String) { LocalLog.save(items, key) }

    static func dayKey(_ d: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// "4:05" or "1:02:05".
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "1 h 20 min", "35 min".
    static func minutes(_ m: Int) -> String {
        m >= 60 ? (m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min") : "\(m) min"
    }

    static func notify(_ id: String, title: String, body: String, at date: Date, sound: Bool = true) {
        guard date > Date() else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        if sound { c.sound = .default }
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let req = UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        let center = UNUserNotificationCenter.current()
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            try? await center.addKeel(req)
        }
    }

    static func cancel(_ ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    static func cancel(prefix: String) {
        let center = UNUserNotificationCenter.current()
        Task {
            let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Days in a row (ending today, or yesterday if today isn't done yet) that are in `days`.
    static func streak(_ days: Set<String>, today: Date = Date()) -> Int {
        let cal = Calendar.current
        var d = cal.startOfDay(for: today)
        if !days.contains(dayKey(d)) { d = cal.date(byAdding: .day, value: -1, to: d) ?? d }
        var n = 0
        while days.contains(dayKey(d)) {
            n += 1
            d = cal.date(byAdding: .day, value: -1, to: d) ?? d
        }
        return n
    }

    static func money(_ v: Double) -> String { v.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")) }
}

/// The short "what this is and how to use it" at the top of every tool.
struct KitIntro: View {
    let icon: String
    let color: Color
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(color).frame(width: 30)
            Text(text).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10), in: .rect(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

/// A big number with a caption, for streaks and totals.
struct KitStat: View {
    let value: String
    let label: String
    var color: Color = DS.Palette.accent
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit().foregroundStyle(color)
                .contentTransition(.numericText())
            Text(label).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { PremiumSurface(radius: 16) }
        .accessibilityElement(children: .combine)
    }
}

/// A countdown ring that empties as time runs out.
struct KitRing: View {
    let fraction: Double
    let text: String
    var color: Color = DS.Palette.accent
    var size: CGFloat = 200
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: size * 0.07)
            Circle().trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: fraction)
            Text(text).font(.system(size: size * 0.2, weight: .semibold, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// One line of text with a date and an optional tick, used by several list tools.
struct KitItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var date = Date()
    var done = false
    var detail = ""
}

/// A simple list you can add to, tick, swipe away and (optionally) draw one at random from.
struct KitTextListView: View {
    let key: String
    let title: String
    let icon: String
    let color: Color
    let intro: String
    let placeholder: String
    var checkable = false
    var randomTitle: String? = nil
    var seed: [String] = []

    @State private var items: [KitItem] = []
    @State private var draft = ""
    @State private var picked: KitItem?

    var body: some View {
        List {
            Section { KitIntro(icon: icon, color: color, text: intro) }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section {
                HStack {
                    TextField(placeholder, text: $draft, axis: .vertical).onSubmit(add)
                    Button("Add", action: add).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let randomTitle, !items.isEmpty {
                Section {
                    Button {
                        withAnimation(.spring(duration: 0.4)) { picked = items.filter { !$0.done }.randomElement() ?? items.randomElement() }
                        Haptics.tap()
                    } label: { Label(randomTitle, systemImage: "sparkles").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(color)
                    if let picked {
                        Text(picked.text).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .transition(.scale.combined(with: .opacity))
                            .id(picked.id)
                    }
                }
            }
            Section(checkable ? "\(items.filter(\.done).count) of \(items.count) done" : "\(items.count)") {
                ForEach(items) { item in
                    HStack(alignment: .top) {
                        if checkable {
                            Button { toggle(item) } label: {
                                Image(systemName: item.done ? "checkmark.circle.fill" : "circle").foregroundStyle(item.done ? color : DS.Palette.inkSoft)
                            }
                            .buttonStyle(.plain)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.text).strikethrough(checkable && item.done)
                            Text(item.date.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                }
                .onDelete { idx in items.remove(atOffsets: idx); Kit.save(items, key) }
            }
        }
        .navigationTitle(title)
        .onAppear {
            items = Kit.load(key)
            if items.isEmpty, !seed.isEmpty, !UserDefaults.standard.bool(forKey: key + ".seeded") {
                items = seed.map { KitItem(text: $0) }
                Kit.save(items, key)
                UserDefaults.standard.set(true, forKey: key + ".seeded")
            }
        }
    }

    private func add() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        withAnimation { items.insert(KitItem(text: t), at: 0) }
        Kit.save(items, key)
        draft = ""
        Haptics.tap()
    }

    private func toggle(_ item: KitItem) {
        guard let i = items.firstIndex(of: item) else { return }
        items[i].done.toggle()
        Kit.save(items, key)
        if items[i].done { Haptics.success() }
    }
}
