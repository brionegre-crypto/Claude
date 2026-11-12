import Foundation
import ActivityKit
import Observation
import FamilyControls
import ManagedSettings
import AppIntents
import UserNotifications

/// Escalating Shutdown for uninterrupted work.
///  Level 1 – Soft:   Keel hides inbox + badges, holds its own notifications, distraction-free UI.
///  Level 2 – Shield: Screen Time shields the apps/sites YOU picked (FamilyControls, on-device, private).
///  Level 3 – Locked: same shields, but ending early requires a 60-second "are you sure?" cool-down.
/// Plus the end-of-day Shutdown Ritual (see ShutdownRitualView).
@MainActor @Observable
final class ShutdownManager {
    static let shared = ShutdownManager()

    enum Level: Int, CaseIterable, Identifiable {
        case soft = 1, shield, locked
        var id: Int { rawValue }
        var title: String { switch self { case .soft: "Soft"; case .shield: "Shield"; case .locked: "Locked" } }
        var detail: String {
            switch self {
            case .soft: "Hide inbox and hold Keel alerts"
            case .shield: "Also block the apps you choose"
            case .locked: "Blocks + a cool-down before quitting"
            }
        }
    }

    private let store = ManagedSettingsStore(named: .init("keel.focus"))
    var selection = FamilyActivitySelection()       // apps/sites picked via FamilyActivityPicker
    private(set) var isAuthorized = false
    private(set) var active: FocusSession?
    private(set) var level: Level = .soft
    var endsAt: Date? { active.map { $0.startedAt.addingTimeInterval(Double($0.plannedMinutes * 60)) } }

    /// Why app blocking isn't available, if it isn't (shown in the Focus screen instead of failing silently).
    private(set) var blockingUnavailableReason: String?

    func authorize() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
            blockingUnavailableReason = isAuthorized ? nil : "Screen Time permission wasn't granted. You can allow it in Settings → Screen Time."
        } catch {
            isAuthorized = false
            // Simulator, or a TestFlight build before Apple approves the FamilyControls entitlement.
            blockingUnavailableReason = "App blocking isn't available in this build yet. Soft focus still hides your inbox and holds Keel's alerts."
        }
    }

    func start(minutes: Int, level: Level, task: TaskItem?) -> FocusSession {
        let s = FocusSession(plannedMinutes: minutes, mode: "deep", taskId: task?.id)
        active = s
        BreakReminders.schedule(skipUntil: Date().addingTimeInterval(Double(minutes * 60)))   // no breaks mid-focus
        self.level = level
        if level != .soft, isAuthorized {
            store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
            store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
            store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        }
        scheduleTransitionNudges(minutes: minutes)
        startLiveActivity(endsAt: s.startedAt.addingTimeInterval(Double(minutes * 60)), task: task?.title)
        FocusSound.shared.play(FocusSound.Kind(rawValue: UserDefaults.standard.string(forKey: "focus.sound") ?? "off") ?? .off)
        Haptics.milestone()
        return s
    }

    /// Lock Screen + Dynamic Island countdown.
    private func startLiveActivity(endsAt: Date, task: String?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(state: FocusActivityAttributes.ContentState(endsAt: endsAt, taskTitle: task),
                                      staleDate: endsAt.addingTimeInterval(60))
        _ = try? Activity.request(attributes: FocusActivityAttributes(startedAt: Date()), content: content)
    }

    private func endLiveActivities() {
        Task {
            for activity in Activity<FocusActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    func end(early: Bool) {
        defer { BreakReminders.schedule(skipUntil: Date()) }
        endLiveActivities()
        FocusSound.shared.stop()
        store.clearAllSettings()
        active?.endedAt = Date()
        active?.brokeEarly = early
        active = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["focus.5min", "focus.end", "focus.hyper"])
    }

    /// ADHD: transitions are hard. Warn 5 min before the end, and guard against hyperfocus afterwards.
    private func scheduleTransitionNudges(minutes: Int) {
        let center = UNUserNotificationCenter.current()
        func note(_ id: String, _ title: String, _ body: String, after seconds: Double) {
            guard seconds > 0 else { return }
            let c = UNMutableNotificationContent()
            c.title = title; c.body = body; c.interruptionLevel = .timeSensitive
            center.add(UNNotificationRequest(identifier: id, content: c,
                                             trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)))
        }
        note("focus.5min", "5 minutes left", "Start wrapping up — jot where you stopped so future-you can restart fast.", after: Double((minutes - 5) * 60))
        note("focus.end", "Focus block done 🎉", "Stand up, water, 5-minute break. Your next thing is ready when you are.", after: Double(minutes * 60))
        if UserDefaults.standard.bool(forKey: "focus.hyperfocusOff") { return }
        note("focus.hyper", "Hyperfocus check", "You've gone 30 min past your block. Still the right thing to be doing?", after: Double((minutes + 30) * 60))
    }
}

/// iOS Focus Filter: when the user's system Focus (e.g. "Work") turns on, Keel auto-enters Soft shutdown.
struct KeelFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Keel Focus"
    static let description: IntentDescription? = "Hide the inbox and only show what you're working on."

    // iOS calls perform() with the *default* values when the Focus turns off, so the default must be
    // the no-Focus state (inbox visible). Users switch this on when adding the filter to a Focus.
    @Parameter(title: "Hide inbox", default: false) var hideInbox: Bool

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "Keel: \(hideInbox ? "inbox hidden" : "normal")") }

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(hideInbox, forKey: "focus.hideInbox")
        return .result()
    }

    /// Re-reads the active Focus filter (defaults when no Focus is on) so a stale "hide inbox" never sticks.
    static func syncCurrent() async {
        let hide = (try? await KeelFocusFilter.current)?.hideInbox ?? false
        UserDefaults.standard.set(hide, forKey: "focus.hideInbox")
    }
}
