import AVFoundation
import Foundation
import XCTest
@testable import FootyLevels_Frontend

private final class StorageProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class PrivateUploadTests: XCTestCase {
    override func tearDown() { StorageProtocol.handler = nil; super.tearDown() }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StorageProtocol.self]
        return URLSession(configuration: config)
    }

    private func fixture(bytes: Int) -> UploadDraft {
        UploadDraft(id: UUID().uuidString, ownerId: "alice", scope: "scope", title: "Practice", label: nil,
            source: "gallery", byteSize: bytes, sha256: String(repeating: "a", count: 64), projectId: "project", uploadId: "upload")
    }

    private func grant(bytes: Int, host: String = ApplicationEnvironment.dev.storageHost) throws -> PrivateUploadGrant {
        let json: [String: Any] = ["id": "upload", "status": "uploading", "protocol": "tus", "expectedBytes": bytes, "chunkSize": 6*1024*1024,
            "endpoint": "https://\(host)/storage/v1/upload/resumable/sign",
            "headers": ["x-signature": "test-signature", "x-upsert": "false"],
            "metadata": ["bucketName": "private-media", "objectName": "users/alice/projects/project/source/upload.mp4",
                         "contentType": "video/mp4", "cacheControl": "0"]]
        return try JSONDecoder().decode(PrivateUploadGrant.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @MainActor
    func testResumedTransferUsesConfirmedOffsetAndNeverFirebaseCredentials() async throws {
        let size = PrivateTUSClient.chunkSize + 9
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(repeating: 3, count: size).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let client = PrivateTUSClient(environment: .dev, session: session())
        var offset = PrivateTUSClient.chunkSize // First chunk was sent before interruption.
        var requests: [String] = []
        StorageProtocol.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "apikey"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-signature"), "test-signature")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-upsert"), "false")
            requests.append(request.httpMethod!)
            if request.httpMethod == "HEAD" { return (200, ["Upload-Offset": "\(offset)", "Upload-Length": "\(size)"], Data()) }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Upload-Offset"), "\(offset)")
            let count = request.httpBody?.count ?? 9 // URLSession may expose body through a stream.
            XCTAssertLessThanOrEqual(count, PrivateTUSClient.chunkSize)
            offset += count
            return (204, ["Upload-Offset": "\(offset)"], Data())
        }
        var lastProgress = 0.0
        try await client.transfer(file: file, at: URL(string: "https://\(client.host)/storage/v1/upload/resumable/sign/test-location")!,
            grant: grant(bytes: size), total: size, checkSession: {}, progress: { lastProgress = $0 })
        XCTAssertEqual(requests, ["HEAD", "PATCH"])
        XCTAssertEqual(offset, size)
        XCTAssertEqual(lastProgress, 1)
    }

    @MainActor
    func testForeignOriginsAndWrongObjectCannotReceiveSignature() throws {
        let client = PrivateTUSClient(environment: .dev, session: session())
        let draft = fixture(bytes: 10)
        XCTAssertNoThrow(try client.validate(grant(bytes: 10), draft: draft))
        XCTAssertThrowsError(try client.validate(grant(bytes: 10, host: ApplicationEnvironment.demo.storageHost), draft: draft))
        XCTAssertThrowsError(try client.validate(grant(bytes: 11), draft: draft))
        var other = draft
        other.projectId = "someone-else"
        XCTAssertThrowsError(try client.validate(grant(bytes: 10), draft: other))
        for text in ["http://\(client.host)/storage/v1/upload/resumable/sign/id",
                     "https://evil.example/storage/v1/upload/resumable/sign/id",
                     "https://\(client.host)/storage/v1/object/id",
                     "https://user@\(client.host)/storage/v1/upload/resumable/sign/id",
                     "https://\(client.host)/storage/v1/upload/resumable/sign/%2e%2e/id",
                     "https://\(client.host)/storage/v1/upload/resumable/sign/id?token=anything"] {
            XCTAssertFalse(client.validURL(URL(string: text)!), text)
        }
    }

    @MainActor
    func testUntrustedLocationAndInvalidOffsetsAreRejected() async throws {
        let client = PrivateTUSClient(environment: .dev, session: session())
        StorageProtocol.handler = { _ in (201, ["Location": "https://evil.example/upload"], Data()) }
        do { _ = try await client.create(grant(bytes: 10), draft: fixture(bytes: 10), checkSession: {}); XCTFail() }
        catch { XCTAssertEqual(error as? ClipUploadError, .invalidGrant) }
        StorageProtocol.handler = { _ in (200, ["Upload-Length": "10", "Upload-Offset": "11"], Data()) }
        do { _ = try await client.offset(at: URL(string: "https://\(client.host)/storage/v1/upload/resumable/sign/id")!,
            grant: grant(bytes: 10), total: 10, checkSession: {}); XCTFail() }
        catch { XCTAssertEqual(error as? ClipUploadError, .invalidOffset) }
    }

    @MainActor
    func testAccountChangeStopsTransferBeforeAnotherChunk() async throws {
        let client = PrivateTUSClient(environment: .dev, session: session())
        var active = true
        StorageProtocol.handler = { _ in
            active = false
            return (200, ["Upload-Length": "10", "Upload-Offset": "0"], Data())
        }
        do {
            _ = try await client.offset(at: URL(string: "https://\(client.host)/storage/v1/upload/resumable/sign/id")!,
                grant: grant(bytes: 10), total: 10, checkSession: { if !active { throw AccountAPIError.sessionChanged } })
            XCTFail()
        } catch { XCTAssertEqual(error as? AccountAPIError, .sessionChanged) }
    }

    func testPrivateDraftSurvivesRecreationAndIsIsolatedByOwnerEnvironmentAndAPI() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let api = URL(string: "https://api.example")!
        let first = try UploadDraftStore(ownerId: "alice", environment: .dev, apiURL: api, root: root)
        let draft = UploadDraft(id: UUID().uuidString, ownerId: "alice", scope: first.scope, title: "Saved", label: nil,
            source: "capture", byteSize: 10, sha256: String(repeating: "a", count: 64))
        try first.save(draft)
        XCTAssertEqual(try UploadDraftStore(ownerId: "alice", environment: .dev, apiURL: api, root: root).load(), [draft])
        XCTAssertTrue(try UploadDraftStore(ownerId: "bob", environment: .dev, apiURL: api, root: root).load().isEmpty)
        XCTAssertTrue(try UploadDraftStore(ownerId: "alice", environment: .demo, apiURL: api, root: root).load().isEmpty)
        XCTAssertTrue(try UploadDraftStore(ownerId: "alice", environment: .dev, apiURL: URL(string: "https://other.example")!, root: root).load().isEmpty)
        let data = try Data(contentsOf: first.directory(draft.id).appendingPathComponent("draft.json"))
        let text = String(data: data, encoding: .utf8)!
        XCTAssertFalse(text.contains("signature")); XCTAssertFalse(text.contains("token")); XCTAssertFalse(text.contains("https://"))
        XCTAssertThrowsError(try first.directory("../bad"))
    }

    func testInvalidInputRejectedBeforeProjectCreation() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try Data("broken movie".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        do { _ = try await VideoClipPreparer.inspect(file); XCTFail("Accepted a corrupt clip") }
        catch { /* AVFoundation or the validator rejects it before networking. */ }
        XCTAssertThrowsError(try UploadDraftStore.fingerprint(URL(fileURLWithPath: "/no/such/file")))
    }
}

