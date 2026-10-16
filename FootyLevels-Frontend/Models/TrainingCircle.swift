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
                  projectId == pinned.projectId, video == pinned.video else { throw CommunityError.invalidResponse }
        }
        try Self.validateVideo(video, author: authorId, project: projectId)
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
    case invalidInput, invalidResponse, unavailableClip
    var errorDescription: String? {
        switch self {
        case .invalidInput: return "Check the text length and any attached video time, then try again."
        case .invalidResponse: return "The circle response couldn't be verified. Please refresh."
        case .unavailableClip: return "Choose one of your prepared private videos. New uploads must finish preparation first."
        }
    }
}
