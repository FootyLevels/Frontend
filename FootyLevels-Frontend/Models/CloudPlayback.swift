import Foundation

struct CloudAssetReference: Decodable, Hashable {
    let bucket: String
    let objectKey: String
    let sha256: String
    let byteSize: Int
    let contentType: String

    func validate(prefix: String) throws {
        guard bucket == "private-media", objectKey.hasPrefix(prefix),
              objectKey.utf8.count <= 1024, !objectKey.contains(where: { $0.isWhitespace || $0.isNewline }),
              !objectKey.contains(where: { "%:?#\\".contains($0) }),
              objectKey.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              (1...52_428_800).contains(byteSize), sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
        else { throw CloudPlaybackError.invalidAsset }
    }
}

struct CloudPreparedMedia: Decodable, Hashable {
    let profileVersion: String
    let video: CloudAssetReference
    let width: Int
    let height: Int
    let fps: Double
    let duration: Double
    let frameCount: Int
    let previews: [Preview]
    struct Preview: Decodable, Hashable { let asset: CloudAssetReference; let timestamp: Double; let frameIndex: Int }
}

struct CloudJob: Decodable {
    let id: String
    let ownerId: String
    let projectId: String
    let inputRevision: Int
    let kind: String
    let status: String
    let stage: String
    let attemptCount: Int
    let inputHash: String
    let profileVersion: String
    let sourceAsset: CloudAssetReference
    let motionSegment: Segment?
    let keyframes: [CloudKeyframeSelection]?
    let reconstructionId: String?
    let errorCode: String?
    struct Segment: Decodable { let startFrame: Int; let endFrame: Int }

    var isActive: Bool { ["queued", "running", "retrying"].contains(status) }
    var statusText: String {
        if kind == "prepareMedia" {
            switch status {
            case "queued", "retrying": return "Waiting for video preparation"
            case "running": return "Preparing your video"
            case "succeeded": return "Video ready for 3D generation"
            case "failed": return "Video preparation couldn't finish"
            case "cancelled": return "Video preparation cancelled"
            default: return "Unavailable preparation status"
            }
        }
        if kind == "reconstructKeyframes" {
            switch status {
            case "queued", "retrying": return "Waiting for the 3D worker"
            case "running": return "Generating selected 3D poses"
            case "succeeded": return "Selected 3D poses ready"
            case "partial": return "Selected poses ready · some could not be reconstructed"
            case "cancelled": return "Generation cancelled"
            default: return "Selected-pose generation couldn't finish"
            }
        }
        switch status {
        case "queued": return "Waiting for the 3D worker"
        case "retrying": return "Waiting to retry generation"
        case "running": return "Generating your 3D motion"
        case "succeeded": return "3D motion ready"
        case "partial": return "3D motion ready · some poses are missing"
        case "cancelled": return "Generation cancelled"
        case "failed": return "Generation couldn't finish. Select another segment to try again."
        default: return "Unavailable job status"
        }
    }
}

struct CloudReconstruction: Decodable {
    let schemaVersion: Int
    let id: String
    let ownerId: String
    let projectId: String
    let jobId: String
    let inputRevision: Int
    let profileVersion: String
    let sourceAsset: CloudAssetReference
    let mode: String
    let outcome: String
    let contract: Contract
    let engine: Engine
    let artifacts: [CloudAssetReference]
    let requestedFrameCount: Int
    let reconstructedFrameCount: Int
    let missingFrameCount: Int

    struct Contract: Decodable, Equatable {
        let schemaVersion: Int
        let topologyVersion: String
        let coordinateSystem: String
        let units: String
        let encoding: String
    }
    struct Engine: Decodable, Equatable {
        let modelName: String
        let upstreamCommit: String
        let checkpointHash: String
        let configHash: String
    }

    func validateMotion(owner: String, project: CloudProject) throws {
        try validate(owner: owner, project: project, keyframes: false)
    }

    func validateKeyframes(owner: String, project: CloudProject) throws {
        try validate(owner: owner, project: project, keyframes: true)
    }

