import SwiftUI
import SwiftData

/// Subscriptions & bills found in your email, with a monthly total and renewal reminders.
struct SubscriptionsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Subscription.name) private var all: [Subscription]
    @State private var showHidden = false

    @AppStorage("bills.autoTask") private var billTasks = true

    private var visible: [Subscription] { all.filter { !$0.isHidden } }

    var body: some View {
        List {
            let subs = visible.filter { $0.kind == "subscription" }
            let bills = visible.filter { $0.kind == "bill" }
            let trials = visible.filter { $0.kind == "trial" && ($0.nextDate ?? .distantPast) > Date().addingTimeInterval(-86_400) }
            let month = Date().addingTimeInterval(30 * 86_400)
            let comingUp = visible.filter { s in s.nextDate.map { $0 >= Calendar.current.startOfDay(for: Date()) && $0 <= month } ?? false }
                .sorted { ($0.nextDate ?? .distantFuture) < ($1.nextDate ?? .distantFuture) }
            Section {
                let monthly = subs.reduce(0) { $0 + $1.monthlyCost }
                let due30 = comingUp.filter { $0.kind != "trial" }.reduce(0) { $0 + $1.amount }
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%@%.2f / month", subs.first?.currency ?? "$", monthly)).font(.system(.largeTitle, design: .rounded).weight(.bold))
                    Text(String(format: "About %@%.0f a year across %d subscriptions", subs.first?.currency ?? "$", monthly * 12, subs.count))
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    if due30 > 0 {
                        Label(String(format: "%@%.2f going out in the next 30 days", visible.first?.currency ?? "$", due30), systemImage: "calendar")
                            .font(DS.Font.caption).foregroundStyle(DS.Palette.ink).padding(.top, 4)
                    }
                }
            } footer: { Text("Found in receipts, bills and trial emails, on this iPhone. Swipe to hide anything that isn't right.") }
            if !trials.isEmpty {
                Section {
                    ForEach(trials.sorted { ($0.nextDate ?? .distantFuture) < ($1.nextDate ?? .distantFuture) }) { row($0) }
                } header: { Label("Free trials ending", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) } footer: {
                    Text("Keel warns you 2 days before a trial turns into a charge. Cancel in the app or website you signed up with.")
                }
            }
            if !comingUp.isEmpty {
                Section("Coming up") {
                    ForEach(comingUp) { s in
                        HStack {
                            Text(s.nextDate?.formatted(.dateTime.month(.abbreviated).day()) ?? "").font(DS.Font.caption.monospacedDigit())
                                .foregroundStyle(DS.Palette.inkSoft).frame(width: 52, alignment: .leading)
                            Image(systemName: icon(s)).foregroundStyle(color(s))
                            Text(s.name).lineLimit(1)
                            Spacer()
                            Text(s.amount > 0 ? String(format: "%@%.2f", s.currency, s.amount) : "Free").monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if !bills.isEmpty {
                Section("Bills") { ForEach(bills.sorted { ($0.nextDate ?? .distantFuture) < ($1.nextDate ?? .distantFuture) }) { row($0) } }
            }
            Section("Subscriptions") {
                if subs.isEmpty { Text("None found yet. Receipts show up here as they arrive.").foregroundStyle(DS.Palette.inkSoft) }
                ForEach(subs.sorted { $0.monthlyCost > $1.monthlyCost }) { row($0) }
            }
            Section {
                Toggle("Add Bills as Tasks", isOn: $billTasks)
            } footer: { Text("Each bill gets a “Pay …” task on its due date, with an alert that morning.") }
            .onChange(of: billTasks) { if billTasks { MailScanners.addBillTasks(ctx: ctx) } }
            if all.contains(where: \.isHidden) {
                Section {
                    Toggle("Show hidden", isOn: $showHidden)
                    if showHidden {
                        ForEach(all.filter(\.isHidden)) { s in
                            Button("\(s.name): show again") { s.isHidden = false }
                        }
                    }
                }
            }
        }
        .navigationTitle("Bills & Money")
        .onAppear { MailScanners.backfillIfNeeded(ctx: ctx) }
    }

    private func icon(_ s: Subscription) -> String {
        s.kind == "trial" ? "hourglass" : s.kind == "bill" ? "doc.text.fill" : "arrow.triangle.2.circlepath"
    }
    private func color(_ s: Subscription) -> Color {
        s.kind == "trial" ? .red : s.kind == "bill" ? DS.Palette.warmth : DS.Palette.accent
    }

    private func row(_ s: Subscription) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name).font(DS.Font.headline)
                if let n = s.nextDate {
                    Text("\(s.kind == "trial" ? "Trial ends" : s.kind == "bill" ? "Due" : "Renews") \(n.formatted(date: .abbreviated, time: .omitted))")
                        .font(DS.Font.caption).foregroundStyle(n < Date().addingTimeInterval(3 * 86_400) ? (s.kind == "trial" ? .red : DS.Palette.warmth) : DS.Palette.inkSoft)
                }
                let before = UserDefaults.standard.double(forKey: "price.up.\(s.key)")
                if before > 0 && before < s.amount {
                    Label(String(format: "Up from %@%.2f", s.currency, before), systemImage: "arrow.up.right")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.red)
                }
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(String(format: "%@%.2f", s.currency, s.amount)).monospacedDigit()
                Text(s.period).font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
            }
        }
        .swipeActions {
            Button("Hide") { s.isHidden = true }.tint(.gray)
            if s.kind != "bill", let url = cancelHelp(s) {
                Button("How to Cancel") { UIApplication.shared.open(url) }.tint(.red)
            }
            if s.kind == "bill" {
                Button("Task") {
                    _ = QuickAdd.create("Pay \(s.name) bill \(String(format: "%@%.2f", s.currency, s.amount))", in: ctx, defaultDue: s.nextDate)
                    Haptics.success()
                }.tint(DS.Palette.accent)
            }
        }
        .contextMenu {
            Picker("Billed", selection: Binding(get: { s.period }, set: { s.period = $0 })) {
                Text("Weekly").tag("weekly"); Text("Monthly").tag("monthly"); Text("Yearly").tag("yearly")
            }
            Toggle("Remind before renewal", isOn: Binding(get: { s.remind }, set: { s.remind = $0; MailScanners.scheduleRenewalReminders(ctx: ctx) }))
            Button(s.kind == "bill" ? "It's a subscription" : "It's a bill") { s.kind = s.kind == "bill" ? "subscription" : "bill" }
            if s.kind != "bill", let url = cancelHelp(s) {
                Button("How to Cancel", systemImage: "xmark.circle") { UIApplication.shared.open(url) }
            }
            Button("Not a subscription", systemImage: "eye.slash", role: .destructive) { s.isHidden = true }
        }
    }

    /// A web search for the merchant's own cancellation steps (only the merchant name is sent).
    private func cancelHelp(_ s: Subscription) -> URL? {
        let q = "how to cancel \(s.name) subscription".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://duckduckgo.com/?q=\(q)")
    }
}

