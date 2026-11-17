import SwiftUI

// MARK: - Customize everything: one place for how each part of Keel looks and behaves

/// Every customizable choice, read where it's used. Defaults keep Keel exactly as it was.
enum Custom {
    private static var d: UserDefaults { .standard }
    private static func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) as? Bool ?? def }
    private static func int(_ k: String, _ def: Int) -> Int { let v = d.integer(forKey: k); return d.object(forKey: k) == nil ? def : v }

    // Tasks
    static let taskSortKey = "custom.tasks.sort"                  // due, priority, title, newest
    static var taskSort: String { d.string(forKey: taskSortKey) ?? "due" }
    static let taskShowDurationKey = "custom.tasks.showDuration"
    static var taskShowDuration: Bool { bool(taskShowDurationKey, false) }
    static let taskShowEnergyKey = "custom.tasks.showEnergy"
    static var taskShowEnergy: Bool { bool(taskShowEnergyKey, true) }
    static let taskShowTagsKey = "custom.tasks.showTags"
    static var taskShowTags: Bool { bool(taskShowTagsKey, true) }
    static let taskShowListKey = "custom.tasks.showList"
    static var taskShowList: Bool { bool(taskShowListKey, true) }
    static let taskEveningKey = "custom.tasks.evening"
    static var taskEveningSection: Bool { bool(taskEveningKey, true) }

    // Today
    static let todaySharedKey = "custom.today.shared"
    static var todayShared: Bool { bool(todaySharedKey, true) }
    static let todayRoutineKey = "custom.today.routine"
    static var todayRoutine: Bool { bool(todayRoutineKey, true) }
    static let todayWeatherKey = "custom.today.weather"
    static var todayWeather: Bool { bool(todayWeatherKey, true) }
    static let tomorrowHourKey = "custom.today.tomorrowHour"
    static var tomorrowHour: Int { int(tomorrowHourKey, 18) }

    // Calendar
    static let calendarDensityKey = "custom.calendar.density"     // 0.75 compact, 1 regular, 1.3 roomy
    static var calendarDensity: Double { let v = d.double(forKey: calendarDensityKey); return v > 0 ? v : 1 }
    static let eventMinutesKey = "custom.calendar.eventMinutes"
    static var eventMinutes: Int { int(eventMinutesKey, 60) }
    static let dimPastKey = "custom.calendar.dimPast"
    static var dimPastEvents: Bool { bool(dimPastKey, true) }

    // Focus
    static let shortBreakKey = "custom.focus.shortBreak"
    static var shortBreak: Int { int(shortBreakKey, 5) }
    static let longBreakKey = "custom.focus.longBreak"
    static var longBreak: Int { int(longBreakKey, 15) }
    static let longEveryKey = "custom.focus.longEvery"
    static var longEvery: Int { max(2, int(longEveryKey, 4)) }
    static let focusLevelKey = "custom.focus.level"
    static var focusLevel: Int { int(focusLevelKey, 1) }

    // Body
    static let bodyHiddenKey = "custom.body.hiddenPages"
    static var bodyHidden: Set<String> { Set((d.string(forKey: bodyHiddenKey) ?? "").split(separator: ",").map(String.init)) }
    static let bodyStartKey = "custom.body.startPage"             // "" = where you left off
    nonisolated(unsafe) static var bodyStartApplied = false

    // Notes
    static let notesJumpKey = "custom.notes.jumpBackIn"
    static var notesJumpBackIn: Bool { bool(notesJumpKey, true) }
    static let notesFavoritesKey = "custom.notes.favorites"
    static var notesFavorites: Bool { bool(notesFavoritesKey, true) }
    static let notesRecentKey = "custom.notes.recentCount"
    static var notesRecentCount: Int { int(notesRecentKey, 8) }
    static let notesSpacingKey = "custom.notes.lineSpacing"       // 0 normal, 4 airy, 8 spacious
    static var notesSpacing: Double { d.double(forKey: notesSpacingKey) }

    // Compass
    static let compassHiddenKey = "custom.compass.hiddenGroups"
    static var compassHidden: Set<String> { Set((d.string(forKey: compassHiddenKey) ?? "").split(separator: ",").map(String.init)) }
}

