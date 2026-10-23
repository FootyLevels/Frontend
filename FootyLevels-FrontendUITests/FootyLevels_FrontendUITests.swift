import XCTest

final class FootyLevels_FrontendUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testIncludedExampleOpensWithoutLogin() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["INCLUDED EXAMPLE"].waitForExistence(timeout: 10))
        app.staticTexts["The over fake"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "Included example").firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Welcome to FootyLevels"].exists)
        let stage = app.descendants(matching: .any).matching(identifier: "motion-stage").firstMatch
        XCTAssertTrue(stage.waitForExistence(timeout: 20))
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Ready"), object: stage)], timeout: 45) == .completed,
                      "The bundled 3D motion must finish decoding into the reused player")
    }

    /// The Learn tab lists the bundled lessons; a pipeline lesson opens, switches skill and stage.
    @MainActor
    func testLearnTabPlaysABundledLesson() {
        let app = XCUIApplication()
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
}
