import Foundation

/// Community records contain references, never signed playback links.
struct TrainingCircle: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let ownerId: String
    let createdAt: String
    let memberCount: Int
    let members: [Member]

    struct Member: Decodable, Identifiable, Hashable {
        let uid: String
        let displayName: String
        let joinedAt: String
        var id: String { uid }
    }

    func validate(member uid: String) throws {
        guard CommunityValidation.validID(id), CommunityValidation.validID(ownerId),
              (1...80).contains(name.count), description.count <= 240,
              memberCount == members.count, (1...20).contains(memberCount),
              Set(members.map(\.uid)).count == members.count,
              members.contains(where: { $0.uid == uid }), members.contains(where: { $0.uid == ownerId }),
              members.allSatisfy({ CommunityValidation.validID($0.uid) && $0.displayName.count <= 120 })
        else { throw CommunityError.invalidResponse }
    }
}

struct CircleInvite: Decodable {
    let code: String
    let expiresAt: String
}

struct CirclePost: Decodable, Identifiable, Hashable {
    let id: String
    let circleId: String
    let authorId: String
    let authorName: String
    let projectId: String
    let projectTitle: String
    let skill: String
    let note: String
    let createdAt: String
    let previousPostId: String?
    let video: Video
    var motion: Motion? = nil

    struct Motion: Decodable, Hashable {
        let reconstruction: CloudReconstruction
        let job: CloudJob

        var startTime: Double { Double(job.motionSegment?.startFrame ?? 0) / 30 }
        var duration: Double { Double(reconstruction.requestedFrameCount) / 30 }

        func validate(author: String, projectID: String, video: Video) throws {
            let result = reconstruction
            guard [result.id, result.jobId, job.id].allSatisfy(CommunityValidation.validID), result.inputRevision > 0,
                  result.id == job.id, result.jobId == job.id, job.ownerId == author, job.projectId == projectID,
                  job.inputRevision == result.inputRevision, job.kind == "reconstructMotion",
                  job.status == (result.outcome == "ready" ? "succeeded" : "partial"), job.stage == result.outcome,
                  job.reconstructionId == result.id, job.profileVersion == result.profileVersion,
                  job.sourceAsset == video.asset, job.sourceAsset == result.sourceAsset,
                  job.inputHash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                  (1...5).contains(job.attemptCount), job.keyframes == nil, job.errorCode == nil,
                  let segment = job.motionSegment, segment.startFrame >= 0, segment.endFrame <= video.frameCount,
                  segment.endFrame > segment.startFrame,
                  segment.endFrame - segment.startFrame == result.requestedFrameCount
            else { throw CommunityError.invalidResponse }
            try result.validateSharedMotion(owner: author, projectID: projectID,
                inputRevision: job.inputRevision, video: video.asset)
            var names = Set<String>()
            for asset in result.artifacts {
                let parts = asset.objectKey.split(separator: "/")
                guard parts.count >= 2, parts[parts.count - 2] == String(job.attemptCount), let name = parts.last,
                      names.insert(String(name)).inserted else { throw CloudPlaybackError.invalidAsset }
                switch String(name) {
                case "sequence.json": guard asset.contentType == "application/json" else { throw CloudPlaybackError.invalidAsset }
                case "video.mp4": guard asset.contentType == "video/mp4" else { throw CloudPlaybackError.invalidAsset }
                case "faces.bin": guard asset.contentType == "application/octet-stream" else { throw CloudPlaybackError.invalidAsset }
                default:
                    if name.range(of: "^body-[0-9]{6}\\.bin\\.gz$", options: .regularExpression) != nil {
                        guard asset.contentType == "application/gzip" else { throw CloudPlaybackError.invalidAsset }
                    } else if name.range(of: "^preview-[0-9]{4}\\.jpg$", options: .regularExpression) != nil {
                        guard asset.contentType == "image/jpeg",
                              let index = Int(name.dropFirst(8).dropLast(4)), index < result.requestedFrameCount else { throw CloudPlaybackError.invalidAsset }
                    } else { throw CloudPlaybackError.invalidAsset }
                }
            }
            let expectedChunks = Set(stride(from: 0, to: result.requestedFrameCount, by: 30).map { String(format: "body-%06d.bin.gz", $0) })
            guard names.contains("faces.bin"), Set(names.filter { $0.hasPrefix("body-") }) == expectedChunks
            else { throw CloudPlaybackError.invalidResult }
        }
    }

