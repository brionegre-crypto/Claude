import SwiftUI
import SwiftData
import EventKit
import TipKit
import UserNotifications

// MARK: - Plan my day: drag tasks onto the hours of your day

/// Your open tasks on top, your day's hours below. Drag a task onto an hour (or tap a task, then tap an hour)
/// and Keel blocks that time on your calendar, sized to how long things really take you.
struct DayPlannerView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }, animation: .snappy) private var open: [TaskItem]
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var events: [EKEvent] = []
    @State private var picked: TaskItem?
    @State private var target: Int?
    @AppStorage("planner.startHour") private var startHour = 7
    @AppStorage("planner.endHour") private var endHour = 22

    private let rowHeight: CGFloat = 60

    private var cal: Calendar { Calendar.current }
    private func isOnDay(_ d: Date?) -> Bool { d.map { cal.isDate($0, inSameDayAs: day) } ?? false }

    /// Not yet given a time on this day.
    private var tray: [TaskItem] {
        open.filter { !$0.isDeleted && !isOnDay($0.scheduledBlockStart) }
            .sorted { a, b in
                let ad = a.dueDate ?? .distantFuture, bd = b.dueDate ?? .distantFuture
                return ad != bd ? ad < bd : a.priority.rawValue > b.priority.rawValue
            }
    }
    private func placed(at hour: Int) -> [TaskItem] {
        open.filter { t in
            guard !t.isDeleted, let s = t.scheduledBlockStart, cal.isDate(s, inSameDayAs: day) else { return false }
            return cal.component(.hour, from: s) == hour
        }
    }
    private func events(at hour: Int) -> [EKEvent] {
        events.filter { e in
            guard !e.isAllDay, !(e.notes ?? "").hasPrefix("keel-task:") else { return false }
            let h0 = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
            return e.startDate < h0.addingTimeInterval(3600) && e.endDate > h0
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TipView(PlanDayTip()).padding(.horizontal).padding(.top, 6)
                Picker("Day", selection: $day) {
                    Text("Today").tag(cal.startOfDay(for: Date()))
                    Text("Tomorrow").tag(cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date())
                }
                .pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 8)
                trayView
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(startHour...max(startHour, endHour), id: \.self) { h in hourRow(h).id(h) }
                        }
                        .padding(.horizontal)
                    }
                    .onAppear { proxy.scrollTo(max(startHour, cal.component(.hour, from: Date()) - 1), anchor: .top) }
                }
            }
            .navigationTitle("Plan my day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { try? ctx.save(); dismiss() } }
                if cal.isDateInToday(day) {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fill my day", systemImage: "wand.and.stars") {
                            let r = AutoScheduler.scheduleToday(tasks: Array(open))
                            UndoCenter.shared.notify(r.scheduled == 0 ? "Nothing more fits today" : "Planned \(r.scheduled) task\(r.scheduled == 1 ? "" : "s")")
                            load()
                        }
                    }
                }
            }
            .task(id: day) { load() }
        }
    }

    private var trayView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(picked == nil ? "Drag a task onto an hour, or tap it and then tap an hour." : "Now tap an hour for “\(picked?.title ?? "")”.")
                .font(DS.Font.caption).foregroundStyle(picked == nil ? DS.Palette.inkSoft : DS.Palette.accent)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if tray.isEmpty { Text("Everything has a time. Nice.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft) }
                    ForEach(tray.prefix(40)) { t in
                        let on = picked?.id == t.id
                        Button { withAnimation(.snappy) { picked = on ? nil : t } } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title).font(DS.Font.caption.weight(.semibold)).lineLimit(1)
                                Text("\(ADHDCoach.calibratedMinutes(t)) min" + (t.dueDate.map { " · due " + $0.formatted(.dateTime.month(.abbreviated).day()) } ?? ""))
                                    .font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .frame(maxWidth: 200, alignment: .leading)
                            .background(on ? DS.Palette.accent.opacity(0.25) : DS.Palette.elevated, in: .rect(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? DS.Palette.accent : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .draggable(t.id.uuidString) {
                            Text(t.title).font(DS.Font.caption.weight(.semibold)).padding(10)
                                .background(DS.Palette.accent.opacity(0.3), in: .rect(cornerRadius: 10))
                        }
                        .accessibilityHint("Then tap an hour to give it that time")
                    }
                }
                .padding(.horizontal).padding(.bottom, 10)
            }
        }
    }

    private func hourRow(_ h: Int) -> some View {
        let label = (cal.date(bySettingHour: h, minute: 0, second: 0, of: day) ?? day).formatted(date: .omitted, time: .shortened)
        let now = cal.isDateInToday(day) && cal.component(.hour, from: Date()) == h
        return HStack(alignment: .top, spacing: 10) {
            Text(label).font(.caption2.monospacedDigit()).foregroundStyle(now ? DS.Palette.accent : DS.Palette.inkSoft)
                .frame(width: 58, alignment: .trailing).padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(events(at: h), id: \.eventIdentifier) { e in
                    Label(e.title ?? "Event", systemImage: "calendar").font(.caption).lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.Palette.meeting.opacity(0.18), in: .rect(cornerRadius: 8))
                }
                ForEach(placed(at: h)) { t in
                    HStack {
                        Text("◆ " + t.title).font(.caption.weight(.medium)).lineLimit(1)
                        Spacer()
                        Text(t.scheduledBlockStart?.formatted(date: .omitted, time: .shortened) ?? "").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(DS.Palette.accent.opacity(0.2), in: .rect(cornerRadius: 8))
                    .contextMenu { Button("Take off this day", systemImage: "calendar.badge.minus") { unplace(t) } }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .topLeading)
            .padding(4)
            .background(target == h ? DS.Palette.accent.opacity(0.12) : Color.clear, in: .rect(cornerRadius: 10))
            .overlay(alignment: .top) { Rectangle().fill(DS.Palette.inkSoft.opacity(0.15)).frame(height: 0.5) }
            .contentShape(Rectangle())
            .onTapGesture { if let t = picked { place(t, hour: h, half: false) } }
            .dropDestination(for: String.self) { ids, loc in
                guard let s = ids.first, let id = UUID(uuidString: s), let t = open.first(where: { $0.id == id }) else { return false }
                place(t, hour: h, half: loc.y > rowHeight / 2)
                return true
            } isTargeted: { on in withAnimation(.snappy) { target = on ? h : (target == h ? nil : target) } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(label)")
    }

    private func load() {
        events = CalendarService.shared.events(from: day, to: day.addingTimeInterval(86_400))
    }

    private func place(_ t: TaskItem, hour: Int, half: Bool) {
        guard let start = cal.date(bySettingHour: hour, minute: half ? 30 : 0, second: 0, of: day) else { return }
        let minutes = max(5, ADHDCoach.calibratedMinutes(t))
        removeBlocks(of: t)
        do {
            try CalendarService.shared.timeBlock(t, start: start, minutes: minutes)
        } catch {
            t.scheduledBlockStart = start          // still planned in Keel if the calendar can't be written
        }
        withAnimation(.snappy) {
            t.dueDate = start
            t.updatedAt = Date()
            picked = nil
        }
        try? CalendarService.shared.push(t)
        TaskAlerts.schedule(t)
        Haptics.success()
        UndoCenter.shared.notify("“\(t.title)” at \(start.formatted(date: .omitted, time: .shortened)) for \(minutes) min")
        load()
    }

    private func unplace(_ t: TaskItem) {
        removeBlocks(of: t)
        withAnimation(.snappy) { t.scheduledBlockStart = nil }
        load()
    }

    /// The task's earlier time block on this day, if any.
    private func removeBlocks(of t: TaskItem) {
        let tag = "keel-task:\(t.id.uuidString)"
        for e in CalendarService.shared.events(from: day, to: day.addingTimeInterval(86_400)) where e.notes == tag {
            try? CalendarService.shared.delete(e)
        }
    }
}

// MARK: - Booking link

/// Your own booking page: people pick a free time and it lands on your calendar.
/// Keel's server only ever receives the open times your iPhone works out, never your calendar.
@MainActor
enum BookingLink {
    static let onKey = "booking.on", urlKey = "booking.url", titleKey = "booking.title", minutesKey = "booking.minutes"
    static let daysKey = "booking.days", startKey = "booking.startHour", endKey = "booking.endHour"
    static let weekendsKey = "booking.weekends", noteKey = "booking.note", bufferKey = "booking.buffer"

    private static var d: UserDefaults { .standard }
    static var isOn: Bool { d.bool(forKey: onKey) }
    static var url: URL? { d.string(forKey: urlKey).flatMap(URL.init(string:)) }
    static var minutes: Int { let m = d.integer(forKey: minutesKey); return m > 0 ? m : 30 }
    static var title: String { let t = d.string(forKey: titleKey) ?? ""; return t.isEmpty ? "Meeting" : t }

    /// Open times for the next few days, in your working hours, at least 2 hours from now.
    static func slots(now: Date = Date()) -> [[String: String]] {
        let cal = Calendar.current
        let days = d.integer(forKey: daysKey) > 0 ? d.integer(forKey: daysKey) : 14
        let startH = d.object(forKey: startKey) as? Int ?? 9
        let endH = d.object(forKey: endKey) as? Int ?? 17
        let weekends = d.bool(forKey: weekendsKey)
        let buffer = Double(d.object(forKey: bufferKey) as? Int ?? 10) * 60
        let len = Double(minutes * 60)
        let iso = ISO8601DateFormatter()
        var out: [[String: String]] = []
        for i in 0..<days {
            guard let day = cal.date(byAdding: .day, value: i, to: cal.startOfDay(for: now)) else { continue }
            let wd = cal.component(.weekday, from: day)
            if !weekends && (wd == 1 || wd == 7) { continue }
            guard let open = cal.date(bySettingHour: startH, minute: 0, second: 0, of: day) else { continue }
            let from = max(open, now.addingTimeInterval(2 * 3600))
            for gap in CalendarService.shared.freeSlots(minMinutes: minutes, from: from, until: endH) {
                // Start on the next quarter hour, leave a little breathing room after meetings.
                var t = gap.start.addingTimeInterval(gap.start == from ? 0 : buffer)
                let q = cal.component(.minute, from: t) % 15
                if q != 0 { t = t.addingTimeInterval(Double((15 - q) * 60)) }
                t = Date(timeIntervalSince1970: (t.timeIntervalSince1970 / 60).rounded(.down) * 60)
                while t.addingTimeInterval(len) <= gap.end.addingTimeInterval(gap.end == cal.date(bySettingHour: endH, minute: 0, second: 0, of: day) ? 0 : -buffer) {
                    out.append(["start": iso.string(from: t), "end": iso.string(from: t.addingTimeInterval(len))])
                    t = t.addingTimeInterval(len >= 3600 ? len : 30 * 60)
                }
            }
        }
        return Array(out.prefix(400))
    }

    @discardableResult
    static func publish() async throws -> URL? {
        await CalendarService.shared.requestAccess()
        let body: [String: Any] = ["title": title, "minutes": minutes, "owner": d.string(forKey: "profile.name") ?? "",
                                   "note": d.string(forKey: noteKey) ?? "", "slots": slots()]
        let data = try await KeelCloud.call("booking", method: "POST", body: body, auth: true)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let s = obj?["url"] as? String { d.set(s, forKey: urlKey) }
        return url
    }

    static func turnOff() async {
        _ = try? await KeelCloud.call("booking", method: "DELETE", auth: true)
        d.set(false, forKey: onKey)
    }

    /// New bookings become calendar events (with the person's name, email and note), and you get a heads-up.
    static func pullRequests() async -> Int {
        guard let data = try? await KeelCloud.call("booking/requests", auth: true),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !list.isEmpty else { return 0 }
        let iso = ISO8601DateFormatter()
        let store = CalendarService.shared.store
        var made = 0
        for r in list {
            guard let s = (r["start"] as? String).flatMap(iso.date(from:)), let e = (r["end"] as? String).flatMap(iso.date(from:)) else { continue }
            let name = r["name"] as? String ?? "Someone", email = r["email"] as? String ?? ""
            let ev = EKEvent(eventStore: store)
            ev.calendar = store.defaultCalendarForNewEvents
            ev.title = "\(title) with \(name)"
            ev.startDate = s; ev.endDate = e
            ev.notes = "Booked through your Keel link.\nEmail: \(email)" + ((r["note"] as? String).map { $0.isEmpty ? "" : "\nNote: \($0)" } ?? "")
            ev.addAlarm(EKAlarm(relativeOffset: -10 * 60))
            guard (try? store.save(ev, span: .thisEvent)) != nil else { continue }
            made += 1
            let c = UNMutableNotificationContent()
            c.title = "New booking: \(name)"
            c.body = "\(title), \(s.formatted(date: .abbreviated, time: .shortened)). It's on your calendar."
            c.sound = .default
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "booking.\(s.timeIntervalSince1970)", content: c, trigger: nil))
        }
        CalendarService.shared.invalidateEvents()
        return made
    }

    /// From sync: bring in bookings, and keep the open times fresh (every 30 minutes, or right after a booking).
    static func refreshIfDue() async {
        guard isOn, KeelServer.isConfigured else { return }
        let made = await pullRequests()
        if made > 0 || Throttle.due("booking.publish", every: 1800) { _ = try? await publish() }
    }
}

