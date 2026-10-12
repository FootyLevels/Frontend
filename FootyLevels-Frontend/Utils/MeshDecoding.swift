import Foundation
import RealityKit
import zlib

// Decoders for the backend's binary assets: gzip'd motion chunks, uint32
// topology, and GLB meshes. RealityKit loads USDZ but not glTF, so key-frame
// and ball meshes are parsed here and rebuilt with `MeshDescriptor`.

// MARK: - Gzip

enum Gzip {
    /// The private format requires a complete gzip member, valid CRC/trailer,
    /// exact output size and no trailing data. Never inflate beyond this buffer.
    static func decompress(_ data: Data, expectedByteCount: Int) throws -> Data {
        guard (1...4_500_000).contains(expectedByteCount), data.count <= 52_428_800 else { throw CloudPlaybackError.corruptFile }
        var stream = z_stream()
        guard inflateInit2_(&stream, MAX_WBITS + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK
        else { throw CloudPlaybackError.corruptFile }
        defer { inflateEnd(&stream) }
        var result = Data(count: expectedByteCount + 1)
        let status = data.withUnsafeBytes { input in
            result.withUnsafeMutableBytes { output in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(data.count)
                stream.next_out = output.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(output.count)
                return inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END, stream.total_out == expectedByteCount, stream.avail_in == 0
        else { throw CloudPlaybackError.corruptFile }
        result.removeLast(); return result
    }

    /// Inflates a gzip member (RFC 1952). Data that isn't gzip is returned as-is,
    /// in case a proxy or server ever sends it with `Content-Encoding: gzip` and
    /// URLSession has already decoded it.
    static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1f, bytes[1] == 0x8b else {
            return data
        }
        guard bytes[2] == 8 else { throw MeshDecodingError.unsupportedCompression }

        // Walk past the optional header fields. Python's gzip.compress sets
        // none of them, but skipping them properly costs nothing.
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 {
            guard offset + 2 <= bytes.count else { throw MeshDecodingError.truncated }
            offset += 2 + (Int(bytes[offset]) | Int(bytes[offset + 1]) << 8)
        }
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 }
        guard offset < bytes.count - 8 else { throw MeshDecodingError.truncated }

        // Apple's `.zlib` is raw DEFLATE (RFC 1951) — exactly the gzip payload
        // once the 10-byte header and 8-byte CRC/size trailer are removed.
        let deflated = Data(bytes[offset..<(bytes.count - 8)])
        return try (deflated as NSData).decompressed(using: .zlib) as Data
    }
}

// MARK: - Buffers

enum BinaryBuffers {
    /// Copies little-endian values out of `data` into an aligned array. Binding
    /// `Data`'s storage in place would be undefined behaviour if unaligned.
    static func array<T: FixedWidthInteger>(of type: T.Type, from data: Data) -> [T] {
        var values = [T](repeating: 0, count: data.count / MemoryLayout<T>.size)
        values.withUnsafeMutableBytes { _ = data.copyBytes(to: $0) }
        return values
    }
}

// MARK: - Normals

enum MeshNormals {
    /// Area-weighted smooth vertex normals. Neither the motion chunks nor the
    /// packed topology carry normals, so every body frame needs this.
    ///
    /// Written against raw buffers: it runs per frame during playback, and
    /// bounds-checked array access is the difference between comfortably
    /// inside a frame budget and not, in a debug build.
    static func compute(positions: UnsafeBufferPointer<SIMD3<Float>>,
                        indices: UnsafeBufferPointer<UInt32>,
                        into normals: UnsafeMutableBufferPointer<SIMD3<Float>>) {
        for i in 0..<normals.count { normals[i] = .zero }

        var t = 0
        while t + 2 < indices.count {
            let a = Int(indices[t]), b = Int(indices[t + 1]), c = Int(indices[t + 2])
            let pa = positions[a]
            // Unnormalised cross product: larger triangles contribute more.
            let n = simd_cross(positions[b] - pa, positions[c] - pa)
            normals[a] += n
            normals[b] += n
            normals[c] += n
            t += 3
        }

        for i in 0..<normals.count {
            let length = simd_length(normals[i])
            normals[i] = length > 1e-12 ? normals[i] / length : SIMD3(0, 1, 0)
        }
    }