@MainActor
private final class UploadCredentials: APICredentials {
    var currentSession: AccountSession? = AccountSession(uid: "alice", generation: UUID())
    func token(for session: AccountSession, forceRefresh: Bool) async throws -> String { "firebase-test-only" }
    func invalidate(_ session: AccountSession) { currentSession = nil }
}

extension PrivateUploadTests {
    @MainActor
    func testLostProjectResponseRecoversSameDraftAfterRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = UploadCredentials()
        let api = URL(string: "https://api.example")!
        let coordinator = try CloudUploadCoordinator(apiURL: api, environment: .dev, credentials: credentials,
                                                     apiSession: session(), root: root)
        let data = Data("small test fixture".utf8)
        let id = UUID().uuidString.lowercased()
        let dir = try coordinator.store.directory(id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("clip.mp4")
        try data.write(to: file)
        let fingerprint = try UploadDraftStore.fingerprint(file)
        let draft = UploadDraft(id: id, ownerId: "alice", scope: coordinator.store.scope, title: "Practice", label: nil,
            source: "gallery", byteSize: fingerprint.bytes, sha256: fingerprint.hash)
        try coordinator.store.save(draft)
        var keys: [String] = []
        var firstCreate = true
        StorageProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer firebase-test-only")
            let path = request.url!.path
            if path == "/api/projects" {
                keys.append(request.value(forHTTPHeaderField: "Idempotency-Key")!)
                if firstCreate { firstCreate = false; throw URLError(.timedOut) } // Server created it, response lost.
                return (201, [:], Data(#"{"id":"same-project","ownerId":"alice","title":"Practice","state":"uploading","inputRevision":1}"#.utf8))
            }
            if path.hasSuffix("/upload-session") {
                return (200, [:], Data(#"{"id":"upload","status":"committed"}"#.utf8))
            }
            XCTAssertEqual(path, "/api/uploads/upload/finalize")
            return (202, [:], Data(#"{"id":"same-project","ownerId":"alice","title":"Practice","state":"preparing","inputRevision":2}"#.utf8))
        }
        do { _ = try await coordinator.upload(draft, progress: { _ in }); XCTFail("Lost response should leave a draft") }
        catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        XCTAssertNil(try coordinator.store.load().first?.projectId)
        let restored = try CloudUploadCoordinator(apiURL: api, environment: .dev, credentials: credentials,
                                                 apiSession: session(), root: root)
        let finished = try await restored.upload(try XCTUnwrap(restored.store.load().first), progress: { _ in })
        XCTAssertEqual(finished.id, "same-project")
        XCTAssertEqual(keys, [id, id])
        XCTAssertTrue(try restored.store.load().isEmpty)
        credentials.currentSession = AccountSession(uid: "alice", generation: UUID())
        do { _ = try await restored.list(); XCTFail("Previous same-UID session must be fenced") }
        catch { XCTAssertEqual(error as? AccountAPIError, .sessionChanged) }
    }

    @MainActor
    func testStaleOffsetIsResynchronizedWithoutResendingWholeFile() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(repeating: 3, count: 10).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let client = PrivateTUSClient(environment: .dev, session: session())
        var calls = 0
        StorageProtocol.handler = { request in
            calls += 1
            if request.httpMethod == "HEAD" {
                return (200, ["Upload-Length": "10", "Upload-Offset": calls == 1 ? "0" : "7"], Data())
            }
            if calls == 2 { return (409, [:], Data()) }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Upload-Offset"), "7")
            return (204, ["Upload-Offset": "10"], Data())
        }
        try await client.transfer(file: file, at: URL(string: "https://\(client.host)/storage/v1/upload/resumable/sign/location")!,
            grant: grant(bytes: 10), total: 10, checkSession: {}, progress: { _ in })
        XCTAssertEqual(calls, 4)
    }
}

extension PrivateUploadTests {
    func testPreparedSampleKeepsVideoRemovesAudioAndAppliesTrim() async throws {
        let project = try XCTUnwrap(BundledSample.project)
        let input = try XCTUnwrap(BundledSample.fileURL(forAssetPath: project.video.url))
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: output) }
        try await VideoClipPreparer.prepare(input, start: 1, end: 3, destination: output)
        let details = try await VideoClipPreparer.inspect(output)
        XCTAssertEqual(details.duration, 2, accuracy: 0.1)
        let asset = AVURLAsset(url: output)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let video = try await asset.loadTracks(withMediaType: .video)
        XCTAssertTrue(audio.isEmpty)
        XCTAssertEqual(video.count, 1)
        let size = try await video[0].load(.naturalSize)
        let transform = try await video[0].load(.preferredTransform)
        let bounds = size.applying(transform)
        XCTAssertGreaterThan(abs(bounds.height), abs(bounds.width), "Portrait orientation should survive preparation")
        XCTAssertLessThanOrEqual(try UploadDraftStore.fingerprint(output).bytes, 52_428_800)
        for (start, end) in [(-1.0, 3.0), (0.0, 61.0), (3.0, 3.5)] {
            do { try await VideoClipPreparer.prepare(input, start: start, end: end, destination: output); XCTFail() }
            catch { XCTAssertEqual(error as? ClipUploadError, .invalidTrim) }
        }
    }

    func testOversizeDraftIsRejectedWithoutReadingWholeFileIntoMemory() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        _ = FileManager.default.createFile(atPath: file.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: file) }
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 52_428_801)
        try handle.close()
        XCTAssertThrowsError(try UploadDraftStore.fingerprint(file)) { error in
            XCTAssertEqual(error as? ClipUploadError, .tooLarge)
        }
    }
}
