import Foundation
import Observation

/// "Create lesson" for one prepared project: consent (asked once per account), the lesson job,
/// and the finished lesson downloaded into `UserLessonStore` as a library entry.
@MainActor
@Observable
final class CloudLessonViewModel {
    enum Phase: Equatable {
        case idle, needsConsent, submitting, building(String), downloading, ready, failed(String)
    }

    private(set) var project: CloudProject
    private(set) var phase: Phase = .idle
    private(set) var job: CloudJob?
    private(set) var lesson: CloudLesson?
    private(set) var entry: LessonLibrary.Entry?
    var showingConsent = false
    private(set) var client: CloudLessonClient?
    private(set) var store: UserLessonStore?
    private var requestKey: String?
    private var stopped = false
    private let makeClient: @MainActor () throws -> CloudLessonClient

    init(project: CloudProject, makeClient: (@MainActor () throws -> CloudLessonClient)? = nil) {
        self.project = project
        self.makeClient = makeClient ?? {
            guard let url = ApplicationEnvironment.apiBaseURL else { throw AccountAPIError.notConfigured }
            return try CloudLessonClient(apiURL: url, credentials: FirebaseAPICredentials.shared, environment: .current)
        }
    }

    var canCreate: Bool {
        guard project.state == "ready", project.preparedMedia != nil, project.activeJobId == nil else { return false }
        switch phase {
        case .idle, .needsConsent, .failed: return true
        default: return false
        }
    }

    /// Called by the project screen with each refreshed project.
    func update(project latest: CloudProject) {
        guard latest.id == project.id else { return }
        project = latest
    }

    private func ready() throws -> (CloudLessonClient, UserLessonStore) {
        if let client, let store { try client.checkSession(); return (client, store) }
        let client = try makeClient()
        let store = try UserLessonStore(uid: client.account.uid)
        self.client = client; self.store = store
        return (client, store)
    }

    /// Polls an active lesson job, or opens the project's latest lesson, every 15 s.
    func watch() async {
        stopped = false
        while !Task.isCancelled && !stopped {
            await refresh()
            if case .ready = phase { return }
            try? await Task.sleep(for: .seconds(15))
        }
    }

    func refresh() async {
        do {
            let (client, _) = try ready()
            if let job, job.isActive {
                self.job = try await client.job(job.id, project: project)
            } else if let active = project.activeJobId, job == nil {
                // The active job may be a reconstruction; only a lesson job is ours to show.
                if let found = try? await client.job(active, project: project) { job = found }
            }
            if let job {
                if job.isActive { phase = .building(job.statusText); return }
                if job.status == "succeeded", let id = job.lessonId { try await open(id); return }
                if job.status == "failed" || job.status == "cancelled" {
                    phase = .failed(job.errorCode == "lesson_rejected" ? CloudLessonError.rejected.localizedDescription
                                                                       : job.statusText)
                    return
                }
            }
            if let id = project.latestLessonId, entry == nil { try await open(id) }
        } catch is CancellationError {
        } catch {
            if case .ready = phase { return }
            phase = .failed(error.localizedDescription)
        }
    }

    func createLesson() {
        Task {
            do {
                let (client, _) = try ready()
                phase = .submitting
                guard try await client.hasConsent() else { phase = .needsConsent; showingConsent = true; return }
                try await submit(client)
            } catch { phase = .failed(error.localizedDescription) }
        }
    }

    func answerConsent(_ accepted: Bool) {
        showingConsent = false
        guard accepted else { phase = .idle; return }
        Task {
            do {
                let (client, _) = try ready()
                phase = .submitting
                try await client.setConsent(true)
                try await submit(client)
            } catch { phase = .failed(error.localizedDescription) }
        }
    }

    private func submit(_ client: CloudLessonClient) async throws {
        // One key per tap, reused if this tap's response is lost and the user retries.
        let key = requestKey ?? "lesson-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        requestKey = key
        do {
            job = try await client.create(project: project, key: key)
        } catch CloudLessonError.consentRequired {
            phase = .needsConsent; showingConsent = true; return
        }
        requestKey = nil
        phase = .building(job?.statusText ?? "Waiting for the lesson builder")
        await watch()
    }

    private func open(_ id: String) async throws {
        let (client, store) = try ready()
        // The record is fetched even for a cached copy: it proves the lesson still exists.
        let lesson = try await client.lesson(id)
        if let cached = store.entry(for: id) {
            self.lesson = lesson; entry = cached; phase = .ready; return
        }
        phase = .downloading
        let assets = try client.assets(for: lesson)
        defer { assets.close() }
        let url = try await store.install(lesson, assets: assets)
        guard let entry = LessonLibrary.entry(at: url) else { throw CloudPlaybackError.invalidResult }
        self.lesson = lesson; self.entry = entry; phase = .ready
    }

    func stop() { stopped = true }
}
