import AVFoundation
import Foundation
import Observation
import RealityKit
import UIKit

/// Plays the Over Fake lesson: the included example's video as the clock, its
/// 3D body with the stepping foot in orange and the front foot in blue, and
/// the cues that teach the move (footprints, trails, a ghost of the last step,
/// a direction arrow) plus the readings shown in the info bar.
///
/// Everything comes from the app bundle, so the lesson works offline and
/// without an account.
@MainActor
@Observable
final class SkillLessonModel {

    enum LoadState: Equatable {
        case loading(String)
        case ready
        case failed(String)
    }

    let lesson: SkillLesson
    let playback: PlaybackController

    var state: LoadState = .loading("Loading the 3D motion\u{2026}")
    var stage: LessonStage = .watch
    var overlays = LessonOverlays() { didSet { lastGhostTime = -1; redraw() } }
    /// Flips the video and the 3D, to learn the move on the other foot.
    var mirror = false { didSet { stageRoot?.scale.x = mirror ? -1 : 1; redraw() } }
    var angle: CameraAngle = .source
    private(set) var loop: ClosedRange<Double>?
    private(set) var stageRoot: Entity?
    /// Playback pauses once it passes this time, e.g. at the end of a challenge clip.
    var stopAt: Double?
    /// Counts automatic stops, so a view can react to one.
    private(set) var autoStops = 0

    // Info-bar readings, refreshed once per video frame.
    private(set) var phase: SkillLesson.Phase
    private(set) var frontPlanted = false
    private(set) var stepPlanted = false
    /// 0 = over the front (left) foot, 1 = over the stepping (right) foot.
    private(set) var weight = 0.5
    private(set) var dropCm = 0.0
    /// Degrees turned since the phase began, during the two turning phases.
    private(set) var turnDegrees: Double?
    private(set) var ballSpeed = 0.0

    @ObservationIgnored let camera = OrbitCamera()
    @ObservationIgnored private var skipsPause = false
    @ObservationIgnored private var clip: MotionClip?
    @ObservationIgnored private var body: AnimatedBodyMesh?
    @ObservationIgnored private var ghost: AnimatedBodyMesh?
    @ObservationIgnored private let ball = Entity()
    @ObservationIgnored private var trails: [Trail] = []
    @ObservationIgnored private var footprints: [Footprint] = []
    @ObservationIgnored private let arrow = Entity()
    @ObservationIgnored private var lastFrame = -1
    @ObservationIgnored private var lastPoseTime = -1.0
    @ObservationIgnored private var lastGhostTime = -1.0
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var streaming: Task<Void, Never>?
    @ObservationIgnored private var started = false

    init(lesson: SkillLesson, videoURL: URL) {
        self.lesson = lesson
        playback = PlaybackController(url: videoURL, duration: lesson.duration)
        playback.speed = 1
        playback.loops = false
        phase = lesson.phases[0]
    }

    /// The lesson built from the included example in the app bundle.
    static func bundled() throws -> SkillLessonModel {
        guard let sample = BundledSample.project,
              let url = BundledSample.fileURL(forAssetPath: sample.video.url) else {
            throw SkillLesson.LoadError.missing
        }
        return SkillLessonModel(lesson: try SkillLesson.bundled(), videoURL: url)
    }

    // MARK: - Loading

