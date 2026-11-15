import SwiftUI
import SwiftData
import MessageUI
import Contacts
import EventKit

// MARK: - Messages: draft a text in Keel, send it through Apple's own Messages sheet
//
// Apple lets apps write a message and hand it to the Messages sheet; you always press Send yourself, and no app can
// read your message history. On a Mac (or anywhere Messages can't be shown inside Keel), Keel opens the Messages app
// with the text filled in where it can, and copies it so you can paste it.

struct TextDraft: Identifiable, Hashable {
    let id = UUID()
    var recipients: [String] = []          // phone numbers or iMessage email addresses
    var body = ""
    var personName: String?                // for "Write it for me" and logging that you were in touch
    var context: String?                   // what it's about, for the AI ("Running late to Design review")
}

@MainActor
enum AppleMessages {
    static var canSendHere: Bool { MFMessageComposeViewController.canSendText() }

    /// sms:// link with the recipients and the text (used when the in-app sheet isn't available).
    static func url(for d: TextDraft) -> URL? {
        let to = d.recipients.map { $0.filter { !$0.isWhitespace } }.joined(separator: ",")
        let body = d.body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: to.isEmpty ? "sms:&body=\(body)" : "sms:/open?addresses=\(to)&body=\(body)")
    }

    /// "Running 10 min late. I'll be there around 3:40." with the event's own start time.
    static func runningLate(_ title: String?, start: Date, minutes: Int) -> String {
        let eta = start.addingTimeInterval(Double(minutes * 60)).formatted(date: .omitted, time: .shortened)
        let what = (title?.isEmpty == false) ? " for \(title!)" : ""
        return "Hi, I'm running about \(minutes) min late\(what). I'll be there around \(eta). Sorry!"
    }

    static let templates: [(label: String, text: String)] = [
        ("On my way", "On my way!"),
        ("Running late", "Running a few minutes late, sorry. Be there soon."),
        ("Thinking of you", "Thinking of you. How are things?"),
        ("Thank you", "Thank you so much, I really appreciate it."),
        ("Can we reschedule?", "Hi, something's come up. Could we move our plan to another time?"),
        ("Call me when free", "Can you call me when you're free? Nothing urgent."),
    ]

    /// A short text in your usual style. Apple Intelligence on the device, Claude if you've added a key; plain fallback otherwise.
    static func write(about: String, to name: String?) async -> String {
        let style = WritingStyle.profile
        var hints: [String] = ["Write one short, friendly text message (1–3 sentences). No subject, no sign-off, no quotation marks."]
        if style.samples >= 5 {
            if style.lowercaseRate > 0.5 { hints.append("Start in lowercase, the way the user usually writes.") }
            if style.exclamationRate > 0.4 { hints.append("An exclamation mark is fine.") }
            if style.emojiRate > 0.3 { hints.append("One emoji is fine.") }
        }
        let prompt = hints.joined(separator: " ") + "\nTo: \(name ?? "a friend")\nAbout: \(about)"
        if let r = await AIRouter.shared.write(prompt)?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty {
            return r.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
        }
        return about
    }

    /// Opens Keel's text composer from anywhere (buttons, Siri, notifications).
    static func compose(_ d: TextDraft) { AppRouter.shared.textDraft = d }

    /// "Text them" for a Keel person: their phone, else their email (iMessage).
    static func compose(person: Person, body: String = "", context: String? = nil) {
        let to = !person.phone.isEmpty ? person.phone : person.email
        compose(TextDraft(recipients: to.isEmpty ? [] : [to], body: body, personName: person.name, context: context))
    }

    /// "Text them" for someone you know by email: their phone from your people or Contacts if Keel can find it, else the email (iMessage).
    static func compose(email: String, name: String?, context: String?) {
        let people = (try? KeelStore.container.mainContext.fetch(FetchDescriptor<Person>())) ?? []
        if let p = people.first(where: { $0.email.caseInsensitiveCompare(email) == .orderedSame }) {
            compose(person: p, context: context); return
        }
        let phone = KeelContacts.match(email: email, name: name ?? "")?.phone
        compose(TextDraft(recipients: [phone ?? email], personName: name, context: context))
    }

    /// "Running late" to the other people in a meeting: phones from Keel people or your Contacts, matched by email or name.
    static func runningLate(for e: EKEvent, minutes: Int = 10) {
        let people = (try? KeelStore.container.mainContext.fetch(FetchDescriptor<Person>())) ?? []
        let guests = (e.attendees ?? []).filter { !$0.isCurrentUser }
        var to: [String] = []
        var names: [String] = []
        for g in guests {
            let email = g.url.absoluteString.replacingOccurrences(of: "mailto:", with: "").lowercased()
            let name = g.name ?? ""
            if let p = people.first(where: { (!email.isEmpty && $0.email.lowercased() == email) || (!name.isEmpty && $0.name == name) }) {
                if !p.phone.isEmpty { to.append(p.phone) } else if !p.email.isEmpty { to.append(p.email) }
                names.append(p.name)
            } else if let c = KeelContacts.match(email: email, name: name), let phone = c.phone {
                to.append(phone); names.append(c.name)
            } else if !email.isEmpty, email.contains("@") {
                to.append(email); if !name.isEmpty { names.append(name) }
            }
        }
        compose(TextDraft(recipients: Array(to.prefix(10)), body: runningLate(e.title, start: e.startDate, minutes: minutes),
                          personName: names.first, context: "Running late to \(e.title ?? "a meeting")"))
    }
}

