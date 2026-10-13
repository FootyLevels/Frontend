import Foundation

/// One project's whole-video body motion, decoded for playback: the sequence
/// header, the shared topology and the quantised pose chunks.
///
/// Loads the same files as the motion inspector — header, topology and one
/// chunk up front, the rest streamed — so a clip appears before all of it has
/// arrived.
@MainActor
final class MotionClip {
    enum LoadError: LocalizedError {
        case noFrames

        var errorDescription: String? { "This video's 3D motion has no frames." }
    }

    let projectId: String
    let sequence: MotionSequence
    /// Triangle indices shared by every frame.
    let indices: [UInt32]
    private(set) var loadedChunks = 0

    /// Decoded `uint16` values per chunk index.
    private var chunks: [Int: [UInt16]] = [:]
    /// Chunk index for every frame, so lookup during playback is O(1).
    private let chunkForFrame: [Int]

    private init(projectId: String, sequence: MotionSequence, indices: [UInt32], chunkForFrame: [Int]) {
        self.projectId = projectId
        self.sequence = sequence
        self.indices = indices
        self.chunkForFrame = chunkForFrame
    }

    /// Fetches enough to show the first frame.
    static func load(projectId: String, sequencePath: String) async throws -> MotionClip {
        let client = SkillLabClient.shared
        let sequence = try await client.sequence(path: sequencePath)
        guard sequence.encoding == "uint16-le-xyz-gzip" else {
            throw MeshDecodingError.unsupportedEncoding(sequence.encoding)
        }
        guard sequence.frameCount > 0, !sequence.chunks.isEmpty else { throw LoadError.noFrames }

        let lookup = chunkLookup(for: sequence)
        let first = lookup.first ?? 0
        async let topology = client.data(path: client.motionAssetPath(projectId: projectId, file: sequence.topologyFile))
        async let firstChunk = fetchChunk(first, of: sequence, projectId: projectId)

        let indices = BinaryBuffers.array(of: UInt32.self, from: try await topology)
        guard indices.count == sequence.faceCount * 3 else {
            throw MeshDecodingError.chunkSizeMismatch(file: sequence.topologyFile,
                                                      expected: sequence.faceCount * 12,
                                                      actual: indices.count * 4)
        }

        let clip = MotionClip(projectId: projectId, sequence: sequence, indices: indices, chunkForFrame: lookup)
        clip.chunks[first] = try await firstChunk
        clip.loadedChunks = 1
        return clip
    }

    var isComplete: Bool { loadedChunks >= sequence.chunks.count }

    /// Streams the remaining chunks, calling `onChunk` after each so the caller
    /// can redraw a frame that was waiting on it.
    func loadRemainingChunks(onChunk: @escaping @MainActor () -> Void) async {
        let sequence = sequence, projectId = projectId
        var pending = sequence.chunks.indices.filter { chunks[$0] == nil }.makeIterator()

        await withTaskGroup(of: (Int, [UInt16]?).self) { group in
            // Three in flight saturates a LAN link without starving playback.
            for _ in 0..<3 {
                guard let index = pending.next() else { break }
                group.addTask { (index, try? await Self.fetchChunk(index, of: sequence, projectId: projectId)) }
            }
            for await (index, values) in group {
                if Task.isCancelled { return }
                if let values {
                    chunks[index] = values
                    loadedChunks += 1
                    onChunk()
                }
                if let next = pending.next() {
                    group.addTask { (next, try? await Self.fetchChunk(next, of: sequence, projectId: projectId)) }
                }
            }
        }
    }

    /// One frame's slice of its chunk, or nil until that chunk has arrived.
    func pose(_ frame: Int) -> AnimatedBodyMesh.Pose? {
        guard chunkForFrame.indices.contains(frame) else { return nil }
        let chunkIndex = chunkForFrame[frame]
        guard let values = chunks[chunkIndex] else { return nil }
        return .init(values: values, offset: (frame - sequence.chunks[chunkIndex].start) * sequence.vertexCount * 3)
    }

    /// Downloads and inflates one chunk off the main actor, checking its size
    /// against the header so a truncated file can't masquerade as a pose.
    nonisolated private static func fetchChunk(_ index: Int, of sequence: MotionSequence,
                                               projectId: String) async throws -> [UInt16] {
        let chunk = sequence.chunks[index]
        let client = SkillLabClient.shared
        let compressed = try await client.data(path: client.motionAssetPath(projectId: projectId, file: chunk.file))

        return try await Task.detached(priority: .userInitiated) {
            let raw = try Gzip.decompress(compressed)
            let expected = chunk.count * sequence.vertexCount * 3 * MemoryLayout<UInt16>.size
            guard raw.count == expected else {
                throw MeshDecodingError.chunkSizeMismatch(file: chunk.file, expected: expected, actual: raw.count)
            }
            return BinaryBuffers.array(of: UInt16.self, from: raw)
        }.value
    }

    private static func chunkLookup(for sequence: MotionSequence) -> [Int] {
        var lookup = Array(repeating: 0, count: sequence.frameCount)
        for (index, chunk) in sequence.chunks.enumerated() {
            let end = Swift.min(chunk.start + chunk.count, sequence.frameCount)
            // A malformed header can't make the range below trap.
            guard chunk.start >= 0, chunk.start < end else { continue }
            for frame in chunk.start..<end {
                lookup[frame] = index
            }
        }
        return lookup
    }
}
