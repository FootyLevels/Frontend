import CryptoKit
import AVFoundation
import Foundation
import XCTest
@testable import FootyLevels_Frontend

private final class PlaybackURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@MainActor (URLRequest) async throws -> (Int, [String: String], Data))?
    private var operation: Task<Void, Never>?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let request = request
        operation = Task {
            do {
                let (status, headers, bytes) = try await Self.handler!(request)
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: bytes)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() { operation?.cancel() }
}

@MainActor
private final class PlaybackCredentials: APICredentials {
    var currentSession: AccountSession? = AccountSession(uid: "alice", generation: UUID())
    func token(for session: AccountSession, forceRefresh: Bool) async throws -> String { "fixture-firebase-token" }
    func invalidate(_ session: AccountSession) { currentSession = nil }
}

@MainActor
private final class PlaybackFixture {
    let credentials = PlaybackCredentials()
    var files: [String: Data]
    var metadata: [String: Any]
    var resultJSON: [String: Any]
    var projectJSON: [String: Any]
    var jobJSON: [String: Any]
    var grantRequests = 0
    let api: AuthenticatedAPIClient
    let client: CloudReconstructionClient
    static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func encode(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }

    init() throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [PlaybackURLProtocol.self]
        let session = URLSession(configuration: config)
        api = try AuthenticatedAPIClient(baseURL: URL(string: "https://api.example.test")!, credentials: credentials, session: session)
        client = try CloudReconstructionClient(apiURL: URL(string: "https://api.example.test")!, credentials: credentials,
            environment: .dev, apiSession: session)
        let topology = Data([0,0,0,0,1,0,0,0,2,0,0,0])
        let chunk = Data(base64Encoded: "H4sIAAAAAAAC/2NgAIH//xlQ6FGRUREGBgB/tHf3HAIAAA==")!
        files = ["faces.bin": topology, "body-0000.bin.gz": chunk, "video.mp4": Data("fixture-video".utf8)]
        let contract: [String: Any] = ["schemaVersion": 1, "topologyVersion": "mhr-\(Self.sha(topology).prefix(24))-v1",
            "coordinateSystem": "rightHandedYUp", "units": "meters", "encoding": "motionBuffers"]
        let engine: [String: Any] = ["modelName": "fixture", "upstreamCommit": String(repeating: "c", count: 40),
            "checkpointHash": String(repeating: "d", count: 64), "configHash": String(repeating: "e", count: 64)]
        let source: [String: Any] = ["bucket": "private-media", "objectKey": "users/alice/projects/project/media/\(String(repeating: "f", count: 64))/1/video.mp4",
            "sha256": String(repeating: "a", count: 64), "byteSize": 10, "contentType": "video/mp4"]
        projectJSON = ["id": "project", "ownerId": "alice", "title": "Practice", "state": "ready", "inputRevision": 2,
            "latestReconstructionId": "job", "preparedMedia": ["profileVersion": "media-720p30-v1", "video": source,
                "width": 720, "height": 480, "fps": 30, "duration": 2, "frameCount": 60, "previews": []]]
        jobJSON = ["id": "job", "ownerId": "alice", "projectId": "project", "kind": "reconstructMotion", "inputRevision": 2,
            "profileVersion": "body-motion-30fps-v1", "inputHash": String(repeating: "b", count: 64), "sourceAsset": source,
            "motionSegment": ["startFrame": 15, "endFrame": 45], "attemptCount": 2,
            "status": "partial", "stage": "partial", "reconstructionId": "job"]
        var frames: [[String: Any]] = []
        for i in 0..<30 {
            frames.append(["index": i, "time": Double(i)/30, "shot": 0, "valid": i != 7,
                "sourceFrameIndex": 15+i, "sourceTimestamp": Double(15+i)/30])
        }
        metadata = ["schemaVersion": 1, "version": 1, "profileVersion": "body-motion-30fps-v1", "jobId": "job", "attempt": 2,
            "inputRevision": 2, "inputHash": String(repeating: "b", count: 64), "sourceSha256": String(repeating: "a", count: 64),
            "sourceStartFrame": 15, "sourceEndFrame": 45, "sourceTimeOffset": 0.5, "playbackVideo": "video.mp4",
            "engine": engine, "contract": contract, "vertexCount": 3, "faceCount": 1, "frameCount": 30,
            "min": [0,0,0], "span": [1,1,1], "encoding": "uint16-le-xyz-gzip", "topologyFile": "faces.bin",
            "fps": 30, "duration": 1, "validBodyFrames": 29, "validBallFrames": 0, "ball": ["diameter": 0.22],
            "chunks": [["start": 0, "count": 30, "file": "body-0000.bin.gz", "bytes": chunk.count]],
            "frames": frames]
        resultJSON = ["schemaVersion": 1, "id": "job", "ownerId": "alice", "projectId": "project", "jobId": "job", "inputRevision": 2,
            "profileVersion": "body-motion-30fps-v1", "sourceAsset": source, "mode": "motion", "outcome": "partial",
            "engine": engine, "contract": contract, "requestedFrameCount": 30, "reconstructedFrameCount": 29, "missingFrameCount": 1]
        try rebuildArtifacts()
        PlaybackURLProtocol.handler = { [weak self] request in
            guard let self else { throw URLError(.cancelled) }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-firebase-token")
            switch request.url!.path {
            case "/api/reconstructions/job": return (200, [:], try Self.encode(self.resultJSON))
            case "/api/jobs/job": return (200, [:], try Self.encode(self.jobJSON))
            case "/api/reconstructions/job/assets":
                self.grantRequests += 1
                return (200, [:], try Self.encode(self.grantJSON(token: "capability-\(self.grantRequests)")))
            case "/api/projects/project": return (200, [:], try Self.encode(self.projectJSON))
            default: throw URLError(.badURL)
            }
        }
    }

    func rebuildArtifacts() throws {
        files["sequence.json"] = try Self.encode(metadata)
        resultJSON["artifacts"] = files.keys.sorted().map { name in asset(name) }
    }
    func asset(_ name: String) -> [String: Any] {
        let data = files[name]!
        return ["bucket": "private-media", "objectKey": "users/alice/projects/project/reconstruction/job/2/\(name)",
            "sha256": Self.sha(data), "byteSize": data.count,
            "contentType": name.hasSuffix(".json") ? "application/json" : name.hasSuffix(".glb") ? "model/gltf-binary" : name == "video.mp4" ? "video/mp4" : "application/octet-stream"]
    }
    func grantJSON(token: String = "fixture-capability") -> [String: Any] {
        ["expiresAt": ISO8601DateFormatter.fractional.string(from: Date().addingTimeInterval(300)),
         "assets": Dictionary(uniqueKeysWithValues: files.keys.map { name in
            var value = asset(name)
            value["url"] = "https://bwzxrvkxfubnmuieljoj.supabase.co/storage/v1/object/sign/private-media/\(value["objectKey"]!)?token=\(token)"
            return (name, value)
         })]
    }
    func project() throws -> CloudProject { try JSONDecoder().decode(CloudProject.self, from: Self.encode(projectJSON)) }
    func result() throws -> CloudReconstruction { try JSONDecoder().decode(CloudReconstruction.self, from: Self.encode(resultJSON)) }
    func job() throws -> CloudJob { try JSONDecoder().decode(CloudJob.self, from: Self.encode(jobJSON)) }
    func assets(transport: PrivatePlaybackAssets.Transport? = nil) throws -> PrivatePlaybackAssets {
        let mapping = Dictionary(uniqueKeysWithValues: try result().artifacts.map { ($0.objectKey.split(separator: "/").last!.description, $0) })
        let files = files
        return try PrivatePlaybackAssets(api: api, credentials: credentials, environment: .dev,
            grantPath: "/api/reconstructions/job/assets", artifacts: mapping,
            transport: transport ?? { url, _ in files[url.lastPathComponent]! })
    }
    func source() throws -> PrivateMotionAssetSource { try PrivateMotionAssetSource(result: result(), job: job(), assets: assets()) }

    static func glb(documentChange: (inout [String: Any]) -> Void = { _ in }, positions: [Float] = [0,0,0,1,0,0,0,1,0], indices: [UInt32] = [0,1,2]) throws -> Data {
        var bin = Data()
        for index in indices { var v = index.littleEndian; withUnsafeBytes(of: &v) { bin.append(contentsOf: $0) } }
        for point in positions { var v = point; withUnsafeBytes(of: &v) { bin.append(contentsOf: $0) } }
        var document: [String: Any] = ["asset": ["version": "2.0"], "buffers": [["byteLength": bin.count]],
            "nodes": [["children": [1]], ["mesh": 0]],
            "meshes": [["primitives": [["attributes": ["POSITION": 0], "indices": 1]]]],
            "bufferViews": [["buffer": 0, "byteOffset": indices.count*4, "byteLength": positions.count*4],
                ["buffer": 0, "byteOffset": 0, "byteLength": indices.count*4]],
            "accessors": [["bufferView": 0, "componentType": 5126, "count": positions.count/3, "type": "VEC3"],
                ["bufferView": 1, "componentType": 5125, "count": indices.count, "type": "SCALAR"]]]
        documentChange(&document)
        var json = try encode(document); while json.count%4 != 0 { json.append(0x20) }
        var data = Data("glTF".utf8)
        func u32(_ n: Int) { var v = UInt32(n).littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        u32(2); u32(12+8+json.count+8+bin.count); u32(json.count); u32(0x4E4F534A); data.append(json)
        u32(bin.count); u32(0x004E4942); data.append(bin); return data
    }

    func makeKeyframes() throws {
        files = ["frame-0000.glb": try Self.glb()]
        var contract = resultJSON["contract"] as! [String: Any]; contract["encoding"] = "glb"
        resultJSON["contract"] = contract; resultJSON["mode"] = "keyframes"
        resultJSON["profileVersion"] = "body-keyframes-v1"; resultJSON["requestedFrameCount"] = 2
        resultJSON["reconstructedFrameCount"] = 1
        jobJSON["kind"] = "reconstructKeyframes"; jobJSON["profileVersion"] = "body-keyframes-v1"
        jobJSON.removeValue(forKey: "motionSegment")
        jobJSON["keyframes"] = [["frameIndex": 0, "bbox": [0,0,1,1]], ["frameIndex": 5, "bbox": [0,0,1,1]]]
        metadata = ["schemaVersion": 1, "jobId": "job", "attempt": 2, "inputRevision": 2,
            "inputHash": jobJSON["inputHash"]!, "sourceSha256": String(repeating: "a",count: 64),
            "profileVersion": "body-keyframes-v1", "contract": contract, "engine": resultJSON["engine"]!,
            "frames": [["frameIndex": 0, "timestamp": 0, "bbox": [0,0,1,1], "artifact": "frame-0000.glb",
                "metadata": ["vertexCount": 3, "faceCount": 1]]], "missingFrameIndices": [5]]
        try rebuildKeyframes()
    }
    func rebuildKeyframes() throws {
        files["keyframes.json"] = try Self.encode(metadata)
        resultJSON["artifacts"] = files.keys.sorted().map { asset($0) }
    }
    func poseSource() throws -> PrivateKeyframeAssetSource {
        PrivateKeyframeAssetSource(result: try result(), job: try job(), assets: try assets())
    }
}

