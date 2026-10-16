import Foundation
import RealityKit

/// Builds the body mesh from the API's raw binary vertex buffers.
///
/// This is the `raw=true` path: positions and normals arrive as interleaved
/// little-endian `float32`, and the triangle indices come from the shared
/// `/api/topology` endpoint. Owning the vertices here is what makes per-vertex
/// work possible later — error colour-mapping, overlaying a reference pose,
/// or swapping positions per frame for animation.
struct BodyMeshBuilder {

    /// The decoded buffers for one reconstruction.
    struct Buffers {
        let positions: Data
        let normals: Data?
        /// Shared across reconstructions — the topology never changes.
        let indices: Data
        let vertexCount: Int
        let faceCount: Int
    }

    /// The mesh is uniformly scaled so its tallest axis measures this much,
    /// matching `SkeletonMeshBuilder.targetHeight` so the two overlay.
    var targetHeight: Float = 1.0
    var orientation = PoseOrientation()

    // MARK: - Mesh generation

    func makeMesh(from buffers: Buffers) throws -> MeshResource {
        let rawPositions = try Self.decodeVectors(buffers.positions,
                                                  vertexCount: buffers.vertexCount,
                                                  label: "positions")
        let rawNormals = try buffers.normals.map {
            try Self.decodeVectors($0, vertexCount: buffers.vertexCount, label: "normals")
        }
        var indices = try Self.decodeIndices(buffers.indices, faceCount: buffers.faceCount)

        // Reject indices that point past the vertex buffer before handing them
        // to RealityKit, which would otherwise read out of bounds.
        if let highest = indices.max(), Int(highest) >= buffers.vertexCount {
            throw BodyMeshError.indexOutOfRange(highest: Int(highest), vertexCount: buffers.vertexCount)
        }

        let positions = normalized(rawPositions)
        // Normals are directions: apply the axis flips but not the translation
        // or scale, then renormalise in case the buffer wasn't unit length.
        let normals = rawNormals?.map { normal -> SIMD3<Float> in
            let flipped = orientation.apply(to: normal)
            let length = simd_length(flipped)
            return length > 1e-6 ? flipped / length : flipped
        }

        // A single axis flip mirrors the mesh, which reverses the front face of
        // every triangle. Swap two indices per triangle to put winding back.
        if orientation.invertsWinding {
            for triangle in stride(from: 0, to: indices.count - 2, by: 3) {
                indices.swapAt(triangle + 1, triangle + 2)
            }
        }

        var descriptor = MeshDescriptor(name: "body")
        descriptor.positions = MeshBuffers.Positions(positions)
        if let normals {
            descriptor.normals = MeshBuffers.Normals(normals)
        }
        descriptor.primitives = .triangles(indices)

        return try MeshResource.generate(from: [descriptor])
    }

    /// Recentres on the bounding-box centre and scales to `targetHeight`, so the
    /// mesh orbits about itself and frames predictably. Discards real-world scale.
    private func normalized(_ points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        let converted = points.map { orientation.apply(to: $0) }
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

    // MARK: - Binary decoding

    /// Decodes interleaved `float32` XYZ triples.
    ///
    /// The bytes are copied into a properly aligned `[Float]` rather than bound
    /// in place: `Data`'s storage carries no alignment guarantee, and binding
    /// unaligned bytes to `Float` is undefined behaviour. iOS is little-endian,
    /// matching the buffer's declared layout, so no byte swapping is needed.
    static func decodeVectors(_ data: Data, vertexCount: Int, label: String) throws -> [SIMD3<Float>] {
        let expectedBytes = vertexCount * 3 * MemoryLayout<Float>.size
        guard data.count == expectedBytes else {
            throw BodyMeshError.bufferSizeMismatch(label: label,
                                                   expected: expectedBytes,
                                                   actual: data.count)
        }

        var scalars = [Float](repeating: 0, count: vertexCount * 3)
        scalars.withUnsafeMutableBytes { destination in
            _ = data.copyBytes(to: destination)
        }

        return (0..<vertexCount).map { index in
            let base = index * 3
            return SIMD3(scalars[base], scalars[base + 1], scalars[base + 2])
        }
    }

    /// Decodes the triangle index buffer, inferring the integer width from its
    /// byte length. 18k vertices needs `uint32`, but `uint16` is accepted in
    /// case the topology endpoint ever serves a lower-poly model.
    static func decodeIndices(_ data: Data, faceCount: Int) throws -> [UInt32] {
        let indexCount = faceCount * 3

        switch data.count {
        case indexCount * MemoryLayout<UInt32>.size:
            var values = [UInt32](repeating: 0, count: indexCount)
            values.withUnsafeMutableBytes { destination in
                _ = data.copyBytes(to: destination)
            }
            return values

        case indexCount * MemoryLayout<UInt16>.size:
            var values = [UInt16](repeating: 0, count: indexCount)
            values.withUnsafeMutableBytes { destination in
                _ = data.copyBytes(to: destination)
            }
            return values.map(UInt32.init)

        default:
            throw BodyMeshError.indexSizeMismatch(faceCount: faceCount, actual: data.count)
        }
    }
}

enum BodyMeshError: LocalizedError {
    case bufferSizeMismatch(label: String, expected: Int, actual: Int)
    case indexSizeMismatch(faceCount: Int, actual: Int)
    case indexOutOfRange(highest: Int, vertexCount: Int)

    var errorDescription: String? {
        switch self {
        case .bufferSizeMismatch(let label, let expected, let actual):
            return "\(label) buffer is \(actual) bytes, expected \(expected)."
        case .indexSizeMismatch(let faceCount, let actual):
            return "Index buffer is \(actual) bytes, which is neither uint16 nor uint32 for \(faceCount) faces."
        case .indexOutOfRange(let highest, let vertexCount):
            return "Index \(highest) exceeds the \(vertexCount)-vertex buffer."
        }
    }
}
