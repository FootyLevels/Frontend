import Foundation
import RealityKit
import simd

/// The geometry behind the overlay: where a body's center of mass is, how far
/// one body must turn to face like the other, and the transform that puts the
/// second body on the first.
///
/// Everything here works in the backend's motion space — Y-up metres — so
/// "turning" is always about the vertical axis.
enum OverlayAlignment {

    /// Center of mass of a closed triangle mesh at uniform density: its volume
    /// centroid.
    ///
    /// The plain vertex average would be pulled toward finely modelled parts
    /// such as the face and hands, so each triangle instead contributes the
    /// signed tetrahedron it forms with a reference point. A mesh with no
    /// volume (open or flat) falls back to the area-weighted surface centroid,
    /// then to the vertex average.
    ///
    /// Written against raw buffers because it runs for each body every frame.
    static func centerOfMass(positions: UnsafeBufferPointer<SIMD3<Float>>,
                             indices: UnsafeBufferPointer<UInt32>) -> SIMD3<Float> {
        guard let origin = positions.first else { return .zero }

        var volume: Float = 0            // 6 × the signed volume
        var weighted = SIMD3<Float>.zero // Σ 6V × 4 × tetra centroid, relative to origin
        var area: Float = 0              // 2 × the surface area
        var surface = SIMD3<Float>.zero  // Σ 2A × 3 × triangle centroid, relative to origin

        var t = 0
        while t + 2 < indices.count {
            let ia = Int(indices[t]), ib = Int(indices[t + 1]), ic = Int(indices[t + 2])
            t += 3
            guard ia < positions.count, ib < positions.count, ic < positions.count else { continue }
            let a = positions[ia] - origin, b = positions[ib] - origin, c = positions[ic] - origin
            let sum = a + b + c

            let v = simd_dot(a, simd_cross(b, c))
            volume += v
            weighted += v * sum

            let s = simd_length(simd_cross(b - a, c - a))
            area += s
            surface += s * sum
        }

        if abs(volume) > 1e-9 { return origin + weighted / (4 * volume) }
        if area > 1e-12 { return origin + surface / (3 * area) }

        var mean = SIMD3<Float>.zero
        for point in positions { mean += point }
        return mean / Float(positions.count)
    }

    static func centerOfMass(positions: [SIMD3<Float>], indices: [UInt32]) -> SIMD3<Float> {
        positions.withUnsafeBufferPointer { p in
            indices.withUnsafeBufferPointer { i in centerOfMass(positions: p, indices: i) }
        }
    }

    /// The turn about the vertical axis, in radians, that best lines `moving`
    /// up with `fixed`: a yaw-only Procrustes fit.
    ///
    /// Both bodies come from the same SAM 3D Body model, so vertex `i` is the
    /// same point on both people. Each is measured from its own center, so
    /// where they stand doesn't matter — only which way they face. Nil when
    /// the meshes don't correspond.
    static func facingYaw(aligning moving: [SIMD3<Float>], about movingCenter: SIMD3<Float>,
                          to fixed: [SIMD3<Float>], about fixedCenter: SIMD3<Float>) -> Float? {
        guard !moving.isEmpty, moving.count == fixed.count else { return nil }
        var dot: Float = 0
        var cross: Float = 0
        for i in moving.indices {
            let q = moving[i] - movingCenter
            let p = fixed[i] - fixedCenter
            dot += p.x * q.x + p.z * q.z
            cross += p.x * q.z - p.z * q.x
        }
        guard dot != 0 || cross != 0 else { return nil }
        return atan2(cross, dot)
    }

    /// Places a body so its point `center` lands on `target`, turned by `yaw`
    /// radians about the vertical axis through that point.
    static func transform(moving center: SIMD3<Float>, onto target: SIMD3<Float>, yaw: Float) -> Transform {
        let rotation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        return Transform(scale: .one, rotation: rotation, translation: target - rotation.act(center))
    }
}

// MARK: - Time

extension MotionSequence {
    /// The pose to show at a moment in the clip: a frame, the next one, and
    /// how far to blend between them.
    struct Sample: Equatable {
        let index: Int
        let next: Int
        let blend: Float
    }

    /// Maps `seconds` into the clip. Times before the start or past the end
    /// hold the first or last frame, so a shorter clip waits rather than
    /// vanishing. Never blends across a camera cut or into a missing pose.
    func sample(at seconds: Double) -> Sample? {
        guard frameCount > 0, fps > 0 else { return nil }
        let time = seconds.isFinite ? seconds : 0
        let position = Swift.min(Double(frameCount - 1), Swift.max(0, time * fps + 1e-4))
        let index = Int(position)
        let next = Swift.min(index + 1, frameCount - 1)
        guard frames.indices.contains(index), frames.indices.contains(next) else { return nil }
        let a = frames[index], b = frames[next]
        let blend = a.shot == b.shot && a.valid && b.valid ? Float(position - Double(index)) : 0
        return Sample(index: index, next: next, blend: blend)
    }
}