    struct Video: Decodable, Hashable {
        let duration: Double
        let width: Int
        let height: Int
        let fps: Double
        let frameCount: Int
        let asset: CloudAssetReference
    }

    func validate(circle: String, pinned: CirclePost? = nil) throws {
        guard circleId == circle, [id, circleId, authorId, projectId].allSatisfy(CommunityValidation.validID),
              (1...60).contains(skill.count), note.count <= 500,
              authorName.count <= 120, projectTitle.count <= 120,
              previousPostId.map(CommunityValidation.validID) ?? true,
              previousPostId != id else { throw CommunityError.invalidResponse }
        if let pinned {
            guard id == pinned.id, circleId == pinned.circleId, authorId == pinned.authorId,
                  projectId == pinned.projectId, video == pinned.video, motion == pinned.motion else { throw CommunityError.invalidResponse }
        }
        try Self.validateVideo(video, author: authorId, project: projectId)
        try motion?.validate(author: authorId, projectID: projectId, video: video)
    }

    static func validateVideo(_ video: Video, author: String, project: String) throws {
        guard video.duration.isFinite, (1...60.05).contains(video.duration), video.fps == 30,
              (1...1280).contains(video.width), (1...720).contains(video.height),
              (30...1802).contains(video.frameCount),
              abs(video.duration - Double(video.frameCount) / 30) <= 0.05,
              video.asset.contentType == "video/mp4" else { throw CommunityError.invalidResponse }
        let prefix = "users/\(author)/projects/\(project)/media/"
        try video.asset.validate(prefix: prefix)
        let parts = video.asset.objectKey.dropFirst(prefix.count).split(separator: "/")
        guard parts.count == 3,
              parts[0].range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              let attempt = Int(parts[1]), (1...5).contains(attempt), parts[2] == "video.mp4"
        else { throw CloudPlaybackError.invalidAsset }
    }
}

struct CircleComment: Decodable, Identifiable, Hashable {
    let id: String
    let authorId: String
    let authorName: String
    let text: String
    let timestamp: Double?
    let createdAt: String

    func validate(duration: Double) throws {
        guard CommunityValidation.validID(id), CommunityValidation.validID(authorId),
              authorName.count <= 120, (1...500).contains(text.count),
              CommunityValidation.validTimestamp(timestamp, duration: duration)
        else { throw CommunityError.invalidResponse }
    }
}

struct CommunityPage<Item: Decodable>: Decodable {
    let items: [Item]
    let nextCursor: String?
}

enum CommunityValidation {
    static func validID(_ value: String) -> Bool {
        value.range(of: "^[a-zA-Z0-9_-]{1,128}$", options: .regularExpression) != nil
    }
    static func trimmed(_ value: String, limit: Int, required: Bool = true) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= limit, !required || !value.isEmpty else { throw CommunityError.invalidInput }
        return value
    }
    static func validTimestamp(_ value: Double?, duration: Double) -> Bool {
        guard let value else { return true }
        return duration.isFinite && value.isFinite && value >= 0 && value < duration
    }
    static func timeLabel(_ value: Double) -> String {
        guard value.isFinite, (0...86400).contains(value) else { return "—" }
        return String(format: "%d:%05.2f", Int(value) / 60, value.truncatingRemainder(dividingBy: 60))
    }
    static func message(_ error: Error) -> String {
        if error as? AccountAPIError == .notFound {
            return "Community isn't available on this server yet, or this circle or attempt is no longer shared. Refresh to check again."
        }
        if error as? AccountAPIError == .forbidden {
            return "You no longer have access to this circle. Refresh your circles to continue."
        }
        if error as? AccountAPIError == .server(409) {
            return "This circle or shared item changed, or reached its limit. Refresh and try again."
        }
        if error as? AccountAPIError == .server(429) {
            return "Community is busy. Please wait a moment and try again."
        }
        return error.localizedDescription
    }
}

enum CommunityError: LocalizedError {
    case invalidInput, invalidResponse, unavailableClip, unavailableMotion
    var errorDescription: String? {
        switch self {
        case .invalidInput: return "Check the text length and any attached video time, then try again."
        case .invalidResponse: return "The circle response couldn't be verified. Please refresh."
        case .unavailableMotion: return "The latest 3D motion isn't available for sharing. You can still share the video on its own."
        case .unavailableClip: return "Choose one of your prepared private videos. New uploads must finish preparation first."
        }
    }
}