/// Packages on the way, from shipping emails.
struct DeliveriesView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.openURL) private var openURL
    @Query(sort: \Delivery.updatedAt, order: .reverse) private var all: [Delivery]

    var body: some View {
        List {
            let active = all.filter { !$0.isArchived && $0.status != "delivered" }
            let done = all.filter { !$0.isArchived && $0.status == "delivered" }
            Section("On the way") {
                if active.isEmpty { Text("Nothing on the way. Shipping emails show up here automatically.").foregroundStyle(DS.Palette.inkSoft) }
                ForEach(active) { row($0) }
            }
            if !done.isEmpty { Section("Delivered") { ForEach(done.prefix(15)) { row($0) } } }
        }
        .navigationTitle("Deliveries")
        .onAppear { MailScanners.backfillIfNeeded(ctx: ctx) }
    }

    private func row(_ d: Delivery) -> some View {
        Button { if let u = d.trackURL { openURL(u) } } label: {
            HStack(spacing: DS.Space.m) {
                Image(systemName: icon(d.status)).font(.title3).foregroundStyle(d.status == "delivered" ? DS.Palette.calm : DS.Palette.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.title).foregroundStyle(DS.Palette.ink).lineLimit(2)
                    Text("\(d.carrier) · \(label(d))").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                Spacer()
                if d.trackURL != nil { Image(systemName: "arrow.up.right.square").foregroundStyle(DS.Palette.inkSoft) }
            }
        }
        .swipeActions {
            Button("Remove") { d.isArchived = true }.tint(.gray)
            if d.status != "delivered" { Button("Got it") { d.status = "delivered"; Haptics.success() }.tint(DS.Palette.calm) }
        }
    }

    private func icon(_ s: String) -> String {
        switch s { case "delivered": "shippingbox.fill"; case "out": "truck.box.fill"; default: "shippingbox" }
    }

    private func label(_ d: Delivery) -> String {
        switch d.status {
        case "delivered": return "Delivered"
        case "out": return "Out for delivery today"
        default:
            guard let e = d.expected else { return "Shipped" }
            return Calendar.current.isDateInToday(e) ? "Arriving today" : Calendar.current.isDateInTomorrow(e) ? "Arriving tomorrow" : "Arriving \(e.formatted(.dateTime.weekday(.wide).month().day()))"
        }
    }
}

/// Today: packages arriving today, and bills due within 3 days.
struct FoundInMailTodayCard: View {
    @Query private var deliveries: [Delivery]
    @Query private var subs: [Subscription]

    var body: some View {
        let today = deliveries.filter { !$0.isArchived && ($0.status == "out" || ($0.status == "shipped" && ($0.expected.map(Calendar.current.isDateInToday) ?? false))) }
        let soon = Date().addingTimeInterval(3 * 86_400)
        let bills = subs.filter { !$0.isHidden && $0.kind == "bill" && ($0.nextDate.map { $0 > Date() && $0 < soon } ?? false) }
        if !today.isEmpty || !bills.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    if !today.isEmpty {
                        NavigationLink { DeliveriesView() } label: {
                            Label("\(today.count) package\(today.count == 1 ? "" : "s") arriving today", systemImage: "truck.box.fill").font(DS.Font.headline)
                        }.buttonStyle(.plain)
                        ForEach(today.prefix(3)) { Text("· \($0.title)").font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft).lineLimit(1) }
                    }
                    if !bills.isEmpty {
                        NavigationLink { SubscriptionsView() } label: {
                            Label("\(bills.count) bill\(bills.count == 1 ? "" : "s") due soon", systemImage: "creditcard.fill").font(DS.Font.headline)
                        }.buttonStyle(.plain)
                        ForEach(bills) { b in
                            Text("· \(b.name) \(String(format: "%@%.2f", b.currency, b.amount)), \(b.nextDate!.formatted(.dateTime.weekday(.abbreviated)))")
                                .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                }
            }
        }
    }
}
