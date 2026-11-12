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

struct PeopleView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Person.name) private var people: [Person]
    @State private var showPicker = false
    @State private var editing: Person?

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
        .toolbar { Button { showPicker = true } label: { Image(systemName: "person.badge.plus") } }
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
                TextField("Name", text: $person.name)
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
