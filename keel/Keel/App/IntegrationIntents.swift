import AppIntents
import SwiftData
import UIKit

// Siri, Shortcuts, Spotlight, the Action button and Apple Intelligence can use every action here.
// They're in the Shortcuts app under Keel; give any of them your own Siri phrase there.

// MARK: - People (lets Siri pick one of your Keel people by name)

struct PersonEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Person"
    static let defaultQuery = PersonEntityQuery()
    let id: UUID
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct PersonEntityQuery: EntityStringQuery {
    @MainActor private func all() -> [Person] { (try? KeelStore.container.mainContext.fetch(FetchDescriptor<Person>())) ?? [] }
    func entities(for identifiers: [UUID]) async throws -> [PersonEntity] {
        await MainActor.run { all().filter { identifiers.contains($0.id) }.map { PersonEntity(id: $0.id, name: $0.name) } }
    }
    func entities(matching string: String) async throws -> [PersonEntity] {
        await MainActor.run { all().filter { $0.name.localizedCaseInsensitiveContains(string) }.map { PersonEntity(id: $0.id, name: $0.name) } }
    }
    func suggestedEntities() async throws -> [PersonEntity] {
        await MainActor.run { all().sorted { $0.name < $1.name }.prefix(30).map { PersonEntity(id: $0.id, name: $0.name) } }
    }
}

@MainActor private func person(_ e: PersonEntity) -> Person? {
    let id = e.id
    return try? KeelStore.container.mainContext.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.id == id })).first
}

// MARK: - Messages & calls

struct TextPersonIntent: AppIntent {
    static let title: LocalizedStringResource = "Text Someone with Keel"
    static let description: IntentDescription = "Drafts a text to one of your people (Keel can write it in your style). You send it from Messages."
    static let openAppWhenRun = true
    @Parameter(title: "Person") var who: PersonEntity
    @Parameter(title: "About") var about: String?

    @MainActor func perform() async throws -> some IntentResult {
        guard let p = person(who) else { return .result() }
        AppleMessages.compose(person: p, context: about)
        return .result()
    }
}

struct RunningLateIntent: AppIntent {
    static let title: LocalizedStringResource = "Text: I'm Running Late"
    static let description: IntentDescription = "Drafts a running-late text to the people in your next meeting, with your new arrival time."
    static let openAppWhenRun = true
    @Parameter(title: "Minutes late", default: 10) var minutes: Int

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let next = KeelContacts.nextMeeting() else { return .result(dialog: "There's no meeting with other people coming up today.") }
        AppleMessages.runningLate(for: next.event, minutes: minutes)
        return .result(dialog: "Here's a text for \(next.event.title ?? "your meeting").")
    }
}

struct WhoAmIMeetingIntent: AppIntent {
    static let title: LocalizedStringResource = "Who Am I Meeting Next?"
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let next = KeelContacts.nextMeeting() else { return .result(dialog: "No meetings with other people for the rest of today.") }
        let who = next.people.isEmpty ? "" : " with \(ListFormatter.localizedString(byJoining: Array(next.people.prefix(4))))"
        return .result(dialog: "\(next.event.title ?? "A meeting") at \(next.event.startDate.formatted(date: .omitted, time: .shortened))\(who).")
    }
}

struct CallPersonIntent: AppIntent {
    static let title: LocalizedStringResource = "Call Someone from Keel"
    static let openAppWhenRun = true
    @Parameter(title: "Person") var who: PersonEntity

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let p = person(who) else { return .result(dialog: "I couldn't find them in Keel.") }
        let digits = p.phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty, let url = URL(string: "tel:\(digits)") else { return .result(dialog: "Keel doesn't have a phone number for \(p.name).") }
        p.lastContact = Date()
        _ = await UIApplication.shared.open(url)
        return .result(dialog: "Calling \(p.name).")
    }
}

// MARK: - Timers & focus helpers

struct StartKeelTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a Keel Timer"
    static let description: IntentDescription = "Starts a named timer (laundry, oven, tea). It notifies you when it's done."
    @Parameter(title: "Name", default: "Timer") var name: String
    @Parameter(title: "Minutes", default: 10) var minutes: Int

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let t = KitTimer(name: name, endsAt: Date().addingTimeInterval(Double(max(1, minutes) * 60)), minutes: max(1, minutes))
        Kit.save(Kit.load(KitMultiTimersView.key, as: KitTimer.self) + [t], KitMultiTimersView.key)
        Kit.notify("kit.timer.\(t.id)", title: "\(t.name) is done", body: "Your \(t.minutes)-minute timer finished.", at: t.endsAt)
        return .result(dialog: "\(name): \(minutes) minutes, starting now.")
    }
}

