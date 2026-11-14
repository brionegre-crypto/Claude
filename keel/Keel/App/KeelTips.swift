import SwiftUI
import TipKit

// In-app tips (Apple's TipKit): each one explains a feature right where you'll use it, once, and goes away
// when you close it or use the feature. At most one new tip a day, so they never pile up.

enum KeelTips {
    static func configure() {
        TipsReset.applyIfAsked()                 // "Show all tips again" (Settings → Keel status)
        try? Tips.configure([.displayFrequency(.daily)])
    }
}

struct AskAITip: Tip {
    var title: Text { Text("Write with AI in any page") }
    var message: Text? { Text("Press space on an empty line, or type /ai. Select text and tap ✨ above the keyboard to rewrite it. Pick Apple Intelligence, Claude, ChatGPT or Gemini each time.") }
    var image: Image? { Image(systemName: "sparkles") }
}

struct CaptureTip: Tip {
    var title: Text { Text("Capture anything with +") }
    var message: Text? { Text("The + button is on every screen. Type or talk; Keel guesses if it's a task, event, note or reminder.") }
    var image: Image? { Image(systemName: "plus.circle.fill") }
}

struct OpenWaterTip: Tip {
    var title: Text { Text("Your day as a route") }
    var message: Text? { Text("Meetings are ports, timed tasks are waypoints, and “open water” is free time. Tap open water to fill it.") }
    var image: Image? { Image(systemName: "water.waves") }
}

struct PlanDayTip: Tip {
    var title: Text { Text("Drag tasks onto your day") }
    var message: Text? { Text("Open Plan my day, then drag a task onto an hour to block time for it. It goes on your calendar.") }
    var image: Image? { Image(systemName: "calendar.badge.plus") }
}

struct BookingTip: Tip {
    var title: Text { Text("Let people book time with you") }
    var message: Text? { Text("Turn on your booking link and share it. People pick from your real free times, and the meeting lands on your calendar.") }
    var image: Image? { Image(systemName: "link.badge.plus") }
}

struct AssignTip: Tip {
    var title: Text { Text("Hand a task to someone") }
    var message: Text? { Text("In a task, choose Assign to pick a person. Keel can email it to them and keeps it in Delegated until it's done.") }
    var image: Image? { Image(systemName: "person.crop.circle.badge.checkmark") }
}

struct TimelineTip: Tip {
    var title: Text { Text("See dates as a timeline") }
    var message: Text? { Text("Databases with a date can show as a timeline: each row is a bar across the days it covers.") }
    var image: Image? { Image(systemName: "chart.bar.xaxis") }
}
