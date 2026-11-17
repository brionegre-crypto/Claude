import SwiftUI
import SwiftData

// MARK: - Things you shared to Keel (from Safari, Notes, Messages, Photos…) show up on Today

/// A list of what just arrived through the share sheet, so it's in front of you on Today instead of quietly
/// filed away. Links go to Read later and text or photos become a page, as before; this remembers them for Today.
@MainActor
enum SharedArrivals {
    struct Arrival: Codable, Identifiable, Hashable {
        enum Kind: String, Codable { case link, note }
        var id: UUID            // the SavedLink's or Note's id
        var kind: Kind
        var title: String
        var detail: String
        var at: Date
    }

    static let key = "share.arrivals"

    static var all: [Arrival] {
        let list: [Arrival] = LocalLog.load(key)
        return list.filter { Date().timeIntervalSince($0.at) < 3 * 86_400 }      // three days, then they've had their moment
    }

    static func add(_ a: Arrival) {
        var list = all.filter { $0.id != a.id }
        list.insert(a, at: 0)
        LocalLog.save(Array(list.prefix(20)), key)
        SharedArrivalsStore.shared.reload()
    }

    static func dismiss(_ id: UUID) { LocalLog.save(all.filter { $0.id != id }, key); SharedArrivalsStore.shared.reload() }
    static func clear() { LocalLog.save([Arrival](), key); SharedArrivalsStore.shared.reload() }
}

/// What Today's card shows; changes as things arrive or are dismissed.
@MainActor @Observable
final class SharedArrivalsStore {
    static let shared = SharedArrivalsStore()
    private(set) var items: [SharedArrivals.Arrival] = SharedArrivals.all
    func reload() { withAnimation(DS.spring) { items = SharedArrivals.all } }
}

struct SharedToKeelCard: View {
    @Environment(\.modelContext) private var ctx
    @State private var store = SharedArrivalsStore.shared
    private var items: [SharedArrivals.Arrival] { store.items }
    @State private var reading: SavedLink?
    @State private var madeTask: UUID?

    var body: some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Shared to Keel", systemImage: "square.and.arrow.down.on.square.fill").font(DS.Font.headline)
                            .foregroundStyle(DS.Palette.accent)
                        Spacer()
                        Button("Clear") { SharedArrivals.clear() }
                            .font(DS.Font.caption).buttonStyle(.borderless)
                    }
                    ForEach(items.prefix(4)) { a in row(a) }
                    if items.count > 4 {
                        Text("+\(items.count - 4) more in Read later and Notes").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
                .padding(DS.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { PremiumSurface(tint: DS.Palette.accent) }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(item: $reading) { link in NavigationStack { ReaderView(link: link) } }
    }

    private func row(_ a: SharedArrivals.Arrival) -> some View {
        HStack(spacing: 10) {
            Button { open(a) } label: {
                HStack(spacing: 10) {
                    Image(systemName: a.kind == .link ? "link" : "doc.text.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: 32, height: 32).background(DS.Palette.accent.gradient, in: .rect(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(a.title).font(DS.Font.body).foregroundStyle(DS.Palette.ink).lineLimit(1)
                        Text("\(a.detail) · \(a.at.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Menu {
                Button("Open", systemImage: "arrow.up.right") { open(a) }
                Button("Make it a task", systemImage: "checkmark.circle") { makeTask(a) }
                Button("Done with it", systemImage: "xmark") { SharedArrivals.dismiss(a.id) }
            } label: {
                Image(systemName: madeTask == a.id ? "checkmark.circle.fill" : "ellipsis.circle").font(.title3)
                    .foregroundStyle(madeTask == a.id ? DS.Palette.calm : DS.Palette.inkSoft)
            }
            .accessibilityLabel("Actions for \(a.title)")
        }
    }

    private func open(_ a: SharedArrivals.Arrival) {
        let id = a.id
        switch a.kind {
        case .link:
            reading = (try? ctx.fetch(FetchDescriptor<SavedLink>(predicate: #Predicate { $0.id == id })))?.first
        case .note:
            AppRouter.shared.openNoteId = id
            AppRouter.shared.tab = .notes
        }
    }

    private func makeTask(_ a: SharedArrivals.Arrival) {
        let t = TaskItem(title: a.kind == .link ? "Read: \(a.title)" : a.title)
        t.notes = a.detail
        ctx.insert(t)
        try? ctx.save()
        Haptics.success()
        withAnimation { madeTask = a.id }
    }
}

extension Notification.Name {
    static let keelSharedArrived = Notification.Name("keel.sharedArrived")
}

// MARK: - Daily affirmation on Today (turn it on or off from Today's menu, or the card's own menu)

enum DailyAffirmation {
    static let toggleKey = "today.affirmation"
    static let builtIn = [
        "My brain works differently, not wrongly.", "Starting is the hardest part, and I can start small.",
        "Rest is productive.", "I've handled hard days before.", "Done is better than perfect.",
        "I don't have to do it all today. Just the next thing.", "My worth isn't my to-do list.",
        "I can ask for help, and that's a strength.", "Progress counts, even when it's small.",
        "I'm allowed to change my plan.", "Forgetting something doesn't make me careless; I'm learning my systems.",
        "Today I'll be as kind to myself as I'd be to a friend.", "Five minutes is enough to begin.",
        "I can do hard things, one step at a time.", "My curiosity and energy are gifts.",
        "It's okay to take a break and come back.", "I finish more than I give myself credit for.",
    ]

    /// Your own affirmations (from the Affirmations tool) if you've kept any, otherwise Keel's.
    static var pool: [String] {
        let mine: [KitItem] = Kit.load("kit.affirmations")
        let texts = mine.map(\.text).filter { !$0.isEmpty }
        return texts.isEmpty ? builtIn : texts
    }

    /// The same one all day, a new one each day.
    static func today(offset: Int = 0) -> String {
        let p = pool
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return p[(day + offset) % max(p.count, 1)]
    }
}

struct DailyAffirmationCard: View {
    @AppStorage(DailyAffirmation.toggleKey) private var on = true
    @State private var offset = 0

    var body: some View {
        if on {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "quote.opening").font(.title3.weight(.bold)).foregroundStyle(.pink.gradient)
                Text(DailyAffirmation.today(offset: offset)).font(.system(.body, design: .serif)).italic()
                    .foregroundStyle(DS.Palette.ink).frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.opacity).id(offset)
                Menu {
                    Button("Show another", systemImage: "arrow.triangle.2.circlepath") { withAnimation(DS.spring) { offset += 1 } }
                    NavigationLink { LazyView(KitAffirmationsView()) } label: { Label("Edit my affirmations", systemImage: "pencil") }
                    Button("Hide daily affirmation", systemImage: "eye.slash") { withAnimation(DS.spring) { on = false } }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(DS.Palette.inkSoft).frame(width: 28, height: 28)
                }
                .accessibilityLabel("Affirmation options")
            }
            .padding(DS.Space.m)
            .background { PremiumSurface(tint: .pink) }
            .onTapGesture { withAnimation(DS.spring) { offset += 1 } }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Today's affirmation: \(DailyAffirmation.today(offset: offset))")
        }
    }
}
