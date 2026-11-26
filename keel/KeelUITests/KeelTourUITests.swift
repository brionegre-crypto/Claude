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
        app.launchArguments += ["-KeelDemo", "YES", "-KeelDemoReset", "YES"]     // fresh demo data for every test
        // KEEL_ATTACH=1: Keel was already launched (by Instruments, with -KeelDemo YES); drive that copy.
        if ProcessInfo.processInfo.environment["KEEL_ATTACH"] == "1" { app.activate() } else { app.launch() }
    }

    func testTourEveryScreen() {
        XCTAssertTrue(tab("inbox").waitForExistence(timeout: 20), "tab bar never appeared")
        checkpoint("home")

        // Settings → Customize Keel → Look & feel → Chart Table
        tap(app.buttons["Settings"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        checkpoint("settings")
        tap(find("Customize Keel"))
        tap(find("Look & feel"))
        let chart = find("Chart Table")
        checkpoint("customize-look")
        tap(chart)
        checkpoint("customize-chart-table")
        tap(app.navigationBars["Appearance"].buttons.element(boundBy: 0))         // back from Look & feel
        tap(app.navigationBars["Customize Keel"].buttons.element(boundBy: 0))     // back from Customize
        tap(app.navigationBars["Settings"].buttons["Done"])

        for lap in 0..<laps {
            let first = lap == 0
            visit("inbox", shot: first ? "inbox" : nil)
            visit("tasks", shot: first ? "tasks" : nil)
            visit("calendar", shot: nil)
            if first {
                tap(app.buttons.matching(NSPredicate(format: "label == 'Day'")).firstMatch)     // Calendar → Day
                checkpoint("calendar-day")
                scroll()
            }
            visit("notes", shot: first ? "notes" : nil)
            visit("today", shot: nil)
        }

        // The Log button in the middle of the floating bar: the one-line capture sheet.
        tap(barButton("log"))
        checkpoint("log")
        tap(app.navigationBars["Capture"].buttons["Cancel"])     // close the sheet
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.navigationBars["Capture"])
        wait(for: [gone], timeout: 5)

        // Body: the Body card on Home opens the full Body screen.
        let body = find("Body")
        clearOfBar(body)
        tap(body)
        let opened = app.navigationBars.matching(NSPredicate(format: "identifier IN %@", ["Body", "Condition"])).firstMatch   // "Condition" in Chart Table
        XCTAssertTrue(opened.waitForExistence(timeout: 8), "Body didn't open")
        checkpoint("body")
        scroll()
    }

    /// For Instruments: switch between Inbox, Tasks and Calendar (week and day) and scroll each, three times over.
    func testProfileSwitchAndScroll() {
        XCTAssertTrue(tab("inbox").waitForExistence(timeout: 20), "tab bar never appeared")
        for _ in 0..<3 {
            for id in ["inbox", "tasks", "calendar"] {
                tap(tab(id))
                scroll()
                if id == "calendar" {
                    for mode in ["Week", "Day"] {
                        tap(app.buttons.matching(NSPredicate(format: "label == %@", mode)).firstMatch)
                        scroll()
                    }
                }
            }
        }
    }

    /// Routines from lists: a suggested Reminders list, picking any list, then the linked routine on the Voyage.
    func testRoutinesFromLists() {
        XCTAssertTrue(tab("inbox").waitForExistence(timeout: 20), "tab bar never appeared")
        tap(tab("tasks"))
        tap(app.buttons["Schedule"])                       // Tasks → wand menu → Routines
        tap(find("Routines"))
        XCTAssertTrue(app.navigationBars["Routines"].waitForExistence(timeout: 8))
        XCTAssertTrue(find("Use “Bedtime” as a routine").waitForExistence(timeout: 5), "Bedtime list not suggested")
        checkpoint("rl1-suggested")
        tap(app.buttons.matching(NSPredicate(format: "label == 'Use'")).firstMatch)
        checkpoint("rl2-linked-editor")
        tap(app.buttons["Save"])
        closeFitOffer()
        checkpoint("rl3-routines")
        tap(find("Use a Reminders list as a routine"))
        checkpoint("rl4-list-picker")
        tap(find("Errands"))
        tap(app.buttons["Save"])
        closeFitOffer()
        XCTAssertTrue(find("Errands").waitForExistence(timeout: 5))
        checkpoint("rl5-routines-linked")

        // The Bedtime routine on the Voyage: tick a step, which completes that reminder.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap(tab("today"))
        tap(app.buttons["Home options"])
        tap(find("Full Today"))
        let bedtime = find("Bedtime routine")
        clearOfBar(bedtime)
        tap(bedtime)
        checkpoint("rl6-voyage-bedtime")
        tap(app.buttons["Mark Take magnesium done"])
        checkpoint("rl7-ticked")
    }

    /// Loose tasks into routines: Keel's suggestions (approved), adding by hand, and the offer after linking a list.
    func testTasksFitRoutines() {
        XCTAssertTrue(tab("inbox").waitForExistence(timeout: 20), "tab bar never appeared")
        tap(tab("tasks"))
        tap(app.buttons["Schedule"])
        tap(find("Routines"))
        XCTAssertTrue(app.navigationBars["Routines"].waitForExistence(timeout: 8))
        let chip = app.buttons.matching(NSPredicate(format: "label ENDSWITH 'fit Morning'")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 8), "no routine shows tasks that fit")
        checkpoint("fit1-chips")
        tap(chip)
        checkpoint("fit2-suggested")
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add '")).firstMatch)
        checkpoint("fit3-added")

        // By hand: Evening wind-down → Edit → Add from your tasks → pick "Water the plants".
        tap(find("Evening wind-down"))
        tap(find("Add from your tasks"))
        let field = app.searchFields["Find a task"]           // not Inbox's search (that tab is kept ready behind)
        tap(field); field.typeText("plants")
        tap(find("Water the plants"))
        checkpoint("fit4-manual-pick")
        // The bottom button stays reachable while searching.
        let addButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add ' AND label ENDSWITH 'to Evening wind-down'")).firstMatch
        if !addButton.waitForExistence(timeout: 8) {
            add(XCTAttachment(string: app.debugDescription))      // what was on screen, for the record
        }
        tap(addButton)
        checkpoint("fit5-manual-added")
        tap(app.buttons["Save"])

        // Link the Bedtime list: Keel offers the loose tasks that fit it as soon as the routine is saved.
        tap(app.buttons.matching(NSPredicate(format: "label == 'Use'")).firstMatch)
        tap(app.buttons["Save"])
        XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH 'Add to'")).firstMatch.waitForExistence(timeout: 8),
                      "no offer after linking Bedtime")
        checkpoint("fit6-offer-after-link")
    }

    /// Keel Voice: Settings (your work, your words), the mic in the Log sheet and the listening bar.
    func testKeelVoiceScreens() {
        XCTAssertTrue(tab("inbox").waitForExistence(timeout: 20), "tab bar never appeared")
        tap(app.buttons["Settings"])
        tap(find("Keel Voice"))
        XCTAssertTrue(app.navigationBars["Keel Voice"].waitForExistence(timeout: 5))
        let work = app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH 'e.g.'")).firstMatch
        tap(work); work.typeText("Pastor and men's ministry coach")
        checkpoint("kv1-settings")
        tap(app.navigationBars["Keel Voice"].buttons.element(boundBy: 0))
        tap(app.navigationBars["Settings"].buttons["Done"])

        tap(barButton("log"))
        let mic = app.descendants(matching: .any)["keelVoice.mic"].firstMatch
        XCTAssertTrue(mic.waitForExistence(timeout: 5), "no mic in the Log sheet")
        checkpoint("kv2-log-mic")
        mic.tap()
        checkpoint("kv3-listening")
    }

    /// Routines on the Voyage (Home → ⋯ → Full Today): tick steps, skip one today, take one out, tick a whole routine, edit.
    func testRoutinesOnVoyage() {
        XCTAssertTrue(tab("inbox").waitForExistence(timeout: 20), "tab bar never appeared")
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

    /// After a list becomes a routine, Keel may offer loose tasks that fit it; this test isn't about that, so close it.
    private func closeFitOffer() {
        let offer = app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH 'Add to'")).firstMatch
        if offer.waitForExistence(timeout: 3) { offer.buttons["Cancel"].tap() }
    }

    private func scrollTo(_ e: XCUIElement) {
        var n = 0
        while !(e.exists && e.isHittable) && n < 10 { app.swipeUp(velocity: .slow); n += 1 }
    }

    /// The floating bar sits over the bottom of each screen; scroll until `e` is above it so a tap lands on `e`.
    private func clearOfBar(_ e: XCUIElement) {
        let bar = barButton("log")
        guard bar.exists else { return }
        var n = 0
        while e.exists && e.frame.maxY > bar.frame.minY - 90 && n < 6 {
            app.swipeUp(velocity: .slow); n += 1
        }
    }

    /// A button on Keel's floating tab bar ("tab.inbox", "tab.log"…).
    private func barButton(_ id: String) -> XCUIElement { app.descendants(matching: .any)["tab." + id].firstMatch }

    /// A tab by id (today, inbox, calendar, tasks, notes): the floating bar, or the system tab bar in classic looks.
    private func tab(_ id: String) -> XCUIElement {
        let b = barButton(id)
        if b.exists { return b }
        let names = ["today": ["Today", "Helm", "Log", "Bridge"], "calendar": ["Calendar", "Chart"]][id] ?? [id.capitalized]
        return names.lazy.map { self.app.tabBars.buttons[$0] }.first { $0.exists } ?? app.tabBars.buttons[names[0]]
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
