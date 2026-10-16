import Foundation
import Observation

@MainActor
@Observable
final class CloudProjectViewModel {
    var project: CloudProject
    var job: CloudJob?
    var playback: PlaybackController?
    var preparedPlayback: PlaybackController?
    var motion: MotionPlayerViewModel?
    var pose: PoseInspectorModel?
    var keyframeIndices: [Int] = []
    var selectedKeyframe: Int?
    var errorMessage: String?
    var playbackError: String?
    var loadingMessage: String?
    var isMutating = false
    private var client: CloudReconstructionClient?
    private var refreshing = false
    private var loadedResult: String?
    private var source: PrivateMotionAssetSource?
    private var poseSource: PrivateKeyframeAssetSource?
    private var poseSelection: Task<Void, Never>?
    private var preparedAssets: PrivatePlaybackAssets?
    private var preparedRevision: Int?
    private var attemptedResult: String?
    private var action: Task<Void, Never>?
    private var stopped = false
    var isForeground = true
    var isLoading: Bool { refreshing || loadingMessage != nil }

    init(project: CloudProject) { self.project = project }
    var canGenerate: Bool { !stopped && client != nil && project.state == "ready" && project.preparedMedia != nil && job?.isActive != true && !isMutating }
    func checkPlaybackSession() throws {
        guard !stopped, let client else { throw AccountAPIError.sessionChanged }
        try client.checkSession()
    }

    func watch() async {
        stopped = false
        do {
            guard let url = ApplicationEnvironment.apiBaseURL else { throw AccountAPIError.notConfigured }
            client = try CloudReconstructionClient(apiURL: url, credentials: FirebaseAPICredentials.shared, environment: .current)
            while !Task.isCancelled {
                await refresh()
                for _ in 0..<15 {
                    try await Task.sleep(for: .seconds(1))
                    try client?.checkSession()
                }
            }
        } catch is CancellationError {} catch { errorMessage = error.localizedDescription }
        stop()
    }

