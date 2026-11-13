import WidgetKit
import SwiftUI
#if !targetEnvironment(macCatalyst)
import ActivityKit
#endif
import AppIntents

@main
struct KeelWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        NextEventWidget()
        CountdownWidget()
        TasksCheckWidget()
        HabitsCheckWidget()
        MedsWidget()
        MomentumWidget()
        GroceriesWidget()
        TonightWidget()
        LevelWidget()
        #if !targetEnvironment(macCatalyst)       // Live Activities and Control Center are iPhone-only
        FocusLiveActivity()
        MeetingLiveActivity()
        CaptureControl()
        FocusControl()
        StartNowControl()
        #endif
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
                .widgetURL(NextEventView.joinLink(entry) ?? URL(string: "com.keel.app://calendar"))
        }
        .configurationDisplayName("Next Event")
        .description("A countdown to what's next, so time doesn't sneak up on you.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

struct NextEventView: View {
    let entry: KeelEntry
    @Environment(\.widgetFamily) private var family

    /// Within 15 minutes of a video meeting, tapping the widget joins the call.
    static func joinLink(_ entry: KeelEntry) -> URL? {
        guard let e = entry.upcoming.first, let link = e.joinURL, e.start.timeIntervalSince(entry.date) < 900,
              let q = link.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        return URL(string: "com.keel.app://join?url=\(q)")
    }

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
                    if Self.joinLink(entry) != nil {
                        Label("Tap to join", systemImage: "video.fill").font(.caption.weight(.semibold)).foregroundStyle(Color(hex: e.colorHex))
                    } else {
                        Text(e.start, style: .time).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Nothing else on your calendar today").font(.caption).foregroundStyle(.secondary)
        }
    }
}

#if !targetEnvironment(macCatalyst)
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

// MARK: - Meeting Live Activity: time left, Join, recording dot

private let meetingColor = Color(red: 0.95, green: 0.55, blue: 0.25)

struct MeetingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MeetingActivityAttributes.self) { context in
            let s = context.state
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: s.recording ? "record.circle" : "person.2.fill")
                        .font(.title3).foregroundStyle(s.recording ? .red : meetingColor)
                        .symbolEffect(.pulse, isActive: s.recording)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.title).font(.headline).lineLimit(1)
                        Text(s.recording ? "Recording notes" : (Date() < s.start ? "Starts \(s.start.formatted(date: .omitted, time: .shortened))" : "In progress"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(timerInterval: Date()...max(Date(), s.end), countsDown: true)
                            .font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
                            .multilineTextAlignment(.trailing).frame(maxWidth: 96)
                        Text("left").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                ProgressView(timerInterval: s.start...max(s.start.addingTimeInterval(60), s.end), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(meetingColor)
                HStack(spacing: 8) {
                    if let join = context.attributes.joinDeepLink {
                        Link(destination: join) {
                            Label("Join \(context.attributes.service ?? "call")", systemImage: "video.fill")
                                .font(.caption.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(meetingColor, in: Capsule()).foregroundStyle(.white)
                        }
                    }
                    if !s.recording, let rec = URL(string: "com.keel.app://record") {
                        Link(destination: rec) {
                            Label("Record notes", systemImage: "mic.fill")
                                .font(.caption.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(.white.opacity(0.15), in: Capsule())
                        }
                    }
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
            .widgetURL(URL(string: "com.keel.app://calendar"))
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.title, systemImage: s.recording ? "record.circle" : "person.2.fill")
                        .font(.caption).lineLimit(1).foregroundStyle(s.recording ? .red : meetingColor)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date()...max(Date(), s.end), countsDown: true)
                        .monospacedDigit().frame(maxWidth: 70)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let join = context.attributes.joinDeepLink {
                            Link(destination: join) { Label("Join", systemImage: "video.fill").font(.caption.weight(.semibold)) }
                        }
                        Spacer()
                        if !s.recording, let rec = URL(string: "com.keel.app://record") {
                            Link(destination: rec) { Label("Record notes", systemImage: "mic.fill").font(.caption.weight(.semibold)) }
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: s.recording ? "record.circle" : "person.2.fill").foregroundStyle(s.recording ? .red : meetingColor)
            } compactTrailing: {
                Text(timerInterval: Date()...max(Date(), s.end), countsDown: true)
                    .monospacedDigit().frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "person.2.fill").foregroundStyle(meetingColor)
            }
            .widgetURL(URL(string: "com.keel.app://calendar"))
        }
    }
}

