import AVFoundation
import CryptoKit
import Foundation
import XCTest
@testable import FootyLevels_Frontend

private final class CommunityURLProtocol: URLProtocol {
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
                let (status, bytes) = try await handler(request)
                try Task.checkCancellation()
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: bytes); client?.urlProtocolDidFinishLoading(self)
            } catch {
                if !Task.isCancelled { client?.urlProtocol(self, didFailWithError: error) }
            }
        }
    }
    override func stopLoading() { operation?.cancel() }
}

@MainActor
private final class CommunityCredentials: APICredentials {
    var currentSession: AccountSession? = AccountSession(uid: "alice", generation: UUID())
    func token(for session: AccountSession, forceRefresh: Bool) async throws -> String { "fixture-token" }
    func invalidate(_ session: AccountSession) { currentSession = nil }
}

@MainActor
private final class CommunityFixture {
    let credentials = CommunityCredentials()
    let client: CommunityClient
    let bytes = Data("prepared-video-fixture".utf8)
    var postJSON: [String: Any] = [:]
    var circleJSON: [String: Any] = [:]
    var video: [String: Any] = [:]
    var asset: [String: Any] = [:]
    var grantLifetime: Double = 60
    var postReads = 0
    init() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CommunityURLProtocol.self]
        client = try CommunityClient(apiURL: URL(string: "https://api.example.test")!, credentials: credentials,
            environment: .dev, apiSession: URLSession(configuration: configuration))
        asset = ["bucket": "private-media", "objectKey": "users/alice/projects/project/media/\(String(repeating: "a", count: 64))/1/video.mp4",
            "sha256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), "byteSize": bytes.count, "contentType": "video/mp4"]
        video = ["duration": 2.0, "fps": 30, "frameCount": 60, "width": 720, "height": 480, "asset": asset]
        postJSON = ["id": "post", "circleId": "circle", "authorId": "alice", "authorName": "Alice", "projectId": "project",
            "projectTitle": "Practice", "skill": "Elastico", "note": "Second touch?", "createdAt": "2026-10-16T12:00:00Z", "video": video]
        circleJSON = ["id": "circle", "name": "Training", "description": "Tuesday practice", "ownerId": "alice",
            "createdAt": "2026-10-16T12:00:00Z", "memberCount": 2,
            "members": [["uid": "alice", "displayName": "Alice", "joinedAt": "2026-10-16T12:00:00Z"],
                ["uid": "bob", "displayName": "Bob", "joinedAt": "2026-10-16T12:00:00Z"]]]
        CommunityURLProtocol.handler = { [weak self] request in
            guard let self else { throw URLError(.cancelled) }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
            switch request.url!.path {
            case "/api/circles": return (200, try Self.encode(["items": [self.circleJSON]]))
            case "/api/circles/circle": return (200, try Self.encode(self.circleJSON))
            case "/api/circles/circle/posts/post": self.postReads += 1; return (200, try Self.encode(self.postJSON))
            case "/api/circles/circle/posts/post/assets": return (200, try Self.encode(self.grant()))
            case "/api/circles/circle/posts/post/comments": return (200, try Self.encode(["items": []]))
            default: throw URLError(.badURL)
            }
        }
    }
    static func encode(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
    static func body(_ request: URLRequest) throws -> [String: Any] {
        if let bytes = request.httpBody { return try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any]) }
        let stream = try XCTUnwrap(request.httpBodyStream); stream.open(); defer { stream.close() }
        var all = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }; all.append(contentsOf: buffer.prefix(count))
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: all) as? [String: Any])
    }
    func post() throws -> CirclePost { try JSONDecoder().decode(CirclePost.self, from: Self.encode(postJSON)) }
    func circle() throws -> TrainingCircle { try JSONDecoder().decode(TrainingCircle.self, from: Self.encode(circleJSON)) }
    func project() throws -> CloudProject {
        try JSONDecoder().decode(CloudProject.self, from: Self.encode(["id": "project", "ownerId": "alice", "title": "Practice", "state": "ready", "inputRevision": 2,
            "preparedMedia": ["profileVersion": "media-720p30-v1", "video": asset, "width": 720, "height": 480, "fps": 30, "duration": 2, "frameCount": 60, "previews": []]]))
    }
    func grant() -> [String: Any] {
        var item = asset
        item["url"] = "https://bwzxrvkxfubnmuieljoj.supabase.co/storage/v1/object/sign/private-media/\(asset["objectKey"]!)?token=fixture-capability"
        return ["expiresAt": ISO8601DateFormatter.fractional.string(from: Date().addingTimeInterval(grantLifetime)), "assets": ["video": item]]
    }
}

