import AVFoundation
import FirebaseAuth
import FirebaseCore
import Foundation
import XCTest
@testable import FootyLevels_Frontend

/// Explicit Development-only service/player proof. Never substitutes for a
/// named physical iPhone or interactive Google consent. The operator may select
/// either the private SSH forward or the approved Development HTTPS endpoint.
final class LivePrivatePlaybackTests: XCTestCase {
    @MainActor
    func testRealUploadDGXMotionAndPrivatePlayer() async throws {
        guard ProcessInfo.processInfo.environment["FOOTYLEVELS_LIVE_PLAYBACK_TESTS"] == "1" else {
            throw XCTSkip("Real GPU/cloud playback requires explicit opt-in")
        }
        guard FirebaseApp.app()?.options.projectID == "footylevels-dev-20261009",
              let text = ProcessInfo.processInfo.environment["FOOTYLEVELS_AUTH_TEST_API"],
              let url = URL(string: text),
              text == "http://127.0.0.1:8012" || text == "https://ranting-pesticide-thespian.ngrok-free.dev"
        else { throw AccountAPIError.unsafeAddress }
        let runID = UUID().uuidString.lowercased()
        let email = "fp40-ios-\(runID)@example.invalid"
        let password = UUID().uuidString + UUID().uuidString
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fp40-live-" + runID)
        let evidence = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("fp40-ios-evidence.json")
        var uid: String?, pid: String?, jobID: String?
        var phases: [String] = [], details: [String: Any] = [:]
        var accountsDeleted = false
        var motion: MotionPlayerViewModel?, playback: PlaybackController?
        var pose: PoseInspectorModel?, poseSource: PrivateKeyframeAssetSource?
        var preparedAssets: PrivatePlaybackAssets?, source: PrivateMotionAssetSource?
        var coordinator: CloudUploadCoordinator?
        func save(_ phase: String) throws {
            phases.append(phase)
            let body: [String: Any] = ["ticket": "FP-40", "environment": "dev", "runID": runID,
                "users": uid.map { [$0] } ?? [], "projects": pid.map { [$0] } ?? [],
                "jobs": jobID.map { [$0] } ?? [], "phases": phases, "details": details,
                "accountsDeleted": accountsDeleted, "physicalDeviceVerified": false,
                "publicAuthenticatedRouteVerified": url.scheme == "https" && phase.hasPrefix("passed-account-deleted-"),
                "interactiveGoogleLoginVerified": false]
            try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
                .write(to: evidence, options: .atomic)
        }
        func teardownLocal() {
            motion?.teardown(); playback?.teardown(); source?.close(); preparedAssets?.close()
            pose?.clear(); poseSource?.close()
            if let store = coordinator?.store, let drafts = try? store.load() {
                for draft in drafts { try? store.remove(draft) }
            }
            try? FileManager.default.removeItem(at: root)
        }
        func retireAccount() async throws {
            guard uid != nil else { return }
            // Refresh the SDK login before deleting an account after a long GPU wait.
            _ = try await Auth.auth().signIn(withEmail: email, password: password)
            let api = try AuthenticatedAPIClient(baseURL: url, credentials: FirebaseAPICredentials.shared)
            if let pid { _ = try await api.request("DELETE", path: "/api/projects/\(pid)") }
            try await Auth.auth().currentUser!.delete()
            try AuthManager.shared.signOut(); accountsDeleted = true
        }
        do {
            try AuthManager.shared.signOut()
            let account = try await Auth.auth().createUser(withEmail: email, password: password)
            uid = account.user.uid; try save("firebase-account-created")
            let api = try AuthenticatedAPIClient(baseURL: url, credentials: FirebaseAPICredentials.shared)
            _ = try await api.bootstrap()
            let uploads = try CloudUploadCoordinator(apiURL: url, environment: .dev,
                credentials: FirebaseAPICredentials.shared, root: root)
            coordinator = uploads
            let sample = try XCTUnwrap(BundledSample.project)
            let original = try XCTUnwrap(BundledSample.fileURL(forAssetPath: sample.video.url))
            let clip = root.appendingPathComponent("prepared.mp4")
            try await VideoClipPreparer.prepare(original, start: 0, end: 2, destination: clip)
            let fingerprint = try UploadDraftStore.fingerprint(clip)
            let draftID = UUID().uuidString.lowercased()
            var draft = UploadDraft(id: draftID, ownerId: account.user.uid, scope: uploads.store.scope,
                title: "FP40 iOS " + runID, label: "Practice", source: "gallery",
                byteSize: fingerprint.bytes, sha256: fingerprint.hash)
            try FileManager.default.createDirectory(at: uploads.store.directory(draftID), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: clip, to: uploads.store.file(draft))
            let body = try JSONSerialization.data(withJSONObject: ["title": draft.title, "label": "Practice", "source": "gallery"])
            let created = try JSONDecoder().decode(CloudProject.self,
                from: await api.request("POST", path: "/api/projects", body: body, idempotencyKey: draftID))
            pid = created.id; try save("owned-project-created")
            draft.projectId = created.id; try uploads.store.save(draft)
            let uploaded = try await uploads.upload(draft, progress: { _ in })
            XCTAssertEqual(uploaded.id, created.id); XCTAssertEqual(uploaded.state, "preparing")
            try save("real-private-upload-finalized")
            let client = try CloudReconstructionClient(apiURL: url, credentials: FirebaseAPICredentials.shared, environment: .dev)
            var project = try await client.project(created.id)
            let preparationDeadline = Date().addingTimeInterval(360)
            while project.state == "preparing", Date() < preparationDeadline {
                try await Task.sleep(for: .seconds(3)); project = try await client.project(created.id)
            }
            guard project.state == "ready", let media = project.preparedMedia else { throw CloudPlaybackError.invalidResult }
            let prepared = try client.preparedAssets(project: project); preparedAssets = prepared
            let preparedURL = try await prepared.localFile(file: "video")
            XCTAssertTrue(FileManager.default.fileExists(atPath: preparedURL.path))
            details["preparedFrames"] = media.frameCount; try save("prepared-private-video-verified")
            if ProcessInfo.processInfo.environment["FOOTYLEVELS_LIVE_PLAYBACK_KIND"] == "keyframes" {
                var job = try await client.generateKeyframes(project: project,selections: [
                    CloudKeyframeSelection(frameIndex: 0,bbox: [0,0,1,1]),
                    CloudKeyframeSelection(frameIndex: 15,bbox: [0,0,1,1])])
                jobID = job.id; details["mode"] = "keyframes"; try save("durable-keyframe-job-created")
                let deadline = Date().addingTimeInterval(600)
                while job.isActive, Date() < deadline {
                    try await Task.sleep(for: .seconds(4)); job = try await client.job(job.id,project: project)
                }
                details["jobStatus"] = job.status
                guard job.status == "succeeded", let rid = job.reconstructionId else { throw CloudPlaybackError.invalidResult }
                try save("real-dgx-keyframes-generated")
                project = try await client.project(project.id)
                let (result,winningJob,assets) = try await client.keyframeResult(rid,project: project)
                let source = PrivateKeyframeAssetSource(result: result,job: winningJob,assets: assets); poseSource = source
                let manifest = try await source.manifest()
                XCTAssertEqual(manifest.frames.map(\.frameIndex),[0,15]); XCTAssertEqual(manifest.frames.map(\.timestamp),[0,0.5])
                let model = PoseInspectorModel(); pose = model
                let controller = PlaybackController(url: preparedURL,duration: media.duration); playback = controller
                for frame in manifest.frames {
                    let decoded = try await source.mesh(frameIndex: frame.frameIndex)
                    let mesh = try XCTUnwrap(decoded)
                    XCTAssertEqual(mesh.positions.count,18_439); XCTAssertEqual(mesh.indices.count,36_874*3)
                    await model.showPrivate(frameIndex: frame.frameIndex,source: source)
                    XCTAssertNotNil(model.stageRoot?.findEntity(named: "body")); XCTAssertNil(model.errorMessage)
                    _ = await controller.player.seek(to: CMTime(value: Int64(frame.frameIndex),timescale: 30),
                        toleranceBefore: .zero,toleranceAfter: .zero)
                    XCTAssertEqual(controller.player.currentTime().seconds,frame.timestamp,accuracy: 1.0/60)
                    let generator = AVAssetImageGenerator(asset: controller.player.currentItem!.asset)
                    generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
                    let image = try await generator.image(at: CMTime(value: Int64(frame.frameIndex),timescale: 30))
                    XCTAssertEqual(image.actualTime.seconds,frame.timestamp,accuracy: 1.0/60)
                    generator.cancelAllCGImageGeneration()
                }
                model.show(.left); model.wireframe = true; model.autoRotate = true
                details["frames"] = manifest.frames.count; details["validFrames"] = manifest.frames.count
                details["vertices"] = 18_439; details["faces"] = 36_874; details["artifactCount"] = result.artifacts.count
                details["winningAttempt"] = winningJob.attemptCount; details["sourceTimes"] = manifest.frames.map(\.timestamp)
                try save("verified-private-glbs-pose-inspector-and-exact-source-images-ready")
                try AuthManager.shared.signOut()
                do { try source.checkSession(); XCTFail("Signed-out pose source remained usable") }
                catch { XCTAssertEqual(error as? AccountAPIError,.sessionChanged) }
                teardownLocal(); XCTAssertNil(model.stageRoot)
                XCTAssertFalse(FileManager.default.fileExists(atPath: preparedURL.path))
                try await retireAccount(); try save("passed-account-deleted-awaiting-exact-cloud-cleanup")
                return
            }
            var job = try await client.generateMotion(project: project, startFrame: 15, endFrame: 45)
            jobID = job.id; try save("durable-motion-job-created")
            let generationDeadline = Date().addingTimeInterval(900)
            while job.isActive, Date() < generationDeadline {
                try await Task.sleep(for: .seconds(4)); job = try await client.job(job.id, project: project)
            }
            details["jobStatus"] = job.status
            guard ["succeeded", "partial"].contains(job.status), let rid = job.reconstructionId else { throw CloudPlaybackError.invalidResult }
            try save("real-dgx-motion-generated")
            project = try await client.project(project.id)
            let (result, winningJob, assets) = try await client.motionResult(rid, project: project)
            let privateSource = PrivateMotionAssetSource(result: result, job: winningJob, assets: assets); source = privateSource
            let sequence = try await privateSource.sequence()
            XCTAssertEqual(sequence.frameCount, 30); XCTAssertEqual(sequence.vertexCount, 18_439)
            XCTAssertEqual(sequence.faceCount, 36_874); XCTAssertEqual(privateSource.sourceTimeOffset, 0.5)
            let localVideo = try await privateSource.videoURL()
            let controller = PlaybackController(url: localVideo, duration: sequence.duration); playback = controller
            let model = MotionPlayerViewModel(projectId: project.id, assets: privateSource, player: controller.player); motion = model
            await model.load()
            XCTAssertEqual(model.state, .ready); XCTAssertNotNil(model.stageRoot?.findEntity(named: "body"))
            guard model.state == .ready else { throw CloudPlaybackError.invalidResult }
            _ = await controller.player.seek(to: CMTime(value: 15, timescale: 30), toleranceBefore: .zero, toleranceAfter: .zero)
            for _ in 0..<100 where model.currentFrame != 15 { try await Task.sleep(for: .milliseconds(50)) }
            XCTAssertEqual(model.currentFrame, 15); XCTAssertEqual(model.sourceTime, 1, accuracy: 0.000001)
            model.show(.left); model.show(.source); model.wireframe = true; model.wireframe = false
            controller.speed = 1; XCTAssertEqual(controller.player.defaultRate, 1)
            details["frames"] = sequence.frameCount; details["validFrames"] = sequence.validBodyFrames
            details["vertices"] = sequence.vertexCount; details["faces"] = sequence.faceCount
            details["artifactCount"] = result.artifacts.count; details["winningAttempt"] = winningJob.attemptCount
            details["sourceTimeOffset"] = privateSource.sourceTimeOffset
            try save("verified-private-files-decoded-realitykit-player-ready-and-source-clock-checked")
            try AuthManager.shared.signOut()
            do { try privateSource.checkSession(); XCTFail("Signed-out private source remained usable") }
            catch { XCTAssertEqual(error as? AccountAPIError, .sessionChanged) }
            teardownLocal()
            XCTAssertFalse(FileManager.default.fileExists(atPath: localVideo.path))
            try await retireAccount(); try save("passed-account-deleted-awaiting-exact-cloud-cleanup")
        } catch {
            teardownLocal()
            try? await retireAccount(); try? save("failed-awaiting-exact-cloud-cleanup")
            // Do not print SDK errors, URLs, response bodies or capabilities.
            XCTFail("Real private playback failed; inspect the credential-free evidence phase")
        }
    }
}
