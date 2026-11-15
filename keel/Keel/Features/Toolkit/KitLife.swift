import SwiftUI

// MARK: - Life admin tools

// 28. Where did I put it?

struct KitStash: Codable, Identifiable, Hashable { var id = UUID(); var item: String; var place: String; var date = Date() }

struct KitWhereView: View {
    static let key = "kit.stash"
    @State private var list: [KitStash] = []
    @State private var item = ""
    @State private var place = ""
    @State private var search = ""

    var body: some View {
        List {
            Section { KitIntro(icon: "magnifyingglass.circle.fill", color: .brown, text: "Where did I put it? When you put something somewhere \"safe\" (passport, spare key, the warranty), note it here. Later, just search.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section("I just put…") {
                TextField("Item (spare key, passport…)", text: $item)
                TextField("Place (blue box, top shelf in hall…)", text: $place)
                Button("Remember it") {
                    list.removeAll { $0.item.lowercased() == item.lowercased() }
                    list.insert(KitStash(item: item, place: place), at: 0); Kit.save(list, Self.key)
                    item = ""; place = ""; Haptics.success()
                }
                .disabled(item.isEmpty || place.isEmpty)
            }
            Section {
                ForEach(filtered) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.item).font(.headline)
                        Label(s.place, systemImage: "mappin").font(.callout)
                        Text("Since \(s.date.formatted(date: .abbreviated, time: .omitted))").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                    }
                }
                .onDelete { idx in
                    let ids = idx.map { filtered[$0].id }
                    list.removeAll { ids.contains($0.id) }; Kit.save(list, Self.key)
                }
            }
        }
        .searchable(text: $search, prompt: "Where's my…")
        .navigationTitle("Where did I put it?")
        .onAppear { list = Kit.load(Self.key) }
    }
    private var filtered: [KitStash] {
        search.isEmpty ? list : list.filter { $0.item.localizedCaseInsensitiveContains(search) || $0.place.localizedCaseInsensitiveContains(search) }
    }
}

// 29. Parking.

struct KitParkingView: View {
    @AppStorage("kitlocal.park.spot") private var spot = ""
    @AppStorage("kitlocal.park.at") private var parkedAt: Double = 0
    @AppStorage("kitlocal.park.meter") private var meterEnds: Double = 0
    @State private var draft = ""
    @State private var meterMinutes = 60

    var body: some View {
        List {
            Section { KitIntro(icon: "car.fill", color: .blue, text: "Parking. Note where you parked (level, row, street) and, if there's a meter or a time limit, Keel warns you 10 minutes before it runs out.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            if parkedAt > 0 {
                Section("Your car") {
                    Text(spot.isEmpty ? "Parked" : spot).font(.title3.weight(.semibold))
                    Text("Since \(Date(timeIntervalSince1970: parkedAt).formatted(date: .omitted, time: .shortened))").foregroundStyle(DS.Palette.inkSoft)
                    if meterEnds > Date().timeIntervalSince1970 {
                        TimelineView(.periodic(from: .now, by: 1)) { tl in
                            let left = Int(Date(timeIntervalSince1970: meterEnds).timeIntervalSince(tl.date))
                            Label("Time left: \(Kit.clock(left))", systemImage: "timer").monospacedDigit().foregroundStyle(left < 900 ? .orange : DS.Palette.ink)
                        }
                    }
                    Button("I'm back at the car", systemImage: "checkmark") {
                        parkedAt = 0; spot = ""; meterEnds = 0; Kit.cancel(["kit.park.10", "kit.park.0"]); Haptics.success()
                    }
                }
            } else {
                Section("I just parked") {
                    TextField("Level 3, row F / Elm Street", text: $draft)
                    Stepper(meterMinutes == 0 ? "No time limit" : "Time limit: \(Kit.minutes(meterMinutes))", value: $meterMinutes, in: 0...600, step: 15)
                    Button("Save", systemImage: "parkingsign.circle.fill") { park() }
                }
            }
        }
        .navigationTitle("Parking")
    }
    private func park() {
        spot = draft; draft = ""; parkedAt = Date().timeIntervalSince1970
        if meterMinutes > 0 {
            let end = Date().addingTimeInterval(Double(meterMinutes * 60))
            meterEnds = end.timeIntervalSince1970
            Kit.notify("kit.park.10", title: "Parking runs out in 10 minutes", body: spot.isEmpty ? "Head back to the car." : spot, at: end.addingTimeInterval(-600))
            Kit.notify("kit.park.0", title: "Parking time is up", body: spot, at: end)
        } else { meterEnds = 0 }
        Haptics.success()
    }
}

// 30. Returns & warranties.

struct KitPurchase: Codable, Identifiable, Hashable {
    var id = UUID(); var item: String; var store: String; var bought = Date(); var returnBy: Date?; var warrantyUntil: Date?; var returned = false
}

struct KitReturnsView: View {
    static let key = "kit.returns"
    @State private var list: [KitPurchase] = []
    @State private var item = ""
    @State private var store = ""
    @State private var returnDays = 30
    @State private var warrantyYears = 1

