import SwiftUI
import SwiftData
import ContactsUI

/// Keep in touch: the people who matter, how often you want to connect, and a nudge when it's been too long.
@MainActor
enum KeepInTouch {
    /// After sync: an email from someone on your list counts as being in touch.
    static func updateFromMail(ctx: ModelContext) {
        let people = ((try? ctx.fetch(FetchDescriptor<Person>())) ?? []).filter { !$0.email.isEmpty }
        guard !people.isEmpty else { return }
        let mail = (try? ctx.fetch(FetchDescriptor<EmailMessage>())) ?? []
        for p in people {
            let addr = p.email.lowercased()
            if let latest = mail.filter({ $0.from.lowercased() == addr || $0.toLine.lowercased().contains(addr) }).map(\.receivedAt).max(),
               latest > (p.lastContact ?? .distantPast) {
                p.lastContact = latest
            }
        }
    }
}

extension KeepInTouch {
    struct Suggestion: Identifiable { var id: String { email }; let name: String; let email: String; let count: Int; let last: Date }

    /// Real people you write to back and forth, who aren't on your list yet. Skips newsletters and no-reply senders.
    static func suggestions(ctx: ModelContext, existing: [Person]) -> [Suggestion] {
        let known = Set(existing.map { $0.email.lowercased() })
        let dismissed = Set(UserDefaults.standard.stringArray(forKey: "people.dismissed") ?? [])
        let accounts = Set(((try? ctx.fetch(FetchDescriptor<MailAccount>())) ?? []).map { $0.address.lowercased() })
        let since = Date().addingTimeInterval(-120 * 86_400)
        let mail = ((try? ctx.fetch(FetchDescriptor<EmailMessage>(predicate: #Predicate { $0.receivedAt > since }))) ?? [])
            .filter { [TriageCategory.important, .actionable, .calendar].contains($0.category ?? .important) }
        let groups = Dictionary(grouping: mail) { $0.from.lowercased() }
        return groups.compactMap { addr, msgs -> Suggestion? in
            guard msgs.count >= 3, !known.contains(addr), !dismissed.contains(addr), !accounts.contains(addr),
                  !["noreply", "no-reply", "notifications", "newsletter", "support", "info@", "hello@", "team@"].contains(where: addr.contains) else { return nil }
            let name = msgs.first { !$0.fromName.isEmpty }?.fromName ?? addr
            return Suggestion(name: name, email: addr, count: msgs.count, last: msgs.map(\.receivedAt).max()!)
        }
        .sorted { $0.count > $1.count }
        .prefix(5).map { $0 }
    }
}

struct PeopleView: View {
    @State private var personPage: Person?
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Person.name) private var people: [Person]
    @State private var showPicker = false
    @State private var editing: Person?
    @State private var dismissTick = 0

    var body: some View {
        List {
            let due = people.filter(\.isDue).sorted { $0.nextDue < $1.nextDue }
            if !due.isEmpty {
                Section("Reach out") { ForEach(due) { row($0) } }
            }
            let fine = people.filter { !$0.isDue }.sorted { $0.nextDue < $1.nextDue }
            if !fine.isEmpty {
                Section("In touch") { ForEach(fine) { row($0) } }
            }
            let suggestions = dismissTick >= 0 ? KeepInTouch.suggestions(ctx: ctx, existing: people) : []
            if !suggestions.isEmpty {
                Section {
                    ForEach(suggestions) { s in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(s.name)
                                Text("\(s.count) emails · last \(s.last.formatted(.relative(presentation: .named)))")
                                    .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                            }
                            Spacer()
                            Button("Add") {
                                let p = Person(name: s.name); p.email = s.email; p.lastContact = s.last
                                ctx.insert(p); editing = p; Haptics.success()
                            }
                            .buttonStyle(.bordered).tint(DS.Palette.accent)
                        }
                        .swipeActions {
                            Button("Not now") {
                                var d = UserDefaults.standard.stringArray(forKey: "people.dismissed") ?? []
                                d.append(s.email); UserDefaults.standard.set(d, forKey: "people.dismissed")
                                dismissTick += 1
                            }
                        }
                    }
                } header: { Text("Suggested") } footer: { Text("People you email with often. Add them to get a nudge when it's been a while.") }
            }
            if people.isEmpty {
                ContentUnavailableView {
                    Label("Keep in touch", systemImage: "person.2")
                } description: {
                    Text("Add the people who matter most. Keel reminds you when it's been too long, so no one slips through the cracks.")
                } actions: {
                    Button("Add from Contacts") { showPicker = true }.buttonStyle(.borderedProminent).tint(DS.Palette.accent)
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Keep in Touch")
        .navigationDestination(item: $personPage) { PersonPageView(person: $0) }
        .toolbar { Button { showPicker = true } label: { Image(systemName: "person.badge.plus") }.accessibilityLabel("Add person") }
        .sheet(isPresented: $showPicker) {
            ContactPicker { contact in
                let p = Person(name: CNContactFormatter.string(from: contact, style: .fullName) ?? contact.givenName)
                p.email = contact.emailAddresses.first.map { $0.value as String } ?? ""
                p.phone = contact.phoneNumbers.first?.value.stringValue ?? ""
                ctx.insert(p)
                KeepInTouch.updateFromMail(ctx: ctx)
                editing = p
            }
            .ignoresSafeArea()
        }
        .sheet(item: $editing) { PersonEditor(person: $0) }
    }

    private func row(_ p: Person) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(DS.Font.headline)
                Text(p.lastContact.map { "Last in touch \($0.formatted(.relative(presentation: .named)))" } ?? "No contact logged yet")
                    .font(DS.Font.caption).foregroundStyle(p.isDue ? DS.Palette.warmth : DS.Palette.inkSoft)
            }
            Spacer()
            ReachOutButtons(person: p)
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = p }
        .swipeActions {
            Button(role: .destructive) { ctx.delete(p) } label: { Label("Remove", systemImage: "trash") }
            Button { p.lastContact = Date(); Haptics.success() } label: { Label("Talked", systemImage: "checkmark") }.tint(DS.Palette.calm)
        }
        .swipeActions(edge: .leading) { Button { personPage = p } label: { Label("Page", systemImage: "person.text.rectangle") }.tint(.indigo) }
    }
}

/// Call / text / email in one tap; tapping logs the contact.
struct ReachOutButtons: View {
    let person: Person
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 6) {
            let digits = person.phone.filter { $0.isNumber || $0 == "+" }
            if !digits.isEmpty {
                circle("phone.fill") { open("tel:\(digits)") }
                circle("message.fill") { open("sms:\(digits)") }
            }
            if !person.email.isEmpty {
                circle("envelope.fill") {
                    person.lastContact = Date()
                    MailRouter.shared.pending = ComposeDraft(to: person.email, subject: "Thinking of you")
                }
            }
        }
    }

    private func open(_ s: String) {
        guard let url = URL(string: s) else { return }
        person.lastContact = Date()
        openURL(url)
    }

    private func circle(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(DS.Palette.accent, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

struct PersonEditor: View {
    @Bindable var person: Person
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                BufferedTextField("Name", text: $person.name)
                TextField("Email", text: $person.email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                TextField("Phone", text: $person.phone).keyboardType(.phonePad)
                Picker("Be in touch every", selection: $person.cadenceDays) {
                    Text("Week").tag(7); Text("2 weeks").tag(14); Text("Month").tag(30); Text("3 months").tag(90)
                }
                Section("Notes") { TextField("Kids' names, what they're working on…", text: $person.notes, axis: .vertical).lineLimit(2...6) }
                Section { Button("I was just in touch") { person.lastContact = Date(); Haptics.success(); dismiss() } }
            }
            .navigationTitle(person.name.isEmpty ? "Person" : person.name)
            .toolbar { Button("Done") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ContactPicker: UIViewControllerRepresentable {
    var onPick: (CNContact) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let vc = CNContactPickerViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: CNContactPickerViewController, context: Context) {}
    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (CNContact) -> Void
        init(onPick: @escaping (CNContact) -> Void) { self.onPick = onPick }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) { onPick(contact) }
    }
}