struct BookingLinkView: View {
    @AppStorage(BookingLink.onKey) private var on = false
    @AppStorage(BookingLink.titleKey) private var title = ""
    @AppStorage(BookingLink.minutesKey) private var minutes = 30
    @AppStorage(BookingLink.daysKey) private var days = 14
    @AppStorage(BookingLink.startKey) private var startHour = 9
    @AppStorage(BookingLink.endKey) private var endHour = 17
    @AppStorage(BookingLink.weekendsKey) private var weekends = false
    @AppStorage(BookingLink.bufferKey) private var buffer = 10
    @AppStorage(BookingLink.noteKey) private var note = ""
    @AppStorage(BookingLink.urlKey) private var link = ""
    @State private var working = false
    @State private var error: String?
    @State private var openCount = 0

    var body: some View {
        Form {
            Section { TipView(BookingTip()) }
            Section {
                Toggle("Booking link", isOn: Binding(get: { on }, set: { v in on = v; Task { await apply(v) } }))
                if on, let url = URL(string: link), !link.isEmpty {
                    LabeledContent("Link") { Text(url.absoluteString).font(.caption).lineLimit(1).truncationMode(.middle).textSelection(.enabled) }
                    ShareLink(item: url) { Label("Share link", systemImage: "square.and.arrow.up") }
                    Button("Copy link", systemImage: "doc.on.doc") { UIPasteboard.general.url = url; UndoCenter.shared.notify("Link copied") }
                    Link(destination: url) { Label("See your page", systemImage: "safari") }
                    LabeledContent("Open times showing", value: "\(openCount)")
                }
                if working { HStack { ProgressView(); Text("Updating…") } }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            } footer: {
                Text(KeelServer.isConfigured
                     ? "People pick one of your free times and it's added to your calendar. Only the open times are sent to your Keel server, never your events."
                     : "Needs your Keel server (Settings → Sign in to Keel, or Optional AI Server).")
            }
            if on {
                let booked = CalendarService.shared.events(from: Date(), to: Date().addingTimeInterval(30 * 86_400))
                    .filter { ($0.notes ?? "").hasPrefix("Booked through your Keel link") }
                Section("Upcoming bookings") {
                    if booked.isEmpty { Text("None yet.").foregroundStyle(DS.Palette.inkSoft) }
                    ForEach(booked, id: \.eventIdentifier) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title ?? "Booking")
                            Text(e.startDate.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                }
            }
            Section("What people book") {
                TextField("Name it, e.g. Intro call", text: $title)
                Picker("Length", selection: $minutes) { ForEach([15, 20, 30, 45, 60, 90], id: \.self) { Text("\($0) min").tag($0) } }
                TextField("A short note for them (optional)", text: $note, axis: .vertical)
            }
            Section("When") {
                Picker("From", selection: $startHour) { ForEach(5..<15, id: \.self) { Text(hour($0)).tag($0) } }
                Picker("Until", selection: $endHour) { ForEach(12..<23, id: \.self) { Text(hour($0)).tag($0) } }
                Toggle("Weekends too", isOn: $weekends)
                Picker("Up to", selection: $days) { ForEach([7, 14, 21, 30], id: \.self) { Text("\($0) days ahead").tag($0) } }
                Picker("Gap after meetings", selection: $buffer) { ForEach([0, 5, 10, 15, 30], id: \.self) { Text($0 == 0 ? "None" : "\($0) min").tag($0) } }
            }
            if on {
                Section {
                    Button("Update open times now", systemImage: "arrow.clockwise") { Task { await apply(true) } }.disabled(working)
                } footer: { Text("Keel refreshes them by itself about every 30 minutes and right after each booking.") }
            }
        }
        .navigationTitle("Booking link")
        .onAppear { openCount = on ? BookingLink.slots().count : 0 }
        .onChange(of: minutes) { if on { Task { await apply(true) } } }
        .onChange(of: weekends) { if on { Task { await apply(true) } } }
    }

    private func hour(_ h: Int) -> String {
        (Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date()).formatted(date: .omitted, time: .shortened)
    }

    private func apply(_ v: Bool) async {
        working = true; error = nil
        defer { working = false }
        if v {
            do { _ = try await BookingLink.publish(); openCount = BookingLink.slots().count }
            catch { self.error = "Couldn't publish: \(error.localizedDescription)"; on = false }
        } else {
            await BookingLink.turnOff()
        }
    }
}
