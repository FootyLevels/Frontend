import CryptoKit
import Foundation
import XCTest
@testable import FootyLevels_Frontend

private final class LessonURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@MainActor (URLRequest) async throws -> (Int, Data))?
    private var operation: Task<Void, Never>?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let request = request
        operation = Task {
            do {
                let (status, bytes) = try await Self.handler!(request)
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: bytes)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() { operation?.cancel() }
}

@MainActor
private final class LessonCredentials: APICredentials {
    var currentSession: AccountSession? = AccountSession(uid: "alice", generation: UUID())
    func token(for session: AccountSession, forceRefresh: Bool) async throws -> String { "fixture-firebase-token" }
    func invalidate(_ session: AccountSession) { currentSession = nil }
}

/// Serves a copy of a bundled lesson the way the backend publishes a user's lesson.
@MainActor
private final class LessonServer {
    static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }

    let credentials = LessonCredentials()
    let client: CloudLessonClient
    var files: [String: Data] = [:]
    var lessonJSON: [String: Any] = [:]
    var requests: [URLRequest] = []
    var createStatus = 202
    let lessonID = String(repeating: "e", count: 64)

    init() throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [LessonURLProtocol.self]
        client = try CloudLessonClient(apiURL: URL(string: "https://api.example.test")!, credentials: credentials,
                                       environment: .dev, apiSession: URLSession(configuration: config))
        let bundled = try XCTUnwrap(LessonLibrary.lessons().first, "the app ships lesson bundles")
        let enumerator = FileManager.default.enumerator(at: bundled.url, includingPropertiesForKeys: nil)!
        for case let url as URL in enumerator where !url.hasDirectoryPath {
            let name = url.path.replacingOccurrences(of: bundled.url.path + "/", with: "")
            files[name] = try Data(contentsOf: url)
        }
        let source: [String: Any] = ["bucket": "private-media", "objectKey": "users/alice/projects/p1/media/\(String(repeating: "f", count: 64))/1/video.mp4",
                                     "sha256": String(repeating: "a", count: 64), "byteSize": 10, "contentType": "video/mp4"]
        lessonJSON = ["id": lessonID, "ownerId": "alice", "projectId": "p1", "jobId": lessonID, "inputRevision": 1,
                      "profileVersion": "lesson-3d-v1", "sourceAsset": source, "title": "Chop and spin",
                      "skills": [["id": "chop", "name": "Chop"]],
                      "authoring": ["model": "gemini-4-carbon", "mode": "grounded", "promptSha256": String(repeating: "a", count: 64),
                                    "claimsRemoved": 2, "calls": 10],
                      "artifacts": files.keys.sorted().map(asset), "aiGenerated": true, "state": "ready",
                      "completedAt": "2026-11-11T10:00:00Z", "schemaVersion": 1,
                      "createdAt": "2026-11-11T10:00:00Z", "updatedAt": "2026-11-11T10:00:00Z"]
        LessonURLProtocol.handler = { [unowned self] request in
            self.requests.append(request)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-firebase-token")
            switch (request.httpMethod!, request.url!.path) {
            case ("GET", "/api/me"): return (200, try Self.json(["id": "alice", "consents": ["lessonAi": ["accepted": false]]]))
            case ("PUT", "/api/me/consents/lesson-ai"): return (200, try Self.json(["lessonAi": ["accepted": true]]))
            case ("POST", "/api/projects/p1/lessons"):
                return (self.createStatus, self.createStatus == 202 ? try Self.json(self.jobJSON(status: "queued")) : Data("{}".utf8))
            case ("GET", "/api/jobs/\(self.lessonID)"): return (200, try Self.json(self.jobJSON(status: "succeeded")))
            case ("GET", "/api/lessons"): return (200, try Self.json(["items": [self.lessonJSON]]))
            case ("GET", "/api/lessons/\(self.lessonID)"): return (200, try Self.json(self.lessonJSON))
            case ("POST", "/api/lessons/\(self.lessonID)/assets"): return (200, try Self.json(self.grant()))
            default: throw URLError(.badURL)
            }
        }
    }

    func asset(_ name: String) -> [String: Any] {
        let data = files[name]!
        let type = name.hasSuffix(".json") ? "application/json" : name.hasSuffix(".mp4") ? "video/mp4"
            : name.hasSuffix(".gz") ? "application/gzip" : "application/octet-stream"
        return ["bucket": "private-media", "objectKey": "users/alice/projects/p1/lesson/\(lessonID)/1/\(name)",
                "sha256": Self.sha(data), "byteSize": data.count, "contentType": type]
    }

    func grant() -> [String: Any] {
        ["expiresAt": ISO8601DateFormatter.fractional.string(from: Date().addingTimeInterval(300)),
         "assets": Dictionary(uniqueKeysWithValues: files.keys.map { name -> (String, [String: Any]) in
             var value = asset(name)
             value["url"] = "https://bwzxrvkxfubnmuieljoj.supabase.co/storage/v1/object/sign/private-media/\(value["objectKey"]!)?token=t"
             return (name, value)
         })]
    }

    func jobJSON(status: String) -> [String: Any] {
        ["id": lessonID, "ownerId": "alice", "projectId": "p1", "kind": "buildLesson", "inputRevision": 1,
         "profileVersion": "lesson-3d-v1", "inputHash": String(repeating: "b", count: 64), "sourceAsset": lessonJSON["sourceAsset"]!,
         "attemptCount": 1, "status": status, "stage": status == "queued" ? "queued" : "ready",
         "lessonId": status == "succeeded" ? lessonID : NSNull()]
    }

    func lesson() throws -> CloudLesson { try JSONDecoder().decode(CloudLesson.self, from: Self.json(lessonJSON)) }

    func project() throws -> CloudProject {
        let media: [String: Any] = ["profileVersion": "media-720p30-v1", "video": lessonJSON["sourceAsset"]!, "width": 720,
                                    "height": 720, "fps": 30, "duration": 9, "frameCount": 270, "previews": []]
        return try JSONDecoder().decode(CloudProject.self, from: Self.json(
            ["id": "p1", "ownerId": "alice", "title": "Clip", "state": "ready", "inputRevision": 1, "preparedMedia": media]))
    }

    /// Download transport for signed URLs: serves the file the URL names.
    var transport: PrivatePlaybackAssets.Transport {
        let files = files, prefix = "/storage/v1/object/sign/private-media/users/alice/projects/p1/lesson/\(lessonID)/1/"
        return { url, _ in try XCTUnwrap(files[String(url.path.dropFirst(prefix.count))]) }
    }
}

