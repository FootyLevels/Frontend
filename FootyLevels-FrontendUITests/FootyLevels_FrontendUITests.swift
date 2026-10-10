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
}
