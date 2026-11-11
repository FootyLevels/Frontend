import Foundation

/// Lesson requests for the signed-in account. Every response is checked against that account
/// before use; asset capabilities are minted per download by `PrivatePlaybackAssets`.
@MainActor
final class CloudLessonClient {
    private let api: AuthenticatedAPIClient
    private let credentials: any APICredentials
    private let environment: ApplicationEnvironment
    let account: AccountSession

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

    // MARK: Consent

    func hasConsent() async throws -> Bool {
        try checkSession()
        let me = try JSONDecoder().decode(LessonConsent.self, from: await api.request("GET", path: "/api/me"))
        try checkSession()
        return me.consents?.lessonAi.accepted == true
    }

    func setConsent(_ accepted: Bool) async throws {
        try checkSession()
        let body = try JSONSerialization.data(withJSONObject: ["accepted": accepted])
        _ = try await api.request("PUT", path: "/api/me/consents/lesson-ai", body: body)
        try checkSession()
    }

    // MARK: Lessons

    /// Queues a lesson. Reuse `key` when retrying the same tap so a lost response can't create two.
    func create(project: CloudProject, key: String) async throws -> CloudJob {
        try checkSession(); try validID(project.id)
        guard project.ownerId == account.uid, project.state == "ready", project.preparedMedia != nil
        else { throw CloudPlaybackError.invalidResult }
        let body = try JSONSerialization.data(withJSONObject: ["inputRevision": project.inputRevision])
        let data: Data
        do {
            data = try await api.request("POST", path: "/api/projects/\(project.id)/lessons", body: body, idempotencyKey: key)
        } catch AccountAPIError.forbidden { throw CloudLessonError.consentRequired }
        catch AccountAPIError.server(422) { throw CloudLessonError.tooLong }
        catch AccountAPIError.server(429) { throw CloudLessonError.quota }
        return try checkedJob(data, project: project)
    }

    func job(_ id: String, project: CloudProject) async throws -> CloudJob {
        try checkSession(); try validID(id)
        let job = try checkedJob(await api.request("GET", path: "/api/jobs/\(id)"), project: project)
        guard job.id == id else { throw CloudPlaybackError.invalidResult }
        return job
    }

    private func checkedJob(_ data: Data, project: CloudProject) throws -> CloudJob {
        let job = try JSONDecoder().decode(CloudJob.self, from: data)
        try checkSession(); try validID(job.id)
        guard job.ownerId == account.uid, job.projectId == project.id, job.kind == "buildLesson",
              job.profileVersion == "lesson-3d-v1",
              ["queued", "running", "retrying", "succeeded", "failed", "cancelled"].contains(job.status)
        else { throw CloudPlaybackError.invalidResult }
        return job
    }

    func lessons() async throws -> [CloudLesson] {
        try checkSession()
        let list = try JSONDecoder().decode(CloudLessonList.self, from: await api.request("GET", path: "/api/lessons"))
        try checkSession()
        // A lesson that fails its checks is left out rather than shown half-verified.
        return list.items.filter { (try? $0.bundleFiles(owner: account.uid)) != nil }
    }

    func lesson(_ id: String) async throws -> CloudLesson {
        try checkSession(); try validID(id)
        let lesson = try JSONDecoder().decode(CloudLesson.self, from: await api.request("GET", path: "/api/lessons/\(id)"))
        try checkSession()
        guard lesson.id == id else { throw CloudPlaybackError.invalidResult }
        _ = try lesson.bundleFiles(owner: account.uid)
        return lesson
    }

    func assets(for lesson: CloudLesson, transport: PrivatePlaybackAssets.Transport? = nil) throws -> PrivatePlaybackAssets {
        try PrivatePlaybackAssets(api: api, credentials: credentials, environment: environment,
                                  grantPath: "/api/lessons/\(lesson.id)/assets",
                                  artifacts: try lesson.bundleFiles(owner: account.uid), transport: transport)
    }

    func delete(_ lesson: CloudLesson) async throws {
        try checkSession(); try validID(lesson.id)
        _ = try await api.request("DELETE", path: "/api/lessons/\(lesson.id)")
        try checkSession()
    }

    static let reportReasons: [(code: String, label: String)] = [
        ("wrong_move", "It names the wrong move"), ("wrong_timing", "The moments are wrong"),
        ("inaccurate", "Something else is inaccurate"), ("unsafe", "It's unsafe or inappropriate"), ("other", "Other")]

    func report(_ lesson: CloudLesson, reason: String, note: String?) async throws {
        try checkSession(); try validID(lesson.id)
        guard Self.reportReasons.contains(where: { $0.code == reason }) else { throw CloudPlaybackError.invalidResult }
        var body: [String: Any] = ["reason": reason]
        if let note, !note.isEmpty { body["note"] = String(note.prefix(500)) }
        _ = try await api.request("POST", path: "/api/lessons/\(lesson.id)/reports",
                                  body: try JSONSerialization.data(withJSONObject: body))
        try checkSession()
    }
}
