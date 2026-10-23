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
        case badPath

        var errorDescription: String? {
            switch self {
            case .noFrames: return "This video's 3D motion has no frames."
            case .badPath: return "The motion data refers to a file outside its folder."
            }
        }
    }

    /// Where the files come from: a server project, or a folder in the app bundle.
    enum Source: Sendable {
        case server(projectId: String)
        case local(URL)
    }

    let source: Source
    var projectId: String {
        if case .server(let id) = source { return id }
        return ""
    }
    let sequence: MotionSequence
    /// Triangle indices shared by every frame.
    let indices: [UInt32]
    private(set) var loadedChunks = 0

    /// Decoded `uint16` values per chunk index.
    private var chunks: [Int: [UInt16]] = [:]
    /// Chunk index for every frame, so lookup during playback is O(1).
    private let chunkForFrame: [Int]

    private init(source: Source, sequence: MotionSequence, indices: [UInt32], chunkForFrame: [Int]) {
        self.source = source
        self.sequence = sequence
        self.indices = indices
        self.chunkForFrame = chunkForFrame
    }

    /// Fetches enough to show the first frame.
    static func load(projectId: String, sequencePath: String) async throws -> MotionClip {
        let sequence = try await SkillLabClient.shared.sequence(path: sequencePath)
        return try await load(sequence: sequence, source: .server(projectId: projectId))
    }

    /// Loads motion stored in a folder (`sequence.json`, the topology and the
    /// chunks), such as a lesson bundle shipped inside the app.
    static func load(directory: URL) async throws -> MotionClip {
        let data = try Data(contentsOf: directory.appendingPathComponent("sequence.json"))
        let sequence = try JSONDecoder().decode(MotionSequence.self, from: data)
        return try await load(sequence: sequence, source: .local(directory))
    }

    private static func load(sequence: MotionSequence, source: Source) async throws -> MotionClip {
        guard sequence.encoding == "uint16-le-xyz-gzip" else {
            throw MeshDecodingError.unsupportedEncoding(sequence.encoding)
        }
        guard sequence.frameCount > 0, !sequence.chunks.isEmpty else { throw LoadError.noFrames }

        let lookup = chunkLookup(for: sequence)
        let first = lookup.first ?? 0
        async let topology = fileData(sequence.topologyFile, from: source)
        async let firstChunk = fetchChunk(first, of: sequence, source: source)

        let indices = BinaryBuffers.array(of: UInt32.self, from: try await topology)
        guard indices.count == sequence.faceCount * 3 else {
            throw MeshDecodingError.chunkSizeMismatch(file: sequence.topologyFile,
                                                      expected: sequence.faceCount * 12,
                                                      actual: indices.count * 4)
        }

        let clip = MotionClip(source: source, sequence: sequence, indices: indices, chunkForFrame: lookup)
        clip.chunks[first] = try await firstChunk
        clip.loadedChunks = 1
        return clip
    }

    var isComplete: Bool { loadedChunks >= sequence.chunks.count }

    /// Streams the remaining chunks, calling `onChunk` after each so the caller
    /// can redraw a frame that was waiting on it.
    func loadRemainingChunks(onChunk: @escaping @MainActor () -> Void) async {
        let sequence = sequence, source = source
        var pending = sequence.chunks.indices.filter { chunks[$0] == nil }.makeIterator()

        await withTaskGroup(of: (Int, [UInt16]?).self) { group in
            // Three in flight saturates a LAN link without starving playback.
            for _ in 0..<3 {
                guard let index = pending.next() else { break }
                group.addTask { (index, try? await Self.fetchChunk(index, of: sequence, source: source)) }
            }
            for await (index, values) in group {
                if Task.isCancelled { return }
                if let values {
                    chunks[index] = values
                    loadedChunks += 1
                    onChunk()
                }
                if let next = pending.next() {
                    group.addTask { (next, try? await Self.fetchChunk(next, of: sequence, source: source)) }
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
                                               source: Source) async throws -> [UInt16] {
        let chunk = sequence.chunks[index]
        let compressed = try await fileData(chunk.file, from: source)

        return try await Task.detached(priority: .userInitiated) {
            let raw = try Gzip.decompress(compressed)
            let expected = chunk.count * sequence.vertexCount * 3 * MemoryLayout<UInt16>.size
            guard raw.count == expected else {
                throw MeshDecodingError.chunkSizeMismatch(file: chunk.file, expected: expected, actual: raw.count)
            }
            return BinaryBuffers.array(of: UInt16.self, from: raw)
        }.value
    }

    /// One motion file, from the server or from the folder. Local names can't
    /// climb out of their folder.
    nonisolated private static func fileData(_ file: String, from source: Source) async throws -> Data {
        switch source {
        case .server(let projectId):
            let client = SkillLabClient.shared
            return try await client.data(path: client.motionAssetPath(projectId: projectId, file: file))
        case .local(let directory):
            guard !file.isEmpty, !file.contains("/"), !file.hasPrefix(".") else { throw LoadError.badPath }
            return try Data(contentsOf: directory.appendingPathComponent(file))
        }
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
