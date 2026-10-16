import Foundation
import XCTest
@testable import FootyLevels_Frontend

private final class AccountURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@MainActor (URLRequest) async throws -> (Int, Data))?
    private var operation: Task<Void, Never>?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let request = request
        operation = Task {
            do {
                guard let handler = Self.handler else { throw URLError(.badServerResponse) }
                let (status, data) = try await handler(request)
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }
    override func stopLoading() { operation?.cancel() }
}

@MainActor
private final class TestCredentials: APICredentials {
    var currentSession: AccountSession? = AccountSession(uid: "alice", generation: UUID())
    var refreshes: [Bool] = []
    var invalidations = 0
    var beforeToken: (() -> Void)?
    func token(for session: AccountSession, forceRefresh: Bool) async throws -> String {
        refreshes.append(forceRefresh)
        beforeToken?()
        return forceRefresh ? "refreshed-token" : "first-token"
    }
    func invalidate(_ session: AccountSession) {
        guard currentSession == session else { return }
        invalidations += 1
        currentSession = nil
    }
}

final class AuthenticatedAPIClientTests: XCTestCase {
    @MainActor
    private func client(_ credentials: TestCredentials) throws -> AuthenticatedAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AccountURLProtocol.self]
        return try AuthenticatedAPIClient(baseURL: URL(string: "https://api.example.test")!,
                                          credentials: credentials, session: URLSession(configuration: config))
    }

    @MainActor
    func testNoSessionNeverMakesCloudRequest() async throws {
        let credentials = TestCredentials()
        credentials.currentSession = nil
        AccountURLProtocol.handler = { _ in XCTFail("Unauthenticated network request"); return (200, Data()) }
        do { _ = try await client(credentials).profile(); XCTFail("Expected sign-in") }
        catch { XCTAssertEqual(error as? AccountAPIError, .signInRequired) }
        XCTAssertTrue(credentials.refreshes.isEmpty)
    }

    @MainActor
    func testBearerTokenAndSingleRefresh() async throws {
        let credentials = TestCredentials()
        var requests = 0
        AccountURLProtocol.handler = { request in
            requests += 1
            XCTAssertEqual(request.url?.host, "api.example.test")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), requests == 1 ? "Bearer first-token" : "Bearer refreshed-token")
            return requests == 1 ? (401, Data()) : (200, Data(#"{"id":"alice","displayName":"Alice","accountState":"active"}"#.utf8))
        }
        let profile = try await client(credentials).bootstrap()
        XCTAssertEqual(profile.id, "alice")
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(credentials.refreshes, [false, true])
    }

    @MainActor
    func testRepeated401InvalidatesOnlyCurrentSession() async throws {
        let credentials = TestCredentials()
        AccountURLProtocol.handler = { _ in (401, Data()) }
        do { _ = try await client(credentials).profile(); XCTFail("Expected sign-in") }
        catch { XCTAssertEqual(error as? AccountAPIError, .signInRequired) }
        XCTAssertEqual(credentials.refreshes, [false, true])
        XCTAssertEqual(credentials.invalidations, 1)
        XCTAssertNil(credentials.currentSession)
    }

    @MainActor
    func testAccountSwitchDuringTokenFetchSendsNothing() async throws {
        let credentials = TestCredentials()
        credentials.beforeToken = { credentials.currentSession = AccountSession(uid: "bob", generation: UUID()) }
        AccountURLProtocol.handler = { _ in XCTFail("Stale identity was sent"); return (200, Data()) }
        do { _ = try await client(credentials).profile(); XCTFail("Expected session change") }
        catch { XCTAssertEqual(error as? AccountAPIError, .sessionChanged) }
    }

    @MainActor
    func testLateResponseCannotReplaceAnotherAccountsDataOrSignItOut() async throws {
        for status in [200, 401] {
            let credentials = TestCredentials()
            AccountURLProtocol.handler = { _ in
                credentials.currentSession = AccountSession(uid: "bob", generation: UUID())
                return (status, Data(#"{"id":"alice","displayName":"Alice","accountState":"active"}"#.utf8))
            }
            do { _ = try await client(credentials).profile(); XCTFail("Stale response accepted") }
            catch { XCTAssertEqual(error as? AccountAPIError, .sessionChanged) }
            XCTAssertEqual(credentials.currentSession?.uid, "bob")
            XCTAssertEqual(credentials.invalidations, 0)
        }
    }

    @MainActor
    func testSameAccountNewSessionDiscardsOldResponse() async throws {
        let credentials = TestCredentials()
        AccountURLProtocol.handler = { _ in
            credentials.currentSession = AccountSession(uid: "alice", generation: UUID())
            return (200, Data())
        }
        do { _ = try await client(credentials).request("GET", path: "/api/me"); XCTFail("Stale response accepted") }
        catch { XCTAssertEqual(error as? AccountAPIError, .sessionChanged) }
    }

    @MainActor
    func testForeignAssetURLsCannotReceiveTokens() async throws {
        let credentials = TestCredentials()
        let api = try client(credentials)
        for path in ["https://storage.example.test/object", "//storage.example.test/object", "/assets-data/private", "/api/../assets-data/private", "file:///secret"] {
            do { _ = try await api.request("GET", path: path); XCTFail("Unsafe URL accepted") }
            catch { XCTAssertEqual(error as? AccountAPIError, .unsafeAddress) }
        }
        XCTAssertTrue(credentials.refreshes.isEmpty)
    }

    @MainActor
    func testUnsafeBaseURLsAreRejected() {
        for address in ["http://public.example.test", "https://user:password@api.example.test", "https://api.example.test/prefix", "https://api.example.test?x=1"] {
            XCTAssertFalse(AuthenticatedAPIClient.validBaseURL(URL(string: address)!))
        }
        XCTAssertTrue(AuthenticatedAPIClient.validBaseURL(URL(string: "https://api.example.test")!))
    }

    @MainActor
    func testServerUnavailableDoesNotSignOutOrRetryMutation() async throws {
        let credentials = TestCredentials()
        var requests = 0
        AccountURLProtocol.handler = { _ in requests += 1; return (503, Data()) }
        do { _ = try await client(credentials).bootstrap(); XCTFail("Expected unavailable") }
        catch { XCTAssertEqual(error as? AccountAPIError, .unavailable) }
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(credentials.invalidations, 0)
    }
}