/// Settings → Customize Keel: every area, one tap away.
struct CustomizeHubView: View {
    var body: some View {
        List {
            Section {
                link("Today", "sun.max.fill", .orange) { TodayCustomizeView() }
                link("Inbox & mail", "envelope.fill", .blue) { MailSettings() }
                link("Calendar", "calendar", .red) { CalendarCustomizeView() }
                link("Tasks", "checklist", .green) { TasksCustomizeView() }
                link("Notes", "note.text", .yellow) { NotesCustomizeView() }
                link("Focus", "moon.fill", .indigo) { FocusCustomizeView() }
                link("Body", "water.waves", .teal) { BodyCustomizeView() }
                link("Compass", "square.grid.2x2.fill", .purple) { CompassCustomizeView() }
                link("Quiet hours", "moon.zzz.fill", .indigo) { QuietHoursView() }
            } footer: { Text("How each part of Keel looks and behaves. Nothing here deletes anything; switch things back any time.") }
            Section {
                link("Look & feel (theme, colors, fonts, text size)", "paintbrush.fill", .pink) { AppearanceSettings() }
                link("Tab bar", "dock.rectangle", .gray) { TabBarSettings() }
                link("Inbox tabs", "rectangle.split.3x1", .blue) { InboxTabsSettings() }
            }
        }
        .navigationTitle("Customize Keel")
    }

    private func link<V: View>(_ t: String, _ icon: String, _ c: Color, @ViewBuilder _ dest: @escaping () -> V) -> some View {
        NavigationLink { LazyView(dest()) } label: {
            Label { Text(t) } icon: {
                Image(systemName: icon).foregroundStyle(.white).font(.caption.weight(.semibold))
                    .frame(width: 28, height: 28).background(c.gradient, in: .rect(cornerRadius: 7))
            }
        }
    }
}

struct TodayCustomizeView: View {
    @AppStorage(Custom.todaySharedKey) private var shared = true
    @AppStorage(Custom.todayRoutineKey) private var routine = true
    @AppStorage(Custom.todayWeatherKey) private var weather = true
    @AppStorage("custom.today.favoritePages") private var favoritePages = true
    @AppStorage(CalendarClashes.onKey) private var clashes = true
    @AppStorage("custom.today.progress") private var progress = true
    @AppStorage("custom.today.pinnedMail") private var pinnedMail = true
    @AppStorage(DailyAffirmation.toggleKey) private var affirmation = true
    @AppStorage("today.tomorrowPreview") private var tomorrow = true
    @AppStorage(Custom.tomorrowHourKey) private var tomorrowHour = 18
    @AppStorage(Prefs.calm) private var calm = false
    @AppStorage(DayWrap.onKey) private var wrap = true
    @AppStorage(DayWrap.minuteKey) private var wrapMinute = 18 * 60
    @Environment(\.modelContext) private var ctx

    var body: some View {
        Form {
            Section {
                NavigationLink { LazyView(CustomizeTodayView()) } label: { Label("Cards and their order", systemImage: "rectangle.stack") }
                Toggle("Calm mode (fewer cards, softer colors)", isOn: $calm)
            }
            Section("At the top") {
                Toggle("Weather line", isOn: $weather)
                Toggle("Daily affirmation", isOn: $affirmation)
                Toggle("Things shared to Keel", isOn: $shared)
                Toggle("Routine coming up", isOn: $routine)
                Toggle("Favorite pages", isOn: $favoritePages)
                Toggle("Calendar clashes this week", isOn: $clashes)
                Toggle("Pinned emails", isOn: $pinnedMail)
                Toggle("Today's progress ring", isOn: $progress)
            }
            Section {
                Toggle("Tomorrow at a glance", isOn: $tomorrow)
                if tomorrow {
                    Picker("Show it from", selection: $tomorrowHour) {
                        ForEach([16, 17, 18, 19, 20, 21], id: \.self) { h in
                            Text(Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date())!.formatted(date: .omitted, time: .shortened)).tag(h)
                        }
                    }
                }
                Toggle("End-of-day wrap-up", isOn: $wrap)
                if wrap {
                    DatePicker("Wrap-up at", selection: Binding(get: {
                        Calendar.current.date(bySettingHour: wrapMinute / 60, minute: wrapMinute % 60, second: 0, of: Date()) ?? Date()
                    }, set: { d in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: d); wrapMinute = (c.hour ?? 18) * 60 + (c.minute ?? 0)
                    }), displayedComponents: .hourAndMinute)
                }
            } header: { Text("Evenings") } footer: { Text("The wrap-up is a quiet note: what you finished today and the first thing tomorrow.") }
            .onChange(of: wrap) { DayWrap.reschedule(ctx: ctx) }
            .onChange(of: wrapMinute) { DayWrap.reschedule(ctx: ctx) }
            Section { NavigationLink { LazyView(DailyAffirmationsEditor()) } label: { Label("My affirmations", systemImage: "quote.bubble") } }
        }
        .navigationTitle("Today")
    }
}

private struct DailyAffirmationsEditor: View { var body: some View { KitAffirmationsView() } }

struct TasksCustomizeView: View {
    @AppStorage(Custom.taskSortKey) private var sort = "due"
    @AppStorage(Custom.taskShowDurationKey) private var duration = false
    @AppStorage(Custom.taskShowEnergyKey) private var energy = true
    @AppStorage(Custom.taskShowTagsKey) private var tags = true
    @AppStorage(Custom.taskShowListKey) private var list = true
    @AppStorage(Custom.taskEveningKey) private var evening = true
    @AppStorage(MorningRollover.onKey) private var rollover = false

