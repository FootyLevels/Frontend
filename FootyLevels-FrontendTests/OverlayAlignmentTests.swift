import Foundation
import RealityKit
import Testing
@testable import FootyLevels_Frontend

/// The geometry the overlay relies on: center of mass, facing and placement,
/// plus how a moment in time maps to a pose.
struct OverlayAlignmentTests {

    // MARK: - Fixtures

    /// A closed unit cube, every face wound outward.
    private static let cubeCorners: [SIMD3<Float>] = [
        [0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0],
        [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1],
    ]
    private static let cubeSides: [UInt32] = [0, 2, 1, 0, 3, 2,   // z = 0
                                              4, 5, 6, 4, 6, 7,   // z = 1
                                              0, 1, 5, 0, 5, 4,   // y = 0
                                              0, 4, 7, 0, 7, 3,   // x = 0
                                              1, 2, 6, 1, 6, 5]   // x = 1
    private static let cubeTop: [UInt32] = [3, 7, 6, 3, 6, 2]     // y = 1

    private func expectClose(_ a: SIMD3<Float>, _ b: SIMD3<Float>, tolerance: Float = 1e-4,
                             sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(simd_length(a - b) < tolerance, "\(a) vs \(b)", sourceLocation: sourceLocation)
    }

    private func mean(_ points: [SIMD3<Float>]) -> SIMD3<Float> {
        points.reduce(.zero, +) / Float(points.count)
    }

    // MARK: - Center of mass

    @Test func centerOfMassOfAClosedMeshIsItsVolumeCenter() {
        let offset = SIMD3<Float>(2, -1, 3)
        let cube = Self.cubeCorners.map { $0 + offset }
        let center = OverlayAlignment.centerOfMass(positions: cube, indices: Self.cubeSides + Self.cubeTop)
        expectClose(center, offset + 0.5)
    }

    /// Why it isn't the vertex average: extra detail on one side of a body
    /// (faces, hands) would drag that toward it.
    @Test func denserVerticesOnOneSideDoNotPullTheCenter() {
        // The top face rebuilt as a fan around an extra vertex in its middle.
        let positions = Self.cubeCorners + [[0.5, 1, 0.5]]
        let fan: [UInt32] = [3, 7, 8, 7, 6, 8, 6, 2, 8, 2, 3, 8]
        let center = OverlayAlignment.centerOfMass(positions: positions, indices: Self.cubeSides + fan)

        #expect(mean(positions).y > 0.55)   // the naive average leans up
        expectClose(center, [0.5, 0.5, 0.5])
    }

    @Test func aFlatMeshFallsBackToItsSurfaceCenter() {
        let triangle: [SIMD3<Float>] = [[0, 0, 0], [3, 0, 0], [0, 3, 0]]
        expectClose(OverlayAlignment.centerOfMass(positions: triangle, indices: [0, 1, 2]), [1, 1, 0])
    }

    @Test func indicesPastTheVertexBufferAreIgnored() {
        let cube = Self.cubeCorners
        let center = OverlayAlignment.centerOfMass(positions: cube, indices: Self.cubeSides + Self.cubeTop + [0, 1, 99])
        expectClose(center, [0.5, 0.5, 0.5])
    }

    // MARK: - Facing

