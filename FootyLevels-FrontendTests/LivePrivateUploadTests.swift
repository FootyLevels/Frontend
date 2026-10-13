import AVFoundation
import FirebaseAuth
import FirebaseCore
import Foundation
import XCTest
@testable import FootyLevels_Frontend

/// Explicit opt-in: two temporary Development accounts, real Firestore and
/// Supabase. Cleanup IDs contain no token; an operator removes exact records.
final class LivePrivateUploadTests: XCTestCase {
    @MainActor
    func testRealPrivateUploadsResumeAndRemainOwned() async throws {
        guard ProcessInfo.processInfo.environment["FOOTYLEVELS_LIVE_UPLOAD_TESTS"] == "1" else {
            throw XCTSkip("Real private uploads require explicit opt-in")
        }
        let configuredProject = FirebaseApp.app()?.options.projectID
        XCTAssertEqual(configuredProject, "footylevels-dev-20261009", "The live test must use Development Firebase")
        guard configuredProject == "footylevels-dev-20261009" else { throw AccountAPIError.unsafeAddress }
        let text = try XCTUnwrap(ProcessInfo.processInfo.environment["FOOTYLEVELS_AUTH_TEST_API"], "Missing loopback test API environment")
        let apiURL = try XCTUnwrap(URL(string: text), "Invalid loopback test API URL")
        XCTAssertEqual(apiURL.host, "127.0.0.1", "The live test must use the SSH loopback forward")
        guard apiURL.host == "127.0.0.1" else { throw AccountAPIError.unsafeAddress }
        let api = try AuthenticatedAPIClient(baseURL: apiURL, credentials: FirebaseAPICredentials.shared)
        let runID = UUID().uuidString.lowercased()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fp16-live-" + runID)
        let evidence = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("fp16-ios-evidence.json")
        var accounts: [(uid: String, email: String, password: String)] = []
        var pids: [String] = []
        var phases: [String] = []
        func save(_ phase: String) throws {
            phases.append(phase)
            try JSONSerialization.data(withJSONObject: ["runID": runID, "users": accounts.map(\.uid),
                "projects": pids, "phases": phases], options: .prettyPrinted).write(to: evidence, options: .atomic)
        }
        func cleanAccounts() async throws {
            for account in accounts {
                _ = try await Auth.auth().signIn(withEmail: account.email, password: account.password)
                try await Auth.auth().currentUser!.delete()
            }
            try AuthManager.shared.signOut()
        }
        do {
            try AuthManager.shared.signOut()
            let email = "fp16-ios-\(runID)-a@example.invalid"
            let password = UUID().uuidString + UUID().uuidString
            let first = try await Auth.auth().createUser(withEmail: email, password: password)
            accounts.append((first.user.uid, email, password))
            try save("first-account-created")
            _ = try await api.bootstrap()
            let coordinator = try CloudUploadCoordinator(apiURL: apiURL, environment: .dev,
                credentials: FirebaseAPICredentials.shared, root: root)
            let sample = try XCTUnwrap(BundledSample.project)
            let input = try XCTUnwrap(BundledSample.fileURL(forAssetPath: sample.video.url))
            let details = try await VideoClipPreparer.inspect(input)
            // Verify preparation: trim the sample, preserve a video track, remove audio.
            let prepared = root.appendingPathComponent("prepared.mp4")
            try await VideoClipPreparer.prepare(input, start: 0, end: min(3, details.duration), destination: prepared)
            let audioTracks = try await AVURLAsset(url: prepared).loadTracks(withMediaType: .audio)
            XCTAssertEqual(audioTracks.count, 0)
            let preparedDetails = try await VideoClipPreparer.inspect(prepared)
            XCTAssertLessThanOrEqual(preparedDetails.duration, 3.1)
            try save("trim-video-only-export-passed")
            // Pad a valid MP4 beyond one chunk to exercise real interruption and resume.
            let handle = try FileHandle(forWritingTo: prepared)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(repeating: 0, count: PrivateTUSClient.chunkSize + 101))
            try handle.close()
            let fingerprint = try UploadDraftStore.fingerprint(prepared)
            let draftID = UUID().uuidString.lowercased()
            var draft = UploadDraft(id: draftID, ownerId: first.user.uid, scope: coordinator.store.scope,
                title: "FP16 iOS " + runID, label: "Practice", source: "gallery", byteSize: fingerprint.bytes, sha256: fingerprint.hash)
            let dir = try coordinator.store.directory(draft.id)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: prepared, to: coordinator.store.file(draft))
            try coordinator.store.save(draft)
            let body = try JSONSerialization.data(withJSONObject: ["title": draft.title, "label": "Practice", "source": "gallery"])
            let created = try JSONDecoder().decode(CloudProject.self,
                from: await api.request("POST", path: "/api/projects", body: body, idempotencyKey: draftID))
            pids.append(created.id); try save("owned-project-created")
            let retry = try JSONDecoder().decode(CloudProject.self,
                from: await api.request("POST", path: "/api/projects", body: body, idempotencyKey: draftID))
            XCTAssertEqual(retry.id, created.id)
            draft.projectId = created.id
            let uploadBody = try JSONSerialization.data(withJSONObject: ["expectedRevision": 1, "byteSize": draft.byteSize,
                "sha256": draft.sha256, "contentType": "video/mp4"])
            let grant = try JSONDecoder().decode(PrivateUploadGrant.self,
                from: await api.request("POST", path: "/api/projects/\(created.id)/upload-session", body: uploadBody, idempotencyKey: draftID))
            draft.uploadId = grant.id
            try coordinator.store.save(draft)
            let storage = PrivateTUSClient(environment: .dev)
            let location = try await storage.create(grant, draft: draft, checkSession: coordinator.checkSession)
            try coordinator.store.setLocation(location, for: draft)
            var interrupt = false
            do {
                try await storage.transfer(file: coordinator.store.file(draft), at: location, grant: grant,
                    total: draft.byteSize, checkSession: {
                        try coordinator.checkSession()
                        if interrupt { throw CancellationError() }
                    }, progress: { value in if value > 0 && value < 1 { interrupt = true } })
                XCTFail("Transfer was not interrupted")
            } catch is CancellationError { /* First chunk confirmed; simulate app interruption. */ }
            XCTAssertTrue(interrupt)
            try save("first-chunk-interrupted")
            // New coordinator and store restore only private files/Keychain Location.
            let resumed = try CloudUploadCoordinator(apiURL: apiURL, environment: .dev,
                credentials: FirebaseAPICredentials.shared, root: root)
            let restored = try XCTUnwrap(resumed.store.load().first)
            let finished = try await resumed.upload(restored, progress: { _ in })
            XCTAssertEqual(finished.id, created.id)
            XCTAssertEqual(finished.state, "preparing")
            XCTAssertEqual(finished.inputRevision, 2)
            XCTAssertTrue(try resumed.store.load().isEmpty)
            try save("new-coordinator-resume-finalize-passed")
            // A second independent clip maps to a second owned project.
            let secondID = UUID().uuidString.lowercased()
            var second = draft
            second = UploadDraft(id: secondID, ownerId: first.user.uid, scope: resumed.store.scope,
                title: "FP16 second " + runID, label: nil, source: "capture", byteSize: draft.byteSize, sha256: draft.sha256)
            try FileManager.default.createDirectory(at: resumed.store.directory(secondID), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: prepared, to: resumed.store.file(second))
            try resumed.store.save(second)
            let another = try await resumed.upload(second, progress: { _ in })
            pids.append(another.id); try save("second-recording-uploaded")
            XCTAssertNotEqual(another.id, created.id)
            try AuthManager.shared.signOut()
            let otherEmail = "fp16-ios-\(runID)-b@example.invalid"
            let otherPassword = UUID().uuidString + UUID().uuidString
            let other = try await Auth.auth().createUser(withEmail: otherEmail, password: otherPassword)
            accounts.append((other.user.uid, otherEmail, otherPassword)); try save("second-account-created")
            _ = try await api.bootstrap()
            do { _ = try await resumed.list(); XCTFail("Stale coordinator accepted another account") }
            catch { XCTAssertEqual(error as? AccountAPIError, .sessionChanged) }
            do { _ = try await api.request("POST", path: "/api/projects/\(created.id)/assets"); XCTFail("Foreign assets readable") }
            catch { XCTAssertEqual(error as? AccountAPIError, .notFound) }
            try save("foreign-account-access-denied")
            _ = try await AuthManager.shared.loginWithEmail(email: email, password: password)
            let links = try await api.request("POST", path: "/api/projects/\(created.id)/assets")
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: links) as? [String: Any])
            let assets = try XCTUnwrap(object["assets"] as? [String: [String: Any]])
            let source = try XCTUnwrap(assets["source"])
            let url = try XCTUnwrap(URL(string: try XCTUnwrap(source["url"] as? String)))
            let (downloaded, response) = try await URLSession.shared.data(from: url)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            XCTAssertEqual(downloaded.count, draft.byteSize)
            // Signed URL stays in RAM; downloaded fixture is removed with root.
            let checked = root.appendingPathComponent("checked.mp4")
            try downloaded.write(to: checked)
            XCTAssertEqual(try UploadDraftStore.fingerprint(checked).hash, draft.sha256)
            for pid in pids { _ = try await api.request("DELETE", path: "/api/projects/\(pid)") }
            try save("signed-private-source-checksum-and-tombstone-passed")
            try await cleanAccounts()
            try save("passed-accounts-deleted-needs-exact-metadata-and-blob-cleanup")
            try FileManager.default.removeItem(at: root)
        } catch {
            try? await cleanAccounts()
            try? save("failed-needs-exact-metadata-and-blob-cleanup")
            throw error
        }
    }
}
