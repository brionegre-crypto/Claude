import SwiftUI
import EventKit

// MARK: - Calendar clashes, and "can't make it" with new times

@MainActor
enum CalendarClashes {
    static let onKey = "custom.today.clashes"
    static var isOn: Bool { UserDefaults.standard.object(forKey: onKey) as? Bool ?? true }

    struct Clash: Identifiable { let a: EKEvent; let b: EKEvent; var id: String { a.calendarItemIdentifier + b.calendarItemIdentifier + "\(a.startDate.timeIntervalSince1970)" } }

    /// Timed events in the next week that overlap (Keel's own buffers and routines don't count).
    static func next(days: Int = 7) -> [Clash] {
        let evs = CalendarService.shared.events(from: Date(), to: Date().addingTimeInterval(Double(days) * 86_400))
            .filter { !$0.isAllDay && !(($0.notes ?? "").contains("keel-buffer") || ($0.notes ?? "").contains("keel-routine")) && $0.availability != .free }
            .sorted { $0.startDate < $1.startDate }
        var out: [Clash] = []
        for (i, a) in evs.enumerated() {
            for b in evs.dropFirst(i + 1) {
                if b.startDate >= a.endDate { break }
                if a.calendarItemIdentifier != b.calendarItemIdentifier { out.append(Clash(a: a, b: b)) }
            }
        }
        return out
    }

    /// Up to three free times over the next working days that fit this event's length.
    static func alternatives(for e: EKEvent, count: Int = 3) -> [Date] {
        let cal = Calendar.current
        let minutes = max(15, Int(e.endDate.timeIntervalSince(e.startDate) / 60))
        var out: [Date] = []
        var day = cal.startOfDay(for: max(Date(), e.startDate))
        for _ in 0..<10 where out.count < count {
            if !cal.isDateInWeekend(day) {
                let start = max(Date(), cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day)
                if let slot = CalendarService.shared.freeSlots(minMinutes: minutes, from: start, until: 17).first(where: { !cal.isDate($0.start, inSameDayAs: e.startDate) || $0.start > e.endDate }) {
                    out.append(slot.start)
                }
            }
            day = cal.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return out
    }

    /// An email to the organizer: sorry, can't make it, here are times that work.
    static func regretsDraft(for e: EKEvent) -> ComposeDraft? {
        guard let org = e.organizer, !org.isCurrentUser else { return nil }
        let email = org.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
        guard email.contains("@") else { return nil }
        let first = org.name?.split(separator: " ").first.map(String.init) ?? "there"
        let times = alternatives(for: e).map { "• " + $0.formatted(.dateTime.weekday(.wide).month().day().hour().minute()) }
        var body = "Hi \(first),\n\nSorry, I can't make \(e.title ?? "our meeting") on \(e.startDate.formatted(.dateTime.weekday(.wide).month().day().hour().minute())). "
        body += times.isEmpty ? "Could we find another time?" : "Would one of these work instead?\n\n" + times.joined(separator: "\n")
        body += "\n\nThanks,\n"
        return ComposeDraft(to: email, subject: "Re: \(e.title ?? "Meeting")", body: body)
    }
}

/// Today: overlapping events this week, with a fix.
struct ClashesCard: View {
    @AppStorage(CalendarClashes.onKey) private var on = true
    @State private var clashes: [CalendarClashes.Clash] = []
    @State private var fixing = false

    var body: some View {
        Group {
            if on && !clashes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(clashes.count) calendar clash\(clashes.count == 1 ? "" : "es") this week", systemImage: "exclamationmark.triangle.fill")
                        .font(DS.Font.headline).foregroundStyle(DS.Palette.warmth)
                    ForEach(clashes.prefix(2)) { c in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(c.a.title ?? "Event") ↔ \(c.b.title ?? "Event")").font(DS.Font.body).lineLimit(1)
                            Text(c.b.startDate.formatted(.dateTime.weekday(.abbreviated).hour().minute())).font(.caption).foregroundStyle(DS.Palette.inkSoft)
                            HStack {
                                ForEach([c.a, c.b], id: \.calendarItemIdentifier) { e in
                                    if let d = CalendarClashes.regretsDraft(for: e) {
                                        Button("Can't make \(String((e.title ?? "it").prefix(14)))") { MailRouter.shared.pending = d }
                                            .buttonStyle(.bordered).controlSize(.small)
                                    }
                                }
                                Button("Move one") { fixing = true }.buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                }
                .padding(DS.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { PremiumSurface(tint: DS.Palette.warmth) }
                .sheet(isPresented: $fixing) { NavigationStack { CalendarAIView() } }
            }
        }
        .task {
            guard on else { return }
            try? await Task.sleep(for: .milliseconds(500))           // after Today has appeared
            clashes = CalendarClashes.next()
        }
    }
}

// MARK: - Checks before sending

enum SendChecks {
    /// Things you'd probably want to know before an email goes: a missing attachment, no subject, lots of people.
    static func warnings(body: String, subject: String, attachments: Int, recipients: Int, isForward: Bool) -> [String] {
        var out: [String] = []
        let mine = (body.components(separatedBy: "\n>").first ?? body).lowercased()
        let words = ["attached", "attachment", "i've attached", "i have attached", "enclosed", "see the file", "find the file", "here's the file", "pdf attached"]
        if attachments == 0 && !isForward && words.contains(where: { mine.contains($0) }) {
            out.append("You mention an attachment, but nothing is attached.")
        }
        if subject.trimmingCharacters(in: .whitespaces).isEmpty { out.append("There's no subject.") }
        if recipients > 8 { out.append("This goes to \(recipients) people.") }
        return out
    }
}
