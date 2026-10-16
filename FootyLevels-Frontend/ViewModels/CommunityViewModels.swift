import Foundation
import Observation

@MainActor
@Observable
final class CommunityViewModel {
    var circles: [TrainingCircle] = []
    var errorMessage: String?
    var isLoading = false
    var isWorking = false
    var client: CommunityClient?
    private var active = false
    private var epoch = UUID()

    func watch() async {
        active = true; epoch = UUID()
        let scope = epoch
        defer { if scope == epoch { clear() } }
        do {
            guard let url = ApplicationEnvironment.apiBaseURL else { throw AccountAPIError.notConfigured }
            client = try CommunityClient(apiURL: url, credentials: FirebaseAPICredentials.shared, environment: .current)
            await refresh()
            while !Task.isCancelled && active && scope == epoch {
                try await Task.sleep(for: .seconds(1))
                try client?.checkSession()
            }
        } catch is CancellationError {} catch {
            if active, scope == epoch { errorMessage = CommunityValidation.message(error) }
        }
    }

    func refresh() async {
        guard active, let client, !isLoading else { return }
        let scope = epoch
        isLoading = true
        defer { if scope == epoch { isLoading = false } }
        do {
            let circles = try await client.circles()
            try client.checkSession(); guard active, scope == epoch else { return }
            self.circles = circles; errorMessage = nil
        } catch { if active, scope == epoch { handle(error) } }
    }

    func create(name: String, description: String) async -> Bool {
        await mutate { try await $0.create(name: name, description: description) }
    }
    func join(code: String) async -> Bool { await mutate { try await $0.join(code: code) } }

    private func mutate(_ operation: (CommunityClient) async throws -> TrainingCircle) async -> Bool {
        guard active, let client, !isWorking else { return false }
        let scope = epoch
        isWorking = true; errorMessage = nil
        defer { if scope == epoch { isWorking = false } }
        do {
            let circle = try await operation(client)
            try client.checkSession(); guard active, scope == epoch else { return false }
            circles.removeAll { $0.id == circle.id }; circles.insert(circle, at: 0)
            return true
        } catch { if active, scope == epoch { handle(error) }; return false }
    }
    func stop() { active = false; epoch = UUID(); isLoading = false; isWorking = false; clear() }
    private func clear() { circles = []; client = nil }
    private func handle(_ error: Error) {
        if error as? AccountAPIError == .sessionChanged || error as? AccountAPIError == .signInRequired { clear() }
        errorMessage = CommunityValidation.message(error)
    }
}

@MainActor
@Observable
final class CircleDetailViewModel {
    var circle: TrainingCircle
    var posts: [CirclePost] = []
    var nextCursor: String?
    var errorMessage: String?
    var invite: CircleInvite?
    var isLoading = false
    var isWorking = false
    var isRemoved = false
    var hasAccess = true
    let client: CommunityClient
    private var active = true
    private let circleID: String
    private var lastValidated: Date?
    private var membershipTask: Task<Void, Never>?
    private var epoch = UUID()
    var isOwner: Bool { circle.ownerId == client.account.uid }

    init(circle: TrainingCircle, client: CommunityClient) { self.circle = circle; self.circleID = circle.id; self.client = client }

    func watch() async {
        active = true; epoch = UUID()
        let scope = epoch
        await refresh()
        do {
            while !Task.isCancelled && active && scope == epoch {
                try await Task.sleep(for: .seconds(1)); try client.checkSession()
                if hasAccess, let lastValidated, Date().timeIntervalSince(lastValidated) >= 45 { revokeView() }
                if membershipTask == nil, lastValidated == nil || Date().timeIntervalSince(lastValidated!) >= 15 {
                    membershipTask = Task { [weak self] in
                        guard let self else { return }
                        defer { if scope == self.epoch { self.membershipTask = nil } }
                        do {
                            let latest = try await self.client.circle(self.circleID)
                            try self.client.checkSession()
                            guard self.active, scope == self.epoch else { return }
                            self.circle = latest; self.hasAccess = true; self.lastValidated = Date()
                        } catch { if self.active, scope == self.epoch { self.fail(error); self.lastValidated = Date() } }
                    }
                }
            }
        } catch is CancellationError {} catch { if active, scope == epoch { fail(error) } }
    }
    func stop() { active = false; epoch = UUID(); membershipTask?.cancel(); membershipTask = nil; isLoading = false; isWorking = false; revokeView() }