    private func validate(owner: String, project: CloudProject, keyframes: Bool) throws {
        try sourceAsset.validate(prefix: "users/\(owner)/projects/\(project.id)/media/")
        guard schemaVersion == 1, contract.schemaVersion == 1,
              profileVersion == (keyframes ? "body-keyframes-v1" : "body-motion-30fps-v1"),
              mode == (keyframes ? "keyframes" : "motion"), contract.encoding == (keyframes ? "glb" : "motionBuffers"),
              contract.coordinateSystem == "rightHandedYUp",
              contract.units == "meters" else { throw CloudPlaybackError.unsupportedVersion }
        guard ownerId == owner, projectId == project.id, jobId == id, inputRevision == project.inputRevision,
              sourceAsset == project.preparedMedia?.video,
              sourceAsset.contentType == "video/mp4", project.preparedMedia?.profileVersion == "media-720p30-v1",
              project.preparedMedia?.fps == 30,
              ["ready", "partial"].contains(outcome), (keyframes ? 1...24 : 30...300).contains(requestedFrameCount),
              reconstructedFrameCount > 0, missingFrameCount >= 0,
              reconstructedFrameCount + missingFrameCount == requestedFrameCount,
              (outcome == "ready") == (missingFrameCount == 0), (keyframes ? 2...25 : 3...32).contains(artifacts.count)
        else { throw CloudPlaybackError.invalidResult }
        let prefix = "users/\(owner)/projects/\(projectId)/reconstruction/\(jobId)/"
        var names = Set<String>(), attempt: String?
        for asset in artifacts {
            try asset.validate(prefix: prefix)
            let parts = asset.objectKey.dropFirst(prefix.count).split(separator: "/")
            guard parts.count == 2, let number = Int(parts[0]), (1...5).contains(number),
                  attempt == nil || attempt == String(parts[0]), names.insert(String(parts[1])).inserted
            else { throw CloudPlaybackError.invalidAsset }
            attempt = String(parts[0])
        }
        if keyframes {
            guard names.contains("keyframes.json"), artifacts.count == reconstructedFrameCount + 1,
                  artifacts.allSatisfy({ $0.objectKey.hasSuffix("/keyframes.json") ? $0.contentType == "application/json" :
                    $0.contentType == "model/gltf-binary" && $0.byteSize <= 4_194_304 &&
                    $0.objectKey.split(separator: "/").last!.range(of: "^frame-[0-9]{4}\\.glb$", options: .regularExpression) != nil })
            else { throw CloudPlaybackError.invalidResult }
        } else {
            guard names.contains("sequence.json"), names.contains("video.mp4") else { throw CloudPlaybackError.invalidResult }
        }
    }
}

struct CloudKeyframeSelection: Codable, Equatable {
    let frameIndex: Int
    let bbox: [Double]
    func validate(frameCount: Int) throws {
        guard frameIndex >= 0, frameIndex < frameCount, Self.validBox(bbox) else { throw CloudPlaybackError.invalidResult }
    }
    static func validBox(_ box: [Double]) -> Bool {
        box.count == 4 && box.allSatisfy { $0.isFinite && (0...1).contains($0) }
            && box[2]-box[0] >= 0.03 && box[3]-box[1] >= 0.03
    }
}

struct PrivateReadGrant: Decodable {
    let expiresAt: String
    let assets: [String: Asset]
    struct Asset: Decodable {
        let url: String
        let sha256: String
        let byteSize: Int
        let contentType: String
    }
    var expiry: Date? { ISO8601DateFormatter.fractional.date(from: expiresAt) ?? ISO8601DateFormatter().date(from: expiresAt) }
}

enum CloudPlaybackError: LocalizedError, Equatable {
    case invalidAsset, invalidResult, unsupportedVersion, corruptFile, expired, unavailable
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "This 3D format isn't supported by this version of the app."
        case .invalidAsset, .invalidResult: return "The private 3D result couldn't be verified."
        case .corruptFile: return "A 3D file is incomplete or damaged. Please reload the result."
        case .expired: return "The private playback link expired. Please reload the result."
        case .unavailable: return "Private playback is unavailable. Please try again."
        }
    }
}
