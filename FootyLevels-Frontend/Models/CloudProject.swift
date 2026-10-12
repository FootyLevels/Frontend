import Foundation

/// Account records deliberately stay separate from the legacy local workspace.
struct CloudProject: Decodable, Identifiable, Hashable {
    let id: String
    let ownerId: String
    let title: String
    let label: String?
    let state: String
    let inputRevision: Int
    let activeJobId: String?
    let latestReconstructionId: String?
    let preparedMedia: CloudPreparedMedia?

    var statusText: String {
        switch state {
        case "uploading": return "Upload not finished"
        case "preparing": return "Uploaded · waiting for media preparation"
        case "ready": return "Video ready"
        case "rejected": return "Video needs attention"
        default: return "Unavailable"
        }
    }
}

struct CloudProjectsPage: Decodable {
    let items: [CloudProject]
    let nextCursor: String?
}

/// These capabilities exist only in memory; never encode them into draft JSON.
struct PrivateUploadGrant: Decodable {
    let id: String
    let status: String
    let `protocol`: String?
    let endpoint: String?
    let headers: [String: String]?
    let metadata: [String: String]?
    let expectedBytes: Int?
    let chunkSize: Int?
}

enum ClipUploadError: LocalizedError, Equatable {
    case invalidVideo, invalidTrim, tooLarge, changedFile, invalidGrant, invalidOffset
    case capabilityExpired, resourceMissing, alreadyStored, storage(Int), localStorage

    var errorDescription: String? {
        switch self {
        case .invalidVideo: return "Choose a readable video with a video track."
        case .invalidTrim: return "Choose a clip between 1 and 60 seconds."
        case .tooLarge: return "The prepared clip is over 50 MB. Try a shorter clip."
        case .changedFile: return "The saved clip has changed. Discard this draft and import it again."
        case .invalidGrant, .invalidOffset: return "The upload response couldn't be verified. Your draft is saved."
        case .capabilityExpired: return "The upload link expired. Resume to request a new one."
        case .resourceMissing: return "The interrupted upload expired. Resume to restart its transfer."
        case .alreadyStored: return "The file is already stored. Verifying the upload…"
        case .storage(let status) where status == 413: return "The storage service rejected the clip size. Try a shorter clip."
        case .storage: return "Storage couldn't complete the upload. Your draft is saved; please resume later."
        case .localStorage: return "The clip couldn't be saved on this device. Check available storage and try again."
        }
    }
}
