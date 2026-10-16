import AVFoundation
import Foundation
import Observation
import RealityKit

/// The "Motion inspector": the whole-video body and football, in lockstep with
/// the source video.
///
/// The shared `AVPlayer` is the clock. A 60 Hz time observer maps video time to
/// a fractional frame and the body is blended between the two nearest samples,
/// as the web viewer does — so half- and quarter-speed playback stay smooth.
@MainActor
@Observable
final class MotionPlayerViewModel {

    enum LoadState: Equatable {
        case loading(String)
        case ready
        case failed(String)
    }

    let projectId: String

    var state: LoadState = .loading("Loading motion sequence…")
    var sequence: MotionSequence?
    var currentFrame = 0
    /// Chunks decoded so far, out of `sequence.chunks.count`.
    var loadedChunks = 0
    /// False when the current frame has no reconstruction.
    var missingPose = false
    var waitingForChunk = false
    var assetWarning: String?
    var contactLabel: String?
    var stageRoot: Entity?
    var angle: CameraAngle = .source

    var showBall = true { didSet { updateBall(frame: currentFrame, next: currentFrame, blend: 0) } }
    var follow = true
    var wireframe = false { didSet { body?.wireframe = wireframe } }

    @ObservationIgnored let camera = OrbitCamera()
    @ObservationIgnored private let assets: any MotionAssetSource
    @ObservationIgnored private let player: AVPlayer
    @ObservationIgnored private var body: AnimatedBodyMesh?
    @ObservationIgnored private var ball: Entity?
    /// Decoded `uint16` values per chunk index.
    @ObservationIgnored private var chunks: [Int: [UInt16]] = [:]
    /// Chunk index for every frame, so lookup during playback is O(1).
    @ObservationIgnored private var chunkForFrame: [Int] = []
    @ObservationIgnored private var lastTime = -1.0
    @ObservationIgnored private var lastShot = -1
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var backgroundLoad: Task<Void, Never>?

    init(projectId: String, sequencePath: String, player: AVPlayer) {
        self.projectId = projectId
        self.assets = LegacyMotionAssetSource(projectId: projectId, sequencePath: sequencePath)
        self.player = player
    }

    init(projectId: String, assets: any MotionAssetSource, player: AVPlayer) {
        self.projectId = projectId; self.assets = assets; self.player = player
    }

    var sourceTime: Double { assets.sourceTimeOffset + Double(currentFrame) / fps }
    var accessibilityStatus: String {
        switch state { case .ready: return "Ready"; case .loading: return "Loading"; case .failed: return "Failed" }
    }

    var fps: Double { sequence?.fps ?? 30 }

    // MARK: - Loading