struct TomorrowFirstStepIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Tomorrow's First Step"
    @Parameter(title: "First step") var step: String

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        UserDefaults.standard.set(step, forKey: "kit.firststep.text")
        let d = UserDefaults.standard
        let hour = d.object(forKey: "kit.firststep.hour") as? Int ?? 8, minute = d.object(forKey: "kit.firststep.minute") as? Int ?? 30
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: cal.component(.hour, from: Date()) < hour ? 0 : 1, to: Date()) ?? Date()
        if let at = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) {
            Kit.notify("kit.firststep", title: "Your first step today", body: step, at: at)
        }
        return .result(dialog: "Saved. You'll see it in the morning.")
    }
}

// MARK: - Top 3, frog, done list, wins

struct AddTop3Intent: AppIntent {
    static let title: LocalizedStringResource = "Add to My Top 3"
    @Parameter(title: "Thing") var thing: String

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        var all = Kit.load(KitTop3.key, as: KitTop3Day.self)
        var today = all.first { $0.day == Kit.dayKey() } ?? KitTop3Day(day: Kit.dayKey(), items: ["", "", ""], done: [false, false, false])
        guard let i = today.items.firstIndex(where: { $0.isEmpty }) else { return .result(dialog: "Your Top 3 is already full. Finish one first.") }
        today.items[i] = thing
        all.removeAll { $0.day == today.day }; all.append(today)
        Kit.save(Array(all.suffix(120)), KitTop3.key)
        return .result(dialog: "Added as number \(i + 1).")
    }
}

struct MyTop3Intent: AppIntent {
    static let title: LocalizedStringResource = "What's My Top 3?"
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let today = Kit.load(KitTop3.key, as: KitTop3Day.self).first { $0.day == Kit.dayKey() }
        let open = zip(today?.items ?? [], today?.done ?? []).filter { !$0.0.isEmpty && !$0.1 }.map { $0.0 }
        if today == nil || today!.items.allSatisfy(\.isEmpty) { return .result(dialog: "You haven't picked a Top 3 today.") }
        return .result(dialog: open.isEmpty ? "All three done. Well done!" : "Still to do: \(ListFormatter.localizedString(byJoining: open)).")
    }
}

struct SetFrogIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Today's Frog"
    static let description: IntentDescription = "The one task you're most tempted to avoid, to do first."
    @Parameter(title: "Frog") var frog: String

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        var all = Kit.load(KitFrogView.key, as: KitFrog.self)
        all.removeAll { $0.day == Kit.dayKey() }
        all.append(KitFrog(day: Kit.dayKey(), text: frog))
        Kit.save(Array(all.suffix(365)), KitFrogView.key)
        return .result(dialog: "Today's frog: \(frog). Do it first.")
    }
}

struct LogDoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to My Done List"
    @Parameter(title: "What I did") var what: String
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        Kit.save([KitItem(text: what)] + Kit.load(KitDoneListView.key, as: KitItem.self).prefix(1499), KitDoneListView.key)
        return .result(dialog: "Nice. Added to your done list.")
    }
}

struct LogWinIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a Win to My Jar"
    @Parameter(title: "Win") var win: String
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        Kit.save([KitItem(text: win)] + Kit.load("kit.wins", as: KitItem.self), "kit.wins")
        return .result(dialog: "In the jar.")
    }
}

// MARK: - Life admin

struct ParkedHereIntent: AppIntent {
    static let title: LocalizedStringResource = "I Parked Here"
    @Parameter(title: "Where (level, row, street)") var spot: String
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let d = UserDefaults.standard
        d.set(spot, forKey: "kitlocal.park.spot"); d.set(Date().timeIntervalSince1970, forKey: "kitlocal.park.at"); d.set(0.0, forKey: "kitlocal.park.meter")
        return .result(dialog: "Got it: \(spot).")
    }
}

struct WhereIsMyCarIntent: AppIntent {
    static let title: LocalizedStringResource = "Where Did I Park?"
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let d = UserDefaults.standard
        let at = d.double(forKey: "kitlocal.park.at")
        guard at > 0 else { return .result(dialog: "You haven't saved a parking spot.") }
        let spot = d.string(forKey: "kitlocal.park.spot") ?? ""
        return .result(dialog: "\(spot.isEmpty ? "Saved" : spot), since \(Date(timeIntervalSince1970: at).formatted(date: .omitted, time: .shortened)).")
    }
}