    func load() async {
        guard !started else { return }
        started = true
        do {
            guard let path = BundledSample.project?.motion?.sequenceUrl else { throw SkillLesson.LoadError.missing }
            let clip = try await MotionClip.load(projectId: BundledSample.id, sequencePath: path)
            let vertices = UInt32(clip.sequence.vertexCount)
            guard clip.sequence.frameCount == lesson.frameCount,
                  (lesson.footSets.left + lesson.footSets.right).allSatisfy({ $0 < vertices }) else {
                throw SkillLesson.LoadError.inconsistent
            }
            self.clip = clip
            streaming = Task { [weak self] in
                await clip.loadRemainingChunks { self?.redraw() }
            }
            stageRoot = try await buildStage(clip)
            camera.homeDistance = 4.1
            camera.distanceRange = 0.8...14
            camera.show(angle)
            observePlayback()
            state = .ready
            redraw()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Resolves once every frame of the motion has arrived.
    func finishLoading() async {
        await streaming?.value
    }

    private func buildStage(_ clip: MotionClip) async throws -> Entity {
        func material(_ color: UIColor) -> SimpleMaterial {
            var m = StageBuilder.bodyMaterial
            m.color = .init(tint: color)
            return m
        }
        let body = try AnimatedBodyMesh(
            sequence: clip.sequence, indices: clip.indices, material: StageBuilder.bodyMaterial,
            highlights: [.init(vertices: Set(lesson.footSets.left), material: material(SL.overlayFirst)),
                         .init(vertices: Set(lesson.footSets.right), material: material(SL.overlaySecond))])
        body.entity.name = "lesson-body"
        // The ghost is an extra; the lesson works without it.
        let ghost = try? AnimatedBodyMesh(sequence: clip.sequence, indices: clip.indices,
                                          material: material(UIColor(red: 0.62, green: 0.78, blue: 1, alpha: 1)))
        ghost?.entity.name = "lesson-ghost"
        ghost?.entity.components.set(OpacityComponent(opacity: 0.3))
        self.body = body
        self.ghost = ghost

        let radius = Float(lesson.ball.diameter / 2)
        ball.name = "lesson-ball"
        ball.components.set(ModelComponent(mesh: .generateSphere(radius: radius), materials: [StageBuilder.ballMaterial]))
        ball.isEnabled = false

        trails = [
            Trail(name: "trail-body", color: .white, radius: 0.02),
            Trail(name: "trail-step", color: SL.overlaySecond, radius: 0.016),
            Trail(name: "trail-front", color: SL.overlayFirst, radius: 0.016),
            Trail(name: "trail-ball", color: UIColor(white: 1, alpha: 0.6), radius: 0.012),
        ]
        footprints = makeFootprints()
        buildArrow()

        let content: [Entity] = [body.entity, ghost?.entity, ball, arrow].compactMap { $0 }
            + trails.map(\.entity) + footprints.map(\.entity)
        let com = lesson.frames.com
        let center = SIMD3<Float>(com.map { $0[0] }.reduce(0, +) / Float(com.count), 0,
                                  com.map { $0[2] }.reduce(0, +) / Float(com.count))
        let extent = clip.sequence.extent
        let stage = await StageBuilder.makeStage(content: content, floorCenter: center,
                                                 floorSize: Swift.max(extent.x, extent.z) + 8)
        stage.root.scale.x = mirror ? -1 : 1
        return stage.root
    }

    /// One flat print where each foot came down and stayed for at least four frames.
    private func makeFootprints() -> [Footprint] {
        let disc = MeshResource.generateCylinder(height: 0.004, radius: 0.07)
        var prints: [Footprint] = []
        let sides: [([Int], [[Float]], UIColor, String)] = [
            (lesson.frames.leftPlanted, lesson.frames.left, SL.overlayFirst, "front"),
            (lesson.frames.rightPlanted, lesson.frames.right, SL.overlaySecond, "step"),
        ]
        for (planted, positions, color, side) in sides {
            var i = 0
            while i < lesson.frameCount {
                guard planted[i] == 1 else { i += 1; continue }
                let shot = lesson.shot(ofFrame: i)
                var end = i
                while end + 1 < lesson.frameCount, planted[end + 1] == 1, lesson.shot(ofFrame: end + 1) == shot { end += 1 }
                if end - i >= 3 {
                    let entity = ModelEntity(mesh: disc, materials: [UnlitMaterial(color: color)])
                    entity.name = "print-\(side)-\(i)"
                    entity.position = [positions[i][0], 0.003, positions[i][2]]
                    entity.scale = [1, 1, 1.5]
                    entity.components.set(OpacityComponent(opacity: 0.9))
                    entity.isEnabled = false
                    prints.append(Footprint(entity: entity, shot: shot, start: i, end: end))
                }
                i = end + 1
            }
        }
        return prints
    }

    /// A flat arrow along local +z; `render` points and stretches it.
    private func buildArrow() {
        arrow.name = "lesson-direction"
        let color = UnlitMaterial(color: UIColor(red: 1, green: 0.82, blue: 0.4, alpha: 1))
        let shaft = ModelEntity(mesh: .generateCylinder(height: 1, radius: 0.014), materials: [color])
        shaft.name = "shaft"
        shaft.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        let head = ModelEntity(mesh: .generateCone(height: 0.14, radius: 0.06), materials: [color])
        head.name = "head"
        head.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        arrow.addChild(shaft)
        arrow.addChild(head)
        arrow.isEnabled = false
    }

    // MARK: - Playback

    private func observePlayback() {
        let interval = CMTime(value: 1, timescale: 60)
        timeObserver = playback.player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
    }

    private var isPlaying: Bool { playback.player.rate != 0 }

    private func tick(_ seconds: Double) {
        var t = seconds.isFinite ? seconds : 0
        if isPlaying {
            let pause = OverFakeLessonContent.pause
            if skipsPause, t > pause.lowerBound, t < pause.upperBound {
                t = pause.upperBound
                playback.seek(to: t)
            }
            if let loop, t >= loop.upperBound {
                t = loop.lowerBound
                playback.seek(to: t)
            }
            if let stopAt, t >= stopAt {
                self.stopAt = nil
                playback.pause()
                autoStops += 1
            }
        }
        render(at: t)
    }

    /// Plays `range` on a loop at `rate`.
    func play(_ range: ClosedRange<Double>, rate: Float, skipPause: Bool = false) {
        loop = range
        skipsPause = skipPause
        playback.speed = rate
        playback.seek(to: range.lowerBound)
        playback.player.rate = rate
    }

    /// Plays from `time` without a loop, stopping at `stop` if given.
    func play(from time: Double, rate: Float, stopAt stop: Double? = nil) {
        loop = nil
        skipsPause = false
        stopAt = stop
        playback.speed = rate
        playback.seek(to: time)
        playback.player.rate = rate
    }

    func freeze(at time: Double) {
        stopAt = nil
        playback.pause()
        playback.seek(to: time)
        render(at: time)
    }

    func togglePlayback() {
        if isPlaying { playback.pause() } else { playback.player.rate = playback.speed }
    }

    func step(frames: Int) {
        freeze(at: Swift.min(Swift.max(playback.currentTime + Double(frames) / lesson.fps, 0), lesson.duration - 0.02))
    }

    func setLoop(_ range: ClosedRange<Double>?) {
        loop = range
        if range == nil { skipsPause = false }
    }

    func toggleLoop() {
        setLoop(loop == nil ? phase.start...phase.end : nil)
    }

    func pause() { playback.pause() }

    func show(_ angle: CameraAngle) {
        self.angle = angle
        camera.show(angle)
    }

    /// Sets up the stage: Watch plays the full-speed demo, Break it down opens
    /// on the set-up, and Practise and Test start still.
    func enter(_ stage: LessonStage) {
        self.stage = stage
        show(.source)
        switch stage {
        case .watch:
            overlays = LessonOverlays()
            play(0...3.0, rate: 1)
        case .breakdown:
            if let setup = lesson.phase("setup") { focus(on: setup) }
        case .practise:
            overlays = LessonOverlays(direction: false)
            setLoop(nil)
            pause()
        case .test:
            overlays = LessonOverlays(footprints: false, direction: false)
            setLoop(nil)
            pause()
        }
    }

    /// Freezes on a phase's key moment, loops the phase and switches the cues
    /// to the ones that matter for it.
    func focus(on phase: SkillLesson.Phase) {
        let content = OverFakeLessonContent.phase(phase.id)
        overlays = content.overlays
        if let angle = content.angle { show(angle) }
        setLoop(phase.start...phase.end)
        freeze(at: phase.key)
    }

    func teardown() {
        streaming?.cancel()
        if let timeObserver {
            playback.player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        playback.teardown()
    }

    // MARK: - Rendering

    private func redraw() {
        lastFrame = -1
        render(at: playback.currentTime)
    }

    /// Draws the moment at `time`. Internal so tests can drive it directly.
    func render(at time: Double) {
        guard let clip, let body else { return }
        let i = lesson.frame(at: time)
        let current = lesson.phase(at: time)
        if current != phase { phase = current }

        if time != lastPoseTime, let sample = clip.sequence.sample(at: time), let pose = clip.pose(sample.index) {
            body.show(pose, blendingTo: sample.blend > 0 ? clip.pose(sample.next) : nil, amount: sample.blend)
            body.entity.isEnabled = true
            lastPoseTime = time
        }
        renderGhost(for: current, in: clip)

        let ballPosition = lesson.ball.positions[i]
        ball.isEnabled = ballPosition != nil
        if let p = ballPosition { ball.position = [p[0], p[1], p[2]] }

        if i != lastFrame {
            lastFrame = i
            updateReadings(frame: i, phase: current)
            renderTrails(frame: i, phase: current)
            renderFootprints(frame: i)
            renderArrow(frame: i)
        }
        if overlays.follow {
            let c = lesson.frames.com[i]
            let goal = SIMD3<Float>(mirror ? -c[0] : c[0], 0.8, c[2])
            camera.target += (goal - camera.target) * 0.15
        }
    }

    private func renderGhost(for phase: SkillLesson.Phase, in clip: MotionClip) {
        guard let ghost else { return }
        guard overlays.ghost, let previous = lesson.previousKeyPhase(before: phase) else {
            ghost.entity.isEnabled = false
            return
        }
        if previous.key != lastGhostTime, let pose = clip.pose(lesson.frame(at: previous.key)) {
            ghost.show(pose)
            lastGhostTime = previous.key
        }
        ghost.entity.isEnabled = lastGhostTime == previous.key
    }

    private func updateReadings(frame i: Int, phase: SkillLesson.Phase) {
        let f = lesson.frames
        frontPlanted = f.leftPlanted[i] == 1
        stepPlanted = f.rightPlanted[i] == 1
        weight = Swift.min(Swift.max(f.weight[i], 0), 1)
        dropCm = f.comDropCm[i]
        ballSpeed = f.ballSpeed[i]
        if phase.id == "change" || phase.id == "turn" {
            turnDegrees = abs(f.yaw[i] - f.yaw[lesson.frame(at: phase.start)])
        } else {
            turnDegrees = nil
        }
    }

    private func renderTrails(frame i: Int, phase: SkillLesson.Phase) {
        guard overlays.paths else {
            trails.forEach { $0.entity.isEnabled = false }
            return
        }
        let from = Swift.max(lesson.frame(at: phase.start), i - 45)
        let f = lesson.frames
        let frames = Array(from...i)
        trails[0].show(frames.map { [f.com[$0][0], 0.01, f.com[$0][2]] })
        trails[1].show(frames.map { [f.right[$0][0], f.right[$0][1], f.right[$0][2]] })
        trails[2].show(frames.map { [f.left[$0][0], f.left[$0][1], f.left[$0][2]] })
        trails[3].show(frames.compactMap { lesson.ball.positions[$0].map { [$0[0], $0[1], $0[2]] } })
    }

    private func renderFootprints(frame i: Int) {
        let shot = lesson.shot(ofFrame: i)
        for print in footprints {
            let visible = overlays.footprints && print.shot == shot && print.start <= i
            print.entity.isEnabled = visible
            if visible {
                print.entity.components.set(OpacityComponent(opacity: print.end >= i ? 0.9 : 0.35))
            }
        }
    }

    /// Where the body's mass is heading, from a short window within the shot.
    private func renderArrow(frame i: Int) {
        let shotStart = lesson.shot(ofFrame: i) == 0 ? 0 : lesson.frame(at: lesson.shots[1].start)
        let shotEnd = lesson.shot(ofFrame: i) == 0 ? lesson.frame(at: lesson.shots[1].start) - 1 : lesson.frameCount - 1
        let a = Swift.max(i - 3, shotStart), b = Swift.min(i + 3, shotEnd)
        let c0 = lesson.frames.com[a], c1 = lesson.frames.com[b]
        let dx = c1[0] - c0[0], dz = c1[2] - c0[2]
        let speed = (dx * dx + dz * dz).squareRoot() / Swift.max(Float(b - a) / Float(lesson.fps), 1e-3)
        guard overlays.direction, speed > 0.35, speed < 8 else {
            arrow.isEnabled = false
            return
        }
        let length = Swift.min(Swift.max(speed * 0.35, 0.3), 1.3)
        let c = lesson.frames.com[i]
        arrow.position = [c[0], 0.03, c[2]]
        arrow.orientation = simd_quatf(angle: atan2(dx, dz), axis: [0, 1, 0])
        arrow.findEntity(named: "shaft")?.scale = [1, length, 1]
        arrow.findEntity(named: "shaft")?.position = [0, 0, length / 2]
        arrow.findEntity(named: "head")?.position = [0, 0, length + 0.07]
        arrow.isEnabled = true
    }
}

// MARK: - Scene pieces

/// A breadcrumb trail: small dots, older ones smaller.
@MainActor
private final class Trail {
    static let capacity = 46
    let entity = Entity()
    private var dots: [ModelEntity] = []

    init(name: String, color: UIColor, radius: Float) {
        entity.name = name
        let mesh = MeshResource.generateSphere(radius: radius)
        let material = UnlitMaterial(color: color)
        for _ in 0..<Self.capacity {
            let dot = ModelEntity(mesh: mesh, materials: [material])
            dot.isEnabled = false
            entity.addChild(dot)
            dots.append(dot)
        }
    }

    func show(_ points: [SIMD3<Float>]) {
        entity.isEnabled = true
        let shown = points.suffix(Self.capacity)
        let n = shown.count
        for (k, dot) in dots.enumerated() {
            guard k < n else { dot.isEnabled = false; continue }
            dot.position = shown[shown.startIndex + k]
            dot.scale = .init(repeating: 0.35 + 0.65 * Float(k + 1) / Float(n))
            dot.isEnabled = true
        }
    }
}

private struct Footprint {
    let entity: ModelEntity
    let shot: Int
    let start: Int
    let end: Int
}