    /// Fetches just enough to show the first frame, then streams the rest.
    ///
    /// Everything up front is small — `sequence.json`, the ~430 KB topology and
    /// one 30-frame chunk — so the body appears while later seconds of the clip
    /// are still arriving.
    func load() async {
        guard stageRoot == nil else { return }
        do {
            let sequence = try await assets.sequence()
            guard sequence.encoding == "uint16-le-xyz-gzip" else {
                throw MeshDecodingError.unsupportedEncoding(sequence.encoding)
            }
            self.sequence = sequence
            chunkForFrame = Self.chunkLookup(for: sequence)

            async let topologyTask = assets.data(file: sequence.topologyFile)
            async let ballTask = loadBallMesh(sequence)

            let firstChunk = chunkForFrame.first ?? 0
            let firstChunkTask = Task { try await self.fetchChunk(firstChunk, sequence) }
            defer { firstChunkTask.cancel() }

            let indices = BinaryBuffers.array(of: UInt32.self, from: try await topologyTask)
            guard indices.count == sequence.faceCount * 3, indices.allSatisfy({ $0 < sequence.vertexCount }) else {
                throw MeshDecodingError.chunkSizeMismatch(file: sequence.topologyFile,
                                                          expected: sequence.faceCount * 12,
                                                          actual: indices.count * 4)
            }
            let body = try AnimatedBodyMesh(sequence: sequence, indices: indices,
                                            material: StageBuilder.bodyMaterial)
            self.body = body

            chunks[firstChunk] = try await firstChunkTask.value
            loadedChunks = 1

            let ball = await ballTask
            self.ball = ball

            // A generous floor centred on the action, in 25 cm cells like the
            // web viewer's grid.
            let floorCenter = (sequence.lowerBound + sequence.upperBound) / 2
            let floorSize = Swift.min(50, Swift.max(sequence.extent.x, sequence.extent.z) + 10)
            let stage = await StageBuilder.makeStage(content: [body.entity, ball].compactMap { $0 },
                                                     floorCenter: floorCenter, floorSize: floorSize)
            stageRoot = stage.root

            camera.homeDistance = 4.1
            camera.distanceRange = 0.7...25
            camera.show(.source)

            render(time: player.currentTime().seconds, force: true)
            observePlayback()
            state = .ready

            backgroundLoad = Task { await self.loadRemainingChunks(after: firstChunk, sequence) }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Streams the remaining chunks a few at a time, re-rendering if the
    /// current frame was waiting on one of them.
    private func loadRemainingChunks(after first: Int, _ sequence: MotionSequence) async {
        let pending = sequence.chunks.indices.filter { $0 != first }
        var iterator = pending.makeIterator()

        await withTaskGroup(of: (Int, [UInt16]?).self) { group in
            // Three in flight saturates a LAN link without starving playback.
            for _ in 0..<3 {
                guard let index = iterator.next() else { break }
                group.addTask { (index, try? await self.fetchChunk(index, sequence)) }
            }
            for await (index, values) in group {
                if Task.isCancelled { group.cancelAll(); return }
                if let values {
                    chunks[index] = values
                    loadedChunks += 1
                    render(time: player.currentTime().seconds, force: true)
                } else {
                    assetWarning = "Some 3D frames couldn't be loaded. Reload the result to try again."
                }
                if let next = iterator.next() {
                    group.addTask { (next, try? await self.fetchChunk(next, sequence)) }
                }
            }
        }
    }

    /// Downloads and inflates one chunk off the main actor, checking its size
    /// against the header so a truncated file can't masquerade as a pose.
    private func fetchChunk(_ index: Int, _ sequence: MotionSequence) async throws -> [UInt16] {
        let chunk = sequence.chunks[index]
        let compressed = try await assets.data(file: chunk.file)
        let strict = assets.usesPrivateContract

        return try await Task.detached(priority: .userInitiated) {
            let expected = chunk.count * sequence.vertexCount * 3 * MemoryLayout<UInt16>.size
            let raw = try strict ? Gzip.decompress(compressed, expectedByteCount: expected) : Gzip.decompress(compressed)
            guard raw.count == expected else {
                throw MeshDecodingError.chunkSizeMismatch(file: chunk.file, expected: expected, actual: raw.count)
            }
            return BinaryBuffers.array(of: UInt16.self, from: raw)
        }.value
    }

    /// The football: SAM 3D Objects' mesh when available, else a plain sphere.
    /// The backend doesn't estimate spin, so a fixed orientation is correct.
    private func loadBallMesh(_ sequence: MotionSequence) async -> Entity? {
        guard sequence.validBallFrames > 0 else { return nil }
        let diameter = Float(sequence.ball.diameter)
        let entity = Entity()
        entity.name = "ball"

        var resource: MeshResource?
        if let file = sequence.ball.file {
            if let data = try? await assets.data(file: file),
               var mesh = try? GLBLoader.load(data) {
                // Recentre and resize to the diameter the tracker assumed, so the
                // mesh sits where the ball positions say it does.
                let bounds = mesh.bounds
                let size = Swift.max(bounds.extents.x, Swift.max(bounds.extents.y, bounds.extents.z))
                if size > 1e-6 {
                    let factor = diameter / size
                    mesh.positions = mesh.positions.map { ($0 - bounds.center) * factor }
                    resource = try? mesh.makeResource(name: "ball")
                }
            }
        }

        entity.components.set(ModelComponent(mesh: resource ?? .generateSphere(radius: diameter / 2),
                                             materials: [StageBuilder.ballMaterial]))
        entity.components.set(GroundingShadowComponent(castsShadow: true))
        entity.isEnabled = false
        return entity
    }

    private static func chunkLookup(for sequence: MotionSequence) -> [Int] {
        var lookup = Array(repeating: 0, count: sequence.frameCount)
        for (index, chunk) in sequence.chunks.enumerated() {
            for frame in chunk.start..<Swift.min(chunk.start + chunk.count, sequence.frameCount) {
                lookup[frame] = index
            }
        }
        return lookup
    }

    // MARK: - Camera

    func show(_ angle: CameraAngle) {
        self.angle = angle
        camera.show(angle)
    }

    // MARK: - Playback

    private func observePlayback() {
        let interval = CMTime(value: 1, timescale: 60)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.render(time: time.seconds)
            }
        }
    }

