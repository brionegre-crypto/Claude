import XCTest

/// Walks every main screen of Keel with made-up data (the app's debug-only `-KeelDemo` mode: no sign-ins, no sync).
/// Used for screenshots and for profiling tab switches and scrolling with Instruments:
///
///     xcodebuild test -scheme KeelTour -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
///
/// Set TEST_RUNNER_KEEL_SYNC_DIR to a folder and the tour pauses at each screen, writing `<name>.ready` and
/// waiting for `<name>.done`, so a script outside can take a `simctl io screenshot` of exactly that screen.
final class KeelTourUITests: XCTestCase {
    private var app: XCUIApplication!
    private let syncDir = ProcessInfo.processInfo.environment["KEEL_SYNC_DIR"]
    private let laps = Int(ProcessInfo.processInfo.environment["KEEL_TOUR_LAPS"] ?? "") ?? 1

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-KeelDemo", "YES"]
        // KEEL_ATTACH=1: Keel was already launched (by Instruments, with -KeelDemo YES); drive that copy.
        if ProcessInfo.processInfo.environment["KEEL_ATTACH"] == "1" { app.activate() } else { app.launch() }
    }

    func testTourEveryScreen() {
        XCTAssertTrue(tab("Inbox").waitForExistence(timeout: 20), "tab bar never appeared")
        checkpoint("01-home")

        // Settings → Customize Keel → Look & feel → Chart Table
        tap(app.buttons["Settings"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        checkpoint("07-settings")
        tap(find("Customize Keel"))
        tap(find("Look & feel"))
        let chart = find("Chart Table")
        checkpoint("00a-customize-look")
        tap(chart)
        checkpoint("00b-customize-chart-table")
        tap(app.navigationBars["Appearance"].buttons.element(boundBy: 0))         // back from Look & feel
        tap(app.navigationBars["Customize Keel"].buttons.element(boundBy: 0))     // back from Customize
        tap(app.navigationBars["Settings"].buttons["Done"])

        for lap in 0..<laps {
            let first = lap == 0
            visit("Inbox", shot: first ? "02-inbox" : nil)
            visit("Tasks", shot: first ? "03-tasks" : nil)
            visit(calendarTabName, shot: first ? "04-calendar" : nil)
            visit("Notes", shot: first ? "05-notes" : nil)
            visit("Today", shot: nil)
        }

        // Body: the Body card on Home opens the full Body screen.
        tap(find("Body"))
        _ = app.navigationBars["Body"].waitForExistence(timeout: 5)
        checkpoint("06-body")
        scroll()
    }

    /// Routines on the Voyage (Home → ⋯ → Full Today): tick steps, skip one today, take one out, tick a whole routine, edit.
    func testRoutinesOnVoyage() {
        XCTAssertTrue(tab("Inbox").waitForExistence(timeout: 20), "tab bar never appeared")
        tap(app.buttons["Home options"])
        tap(find("Full Today"))
        let morning = find("Morning routine")
        app.swipeUp(velocity: .slow)                         // a little room below it for the steps
        scrollTo(morning)
        checkpoint("r1-voyage-collapsed")
        tap(morning)
        checkpoint("r2-morning-expanded")
        tap(app.buttons["Mark Shower done"])
        checkpoint("r3-ticked-a-step")
        tap(app.buttons["More for Get dressed"]); tap(find("Skip today"))
        checkpoint("r4-skipped-today")
        tap(app.buttons["More for Breakfast"]); tap(find("Remove from routine"))
        checkpoint("r5-removed-step")
        let leaving = app.buttons["Mark Leaving the house routine done"]
        scrollTo(leaving)
        tap(leaving)
        checkpoint("r6-whole-routine-done")
        scrollTo(find("Edit routine"))
        tap(find("Edit routine"))
        checkpoint("r7-edit-routine")
        tap(app.buttons["Cancel"])
    }

    // MARK: Helpers

    private func scrollTo(_ e: XCUIElement) {
        var n = 0
        while !(e.exists && e.isHittable) && n < 10 { app.swipeUp(velocity: .slow); n += 1 }
    }

    /// The calendar tab is named per theme ("Chart" in Chart Table).
    private var calendarTabName: String { tab("Chart").exists ? "Chart" : "Calendar" }

    private func tab(_ name: String) -> XCUIElement {
        let t = app.tabBars.buttons[name]
        return t.exists ? t : app.buttons[name]
    }

    private func visit(_ name: String, shot: String?) {
        tap(tab(name))
        if let shot { checkpoint(shot) }
        scroll()
    }

    /// Flick down the screen and back, like reading it.
    private func scroll() {
        for _ in 0..<3 { app.swipeUp(velocity: .fast) }
        for _ in 0..<3 { app.swipeDown(velocity: .fast) }
    }

    /// The first element whose label starts with `label`, scrolled into view.
    private func find(_ label: String) -> XCUIElement {
        let e = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@ AND (elementType == %d OR elementType == %d OR elementType == %d)",
                                                                     label, XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.cell.rawValue,
                                                                     XCUIElement.ElementType.staticText.rawValue)).firstMatch
        _ = e.waitForExistence(timeout: 3)
        var n = 0
        while !(e.exists && e.isHittable) && n < 10 { app.swipeUp(velocity: .slow); n += 1 }
        return e
    }

    private func tap(_ e: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        guard e.waitForExistence(timeout: 8) else { XCTFail("missing \(e)", file: file, line: line); return }
        e.tap()
    }

    /// Lets the script outside take a simulator screenshot of this exact screen.
    private func checkpoint(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
        guard let dir = syncDir else { return }
        Thread.sleep(forTimeInterval: 1.0)                       // let the screen settle
        FileManager.default.createFile(atPath: "\(dir)/\(name).ready", contents: nil)
        let done = "\(dir)/\(name).done"
        let until = Date().addingTimeInterval(20)
        while !FileManager.default.fileExists(atPath: done) && Date() < until { Thread.sleep(forTimeInterval: 0.2) }
    }
}