@MainActor
final class CloudLessonClientTests: XCTestCase {
    func testConsentCreateAndJobAreCheckedForThisAccount() async throws {
        let server = try LessonServer()
        let consented = try await server.client.hasConsent()
        XCTAssertFalse(consented)
        try await server.client.setConsent(true)
        let job = try await server.client.create(project: server.project(), key: "lesson-fixture-key-0001")
        XCTAssertEqual(job.kind, "buildLesson")
        XCTAssertEqual(job.statusText, "Waiting for the lesson builder")
        let post = try XCTUnwrap(server.requests.first { $0.url!.path == "/api/projects/p1/lessons" })
        XCTAssertEqual(post.value(forHTTPHeaderField: "Idempotency-Key"), "lesson-fixture-key-0001")
        let done = try await server.client.job(server.lessonID, project: server.project())
        XCTAssertEqual(done.lessonId, server.lessonID)
    }

    func testRefusalsBecomeLessonErrors() async throws {
        let server = try LessonServer()
        for (status, expected) in [(403, CloudLessonError.consentRequired), (422, .tooLong), (429, .quota)] {
            server.createStatus = status
            do {
                _ = try await server.client.create(project: server.project(), key: "lesson-fixture-key-0002")
                XCTFail("expected \(expected)")
            } catch let error as CloudLessonError { XCTAssertEqual(error, expected) }
        }
    }

