import CryptoKit
import Foundation

struct PrivateKeyframeManifest: Decodable {
    let schemaVersion: Int, attempt: Int, inputRevision: Int
    let jobId: String, sourceSha256: String, inputHash: String, profileVersion: String
    let engine: CloudReconstruction.Engine
    let contract: CloudReconstruction.Contract
    let frames: [Frame]
    let missingFrameIndices: [Int]
    struct Frame: Decodable {
        let frameIndex: Int, timestamp: Double, bbox: [Double], artifact: String
        let metadata: Geometry
    }
    struct Geometry: Decodable { let vertexCount: Int, faceCount: Int }
}

@MainActor
final class PrivateKeyframeAssetSource {
    let result: CloudReconstruction
    private let job: CloudJob
    private let assets: PrivatePlaybackAssets
    private var loaded: PrivateKeyframeManifest?
    private var cachedMeshes: [Int: TriangleMesh] = [:]
    init(result: CloudReconstruction, job: CloudJob, assets: PrivatePlaybackAssets) {
        self.result = result; self.job = job; self.assets = assets
    }
    func checkSession() throws { try assets.checkSession() }
    func close() { loaded = nil; cachedMeshes.removeAll(); assets.close() }
    func manifest() async throws -> PrivateKeyframeManifest {
        try checkSession(); if let loaded { return loaded }
        let data = try await assets.data(file: "keyframes.json")
        guard data.count <= 1_048_576 else { throw CloudPlaybackError.corruptFile }
        let value = try JSONDecoder().decode(PrivateKeyframeManifest.self, from: data)
        guard value.schemaVersion == 1, value.profileVersion == "body-keyframes-v1", value.contract.encoding == "glb"
        else { throw CloudPlaybackError.unsupportedVersion }
        guard value.jobId == result.jobId, value.attempt == job.attemptCount, value.inputRevision == result.inputRevision,
              value.inputHash == job.inputHash, value.sourceSha256 == result.sourceAsset.sha256,
              value.engine == result.engine, value.contract == result.contract,
              value.frames.count == result.reconstructedFrameCount, value.missingFrameIndices.count == result.missingFrameCount,
              let selections = job.keyframes, selections.count == result.requestedFrameCount,
              Set(selections.map(\.frameIndex)).count == selections.count,
              Set(value.frames.map(\.frameIndex)).count == value.frames.count,
              Set(value.missingFrameIndices).count == value.missingFrameIndices.count,
              Set(value.frames.map(\.frameIndex)).isDisjoint(with: value.missingFrameIndices),
              Set(value.frames.map(\.frameIndex) + value.missingFrameIndices) == Set(selections.map(\.frameIndex))
        else { throw CloudPlaybackError.invalidResult }
        for frame in value.frames {
            guard let selection = selections.first(where: { $0.frameIndex == frame.frameIndex }), frame.bbox == selection.bbox,
                  frame.timestamp.isFinite, abs(frame.timestamp-Double(frame.frameIndex)/30) < 0.000001,
                  frame.artifact == String(format: "frame-%04d.glb", frame.frameIndex),
                  (1...25_000).contains(frame.metadata.vertexCount), (1...50_000).contains(frame.metadata.faceCount),
                  result.artifacts.contains(where: { $0.objectKey.hasSuffix("/\(value.attempt)/\(frame.artifact)") })
            else { throw CloudPlaybackError.invalidResult }
        }
        guard value.frames.map(\.frameIndex) == selections.map(\.frameIndex).filter({ !value.missingFrameIndices.contains($0) }),
              value.missingFrameIndices == selections.map(\.frameIndex).filter({ value.missingFrameIndices.contains($0) }),
              result.artifacts.allSatisfy({ $0.objectKey.contains("/\(value.attempt)/") })
        else { throw CloudPlaybackError.invalidResult }
        try checkSession(); loaded = value; return value
    }
    func mesh(frameIndex: Int) async throws -> TriangleMesh? {
        try checkSession()
        let manifest = try await manifest()
        if manifest.missingFrameIndices.contains(frameIndex) { return nil }
        guard let frame = manifest.frames.first(where: { $0.frameIndex == frameIndex }) else { throw CloudPlaybackError.invalidResult }
        if let cached = cachedMeshes[frameIndex] { return cached }
        let bytes = try await assets.data(file: frame.artifact)
        let mesh = try await Task.detached { try GLBLoader.loadPrivate(bytes) }.value
        var topology = Data()
        for index in mesh.indices { var value = index.littleEndian; withUnsafeBytes(of: &value) { topology.append(contentsOf: $0) } }
        let digest = SHA256.hash(data: topology).map { String(format: "%02x", $0) }.joined()
        guard mesh.positions.count == frame.metadata.vertexCount, mesh.indices.count == frame.metadata.faceCount*3,
              result.contract.topologyVersion == "mhr-\(digest.prefix(24))-v1" else { throw CloudPlaybackError.corruptFile }
        try checkSession()
        if cachedMeshes.count >= 2 { cachedMeshes.removeAll() }
        cachedMeshes[frameIndex] = mesh; return mesh
    }
}