    func refresh(more: Bool = false) async {
        guard active, !isLoading, !isRemoved else { return }
        let scope = epoch
        isLoading = true
        defer { if scope == epoch { isLoading = false } }
        do {
            let latest = try await client.circle(circleID)
            try client.checkSession(); guard active, scope == epoch else { return }
            circle = latest; hasAccess = true; lastValidated = Date()
            let page = try await client.posts(circle: circleID, cursor: more ? nextCursor : nil)
            try requireActive(scope)
            circle = latest
            posts = more ? posts + page.items.filter { item in !posts.contains(where: { $0.id == item.id }) } : page.items
            nextCursor = page.nextCursor; errorMessage = nil
        } catch { if active, scope == epoch { fail(error) } }
    }

    func generateInvite() async {
        await mutate { scope in
            let invite = try await self.client.invite(circle: self.circleID)
            try self.requireActive(scope); self.invite = invite
        }
    }
    func removeMember(_ member: TrainingCircle.Member) async {
        await mutate { scope in
            try await self.client.removeMember(circle: self.circleID, uid: member.uid)
            try self.requireActive(scope)
            if member.uid == self.client.account.uid { self.isRemoved = true; self.posts = []; self.invite = nil }
            else {
                self.invite = nil
                let circle = try await self.client.circle(self.circleID)
                try self.requireActive(scope); self.circle = circle
            }
        }
    }
    func delete() async {
        await mutate { scope in
            try await self.client.deleteCircle(self.circleID)
            try self.requireActive(scope)
            self.isRemoved = true; self.posts = []; self.invite = nil
        }
    }
    func removePost(_ post: CirclePost) async {
        await mutate { scope in
            try await self.client.removePost(post)
            try self.requireActive(scope)
            self.posts.removeAll { $0.id == post.id }
        }
    }
    func didShare(_ post: CirclePost) { posts.removeAll { $0.id == post.id }; posts.insert(post, at: 0) }
    private func mutate(_ operation: (UUID) async throws -> Void) async {
        guard active, !isWorking, !isRemoved, hasAccess else { return }
        let scope = epoch
        isWorking = true; errorMessage = nil
        defer { if scope == epoch { isWorking = false } }
        do { try await operation(scope); try requireActive(scope) }
        catch { if active, scope == epoch { fail(error) } }
    }
    private func fail(_ error: Error) {
        revokeView()
        errorMessage = CommunityValidation.message(error)
    }
    private func revokeView() {
        posts = []; invite = nil; hasAccess = false; nextCursor = nil
        circle = TrainingCircle(id: circleID, name: "Circle unavailable", description: "", ownerId: "", createdAt: "", memberCount: 0, members: [])
    }
    private func requireActive(_ scope: UUID) throws {
        try client.checkSession()
        guard active, scope == epoch else { throw CancellationError() }
    }
}