    func testLessonsFromAnotherAccountOrPrefixAreRejected() async throws {
        let server = try LessonServer()
        let listed = try await server.client.lessons()
        XCTAssertEqual(listed.map(\.id), [server.lessonID])
        server.lessonJSON["ownerId"] = "bob"
        let foreign = try await server.client.lessons()
        XCTAssertEqual(foreign, [])
        server.lessonJSON["ownerId"] = "alice"
        var artifacts = server.lessonJSON["artifacts"] as! [[String: Any]]
        artifacts[0]["objectKey"] = (artifacts[0]["objectKey"] as! String).replacingOccurrences(of: "/1/", with: "/2/")
        server.lessonJSON["artifacts"] = artifacts
        XCTAssertThrowsError(try server.lesson().bundleFiles(owner: "alice"))
    }
}

@MainActor
final class UserLessonStoreTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("user-lessons-\(UUID().uuidString)")
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    func testServedLessonInstallsAndOpensWithTheAppLoader() async throws {
        let server = try LessonServer()
        let store = try UserLessonStore(uid: "alice", root: root)
        let lesson = try await server.client.lesson(server.lessonID)
        let assets = try server.client.assets(for: lesson, transport: server.transport)
        defer { assets.close() }
        let url = try await store.install(lesson, assets: assets)
        XCTAssertEqual(url.lastPathComponent, "Lesson-\(server.lessonID).bundle")
        let package = try LessonPackage.load(url)
        XCTAssertFalse(package.document.skills.isEmpty)
        XCTAssertNotNil(store.entry(for: server.lessonID))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: store.folder.path)
        XCTAssertEqual(leftovers, ["Lesson-\(server.lessonID).bundle"])
    }

    func testACorruptDownloadIsNeverInstalled() async throws {
        let server = try LessonServer()
        let store = try UserLessonStore(uid: "alice", root: root)
        let lesson = try await server.client.lesson(server.lessonID)
        let assets = try server.client.assets(for: lesson) { _, _ in Data("tampered".utf8) }
        defer { assets.close() }
        do { _ = try await store.install(lesson, assets: assets); XCTFail("expected a verification failure") }
        catch {}
        XCTAssertFalse(store.hasBundle(for: server.lessonID))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.folder.path), [])
    }

    func testOtherAccountsAndDeletedLessonsAreRemoved() throws {
        let bob = try UserLessonStore(uid: "bob", root: root)
        try FileManager.default.createDirectory(at: bob.bundleURL(for: "old"), withIntermediateDirectories: true)
        let alice = try UserLessonStore(uid: "alice", root: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bob.folder.path))
        try FileManager.default.createDirectory(at: alice.bundleURL(for: "gone"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: alice.bundleURL(for: "kept"), withIntermediateDirectories: true)
        alice.prune(keeping: ["kept"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: alice.folder.path), ["Lesson-kept.bundle"])
    }
}

final class LessonJobStatusTests: XCTestCase {
    private func job(_ status: String, stage: String = "running", error: String? = nil) throws -> CloudJob {
        let source: [String: Any] = ["bucket": "private-media", "objectKey": "users/a/projects/p/media/x/1/video.mp4",
                                     "sha256": String(repeating: "a", count: 64), "byteSize": 1, "contentType": "video/mp4"]
        var value: [String: Any] = ["id": "j", "ownerId": "a", "projectId": "p", "inputRevision": 1, "kind": "buildLesson",
                                    "status": status, "stage": stage, "attemptCount": 1, "inputHash": "h",
                                    "profileVersion": "lesson-3d-v1", "sourceAsset": source]
        if let error { value["errorCode"] = error }
        return try JSONDecoder().decode(CloudJob.self, from: JSONSerialization.data(withJSONObject: value))
    }

    func testLessonStagesReadAsProgress() throws {
        XCTAssertEqual(try job("running", stage: "screeningVideo").statusText, "Checking your video")
        XCTAssertEqual(try job("running", stage: "generatingBodies").statusText, "Building your 3D motion")
        XCTAssertEqual(try job("running", stage: "writingLesson").statusText, "Writing your lesson")
        XCTAssertEqual(try job("succeeded", stage: "ready").statusText, "Lesson ready")
        XCTAssertEqual(try job("failed", stage: "failed", error: "lesson_rejected").statusText,
                       "No football skill to teach was found in this video")
    }
}
