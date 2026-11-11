import WidgetKit
import SwiftUI
import ActivityKit

@main
struct KeelWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        NextEventWidget()
        FocusLiveActivity()
    }
}

private let accent = Color(red: 0.36, green: 0.42, blue: 0.98)
private let focusColor = Color(red: 0.42, green: 0.36, blue: 0.95)

private extension Color {
    init(hex: String) {
        let v = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x5B8DEF
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

// MARK: - Timeline

struct KeelEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    var upcoming: [WidgetSnapshot.Event] { snapshot.events.filter { $0.end > date } }
}

struct KeelProvider: TimelineProvider {
    func placeholder(in context: Context) -> KeelEntry { KeelEntry(date: Date(), snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (KeelEntry) -> Void) {
        completion(KeelEntry(date: Date(), snapshot: context.isPreview ? .sample : (WidgetSnapshot.load() ?? .sample)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KeelEntry>) -> Void) {
        let snap = WidgetSnapshot.load() ?? WidgetSnapshot()
        // A fresh entry every 15 minutes so "next event" rolls forward even if Keel isn't opened.
        let entries = (0..<8).map { KeelEntry(date: Date().addingTimeInterval(Double($0) * 900), snapshot: snap) }
        completion(Timeline(entries: entries, policy: .after(Date().addingTimeInterval(7_200))))
    }
}

// MARK: - Today widget ("Just One Thing" + what's next)

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KeelToday", provider: KeelProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) { LinearGradient(colors: [accent.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom) }
                .widgetURL(URL(string: "com.keel.app://today"))
        }
        .configurationDisplayName("Just One Thing")
        .description("Your single best next step, and what's coming up.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct TodayWidgetView: View {
    let entry: KeelEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(entry.snapshot.nextThing.map { "◆ \($0)" } ?? "Nothing urgent")
        case .accessoryCircular:
            let total = max(1, entry.snapshot.tasksLeftToday + entry.snapshot.tasksDoneToday)
            Gauge(value: Double(entry.snapshot.tasksDoneToday), in: 0...Double(total)) {
                Image(systemName: "checkmark")
            } currentValueLabel: {
                Text("\(entry.snapshot.tasksLeftToday)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("ONE THING").font(.caption2.weight(.semibold))
                Text(entry.snapshot.nextThing ?? "Nothing urgent").font(.headline).lineLimit(2)
            }
        case .systemMedium:
            HStack(alignment: .top, spacing: 14) {
                oneThing
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("UP NEXT").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    if entry.upcoming.isEmpty { Text("Clear calendar").font(.caption).foregroundStyle(.secondary) }
                    ForEach(entry.upcoming.prefix(3), id: \.self) { e in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(Color(hex: e.colorHex)).frame(width: 3, height: 26)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(e.title).font(.caption.weight(.semibold)).lineLimit(1)
                                Text(e.start, style: .time).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            oneThing
        }
    }

    private var oneThing: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("JUST ONE THING").font(.caption2.weight(.bold)).foregroundStyle(accent)
            Text(entry.snapshot.nextThing ?? "Nothing urgent. Enjoy the space.")
                .font(.system(.headline, design: .rounded)).lineLimit(3)
            if let step = entry.snapshot.nextThingStep {
                Text("Start: \(step)").font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Text("\(entry.snapshot.tasksLeftToday) left today").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Next event widget

struct NextEventWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KeelNextEvent", provider: KeelProvider()) { entry in
            NextEventView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(URL(string: "com.keel.app://calendar"))
        }
        .configurationDisplayName("Next Event")
        .description("A countdown to what's next, so time doesn't sneak up on you.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

struct NextEventView: View {
    let entry: KeelEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let e = entry.upcoming.first {
            switch family {
            case .accessoryInline:
                Text("\(e.title) \(e.start, style: .relative)")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.title).font(.headline).lineLimit(1)
                    Text(e.start, style: .time).font(.caption)
                    Text(e.start, style: .relative).font(.caption2)
                }
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEXT").font(.caption2.weight(.bold)).foregroundStyle(Color(hex: e.colorHex))
                    Text(e.title).font(.system(.headline, design: .rounded)).lineLimit(3)
                    Spacer(minLength: 0)
                    Text(e.start, style: .relative).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(Color(hex: e.colorHex))
                    Text(e.start, style: .time).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Nothing else on your calendar today").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Focus Live Activity (Lock Screen + Dynamic Island)

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "moon.zzz.fill").font(.title2).foregroundStyle(focusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Focusing").font(.headline)
                    if let t = context.state.taskTitle { Text(t).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
                Text(timerInterval: Date()...max(Date(), context.state.endsAt), countsDown: true)
                    .font(.system(.title, design: .rounded).weight(.semibold).monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
            .widgetURL(URL(string: "com.keel.app://focus"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Focus", systemImage: "moon.zzz.fill").foregroundStyle(focusColor)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date()...max(Date(), context.state.endsAt), countsDown: true)
                        .monospacedDigit().frame(maxWidth: 70)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.taskTitle ?? "Deep work. Everything else can wait.").font(.caption).lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "moon.zzz.fill").foregroundStyle(focusColor)
            } compactTrailing: {
                Text(timerInterval: Date()...max(Date(), context.state.endsAt), countsDown: true)
                    .monospacedDigit().frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "moon.zzz.fill").foregroundStyle(focusColor)
            }
            .widgetURL(URL(string: "com.keel.app://focus"))
        }
    }
}
