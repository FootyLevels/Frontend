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
    var resultJSON: [String: Any] = [:]
    var jobJSON: [String: Any] = [:]
    var motionFiles: [String: Data] = [:]
    var latestReconstructionID: String?
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
            case "/api/circles/circle/posts/post/motion-assets": return (200, try Self.encode(self.motionGrant()))
            case "/api/reconstructions/job": return (200, try Self.encode(self.resultJSON))
            case "/api/jobs/job": return (200, try Self.encode(self.jobJSON))
            case "/api/projects/project": return (200, try Self.encode(self.projectPayload()))
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
        try JSONDecoder().decode(CloudProject.self, from: Self.encode(projectPayload()))
    }
    func projectPayload() -> [String: Any] {
        var value: [String: Any] = ["id": "project", "ownerId": "alice", "title": "Practice", "state": "ready", "inputRevision": 2,
            "preparedMedia": ["profileVersion": "media-720p30-v1", "video": asset, "width": 720, "height": 480, "fps": 30, "duration": 2, "frameCount": 60, "previews": []]]
        if let latestReconstructionID { value["latestReconstructionId"] = latestReconstructionID }
        return value
    }
    func grant() -> [String: Any] {
        var item = asset
        item["url"] = "https://bwzxrvkxfubnmuieljoj.supabase.co/storage/v1/object/sign/private-media/\(asset["objectKey"]!)?token=fixture-capability"
        return ["expiresAt": ISO8601DateFormatter.fractional.string(from: Date().addingTimeInterval(grantLifetime)), "assets": ["video": item]]
    }

    func installMotion() throws {
        let topology = Data([0,0,0,0,1,0,0,0,2,0,0,0])
        let chunk = Data(base64Encoded: "H4sIAAAAAAAC/2NgAIH//xlQ6FGRUREGBgB/tHf3HAIAAA==")!
        motionFiles = ["faces.bin": topology, "body-000000.bin.gz": chunk, "video.mp4": bytes]
        let digest = SHA256.hash(data: topology).map { String(format: "%02x", $0) }.joined()
        let contract: [String: Any] = ["schemaVersion": 1, "topologyVersion": "mhr-\(digest.prefix(24))-v1",
            "coordinateSystem": "rightHandedYUp", "units": "meters", "encoding": "motionBuffers"]
        let engine: [String: Any] = ["modelName": "fixture", "upstreamCommit": String(repeating: "c", count: 40),
            "checkpointHash": String(repeating: "d", count: 64), "configHash": String(repeating: "e", count: 64)]
        jobJSON = ["id": "job", "ownerId": "alice", "projectId": "project", "kind": "reconstructMotion", "inputRevision": 2,
            "profileVersion": "body-motion-30fps-v1", "inputHash": String(repeating: "b", count: 64), "sourceAsset": asset,
            "motionSegment": ["startFrame": 15, "endFrame": 45], "attemptCount": 1,
            "status": "partial", "stage": "partial", "reconstructionId": "job"]
        var frames: [[String: Any]] = []
        for index in 0..<30 {
            frames.append(["index": index, "time": Double(index)/30, "shot": 0, "valid": index != 7,
                "sourceFrameIndex": 15+index, "sourceTimestamp": Double(15+index)/30])
        }
        let metadata: [String: Any] = ["schemaVersion": 1, "version": 1, "profileVersion": "body-motion-30fps-v1",
            "jobId": "job", "attempt": 1, "inputRevision": 2, "inputHash": String(repeating: "b", count: 64),
            "sourceSha256": asset["sha256"]!, "sourceStartFrame": 15, "sourceEndFrame": 45,
            "sourceTimeOffset": 0.5, "playbackVideo": "video.mp4", "engine": engine, "contract": contract,
            "vertexCount": 3, "faceCount": 1, "frameCount": 30, "min": [0,0,0], "span": [1,1,1],
            "encoding": "uint16-le-xyz-gzip", "topologyFile": "faces.bin", "fps": 30, "duration": 1,
            "validBodyFrames": 29, "validBallFrames": 0, "ball": ["diameter": 0.22],
            "chunks": [["start": 0, "count": 30, "file": "body-000000.bin.gz", "bytes": chunk.count]],
            "frames": frames]
        motionFiles["sequence.json"] = try Self.encode(metadata)
        resultJSON = ["schemaVersion": 1, "id": "job", "ownerId": "alice", "projectId": "project", "jobId": "job", "inputRevision": 2,
            "profileVersion": "body-motion-30fps-v1", "sourceAsset": asset, "mode": "motion", "outcome": "partial",
            "engine": engine, "contract": contract, "requestedFrameCount": 30, "reconstructedFrameCount": 29,
            "missingFrameCount": 1, "artifacts": motionFiles.keys.sorted().map { motionAsset($0) }]
        postJSON["motion"] = ["reconstruction": resultJSON, "job": jobJSON]
        latestReconstructionID = "job"
    }
    func motionAsset(_ name: String) -> [String: Any] {
        let bytes = motionFiles[name]!
        return ["bucket": "private-media", "objectKey": "users/alice/projects/project/reconstruction/job/1/\(name)",
            "sha256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), "byteSize": bytes.count,
            "contentType": name == "sequence.json" ? "application/json" : name == "video.mp4" ? "video/mp4" : name.hasSuffix(".gz") ? "application/gzip" : "application/octet-stream"]
    }
    func motionGrant() -> [String: Any] {
        ["expiresAt": ISO8601DateFormatter.fractional.string(from: Date().addingTimeInterval(grantLifetime)),
         "assets": Dictionary(uniqueKeysWithValues: motionFiles.keys.map { name in
            var item = motionAsset(name)
            item["url"] = "https://bwzxrvkxfubnmuieljoj.supabase.co/storage/v1/object/sign/private-media/\(item["objectKey"]!)?token=fixture-capability"
            return (name, item)
         })]
    }
}