final class CloudPlaybackTests: XCTestCase {
    override func tearDown() { PlaybackURLProtocol.handler = nil; super.tearDown() }

    @MainActor
    func testPrivateKeyframeDrivesReusedPoseInspectorAndMissingFrameClearsPreviousMesh() async throws {
        let fixture = try PlaybackFixture(); try fixture.makeKeyframes()
        _ = try await fixture.client.keyframeResult("job", project: fixture.project())
        let source = try fixture.poseSource(), model = PoseInspectorModel()
        defer { model.clear(); source.close() }
        await model.showPrivate(frameIndex: 0, source: source)
        XCTAssertNotNil(model.stageRoot?.findEntity(named: "body")); XCTAssertNil(model.errorMessage)
        model.show(.left); model.wireframe = true; model.autoRotate = true
        await model.showPrivate(frameIndex: 5, source: source)
        XCTAssertTrue(model.missingPose); XCTAssertNil(model.stageRoot); XCTAssertNil(model.info)
        fixture.credentials.currentSession = nil
        await model.showPrivate(frameIndex: 0, source: source)
        XCTAssertNil(model.stageRoot); XCTAssertNotNil(model.errorMessage)
    }

    @MainActor
    func testKeyframeSubmissionHasOnlyOwnedRevisionAndSelectionsAndRejectsInvalidBoxes() async throws {
        let fixture = try PlaybackFixture(); try fixture.makeKeyframes()
        PlaybackURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path,"/api/projects/project/reconstructions/keyframes")
            let bytes: Data
            if let body = request.httpBody { bytes = body }
            else {
                let stream = try XCTUnwrap(request.httpBodyStream); stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0,count: 2048); let n = stream.read(&buffer,maxLength: buffer.count)
                bytes = Data(buffer.prefix(n))
            }
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            XCTAssertEqual(Set(body.keys),["inputRevision","keyframes"])
            XCTAssertEqual(body["inputRevision"] as? Int,2)
            return (202,[:],try PlaybackFixture.encode(fixture.jobJSON))
        }
        let selection = CloudKeyframeSelection(frameIndex: 0,bbox: [0,0,1,1])
        _ = try await fixture.client.generateKeyframes(project: fixture.project(),selections: [selection])
        for selections in [[],[selection,selection],[.init(frameIndex: 60,bbox: [0,0,1,1])],
                           [.init(frameIndex: 0,bbox: [0,0,0.01,1])],[.init(frameIndex: 0,bbox: [0,0,Double.nan,1])]] {
            do { _ = try await fixture.client.generateKeyframes(project: fixture.project(),selections: selections); XCTFail("Invalid selection submitted") }
            catch { XCTAssertEqual(error as? CloudPlaybackError,.invalidResult) }
        }
    }

    @MainActor
    func testKeyframeManifestRejectsChangedProvenanceTimesSelectionsAndMixedAttempts() async throws {
        for (key,value) in [("attempt",1 as Any),("inputRevision",3 as Any),("sourceSha256","wrong" as Any),
                            ("schemaVersion",2 as Any),("missingFrameIndices",[0] as Any)] {
            let fixture = try PlaybackFixture(); try fixture.makeKeyframes(); fixture.metadata[key] = value
            try fixture.rebuildKeyframes()
            do { _ = try await fixture.poseSource().manifest(); XCTFail("Invalid manifest accepted") } catch {}
        }
        for key in ["timestamp","bbox","artifact"] {
            let fixture = try PlaybackFixture(); try fixture.makeKeyframes()
            var frames = fixture.metadata["frames"] as! [[String: Any]]
            frames[0][key] = key == "timestamp" ? 0.1 as Any : key == "bbox" ? [0,0,0.5,1] as Any : "../frame.glb" as Any
            fixture.metadata["frames"] = frames; try fixture.rebuildKeyframes()
            do { _ = try await fixture.poseSource().manifest(); XCTFail("Changed frame accepted") } catch {}
        }
    }

    @MainActor
    func testPrivateGLBRejectsUnsafeAccessorLayoutsNonFiniteVerticesIndicesAndTransforms() throws {
        XCTAssertEqual(try GLBLoader.loadPrivate(PlaybackFixture.glb()).positions.count,3)
        let changes: [(inout [String: Any]) -> Void] = [
            { d in var a = d["accessors"] as! [[String: Any]]; a[0]["count"] = Int.max; d["accessors"] = a },
            { d in var a = d["accessors"] as! [[String: Any]]; a[0]["normalized"] = true; d["accessors"] = a },
            { d in var a = d["bufferViews"] as! [[String: Any]]; a[0]["byteOffset"] = -1; d["bufferViews"] = a },
            { d in var a = d["bufferViews"] as! [[String: Any]]; a[0]["byteStride"] = 0; d["bufferViews"] = a },
            { d in var a = d["bufferViews"] as! [[String: Any]]; a[0]["byteLength"] = 4; d["bufferViews"] = a },
            { $0["nodes"] = [["mesh": 0,"translation": [1,0,0]]] },
            { $0["buffers"] = [["byteLength": 48,"uri": "https://foreign.test/mesh.bin"]] }
        ]
        for change in changes { XCTAssertThrowsError(try GLBLoader.loadPrivate(PlaybackFixture.glb(documentChange: change))) }
        XCTAssertThrowsError(try GLBLoader.loadPrivate(PlaybackFixture.glb(positions: [0,0,0,1,0,0,0,Float.nan,0])))
        XCTAssertThrowsError(try GLBLoader.loadPrivate(PlaybackFixture.glb(indices: [0,1,99])))
        var tailed = try PlaybackFixture.glb(); tailed.append(0)
        XCTAssertThrowsError(try GLBLoader.loadPrivate(tailed))
    }

    @MainActor
    func testPrivateGLBContractAlsoDecodesExistingBundledBodyGeometry() throws {
        let sample = try XCTUnwrap(BundledSample.project)
        let path = try XCTUnwrap(sample.frames.first?.meshUrl)
        let url = try XCTUnwrap(BundledSample.fileURL(forAssetPath: path))
        let mesh = try GLBLoader.loadPrivate(Data(contentsOf: url))
        XCTAssertEqual(mesh.positions.count,18_439); XCTAssertEqual(mesh.indices.count,36_874*3)
    }

    @MainActor
    func testKeyframeGeometryMustMatchPinnedTopologyAndManifestCounts() async throws {
        let fixture = try PlaybackFixture(); try fixture.makeKeyframes()
        fixture.files["frame-0000.glb"] = try PlaybackFixture.glb(indices: [0,2,1]); try fixture.rebuildKeyframes()
        do { _ = try await fixture.poseSource().mesh(frameIndex: 0); XCTFail("Wrong topology accepted") }
        catch { XCTAssertEqual(error as? CloudPlaybackError,.corruptFile) }
    }

    @MainActor
    func testPrivateDecoderDrivesReusedPlayerAndHidesMissingOrSignedOutPoses() async throws {
        let fixture = try PlaybackFixture(), source = try fixture.source()
        let sample = try XCTUnwrap(BundledSample.project)
        let url = try XCTUnwrap(BundledSample.fileURL(forAssetPath: sample.video.url))
        let player = AVPlayer(url: url)
        let model = MotionPlayerViewModel(projectId: "project", assets: source, player: player)
        defer { model.teardown(); player.pause() }
        await model.load()
        XCTAssertEqual(model.state, .ready)
        let body = try XCTUnwrap(model.stageRoot?.findEntity(named: "body"))
        XCTAssertTrue(body.isEnabled)
        _ = await player.seek(to: CMTime(value: 7, timescale: 30), toleranceBefore: .zero, toleranceAfter: .zero)
        for _ in 0..<100 where model.currentFrame != 7 { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(model.currentFrame, 7); XCTAssertTrue(model.missingPose); XCTAssertFalse(body.isEnabled)
        XCTAssertEqual(model.sourceTime, 0.5 + 7.0/30, accuracy: 0.000001)
        fixture.credentials.currentSession = nil
        player.play()
        for _ in 0..<100 where model.stageRoot != nil { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertNil(model.stageRoot); XCTAssertNil(player.currentItem)
    }

    @MainActor
    func testMotionSubmissionSendsOnlyOwnedRevisionAndExactSegment() async throws {
        let fixture = try PlaybackFixture()
        PlaybackURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/projects/project/reconstructions/motion")
            XCTAssertEqual(request.httpMethod, "POST")
            let data: Data
            if let body = request.httpBody { data = body }
            else {
                let stream = try XCTUnwrap(request.httpBodyStream); stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 2048)
                let count = stream.read(&buffer, maxLength: buffer.count)
                data = Data(buffer.prefix(count))
            }
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(Set(body.keys), ["inputRevision", "segment"])
            XCTAssertEqual(body["inputRevision"] as? Int, 2)
            XCTAssertEqual(body["segment"] as? [String: Int], ["startFrame": 15, "endFrame": 45])
            return (202, [:], try PlaybackFixture.encode(fixture.jobJSON))
        }
        let job = try await fixture.client.generateMotion(project: fixture.project(), startFrame: 15, endFrame: 45)
        XCTAssertEqual(job.id, "job")
        do { _ = try await fixture.client.generateMotion(project: fixture.project(), startFrame: 15, endFrame: 16); XCTFail("Accepted too-short clip") }
        catch { XCTAssertEqual(error as? CloudPlaybackError, .invalidResult) }
    }

    @MainActor
    func testPrivatePartialSequencePreservesOriginalTimesAndMissingPose() async throws {
        let fixture = try PlaybackFixture()
        let (result, job, assets) = try await fixture.client.motionResult("job", project: fixture.project())
        assets.close()
        let source = try fixture.source(); defer { source.close() }
        let value = try await source.sequence()
        XCTAssertEqual(result.missingFrameCount, 1); XCTAssertEqual(job.attemptCount, 2)
        XCTAssertEqual(source.sourceTimeOffset, 0.5); XCTAssertFalse(value.frames[7].valid)
        XCTAssertEqual(value.frames[29].time, 29.0/30, accuracy: 0.000001)
        let compressed = try await source.data(file: "body-0000.bin.gz")
        XCTAssertEqual(try Gzip.decompress(compressed, expectedByteCount: 540).count, 540)
    }

    @MainActor
    func testForeignOwnerStaleSourceAndUnknownContractFailBeforeAssetGrant() async throws {
        for mutation in ["owner", "source", "version", "attempt"] {
            let fixture = try PlaybackFixture()
            if mutation == "owner" { fixture.resultJSON["ownerId"] = "bob" }
            if mutation == "source" { fixture.resultJSON["inputRevision"] = 3 }
            if mutation == "version" { var c = fixture.resultJSON["contract"] as! [String: Any]; c["schemaVersion"] = 2; fixture.resultJSON["contract"] = c }
            if mutation == "attempt" { fixture.jobJSON["motionSegment"] = ["startFrame": 45, "endFrame": 75] }
            do { let (_, _, assets) = try await fixture.client.motionResult("job", project: fixture.project()); assets.close(); XCTFail("Accepted \(mutation)") }
            catch { XCTAssertTrue(error is CloudPlaybackError) }
            XCTAssertEqual(fixture.grantRequests, 0)
        }
    }

    @MainActor
    func testManifestGapsBadSourceTimesAndUnknownPackingFail() async throws {
        for mutation in ["gap", "time", "version", "offset", "provenance", "bad-bounds", "overflow-bounds"] {
            let fixture = try PlaybackFixture()
            if mutation == "gap" { fixture.metadata["chunks"] = [["start": 1, "count": 29, "file": "body-0000.bin.gz", "bytes": fixture.files["body-0000.bin.gz"]!.count]] }
            if mutation == "time" { var frames = fixture.metadata["frames"] as! [[String: Any]]; frames[3]["sourceTimestamp"] = 0; fixture.metadata["frames"] = frames }
            if mutation == "version" { fixture.metadata["version"] = 99 }
            if mutation == "offset" { fixture.metadata["sourceTimeOffset"] = 10 }
            if mutation == "provenance" { fixture.metadata["inputHash"] = String(repeating: "f", count: 64) }
            if mutation == "bad-bounds" { fixture.metadata["min"] = [0, 0] }
            if mutation == "overflow-bounds" { fixture.metadata["span"] = [Double(1e38), 1, 1] }
            try fixture.rebuildArtifacts()
            let source = try fixture.source(); defer { source.close() }
            do { _ = try await source.sequence(); XCTFail("Accepted \(mutation)") } catch { XCTAssertTrue(error is CloudPlaybackError) }
        }
    }

    @MainActor
    func testInvalidTopologyIndexAndHashFail() async throws {
        for invalid in ["index", "hash"] {
            let fixture = try PlaybackFixture()
            if invalid == "index" { fixture.files["faces.bin"] = Data([0,0,0,0,1,0,0,0,3,0,0,0]) }
            else { var c = fixture.resultJSON["contract"] as! [String: Any]; c["topologyVersion"] = "mhr-wrong-v1"; fixture.resultJSON["contract"] = c; fixture.metadata["contract"] = c }
            try fixture.rebuildArtifacts()
            let source = try fixture.source(); defer { source.close() }
            do { _ = try await source.sequence(); XCTFail("Accepted topology \(invalid)") } catch { XCTAssertEqual(error as? CloudPlaybackError, .corruptFile) }
        }
    }

    func testGzipRejectsCrcMismatchTruncationTrailingDataAndOversizedOutput() throws {
        let good = Data(base64Encoded: "H4sIAAAAAAAC/2NgAIH//xlQ6FGRUREGBgB/tHf3HAIAAA==")!
        XCTAssertEqual(try Gzip.decompress(good, expectedByteCount: 540).count, 540)
        var crc = good; crc[crc.count-8] ^= 1
        for bad in [crc, good.dropLast(), good + Data([0]), Data(repeating: 0, count: 540)] {
            XCTAssertThrowsError(try Gzip.decompress(Data(bad), expectedByteCount: 540))
        }
        XCTAssertThrowsError(try Gzip.decompress(good, expectedByteCount: 539))
        XCTAssertThrowsError(try Gzip.decompress(good, expectedByteCount: 541))
    }

    @MainActor
    func testWrongOriginObjectBucketCapabilityAndGrantMetadataRejected() throws {
        let fixture = try PlaybackFixture(), assets = try fixture.assets(); defer { assets.close() }
        let grant = fixture.grantJSON()
        XCTAssertNoThrow(try assets.validate(JSONDecoder().decode(PrivateReadGrant.self, from: PlaybackFixture.encode(grant))))
        for mutation in ["origin", "object", "bucket", "user", "no-token", "size", "hash"] {
            var value = grant, mapping = value["assets"] as! [String: [String: Any]], item = mapping["faces.bin"]!
            let original = item["url"] as! String
            if mutation == "origin" { item["url"] = original.replacingOccurrences(of: "bwzxrvkxfubnmuieljoj", with: "skzgjwbkadiazfvuhtts") }
            if mutation == "object" { item["url"] = original.replacingOccurrences(of: "/alice/", with: "/bob/") }
            if mutation == "bucket" { item["url"] = original.replacingOccurrences(of: "/private-media/", with: "/reference-assets/") }
            if mutation == "user" { item["url"] = original.replacingOccurrences(of: "https://", with: "https://user:password@") }
            if mutation == "no-token" { item["url"] = original.components(separatedBy: "?")[0] }
            if mutation == "size" { item["byteSize"] = 10 }
            if mutation == "hash" { item["sha256"] = String(repeating: "a", count: 64) }
            mapping["faces.bin"] = item; value["assets"] = mapping
            XCTAssertThrowsError(try assets.validate(JSONDecoder().decode(PrivateReadGrant.self, from: PlaybackFixture.encode(value))), mutation)
        }
    }

    @MainActor
    func testExpiredStorageResponseRefreshesGrantOnceAndCacheCannotCrossSession() async throws {
        let fixture = try PlaybackFixture()
        let files = fixture.files
        let assets = try fixture.assets { url, _ in
            if url.query!.contains("capability-1") { throw CloudPlaybackError.expired }
            return files[url.lastPathComponent]!
        }
        defer { assets.close() }
        let first = try await assets.data(file: "faces.bin")
        XCTAssertEqual(first, files["faces.bin"])
        XCTAssertEqual(fixture.grantRequests, 2)
        _ = try await assets.data(file: "faces.bin")
        XCTAssertEqual(fixture.grantRequests, 2)
        fixture.credentials.currentSession = AccountSession(uid: "alice", generation: UUID())
        do { _ = try await assets.data(file: "faces.bin"); XCTFail("Leaked prior-session cache") }
        catch { XCTAssertEqual(error as? AccountAPIError, .sessionChanged) }
    }

    @MainActor
    func testCorruptAndLateDownloadsNeverBecomeCachedOrLocalFiles() async throws {
        for mutation in ["hash", "size", "session"] {
            let fixture = try PlaybackFixture()
            let credentials = fixture.credentials, bytes = fixture.files["faces.bin"]!
            let assets = try fixture.assets { _, _ in
                if mutation == "session" { await MainActor.run { credentials.currentSession = nil } }
                if mutation == "size" { return bytes + Data([0]) }
                if mutation == "hash" { return Data(repeating: 9, count: bytes.count) }
                return bytes
            }
            defer { assets.close() }
            do { _ = try await assets.localFile(file: "faces.bin"); XCTFail("Accepted \(mutation)") }
            catch { XCTAssertTrue(error is CloudPlaybackError || error is AccountAPIError) }
        }
    }

    @MainActor
    func testBoundedTransportNeverSendsFirebaseCredentialsAndRejectsOversizedBytes() async throws {
        for advertisedLength in [nil, "1000"] as [String?] {
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [PlaybackURLProtocol.self]
            PlaybackURLProtocol.handler = { request in
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                XCTAssertNil(request.value(forHTTPHeaderField: "apikey"))
                return (200, advertisedLength.map { ["Content-Length": $0] } ?? [:], Data(repeating: 0, count: 1000))
            }
            do { _ = try await BoundedPlaybackDownload(limit: 16, configuration: config).get(URL(string: "https://storage.example.test/fixture")!); XCTFail("Unbounded download") }
            catch { XCTAssertEqual(error as? CloudPlaybackError, .corruptFile) }
        }
    }
}
