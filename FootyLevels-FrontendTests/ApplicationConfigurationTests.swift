import FirebaseCore
import Foundation
import XCTest
@testable import FootyLevels_Frontend

final class ApplicationConfigurationTests: XCTestCase {
    func testConfiguredProjectAndBundledResources() throws {
        #if DEBUG
        let expected = "footylevels-dev-20261009"
        #else
        let expected = "footylevels-demo-20261009"
        #endif
        XCTAssertEqual(FirebaseApp.app()?.options.projectID, expected)
        XCTAssertNil(Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"))
        for name in ["GoogleService-Info-Dev", "GoogleService-Info-Demo"] {
            XCTAssertNotNil(Bundle.main.path(forResource: name, ofType: "plist"))
        }
    }

    @MainActor
    func testReleaseCannotReachSharedLegacyService() throws {
        #if DEBUG
        XCTAssertTrue(ServerSettings.legacyServiceEnabled)
        #else
        XCTAssertFalse(ServerSettings.legacyServiceEnabled)
        XCTAssertNil(ServerSettings.baseURL)
        XCTAssertFalse(AuthenticatedAPIClient.validBaseURL(URL(string: "http://127.0.0.1:8011")!))
        XCTAssertThrowsError(try SkillLabClient.shared.url(for: "https://legacy.example.test/assets-data/private"))
        #endif
        let sample = try XCTUnwrap(BundledSample.project)
        XCTAssertTrue(try SkillLabClient.shared.url(for: sample.video.url).isFileURL)
    }
}
