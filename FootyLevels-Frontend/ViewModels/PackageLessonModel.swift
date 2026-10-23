import AVFoundation
import Foundation
import Observation
import RealityKit
import UIKit

/// Plays any lesson made by the lesson pipeline: the video as the clock, the 3D body
/// with the ball foot in orange and the standing foot in blue, and the cues each phase
/// asks for (footprints, trails, a ghost of the last step, a direction arrow).
///
/// A lesson can hold several skills; the selected one sets the time range, the phases,
/// which measured foot is the ball foot, and whether the ball may leave the ground.
@MainActor
@Observable
final class PackageLessonModel {

    enum LoadState: Equatable {
        case loading(String)
        case ready
        case failed(String)
    }

    let package: LessonPackage
    let playback: PlaybackController

    var state: LoadState = .loading("Loading the 3D motion\u{2026}")
    var stage: LessonStage = .watch
    private(set) var skill: LessonDocument.Skill
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

    // Readings, refreshed once per video frame.
    private(set) var phase: LessonDocument.Phase?
    private(set) var standPlanted = false
    private(set) var ballPlanted = false
    /// 0 = over the standing foot, 1 = over the ball foot.
    private(set) var weight = 0.5
    private(set) var dropCm = 0.0
    private(set) var turnDegrees: Double?
    private(set) var ballText = "–"
    private(set) var hasBody = true

    @ObservationIgnored let camera = OrbitCamera()
    @ObservationIgnored private var clip: MotionClip?
    @ObservationIgnored private var body: AnimatedBodyMesh?
    @ObservationIgnored private var ghost: AnimatedBodyMesh?
    @ObservationIgnored private let ball = Entity()
    @ObservationIgnored private var trails: [LessonTrail] = []
    @ObservationIgnored private var footprints: [Print] = []
    @ObservationIgnored private let arrow = Entity()
    @ObservationIgnored private var meshBallSide: LessonDocument.Side?
    @ObservationIgnored private var lastFrame = -1
    @ObservationIgnored private var lastPoseTime = -1.0
    @ObservationIgnored private var lastGhostTime = -1.0
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var streaming: Task<Void, Never>?
    @ObservationIgnored private var started = false

    private static let ballColor = SL.overlaySecond
    private static let standColor = SL.overlayFirst

    init(package: LessonPackage) {
        self.package = package
        skill = package.document.skills[0]
        playback = PlaybackController(url: package.videoURL, duration: package.analysis.duration)
        playback.speed = 1
        playback.loops = false
    }

    static func load(_ url: URL) throws -> PackageLessonModel {
        PackageLessonModel(package: try LessonPackage.load(url))
    }

    private var analysis: LessonAnalysis { package.analysis }

    // MARK: - Loading

