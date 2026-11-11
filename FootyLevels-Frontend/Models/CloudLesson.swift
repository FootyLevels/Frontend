import Foundation

/// A private, AI-generated lesson the backend built from one of the user's prepared videos.
/// The files are a `Lesson-<id>.bundle` (see `LessonPackage`) stored under the lesson job's prefix.
struct CloudLesson: Decodable, Identifiable, Hashable {
    let id: String
    let ownerId: String
    let projectId: String
    let jobId: String
    let inputRevision: Int
    let profileVersion: String
    let sourceAsset: CloudAssetReference
    let title: String
    let skills: [Skill]
    let authoring: Authoring
    let artifacts: [CloudAssetReference]
    let aiGenerated: Bool
    let state: String
    let completedAt: String

    struct Skill: Decodable, Hashable { let id: String; let name: String }
    struct Authoring: Decodable, Hashable {
        let model: String
        let mode: String
        let claimsRemoved: Int
    }

    static let requiredFiles: Set<String> = ["lesson.json", "analysis.json", "mesh.json", "video.mp4", "motion/sequence.json"]

    /// Bundle-relative path → file, after checking the record belongs to `owner` and every file
    /// sits in one attempt folder of this lesson's own job.
    func bundleFiles(owner: String) throws -> [String: CloudAssetReference] {
        guard id.range(of: "^[a-zA-Z0-9_-]{1,128}$", options: .regularExpression) != nil,
              ownerId == owner, jobId == id, profileVersion == "lesson-3d-v1", aiGenerated, state == "ready",
              (4...64).contains(artifacts.count), !title.isEmpty else { throw CloudPlaybackError.invalidResult }
        try sourceAsset.validate(prefix: "users/\(owner)/projects/\(projectId)/media/")
        let prefix = "users/\(owner)/projects/\(projectId)/lesson/\(jobId)/"
        var files: [String: CloudAssetReference] = [:], attempt: Substring?
        for asset in artifacts {
            try asset.validate(prefix: prefix)
            let rest = asset.objectKey.dropFirst(prefix.count)
            guard let slash = rest.firstIndex(of: "/") else { throw CloudPlaybackError.invalidAsset }
            let number = rest[..<slash], name = String(rest[rest.index(after: slash)...])
            let parts = name.split(separator: "/", omittingEmptySubsequences: false)
            guard let value = Int(number), (1...5).contains(value), attempt == nil || attempt == number,
                  parts.count == 1 || (parts.count == 2 && parts[0] == "motion"),
                  name.range(of: "^[A-Za-z0-9._/-]+$", options: .regularExpression) != nil,
                  files[name] == nil else { throw CloudPlaybackError.invalidAsset }
            attempt = number
            files[name] = asset
        }
        guard Self.requiredFiles.isSubset(of: files.keys), files["video.mp4"]?.contentType == "video/mp4"
        else { throw CloudPlaybackError.invalidResult }
        return files
    }
}

struct CloudLessonList: Decodable { let items: [CloudLesson] }

struct LessonConsent: Decodable {
    struct State: Decodable { let accepted: Bool }
    struct Consents: Decodable { let lessonAi: State }
    let consents: Consents?
}

enum CloudLessonError: LocalizedError, Equatable {
    case consentRequired, tooLong, quota, rejected, unavailable

    var errorDescription: String? {
        switch self {
        case .consentRequired: return "Allow AI lesson creation to continue."
        case .tooLong: return "Lessons are made from clips up to 20 seconds. Upload a shorter clip."
        case .quota: return "You've reached today's lesson limit. Try again tomorrow."
        case .rejected: return "We couldn't find a football skill to teach in this video. Try a clip with one player and the ball in view."
        case .unavailable: return "The lesson couldn't be created. Please try again later."
        }
    }
}