// MARK: - Control Center / Lock Screen / Action button controls

struct CaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "KeelCapture") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "com.keel.app://capture")!)) {
                Label("Capture", systemImage: "plus.circle")
            }
        }
        .displayName("Keel Capture")
        .description("Jot down a task in one tap.")
    }
}

struct FocusControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "KeelFocus") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "com.keel.app://focus")!)) {
                Label("Focus", systemImage: "moon.zzz.fill")
            }
        }
        .displayName("Keel Focus")
        .description("Start a focus session.")
    }
}

#endif

#if !targetEnvironment(macCatalyst)
struct StartNowControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "KeelStartNow") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "com.keel.app://nownext")!)) {
                Label("Start Now", systemImage: "timer")
            }
        }
        .displayName("Start Next Task")
        .description("Starts your next task with a countdown.")
    }
}
#endif

// MARK: - Countdown widget

struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KeelCountdown", provider: KeelProvider()) { entry in
            CountdownView(entry: entry)
                .containerBackground(for: .widget) { LinearGradient(colors: [accent.opacity(0.2), .clear], startPoint: .top, endPoint: .bottom) }
                .widgetURL(URL(string: "com.keel.app://today"))
        }
        .configurationDisplayName("Countdown")
        .description("Days until the next big date.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

struct CountdownView: View {
    let entry: KeelEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        if let c = entry.snapshot.countdowns?.first(where: { $0.date >= Calendar.current.startOfDay(for: entry.date) }) {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: entry.date), to: Calendar.current.startOfDay(for: c.date)).day ?? 0
            switch family {
            case .accessoryInline:
                Text("\(c.emoji) \(days)d · \(c.title)")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(c.emoji) \(c.title)").font(.headline).lineLimit(1)
                    Text(days == 0 ? "Today!" : "\(days) days").font(.caption)
                }
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Text(c.emoji).font(.title)
                    Spacer(minLength: 0)
                    Text(days == 0 ? "Today!" : "\(days)").font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(accent)
                    if days > 0 { Text(days == 1 ? "day to go" : "days to go").font(.caption).foregroundStyle(.secondary) }
                    Text(c.title).font(.caption.weight(.semibold)).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Add a countdown in Keel").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Interactive: check off tasks and habits right on the Home Screen

struct TasksCheckWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KeelTasksCheck", provider: KeelProvider()) { entry in
            TasksCheckView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
                .widgetURL(URL(string: "com.keel.app://tasks"))
        }
        .configurationDisplayName("Today's Tasks")
        .description("Tap the circle to complete a task without opening Keel.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TasksCheckView: View {
    let entry: KeelEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let limit = family == .systemLarge ? 8 : 4
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TODAY").font(.caption2.weight(.bold)).foregroundStyle(accent)
                Spacer()
                Text("\(entry.snapshot.tasksDoneToday) done · \(entry.snapshot.tasksLeftToday) left").font(.caption2).foregroundStyle(.secondary)
            }
            if entry.snapshot.tasks.isEmpty {
                Spacer()
                Text("All clear for today ✨").font(.headline).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(entry.snapshot.tasks.prefix(limit), id: \.self) { t in
                    HStack(spacing: 8) {
                        if let id = t.id {
                            Button(intent: WidgetCompleteTaskIntent(id: id)) {
                                Image(systemName: "circle").font(.title3).foregroundStyle(priorityColor(t.priority))
                            }
                            .buttonStyle(.plain)
                        }
                        Text(t.title).font(.subheadline).lineLimit(1)
                        Spacer(minLength: 0)
                        if let d = t.due, Calendar.current.dateComponents([.hour, .minute], from: d) != DateComponents(hour: 0, minute: 0) {
                            Text(d, style: .time).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func priorityColor(_ p: Int) -> Color {
        switch p { case 3: .red; case 2: .orange; case 1: .blue; default: .secondary }
    }
}

struct HabitsCheckWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KeelHabitsCheck", provider: KeelProvider()) { entry in
            HabitsCheckView(entry: entry)
                .containerBackground(for: .widget) { LinearGradient(colors: [accent.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom) }
                .widgetURL(URL(string: "com.keel.app://today"))
        }
        .configurationDisplayName("Habits")
        .description("Tap a habit to mark it done for today.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HabitsCheckView: View {
    let entry: KeelEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let habits = entry.snapshot.habits ?? []
        let cols = family == .systemSmall ? 2 : 4
        VStack(alignment: .leading, spacing: 6) {
            Text("HABITS · \(habits.filter(\.done).count)/\(habits.count)").font(.caption2.weight(.bold)).foregroundStyle(accent)
            if habits.isEmpty {
                Spacer()
                Text("Add a habit stack in Keel").font(.caption).foregroundStyle(.secondary)
                Spacer()
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: cols), spacing: 6) {
                    ForEach(habits.prefix(cols * 2), id: \.self) { h in
                        Button(intent: WidgetCompleteHabitIntent(id: h.id)) {
                            VStack(spacing: 2) {
                                Image(systemName: h.done ? "checkmark.circle.fill" : h.icon)
                                    .font(.title3).foregroundStyle(h.done ? Color.green : accent)
                                Text(h.name).font(.system(size: 9)).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(h.done)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Lock Screen: next med dose and momentum

struct MedsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KeelMeds", provider: KeelProvider()) { entry in
            MedsWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(URL(string: "com.keel.app://today"))
        }
        .configurationDisplayName("Medication")
        .description("Your next dose, right on the Lock Screen.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular, .systemSmall])
    }
}

struct MedsWidgetView: View {
    let entry: KeelEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let s = entry.snapshot
        switch family {
        case .accessoryInline:
            if let n = s.nextMed, let at = s.nextMedAt { Text("💊 \(n) \(at, style: .time)") } else { Text("💊 All taken today") }
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "pills.fill")
                Text(s.medsLeftToday.map { $0 == 0 ? "✓" : "\($0)" } ?? "–").font(.headline)
            }
        default:
            VStack(alignment: .leading, spacing: 2) {
                Label("NEXT DOSE", systemImage: "pills.fill").font(.caption2.weight(.semibold))
                if let n = s.nextMed, let at = s.nextMedAt {
                    Text(n).font(.headline).lineLimit(1)
                    Text(at, style: .time).font(.caption)
                } else {
                    Text(s.medsLeftToday == nil ? "No meds added" : "All taken today ✓").font(.headline)
                }
                if family == .systemSmall { Spacer(minLength: 0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MomentumWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KeelMomentum", provider: KeelProvider()) { entry in
            let m = entry.snapshot.momentum ?? 0
            Gauge(value: Double(m), in: 0...100) { Image(systemName: "bolt.fill") } currentValueLabel: { Text("\(m)") }
                .gaugeStyle(.accessoryCircularCapacity)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(URL(string: "com.keel.app://today"))
        }
        .configurationDisplayName("Momentum")
        .description("Today's momentum score. It only goes up.")
        .supportedFamilies([.accessoryCircular])
    }
}


// MARK: - Groceries (tap to check off)

struct GroceriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KeelGroceries", provider: KeelProvider()) { entry in
            GroceriesView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
                .widgetURL(URL(string: "com.keel.app://groceries"))
        }
        .configurationDisplayName("Groceries")
        .description("Your grocery list. Tap the circle to check something off in the store.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct GroceriesView: View {
    let entry: KeelEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let items = entry.snapshot.groceries ?? []
        let limit = family == .systemLarge ? 12 : (family == .systemMedium ? 4 : 4)
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("GROCERIES", systemImage: "cart.fill").font(.caption2.weight(.bold)).foregroundStyle(.green)
                Spacer()
                if !items.isEmpty { Text("\(items.count)").font(.caption2).foregroundStyle(.secondary) }
            }
            if items.isEmpty {
                Spacer()
                Text("List is empty").font(.headline).frame(maxWidth: .infinity)
                Text("Say “Add milk to groceries in Keel”").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                Spacer()
            } else {
                let cols = family == .systemMedium ? 2 : 1
                let shown = Array(items.prefix(family == .systemMedium ? 8 : limit))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: cols), alignment: .leading, spacing: 5) {
                    ForEach(shown, id: \.self) { t in
                        HStack(spacing: 6) {
                            if let id = t.id {
                                Button(intent: WidgetCompleteTaskIntent(id: id)) {
                                    Image(systemName: "circle").foregroundStyle(.green)
                                }
                                .buttonStyle(.plain)
                            }
                            Text(t.title).font(.subheadline).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Tonight & deadlines

struct TonightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KeelTonight", provider: KeelProvider()) { entry in
            TonightView(entry: entry)
                .containerBackground(for: .widget) { LinearGradient(colors: [Color.indigo.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom) }
                .widgetURL(URL(string: "com.keel.app://tasks"))
        }
        .configurationDisplayName("Tonight & Deadlines")
        .description("What you saved for this evening, and the deadlines coming up.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TonightView: View {
    let entry: KeelEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let evening = entry.snapshot.evening ?? []
        let deadlines = entry.snapshot.deadlines ?? []
        HStack(alignment: .top, spacing: 12) {
            if family == .systemMedium || deadlines.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Label("TONIGHT", systemImage: "moon.stars.fill").font(.caption2.weight(.bold)).foregroundStyle(.indigo)
                    if evening.isEmpty {
                        Text("Nothing saved for tonight").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(evening.prefix(4), id: \.self) { t in
                            HStack(spacing: 6) {
                                if let id = t.id {
                                    Button(intent: WidgetCompleteTaskIntent(id: id)) { Image(systemName: "circle").foregroundStyle(.indigo) }.buttonStyle(.plain)
                                }
                                Text(t.title).font(.subheadline).lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !deadlines.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Label("DEADLINES", systemImage: "flag.fill").font(.caption2.weight(.bold)).foregroundStyle(.red)
                    ForEach(deadlines.prefix(4), id: \.self) { t in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(t.title).font(.subheadline).lineLimit(1)
                            if let d = t.due { Text(daysLeft(d)).font(.caption2).foregroundStyle(daysUntil(d) <= 1 ? .red : .secondary) }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func daysUntil(_ d: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d)).day ?? 0
    }
    private func daysLeft(_ d: Date) -> String {
        switch daysUntil(d) {
        case ..<0: "Overdue"
        case 0: "Today"
        case 1: "Tomorrow"
        case let n: "In \(n) days"
        }
    }
}

// MARK: - Level & coins

struct LevelWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KeelLevel", provider: KeelProvider()) { entry in
            LevelView(entry: entry)
                .containerBackground(for: .widget) { LinearGradient(colors: [Color.orange.opacity(0.2), .clear], startPoint: .top, endPoint: .bottom) }
                .widgetURL(URL(string: "com.keel.app://tool/rewards"))
        }
        .configurationDisplayName("Level & Coins")
        .description("Your Keel level, progress to the next one, and coins to spend on rewards.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct LevelView: View {
    let entry: KeelEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let level = entry.snapshot.level ?? 1
        let progress = entry.snapshot.levelProgress ?? 0
        if family == .accessoryCircular {
            Gauge(value: progress) { Text("Lv") } currentValueLabel: { Text("\(level)") }
                .gaugeStyle(.accessoryCircularCapacity)
        } else {
            VStack(spacing: 6) {
                ZStack {
                    Circle().stroke(Color.orange.opacity(0.2), lineWidth: 8)
                    Circle().trim(from: 0, to: progress).stroke(Color.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("LEVEL").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        Text("\(level)").font(.title.weight(.bold)).monospacedDigit()
                    }
                }
                .frame(width: 84, height: 84)
                Label("\(entry.snapshot.coins ?? 0) coins", systemImage: "circle.hexagongrid.fill").font(.caption.weight(.semibold)).foregroundStyle(.orange)
            }
        }
    }
}