    var body: some View {
        List {
            Section { KitIntro(icon: "shippingbox.and.arrow.backward.fill", color: .orange, text: "Returns & warranties. Note what you bought and how long you have to return it. Keel reminds you 3 days before the return window closes, and keeps the warranty date for when something breaks.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section("New purchase") {
                TextField("Item", text: $item)
                TextField("Store", text: $store)
                Stepper(returnDays == 0 ? "No returns" : "Return within \(returnDays) days", value: $returnDays, in: 0...365, step: returnDays < 30 ? 7 : 15)
                Stepper(warrantyYears == 0 ? "No warranty" : "Warranty \(warrantyYears) year\(warrantyYears == 1 ? "" : "s")", value: $warrantyYears, in: 0...10)
                Button("Add") { add() }.disabled(item.isEmpty)
            }
            let open = list.filter { !$0.returned && ($0.returnBy ?? .distantPast) > Date() }.sorted { ($0.returnBy ?? .distantFuture) < ($1.returnBy ?? .distantFuture) }
            if !open.isEmpty {
                Section("Return window open") {
                    ForEach(open) { p in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(p.item)
                                Text("\(p.store) · until \(p.returnBy?.formatted(date: .abbreviated, time: .omitted) ?? "")").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                            }
                            Spacer()
                            Button("Returned") { mark(p) }.buttonStyle(.bordered).font(.caption)
                        }
                    }
                }
            }
            Section("Warranties") {
                ForEach(list.filter { $0.warrantyUntil != nil }) { p in
                    let valid = (p.warrantyUntil ?? .distantPast) > Date()
                    HStack {
                        Text(p.item)
                        Spacer()
                        Text(valid ? "until \(p.warrantyUntil!.formatted(date: .abbreviated, time: .omitted))" : "expired").font(.caption)
                            .foregroundStyle(valid ? DS.Palette.calm : DS.Palette.inkSoft)
                    }
                }
                .onDelete { idx in
                    let withW = list.filter { $0.warrantyUntil != nil }
                    let ids = idx.map { withW[$0].id }
                    list.removeAll { ids.contains($0.id) }; Kit.save(list, Self.key)
                }
            }
        }
        .navigationTitle("Returns & warranties")
        .onAppear { list = Kit.load(Self.key) }
    }
    private func add() {
        let cal = Calendar.current
        let p = KitPurchase(item: item, store: store,
                            returnBy: returnDays > 0 ? cal.date(byAdding: .day, value: returnDays, to: Date()) : nil,
                            warrantyUntil: warrantyYears > 0 ? cal.date(byAdding: .year, value: warrantyYears, to: Date()) : nil)
        list.insert(p, at: 0); Kit.save(list, Self.key)
        if let r = p.returnBy, let remind = cal.date(byAdding: .day, value: -3, to: r).flatMap({ cal.date(bySettingHour: 10, minute: 0, second: 0, of: $0) }) {
            Kit.notify("kit.return.\(p.id)", title: "Return \(p.item)?", body: "The return window at \(p.store.isEmpty ? "the store" : p.store) closes in 3 days.", at: remind)
        }
        item = ""; store = ""; Haptics.success()
    }
    private func mark(_ p: KitPurchase) {
        if let i = list.firstIndex(of: p) { list[i].returned = true }
        Kit.save(list, Self.key); Kit.cancel(["kit.return.\(p.id)"]); Haptics.success()
    }
}

