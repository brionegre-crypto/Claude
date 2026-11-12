import SwiftUI
import SwiftData

/// Process loose tasks one at a time, so nothing piles up: do it now (2 min), schedule it,
/// it's waiting on someone, someday, or delete. Calm, one decision per screen.
struct ProcessInboxView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    @State private var showDate = false
    @State private var pickDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
    @State private var handled = 0

    /// Loose = no date, in the Inbox list, not someday/waiting, plus anything from the focus parking lot.
    private var queue: [TaskItem] {
        tasks.filter { !$0.isDone && !$0.isSomeday && !$0.isWaitingOn && (($0.dueDate == nil && $0.listName == "Inbox" && $0.projectId == nil) || $0.fromParkingLot) }
    }

    var body: some View {
        VStack(spacing: DS.Space.l) {
            if let t = queue.first {
                Text("\(queue.count) to sort").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                Spacer()
                VStack(spacing: DS.Space.s) {
                    if t.fromParkingLot { Chip(text: "From your parking lot", color: DS.Palette.focus, icon: "parkingsign") }
                    Text(t.title).font(DS.Font.hero).multilineTextAlignment(.center)
                    if !t.notes.isEmpty { Text(t.notes).font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft).lineLimit(3) }
                }
                .padding(.horizontal)
                Spacer()
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Space.s) {
                    choice("Do it now", "bolt.fill", DS.Palette.calm) { TaskActions.setDone(t, true); next(t) }
                    choice("Today", "sun.max.fill", DS.Palette.warmth) { TaskActions.reschedule(t, to: Date()); next(t) }
                    choice("Pick a date", "calendar", DS.Palette.meeting) { showDate = true }
                    choice("Waiting on…", "hourglass", .purple) { t.isWaitingOn = true; next(t) }
                    choice("Someday", "moon.zzz", .gray) { t.isSomeday = true; t.listName = "Someday"; next(t) }
                    choice("Delete", "trash", .red) { TaskActions.delete(t, ctx: ctx) ; handled += 1 }
                }
                Text("Takes under 2 minutes? Just do it now.").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    .sheet(isPresented: $showDate) {
                        NavigationStack {
                            DatePicker("When", selection: $pickDate, in: Date()..., displayedComponents: .date)
                                .datePickerStyle(.graphical).padding()
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button("Schedule") { TaskActions.reschedule(t, to: pickDate); showDate = false; next(t) }
                                    }
                                }
                        }
                        .presentationDetents([.medium, .large])
                    }
            } else {
                Spacer()
                Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(DS.Palette.calm).symbolEffect(.bounce, value: handled)
                Text(handled == 0 ? "Nothing to sort" : "All sorted").font(DS.Font.hero)
                Text(handled == 0 ? "New tasks without a date land here." : "\(handled) decided. Your head is clearer now.")
                    .font(DS.Font.body).foregroundStyle(DS.Palette.inkSoft)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent).tint(DS.Palette.accent)
            }
        }
        .padding()
        .navigationTitle("Sort tasks")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func next(_ t: TaskItem) {
        t.fromParkingLot = false
        t.updatedAt = Date()
        try? CalendarService.shared.push(t)
        handled += 1
        Haptics.tap()
    }

    private func choice(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title2)
                Text(title).font(DS.Font.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(color.opacity(0.14), in: .rect(cornerRadius: DS.Radius.card))
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }
}

/// During focus: park a stray thought in one tap and get back to work. Reviewed in "Sort tasks" afterwards.
struct ParkingLotField: View {
    @Environment(\.modelContext) private var ctx
    @State private var text = ""
    @State private var parked = 0

    var body: some View {
        HStack {
            Image(systemName: "parkingsign.circle.fill").foregroundStyle(DS.Palette.focus)
            TextField("Distracting thought? Park it here", text: $text)
                .onSubmit {
                    guard !text.isEmpty else { return }
                    let t = TaskItem(title: text)
                    t.fromParkingLot = true
                    ctx.insert(t)
                    text = ""; parked += 1
                    Haptics.tap()
                }
            if parked > 0 { Text("\(parked) parked").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft) }
        }
        .padding(DS.Space.s)
        .background(DS.Palette.elevated, in: Capsule())
    }
}