final class CommunityClientTests: XCTestCase {
    override func tearDown() { CommunityURLProtocol.handler = nil; super.tearDown() }

    @MainActor
    func testMotionShareSendsOnlyExplicitResultIDAndPinsReturnedMotion() async throws {
        let fixture = try CommunityFixture(); try fixture.installMotion()
        let chosen = try XCTUnwrap(fixture.post().motion)
        CommunityURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/circles/circle/posts")
            let body = try CommunityFixture.body(request)
            XCTAssertEqual(Set(body.keys), ["projectId", "skill", "note", "reconstructionId"])
            XCTAssertEqual(body["reconstructionId"] as? String, "job")
            return (201, try CommunityFixture.encode(fixture.postJSON))
        }
        let post = try await fixture.client.share(circle: "circle", project: fixture.project(), skill: "Elastico",
            note: "Second touch?", previous: nil, motion: chosen, idempotencyKey: UUID().uuidString)
        XCTAssertEqual(post.motion, chosen)
    }

    @MainActor
    func testVideoOnlyShareDoesNotImplicitlyConsentToAvailableMotion() async throws {
        let fixture = try CommunityFixture(); try fixture.installMotion()
        CommunityURLProtocol.handler = { request in
            XCTAssertNil(try CommunityFixture.body(request)["reconstructionId"])
            return (201, try CommunityFixture.encode(fixture.postJSON))
        }
        do {
            _ = try await fixture.client.share(circle: "circle", project: fixture.project(), skill: "Elastico",
                note: "", previous: nil, idempotencyKey: UUID().uuidString)
            XCTFail("Unrequested 3D attachment accepted")
        } catch { XCTAssertTrue(error is CommunityError) }
    }

    @MainActor
    func testMotionCandidateDefaultsToVideoOnlyAndClearsOnProjectChange() async throws {
        let fixture = try CommunityFixture(); try fixture.installMotion()
        let model = CircleShareViewModel(client: fixture.client, circleID: "circle", previous: nil)
        await model.selectProject(try fixture.project())
        XCTAssertEqual(model.motionCandidate?.reconstruction.id, "job")
        XCTAssertFalse(model.includeMotion)
        model.includeMotion = true
        await model.selectProject(nil)
        XCTAssertNil(model.motionCandidate); XCTAssertFalse(model.includeMotion)
    }

    @MainActor
    func testMotionDiscoveryFailureStillAllowsVideoOnlySharing() async throws {
        let fixture = try CommunityFixture(); try fixture.installMotion()
        let original = try XCTUnwrap(CommunityURLProtocol.handler)
        CommunityURLProtocol.handler = { request in
            if request.url?.path == "/api/reconstructions/job" { return (404, Data()) }
            if request.url?.path == "/api/circles/circle/posts" {
                XCTAssertNil(try CommunityFixture.body(request)["reconstructionId"])
                var post = fixture.postJSON; post.removeValue(forKey: "motion")
                return (201, try CommunityFixture.encode(post))
            }
            return try await original(request)
        }
        let model = CircleShareViewModel(client: fixture.client, circleID: "circle", previous: nil)
        await model.selectProject(try fixture.project())
        XCTAssertNil(model.motionCandidate); XCTAssertFalse(model.includeMotion); XCTAssertNotNil(model.motionMessage)
        let post = await model.share(project: try fixture.project(), skill: "Elastico", note: "")
        XCTAssertNotNil(post); XCTAssertNil(post?.motion)
    }

    @MainActor
    func testSharedMotionRejectsForeignSourceMixedAttemptAndUnlistedFiles() throws {
        let fixture = try CommunityFixture(); try fixture.installMotion()
        try fixture.post().validate(circle: "circle")
        let baselineResult = fixture.resultJSON, baselineJob = fixture.jobJSON
        for mutation in ["owner", "project", "source", "revision", "status", "segment", "attempt", "path", "extra", "missingChunk"] {
            var result = baselineResult, job = baselineJob
            if mutation == "owner" { result["ownerId"] = "bob" }
            if mutation == "project" { result["projectId"] = "other" }
            if mutation == "source" { var source = fixture.asset; source["sha256"] = String(repeating: "f", count: 64); result["sourceAsset"] = source }
            if mutation == "revision" { job["inputRevision"] = 3 }
            if mutation == "status" { job["status"] = "running" }
            if mutation == "segment" { job["motionSegment"] = ["startFrame": 40, "endFrame": 70] }
            if mutation == "attempt" { job["attemptCount"] = 2 }
            var artifacts = try XCTUnwrap(result["artifacts"] as? [[String: Any]])
            if mutation == "path" { artifacts[0]["objectKey"] = "users/bob/projects/project/reconstruction/job/1/faces.bin" }
            if mutation == "extra" { var extra = fixture.motionAsset("faces.bin"); extra["objectKey"] = "users/alice/projects/project/reconstruction/job/1/private.glb"; artifacts.append(extra) }
            if mutation == "missingChunk" { artifacts.removeAll { ($0["objectKey"] as? String)?.hasSuffix("body-000000.bin.gz") == true } }
            result["artifacts"] = artifacts
            fixture.postJSON["motion"] = ["reconstruction": result, "job": job]
            XCTAssertThrowsError(try fixture.post().validate(circle: "circle"), "Accepted \(mutation)")
        }
    }

    @MainActor
    func testRefreshRejectsMotionAddedRemovedOrChangedAfterConsent() throws {
        let fixture = try CommunityFixture()
        let videoOnly = try fixture.post()
        try fixture.installMotion()
        let motionPost = try fixture.post()
        XCTAssertThrowsError(try motionPost.validate(circle: "circle", pinned: videoOnly))
        XCTAssertThrowsError(try videoOnly.validate(circle: "circle", pinned: motionPost))
        var job = fixture.jobJSON; job["inputHash"] = String(repeating: "c", count: 64)
        fixture.postJSON["motion"] = ["reconstruction": fixture.resultJSON, "job": job]
        XCTAssertThrowsError(try fixture.post().validate(circle: "circle", pinned: motionPost))
    }

    @MainActor
    func testSharedMotionDownloadsVerifiedFilesWithShortGrantAndCleansOnClose() async throws {
        let fixture = try CommunityFixture(); try fixture.installMotion()
        let files = fixture.motionFiles, post = try fixture.post()
        let assets = try await fixture.client.motionAssets(post) { url, limit in
            let bytes = try XCTUnwrap(files[url.lastPathComponent]); XCTAssertEqual(limit, bytes.count); return bytes
        }
        let local = try await assets.localFile(file: "body-000000.bin.gz")
        XCTAssertEqual(try Data(contentsOf: local), files["body-000000.bin.gz"])
        assets.close(); XCTAssertFalse(FileManager.default.fileExists(atPath: local.path))
        fixture.grantLifetime = 300
        let long = try await fixture.client.motionAssets(post) { _, _ in XCTFail("Long grant downloaded"); return Data() }
        defer { long.close() }
        do { _ = try await long.data(file: "sequence.json"); XCTFail("Long motion grant accepted") }
        catch { XCTAssertEqual(error as? CloudPlaybackError, .invalidAsset) }
    }

    @MainActor
    func testMotionConsentChangesMutationKeyAndIdenticalRetryKeepsIt() async throws {
        let fixture = try CommunityFixture(); try fixture.installMotion()
        let model = CircleShareViewModel(client: fixture.client, circleID: "circle", previous: nil)
        await model.selectProject(try fixture.project())
        var keys: [String] = [], attachments: [String?] = []
        CommunityURLProtocol.handler = { request in
            keys.append(try XCTUnwrap(request.value(forHTTPHeaderField: "Idempotency-Key")))
            attachments.append(try CommunityFixture.body(request)["reconstructionId"] as? String)
            return (409, Data())
        }
        _ = await model.share(project: try fixture.project(), skill: "Elastico", note: "")
        model.includeMotion = true
        _ = await model.share(project: try fixture.project(), skill: "Elastico", note: "")
        _ = await model.share(project: try fixture.project(), skill: "Elastico", note: "")
        XCTAssertEqual(keys.count, 3); XCTAssertNotEqual(keys[0], keys[1]); XCTAssertEqual(keys[1], keys[2])
        XCTAssertNil(attachments[0]); XCTAssertEqual(attachments[1], "job"); XCTAssertEqual(attachments[2], "job")
    }

    @MainActor
    func testSharedMotionRechecksAccessAfterSceneLoadBeforeExposingIt() async throws {
        let fixture = try CommunityFixture(); try fixture.installMotion()
        let post = try fixture.post(), files = fixture.motionFiles, bytes = fixture.bytes
        let original = try XCTUnwrap(CommunityURLProtocol.handler)
        CommunityURLProtocol.handler = { request in
            if request.url?.path == "/api/circles/circle/posts/post", fixture.postReads >= 4 { return (403, Data()) }
            return try await original(request)
        }
        let model = CirclePostViewModel(post: post, client: fixture.client, playbackTransport: { url, _ in
            if url.path.contains("/media/") { return bytes }
            return try XCTUnwrap(files[url.lastPathComponent])
        })
        let operation = Task { await model.watch() }
        defer { operation.cancel(); model.stop() }
        for _ in 0..<300 { if model.playback != nil { break }; try await Task.sleep(for: .milliseconds(10)) }
        let playback = try XCTUnwrap(model.playback)
        let localVideo = try XCTUnwrap((playback.player.currentItem?.asset as? AVURLAsset)?.url)
        model.openMotion()
        for _ in 0..<500 { if !model.isLoadingMotion { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(model.motion); XCTAssertFalse(model.hasAccess); XCTAssertNil(model.playback)
        XCTAssertNotNil(model.errorMessage); XCTAssertEqual(fixture.postReads, 4)
        XCTAssertFalse(FileManager.default.fileExists(atPath: localVideo.path))
    }

    @MainActor
    func testSharedMotionUsesOriginalVideoTimeForFeedbackAndTeardown() async throws {
        let fixture = try CommunityFixture(); try fixture.installMotion()
        let post = try fixture.post(), files = fixture.motionFiles, bytes = fixture.bytes
        let model = CirclePostViewModel(post: post, client: fixture.client, playbackTransport: { url, _ in
            if url.path.contains("/media/") { return bytes }
            return try XCTUnwrap(files[url.lastPathComponent])
        })
        let operation = Task { await model.watch() }
        defer { operation.cancel(); model.stop() }
        for _ in 0..<300 { if model.playback != nil { break }; try await Task.sleep(for: .milliseconds(10)) }
        model.openMotion()
        for _ in 0..<500 { if !model.isLoadingMotion { break }; try await Task.sleep(for: .milliseconds(10)) }
        let motion = try XCTUnwrap(model.motion), playback = try XCTUnwrap(model.playback)
        XCTAssertEqual(motion.state, .ready)
        model.seekToMotion(); XCTAssertEqual(playback.currentTime, 0.5)
        model.attachCurrentTime(); XCTAssertEqual(model.attachedTime, 0.5)
        let comment = CircleComment(id: "comment", authorId: "bob", authorName: "Bob", text: "Second touch", timestamp: 1, createdAt: "now")
        model.seek(comment: comment); XCTAssertEqual(playback.currentTime, 1)
        model.stop()
        XCTAssertNil(model.motion); XCTAssertNil(motion.stageRoot); XCTAssertNil(motion.sequence)
        XCTAssertEqual(motion.loadedChunks, 0); XCTAssertNil(model.playback)
    }

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