// MARK: - Contacts lookups

struct KeelContact: Hashable { let id: String; let name: String; let phone: String?; let email: String?; let birthday: DateComponents? }

@MainActor
enum KeelContacts {
    static var allowed: Bool { CNContactStore.authorizationStatus(for: .contacts) == .authorized }
    private static let keys: [CNKeyDescriptor] = [
        CNContactIdentifierKey as CNKeyDescriptor, CNContactGivenNameKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor, CNContactEmailAddressesKey as CNKeyDescriptor, CNContactBirthdayKey as CNKeyDescriptor,
        CNContactThumbnailImageDataKey as CNKeyDescriptor,
    ]
    private static let store = CNContactStore()

    static func requestAccess() async -> Bool {
        if allowed { return true }
        return (try? await store.requestAccess(for: .contacts)) ?? false
    }

    private static func wrap(_ c: CNContact) -> KeelContact {
        let name = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return KeelContact(id: c.identifier, name: name, phone: c.phoneNumbers.first?.value.stringValue,
                           email: c.emailAddresses.first.map { $0.value as String }, birthday: c.birthday)
    }

    /// The contact with this email, or else exactly this name. Nil without Contacts access.
    static func match(email: String, name: String) -> KeelContact? {
        guard allowed else { return nil }
        if !email.isEmpty, let c = try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingEmailAddress: email), keysToFetch: keys).first {
            return wrap(c)
        }
        if !name.isEmpty, let c = try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: keys)
            .first(where: { [$0.givenName, $0.familyName].filter { !$0.isEmpty }.joined(separator: " ").caseInsensitiveCompare(name) == .orderedSame }) {
            return wrap(c)
        }
        return nil
    }

    static func contact(id: String) -> KeelContact? {
        guard allowed, let c = try? store.unifiedContact(withIdentifier: id, keysToFetch: keys) else { return nil }
        return wrap(c)
    }

    static func photo(id: String) -> UIImage? {
        guard allowed, let c = try? store.unifiedContact(withIdentifier: id, keysToFetch: keys), let d = c.thumbnailImageData else { return nil }
        return UIImage(data: d)
    }

    // A Keel person ↔ a contact. Kept as a setting (the person record itself isn't changed), so it follows you to your other devices.
    static func linkKey(_ p: Person) -> String { "people.contact.\(p.id.uuidString)" }
    static func linkedId(_ p: Person) -> String? { UserDefaults.standard.string(forKey: linkKey(p)) }

    /// Links a person to a contact and fills in their phone and email where Keel doesn't have them yet.
    static func link(_ p: Person, to c: CNContact) {
        UserDefaults.standard.set(c.identifier, forKey: linkKey(p))
        if p.phone.isEmpty, let ph = c.phoneNumbers.first?.value.stringValue { p.phone = ph }
        if p.email.isEmpty, let em = c.emailAddresses.first { p.email = em.value as String }
        if let b = c.birthday, let m = b.month, let d = b.day {
            var manual = Gifts.manual
            if manual[p.name] == nil {
                manual[p.name] = b.year.map { String(format: "%04d-%02d-%02d", $0, m, d) } ?? String(format: "%02d-%02d", m, d)
                Gifts.manual = manual
            }
        }
    }

    /// Who you're meeting next today, matched to your people and contacts.
    static func nextMeeting(now: Date = Date()) -> (event: EKEvent, people: [String])? {
        let soon = CalendarService.shared.events(from: now, to: Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: now) ?? now)
            .filter { !$0.isAllDay && $0.startDate > now.addingTimeInterval(-600) && ($0.attendees?.contains { !$0.isCurrentUser } ?? false) }
        guard let e = soon.first else { return nil }
        let names = (e.attendees ?? []).filter { !$0.isCurrentUser }.compactMap { a -> String? in
            if let n = a.name, !n.isEmpty, !n.contains("@") { return n }
            let email = a.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
            return match(email: email, name: "")?.name ?? email
        }
        return (e, names)
    }
}

