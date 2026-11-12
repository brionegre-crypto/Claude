import WidgetKit
import SwiftUI

/// Watch-face complications: your one thing, next event, and tasks left today.
@main
struct KeelWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        OneThingComplication()
        NextEventComplication()
        TasksLeftComplication()
    }
}

private let accent = Color(red: 0.36, green: 0.42, blue: 0.98)

struct WatchEntry: TimelineEntry {
    let date: Date
    let payload: WatchPayload
    var nextEvent: WatchPayload.EventRow? { payload.events.first { $0.end > date } }
}

struct WatchProvider: TimelineProvider {
    static func load() -> WatchPayload {
        guard let data = UserDefaults(suiteName: "group.com.briangreenejr.keel")?.data(forKey: "watch.payload"),
              let p = WatchCoding.decode(WatchPayload.self, data) else { return WatchPayload() }
        return p
    }

    func placeholder(in context: Context) -> WatchEntry {
        WatchEntry(date: Date(), payload: WatchPayload(nextThing: "Approve Q4 roadmap",
                                                       tasks: [.init(id: UUID(), title: "Call dentist", due: nil, hasTime: false, priority: 1)],
                                                       events: [.init(title: "Standup", start: Date().addingTimeInterval(1_800), end: Date().addingTimeInterval(3_600))]))
    }
    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : WatchEntry(date: Date(), payload: Self.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        let p = Self.load()
        let entries = (0..<8).map { WatchEntry(date: Date().addingTimeInterval(Double($0) * 900), payload: p) }
        completion(Timeline(entries: entries, policy: .after(Date().addingTimeInterval(7_200))))
    }
}

struct OneThingComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KeelWatchOneThing", provider: WatchProvider()) { entry in
            OneThingFace(entry: entry).containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Just One Thing")
        .description("Your best next step.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct OneThingFace: View {
    let entry: WatchEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        switch family {
        case .accessoryInline:
            Text(entry.payload.nextThing.map { "◆ \($0)" } ?? "Nothing urgent")
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text("ONE THING").font(.system(size: 10, weight: .bold)).foregroundStyle(accent)
                Text(entry.payload.nextThing ?? "Nothing urgent").font(.headline).lineLimit(2)
            }
        }
    }
}

struct NextEventComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KeelWatchNextEvent", provider: WatchProvider()) { entry in
            NextEventFace(entry: entry).containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Next Event")
        .description("Countdown to what's next.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct NextEventFace: View {
    let entry: WatchEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        if let e = entry.nextEvent {
            switch family {
            case .accessoryInline:
                Text("\(e.title) \(e.start, style: .relative)")
            case .accessoryCorner:
                Image(systemName: "calendar")
                    .widgetLabel { Text(e.start, style: .time) }
            default:
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.title).font(.headline).lineLimit(1)
                    Text(e.start, style: .time).font(.caption)
                    Text(e.start, style: .relative).font(.caption2).foregroundStyle(.secondary)
                }
            }
        } else {
            Text("No more events").font(.caption)
        }
    }
}

struct TasksLeftComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KeelWatchTasksLeft", provider: WatchProvider()) { entry in
            TasksLeftFace(entry: entry).containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Tasks Left")
        .description("How many tasks are left today.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct TasksLeftFace: View {
    let entry: WatchEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        let left = entry.payload.tasks.count
        switch family {
        case .accessoryCorner:
            Image(systemName: "checklist").widgetLabel { Text("\(left) left") }
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(left)").font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("left").font(.system(size: 9))
                }
            }
        }
    }
}
