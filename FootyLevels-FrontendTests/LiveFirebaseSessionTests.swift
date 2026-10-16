import FirebaseAuth
import FirebaseCore
import Foundation
import XCTest
@testable import FootyLevels_Frontend

/// Explicit opt-in only. Creates temporary Development users; never runs in Demo.
/// The operator removes the exact metadata IDs in the evidence file after the run.
final class LiveFirebaseSessionTests: XCTestCase {
    @MainActor
    func testRealEmailSessionsAndOwnedAPI() async throws {
        guard ProcessInfo.processInfo.environment["FOOTYLEVELS_LIVE_AUTH_TESTS"] == "1" else {
            throw XCTSkip("Real Firebase account mutations require explicit opt-in")
        }
        XCTAssertEqual(FirebaseApp.app()?.options.projectID, "footylevels-dev-20261009")
        guard FirebaseApp.app()?.options.projectID == "footylevels-dev-20261009",
              let address = ProcessInfo.processInfo.environment["FOOTYLEVELS_AUTH_TEST_API"],
              let url = URL(string: address), url.host == "127.0.0.1" else {
            throw AccountAPIError.unsafeAddress
        }
        let api = try AuthenticatedAPIClient(baseURL: url, credentials: FirebaseAPICredentials.shared)
        let runID = UUID().uuidString.lowercased()
        var accounts: [(uid: String, email: String, password: String)] = []
        var projects: [String] = []
        let evidence = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("fp14-ios-evidence.json")
        func saveEvidence(_ phase: String) throws {
            try JSONSerialization.data(withJSONObject: ["runID": runID, "users": accounts.map(\.uid),
                "projects": projects, "phase": phase], options: .prettyPrinted).write(to: evidence, options: .atomic)
        }
        func cleanAccounts() async throws {
            for account in accounts {
                let result = try await Auth.auth().signIn(withEmail: account.email, password: account.password)
                try await result.user.delete()
            }
            try AuthManager.shared.signOut()
        }
        do {
            try AuthManager.shared.signOut()
            for suffix in ["a", "b"] {
                let email = "fp14-ios-\(runID)-\(suffix)@example.invalid"
                let password = UUID().uuidString + UUID().uuidString
                let result = try await Auth.auth().createUser(withEmail: email, password: password)
                accounts.append((result.user.uid, email, password))
                try saveEvidence("created-account")
                let first = try await api.bootstrap()
                let repeated = try await api.bootstrap()
                XCTAssertEqual(first.id, result.user.uid)
                XCTAssertEqual(repeated.id, first.id)
                let body = try JSONSerialization.data(withJSONObject: ["title": "FP14 iOS \(runID)", "source": "gallery"])
                let data = try await api.request("POST", path: "/api/projects", body: body)
                let project = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                projects.append(try XCTUnwrap(project["id"] as? String))
                try saveEvidence("created-project")
                try AuthManager.shared.signOut()
                do { _ = try await api.profile(); XCTFail("Logged-out cloud access succeeded") }
                catch { XCTAssertEqual(error as? AccountAPIError, .signInRequired) }
            }
            for (index, account) in accounts.enumerated() {
                _ = try await AuthManager.shared.loginWithEmail(email: account.email, password: account.password)
                let profile = try await api.profile()
                XCTAssertEqual(profile.id, account.uid)
                _ = try await api.request("GET", path: "/api/projects/\(projects[index])")
                for method in ["GET", "DELETE"] {
                    do {
                        _ = try await api.request(method, path: "/api/projects/\(projects[1-index])")
                        XCTFail("Foreign project access succeeded")
                    } catch { XCTAssertEqual(error as? AccountAPIError, .notFound) }
                }
                try AuthManager.shared.signOut()
            }
            // The included example remains usable after logout.
            let sample = try await SkillLabClient.shared.project(id: BundledSample.id)
            XCTAssertEqual(sample.id, BundledSample.id)
            try await cleanAccounts()
            try saveEvidence("passed-auth-accounts-deleted")
        } catch {
            try? await cleanAccounts()
            try? saveEvidence("failed-needs-metadata-cleanup")
            throw error
        }
    }
}
