import Foundation

@MainActor
final class CloudReconstructionClient {
    private let api: AuthenticatedAPIClient
    private let credentials: any APICredentials
    private let account: AccountSession
    private let environment: ApplicationEnvironment

    init(apiURL: URL, credentials: any APICredentials, environment: ApplicationEnvironment,
         apiSession: URLSession? = nil) throws {
        guard let account = credentials.currentSession else { throw AccountAPIError.signInRequired }
        self.account = account; self.credentials = credentials; self.environment = environment
        api = try AuthenticatedAPIClient(baseURL: apiURL, credentials: credentials, session: apiSession)
    }

    func checkSession() throws {
        try Task.checkCancellation()
        guard credentials.currentSession == account else { throw AccountAPIError.sessionChanged }
    }
    private func validID(_ id: String) throws {
        guard id.range(of: "^[a-zA-Z0-9_-]{1,128}$", options: .regularExpression) != nil else { throw CloudPlaybackError.invalidResult }
    }

    func project(_ id: String) async throws -> CloudProject {
        try checkSession(); try validID(id)
        let result = try JSONDecoder().decode(CloudProject.self, from: await api.request("GET", path: "/api/projects/\(id)"))
        try checkSession()
        guard result.ownerId == account.uid, result.id == id else { throw CloudPlaybackError.invalidResult }
        if result.preparedMedia != nil { _ = try preparedMapping(project: result) }
        return result
    }

    func job(_ id: String, project: CloudProject) async throws -> CloudJob {
        try validID(id)
        return try await jobResponse("GET", path: "/api/jobs/\(id)", project: project, expectedID: id)
    }
    func cancel(_ id: String, project: CloudProject) async throws -> CloudJob {
        try validID(id)
        return try await jobResponse("POST", path: "/api/jobs/\(id)/cancel", project: project, expectedID: id)
    }
    func generateMotion(project: CloudProject, startFrame: Int, endFrame: Int) async throws -> CloudJob {
        try checkSession(); try validID(project.id)
        guard project.ownerId == account.uid, project.state == "ready", let media = project.preparedMedia,
              media.profileVersion == "media-720p30-v1", media.fps == 30,
              startFrame >= 0, endFrame <= media.frameCount, (30...300).contains(endFrame - startFrame)
        else { throw CloudPlaybackError.invalidResult }
        let body = try JSONSerialization.data(withJSONObject: ["inputRevision": project.inputRevision,
            "segment": ["startFrame": startFrame, "endFrame": endFrame]])
        return try await jobResponse("POST", path: "/api/projects/\(project.id)/reconstructions/motion", body: body, project: project)
    }
    private func jobResponse(_ method: String, path: String, body: Data? = nil,
                             project: CloudProject, expectedID: String? = nil) async throws -> CloudJob {
        try checkSession()
        let result = try JSONDecoder().decode(CloudJob.self, from: await api.request(method, path: path, body: body))
        try checkSession(); try validID(result.id)
        guard result.ownerId == account.uid, result.projectId == project.id, result.inputRevision == project.inputRevision,
              expectedID == nil || result.id == expectedID,
              ["prepareMedia", "reconstructKeyframes", "reconstructMotion"].contains(result.kind),
              ["queued", "running", "retrying", "succeeded", "partial", "failed", "cancelled"].contains(result.status)
        else { throw CloudPlaybackError.invalidResult }
        return result
    }

    func motionResult(_ id: String, project: CloudProject) async throws -> (CloudReconstruction, CloudJob, PrivatePlaybackAssets) {
        try checkSession(); try validID(id)
        let result = try JSONDecoder().decode(CloudReconstruction.self,
            from: await api.request("GET", path: "/api/reconstructions/\(id)"))
        try checkSession()
        guard result.id == id else { throw CloudPlaybackError.invalidResult }
        try result.validateMotion(owner: account.uid, project: project)
        let job = try await self.job(result.jobId, project: project)
        guard job.reconstructionId == result.id, ["succeeded", "partial"].contains(job.status),
              job.kind == "reconstructMotion", job.sourceAsset == result.sourceAsset,
              job.profileVersion == result.profileVersion, let segment = job.motionSegment,
              segment.startFrame >= 0, segment.endFrame <= project.preparedMedia!.frameCount,
              segment.endFrame - segment.startFrame == result.requestedFrameCount,
              job.attemptCount > 0 else { throw CloudPlaybackError.invalidResult }
        let mapping = Dictionary(uniqueKeysWithValues: result.artifacts.map { ($0.objectKey.split(separator: "/").last!.description, $0) })
        return (result, job, try PrivatePlaybackAssets(api: api, credentials: credentials, environment: environment,
            grantPath: "/api/reconstructions/\(id)/assets", artifacts: mapping))
    }

    func preparedAssets(project: CloudProject) throws -> PrivatePlaybackAssets {
        let mapping = try preparedMapping(project: project)
        return try PrivatePlaybackAssets(api: api, credentials: credentials, environment: environment,
            grantPath: "/api/projects/\(project.id)/media-assets", artifacts: mapping)
    }

    private func preparedMapping(project: CloudProject) throws -> [String: CloudAssetReference] {
        try checkSession(); try validID(project.id)
        guard project.ownerId == account.uid, project.state == "ready", let media = project.preparedMedia,
              media.profileVersion == "media-720p30-v1", media.fps == 30, (30...1802).contains(media.frameCount),
              media.duration.isFinite, (1...60.05).contains(media.duration),
              (1...1280).contains(media.width), (1...720).contains(media.height),
              (1...6).contains(media.previews.count), media.video.contentType == "video/mp4"
        else { throw CloudPlaybackError.invalidResult }
        let prefix = "users/\(account.uid)/projects/\(project.id)/media/"
        var mapping = ["video": media.video]
        for (i, preview) in media.previews.enumerated() {
            guard preview.timestamp.isFinite, preview.frameIndex >= 0, preview.frameIndex < media.frameCount,
                  abs(preview.timestamp - Double(preview.frameIndex)/30) < 0.000001,
                  preview.asset.contentType == "image/jpeg" else { throw CloudPlaybackError.invalidAsset }
            mapping[String(format: "preview-%02d", i)] = preview.asset
        }
        var parent: String?
        for (name, asset) in mapping {
            try asset.validate(prefix: prefix)
            let suffix = asset.objectKey.dropFirst(prefix.count).split(separator: "/")
            guard suffix.count == 3, suffix[0].range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                  let attempt = Int(suffix[1]), (1...5).contains(attempt),
                  suffix[2] == (name == "video" ? "video.mp4" : name + ".jpg")
            else { throw CloudPlaybackError.invalidAsset }
            let value = suffix.prefix(2).joined(separator: "/")
            guard parent == nil || parent == value else { throw CloudPlaybackError.invalidAsset }
            parent = value
        }
        return mapping
    }
}