    func load() async {
        guard !started else { return }
        started = true
        do {
            let clip = try await MotionClip.load(directory: package.motionDirectory)
            let vertices = UInt32(clip.sequence.vertexCount)
            guard clip.sequence.frameCount == analysis.frameCount,
                  (package.footSets.left + package.footSets.right).allSatisfy({ $0 < vertices }) else {
                throw LessonPackage.LoadError.inconsistent("the motion doesn't match the measurements")
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

    private static func material(_ color: UIColor) -> SimpleMaterial {
        var m = StageBuilder.bodyMaterial
        m.color = .init(tint: color)
        return m
    }

    private func buildStage(_ clip: MotionClip) async throws -> Entity {
        // Highlight 0 is the mesh's left foot, 1 its right; their colours follow the jobs.
        let body = try AnimatedBodyMesh(
            sequence: clip.sequence, indices: clip.indices, material: StageBuilder.bodyMaterial,
            highlights: [.init(vertices: Set(package.footSets.left), material: Self.material(Self.standColor)),
                         .init(vertices: Set(package.footSets.right), material: Self.material(Self.ballColor))])
        body.entity.name = "lesson-body"
        let ghost = try? AnimatedBodyMesh(sequence: clip.sequence, indices: clip.indices,
                                          material: Self.material(UIColor(red: 0.62, green: 0.78, blue: 1, alpha: 1)))
        ghost?.entity.name = "lesson-ghost"
        ghost?.entity.components.set(OpacityComponent(opacity: 0.3))
        self.body = body
        self.ghost = ghost

        ball.name = "lesson-ball"
        ball.components.set(ModelComponent(mesh: .generateSphere(radius: Float(analysis.ballDiameter / 2)),
                                           materials: [StageBuilder.ballMaterial]))
        ball.isEnabled = false

        trails = [
            LessonTrail(name: "trail-body", color: .white, radius: 0.02),
            LessonTrail(name: "trail-ball-foot", color: Self.ballColor, radius: 0.016),
            LessonTrail(name: "trail-standing-foot", color: Self.standColor, radius: 0.016),
            LessonTrail(name: "trail-ball", color: UIColor(white: 1, alpha: 0.6), radius: 0.012),
        ]
        footprints = makeFootprints()
        buildArrow()

        let content: [Entity] = [body.entity, ghost?.entity, ball, arrow].compactMap { $0 }
            + trails.map(\.entity) + footprints.map(\.entity)
        let com = analysis.frames.com
        let center = SIMD3<Float>(com.map { $0[0] }.reduce(0, +) / Float(com.count), 0,
                                  com.map { $0[2] }.reduce(0, +) / Float(com.count))
        let extent = clip.sequence.extent
        let stage = await StageBuilder.makeStage(content: content, floorCenter: center,
                                                 floorSize: Swift.max(extent.x, extent.z) + 8)
        stage.root.scale.x = mirror ? -1 : 1
        applyRoles()
        return stage.root
    }

    /// One flat print per planted spell, where the foot came down.
    private func makeFootprints() -> [Print] {
        let disc = MeshResource.generateCylinder(height: 0.004, radius: 0.07)
        return analysis.events.plants.compactMap { plant in
            guard plant.end - plant.start >= 3 else { return nil }
            let positions = plant.foot == .left ? analysis.frames.left : analysis.frames.right
            let p = positions[plant.start]
            let entity = ModelEntity(mesh: disc, materials: [UnlitMaterial(color: Self.standColor)])
            entity.name = "print-\(plant.foot.rawValue)-\(plant.start)"
            entity.position = [p[0], 0.003, p[2]]
            entity.scale = [1, 1, 1.5]
            entity.isEnabled = false
            return Print(entity: entity, foot: plant.foot, shot: package.shotIndex(ofFrame: plant.start),
                         start: plant.start, end: plant.end)
        }
    }

    /// Colours footprints by the selected skill's foot jobs.
    private func applyRoles() {
        let ballMaterial = UnlitMaterial(color: Self.ballColor), standMaterial = UnlitMaterial(color: Self.standColor)
        for print in footprints {
            print.entity.model?.materials = [print.foot == skill.ballFoot ? ballMaterial : standMaterial]
        }
        meshBallSide = nil
    }

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

    // MARK: - Skills and stages

    func select(_ skillID: String) {
        guard let next = package.document.skills.first(where: { $0.id == skillID }), next.id != skill.id else { return }
        skill = next
        loop = nil
        stopAt = nil
        lastGhostTime = -1
        applyRoles()
        enter(stage)
    }

    /// Sets up the stage: Watch plays the skill at full speed, Break it down opens on
    /// its first phase, and Practise and Test start still.
    func enter(_ stage: LessonStage) {
        self.stage = stage
        show(.source)
        switch stage {
        case .watch:
            overlays = LessonOverlays()
            play(skill.watch, rate: 1)
        case .breakdown:
            focus(on: skill.phases[0])
        case .practise:
            overlays = LessonOverlays(direction: false)
            loop = nil
            freeze(at: skill.range.lowerBound)
        case .test:
            overlays = LessonOverlays(footprints: false, direction: false)
            loop = nil
            freeze(at: skill.range.lowerBound)
        }
    }

    /// Freezes on a phase's key moment, loops the phase and switches the cues to the
    /// ones it asks for.
    func focus(on phase: LessonDocument.Phase) {
        overlays = phase.ov?.lessonOverlays ?? LessonOverlays()
        if let angle = phase.angle { show(angle) }
        loop = phase.start...phase.end
        freeze(at: phase.key)
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
            // Stay inside the loop, or else inside the selected skill.
            let bounds = loop ?? skill.range
            if t >= bounds.upperBound - 0.01 || t < bounds.lowerBound - 0.1 {
                t = bounds.lowerBound
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
    func play(_ range: ClosedRange<Double>, rate: Float) {
        loop = range
        stopAt = nil
        playback.speed = rate
        playback.seek(to: range.lowerBound)
        playback.player.rate = rate
    }

    /// Plays from `time` without a loop, stopping at `stop` if given.
    func play(from time: Double, rate: Float, stopAt stop: Double? = nil) {
        loop = nil
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
        if isPlaying {
            playback.pause()
        } else {
            let t = playback.currentTime
            if t < skill.range.lowerBound - 0.05 || t >= skill.range.upperBound - 0.05 { playback.seek(to: skill.range.lowerBound) }
            playback.player.rate = playback.speed
        }
    }

    func step(frames: Int) {
        let t = playback.currentTime + Double(frames) / analysis.fps
        freeze(at: Swift.min(Swift.max(t, skill.range.lowerBound), skill.range.upperBound - 0.01))
    }

    func toggleLoop() {
        if loop != nil {
            loop = nil
        } else {
            loop = phase.map { $0.start...$0.end } ?? skill.range
        }
    }

    func pause() { playback.pause() }

    func show(_ angle: CameraAngle) {
        self.angle = angle
        camera.show(angle)
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

    /// The ball, kept on the turf for a skill whose ball never leaves the ground.
    func ballPosition(frame i: Int) -> SIMD3<Float>? {
        guard let b = analysis.frames.ball[i] else { return nil }
        if skill.ballLeavesGround == false, analysis.frames.ballAir[i] == 1 {
            return [b[0], Float(analysis.ballDiameter / 2), b[2]]
        }
        return [b[0], b[1], b[2]]
    }

    /// Draws the moment at `time`. Internal so tests can drive it directly.
    func render(at time: Double) {
        guard let clip, let body else { return }
        let i = package.frame(at: time)
        let current = skill.phase(at: time)
        if current != phase { phase = current }

        if time != lastPoseTime, let sample = clip.sequence.sample(at: time), let pose = clip.pose(sample.index) {
            body.show(pose, blendingTo: sample.blend > 0 ? clip.pose(sample.next) : nil, amount: sample.blend)
            lastPoseTime = time
        }
        hasBody = analysis.frames.valid[i] == 1
        body.entity.isEnabled = hasBody && lastPoseTime >= 0
        // A corrected leg swap moves the colours with the real feet.
        let side = analysis.frames.legSwap[i] == 1 ? skill.ballFoot.other : skill.ballFoot
        if side != meshBallSide {
            meshBallSide = side
            let ball = Self.material(Self.ballColor), stand = Self.material(Self.standColor)
            body.setHighlightMaterials(side == .left ? [ball, stand] : [stand, ball])
        }
        renderGhost(for: current, in: clip, frame: i)

        let position = ballPosition(frame: i)
        ball.isEnabled = position != nil
        if let position { ball.position = position }

        if i != lastFrame {
            lastFrame = i
            updateReadings(frame: i, phase: current)
            renderTrails(frame: i, phase: current)
            renderFootprints(frame: i)
            renderArrow(frame: i)
        }
        if overlays.follow {
            let c = analysis.frames.com[i]
            let goal = SIMD3<Float>(mirror ? -c[0] : c[0], 0.8, c[2])
            camera.target += (goal - camera.target) * 0.15
        }
    }

    private func renderGhost(for phase: LessonDocument.Phase?, in clip: MotionClip, frame i: Int) {
        guard let ghost else { return }
        let shot = package.shotIndex(ofFrame: i)
        let previous = phase.flatMap { current in
            skill.phases.last { $0.key < current.start && package.shotIndex(ofFrame: package.frame(at: $0.key)) == shot }
        }
        guard overlays.ghost, let previous else {
            ghost.entity.isEnabled = false
            return
        }
        if previous.key != lastGhostTime, let pose = clip.pose(package.frame(at: previous.key)) {
            ghost.show(pose)
            lastGhostTime = previous.key
        }
        ghost.entity.isEnabled = lastGhostTime == previous.key
    }

    private func positions(_ side: LessonDocument.Side) -> [[Float]] {
        side == .left ? analysis.frames.left : analysis.frames.right
    }

    private func planted(_ side: LessonDocument.Side, _ i: Int) -> Bool {
        (side == .left ? analysis.frames.leftPlanted : analysis.frames.rightPlanted)[i] == 1
    }

    private func updateReadings(frame i: Int, phase: LessonDocument.Phase?) {
        let f = analysis.frames
        ballPlanted = planted(skill.ballFoot, i)
        standPlanted = planted(skill.ballFoot.other, i)
        let towardRight = Swift.min(Swift.max(f.weight[i], 0), 1)
        weight = skill.ballFoot == .right ? towardRight : 1 - towardRight
        dropCm = f.comDropCm[i]
        if let phase, phase.turn == true {
            turnDegrees = abs(f.yaw[i] - f.yaw[package.frame(at: phase.start)])
        } else {
            turnDegrees = nil
        }
        let speed = f.ballSpeed[i]
        if f.ball[i] == nil {
            ballText = "not tracked"
        } else if f.ballAir[i] == 1, skill.ballLeavesGround != false {
            ballText = "in the air"
        } else if speed > 1.5, speed < 15 {
            ballText = String(format: "≈%.1f m/s", speed)
        } else {
            ballText = speed > 0.5 && speed < 15 ? "rolling" : "close"
        }
    }

    private func renderTrails(frame i: Int, phase: LessonDocument.Phase?) {
        guard overlays.paths else {
            trails.forEach { $0.entity.isEnabled = false }
            return
        }
        let shotStart = analysis.shots[package.shotIndex(ofFrame: i)].start
        let from = Swift.max(shotStart, package.frame(at: phase?.start ?? skill.range.lowerBound), i - Int(1.5 * analysis.fps))
        let frames = Array(Swift.min(from, i)...i)
        let f = analysis.frames
        let ballFoot = positions(skill.ballFoot), standFoot = positions(skill.ballFoot.other)
        trails[0].show(frames.map { [f.com[$0][0], 0.01, f.com[$0][2]] })
        trails[1].show(frames.map { [ballFoot[$0][0], ballFoot[$0][1], ballFoot[$0][2]] })
        trails[2].show(frames.map { [standFoot[$0][0], standFoot[$0][1], standFoot[$0][2]] })
        trails[3].show(frames.compactMap { ballPosition(frame: $0) })
    }

    private func renderFootprints(frame i: Int) {
        let shot = package.shotIndex(ofFrame: i)
        let first = package.frame(at: skill.range.lowerBound)
        for print in footprints {
            let visible = overlays.footprints && print.shot == shot && print.start <= i && print.start >= first - 1
            print.entity.isEnabled = visible
            if visible {
                print.entity.components.set(OpacityComponent(opacity: print.end >= i ? 0.9 : 0.35))
            }
        }
    }

    /// Where the body's mass is heading, from a short window within the shot.
    private func renderArrow(frame i: Int) {
        let shot = analysis.shots[package.shotIndex(ofFrame: i)]
        let w = Swift.max(1, Int(0.1 * analysis.fps))
        let a = Swift.max(i - w, shot.start), b = Swift.min(i + w, shot.end - 1)
        let c0 = analysis.frames.com[a], c1 = analysis.frames.com[b]
        let dx = c1[0] - c0[0], dz = c1[2] - c0[2]
        let speed = (dx * dx + dz * dz).squareRoot() / Swift.max(Float(b - a) / Float(analysis.fps), 1e-3)
        guard overlays.direction, hasBody, speed > 0.35, speed < 8 else {
            arrow.isEnabled = false
            return
        }
        let length = Swift.min(Swift.max(speed * 0.35, 0.3), 1.3)
        let c = analysis.frames.com[i]
        arrow.position = [c[0], 0.03, c[2]]
        arrow.orientation = simd_quatf(angle: atan2(dx, dz), axis: [0, 1, 0])
        arrow.findEntity(named: "shaft")?.scale = [1, length, 1]
        arrow.findEntity(named: "shaft")?.position = [0, 0, length / 2]
        arrow.findEntity(named: "head")?.position = [0, 0, length + 0.07]
        arrow.isEnabled = true
    }

    private struct Print {
        let entity: ModelEntity
        let foot: LessonDocument.Side
        let shot: Int
        let start: Int
        let end: Int
    }
}
