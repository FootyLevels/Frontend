import Foundation

/// One durable draft maps to one project and one immutable source upload.
/// Relaunch/resume requests a fresh signature and asks storage for its offset.
@MainActor
final class CloudUploadCoordinator {
    let store: UploadDraftStore
    private let api: AuthenticatedAPIClient
    private let storage: PrivateTUSClient
    private let credentials: any APICredentials
    private let account: AccountSession

    init(apiURL: URL, environment: ApplicationEnvironment, credentials: any APICredentials,
         apiSession: URLSession? = nil, storageSession: URLSession? = nil, root: URL? = nil) throws {
        guard let account = credentials.currentSession else { throw AccountAPIError.signInRequired }
        self.account = account
        self.credentials = credentials
        self.api = try AuthenticatedAPIClient(baseURL: apiURL, credentials: credentials, session: apiSession)
        storage = PrivateTUSClient(environment: environment, session: storageSession)
        store = try UploadDraftStore(ownerId: account.uid, environment: environment, apiURL: apiURL, root: root)
    }

    func checkSession() throws {
        try Task.checkCancellation()
        guard credentials.currentSession == account else { throw AccountAPIError.sessionChanged }
    }

    func list(cursor: String? = nil) async throws -> CloudProjectsPage {
        try checkSession()
        let path = "/api/projects?limit=50" + (cursor.map {
            "&cursor=" + ($0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
        } ?? "")
        let page = try JSONDecoder().decode(CloudProjectsPage.self, from: await api.request("GET", path: path))
        try checkSession()
        guard page.items.allSatisfy({ $0.ownerId == account.uid }) else { throw AccountAPIError.sessionChanged }
        return page
    }

    /// Refresh a known owned recording without replacing the library's pages.
    func project(_ project: CloudProject) async throws -> CloudProject {
        try checkSession()
        guard project.ownerId == account.uid, Self.validID(project.id) else {
            throw AccountAPIError.sessionChanged
        }
        let latest = try JSONDecoder().decode(CloudProject.self,
            from: await api.request("GET", path: "/api/projects/\(project.id)"))
        try checkSession()
        guard latest.ownerId == account.uid else { throw AccountAPIError.sessionChanged }
        guard latest.id == project.id, latest.inputRevision >= project.inputRevision else {
            throw AccountAPIError.unavailable
        }
        return latest
    }

    func deletions() async throws -> [CloudDeletion] {
        struct Page: Decodable { let items: [CloudDeletion] }
        try checkSession()
        let page = try JSONDecoder().decode(Page.self, from: await api.request("GET", path: "/api/deletions"))
        try checkSession()
        guard page.items.allSatisfy({ $0.ownerId == account.uid && ["pending", "completed"].contains($0.state) })
        else { throw AccountAPIError.sessionChanged }
        return page.items
    }

    func delete(_ project: CloudProject) async throws -> CloudDeletion {
        struct Accepted: Decodable { let id: String; let state: String; let deletionId: String }
        try checkSession()
        guard project.ownerId == account.uid,
              project.id.range(of: "^[a-zA-Z0-9_-]{1,128}$", options: .regularExpression) != nil
        else { throw AccountAPIError.sessionChanged }
        let accepted = try JSONDecoder().decode(Accepted.self,
            from: await api.request("DELETE", path: "/api/projects/\(project.id)"))
        try checkSession()
        guard accepted.id == project.id, ["deleting", "deleted"].contains(accepted.state),
              accepted.deletionId.range(of: "^[a-zA-Z0-9_-]{1,128}$", options: .regularExpression) != nil
        else { throw AccountAPIError.unavailable }
        let result = try JSONDecoder().decode(CloudDeletion.self,
            from: await api.request("GET", path: "/api/deletions/\(accepted.deletionId)"))
        try checkSession()
        guard result.id == accepted.deletionId, result.ownerId == account.uid,
              result.scope == "project", result.projectId == project.id,
              ["pending", "completed"].contains(result.state) else { throw AccountAPIError.unavailable }
        return result
    }

    func upload(_ saved: UploadDraft, progress: (Double) -> Void) async throws -> CloudProject {
        try check(saved)
        var draft = saved
        if draft.discarding { throw AccountAPIError.notFound }
        let file = try store.file(draft)
        let fingerprint = try await Task.detached(priority: .utility) { try UploadDraftStore.fingerprint(file) }.value
        try checkSession()
        guard fingerprint.bytes == draft.byteSize, fingerprint.hash == draft.sha256 else { throw ClipUploadError.changedFile }

        if draft.projectId == nil {
            let body = try JSONSerialization.data(withJSONObject: ["title": draft.title, "source": draft.source,
                "label": draft.label as Any? ?? NSNull()])
            let project = try JSONDecoder().decode(CloudProject.self,
                from: await api.request("POST", path: "/api/projects", body: body, idempotencyKey: draft.id))
            try checkSession()
            guard project.ownerId == account.uid, Self.validID(project.id) else { throw AccountAPIError.sessionChanged }
            draft.projectId = project.id
            try store.save(draft)
        }
        let pid = draft.projectId!
        guard Self.validID(pid) else { throw ClipUploadError.invalidGrant }
        let input = try JSONSerialization.data(withJSONObject: ["expectedRevision": 1, "byteSize": draft.byteSize,
            "sha256": draft.sha256, "contentType": "video/mp4"])
        var grant: PrivateUploadGrant
        if let uid = draft.uploadId {
            guard Self.validID(uid) else { throw ClipUploadError.invalidGrant }
            let status = try JSONDecoder().decode(PrivateUploadGrant.self,
                from: await api.request("GET", path: "/api/uploads/\(uid)"))
            if status.status == "committed" { return try await finish(draft) }
            grant = try JSONDecoder().decode(PrivateUploadGrant.self,
                from: await api.request("POST", path: "/api/uploads/\(uid)/refresh"))
        } else {
            grant = try JSONDecoder().decode(PrivateUploadGrant.self,
                from: await api.request("POST", path: "/api/projects/\(pid)/upload-session", body: input, idempotencyKey: draft.id))
            try checkSession()
            guard Self.validID(grant.id) else { throw ClipUploadError.invalidGrant }
            draft.uploadId = grant.id
            try store.save(draft)
            if grant.status == "committed" { return try await finish(draft) }
        }
        _ = try storage.validate(grant, draft: draft)
        // A lost PATCH response is recovered with HEAD. Expired provider links are
        // recreated for the same reserved object; no new project/session is made.
        for attempt in 0...2 {
            try checkSession()
            do {
                let location: URL
                if let savedLocation = try store.location(for: draft) {
                    guard storage.validURL(savedLocation) else { throw ClipUploadError.invalidGrant }
                    location = savedLocation
                } else {
                    location = try await storage.create(grant, draft: draft, checkSession: checkSession)
                    try store.setLocation(location, for: draft)
                }
                try await storage.transfer(file: file, at: location, grant: grant, total: draft.byteSize,
                    checkSession: checkSession, progress: progress)
                return try await finish(draft)
            } catch ClipUploadError.alreadyStored {
                return try await finish(draft)
            } catch ClipUploadError.resourceMissing where attempt < 2 {
                try store.setLocation(nil, for: draft)
            } catch ClipUploadError.capabilityExpired where attempt < 2 {
                grant = try JSONDecoder().decode(PrivateUploadGrant.self,
                    from: await api.request("POST", path: "/api/uploads/\(draft.uploadId!)/refresh"))
                _ = try storage.validate(grant, draft: draft)
            }
        }
        throw ClipUploadError.capabilityExpired
    }

    private func finish(_ draft: UploadDraft) async throws -> CloudProject {
        try check(draft)
        guard let uid = draft.uploadId, Self.validID(uid) else { throw ClipUploadError.invalidGrant }
        let project = try JSONDecoder().decode(CloudProject.self,
            from: await api.request("POST", path: "/api/uploads/\(uid)/finalize"))
        try checkSession()
        guard project.ownerId == account.uid, project.id == draft.projectId, project.inputRevision == 2 else {
            throw ClipUploadError.invalidGrant
        }
        try store.remove(draft)
        return project
    }

    /// Persist deletion intent before networking. A lost response/relaunch repeats
    /// the same tombstone request; never abandons an unknown project creation.
    func discard(_ saved: UploadDraft) async throws {
        try check(saved)
        var draft = saved
        draft.discarding = true
        try store.save(draft)
        if draft.projectId == nil {
            // Recover the ID even if an earlier create response was lost.
            let body = try JSONSerialization.data(withJSONObject: ["title": draft.title, "source": draft.source,
                "label": draft.label as Any? ?? NSNull()])
            do {
                let project = try JSONDecoder().decode(CloudProject.self,
                    from: await api.request("POST", path: "/api/projects", body: body, idempotencyKey: draft.id))
                try checkSession()
                guard project.ownerId == account.uid, Self.validID(project.id) else { throw ClipUploadError.invalidGrant }
                draft.projectId = project.id
                try store.save(draft)
            } catch AccountAPIError.notFound {
                try checkSession()
                try store.remove(draft)
                return
            }
        }
        guard let pid = draft.projectId, Self.validID(pid) else { throw ClipUploadError.invalidGrant }
        do { _ = try await api.request("DELETE", path: "/api/projects/\(pid)") }
        catch AccountAPIError.notFound { /* Already removed. */ }
        try checkSession()
        try store.remove(draft)
    }

    private func check(_ draft: UploadDraft) throws {
        try checkSession()
        guard draft.ownerId == account.uid, draft.scope == store.scope else { throw AccountAPIError.sessionChanged }
    }

    private static func validID(_ text: String) -> Bool {
        text.range(of: "^[a-zA-Z0-9_-]{1,128}$", options: .regularExpression) != nil
    }
}