final class CommunityClientTests: XCTestCase {
    override func tearDown() { CommunityURLProtocol.handler = nil; super.tearDown() }

    @MainActor
    func testShareSendsOnlyProjectAndTrimmedIntentWithIdempotency() async throws {
        let fixture = try CommunityFixture()
        CommunityURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url?.path, "/api/circles/circle/posts")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "request-key-123456789")
            let body = try CommunityFixture.body(request)
            XCTAssertEqual(Set(body.keys), ["projectId", "skill", "note"])
            XCTAssertEqual(body["skill"] as? String, "Elastico"); XCTAssertEqual(body["note"] as? String, "Second touch?")
            return (201, try CommunityFixture.encode(fixture.postJSON))
        }
        _ = try await fixture.client.share(circle: "circle", project: fixture.project(), skill: " Elastico\n", note: " Second touch? ", previous: nil, idempotencyKey: "request-key-123456789")
    }

    @MainActor
    func testShareRejectsForeignProjectAndRetryFromAnotherAuthorBeforeRequest() async throws {
        let fixture = try CommunityFixture()
        CommunityURLProtocol.handler = { _ in XCTFail("Invalid share sent"); return (500, Data()) }
        fixture.credentials.currentSession = AccountSession(uid: "bob", generation: UUID())
        do { _ = try await fixture.client.share(circle: "circle", project: fixture.project(), skill: "Move", note: "", previous: nil, idempotencyKey: UUID().uuidString); XCTFail("Changed session accepted") }
        catch { XCTAssertEqual(error as? AccountAPIError, .sessionChanged) }
    }

    @MainActor
    func testLateResponseAfterAccountChangeIsDiscarded() async throws {
        let fixture = try CommunityFixture()
        CommunityURLProtocol.handler = { _ in
            fixture.credentials.currentSession = AccountSession(uid: "bob", generation: UUID())
            return (200, try CommunityFixture.encode(["items": [fixture.circleJSON]]))
        }
        do { _ = try await fixture.client.circles(); XCTFail("Late circle list accepted") }
        catch { XCTAssertEqual(error as? AccountAPIError, .sessionChanged) }
    }

    @MainActor
    func testCircleMustContainCurrentMemberAndOwner() async throws {
        let fixture = try CommunityFixture()
        fixture.circleJSON["members"] = [["uid": "bob", "displayName": "Bob", "joinedAt": "now"]]
        fixture.circleJSON["memberCount"] = 1
        do { _ = try await fixture.client.circles(); XCTFail("Nonmember accepted") }
        catch { XCTAssertTrue(error is CommunityError) }
    }

    @MainActor
    func testSharedVideoRejectsForeignBucketAuthorPathAndMalformedPreparedKey() throws {
        let fixture = try CommunityFixture()
        try fixture.post().validate(circle: "circle")
        let paths = ["users/bob/projects/project/media/\(String(repeating: "a", count: 64))/1/video.mp4",
            "users/alice/projects/other/media/\(String(repeating: "a", count: 64))/1/video.mp4",
            "users/alice/projects/project/media/hash/1/video.mp4",
            "users/alice/projects/project/media/\(String(repeating: "a", count: 64))/6/video.mp4",
            "users/alice/projects/project/media/\(String(repeating: "a", count: 64))/1/../video.mp4"]
        for path in paths {
            var asset = fixture.asset; asset["objectKey"] = path
            var video = fixture.video; video["asset"] = asset
            fixture.postJSON["video"] = video
            XCTAssertThrowsError(try fixture.post().validate(circle: "circle"))
        }
        var asset = fixture.asset; asset["bucket"] = "public-media"
        var video = fixture.video; video["asset"] = asset; fixture.postJSON["video"] = video
        XCTAssertThrowsError(try fixture.post().validate(circle: "circle"))
    }

    @MainActor
    func testPostRefreshPinsIdentityAndVideoMetadata() throws {
        let fixture = try CommunityFixture(), pinned = try fixture.post()
        for (key, value) in [("id", "other"), ("circleId", "other"), ("authorId", "bob"), ("projectId", "other")] {
            var json = fixture.postJSON; json[key] = value
            let post = try JSONDecoder().decode(CirclePost.self, from: CommunityFixture.encode(json))
            XCTAssertThrowsError(try post.validate(circle: "circle", pinned: pinned))
        }
        var video = fixture.video; video["duration"] = 3; fixture.postJSON["video"] = video
        XCTAssertThrowsError(try fixture.post().validate(circle: "circle", pinned: pinned))
    }

    @MainActor
    func testSharedGrantIsShortLivedAndDownloadsWithoutBearer() async throws {
        let fixture = try CommunityFixture(), bytes = fixture.bytes
        let assets = try await fixture.client.playbackAssets(fixture.post()) { url, limit in
            XCTAssertEqual(url.host, "bwzxrvkxfubnmuieljoj.supabase.co"); XCTAssertEqual(limit, bytes.count)
            return bytes
        }
        defer { assets.close() }
        let file = try await assets.localFile(file: "video")
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        assets.close(); XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        fixture.grantLifetime = 300
        let long = try await fixture.client.playbackAssets(fixture.post()) { _, _ in XCTFail("Long grant downloaded"); return bytes }
        defer { long.close() }
        do { _ = try await long.localFile(file: "video"); XCTFail("Long grant accepted") }
        catch { XCTAssertEqual(error as? CloudPlaybackError, .invalidAsset) }
    }

    @MainActor
    func testSharedPlaybackRechecksMembershipAfterDownloadAndRejectsRevokedAccess() async throws {
        let fixture = try CommunityFixture(), post = try fixture.post(), bytes = fixture.bytes
        let original = try XCTUnwrap(CommunityURLProtocol.handler)
        CommunityURLProtocol.handler = { request in
            if request.url?.path == "/api/circles/circle/posts/post", fixture.postReads >= 2 { return (403, Data()) }
            return try await original(request)
        }
        let model = CirclePostViewModel(post: post, client: fixture.client, playbackTransport: { _, _ in bytes })
        let operation = Task { await model.watch() }
        defer { operation.cancel(); model.stop() }
        for _ in 0..<200 {
            if model.errorMessage != nil && !model.isLoading { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(model.playback); XCTAssertNotNil(model.errorMessage); XCTAssertFalse(model.hasAccess)
        XCTAssertEqual(fixture.postReads, 2)
    }

    @MainActor
    func testTimestampBoundariesAreValidatedBeforeAnyRequest() async throws {
        let fixture = try CommunityFixture(), post = try fixture.post()
        CommunityURLProtocol.handler = { _ in XCTFail("Invalid timestamp sent"); return (500, Data()) }
        for time in [-0.01, 2, 3, Double.nan, Double.infinity] {
            XCTAssertFalse(CommunityValidation.validTimestamp(time, duration: 2))
            do { _ = try await fixture.client.comment(post, text: "Feedback", timestamp: time, idempotencyKey: UUID().uuidString); XCTFail("Invalid timestamp accepted") }
            catch { XCTAssertTrue(error is CommunityError) }
        }
        XCTAssertTrue(CommunityValidation.validTimestamp(nil, duration: 2))
        XCTAssertTrue(CommunityValidation.validTimestamp(0, duration: 2))
        XCTAssertTrue(CommunityValidation.validTimestamp(1.9999, duration: 2))
    }

    @MainActor
    func testCommentContractAndExactTimestamp() async throws {
        let fixture = try CommunityFixture(), post = try fixture.post(), time = 1.0 / 30
        CommunityURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try CommunityFixture.body(request)
            XCTAssertEqual(Set(body.keys), ["text", "timestamp"])
            XCTAssertEqual(body["text"] as? String, "Try a softer touch")
            XCTAssertEqual(body["timestamp"] as? Double, time)
            return (201, try CommunityFixture.encode(["id": "comment", "authorId": "alice", "authorName": "Alice", "text": "Try a softer touch", "timestamp": time, "createdAt": "now"]))
        }
        let item = try await fixture.client.comment(post, text: " Try a softer touch ", timestamp: time, idempotencyKey: UUID().uuidString)
        XCTAssertEqual(item.timestamp, time)
    }

    @MainActor
    func testIdenticalShareRetryKeepsKeyAndEditedPayloadRotatesKey() async throws {
        let fixture = try CommunityFixture(), model = CircleShareViewModel(client: fixture.client, circleID: "circle", previous: nil)
        var keys: [String] = []
        CommunityURLProtocol.handler = { request in
            keys.append(try XCTUnwrap(request.value(forHTTPHeaderField: "Idempotency-Key")))
            return (409, Data())
        }
        _ = await model.share(project: try fixture.project(), skill: "Elastico", note: "First")
        _ = await model.share(project: try fixture.project(), skill: "Elastico", note: "First")
        _ = await model.share(project: try fixture.project(), skill: "Elastico", note: "Edited")
        XCTAssertEqual(keys.count, 3); XCTAssertEqual(keys[0], keys[1]); XCTAssertNotEqual(keys[1], keys[2])
        XCTAssertFalse(try XCTUnwrap(model.errorMessage).contains("upload"))
    }

    @MainActor
    func testTimestampSeekAndLogoutRemovePlayerAndVerifiedLocalFile() async throws {
        let fixture = try CommunityFixture(), post = try fixture.post(), bytes = fixture.bytes
        let model = CirclePostViewModel(post: post, client: fixture.client, playbackTransport: { _, _ in bytes })
        let operation = Task { await model.watch() }
        defer { operation.cancel(); model.stop() }
        for _ in 0..<300 {
            if model.playback != nil { break }; try await Task.sleep(for: .milliseconds(10))
        }
        let playback = try XCTUnwrap(model.playback)
        let file = try XCTUnwrap((playback.player.currentItem?.asset as? AVURLAsset)?.url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        playback.seek(to: 0.5); model.attachCurrentTime(); XCTAssertEqual(model.attachedTime, 0.5)
        let comment = CircleComment(id: "comment", authorId: "bob", authorName: "Bob", text: "Here", timestamp: 1.0 / 30, createdAt: "now")
        model.seek(comment: comment); XCTAssertEqual(playback.currentTime, 1.0 / 30, accuracy: 0.000001)
        fixture.credentials.currentSession = nil
        for _ in 0..<200 {
            if model.playback == nil { break }; try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(model.playback); XCTAssertFalse(model.hasAccess)
        XCTAssertTrue(model.comments.isEmpty); XCTAssertNil(model.attachedTime)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    @MainActor
    func testUnavailableFeatureIsTruthfulAndDoesNotFabricateCircle() async throws {
        let fixture = try CommunityFixture()
        CommunityURLProtocol.handler = { _ in (404, Data()) }
        do { _ = try await fixture.client.circles(); XCTFail("Missing backend accepted") }
        catch { XCTAssertEqual(error as? AccountAPIError, .notFound); XCTAssertTrue(CommunityValidation.message(error).contains("isn't available on this server yet")) }
    }

    @MainActor
    func testMalformedPreparedDurationIsRejectedBeforeRenderingChoices() async throws {
        let fixture = try CommunityFixture()
        CommunityURLProtocol.handler = { _ in
            return (200, try CommunityFixture.encode(["items": [["id": "project", "ownerId": "alice", "title": "Practice",
                "state": "ready", "inputRevision": 2, "preparedMedia": ["profileVersion": "media-720p30-v1",
                "video": fixture.asset, "width": 720, "height": 480, "fps": 30, "duration": 1e100,
                "frameCount": 60, "previews": []]]]]))
        }
        do { _ = try await fixture.client.preparedProjects(); XCTFail("Unsafe duration accepted") }
        catch { XCTAssertTrue(error is CommunityError) }
        XCTAssertEqual(CommunityValidation.timeLabel(1e100), "—")
        XCTAssertEqual(CommunityValidation.timeLabel(.infinity), "—")
    }

    @MainActor
    func testRemovedMemberClearsCachedCircleFeedAndInvitation() async throws {
        let fixture = try CommunityFixture()
        let model = CircleDetailViewModel(circle: try fixture.circle(), client: fixture.client)
        let original = try XCTUnwrap(CommunityURLProtocol.handler)
        var removed = false
        CommunityURLProtocol.handler = { request in
            if request.url?.path == "/api/circles/circle", removed { return (404, Data()) }
            if request.url?.path == "/api/circles/circle/posts" {
                return (200, try CommunityFixture.encode(["items": [fixture.postJSON]]))
            }
            return try await original(request)
        }
        await model.refresh()
        XCTAssertEqual(model.posts.count, 1)
        model.invite = CircleInvite(code: String(repeating: "a", count: 43), expiresAt: "2099-01-01T00:00:00Z")
        removed = true
        await model.refresh()
        XCTAssertTrue(model.posts.isEmpty); XCTAssertNil(model.invite)
        XCTAssertFalse(model.hasAccess); XCTAssertTrue(model.circle.members.isEmpty)
    }

    @MainActor
    func testStoppedCircleCannotPublishAnInFlightFeedResponse() async throws {
        let fixture = try CommunityFixture()
        let model = CircleDetailViewModel(circle: try fixture.circle(), client: fixture.client)
        let original = try XCTUnwrap(CommunityURLProtocol.handler)
        CommunityURLProtocol.handler = { request in
            if request.url?.path == "/api/circles/circle/posts" {
                model.stop()
                return (200, try CommunityFixture.encode(["items": [fixture.postJSON]]))
            }
            return try await original(request)
        }
        await model.refresh()
        XCTAssertTrue(model.posts.isEmpty); XCTAssertFalse(model.hasAccess)
        XCTAssertTrue(model.circle.members.isEmpty)
    }
}
