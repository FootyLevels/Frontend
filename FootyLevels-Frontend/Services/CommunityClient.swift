import Foundation

/// An instance belongs to one sign-in generation; late responses never cross accounts.
@MainActor
final class CommunityClient {
    let account: AccountSession
    private let api: AuthenticatedAPIClient
    private let credentials: any APICredentials
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

    func circles() async throws -> [TrainingCircle] {
        struct Page: Decodable { let items: [TrainingCircle] }
        let page: Page = try await send("GET", path: "/api/circles")
        for item in page.items { try item.validate(member: account.uid) }
        guard Set(page.items.map(\.id)).count == page.items.count else { throw CommunityError.invalidResponse }
        return page.items
    }

    func circle(_ id: String) async throws -> TrainingCircle {
        let path = try circlePath(id)
        let item: TrainingCircle = try await send("GET", path: path)
        try item.validate(member: account.uid)
        guard item.id == id else { throw CommunityError.invalidResponse }
        return item
    }

    func create(name: String, description: String) async throws -> TrainingCircle {
        let body = ["name": try CommunityValidation.trimmed(name, limit: 80),
                    "description": try CommunityValidation.trimmed(description, limit: 240, required: false)]
        let item: TrainingCircle = try await send("POST", path: "/api/circles", body: body)
        try item.validate(member: account.uid)
        guard item.ownerId == account.uid else { throw CommunityError.invalidResponse }
        return item
    }

    func join(code: String) async throws -> TrainingCircle {
        let code = try CommunityValidation.trimmed(code, limit: 128)
        guard code.range(of: "^[a-zA-Z0-9_-]{43}$", options: .regularExpression) != nil else { throw CommunityError.invalidInput }
        let item: TrainingCircle = try await send("POST", path: "/api/circles/join", body: ["code": code])
        try item.validate(member: account.uid)
        return item
    }

    func invite(circle id: String) async throws -> CircleInvite {
        let item: CircleInvite = try await send("POST", path: try circlePath(id) + "/invite")
        let expiry = ISO8601DateFormatter.fractional.date(from: item.expiresAt) ?? ISO8601DateFormatter().date(from: item.expiresAt)
        guard item.code.range(of: "^[a-zA-Z0-9_-]{43}$", options: .regularExpression) != nil,
              let expiry, expiry > Date(), expiry < Date().addingTimeInterval(8 * 86400)
        else { throw CommunityError.invalidResponse }
        return item
    }

    func removeMember(circle id: String, uid: String) async throws {
        try validID(uid)
        try await remove(path: try circlePath(id) + "/members/\(uid)", expected: "removed")
    }

    func deleteCircle(_ id: String) async throws {
        try await remove(path: circlePath(id), expected: "deleted")
    }

    func posts(circle id: String, cursor: String? = nil) async throws -> CommunityPage<CirclePost> {
        let page: CommunityPage<CirclePost> = try await send("GET", path: try circlePath(id) + "/posts" + query(limit: 20, cursor: cursor))
        for post in page.items { try post.validate(circle: id) }
        try validatePage(page)
        return page
    }

    func post(circle id: String, id postID: String, pinned: CirclePost? = nil) async throws -> CirclePost {
        let item: CirclePost = try await send("GET", path: try postPath(id, postID))
        try item.validate(circle: id, pinned: pinned)
        guard item.id == postID else { throw CommunityError.invalidResponse }
        return item
    }

    func share(circle id: String, project: CloudProject, skill: String, note: String,
               previous: CirclePost?, idempotencyKey: String) async throws -> CirclePost {
        try checkSession(); try validID(project.id)
        guard project.ownerId == account.uid, project.state == "ready", let media = project.preparedMedia,
              media.profileVersion == "media-720p30-v1" else { throw CommunityError.unavailableClip }
        let video = CirclePost.Video(duration: media.duration, width: media.width, height: media.height,
            fps: media.fps, frameCount: media.frameCount, asset: media.video)
        try CirclePost.validateVideo(video, author: account.uid, project: project.id)
        var body: [String: Any] = ["projectId": project.id,
            "skill": try CommunityValidation.trimmed(skill, limit: 60),
            "note": try CommunityValidation.trimmed(note, limit: 500, required: false)]
        if let previous {
            try previous.validate(circle: id)
            guard previous.authorId == account.uid else { throw CommunityError.invalidInput }
            body["previousPostId"] = previous.id
        }
        let item: CirclePost = try await send("POST", path: try circlePath(id) + "/posts", body: body, key: idempotencyKey)
        try item.validate(circle: id)
        guard item.authorId == account.uid, item.projectId == project.id, item.video == video,
              item.previousPostId == previous?.id else { throw CommunityError.invalidResponse }
        return item
    }

