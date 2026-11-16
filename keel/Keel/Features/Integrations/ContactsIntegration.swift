import SwiftUI
import SwiftData
import Contacts
import EventKit

// MARK: - Contacts on a person's page: photo, one-tap call / text / email / FaceTime, and linking to your Contacts

struct PersonContactSection: View {
    let person: Person
    @State private var linked: KeelContact?
    @State private var photo: UIImage?
    @State private var picking = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            HStack(spacing: 14) {
                Group {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else {
                        Text(initials).font(.title2.weight(.semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity).background(DS.Palette.accent.gradient)
                    }
                }
                .frame(width: 56, height: 56).clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name).font(DS.Font.headline)
                    Text(linked != nil ? "Linked to your Contacts" : "Not linked to Contacts").font(.caption).foregroundStyle(DS.Palette.inkSoft)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                action("Text", "message.fill", enabled: !(phone.isEmpty && person.email.isEmpty)) { AppleMessages.compose(person: person) }
                action("Call", "phone.fill", enabled: !phone.isEmpty) { open("tel:\(digits)") }
                action("FaceTime", "video.fill", enabled: !(phone.isEmpty && person.email.isEmpty)) { open("facetime:\(phone.isEmpty ? person.email : digits)") }
                action("Email", "envelope.fill", enabled: !person.email.isEmpty) {
                    person.lastContact = Date()
                    MailRouter.shared.pending = ComposeDraft(to: person.email)
                }
            }
            .buttonStyle(.plain)
            Button(linked == nil ? "Link to a contact…" : "Change linked contact…", systemImage: "person.crop.circle.badge.checkmark") { picking = true }
                .font(.caption)
        }
        .task { load() }
        .sheet(isPresented: $picking) {
            ContactPicker { c in
                KeelContacts.link(person, to: c)
                picking = false
                load()
                Haptics.success()
            }
            .ignoresSafeArea()
        }
    }

    private var phone: String { person.phone }
    private var digits: String { person.phone.filter { $0.isNumber || $0 == "+" } }
    private var initials: String { person.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined() }

    private func load() {
        if let id = KeelContacts.linkedId(person) {
            linked = KeelContacts.contact(id: id)
            photo = KeelContacts.photo(id: id)
        } else if let c = KeelContacts.match(email: person.email, name: person.name) {
            linked = c                                   // found on its own: remember it
            UserDefaults.standard.set(c.id, forKey: KeelContacts.linkKey(person))
            photo = KeelContacts.photo(id: c.id)
        }
    }

    private func open(_ s: String) {
        guard let u = URL(string: s) else { return }
        person.lastContact = Date()
        openURL(u)
    }

    private func action(_ title: String, _ icon: String, enabled: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(enabled ? DS.Palette.accent.opacity(0.15) : Color.gray.opacity(0.1), in: Circle())
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(enabled ? DS.Palette.accent : DS.Palette.inkSoft)
        }
        .disabled(!enabled)
    }
}

// MARK: - Today: who you're meeting next

struct NextMeetingPeopleCard: View {
    @State private var next: (event: EKEvent, people: [String])?
    private static var cache: (at: Date, value: (event: EKEvent, people: [String])?)?

    var body: some View {
        Group {
            if let next {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Next: \(next.event.title ?? "Meeting")", systemImage: "person.2.fill").font(DS.Font.headline)
                    Text("\(next.event.startDate.formatted(date: .omitted, time: .shortened)) with \(ListFormatter.localizedString(byJoining: Array(next.people.prefix(3))))\(next.people.count > 3 ? " +\(next.people.count - 3)" : "")")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.inkSoft)
                    HStack {
                        Button("Running late", systemImage: "clock.badge.exclamationmark") { AppleMessages.runningLate(for: next.event) }
                            .buttonStyle(.bordered).controlSize(.small)
                        NavigationLink { LazyView(MeetingPrepView(event: next.event)) } label: { Label("Prep", systemImage: "list.bullet.clipboard") }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .padding(DS.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { PremiumSurface() }
            }
        }
        .task {
            if let c = Self.cache, Date().timeIntervalSince(c.at) < 300 { next = c.value; return }
            try? await Task.sleep(for: .milliseconds(300))            // after Today has finished appearing
            let n = KeelContacts.nextMeeting()
            Self.cache = (Date(), n)
            next = n
        }
    }
}