@MainActor
@Observable
final class CircleShareViewModel {
    var projects: [CloudProject] = []
    var nextCursor: String?
    var isLoading = false
    var isWorking = false
    var errorMessage: String?
    private var requestKey = UUID().uuidString
    private var requestPayload: [String]?
    private let client: CommunityClient
    private let circleID: String
    private let previous: CirclePost?
    private var active = true
    init(client: CommunityClient, circleID: String, previous: CirclePost?) {
        self.client = client; self.circleID = circleID; self.previous = previous
    }
    func load(more: Bool = false) async {
        guard active, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await client.preparedProjects(cursor: more ? nextCursor : nil)
            let ready = page.items.filter { $0.state == "ready" && $0.preparedMedia != nil }
            try client.checkSession(); guard active else { return }
            projects = more ? projects + ready.filter { p in !projects.contains(where: { $0.id == p.id }) } : ready
            nextCursor = page.nextCursor; errorMessage = nil
        } catch { errorMessage = CommunityValidation.message(error) }
    }
    func share(project: CloudProject, skill: String, note: String) async -> CirclePost? {
        guard active, !isWorking else { return nil }
        isWorking = true; errorMessage = nil
        defer { isWorking = false }
        do {
            let payload = [project.id, skill.trimmingCharacters(in: .whitespacesAndNewlines), note.trimmingCharacters(in: .whitespacesAndNewlines)]
            if let requestPayload, requestPayload != payload { requestKey = UUID().uuidString }
            requestPayload = payload
            let post = try await client.share(circle: circleID, project: project, skill: skill, note: note,
                previous: previous, idempotencyKey: requestKey)
            try client.checkSession(); guard active else { return nil }
            requestKey = UUID().uuidString
            return post
        } catch { errorMessage = CommunityValidation.message(error); return nil }
    }
    func stop() { active = false; projects = [] }
}

@MainActor
@Observable
final class CirclePostViewModel {
    let post: CirclePost
    let client: CommunityClient
    var comments: [CircleComment] = []
    var nextCursor: String?
    var playback: PlaybackController?
    var errorMessage: String?
    var isLoading = false
    var isLoadingComments = false
    var isWorking = false
    var isRemoved = false
    private(set) var hasAccess = false
    var attachedTime: Double?
    var commentText = ""
    private var commentKey = UUID().uuidString
    private var commentPayload: String?
    private var assets: PrivatePlaybackAssets?
    private var epoch = UUID()
    private var active = false
    private var lastValidated: Date?
    private var verificationTask: Task<Void, Never>?
    private let playbackTransport: PrivatePlaybackAssets.Transport?

    init(post: CirclePost, client: CommunityClient, playbackTransport: PrivatePlaybackAssets.Transport? = nil) {
        self.post = post; self.client = client; self.playbackTransport = playbackTransport
    }

    func watch() async {
        active = true; epoch = UUID()
        let scope = epoch
        await refresh()
        do {
            while !Task.isCancelled && active && scope == epoch {
                try await Task.sleep(for: .seconds(1))
                try requireActive(scope)
                if playback != nil, let lastValidated, Date().timeIntervalSince(lastValidated) >= 45 {
                    closePlayback(); errorMessage = "Circle access couldn't be refreshed. Reload the shared video to continue."
                }
                if verificationTask == nil, lastValidated == nil || Date().timeIntervalSince(lastValidated!) >= 15 {
                    verificationTask = Task { [weak self] in
                        guard let self else { return }
                        defer { if scope == self.epoch { self.verificationTask = nil } }
                        await self.verifyPlayback(scope)
                    }
                }
            }
        } catch is CancellationError {} catch { if active, scope == epoch { fail(error) } }
        if scope == epoch { stop() }
    }

    func refresh() async {
        guard active, !isLoading else { return }
        let scope = epoch
        await verifyPlayback(scope)
        await loadComments()
    }

    private func verifyPlayback(_ scope: UUID) async {
        guard active, !isLoading, !isRemoved else { return }
        isLoading = true
        defer { if scope == epoch { isLoading = false } }
        do {
            _ = try await client.post(circle: post.circleId, id: post.id, pinned: post)
            try requireActive(scope)
            if playback == nil {
                let source = try await client.playbackAssets(post, transport: playbackTransport)
                do {
                    let file = try await source.localFile(file: "video")
                    _ = try await client.post(circle: post.circleId, id: post.id, pinned: post)
                    try requireActive(scope)
                    lastValidated = Date()
                    assets = source
                    playback = PlaybackController(url: file, duration: post.video.duration)
                } catch { source.close(); throw error }
            }
            hasAccess = true
            lastValidated = Date()
            errorMessage = nil
        } catch {
            guard active, scope == epoch else { return }
            // Fail closed: a failed refresh stops downloaded playback immediately.
            closePlayback(); lastValidated = Date(); fail(error)
        }
    }

