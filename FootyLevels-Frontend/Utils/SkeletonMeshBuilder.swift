import Foundation
import RealityKit

/// Builds RealityKit geometry from SAM 3D Body keypoints.
///
/// Every joint sphere — and every bone, once the API supplies a joint hierarchy —
/// is merged into a single `MeshResource`, so the whole skeleton draws in one
/// pass rather than as 70 separate entities.
struct SkeletonMeshBuilder {

    /// Converts the API's camera-space keypoints into RealityKit's space.
    ///
    /// The keypoints endpoint reports `space: "camera"`, which follows the
    /// computer-vision convention: +X right, +Y **down**, +Z into the scene.
    /// RealityKit is +Y up with +Z toward the viewer, so both axes flip.
    ///
    /// This is the most likely convention, not a verified one — check it against
    /// a known-good frame. If the body renders upside down or mirrored, flip the
    /// corresponding axis (`Pose3DView` exposes both as toggles for exactly this).
    struct Orientation: Equatable {
        var flipY: Bool = true
        var flipZ: Bool = true

        func apply(to point: SIMD3<Float>) -> SIMD3<Float> {
            SIMD3(point.x,
                  flipY ? -point.y : point.y,
                  flipZ ? -point.z : point.z)
        }
    }

    /// Radius of a joint marker, in normalised units (see `targetHeight`).
    var jointRadius: Float = 0.028
    /// Radius of a bone, in normalised units.
    var boneRadius: Float = 0.014
    /// Longitudinal subdivisions of each joint sphere and bone.
    var segments: Int = 10
    /// Latitudinal subdivisions of each joint sphere.
    var rings: Int = 8
    /// The skeleton is uniformly scaled so its tallest axis measures this much,
    /// which keeps framing predictable regardless of the subject's real height.
    var targetHeight: Float = 1.0
    var orientation = Orientation()

    // MARK: - Joint preparation

    /// Converts joints to RealityKit space, recentres them on the origin, and
    /// scales them to `targetHeight`.
    ///
    /// Recentring matters: the raw keypoints sit wherever the subject was
    /// relative to the camera, and orbit controls rotate about the origin — so
    /// without this the skeleton swings around a point off in space.
    func normalized(joints: [SIMD3<Float>]) -> [SIMD3<Float>] {
        let converted = joints.map { orientation.apply(to: $0) }
        guard let first = converted.first else { return [] }

        var lo = first
        var hi = first
        for point in converted {
            lo = simd_min(lo, point)
            hi = simd_max(hi, point)
        }

        let centre = (lo + hi) / 2
        let extent = hi - lo
        let largestAxis = max(extent.x, max(extent.y, extent.z))
        let scale = largestAxis > 1e-5 ? targetHeight / largestAxis : 1

        return converted.map { ($0 - centre) * scale }
    }

    // MARK: - Mesh generation

    /// Builds one mesh containing a sphere per joint plus a cylinder per bone.
    ///
    /// Pass joints that have already been through `normalized(joints:)` —
    /// `jointRadius` and `boneRadius` are sized for that normalised scale.
    func makeMesh(joints: [SIMD3<Float>], bones: [(Int, Int)] = []) throws -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for joint in joints {
            appendSphere(centre: joint,
                         radius: jointRadius,
                         positions: &positions,
                         normals: &normals,
                         indices: &indices)
        }

        for (parent, child) in bones {
            guard joints.indices.contains(parent), joints.indices.contains(child) else { continue }
            appendCylinder(from: joints[parent],
                           to: joints[child],
                           radius: boneRadius,
                           positions: &positions,
                           normals: &normals,
                           indices: &indices)
        }

        guard !positions.isEmpty else { throw SkeletonMeshError.noGeometry }

        var descriptor = MeshDescriptor(name: "skeleton")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)

        return try MeshResource.generate(from: [descriptor])
    }

    // MARK: - Primitive builders

    /// Appends a UV sphere. Winding is counter-clockwise when viewed from
    /// outside, so the faces survive default back-face culling.
    private func appendSphere(
        centre: SIMD3<Float>,
        radius: Float,
        positions: inout [SIMD3<Float>],
        normals: inout [SIMD3<Float>],
        indices: inout [UInt32]
    ) {
        let longitudes = max(3, segments)
        let latitudes = max(2, rings)
        let base = UInt32(positions.count)

        for ring in 0...latitudes {
            let theta = Float.pi * Float(ring) / Float(latitudes)
            let sinTheta = sin(theta)
            let cosTheta = cos(theta)

            for lon in 0...longitudes {
                let phi = 2 * Float.pi * Float(lon) / Float(longitudes)
                let normal = SIMD3<Float>(sinTheta * cos(phi), cosTheta, sinTheta * sin(phi))
                positions.append(centre + normal * radius)
                normals.append(normal)
            }
        }

        let stride = UInt32(longitudes + 1)
        for ring in 0..<latitudes {
            for lon in 0..<longitudes {
                let a = base + UInt32(ring) * stride + UInt32(lon)
                let b = a + 1
                let c = a + stride
                let d = c + 1
                indices.append(contentsOf: [a, b, c, b, d, c])
            }
        }
    }

    /// Appends an open-ended cylinder spanning `from` to `to`.
    ///
    /// The caps are omitted — joint spheres sit at both ends and hide them.
    private func appendCylinder(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        radius: Float,
        positions: inout [SIMD3<Float>],
        normals: inout [SIMD3<Float>],
        indices: inout [UInt32]
    ) {
        let axis = end - start
        let length = simd_length(axis)
        guard length > 1e-5 else { return }

        // Build an orthonormal basis around the bone axis. The helper vector
        // just needs to be non-parallel to the axis.
        let direction = axis / length
        let helper: SIMD3<Float> = abs(direction.y) < 0.99 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
        let u = simd_normalize(simd_cross(helper, direction))
        let v = simd_cross(direction, u)

        let sides = max(3, segments)
        let base = UInt32(positions.count)

        for side in 0...sides {
            let phi = 2 * Float.pi * Float(side) / Float(sides)
            let radial = u * cos(phi) + v * sin(phi)
            positions.append(start + radial * radius)
            normals.append(radial)
            positions.append(end + radial * radius)
            normals.append(radial)
        }

        for side in 0..<sides {
            let bottom = base + UInt32(side * 2)
            let top = bottom + 1
            let nextBottom = base + UInt32((side + 1) * 2)
            let nextTop = nextBottom + 1
            indices.append(contentsOf: [bottom, nextBottom, top, top, nextBottom, nextTop])
        }
    }
}

enum SkeletonMeshError: LocalizedError {
    case noGeometry

    var errorDescription: String? {
        switch self {
        case .noGeometry: return "No joints to build a skeleton from."
        }
    }
}
