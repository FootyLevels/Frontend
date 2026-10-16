import CryptoKit
import Foundation

@MainActor
protocol MotionAssetSource: AnyObject {
    var usesPrivateContract: Bool { get }
    var sourceTimeOffset: Double { get }
    func checkSession() throws
    func sequence() async throws -> MotionSequence
    func data(file: String) async throws -> Data
    func close()
}

@MainActor
final class LegacyMotionAssetSource: MotionAssetSource {
    let usesPrivateContract = false
    let sourceTimeOffset = 0.0
    private let projectId: String
    private let sequencePath: String
    init(projectId: String, sequencePath: String) { self.projectId = projectId; self.sequencePath = sequencePath }
    func checkSession() throws { try Task.checkCancellation() }
    func sequence() async throws -> MotionSequence { try await SkillLabClient.shared.sequence(path: sequencePath) }
    func data(file: String) async throws -> Data {
        try await SkillLabClient.shared.data(path: SkillLabClient.shared.motionAssetPath(projectId: projectId, file: file))
    }
    func close() {}
}

@MainActor
final class PrivateMotionAssetSource: MotionAssetSource {
    let usesPrivateContract = true
    private(set) var sourceTimeOffset = 0.0
    private let result: CloudReconstruction
    private let job: CloudJob
    private let assets: PrivatePlaybackAssets
    private var loaded: MotionSequence?

    init(result: CloudReconstruction, job: CloudJob, assets: PrivatePlaybackAssets) {
        self.result = result; self.job = job; self.assets = assets
    }
    func checkSession() throws { try assets.checkSession() }
    func close() { loaded = nil; assets.close() }

    func sequence() async throws -> MotionSequence {
        try checkSession()
        if let loaded { return loaded }
        let data = try await assets.data(file: "sequence.json")
        let metadata = try JSONDecoder().decode(Metadata.self, from: data)
        let sequence = try JSONDecoder().decode(MotionSequence.self, from: data)
        guard metadata.schemaVersion == 1, metadata.version == 1, metadata.profileVersion == result.profileVersion,
              metadata.profileVersion == "body-motion-30fps-v1", metadata.contract.schemaVersion == 1,
              metadata.contract.encoding == "motionBuffers", metadata.contract.coordinateSystem == "rightHandedYUp",
              metadata.contract.units == "meters",
              metadata.contract == result.contract, metadata.engine == result.engine,
              metadata.jobId == result.jobId, metadata.inputRevision == result.inputRevision,
              metadata.sourceSha256 == result.sourceAsset.sha256, metadata.playbackVideo == "video.mp4",
              metadata.attempt == job.attemptCount, metadata.inputHash == job.inputHash,
              metadata.sourceStartFrame == job.motionSegment?.startFrame,
              metadata.sourceEndFrame == job.motionSegment?.endFrame, metadata.sourceStartFrame >= 0,
              metadata.sourceEndFrame - metadata.sourceStartFrame == result.requestedFrameCount,
              metadata.sourceTimeOffset.isFinite,
              abs(metadata.sourceTimeOffset - Double(metadata.sourceStartFrame) / 30) < 0.000001
        else { throw CloudPlaybackError.invalidResult }
        try Self.validate(sequence, result: result, metadata: metadata)
        let topology = try await assets.data(file: sequence.topologyFile)
        let digest = SHA256.hash(data: topology).map { String(format: "%02x", $0) }.joined()
        let indices = BinaryBuffers.array(of: UInt32.self, from: topology)
        guard topology.count == sequence.faceCount * 12, indices.allSatisfy({ $0 < sequence.vertexCount }),
              result.contract.topologyVersion == "mhr-\(digest.prefix(24))-v1"
        else { throw CloudPlaybackError.corruptFile }
        try checkSession(); loaded = sequence; sourceTimeOffset = metadata.sourceTimeOffset
        return sequence
    }

    func data(file: String) async throws -> Data { try await assets.data(file: file) }
    func videoURL() async throws -> URL { try await assets.localFile(file: "video.mp4") }

    private struct Metadata: Decodable {
        let schemaVersion: Int, version: Int, inputRevision: Int, attempt: Int, sourceStartFrame: Int, sourceEndFrame: Int
        let profileVersion: String, jobId: String, sourceSha256: String, playbackVideo: String, inputHash: String
        let sourceTimeOffset: Double
        let contract: CloudReconstruction.Contract
        let engine: CloudReconstruction.Engine
        let frames: [SourceFrame]
        struct SourceFrame: Decodable { let sourceFrameIndex: Int; let sourceTimestamp: Double }
    }

    private static func validate(_ value: MotionSequence, result: CloudReconstruction, metadata: Metadata) throws {
        let names = Set(result.artifacts.map { String($0.objectKey.split(separator: "/").last!) })
        guard value.encoding == "uint16-le-xyz-gzip", value.fps == 30,
              value.frameCount == result.requestedFrameCount, value.frames.count == value.frameCount,
              metadata.frames.count == value.frameCount, (1...25_000).contains(value.vertexCount),
              (1...50_000).contains(value.faceCount), value.min.count == 3, value.span.count == 3,
              value.min.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }),
              value.span.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 10_000 }),
              value.duration.isFinite, abs(value.duration - Double(value.frameCount)/30) < 0.000001,
              value.validBodyFrames == result.reconstructedFrameCount,
              value.validBodyFrames == value.frames.filter(\.valid).count,
              value.validBallFrames == 0, value.ball.file == nil, value.frames.allSatisfy({ $0.ball == nil }),
              value.ground == nil, names.contains(value.topologyFile), (1...10).contains(value.chunks.count)
        else { throw CloudPlaybackError.invalidResult }
        var covered = 0, files = Set<String>()
        for chunk in value.chunks {
            guard chunk.start == covered, (1...30).contains(chunk.count), covered + chunk.count <= value.frameCount,
                  names.contains(chunk.file), files.insert(chunk.file).inserted,
                  chunk.bytes == result.artifacts.first(where: { $0.objectKey.hasSuffix("/" + chunk.file) })?.byteSize
            else { throw CloudPlaybackError.invalidResult }
            covered += chunk.count
        }
        guard covered == value.frameCount else { throw CloudPlaybackError.invalidResult }
        for (i, frame) in value.frames.enumerated() {
            let source = metadata.frames[i]
            guard frame.index == i, frame.shot >= 0, frame.time.isFinite, abs(frame.time - Double(i)/30) < 0.000001,
                  source.sourceFrameIndex == metadata.sourceStartFrame + i, source.sourceTimestamp.isFinite,
                  abs(source.sourceTimestamp - Double(source.sourceFrameIndex)/30) < 0.000001
            else { throw CloudPlaybackError.invalidResult }
        }
    }
}