// 31. Impulse-buy waiting list.

struct KitWant: Codable, Identifiable, Hashable { var id = UUID(); var item: String; var price: Double; var added = Date(); var days: Int; var outcome: String? }

struct KitWaitlistView: View {
    static let key = "kit.waitlist"
    @State private var list: [KitWant] = []
    @State private var item = ""
    @State private var price = ""
    @State private var days = 30

    var body: some View {
        let saved = list.filter { $0.outcome == "skip" }.reduce(0) { $0 + $1.price }
        List {
            Section { KitIntro(icon: "hourglass.bottomhalf.filled", color: .mint, text: "Impulse waiting list. Want to buy something on a whim? Put it here instead. After the wait (a week or 30 days), Keel asks if you still want it. Most of the time you won't, and you see exactly how much you saved.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section {
                KitStat(value: Kit.money(saved), label: "saved by waiting", color: .mint)
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section("I want…") {
                TextField("Item", text: $item)
                TextField("Price", text: $price).keyboardType(.decimalPad)
                Picker("Wait", selection: $days) { Text("1 week").tag(7); Text("30 days").tag(30) }.pickerStyle(.segmented)
                Button("Add to the waiting list") { add() }.disabled(item.isEmpty)
            }
            Section("Waiting") {
                ForEach(list.filter { $0.outcome == nil }) { w in
                    let ready = Date() >= Calendar.current.date(byAdding: .day, value: w.days, to: w.added) ?? Date()
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(w.item); Spacer(); Text(Kit.money(w.price)).foregroundStyle(DS.Palette.inkSoft) }
                        if ready {
                            HStack {
                                Text("Still want it?").font(.caption.weight(.semibold))
                                Spacer()
                                Button("Skip it") { decide(w, "skip") }.buttonStyle(.borderedProminent).tint(.mint)
                                Button("Buy it") { decide(w, "buy") }.buttonStyle(.bordered)
                            }
                            .font(.caption)
                        } else {
                            Text("Decide on \((Calendar.current.date(byAdding: .day, value: w.days, to: w.added) ?? Date()).formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(DS.Palette.inkSoft)
                        }
                    }
                }
            }
        }
        .navigationTitle("Impulse waiting list")
        .onAppear { list = Kit.load(Self.key) }
    }
    private func add() {
        let w = KitWant(item: item, price: Double(price.replacingOccurrences(of: ",", with: ".")) ?? 0, days: days)
        list.insert(w, at: 0); Kit.save(list, Self.key)
        if let at = Calendar.current.date(byAdding: .day, value: days, to: Date()) {
            Kit.notify("kit.want.\(w.id)", title: "Still want \(w.item)?", body: "Your wait is over. Decide in Keel: skip it or buy it.", at: at)
        }
        item = ""; price = ""; Haptics.success()
    }
    private func decide(_ w: KitWant, _ o: String) {
        if let i = list.firstIndex(of: w) { list[i].outcome = o }
        Kit.save(list, Self.key); Haptics.success()
    }
}

// 32. No-spend days.

struct KitNoSpendView: View {
    @AppStorage("kit.nospend.days") private var raw = ""
    private var days: Set<String> { Set(raw.split(separator: ",").map(String.init)) }

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let month = (0..<35).compactMap { cal.date(byAdding: .day, value: -34 + $0, to: today) }
        List {
            Section { KitIntro(icon: "creditcard.trianglebadge.exclamationmark", color: .green, text: "No-spend days. Tap a day when you spent nothing beyond the essentials (bills, groceries you planned). Watch the streak grow; it makes saving feel like a game.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section {
                HStack {
                    KitStat(value: "\(Kit.streak(days))", label: "day streak", color: .green)
                    KitStat(value: "\(month.filter { days.contains(Kit.dayKey($0)) }.count)", label: "in the last 5 weeks", color: .green)
                }
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section("Tap a day") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(month, id: \.self) { d in
                        let on = days.contains(Kit.dayKey(d))
                        Button { toggle(d) } label: {
                            Text(d.formatted(.dateTime.day())).font(.caption.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 34)
                                .background(on ? Color.green.opacity(0.8) : DS.Palette.canvas, in: .rect(cornerRadius: 8))
                                .foregroundStyle(on ? .white : DS.Palette.ink)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("No-spend days")
    }
    private func toggle(_ d: Date) {
        var s = days; let k = Kit.dayKey(d)
        if s.contains(k) { s.remove(k) } else { s.insert(k); Haptics.tap() }
        raw = s.sorted().suffix(800).joined(separator: ",")
    }
}

// 33. Savings jars.

struct KitJar: Codable, Identifiable, Hashable { var id = UUID(); var name: String; var goal: Double; var saved: Double = 0 }

struct KitJarsView: View {
    static let key = "kit.jars"
    @State private var jars: [KitJar] = []
    @State private var name = ""
    @State private var goal = ""
    @State private var depositFor: KitJar?
    @State private var amount = ""

    var body: some View {
        List {
            Section { KitIntro(icon: "banknote.fill", color: .green, text: "Savings jars. Give each goal its own jar (holiday, new laptop, emergency fund) and log what you put in. Seeing each jar fill up keeps the goal real.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            ForEach(jars) { j in
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(j.name).font(.headline); Spacer(); Text("\(Kit.money(j.saved)) of \(Kit.money(j.goal))").font(.caption).monospacedDigit() }
                        ProgressView(value: min(j.saved, j.goal), total: max(j.goal, 1)).tint(.green)
                        Button("Add money") { depositFor = j; amount = "" }.font(.caption)
                    }
                }
            }
            .onDelete { jars.remove(atOffsets: $0); Kit.save(jars, Self.key) }
            Section("New jar") {
                TextField("What for?", text: $name)
                TextField("Goal amount", text: $goal).keyboardType(.decimalPad)
                Button("Add jar") {
                    jars.append(KitJar(name: name, goal: Double(goal.replacingOccurrences(of: ",", with: ".")) ?? 0)); Kit.save(jars, Self.key); name = ""; goal = ""
                }
                .disabled(name.isEmpty)
            }
        }
        .navigationTitle("Savings jars")
        .onAppear { jars = Kit.load(Self.key) }
        .alert("Add to \(depositFor?.name ?? "")", isPresented: Binding(get: { depositFor != nil }, set: { if !$0 { depositFor = nil } })) {
            TextField("Amount", text: $amount).keyboardType(.decimalPad)
            Button("Add") {
                if let j = depositFor, let i = jars.firstIndex(of: j) {
                    jars[i].saved += Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0
                    Kit.save(jars, Self.key)
                    if jars[i].saved >= jars[i].goal, jars[i].goal > 0 { Haptics.milestone() } else { Haptics.success() }
                }
                depositFor = nil
            }
            Button("Cancel", role: .cancel) { depositFor = nil }
        }
    }
}

// 34. Tip & split.

enum KitSplit {
    static func perPerson(bill: Double, tipPercent: Double, people: Int) -> (tip: Double, total: Double, each: Double) {
        let tip = bill * tipPercent / 100
        let total = bill + tip
        return (tip, total, total / Double(max(1, people)))
    }
}

struct KitTipSplitView: View {
    @State private var bill = ""
    @State private var tip = 18.0
    @State private var people = 2

    var body: some View {
        let r = KitSplit.perPerson(bill: Double(bill.replacingOccurrences(of: ",", with: ".")) ?? 0, tipPercent: tip, people: people)
        Form {
            Section { KitIntro(icon: "person.2.fill", color: .teal, text: "Tip & split. Enter the bill, pick a tip and how many people, and see exactly what each person pays. No mental maths at the end of a meal.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section {
                TextField("Bill", text: $bill).keyboardType(.decimalPad).font(.title2)
                VStack(alignment: .leading) {
                    Text("Tip \(Int(tip))%")
                    Slider(value: $tip, in: 0...30, step: 1)
                }
                Stepper("\(people) \(people == 1 ? "person" : "people")", value: $people, in: 1...30)
            }
            Section {
                LabeledContent("Tip", value: Kit.money(r.tip))
                LabeledContent("Total", value: Kit.money(r.total))
                LabeledContent("Each pays") { Text(Kit.money(r.each)).font(.title2.weight(.bold)).foregroundStyle(.teal) }
            }
        }
        .navigationTitle("Tip & split")
    }
}

// 35. Better deal: compare unit prices.

enum KitDeal {
    /// Price per unit for each, and how much cheaper the better one is (percent).
    static func compare(priceA: Double, qtyA: Double, priceB: Double, qtyB: Double) -> (a: Double, b: Double, saving: Double)? {
        guard qtyA > 0, qtyB > 0, priceA > 0, priceB > 0 else { return nil }
        let a = priceA / qtyA, b = priceB / qtyB
        return (a, b, abs(a - b) / max(a, b) * 100)
    }
}

struct KitDealView: View {
    @State private var pa = ""
    @State private var qa = ""
    @State private var pb = ""
    @State private var qb = ""

    var body: some View {
        let r = KitDeal.compare(priceA: num(pa), qtyA: num(qa), priceB: num(pb), qtyB: num(qb))
        Form {
            Section { KitIntro(icon: "scalemass.fill", color: .indigo, text: "Better deal. Is the big pack really cheaper? Enter the price and the amount (grams, ml, count) of two options, and Keel shows the price per unit and which one wins.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section("Option A") {
                TextField("Price", text: $pa).keyboardType(.decimalPad)
                TextField("Amount (e.g. 500)", text: $qa).keyboardType(.decimalPad)
            }
            Section("Option B") {
                TextField("Price", text: $pb).keyboardType(.decimalPad)
                TextField("Amount (e.g. 1000)", text: $qb).keyboardType(.decimalPad)
            }
            if let r {
                Section {
                    LabeledContent("A per unit", value: r.a.formatted(.number.precision(.fractionLength(4))))
                    LabeledContent("B per unit", value: r.b.formatted(.number.precision(.fractionLength(4))))
                    Text(abs(r.a - r.b) < 0.000001 ? "Same price per unit." : "\(r.a < r.b ? "A" : "B") is \(Int(r.saving.rounded()))% cheaper per unit.")
                        .font(.headline).foregroundStyle(.indigo)
                }
            }
        }
        .navigationTitle("Better deal")
    }
    private func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
}

// 36. Chore rotation.

enum KitChoreRotation {
    /// Who does chore `index` in the given week: everyone moves one chore along each week.
    static func person(for index: Int, week: Int, people: [String]) -> String? {
        guard !people.isEmpty else { return nil }
        return people[(index + week) % people.count]
    }
    static var week: Int { Calendar.current.component(.weekOfYear, from: Date()) }
}

struct KitChoresView: View {
    @AppStorage("kit.chores.people") private var peopleRaw = ""
    @AppStorage("kit.chores.list") private var choresRaw = ""
    @AppStorage("kit.chores.done") private var doneRaw = ""
    @State private var newPerson = ""
    @State private var newChore = ""

    private var people: [String] { peopleRaw.split(separator: "\u{1F}").map(String.init) }
    private var chores: [String] { choresRaw.split(separator: "\u{1F}").map(String.init) }
    private var done: Set<String> { Set(doneRaw.split(separator: "\u{1F}").map(String.init)) }

    var body: some View {
        let week = KitChoreRotation.week
        List {
            Section { KitIntro(icon: "arrow.3.trianglepath", color: .orange, text: "Chore rotation. Add the people at home and the chores. Each week everyone moves on to the next chore, so nobody's stuck with the bathroom forever and nobody has to keep track.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            if !people.isEmpty, !chores.isEmpty {
                Section("This week") {
                    ForEach(Array(chores.enumerated()), id: \.offset) { i, c in
                        let key = "\(week)|\(c)"
                        Button { toggle(key) } label: {
                            HStack {
                                Image(systemName: done.contains(key) ? "checkmark.circle.fill" : "circle").foregroundStyle(done.contains(key) ? DS.Palette.calm : .orange)
                                Text(c).foregroundStyle(DS.Palette.ink)
                                Spacer()
                                Text(KitChoreRotation.person(for: i, week: week, people: people) ?? "").font(.callout.weight(.semibold)).foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            Section("People") {
                ForEach(people, id: \.self) { Text($0) }
                    .onDelete { idx in var p = people; p.remove(atOffsets: idx); peopleRaw = p.joined(separator: "\u{1F}") }
                HStack { TextField("Name", text: $newPerson); Button("Add") { peopleRaw = appended(peopleRaw, newPerson); newPerson = "" }.disabled(newPerson.isEmpty) }
            }
            Section("Chores") {
                ForEach(chores, id: \.self) { Text($0) }
                    .onDelete { idx in var c = chores; c.remove(atOffsets: idx); choresRaw = c.joined(separator: "\u{1F}") }
                HStack { TextField("Chore", text: $newChore); Button("Add") { choresRaw = appended(choresRaw, newChore); newChore = "" }.disabled(newChore.isEmpty) }
            }
        }
        .navigationTitle("Chore rotation")
    }
    private func appended(_ raw: String, _ v: String) -> String {
        let t = v.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return raw }
        return raw.isEmpty ? t : raw + "\u{1F}" + t
    }
    private func toggle(_ key: String) {
        var d = done
        if d.contains(key) { d.remove(key) } else { d.insert(key); Haptics.success() }
        doneRaw = d.filter { $0.hasPrefix("\(KitChoreRotation.week)|") }.joined(separator: "\u{1F}")
    }
}

// 37. Tidy sprint.

enum KitTidy {
    static let rooms: [String: [String]] = [
        "Kitchen": ["Clear the counters", "Load or empty the dishwasher", "Wipe the surfaces", "Take out the rubbish"],
        "Bedroom": ["Make the bed", "Clothes into the basket or wardrobe", "Clear the bedside table", "Open a window"],
        "Living room": ["Put things back where they live", "Fold the throws", "Clear the table", "Quick hoover"],
        "Bathroom": ["Wipe the sink", "Towels on the rail", "Clear the counter", "Quick toilet clean"],
        "Desk": ["Bin the rubbish", "Stack the papers", "Return the mugs", "Wipe the desk"],
    ]
}

struct KitTidyView: View {
    @AppStorage("kit.tidy.count") private var sprints = 0
    @State private var room = "Kitchen"
    @State private var done: Set<String> = []
    @State private var endsAt: Date?

    var body: some View {
        List {
            Section { KitIntro(icon: "sparkles", color: .cyan, text: "Tidy sprint. Pick one room and set 15 minutes. Do only what's on the list, in any order, and stop when the timer ends, even if you're not finished. Short sprints beat the overwhelm of \"clean the whole house\".") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            Section {
                Picker("Room", selection: $room) { ForEach(KitTidy.rooms.keys.sorted(), id: \.self) { Text($0) } }
                if let endsAt {
                    TimelineView(.periodic(from: .now, by: 1)) { tl in
                        let left = Int(endsAt.timeIntervalSince(tl.date))
                        Text(left > 0 ? Kit.clock(left) : "Time's up. Stop here, you did it.").font(.title2.weight(.semibold)).monospacedDigit()
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    Button("Start 15 minutes", systemImage: "play.fill") {
                        endsAt = Date().addingTimeInterval(900); done = []; sprints += 1
                        Kit.notify("kit.tidy", title: "Tidy sprint done", body: "15 minutes in the \(room.lowercased()). Stop and enjoy it.", at: endsAt!)
                        Haptics.start()
                    }
                }
            }
            Section(room) {
                ForEach(KitTidy.rooms[room] ?? [], id: \.self) { step in
                    Button {
                        if done.contains(step) { done.remove(step) } else { done.insert(step); Haptics.tap() }
                    } label: {
                        Label(step, systemImage: done.contains(step) ? "checkmark.circle.fill" : "circle").foregroundStyle(done.contains(step) ? DS.Palette.calm : DS.Palette.ink)
                    }
                }
            }
            Section { Text("\(sprints) sprint\(sprints == 1 ? "" : "s") so far").foregroundStyle(DS.Palette.inkSoft) }
        }
        .navigationTitle("Tidy sprint")
        .onChange(of: room) { done = [] }
    }
}

// 38. Pet care.

struct KitPetEvent: Codable, Identifiable, Hashable { var id = UUID(); var pet: String; var kind: String; var date = Date() }

struct KitPetsView: View {
    static let key = "kit.pets.log"
    @AppStorage("kit.pets.names") private var namesRaw = ""
    @State private var log: [KitPetEvent] = []
    @State private var newPet = ""
    private struct Kind: Hashable { let name: String; let icon: String }
    private let kinds = [Kind(name: "Fed", icon: "fork.knife"), Kind(name: "Walked", icon: "figure.walk"), Kind(name: "Medicine", icon: "pills.fill"),
                         Kind(name: "Litter / clean", icon: "sparkles"), Kind(name: "Vet", icon: "cross.case.fill")]

    var body: some View {
        let pets = namesRaw.split(separator: "\u{1F}").map(String.init)
        List {
            Section { KitIntro(icon: "pawprint.fill", color: .brown, text: "Pet care. One tap to log feeding, walks, medicine and more, so nobody in the house has to ask \"has the dog been fed?\" again. See how long ago each thing happened.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            ForEach(pets, id: \.self) { pet in
                Section(pet) {
                    ForEach(kinds, id: \.self) { k in
                        let kind = k.name
                        let icon = k.icon
                        let last = log.first { $0.pet == pet && $0.kind == kind }
                        Button {
                            log.insert(KitPetEvent(pet: pet, kind: kind), at: 0); Kit.save(Array(log.prefix(600)), Self.key); Haptics.tap()
                        } label: {
                            HStack {
                                Label(kind, systemImage: icon).foregroundStyle(DS.Palette.ink)
                                Spacer()
                                Text(last.map { $0.date.formatted(.relative(presentation: .named)) } ?? "never").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                            }
                        }
                    }
                }
            }
            Section("Pets") {
                HStack {
                    TextField("Pet's name", text: $newPet)
                    Button("Add") { namesRaw = namesRaw.isEmpty ? newPet : namesRaw + "\u{1F}" + newPet; newPet = "" }.disabled(newPet.isEmpty)
                }
            }
        }
        .navigationTitle("Pet care")
        .onAppear { log = Kit.load(Self.key) }
    }
}

// 39. Counters.

struct KitCounter: Codable, Identifiable, Hashable { var id = UUID(); var name: String; var count = 0; var daily = true; var day = Kit.dayKey() }

struct KitCountersView: View {
    static let key = "kit.counters"
    @State private var counters: [KitCounter] = []
    @State private var name = ""
    @State private var daily = true

    var body: some View {
        List {
            Section { KitIntro(icon: "plus.forwardslash.minus", color: .blue, text: "Counters. Tally anything with one tap: glasses of water, pages read, push-ups, times you got distracted. Daily counters reset each morning; others keep counting.") }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            ForEach($counters) { $c in
                HStack {
                    VStack(alignment: .leading) {
                        Text(c.name).font(.headline)
                        Text(c.daily ? "today" : "total").font(.caption2).foregroundStyle(DS.Palette.inkSoft)
                    }
                    Spacer()
                    Button { if c.count > 0 { c.count -= 1; save() } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).font(.title2)
                    Text("\(c.count)").font(.title2.weight(.bold)).monospacedDigit().frame(minWidth: 44).contentTransition(.numericText())
                    Button { withAnimation { c.count += 1 }; save(); Haptics.tap() } label: { Image(systemName: "plus.circle.fill") }.buttonStyle(.plain).font(.title2).foregroundStyle(.blue)
                }
            }
            .onDelete { counters.remove(atOffsets: $0); save() }
            Section("New counter") {
                TextField("What to count", text: $name)
                Toggle("Reset every day", isOn: $daily)
                Button("Add") { counters.append(KitCounter(name: name, daily: daily)); save(); name = "" }.disabled(name.isEmpty)
            }
        }
        .navigationTitle("Counters")
        .onAppear {
            counters = Kit.load(Self.key)
            let today = Kit.dayKey()
            for i in counters.indices where counters[i].daily && counters[i].day != today { counters[i].count = 0; counters[i].day = today }
            save()
        }
    }
    private func save() { Kit.save(counters, Self.key) }
}