    var body: some View {
        Form {
            Section {
                Picker("Sort within each day", selection: $sort) {
                    Text("Due time, then priority").tag("due"); Text("Priority first").tag("priority")
                    Text("A to Z").tag("title"); Text("Newest first").tag("newest")
                }
                Toggle("“This Evening” section", isOn: $evening)
                Toggle("Move overdue tasks to today each morning", isOn: $rollover)
            } header: { Text("Order") } footer: { Text("Roll-over keeps each task's time of day; repeating tasks keep their own schedule; Undo puts them back.") }
            Section {
                Toggle("Time estimate (~5 min)", isOn: $duration)
                Toggle("Energy icon", isOn: $energy)
                Toggle("Tags", isOn: $tags)
                Toggle("List name", isOn: $list)
            } header: { Text("On each task") }
            Section {
                NavigationLink { LazyView(TaskSettings()) } label: { Label("Default list, alerts and alarms", systemImage: "bell") }
                NavigationLink { LazyView(TaskDurationSettings()) } label: { Label("Default task length", systemImage: "clock") }
                NavigationLink { LazyView(SwipeSettingsView()) } label: { Label("Swipe actions", systemImage: "hand.draw") }
                NavigationLink { LazyView(DeletedTasksView()) } label: { Label("Recently deleted", systemImage: "trash") }
            }
        }
        .navigationTitle("Tasks")
    }
}

struct CalendarCustomizeView: View {
    @AppStorage(Custom.calendarDensityKey) private var density = 1.0
    @AppStorage(Custom.eventMinutesKey) private var eventMinutes = 60
    @AppStorage(Custom.dimPastKey) private var dimPast = true
    @AppStorage(MeetingBuffers.key) private var buffer = 0

    var body: some View {
        Form {
            Section {
                Picker("Hour height", selection: $density) {
                    Text("Compact").tag(0.75); Text("Regular").tag(1.0); Text("Roomy").tag(1.3)
                }
                Toggle("Fade events that are over", isOn: $dimPast)
            } header: { Text("Look") }
            Section {
                Picker("New events last", selection: $eventMinutes) {
                    Text("15 min").tag(15); Text("30 min").tag(30); Text("45 min").tag(45); Text("1 hour").tag(60); Text("90 min").tag(90); Text("2 hours").tag(120)
                }
            } header: { Text("New events") } footer: { Text("Used when you add an event without saying how long (“lunch with Sam Friday 1pm”).") }
            Section {
                Picker("Buffer after meetings", selection: $buffer) {
                    Text("Off").tag(0); Text("5 min").tag(5); Text("10 min").tag(10); Text("15 min").tag(15); Text("30 min").tag(30)
                }
                .onChange(of: buffer) { MeetingBuffers.refresh(force: true) }
            } footer: { Text("Keel adds a “Buffer” block after each meeting (on your Keel calendar, next 7 days) when that time is free, so nothing gets booked right on top. Your booking link respects it.") }
            Section { NavigationLink { LazyView(CalendarSettings()) } label: { Label("Calendars, alerts and meeting autopilot", systemImage: "calendar.badge.clock") } }
        }
        .navigationTitle("Calendar")
    }
}

struct FocusCustomizeView: View {
    @AppStorage(Custom.shortBreakKey) private var shortBreak = 5
    @AppStorage(Custom.longBreakKey) private var longBreak = 15
    @AppStorage(Custom.longEveryKey) private var longEvery = 4
    @AppStorage(Custom.focusLevelKey) private var level = 1
    @AppStorage("focus.sound") private var sound = "off"
    @AppStorage(FocusReflections.askKey) private var reflect = true

