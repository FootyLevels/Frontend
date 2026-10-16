import Foundation
import RealityKit
import Testing
@testable import FootyLevels_Frontend

/// The Overlay tab: when a comparison can open, and that opening one really
/// builds both bodies — overlaid in one aligned scene, or side by side.
@MainActor
struct OverlayModelsTests {

    private func project(id: String = "a1b2c3d4", motion: [String: Any]? = nil) throws -> SkillLabProject {
        var json: [String: Any] = [
            "id": id, "title": "Clip", "createdAt": "2026-10-13T12:00:00+00:00",
            "video": ["width": 720, "height": 1280, "fps": 30.0, "duration": 4.0,
                      "frameCount": 120, "url": "/assets-data/\(id)/video.mp4"],
            "frames": [],
        ]
        if let motion { json["motion"] = motion }
        return try JSONDecoder().decode(SkillLabProject.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private var playable: [String: Any] {
        ["status": "complete", "sequenceUrl": "/assets-data/a1b2c3d4/motion/sequence.json"]
    }

    // MARK: - Choosing

    @Test func comparingNeedsBothSlotsWithMotion() throws {
        let model = OverlayDifferenceViewModel()
        #expect(!model.canCompare)

        model.choose(try project(motion: playable), for: .first)
        #expect(!model.canCompare)

        model.choose(try project(id: "e5f6a7b8"), for: .second)
        #expect(!model.canCompare)   // B has no motion yet

        model.choose(try project(id: "e5f6a7b8", motion: playable), for: .second)
        #expect(model.canCompare)
    }

    @Test func theSameVideoCanFillBothSlots() throws {
        let sample = try #require(BundledSample.project)
        let model = OverlayDifferenceViewModel()
        model.choose(sample, for: .first)
        model.choose(sample, for: .second)
        #expect(model.canCompare)
    }

    @Test func buildingMotionIsOfferedOnlyWhenItCanStart() throws {
        let model = OverlayDifferenceViewModel()
        #expect(model.canBuildMotion(try project()))
        #expect(model.canBuildMotion(try project(motion: ["status": "failed"])))

        #expect(!model.canBuildMotion(try project(motion: playable)))
        #expect(!model.canBuildMotion(try project(motion: ["status": "running"])))
        #expect(!model.canBuildMotion(try #require(BundledSample.project)))

        model.startingId = "another-project"
        #expect(!model.canBuildMotion(try project()))
    }

    @Test func pollingRestartsWhenABuildStarts() throws {
        let model = OverlayDifferenceViewModel()
        model.choose(try project(), for: .first)
        let idle = model.pollKey
        model.choose(try project(motion: ["status": "queued"]), for: .first)
        #expect(model.pollKey != idle)
    }

    // MARK: - Comparing

    /// The included example against itself needs no server: both bodies load,
    /// and identical poses line up exactly.
    @Test func identicalClipsOverlayExactly() async throws {
        let sample = try #require(BundledSample.project)
        let model = try ComparisonModel(first: sample, second: sample)
        defer { model.teardown() }

        await model.load()
        #expect(model.state == .ready)

        let root = try #require(model.overlayRoot)
        let first = try #require(root.findEntity(named: "overlay-first"))
        let second = try #require(root.findEntity(named: "overlay-second"))
        #expect(first.components[OpacityComponent.self] != nil)
        #expect(second.components[OpacityComponent.self] != nil)

        #expect(model.turn == 0)
        #expect(simd_length(second.transform.translation) < 1e-3)
    }

    @Test func shiftingBInTimeMovesItOntoAsCenter() async throws {
        let sample = try #require(BundledSample.project)
        let model = try ComparisonModel(first: sample, second: sample)
        defer { model.teardown() }
        await model.load()
        let second = try #require(model.overlayRoot?.findEntity(named: "overlay-second"))

        // 0.8 s on, the player has moved, so B needs moving onto A. (Still in
        // the first one-second chunk, which `load()` waits for; every frame of
        // the example has a pose.)
        model.offset = 0.8
        #expect(!model.secondMissing)
        #expect(simd_length(second.transform.translation) > 1e-3)

        // Unlocked, B stands where it was filmed.
        model.locksCenterOfMass = false
        #expect(simd_length(second.transform.translation) < 1e-3)
    }

    @Test func nudgingShiftsBByOneFrameWithinRange() async throws {
        let sample = try #require(BundledSample.project)
        let model = try ComparisonModel(first: sample, second: sample)
        defer { model.teardown() }
        await model.load()

        model.nudgeOffset(frames: 1)
        #expect(model.offset > 0 && model.offset < 0.05)

        model.offset = model.offsetRange.upperBound
        model.nudgeOffset(frames: 3)
        #expect(model.offset == model.offsetRange.upperBound)
    }

    // MARK: - Side by side

    private func opened() async throws -> ComparisonModel {
        let sample = try #require(BundledSample.project)
        let model = try ComparisonModel(first: sample, second: sample)
        await model.load()
        return model
    }

    @Test func sideBySideGivesEachBodyItsOwnSolidStage() async throws {
        let model = try await opened()
        defer { model.teardown() }

        await model.setLayout(.sideBySide)
        let first = try #require(model.firstRoot?.findEntity(named: "side-first"))
        let second = try #require(model.secondRoot?.findEntity(named: "side-second"))
        #expect(model.firstRoot?.findEntity(named: "side-second") == nil)
        #expect(first.isEnabled && second.isEnabled)
        #expect((first.components[OpacityComponent.self]?.opacity ?? 1) == 1)
        #expect((second.components[OpacityComponent.self]?.opacity ?? 1) == 1)

        // The overlay keeps its own see-through pair, so switching back reloads nothing.
        await model.setLayout(.overlay)
        let overlaid = try #require(model.overlayRoot?.findEntity(named: "overlay-second"))
        #expect((overlaid.components[OpacityComponent.self]?.opacity ?? 1) < 1)
    }

    @Test func sideBySideKeepsBInItsOwnPlace() async throws {
        let model = try await opened()
        defer { model.teardown() }
        let overlaid = try #require(model.overlayRoot?.findEntity(named: "overlay-second"))

        model.offset = 0.8
        #expect(simd_length(overlaid.transform.translation) > 1e-3)   // overlaid: moved onto A

        await model.setLayout(.sideBySide)
        let side = try #require(model.secondRoot?.findEntity(named: "side-second"))
        #expect(simd_length(side.transform.translation) < 1e-3)        // side by side: where it was filmed
    }

    @Test func linkedCamerasMoveTogether() async throws {
        let model = try await opened()
        defer { model.teardown() }
        await model.setLayout(.sideBySide)

        model.firstCamera.orbit(from: model.firstCamera.orientation, translation: CGSize(width: 120, height: 40))
        model.cameraMoved(model.firstCamera)
        #expect(model.secondCamera.orientation == model.firstCamera.orientation)

        model.linksCameras = false
        model.secondCamera.orbit(from: model.secondCamera.orientation, translation: CGSize(width: -200, height: 0))
        model.cameraMoved(model.secondCamera)
        #expect(model.secondCamera.orientation != model.firstCamera.orientation)

        // Relinking brings B's camera back in line with A's.
        model.linksCameras = true
        #expect(model.secondCamera.orientation == model.firstCamera.orientation)
    }

    @Test func matchingACameraKeepsItsOwnTarget() {
        let leader = OrbitCamera()
        leader.target = [1, 1, 1]
        leader.orbit(from: leader.orientation, translation: CGSize(width: 80, height: 30))
        leader.zoom(from: leader.currentDistance, magnification: 1.5)

        let follower = OrbitCamera()
        follower.target = [-3, 0.9, 2]
        follower.match(leader)

        #expect(follower.orientation == leader.orientation)
        #expect(follower.currentDistance == leader.currentDistance)
        #expect(follower.target == [-3, 0.9, 2])
    }
}