    @Test(arguments: [70, -135, 180] as [Float])
    func facingRecoversHowFarBIsTurned(degrees: Float) throws {
        // An asymmetric "body" so every turn is distinguishable.
        let fixed: [SIMD3<Float>] = [[0, 0, 0], [0.4, 0.1, 0.2], [-0.3, 1.2, 0.5], [0.2, 1.6, -0.4], [0.9, 0.7, 0.1]]
        let turn = degrees * .pi / 180
        // B faces `turn` away from A and stands somewhere else entirely.
        let undo = simd_quatf(angle: -turn, axis: [0, 1, 0])
        let moving = fixed.map { undo.act($0) + SIMD3(5, 0, -2) }

        let yaw = try #require(OverlayAlignment.facingYaw(aligning: moving, about: mean(moving),
                                                          to: fixed, about: mean(fixed)))
        let turned = moving.map { simd_quatf(angle: yaw, axis: [0, 1, 0]).act($0 - mean(moving)) }
        for (point, target) in zip(turned, fixed.map { $0 - mean(fixed) }) {
            expectClose(point, target)
        }
    }

    @Test func facingNeedsMatchingBodies() {
        #expect(OverlayAlignment.facingYaw(aligning: [[0, 0, 1]], about: .zero,
                                           to: [[0, 0, 1], [1, 0, 0]], about: .zero) == nil)
        #expect(OverlayAlignment.facingYaw(aligning: [], about: .zero, to: [], about: .zero) == nil)
    }

    // MARK: - Placement

    @Test func placementPutsBsCenterOnAsAndKeepsItsShape() {
        let center = SIMD3<Float>(1, 2, 3)
        let target = SIMD3<Float>(-1, 0.5, 4)
        let other = SIMD3<Float>(1.3, 2.9, 2.6)
        let transform = OverlayAlignment.transform(moving: center, onto: target, yaw: 0.8)

        func apply(_ point: SIMD3<Float>) -> SIMD3<Float> {
            let result = transform.matrix * SIMD4(point, 1)
            return SIMD3(result.x, result.y, result.z)
        }
        expectClose(apply(center), target)
        #expect(abs(simd_distance(apply(other), apply(center)) - simd_distance(other, center)) < 1e-5)
        // Turning is only about the vertical axis: heights relative to the center are unchanged.
        #expect(abs((apply(other) - target).y - (other - center).y) < 1e-5)
    }

    // MARK: - Time

    /// 10 fps; frames 0–1 are one shot, 2–3 another, and frame 3 has no pose.
    private func sequence() throws -> MotionSequence {
        let frames: [[String: Any]] = [
            ["index": 0, "time": 0.0, "shot": 0, "valid": true],
            ["index": 1, "time": 0.1, "shot": 0, "valid": true],
            ["index": 2, "time": 0.2, "shot": 1, "valid": true],
            ["index": 3, "time": 0.3, "shot": 1, "valid": false],
        ]
        let json: [String: Any] = [
            "vertexCount": 3, "faceCount": 1, "frameCount": 4, "min": [0, 0, 0], "span": [1, 1, 1],
            "topologyFile": "topology.bin", "encoding": "uint16-le-xyz-gzip",
            "chunks": [["start": 0, "count": 4, "file": "chunk-0.bin.gz", "bytes": 0]],
            "fps": 10.0, "duration": 0.4, "validBodyFrames": 3, "validBallFrames": 0,
            "ball": ["diameter": 0.22], "frames": frames,
        ]
        return try JSONDecoder().decode(MotionSequence.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func blendsBetweenFramesOfOneShot() throws {
        let sample = try #require(try sequence().sample(at: 0.05))
        #expect(sample.index == 0 && sample.next == 1)
        #expect(abs(sample.blend - 0.5) < 0.01)
    }

    @Test func neverBlendsAcrossACutOrIntoAMissingPose() throws {
        let sequence = try sequence()
        #expect(sequence.sample(at: 0.15)?.blend == 0)   // frame 1 → 2 crosses shots
        #expect(sequence.sample(at: 0.25)?.blend == 0)   // frame 3 has no pose
    }

    @Test func timesOutsideTheClipHoldItsEnds() throws {
        let sequence = try sequence()
        #expect(sequence.sample(at: -2) == .init(index: 0, next: 1, blend: 0))
        #expect(sequence.sample(at: 99) == .init(index: 3, next: 3, blend: 0))
        #expect(sequence.sample(at: .nan)?.index == 0)
    }

    @MainActor
    @Test func bsTimeIsAsShiftedAndHeldAtItsEnds() {
        #expect(ComparisonModel.secondTime(forFirst: 2, offset: 0.5, secondDuration: 3) == 2.5)
        #expect(ComparisonModel.secondTime(forFirst: 2, offset: 1.5, secondDuration: 3) == 3)
        #expect(ComparisonModel.secondTime(forFirst: 0.2, offset: -1, secondDuration: 3) == 0)
    }
}