    func removePost(_ post: CirclePost) async throws {
        try post.validate(circle: post.circleId)
        try await remove(path: postPath(post.circleId, post.id), expected: "removed")
    }

    func comments(_ post: CirclePost, cursor: String? = nil) async throws -> CommunityPage<CircleComment> {
        let page: CommunityPage<CircleComment> = try await send("GET", path: try postPath(post.circleId, post.id) + "/comments" + query(limit: 30, cursor: cursor))
        for comment in page.items { try comment.validate(duration: post.video.duration) }
        try validatePage(page)
        return page
    }

    func comment(_ post: CirclePost, text: String, timestamp: Double?, idempotencyKey: String) async throws -> CircleComment {
        guard CommunityValidation.validTimestamp(timestamp, duration: post.video.duration) else { throw CommunityError.invalidInput }
        var body: [String: Any] = ["text": try CommunityValidation.trimmed(text, limit: 500)]
        if let timestamp { body["timestamp"] = timestamp }
        let item: CircleComment = try await send("POST", path: try postPath(post.circleId, post.id) + "/comments", body: body, key: idempotencyKey)
        try item.validate(duration: post.video.duration)
        guard item.authorId == account.uid, item.timestamp == timestamp else { throw CommunityError.invalidResponse }
        return item
    }

    func removeComment(_ comment: CircleComment, post: CirclePost) async throws {
        try validID(comment.id)
        try await remove(path: try postPath(post.circleId, post.id) + "/comments/\(comment.id)", expected: "removed")
    }

    func preparedProjects(cursor: String? = nil) async throws -> CloudProjectsPage {
        let page: CloudProjectsPage = try await send("GET", path: "/api/projects" + query(limit: 50, cursor: cursor))
        guard page.items.allSatisfy({ $0.ownerId == account.uid && CommunityValidation.validID($0.id) }) else { throw CommunityError.invalidResponse }
        for project in page.items {
            if let media = project.preparedMedia {
                guard media.profileVersion == "media-720p30-v1" else { throw CommunityError.invalidResponse }
                try CirclePost.validateVideo(.init(duration: media.duration, width: media.width, height: media.height,
                    fps: media.fps, frameCount: media.frameCount, asset: media.video), author: account.uid, project: project.id)
            }
        }
        return page
    }

    /// Membership is revalidated before every new local file. Grant refresh itself
    /// also calls an authenticated membership-checking endpoint.
    func playbackAssets(_ post: CirclePost, transport: PrivatePlaybackAssets.Transport? = nil) async throws -> PrivatePlaybackAssets {
        _ = try await self.post(circle: post.circleId, id: post.id, pinned: post)
        try checkSession()
        return try PrivatePlaybackAssets(api: api, credentials: credentials, environment: environment,
            grantPath: try postPath(post.circleId, post.id) + "/assets", artifacts: ["video": post.video.asset],
            maximumGrantLifetime: 61, transport: transport)
    }

    private func send<T: Decodable>(_ method: String, path: String, body: [String: Any]? = nil, key: String? = nil) async throws -> T {
        try checkSession()
        let bytes = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        let data = try await api.request(method, path: path, body: bytes, idempotencyKey: key)
        try checkSession()
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func remove(path: String, expected: String) async throws {
        struct Result: Decodable { let state: String }
        let item: Result = try await send("DELETE", path: path)
        guard item.state == expected else { throw CommunityError.invalidResponse }
    }
    private func circlePath(_ id: String) throws -> String { try validID(id); return "/api/circles/\(id)" }
    private func postPath(_ circle: String, _ post: String) throws -> String { try validID(post); return try circlePath(circle) + "/posts/\(post)" }
    private func validID(_ value: String) throws { guard CommunityValidation.validID(value) else { throw CommunityError.invalidInput } }
    private func query(limit: Int, cursor: String?) -> String {
        "?limit=\(limit)" + (cursor.map { "&cursor=" + ($0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "") } ?? "")
    }
    private func validatePage<T>(_ page: CommunityPage<T>) throws {
        guard page.items.count <= 50, page.nextCursor.map({ !$0.isEmpty && $0.utf8.count <= 4096 }) ?? true else { throw CommunityError.invalidResponse }
    }
}
