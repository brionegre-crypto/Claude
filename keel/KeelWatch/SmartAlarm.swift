import SwiftUI
import WatchKit
import CoreMotion

// MARK: - Smart alarm
//
// Wakes you gently in a lighter moment of sleep instead of in the middle of deep sleep. You pick the latest time
// you want to be up and a window (say 30 minutes). Apple Watch watches your wrist in that window: when you start
// moving (which happens as sleep gets lighter), it taps you awake. If you don't stir, it wakes you at your time.

@MainActor @Observable
final class WatchSmartAlarm: NSObject, WKExtendedRuntimeSessionDelegate {
    static let shared = WatchSmartAlarm()

    private let d = UserDefaults.standard
    var wakeMinutes: Int { didSet { d.set(wakeMinutes, forKey: "alarm.wake") } }       // minutes after midnight
    var window: Int { didSet { d.set(window, forKey: "alarm.window") } }               // minutes
    private(set) var armedFor: Date?
    private(set) var ringing = false

    private var session: WKExtendedRuntimeSession?
    private let motion = CMMotionManager()
    private var movement: [Double] = []
    private var deadline: Timer?

    override init() {
        wakeMinutes = d.object(forKey: "alarm.wake") as? Int ?? 7 * 60
        window = d.object(forKey: "alarm.window") as? Int ?? 30
        super.init()
    }

    /// The next time the alarm would go off.
    var nextWake: Date {
        let cal = Calendar.current
        let today = cal.date(byAdding: .minute, value: wakeMinutes, to: cal.startOfDay(for: Date())) ?? Date()
        return today > Date().addingTimeInterval(60) ? today : (cal.date(byAdding: .day, value: 1, to: today) ?? today)
    }

    func arm() {
        cancel()
        let wake = nextWake
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start(at: wake.addingTimeInterval(-Double(window) * 60))
        session = s
        armedFor = wake
    }

    func cancel() {
        session?.invalidate()
        session = nil
        armedFor = nil
        ringing = false
        motion.stopAccelerometerUpdates()
        deadline?.invalidate(); deadline = nil
    }

    private func ring() {
        guard let s = session, !ringing else { return }
        ringing = true
        motion.stopAccelerometerUpdates()
        // Taps every few seconds until you stop it.
        s.notifyUser(hapticType: .notification) { next in
            next.pointee = 3
            return .notification
        }
    }

    /// Movement in the last minute, sampled from the wrist. Restlessness is a sign of lighter sleep.
    private func startListening(until wake: Date) {
        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 0.5
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let a = data?.acceleration else { return }
            let jolt = abs(sqrt(a.x * a.x + a.y * a.y + a.z * a.z) - 1)        // gravity removed
            MainActor.assumeIsolated {
                self.movement.append(jolt)
                if self.movement.count > 120 { self.movement.removeFirst(self.movement.count - 120) }
                let moving = self.movement.filter { $0 > 0.08 }.count
                if moving >= 6 { self.ring() }                                  // a few clear movements in a minute
            }
        }
        deadline = Timer.scheduledTimer(withTimeInterval: max(1, wake.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.ring() }
        }
    }

    // MARK: WKExtendedRuntimeSessionDelegate

    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        MainActor.assumeIsolated {
            movement = []
            startListening(until: armedFor ?? Date().addingTimeInterval(Double(window) * 60))
        }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        MainActor.assumeIsolated { ring() }
    }

    nonisolated func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                            didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        MainActor.assumeIsolated {
            motion.stopAccelerometerUpdates()
            deadline?.invalidate(); deadline = nil
            session = nil; armedFor = nil; ringing = false
        }
    }
}

struct SmartAlarmPage: View {
    @State private var alarm = WatchSmartAlarm.shared

    var body: some View {
        let wake = Binding<Date>(
            get: { Calendar.current.date(byAdding: .minute, value: alarm.wakeMinutes, to: Calendar.current.startOfDay(for: Date())) ?? Date() },
            set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); alarm.wakeMinutes = (c.hour ?? 7) * 60 + (c.minute ?? 0) })
        List {
            Section {
                DatePicker("Up by", selection: wake, displayedComponents: .hourAndMinute)
                Picker("Window", selection: $alarm.window) {
                    ForEach([10, 20, 30], id: \.self) { Text("\($0) min").tag($0) }
                }
            } footer: { Text("Keel wakes you in a lighter moment of sleep within this window, and at your time at the latest.") }
            if alarm.ringing {
                Button("I'm up") { alarm.cancel() }.tint(.orange)
            } else if let at = alarm.armedFor {
                Label("Set for \(at.formatted(date: .omitted, time: .shortened))", systemImage: "alarm.fill").foregroundStyle(.indigo)
                Button("Turn off", role: .destructive) { alarm.cancel() }
            } else {
                Button { alarm.arm() } label: { Label("Set smart alarm", systemImage: "alarm") }.tint(.indigo)
            }
        }
        .navigationTitle("Smart alarm")
    }
}