    func loadComments(more: Bool = false) async {
        guard active, !isLoadingComments, !isRemoved else { return }
        let scope = epoch
        isLoadingComments = true
        defer { if scope == epoch { isLoadingComments = false } }
        do {
            let page = try await client.comments(post, cursor: more ? nextCursor : nil)
            try requireActive(scope)
            comments = more ? comments + page.items.filter { item in !comments.contains(where: { $0.id == item.id }) } : page.items
            nextCursor = page.nextCursor
        } catch { if active, scope == epoch { fail(error) } }
    }

    func attachCurrentTime() {
        guard let playback else { return }
        playback.pause()
        let time = playback.currentTime
        if CommunityValidation.validTimestamp(time, duration: post.video.duration) { attachedTime = time }
    }
    func seek(comment: CircleComment) {
        guard active, let value = comment.timestamp,
              CommunityValidation.validTimestamp(value, duration: post.video.duration) else { return }
        playback?.pause(); playback?.seek(to: value)
    }
    func sendComment() async -> Bool {
        guard active, !isWorking, !isRemoved else { return false }
        let scope = epoch
        isWorking = true; errorMessage = nil
        defer { if scope == epoch { isWorking = false } }
        do {
            let payload = commentText.trimmingCharacters(in: .whitespacesAndNewlines) + "\u{0}" + (attachedTime.map { String($0) } ?? "none")
            if let commentPayload, commentPayload != payload { commentKey = UUID().uuidString }
            commentPayload = payload
            let item = try await client.comment(post, text: commentText, timestamp: attachedTime, idempotencyKey: commentKey)
            try requireActive(scope)
            comments.removeAll { $0.id == item.id }; comments.append(item)
            commentText = ""; attachedTime = nil; commentKey = UUID().uuidString
            return true
        } catch { if active, scope == epoch { fail(error) }; return false }
    }
    func removeComment(_ item: CircleComment) async {
        guard active, !isWorking, !isRemoved else { return }
        let scope = epoch
        isWorking = true
        defer { if scope == epoch { isWorking = false } }
        do {
            try await client.removeComment(item, post: post)
            try requireActive(scope); comments.removeAll { $0.id == item.id }
        } catch { if active, scope == epoch { fail(error) } }
    }
    func stop() {
        active = false; epoch = UUID(); verificationTask?.cancel(); verificationTask = nil; closePlayback()
        isLoading = false; isLoadingComments = false; isWorking = false
        comments = []; attachedTime = nil; commentText = ""; lastValidated = nil
    }
    private func closePlayback() {
        playback?.teardown(); playback = nil; assets?.close(); assets = nil
        hasAccess = false; comments = []; attachedTime = nil
    }
    private func requireActive(_ scope: UUID) throws {
        try client.checkSession()
        guard active, scope == epoch else { throw CancellationError() }
    }
    private func fail(_ error: Error) {
        if let error = error as? AccountAPIError, [.forbidden, .notFound, .sessionChanged, .signInRequired].contains(error) {
            comments = []; closePlayback()
        }
        errorMessage = CommunityValidation.message(error)
    }

    func removePost() async -> Bool {
        guard active, !isWorking else { return false }
        let scope = epoch
        isWorking = true
        defer { if scope == epoch { isWorking = false } }
        do {
            try await client.removePost(post); try requireActive(scope)
            isRemoved = true; stop(); return true
        } catch { if active, scope == epoch { fail(error) }; return false }
    }
}