// MARK: - The composer

struct TextComposerView: View {
    @State var draft: TextDraft
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Person.name) private var people: [Person]
    @State private var newRecipient = ""
    @State private var writing = false
    @State private var showSystemSheet = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section("To") {
                    ForEach(draft.recipients, id: \.self) { r in
                        HStack {
                            Text(name(for: r) ?? r)
                            Spacer()
                            Button { draft.recipients.removeAll { $0 == r } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(DS.Palette.inkSoft) }
                                .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        TextField("Phone or email", text: $newRecipient).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                            .onSubmit(addRecipient)
                        Button("Add", action: addRecipient).disabled(newRecipient.isEmpty)
                    }
                    let reachable = people.filter { !$0.phone.isEmpty || !$0.email.isEmpty }
                    if !reachable.isEmpty {
                        Menu {
                            ForEach(reachable) { p in
                                Button(p.name) {
                                    let to = p.phone.isEmpty ? p.email : p.phone
                                    if !draft.recipients.contains(to) { draft.recipients.append(to) }
                                    if draft.personName == nil { draft.personName = p.name }
                                }
                            }
                        } label: { Label("From my people", systemImage: "person.crop.circle.badge.plus") }
                    }
                }
                Section {
                    TextField("Message", text: $draft.body, axis: .vertical).lineLimit(3...10)
                    Button {
                        writing = true
                        Task {
                            draft.body = await AppleMessages.write(about: draft.context ?? (draft.body.isEmpty ? "checking in" : draft.body), to: draft.personName)
                            writing = false
                        }
                    } label: { Label(writing ? "Writing…" : "Write it for me", systemImage: "sparkles") }
                    .disabled(writing)
                } footer: { Text("Keel drafts it in your usual style. Nothing is sent until you press Send in Messages.") }
                Section("Quick texts") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(AppleMessages.templates, id: \.label) { t in
                                Button(t.label) { draft.body = t.text }.buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                }
                if copied {
                    Section { Label("Copied. Paste it into Messages if it isn't filled in.", systemImage: "doc.on.clipboard").foregroundStyle(DS.Palette.calm) }
                }
            }
            .navigationTitle("Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open in Messages") { send() }.disabled(draft.body.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showSystemSheet) {
                MessageComposeSheet(recipients: draft.recipients, body: draft.body) { sent in
                    showSystemSheet = false
                    if sent { logContact(); Haptics.success(); dismiss() }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func addRecipient() {
        let r = newRecipient.trimmingCharacters(in: .whitespaces)
        guard !r.isEmpty, !draft.recipients.contains(r) else { return }
        draft.recipients.append(r); newRecipient = ""
    }

    private func name(for r: String) -> String? {
        people.first { $0.phone == r || $0.email.caseInsensitiveCompare(r) == .orderedSame }?.name
    }

    private func send() {
        if AppleMessages.canSendHere {
            showSystemSheet = true
        } else {
            UIPasteboard.general.string = draft.body
            copied = true
            if let url = AppleMessages.url(for: draft) { UIApplication.shared.open(url) }
            logContact()
        }
    }

    private func logContact() {
        for p in people where draft.recipients.contains(where: { $0 == p.phone || $0.caseInsensitiveCompare(p.email) == .orderedSame }) {
            p.lastContact = Date()
        }
    }
}

/// Apple's own Messages sheet.
struct MessageComposeSheet: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    var done: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients = recipients
        vc.body = body
        vc.messageComposeDelegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let done: (Bool) -> Void
        init(done: @escaping (Bool) -> Void) { self.done = done }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            done(result == .sent)
        }
    }
}
