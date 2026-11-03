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
        let spin = app.buttons["Antony spin, Skill 2 · named"]
        XCTAssertTrue(spin.waitForExistence(timeout: 20))
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: spin)], timeout: 30) == .completed,
                      "The lesson's 3D motion must load from the bundle")
        attachScreenshot(of: app, named: "Light-Lesson")
        spin.tap()
        XCTAssertTrue(app.staticTexts["Watch the Antony spin"].waitForExistence(timeout: 5))
        app.buttons["Stage 2: Break it down"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "START THE SPIN")).firstMatch.waitForExistence(timeout: 5))
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
        let controls = [stage, play] + ["Back one frame", "Forward one frame", "Loop", "Mirror"].map { app.buttons[$0] }
        for control in controls {
            XCTAssertTrue(control.waitForExistence(timeout: 5), "\(control) is missing")
            XCTAssertGreaterThanOrEqual(control.frame.height, 44, "\(control.label) is shorter than 44 points")
            XCTAssertGreaterThanOrEqual(control.frame.width, 44, "\(control.label) is narrower than 44 points")
        }
        stage.tap()
        XCTAssertTrue(stage.isSelected)
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
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
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