    private func pose(_ frame: Int, in sequence: MotionSequence) -> AnimatedBodyMesh.Pose? {
        let chunkIndex = chunkForFrame[frame]
        guard let values = chunks[chunkIndex] else { return nil }
        return .init(values: values, offset: (frame - sequence.chunks[chunkIndex].start) * sequence.vertexCount * 3)
    }

    private func render(time: Double, force: Bool = false) {
        do { try assets.checkSession() } catch {
            body?.entity.isEnabled = false; ball?.isEnabled = false
            teardown()
            player.pause(); player.replaceCurrentItem(with: nil)
            chunks.removeAll(); sequence = nil; body = nil; ball = nil
            stageRoot = nil; state = .failed("Your account changed. Open this project again after signing in.")
            return
        }
        guard let sequence, let body, sequence.frameCount > 0 else { return }
        let seconds = time.isFinite ? time : 0
        guard force || seconds != lastTime else { return }
        lastTime = seconds

        let position = Swift.min(Double(sequence.frameCount - 1), Swift.max(0, seconds * sequence.fps + 1e-4))
        let index = Int(position)
        let nextIndex = Swift.min(index + 1, sequence.frameCount - 1)
        guard sequence.frames.indices.contains(index), sequence.frames.indices.contains(nextIndex) else { return }
        let a = sequence.frames[index], b = sequence.frames[nextIndex]
        // Never blend across a camera cut or into a missing frame.
        let blend = a.shot == b.shot && a.valid && b.valid ? Float(position - Double(index)) : 0

        if index != currentFrame || force {
            currentFrame = index
            missingPose = !a.valid
            waitingForChunk = a.valid && pose(index, in: sequence) == nil
            contactLabel = sequence.contactLabel(frame: index)
        }

        if a.valid, let pose = pose(index, in: sequence) {
            body.show(pose, blendingTo: blend > 0 ? self.pose(nextIndex, in: sequence) : nil, amount: blend)
            body.entity.isEnabled = true
            // A new shot has a new origin, so re-frame even when not following.
            if follow || lastShot != a.shot {
                camera.target = body.center
            }
            lastShot = a.shot
        } else {
            // Invalid frames hold placeholder data — never draw it as a pose.
            body.entity.isEnabled = false
        }
        updateBall(frame: index, next: nextIndex, blend: blend)
    }

    private func updateBall(frame: Int, next: Int, blend: Float) {
        guard let ball, let sequence, sequence.frames.indices.contains(frame) else { return }
        let a = sequence.frames[frame]
        guard showBall, let p = a.ball, p.count == 3 else {
            ball.isEnabled = false
            return
        }
        var position = SIMD3(p[0], p[1], p[2])
        if blend > 0, sequence.frames.indices.contains(next), let q = sequence.frames[next].ball, q.count == 3 {
            position += (SIMD3(q[0], q[1], q[2]) - position) * blend
        }
        ball.position = position
        ball.isEnabled = true
    }

    func teardown() {
        backgroundLoad?.cancel()
        assets.close()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }
}