    static func compute(positions: [SIMD3<Float>], indices: [UInt32]) -> [SIMD3<Float>] {
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        positions.withUnsafeBufferPointer { p in
            indices.withUnsafeBufferPointer { i in
                normals.withUnsafeMutableBufferPointer { n in
                    compute(positions: p, indices: i, into: n)
                }
            }
        }
        return normals
    }
}

// MARK: - Static meshes

/// Triangle geometry in the backend's space: Y-up, metres.
struct TriangleMesh {
    var positions: [SIMD3<Float>]
    var normals: [SIMD3<Float>]?
    var indices: [UInt32]

    var bounds: BoundingBox {
        guard let first = positions.first else { return BoundingBox() }
        var box = BoundingBox(min: first, max: first)
        for point in positions { box.formUnion(point) }
        return box
    }

    @MainActor
    func makeResource(name: String) throws -> MeshResource {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals ?? MeshNormals.compute(positions: positions, indices: indices))
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}

// MARK: - GLB

/// Minimal glTF 2.0 binary reader for what `trimesh` exports: triangle
/// primitives with float POSITION / NORMAL and integer indices.
///
/// Node transforms are ignored — the backend writes vertices already in their
/// final space with identity nodes. Materials and vertex colours are dropped.
enum GLBLoader {
    static func load(_ data: Data) throws -> TriangleMesh {
        let bytes = [UInt8](data)
        guard bytes.count >= 20, readUInt32(bytes, 0) == 0x4654_6C67 else {
            throw MeshDecodingError.notGLB
        }
        guard readUInt32(bytes, 4) == 2 else { throw MeshDecodingError.unsupportedGLTFVersion }

        var json: Data?
        var bin: Data?
        var offset = 12
        while offset + 8 <= bytes.count {
            let length = Int(readUInt32(bytes, offset))
            let type = readUInt32(bytes, offset + 4)
            let start = offset + 8
            guard start + length <= bytes.count else { throw MeshDecodingError.truncated }
            let chunk = Data(bytes[start..<(start + length)])
            if type == 0x4E4F_534A { json = chunk }       // "JSON"
            else if type == 0x004E_4942 { bin = chunk }   // "BIN\0"
            offset = start + length
        }
        guard let json, let bin else { throw MeshDecodingError.missingChunk }

        let document = try JSONDecoder().decode(GLTFDocument.self, from: json)
        var mesh = TriangleMesh(positions: [], normals: [], indices: [])

        for primitive in document.meshes.flatMap(\.primitives) {
            guard (primitive.mode ?? 4) == 4 else { continue }  // triangles only
            guard let positionIndex = primitive.attributes["POSITION"] else { continue }

            let base = UInt32(mesh.positions.count)
            let positions = try document.readVec3(positionIndex, from: bin)
            mesh.positions += positions

            if let normalIndex = primitive.attributes["NORMAL"], mesh.normals != nil {
                mesh.normals! += try document.readVec3(normalIndex, from: bin)
            } else {
                mesh.normals = nil   // one primitive without normals → compute all
            }

            if let indexAccessor = primitive.indices {
                mesh.indices += try document.readIndices(indexAccessor, from: bin).map { $0 + base }
            } else {
                mesh.indices += (0..<UInt32(positions.count)).map { $0 + base }
            }
        }

        guard !mesh.positions.isEmpty, !mesh.indices.isEmpty else { throw MeshDecodingError.noGeometry }
        if let highest = mesh.indices.max(), Int(highest) >= mesh.positions.count {
            throw MeshDecodingError.indexOutOfRange
        }
        return mesh
    }

    fileprivate static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
}

private struct GLTFDocument: Decodable {
    let meshes: [Mesh]
    let accessors: [Accessor]
    let bufferViews: [BufferView]

    struct Mesh: Decodable { let primitives: [Primitive] }

    struct Primitive: Decodable {
        let attributes: [String: Int]
        let indices: Int?
        let mode: Int?
    }

