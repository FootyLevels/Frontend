import Foundation
import Observation

/// State for one project's workspace: the project document, what's selected,
/// and every server action the screen can take.
@MainActor
@Observable
final class ProjectDetailViewModel {
    /// The two ways to inspect a clip, as in the web workspace.
    enum Mode: String, CaseIterable, Identifiable {
        case motion = "Whole video in 3D"
        case frames = "Key-frame poses"
        var id: String { rawValue }
    }

    let projectId: String

    var project: SkillLabProject?
    var health: SkillLabHealth?
    var errorMessage: String?
    /// True while a user-initiated request is in flight, to disable its button.
    var isSubmitting = false
    var mode: Mode = .motion
    var selectedFrameId: String?
    /// Key-frame provider for mesh generation; defaults to the first ready one.
    var providerId: String?

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(projectId: String) {
        self.projectId = projectId
    }

    /// The bundled example is read from the app, so nothing can be written.
    var isSample: Bool { BundledSample.isSample(projectId) }

    var selectedFrame: KeyFrame? {
        guard let project else { return nil }
        return project.frames.first { $0.id == selectedFrameId } ?? project.frames.first
    }

    var selectedIndex: Int {
        guard let project, let frame = selectedFrame else { return 0 }
        return project.frames.firstIndex { $0.id == frame.id } ?? 0
    }

    // MARK: - Loading

    func load() async {
        if isSample {
            await refresh()
            return
        }
        async let healthTask = try? SkillLabClient.shared.health()
        await refresh()
        await refreshHealth(await healthTask)
    }

    func refreshHealth(_ prefetched: SkillLabHealth?? = nil) async {
        let latest: SkillLabHealth?
        if let prefetched {
            latest = prefetched
        } else {
            latest = try? await SkillLabClient.shared.health()
        }
        health = latest
        if providerId == nil || readyProviders.contains(where: { $0.id == providerId }) == false {
            providerId = readyProviders.first?.id ?? providerId
        }
    }

    func refresh() async {
        do {
            project = try await SkillLabClient.shared.project(id: projectId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        pollIfBusy()
    }

    /// Both jobs run in the background on the server and report only through
    /// the project document, so poll it for as long as either is active.
    private func pollIfBusy() {
        guard !isSample, project?.isBusy == true, pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.8))
                guard let self, !Task.isCancelled else { return }
                if let latest = try? await SkillLabClient.shared.project(id: self.projectId) {
                    self.project = latest
                }
                if self.project?.isBusy != true { break }
            }
            self?.pollTask = nil
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Capabilities

    var readyProviders: [ProviderCapability] { health?.readyProviders ?? [] }
    var selectedProvider: ProviderCapability? { readyProviders.first { $0.id == providerId } }

    var isRunning: Bool { project?.isBusy ?? false }
    var canEdit: Bool { !isSample && !isRunning && !isSubmitting }
    var canGenerateMotion: Bool { canEdit && (health?.motion.ready ?? false) && motionBlocker == nil }

    /// Why motion reconstruction can't start, or nil if it can.
    var motionBlocker: String? {
        guard let project else { return "Loading…" }
        if isSample { return "The included example is read-only." }
        if project.isBusy { return "Wait for the current job to finish." }
        if project.video.duration > 60 { return "Whole-video reconstruction supports clips up to 60 seconds." }
        if let health, !health.motion.ready { return health.motion.reason ?? "Motion models aren't installed on the server." }
        if health == nil { return "Connect to the server to reconstruct." }
        return nil
    }

    var readyFrameCount: Int { project?.frames.filter { $0.status == "ready" }.count ?? 0 }

    // MARK: - Actions

    func startMotion() async {
        await perform { try await SkillLabClient.shared.startMotion(projectId: self.projectId) }
    }

    /// Generates meshes with the chosen provider — for `frameIds`, or every
    /// frame that isn't ready yet.
    func generateMeshes(frameIds: [String]? = nil) async {
        guard let provider = providerId else { return }
        await perform {
            try await SkillLabClient.shared.generateMeshes(projectId: self.projectId,
                                                           provider: provider, frameIds: frameIds)
        }
    }

    /// Captures the frame at `timestamp` and selects the new key frame.
    func addFrame(at timestamp: Double) async {
        await perform {
            let project = try await SkillLabClient.shared.addFrame(projectId: self.projectId, timestamp: timestamp)
            self.project = project
            self.selectedFrameId = project.frames.min {
                abs($0.timestamp - timestamp) < abs($1.timestamp - timestamp)
            }?.id
        }
    }

    func updateBox(frameId: String, bbox: [Double]) async -> Bool {
        await perform {
            self.project = try await SkillLabClient.shared.updateFrame(projectId: self.projectId,
                                                                        frameId: frameId, bbox: bbox)
        }
    }

    func deleteFrame(_ frameId: String) async -> Bool {
        await perform {
            let project = try await SkillLabClient.shared.deleteFrame(projectId: self.projectId, frameId: frameId)
            self.project = project
            self.selectedFrameId = project.frames.first?.id
        }
    }

    /// Runs a write, surfaces its error, then refreshes so a newly queued job
    /// is picked up by polling.
    @discardableResult
    private func perform(_ action: () async throws -> Void) async -> Bool {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await action()
            errorMessage = nil
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