struct RememberWhereIntent: AppIntent {
    static let title: LocalizedStringResource = "Remember Where I Put Something"
    @Parameter(title: "Item") var item: String
    @Parameter(title: "Place") var place: String
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        var list = Kit.load(KitWhereView.key, as: KitStash.self)
        list.removeAll { $0.item.caseInsensitiveCompare(item) == .orderedSame }
        list.insert(KitStash(item: item, place: place), at: 0)
        Kit.save(list, KitWhereView.key)
        return .result(dialog: "Remembered: \(item) is in \(place).")
    }
}

struct WhereIsItIntent: AppIntent {
    static let title: LocalizedStringResource = "Where Did I Put It?"
    @Parameter(title: "Item") var item: String
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let hit = Kit.load(KitWhereView.key, as: KitStash.self).first { $0.item.localizedCaseInsensitiveContains(item) || item.localizedCaseInsensitiveContains($0.item) }
        guard let hit else { return .result(dialog: "I don't have \(item) written down.") }
        return .result(dialog: "\(hit.item): \(hit.place).")
    }
}

struct WantToBuyIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to My Impulse Waiting List"
    @Parameter(title: "Item") var item: String
    @Parameter(title: "Price") var price: Double?
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let w = KitWant(item: item, price: price ?? 0, days: 30)
        Kit.save([w] + Kit.load(KitWaitlistView.key, as: KitWant.self), KitWaitlistView.key)
        if let at = Calendar.current.date(byAdding: .day, value: 30, to: Date()) {
            Kit.notify("kit.want.\(w.id)", title: "Still want \(item)?", body: "Your wait is over. Decide in Keel: skip it or buy it.", at: at)
        }
        return .result(dialog: "Parked for 30 days. I'll ask you then.")
    }
}

// MARK: - Mind & body

struct ParkWorryIntent: AppIntent {
    static let title: LocalizedStringResource = "Park a Worry"
    @Parameter(title: "Worry") var worry: String
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        Kit.save([KitItem(text: worry)] + Kit.load(KitWorryTimeView.key, as: KitItem.self).prefix(299), KitWorryTimeView.key)
        return .result(dialog: "Parked until worry time. You can let it go for now.")
    }
}

struct SaveIdeaIntent: AppIntent {
    static let title: LocalizedStringResource = "Save an Idea"
    @Parameter(title: "Idea") var idea: String
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        Kit.save([KitIdea(text: idea)] + Kit.load(KitIdeaVaultView.key, as: KitIdea.self), KitIdeaVaultView.key)
        return .result(dialog: "Saved to your idea vault.")
    }
}

struct LogDrinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Drink"
    static let description: IntentDescription = "Logs water, coffee, tea and more for your caffeine and water tracking."
    @Parameter(title: "Drink", default: .water) var drink: KeelDrinkChoice
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let p = Drinks.presets.first(where: { $0.kind == drink.rawValue }) else { return .result(dialog: "Logged.") }
        Drinks.add(p)
        return .result(dialog: "\(p.label) logged. \(Drinks.waterToday) ml today, \(Drinks.caffeineToday) mg caffeine.")
    }
}

enum KeelDrinkChoice: String, AppEnum {
    case water, coffee, espresso, tea, energy, cola
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Drink"
    static let caseDisplayRepresentations: [KeelDrinkChoice: DisplayRepresentation] = [
        .water: "Water", .coffee: "Coffee", .espresso: "Espresso", .tea: "Tea", .energy: "Energy drink", .cola: "Cola",
    ]
}

struct BodyScoresIntent: AppIntent {
    static let title: LocalizedStringResource = "How Recovered Am I?"
    static let description: IntentDescription = "Today's Tide (recovery), Swell (effort) and Anchor (sleep) from Keel's Body screen."
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let s = BodyScores.today() else { return .result(dialog: "No Body scores yet today. Open Body in Keel once Apple Health has last night's data.") }
        let tide = s.tide.map { "Tide \($0)%" } ?? "Tide still learning"
        let anchor = s.anchor.map { ", sleep \($0)" } ?? ""
        return .result(dialog: "\(tide)\(anchor), effort \(s.swell) so far. \(BodyEngine.advice(s.tide))")
    }
}
