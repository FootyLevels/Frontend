import Foundation
import XCTest
@testable import FootyLevels_Frontend

private final class PreparingProjectURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@MainActor (URLRequest) async throws -> (Int, Data))?
    private var operation: Task<Void, Never>?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let request = request
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        operation = Task {
            do {
                try Task.checkCancellation()
                let (status, data) = try await handler(request)
                try Task.checkCancellation()
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                if !Task.isCancelled { client?.urlProtocol(self, didFailWithError: error) }
            }
        }
    }
    override func stopLoading() { operation?.cancel() }
}

@MainActor
private final class PreparingProjectCredentials: APICredentials {
    var currentSession: AccountSession? = AccountSession(uid: "alice", generation: UUID())
    func token(for session: AccountSession, forceRefresh: Bool) async throws -> String { "preparing-project-test-token" }
    func invalidate(_ session: AccountSession) { currentSession = nil }
}

final class CloudUploadsViewModelTests: XCTestCase {
    override func tearDown() { PreparingProjectURLProtocol.handler = nil; super.tearDown() }

    private static func json(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    private static func payload(id: String = "pending", owner: String = "alice", state: String = "preparing", title: String = "Practice") -> [String: Any] {
        ["id": id, "ownerId": owner, "title": title, "state": state, "inputRevision": 2]
    }
    private static func project(id: String = "pending", owner: String = "alice", state: String = "preparing") throws -> CloudProject {
        try JSONDecoder().decode(CloudProject.self, from: json(payload(id: id, owner: owner, state: state)))
    }
    @MainActor
    private func coordinator(_ credentials: PreparingProjectCredentials, root: URL) throws -> CloudUploadCoordinator {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PreparingProjectURLProtocol.self]
        return try CloudUploadCoordinator(apiURL: URL(string: "https://api.example.test")!, environment: .dev,
            credentials: credentials, apiSession: URLSession(configuration: configuration), root: root)
    }

    @MainActor
    func testPreparingRefreshPreservesLoadedPagesOrderAndNextCursor() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = PreparingProjectCredentials()
        let model = CloudUploadsViewModel(coordinator: try coordinator(credentials, root: root))
        var reads: [String] = []
        PreparingProjectURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer preparing-project-test-token")
            switch request.url!.path {
            case "/api/deletions": return (200, try Self.json(["items": []]))
            case "/api/projects/pending":
                reads.append("pending")
                return (200, try Self.json(Self.payload(state: "ready")))
            case "/api/projects":
                let cursor = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "cursor" })?.value
                if cursor == "page-two" {
                    return (200, try Self.json(["items": [Self.payload(id: "older-two", state: "ready")], "nextCursor": "page-three"]))
                }
                if cursor == "page-three" {
                    return (200, try Self.json(["items": [Self.payload(id: "older-three", state: "ready")], "nextCursor": NSNull()]))
                }
                return (200, try Self.json(["items": [Self.payload(), Self.payload(id: "older-one", state: "ready")], "nextCursor": "page-two"]))
            default: XCTFail("Unexpected preparing refresh request"); return (500, Data())
            }
        }
        await model.refresh()
        await model.refresh(more: true)
        await model.refreshPreparingProjects()
        XCTAssertEqual(model.projects.map(\.id), ["pending", "older-one", "older-two"])
        XCTAssertEqual(model.projects.map(\.state), ["ready", "ready", "ready"])
        XCTAssertEqual(reads, ["pending"])
        XCTAssertTrue(model.hasMore)
        await model.refresh(more: true)
        XCTAssertEqual(model.projects.map(\.id), ["pending", "older-one", "older-two", "older-three"])
        XCTAssertFalse(model.hasMore)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testForeignOwnerAndWrongProjectResponsesCannotReplacePreparingRecord() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = PreparingProjectCredentials()
        let original = try Self.project()
        for response in [Self.payload(owner: "bob", state: "ready"), Self.payload(id: "another-project", state: "ready")] {
            let model = CloudUploadsViewModel(coordinator: try coordinator(credentials, root: root))
            model.projects = [original]
            PreparingProjectURLProtocol.handler = { _ in (200, try Self.json(response)) }
            await model.refreshPreparingProjects()
            XCTAssertEqual(model.projects, [original])
            XCTAssertNotNil(model.errorMessage)
            XCTAssertEqual(credentials.currentSession?.uid, "alice")
        }
    }

    @MainActor
    func testForeignOrUnsafeProjectInputDoesNotMakeARequest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = try coordinator(PreparingProjectCredentials(), root: root)
        PreparingProjectURLProtocol.handler = { _ in XCTFail("Unowned project requested"); return (500, Data()) }
        for project in [try Self.project(owner: "bob"), try Self.project(id: "../other")] {
            do { _ = try await service.project(project); XCTFail("Invalid input accepted") }
            catch { XCTAssertEqual(error as? AccountAPIError, .sessionChanged) }
        }
    }

    @MainActor
    func testAccountSwitchFencesAnInFlightPreparingResponse() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = PreparingProjectCredentials()
        let model = CloudUploadsViewModel(coordinator: try coordinator(credentials, root: root))
        let original = try Self.project()
        model.projects = [original]
        PreparingProjectURLProtocol.handler = { _ in
            credentials.currentSession = AccountSession(uid: "bob", generation: UUID())
            return (200, try Self.json(Self.payload(state: "ready")))
        }
        await model.refreshPreparingProjects()
        XCTAssertEqual(model.projects, [original])
        XCTAssertEqual(credentials.currentSession?.uid, "bob")
    }

    @MainActor
    func testNormalRefreshWinsOverAnOlderPreparingResponse() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CloudUploadsViewModel(coordinator: try coordinator(PreparingProjectCredentials(), root: root))
        model.projects = [try Self.project()]
        PreparingProjectURLProtocol.handler = { request in
            switch request.url!.path {
            case "/api/projects/pending":
                await model.refresh()
                return (200, try Self.json(Self.payload(state: "ready", title: "Older poll")))
            case "/api/projects":
                return (200, try Self.json(["items": [Self.payload(state: "ready", title: "Fresh library")], "nextCursor": "later-page"]))
            case "/api/deletions": return (200, try Self.json(["items": []]))
            default: XCTFail("Unexpected request"); return (500, Data())
            }
        }
        await model.refreshPreparingProjects()
        XCTAssertEqual(model.projects.first?.title, "Fresh library")
        XCTAssertTrue(model.hasMore)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testViewTaskCancellationDoesNotPublishOrDisplayAnError() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CloudUploadsViewModel(coordinator: try coordinator(PreparingProjectCredentials(), root: root))
        let original = try Self.project()
        model.projects = [original]
        var work: Task<Void, Never>?
        PreparingProjectURLProtocol.handler = { _ in
            work?.cancel()
            return (200, try Self.json(Self.payload(state: "ready")))
        }
        work = Task { await model.refreshPreparingProjects() }
        await work?.value
        XCTAssertEqual(model.projects, [original])
        XCTAssertNil(model.errorMessage)
    }
}