    var body: some View {
        Form {
            Section {
                Picker("Starts as", selection: $level) {
                    ForEach(ShutdownManager.Level.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Focus sound", selection: $sound) { ForEach(FocusSound.Kind.allCases) { Text($0.label).tag($0.rawValue) } }
                Toggle("Ask “how did it go?” afterwards", isOn: $reflect)
            } header: { Text("Every session") } footer: { Text("Your answers show in Focus history, with when your sessions tend to go best.") }
            Section {
                Stepper("Short break: \(shortBreak) min", value: $shortBreak, in: 1...30)
                Stepper("Long break: \(longBreak) min", value: $longBreak, in: 5...60, step: 5)
                Stepper("Long break every \(longEvery) rounds", value: $longEvery, in: 2...8)
            } header: { Text("Focus rounds") }
            Section {
                FocusMusicPicker()
            } header: { Text("Music") }
            Section { NavigationLink { LazyView(FocusSettings()) } label: { Label("Length, breaks reminders and forecast", systemImage: "timer") } }
        }
        .navigationTitle("Focus")
    }
}

struct BodyCustomizeView: View {
    @AppStorage(Custom.bodyHiddenKey) private var hiddenRaw = ""
    @AppStorage(Custom.bodyStartKey) private var start = ""

    var body: some View {
        Form {
            Section {
                ForEach(BodyPage.allCases) { p in
                    Toggle(isOn: Binding(get: { !hiddenSet.contains(p.rawValue) }, set: { on in
                        var s = hiddenSet
                        if on { s.remove(p.rawValue) } else if s.count < BodyPage.allCases.count - 1 { s.insert(p.rawValue) }
                        hiddenRaw = s.sorted().joined(separator: ",")
                    })) { Label(p.rawValue, systemImage: p.icon) }
                }
            } header: { Text("Pages") } footer: { Text("Hide pages you don't use. One always stays.") }
            Section {
                Picker("Open on", selection: $start) {
                    Text("Where I left off").tag("")
                    ForEach(BodyPage.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
            }
            Section { NavigationLink { LazyView(NutritionSettingsView()) } label: { Label("Food goals & Apple Health", systemImage: "fork.knife") } }
        }
        .navigationTitle("Body")
    }

    private var hiddenSet: Set<String> { Set(hiddenRaw.split(separator: ",").map(String.init)) }
}

struct NotesCustomizeView: View {
    @AppStorage("notes.layout") private var layout = "Cards"
    @AppStorage(Custom.notesJumpKey) private var jump = true
    @AppStorage(Custom.notesFavoritesKey) private var favorites = true
    @AppStorage(Custom.notesRecentKey) private var recent = 8
    @AppStorage(Custom.notesSpacingKey) private var spacing = 0.0

    var body: some View {
        Form {
            Section {
                Picker("Library", selection: $layout) { Text("Folder cards").tag("Cards"); Text("Page tree").tag("Page tree") }
                Toggle("Jump back in", isOn: $jump)
                if jump { Stepper("Recent pages: \(recent)", value: $recent, in: 3...16) }
                Toggle("Favorites", isOn: $favorites)
            } header: { Text("Notes home") }
            Section {
                Picker("Line spacing", selection: $spacing) { Text("Normal").tag(0.0); Text("Airy").tag(4.0); Text("Spacious").tag(8.0) }
            } header: { Text("Pages") } footer: { Text("Page width and the bars while reading are in each page's ⋯ menu.") }
        }
        .navigationTitle("Notes")
    }
}

struct CompassCustomizeView: View {
    @AppStorage(Custom.compassHiddenKey) private var hiddenRaw = ""
    var body: some View {
        Form {
            Section {
                ForEach(HubCatalog.groups) { g in
                    Toggle(isOn: Binding(get: { !hidden.contains(g.id) }, set: { on in
                        var s = hidden
                        if on { s.remove(g.id) } else { s.insert(g.id) }
                        hiddenRaw = s.sorted().joined(separator: ",")
                    })) { Label(g.title, systemImage: g.icon) }
                }
            } header: { Text("Groups") } footer: { Text("Hidden groups' tools still come up when you search Compass.") }
        }
        .navigationTitle("Compass")
    }
    private var hidden: Set<String> { Set(hiddenRaw.split(separator: ",").map(String.init)) }
}

extension BodyPage {
    /// The pages you haven't hidden (Customize → Body), in their usual order.
    static var visible: [BodyPage] {
        let hidden = Custom.bodyHidden
        let v = allCases.filter { !hidden.contains($0.rawValue) }
        return v.isEmpty ? Array(allCases) : v
    }
}

struct QuietHoursView: View {
    @AppStorage(QuietHours.onKey) private var on = false
    @AppStorage(QuietHours.startKey) private var start = 22 * 60
    @AppStorage(QuietHours.endKey) private var end = 7 * 60
    @AppStorage(QuietHours.holdKey) private var hold = false

    var body: some View {
        Form {
            Section {
                Toggle("Quiet hours", isOn: $on)
                if on {
                    DatePicker("From", selection: minutes($start), displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: minutes($end), displayedComponents: .hourAndMinute)
                    Picker("Keel's alerts", selection: $hold) {
                        Text("Arrive silently").tag(false); Text("Wait until morning").tag(true)
                    }
                }
            } footer: { Text("Overnight, Keel's alerts either land silently in Notification Center or wait until quiet hours end. Medication reminders, alarms and time-sensitive alerts always come through. Applies to alerts scheduled from now on.") }
        }
        .navigationTitle("Quiet hours")
    }

    private func minutes(_ b: Binding<Int>) -> Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: b.wrappedValue / 60, minute: b.wrappedValue % 60, second: 0, of: Date()) ?? Date() },
                set: { d in let c = Calendar.current.dateComponents([.hour, .minute], from: d); b.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0) })
    }
}