    func refresh() async {
        guard let client, !stopped, isForeground, !refreshing, !isMutating else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let latest = try await client.project(project.id)
            try client.checkSession()
            if latest.inputRevision != project.inputRevision || latest.state != "ready" { clearAllPlayback() }
            project = latest
            if let id = latest.activeJobId ?? job?.id ?? latest.latestReconstructionId {
                job = try await client.job(id, project: latest)
            }
            if latest.state == "ready", latest.preparedMedia != nil, preparedRevision != latest.inputRevision {
                preparedRevision = latest.inputRevision
                do { try await loadPreparedVideo(client: client) }
                catch let error as AccountAPIError { throw error }
                catch { if !Task.isCancelled { playbackError = error.localizedDescription } }
            }
            if let id = latest.latestReconstructionId, id != loadedResult, id != attemptedResult {
                attemptedResult = id
                do { try await loadResult(id, client: client) }
                catch let error as AccountAPIError { throw error }
                catch { if !Task.isCancelled { playbackError = error.localizedDescription } }
            }
            errorMessage = nil
        } catch is CancellationError {} catch {
            if Task.isCancelled { return }
            if let error = error as? AccountAPIError, [.sessionChanged, .signInRequired, .forbidden, .notFound].contains(error) {
                clearAllPlayback(); self.client = nil
            }
            errorMessage = error.localizedDescription
        }
    }

    private func loadPreparedVideo(client: CloudReconstructionClient) async throws {
        loadingMessage = "Loading your prepared video…"
        defer { loadingMessage = nil }
        let assets = try client.preparedAssets(project: project)
        do {
            let url = try await assets.localFile(file: "video")
            try client.checkSession(); guard !stopped else { throw CancellationError() }
            preparedPlayback?.teardown(); preparedAssets?.close()
            preparedPlayback = PlaybackController(url: url, duration: project.preparedMedia!.duration)
            preparedAssets = assets
        } catch { assets.close(); throw error }
    }

    private func loadResult(_ id: String, client: CloudReconstructionClient) async throws {
        loadingMessage = "Verifying private 3D files…"
        defer { loadingMessage = nil }
        let resultJob = try await client.job(id, project: project)
        if resultJob.kind == "reconstructKeyframes" {
            let (result, job, assets) = try await client.keyframeResult(id, project: project)
            let source = PrivateKeyframeAssetSource(result: result, job: job, assets: assets)
            do {
                _ = try await source.manifest()
                try client.checkSession(); guard !stopped else { throw CancellationError() }
                clearPlayback(); poseSource = source
                let pose = PoseInspectorModel(); self.pose = pose
                keyframeIndices = job.keyframes!.map(\.frameIndex)
                let first = keyframeIndices[0]; selectedKeyframe = first
                preparedPlayback?.pause(); preparedPlayback?.seek(to: Double(first)/30)
                await pose.showPrivate(frameIndex: first, source: source)
                try client.checkSession(); guard !stopped else { throw CancellationError() }
                loadedResult = id; playbackError = nil
            } catch { source.close(); throw error }
            return
        }
        let (result, job, assets) = try await client.motionResult(id, project: project)
        let source = PrivateMotionAssetSource(result: result, job: job, assets: assets)
        do {
            let sequence = try await source.sequence()
            loadingMessage = "Loading your private clip…"
            let url = try await source.videoURL()
            try client.checkSession()
            guard !stopped else { throw CancellationError() }
            clearPlayback()
            self.source = source
            let playback = PlaybackController(url: url, duration: sequence.duration)
            let motion = MotionPlayerViewModel(projectId: project.id, assets: source, player: playback.player)
            self.playback = playback; self.motion = motion
            await motion.load()
            try client.checkSession()
            loadedResult = id
            playbackError = nil
        } catch { source.close(); throw error }
    }

    func generatePose(frameIndex: Int, box: [Double]) {
        guard canGenerate, let client else { return }
        perform {
            let current = try await client.project(self.project.id); self.project = current
            self.job = try await client.generateKeyframes(project: current,
                selections: [CloudKeyframeSelection(frameIndex: frameIndex, bbox: box)])
        }
    }

    func selectPose(_ frameIndex: Int) {
        guard !stopped, let pose, let source = poseSource, keyframeIndices.contains(frameIndex) else { return }
        poseSelection?.cancel(); selectedKeyframe = frameIndex
        preparedPlayback?.pause(); preparedPlayback?.seek(to: Double(frameIndex)/30)
        poseSelection = Task { await pose.showPrivate(frameIndex: frameIndex, source: source) }
    }

    func generate(startFrame: Int, endFrame: Int) {
        guard canGenerate, let client else { return }
        perform {
            let current = try await client.project(self.project.id)
            self.project = current
            self.job = try await client.generateMotion(project: current, startFrame: startFrame, endFrame: endFrame)
        }
    }

    func cancelGeneration() {
        guard let client, let job, job.isActive, job.kind != "prepareMedia", !isMutating else { return }
        perform { self.job = try await client.cancel(job.id, project: self.project) }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        isMutating = true
        action = Task {
            do { try await operation(); errorMessage = nil }
            catch is CancellationError {} catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
            isMutating = false; action = nil
            if !Task.isCancelled { await refresh() }
        }
    }

    func reloadPlayback() {
        guard !isMutating, !refreshing else { return }
        clearAllPlayback(); playbackError = nil
        action = Task { await refresh(); action = nil }
    }

    private func clearPlayback() {
        poseSelection?.cancel(); poseSelection = nil; pose?.clear(); poseSource?.close()
        pose = nil; poseSource = nil; keyframeIndices = []; selectedKeyframe = nil
        playback?.teardown(); motion?.teardown(); source?.close()
        playback = nil; motion = nil; source = nil; loadedResult = nil
    }

    private func clearAllPlayback() {
        clearPlayback(); preparedPlayback?.teardown(); preparedAssets?.close()
        preparedPlayback = nil; preparedAssets = nil; preparedRevision = nil; attemptedResult = nil
    }

    func stop() {
        stopped = true; action?.cancel(); action = nil
        clearAllPlayback(); client = nil
    }
}
