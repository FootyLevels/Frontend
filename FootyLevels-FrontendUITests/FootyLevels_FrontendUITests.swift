import XCTest

final class FootyLevels_FrontendUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // A simulator left in landscape hides rows these portrait checks tap.
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testIncludedExampleOpensWithoutLogin() {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        app.tabBars.buttons["Videos"].tap()
        XCTAssertTrue(app.staticTexts["INCLUDED EXAMPLE"].waitForExistence(timeout: 10))
        app.staticTexts["The over fake"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "Included example").firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Welcome to FootyLevels"].exists)
        let stage = app.descendants(matching: .any).matching(identifier: "motion-stage").firstMatch
        XCTAssertTrue(stage.waitForExistence(timeout: 20))
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Ready"), object: stage)], timeout: 45) == .completed,
                      "The bundled 3D motion must finish decoding into the reused player")
    }

    @MainActor
    func testLearnIsHomeAndTabsOpenInRequestedOrder() {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["Lessons"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.tabBars.buttons.allElementsBoundByIndex.map(\.label),
                       ["Learn", "Overlay", "Community", "Videos"])
        XCTAssertTrue(app.tabBars.buttons["Learn"].isSelected)
        for tab in ["Learn", "Overlay", "Community", "Videos"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.tabBars.buttons[tab].isSelected)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Workspace-\(tab)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    /// The Learn tab lists the bundled lessons; a pipeline lesson opens, switches skill and stage.
    @MainActor
    func testLearnTabPlaysABundledLesson() {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        app.tabBars.buttons["Learn"].tap()
        XCTAssertTrue(app.staticTexts["Lessons"].waitForExistence(timeout: 10))
        let lesson = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Chop and Spin Lesson")).firstMatch
        XCTAssertTrue(lesson.waitForExistence(timeout: 5))
        lesson.tap()
        XCTAssertTrue(app.staticTexts["Watch the Cruyff chop"].waitForExistence(timeout: 20))
        let spin = app.buttons["Skill: Cruyff chop"]
        XCTAssertTrue(spin.waitForExistence(timeout: 20))
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: spin)], timeout: 30) == .completed,
                      "The lesson's 3D motion must load from the bundle")
        attachScreenshot(of: app, named: "Light-Lesson")
        spin.tap()
        let antony = app.buttons["Antony spin"]
        XCTAssertTrue(antony.waitForExistence(timeout: 5))
        antony.tap()
        XCTAssertTrue(app.staticTexts["Watch the Antony spin"].waitForExistence(timeout: 5))
        app.buttons["Stage 2: Break it down"].tap()
        XCTAssertTrue(app.staticTexts["Run at him"].waitForExistence(timeout: 5))
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Start the spin"].waitForExistence(timeout: 5))
    }

    /// The "Practise next" card on Learn opens the featured lesson straight at Practise.
    @MainActor
    func testPractiseCardOpensTheLessonAtPractise() {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        app.tabBars.buttons["Learn"].tap()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Practise next")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(app.staticTexts["Chop on the spot"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Stage 3: Practise"].isSelected)
    }

    /// Walks a lesson through the states the approved prototype showed (the sheet at each
    /// height, View open on a side camera, the 3D body swapped in) and keeps a screenshot of
    /// each for comparing against the prototype.
    @MainActor
    func testLessonScreenStatesForTheDesignCheck() {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        app.tabBars.buttons["Learn"].tap()
        let lesson = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Chop and Spin Lesson")).firstMatch
        XCTAssertTrue(lesson.waitForExistence(timeout: 10))
        lesson.tap()
        let breakdown = app.buttons["Stage 2: Break it down"]
        XCTAssertTrue(breakdown.waitForExistence(timeout: 20))
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: breakdown)], timeout: 30) == .completed)
        XCTAssertFalse(app.tabBars.firstMatch.isHittable, "the tab bar is hidden inside a lesson")
        attachScreenshot(of: app, named: "Lesson-1-Watch", settle: 1)

        breakdown.tap()
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Plant and chop"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "Lesson-2-BreakDown", settle: 1)

        app.buttons["Show more of the lesson"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Turn away")).firstMatch.waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "Lesson-3-Half", settle: 1)

        app.buttons["View options"].tap()
        let left = app.buttons["Left camera"]
        XCTAssertTrue(left.waitForExistence(timeout: 5))
        left.tap()
        XCTAssertTrue(left.isSelected)
        attachScreenshot(of: app, named: "Lesson-4-View-Left", settle: 1)

        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Show the video full screen"].waitForExistence(timeout: 5), "the video moved to the corner")
        attachScreenshot(of: app, named: "Lesson-5-3D-Half", settle: 1)

        app.buttons["Show more of the lesson"].tap()
        attachScreenshot(of: app, named: "Lesson-6-Full", settle: 1)
    }

    /// Watch slides the sheet away: the island shows the key point and can be dragged, it is
    /// still there after a relaunch, a drop near home snaps it home, and the stage pill brings
    /// the sheet back.
    @MainActor
    func testWatchSlidesTheSheetAwayAndTheIslandMoves() {
        let app = XCUIApplication()
        app.launchArguments = []
        let breakdown = openChopAndSpin(app)
        breakdown.tap()
        app.buttons["Watch the video full screen"].tap()

        let island = app.descendants(matching: .any)["LessonIsland"]
        let pill = app.buttons["Show the lesson"]
        XCTAssertTrue(island.waitForExistence(timeout: 5))
        XCTAssertTrue(pill.exists)
        XCTAssertEqual(pill.value as? String, "Break it down", "the pill names the stage")
        XCTAssertFalse(breakdown.isHittable, "the sheet has slid away")
        attachScreenshot(of: app, named: "Lesson-7-Island-Open", settle: 1)
        // Drags wait for it to shrink to its name, so its size can't change mid-drag.
        sleep(4)
        attachScreenshot(of: app, named: "Lesson-8-Island-Closed")

        // Home is the bottom left, 18 points above the pill. Dropping it near there snaps it
        // home, which also clears wherever an earlier run left it.
        let screen = app.windows.firstMatch.frame
        let home = CGPoint(x: screen.minX + 16, y: pill.frame.minY - 18)
        dropIsland(island, nearMinX: home.x, maxY: home.y, in: app)
        XCTAssertEqual(island.frame.minX, home.x, accuracy: 2, "a drop near home snaps home")
        XCTAssertEqual(island.frame.maxY, home.y, accuracy: 2)

        let start = island.frame
        drag(island, by: CGVector(dx: screen.maxX - 16 - start.maxX, dy: 220 - start.minY), in: app)
        let moved = island.frame
        XCTAssertGreaterThan(moved.midX, screen.midX)
        XCTAssertLessThan(moved.midY, screen.midY)
        attachScreenshot(of: app, named: "Lesson-9-Island-Moved", settle: 1)

        app.terminate()
        openChopAndSpin(app).tap()
        app.buttons["Watch the video full screen"].tap()
        XCTAssertTrue(island.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(island.frame.midX, screen.midX, "it stays where it was put")
        XCTAssertLessThan(island.frame.midY, screen.midY)

        sleep(4)
        dropIsland(island, nearMinX: home.x, maxY: home.y, in: app)
        XCTAssertEqual(island.frame.minX, home.x, accuracy: 2, "it snaps home from across the screen")
        XCTAssertEqual(island.frame.maxY, home.y, accuracy: 2)
        pill.tap()
        XCTAssertTrue(app.buttons["Stage 2: Break it down"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Stage 2: Break it down"].isHittable, "the pill brings the sheet back")
        XCTAssertFalse(island.exists)
    }

    /// Drops the island 8 points off home, inside the distance that snaps it there, and waits
    /// for it to settle.
    private func dropIsland(_ island: XCUIElement, nearMinX minX: CGFloat, maxY: CGFloat, in app: XCUIApplication) {
        let frame = island.frame
        drag(island, by: CGVector(dx: minX + 8 - frame.minX, dy: maxY - 8 - frame.maxY), in: app)
        sleep(1)
    }

    /// Opens the bundled lesson and waits for its 3D to load. Returns the Break it down stage.
    @discardableResult
    private func openChopAndSpin(_ app: XCUIApplication) -> XCUIElement {
        app.launch()
        app.tabBars.buttons["Learn"].tap()
        let lesson = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Chop and Spin Lesson")).firstMatch
        XCTAssertTrue(lesson.waitForExistence(timeout: 10))
        lesson.tap()
        let breakdown = app.buttons["Stage 2: Break it down"]
        XCTAssertTrue(breakdown.waitForExistence(timeout: 20))
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: breakdown)], timeout: 30) == .completed)
        return breakdown
    }

    private func drag(_ element: XCUIElement, by offset: CGVector, in app: XCUIApplication) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(offset), withVelocity: 600, thenHoldForDuration: 0.2)
    }

    /// Run after the live SDK probe signs out and deletes its temporary accounts.
    @MainActor
    func testSignedOutEmailLoginRoute() {
        let app = XCUIApplication()
        app.launchArguments = ["--require-login"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome to FootyLevels"].waitForExistence(timeout: 10))
        app.buttons["Log In with Email"].tap()
        XCTAssertTrue(app.staticTexts["Welcome Back"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["you@example.com"].exists)
        XCTAssertTrue(app.secureTextFields["Enter your password"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Sign Up with Email"].tap()
        XCTAssertTrue(app.staticTexts["Create Your Account"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Sign Up"].isEnabled)
    }

    @MainActor
    func testCommunityRequiresAnAccountAndKeepsTheSamplePrivate() {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        let community = app.tabBars.buttons["Community"]
        XCTAssertTrue(community.waitForExistence(timeout: 10))
        community.tap()
        XCTAssertTrue(app.staticTexts["Sign in to train together"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@",
            "Training circles belong to your account.")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Create circle"].exists)
        XCTAssertFalse(app.buttons["Share attempt"].exists)
    }

    /// At the largest accessibility text size the sign-in buttons stay reachable and the
    /// email form still opens: text grows and the page scrolls instead of clipping.
    @MainActor
    func testLargestTextKeepsSignInReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["--require-login"] + Self.largestText
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome to FootyLevels"].waitForExistence(timeout: 10))
        let logIn = app.buttons["Log In with Email"]
        XCTAssertTrue(scrollUntilHittable(logIn, in: app), "Log In with Email must be reachable at the largest text size")
        XCTAssertGreaterThanOrEqual(logIn.frame.height, 44)
        logIn.tap()
        XCTAssertTrue(app.staticTexts["Welcome Back"].waitForExistence(timeout: 5))
        XCTAssertTrue(scrollUntilHittable(app.buttons["Log In"], in: app), "the Log In button must scroll into reach")
    }

    /// At the largest accessibility text size a lesson's stage and transport controls stay
    /// reachable, and every one keeps Apple's 44-point minimum tap area.
    @MainActor
    func testLargestTextKeepsLessonControlsReachable() {
        let app = XCUIApplication()
        app.launchArguments = Self.largestText
        app.launch()
        let lesson = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Chop and Spin Lesson")).firstMatch
        XCTAssertTrue(lesson.waitForExistence(timeout: 10))
        XCTAssertTrue(scrollUntilHittable(lesson, in: app))
        lesson.tap()
        let stage = app.buttons["Stage 2: Break it down"]
        XCTAssertTrue(stage.waitForExistence(timeout: 20))
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: stage)], timeout: 30) == .completed,
                      "The lesson's 3D motion must load from the bundle")
        // Sizes only: swiping to scroll here would orbit the 3D camera instead.
        let play = app.buttons.matching(NSPredicate(format: "label == 'Play' OR label == 'Pause'")).firstMatch
        // View options is a system toolbar button: iOS sets its tap area, so it only has to be there.
        XCTAssertTrue(app.buttons["View options"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["View options"].isHittable)
        let controls = [stage, play] + ["Previous", "Next", "Watch the video full screen", "Show more of the lesson"].map { app.buttons[$0] }
        for control in controls {
            XCTAssertTrue(control.waitForExistence(timeout: 5), "\(control) is missing")
            XCTAssertGreaterThanOrEqual(control.frame.height, 44, "\(control.label) is shorter than 44 points")
            XCTAssertGreaterThanOrEqual(control.frame.width, 44, "\(control.label) is narrower than 44 points")
        }
        stage.tap()
        XCTAssertTrue(stage.isSelected)

        // Slid away, the island and the pill stay on screen and the pill stays easy to tap.
        app.buttons["Watch the video full screen"].tap()
        let island = app.descendants(matching: .any)["LessonIsland"]
        let pill = app.buttons["Show the lesson"]
        XCTAssertTrue(island.waitForExistence(timeout: 5))
        XCTAssertTrue(island.isHittable)
        XCTAssertTrue(pill.isHittable)
        XCTAssertGreaterThanOrEqual(pill.frame.height, 44)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(island.frame), "the island fits on screen")
        attachScreenshot(of: app, named: "Lesson-Island-LargestText", settle: 1)
    }

    /// The app follows the phone's appearance: in dark mode Learn, every tab and the
    /// sign-in page still show their content.
    @MainActor
    func testDarkModeShowsLearnTabsAndSignIn() {
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = .light }

        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["Lessons"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Start Chop and Spin")).firstMatch.exists)
        for tab in ["Learn", "Overlay", "Community", "Videos"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.tabBars.buttons[tab].isSelected)
            attachScreenshot(of: app, named: "Dark-\(tab)")
        }

        app.tabBars.buttons["Learn"].tap()
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Start Chop and Spin")).firstMatch.tap()
        let stage = app.buttons["Stage 2: Break it down"]
        XCTAssertTrue(stage.waitForExistence(timeout: 20))
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: stage)], timeout: 30) == .completed,
                      "The lesson's 3D motion must load from the bundle")
        attachScreenshot(of: app, named: "Dark-Lesson")

        app.terminate()
        app.launchArguments = ["--require-login"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome to FootyLevels"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Sign Up with Email"].exists)
        XCTAssertTrue(app.buttons["Log In with Email"].exists)
        attachScreenshot(of: app, named: "Dark-SignIn")
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String, settle: TimeInterval = 0) {
        if settle > 0 { Thread.sleep(forTimeInterval: settle) }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// The accessibility XXXL content size, the largest a person can choose.
    private static let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    /// Scrolls the screen up, a little at a time, until the element can be tapped.
    @MainActor
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 8) -> Bool {
        guard element.waitForExistence(timeout: 5) else { return false }
        for _ in 0..<attempts where !element.isHittable {
            app.swipeUp(velocity: .slow)
        }
        return element.isHittable
    }
}
