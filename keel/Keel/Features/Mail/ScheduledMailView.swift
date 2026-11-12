import SwiftUI
import SwiftData

/// Inbox → Scheduled: emails waiting to send. Send now, change the time, or cancel.
struct ScheduledMailView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \ScheduledMail.sendAt) private var items: [ScheduledMail]
    @State private var rescheduling: ScheduledMail?
    @State private var newTime = Date()
    @State private var sending: UUID?

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView("Nothing scheduled", systemImage: "clock.badge.checkmark",
                                       description: Text("When writing an email, hold the send button to send it later."))
            }
            ForEach(items) { s in
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.subject.isEmpty ? "(No subject)" : s.subject).font(DS.Font.headline)
                    Text("To \(s.to.joined(separator: ", "))").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(1)
                    Label(s.sendAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.accent)
                    if let e = s.lastError { Text("Last try failed: \(e)").font(DS.Font.caption).foregroundStyle(.red) }
                    if sending == s.id { ProgressView() }
                }
                .swipeActions {
                    Button("Cancel", role: .destructive) { ctx.delete(s) }
                    Button("Send now") { sendNow(s) }.tint(DS.Palette.accent)
                }
                .contextMenu {
                    Button("Send now", systemImage: "paperplane") { sendNow(s) }
                    Button("Change time", systemImage: "calendar.badge.clock") { newTime = s.sendAt; rescheduling = s }
                    Button("Cancel send", systemImage: "trash", role: .destructive) { ctx.delete(s) }
                }
            }
        }
        .navigationTitle("Scheduled")
        .sheet(item: $rescheduling) { s in
            NavigationStack {
                DatePicker("Send at", selection: $newTime, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical).padding()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { s.sendAt = newTime; s.lastError = nil; SyncEngine.scheduleRefresh(at: newTime); rescheduling = nil }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func sendNow(_ s: ScheduledMail) {
        s.sendAt = Date()
        sending = s.id
        Task { await SendLater.sendDue(ctx: ctx); sending = nil; Haptics.success() }
    }
}