    struct Accessor: Decodable {
        let bufferView: Int?
        let byteOffset: Int?
        let componentType: Int
        let count: Int
        let type: String
    }

    struct BufferView: Decodable {
        let byteOffset: Int?
        let byteLength: Int
        let byteStride: Int?
    }

    private static let float = 5126, uint32 = 5125, uint16 = 5123, uint8 = 5121

    func readVec3(_ index: Int, from bin: Data) throws -> [SIMD3<Float>] {
        let (accessor, start, stride) = try layout(index, elementSize: 12)
        guard accessor.type == "VEC3", accessor.componentType == Self.float else {
            throw MeshDecodingError.unsupportedAccessor
        }
        return try bin.withUnsafeBytes { raw in
            guard start + stride * (accessor.count - 1) + 12 <= raw.count else {
                throw MeshDecodingError.truncated
            }
            return (0..<accessor.count).map { i in
                let at = start + i * stride
                return SIMD3(raw.loadUnaligned(fromByteOffset: at, as: Float.self),
                             raw.loadUnaligned(fromByteOffset: at + 4, as: Float.self),
                             raw.loadUnaligned(fromByteOffset: at + 8, as: Float.self))
            }
        }
    }

    func readIndices(_ index: Int, from bin: Data) throws -> [UInt32] {
        let componentType = accessors.indices.contains(index) ? accessors[index].componentType : 0
        let size: Int
        switch componentType {
        case Self.uint32: size = 4
        case Self.uint16: size = 2
        case Self.uint8: size = 1
        default: throw MeshDecodingError.unsupportedAccessor
        }
        let (accessor, start, stride) = try layout(index, elementSize: size)
        guard accessor.type == "SCALAR" else { throw MeshDecodingError.unsupportedAccessor }

        return try bin.withUnsafeBytes { raw in
            guard start + stride * (accessor.count - 1) + size <= raw.count else {
                throw MeshDecodingError.truncated
            }
            return (0..<accessor.count).map { i in
                let at = start + i * stride
                switch size {
                case 4: return raw.loadUnaligned(fromByteOffset: at, as: UInt32.self)
                case 2: return UInt32(raw.loadUnaligned(fromByteOffset: at, as: UInt16.self))
                default: return UInt32(raw[at])
                }
            }
        }
    }

    private func layout(_ index: Int, elementSize: Int) throws -> (Accessor, start: Int, stride: Int) {
        guard accessors.indices.contains(index) else { throw MeshDecodingError.unsupportedAccessor }
        let accessor = accessors[index]
        guard accessor.count > 0,
              let viewIndex = accessor.bufferView, bufferViews.indices.contains(viewIndex) else {
            throw MeshDecodingError.unsupportedAccessor   // sparse / empty accessors
        }
        let view = bufferViews[viewIndex]
        return (accessor, (view.byteOffset ?? 0) + (accessor.byteOffset ?? 0), view.byteStride ?? elementSize)
    }
}

// MARK: - Errors

enum MeshDecodingError: LocalizedError {
    case unsupportedCompression, truncated, notGLB, unsupportedGLTFVersion
    case missingChunk, unsupportedAccessor, noGeometry, indexOutOfRange
    case unsupportedEncoding(String)
    case chunkSizeMismatch(file: String, expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedCompression: return "Unsupported gzip compression method."
        case .truncated: return "The file ended unexpectedly."
        case .notGLB: return "Not a GLB file."
        case .unsupportedGLTFVersion: return "Only glTF 2.0 is supported."
        case .missingChunk: return "GLB is missing its JSON or binary chunk."
        case .unsupportedAccessor: return "GLB uses an accessor layout this viewer doesn't read."
        case .noGeometry: return "The mesh has no triangles."
        case .indexOutOfRange: return "The mesh references a vertex that doesn't exist."
        case .unsupportedEncoding(let encoding): return "Unsupported motion encoding: \(encoding)."
        case .chunkSizeMismatch(let file, let expected, let actual):
            return "\(file) decoded to \(actual) bytes, expected \(expected)."
        }
    }
}
