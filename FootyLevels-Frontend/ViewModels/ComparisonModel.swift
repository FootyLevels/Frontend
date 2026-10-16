import AVFoundation
import Foundation
import Observation
import RealityKit
import UIKit

/// Two clips' bodies compared on one clock — A in blue, B in orange — either
/// overlaid in one scene with B moved onto A's center of mass, or side by side
/// in two scenes.
///
/// A's video is the clock, as in the motion inspector. B follows it shifted by
/// `offset` — in 3D and on its own video — so lining up two attempts is one
/// slider. Each layout keeps its own pair of bodies, so switching never moves
/// a live mesh between 3D views; only the visible pair is updated each frame,
/// and the motion itself is loaded once and shared. Nothing here scores or
/// judges either movement.
///
/// The iOS Simulator draws only the first RealityView on screen, so side by
/// side B's stage stays frozen there; check that layout on a device.
@MainActor
@Observable
final class ComparisonModel {

    enum LoadState: Equatable {
        case loading(String)
        case ready
        case failed(String)
    }

    enum Layout: String, CaseIterable, Identifiable {
        case overlay = "Overlay"
        case sideBySide = "Side by side"

        var id: String { rawValue }
    }

    enum ComparisonError: LocalizedError {
        case motionMissing

        var errorDescription: String? { "Both videos need their 3D motion built before they can be compared." }
    }

    /// A transparency of 1 would hide a body completely.
    static let maxTransparency = 0.9

    let first: SkillLabProject
    let second: SkillLabProject
    /// A's video, and the clock for everything else.
    let playback: PlaybackController
    /// B's video, kept on A's clock by `syncSecondVideo`.
    let secondVideo: AVPlayer

    var state: LoadState = .loading("Loading both motions…")
    private(set) var layout: Layout = .overlay
    /// Both bodies in one scene.
    private(set) var overlayRoot: Entity?
    /// One body each, built the first time side by side is shown.
    private(set) var firstRoot: Entity?
    private(set) var secondRoot: Entity?
    var angle: CameraAngle = .source
    /// A's frame, for the stage label.
    var currentFrame = 0
    var firstMissing = false
    var secondMissing = false

    /// Overlay only; side by side, both bodies are solid. 0 is solid.
    var firstTransparency = 0.1 { didSet { applyTransparency() } }
    var secondTransparency = 0.45 { didSet { applyTransparency() } }
    /// Seconds added to A's time to find B's: positive shows B further into its clip.
    var offset = 0.0 { didSet { redraw() } }
    /// Degrees B is turned about the vertical axis through its center of mass.
    var turn = 0.0 { didSet { redraw() } }
    /// Overlay only: pins B's center of mass to A's in every frame.
    var locksCenterOfMass = true { didSet { redraw() } }
    var follow = true { didSet { redraw() } }
    /// Side by side only: orbiting or zooming one stage moves the other too.
    var linksCameras = true { didSet { if linksCameras { secondCamera.match(firstCamera) } } }

    @ObservationIgnored let camera = OrbitCamera()
    @ObservationIgnored let firstCamera = OrbitCamera()
    @ObservationIgnored let secondCamera = OrbitCamera()
    @ObservationIgnored private var clips: (first: MotionClip, second: MotionClip)?
    @ObservationIgnored private var overlayBodies: (first: AnimatedBodyMesh, second: AnimatedBodyMesh)?
    /// Built the first time side by side is shown.
    @ObservationIgnored private var sideBodies: (first: AnimatedBodyMesh, second: AnimatedBodyMesh)?
    /// The last known centers, so a body's stage holds still while it has no pose.
    @ObservationIgnored private var firstCenter: SIMD3<Float>?
    @ObservationIgnored private var secondCenter: SIMD3<Float>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var sideStages: Task<(Entity, Entity), Never>?
    @ObservationIgnored private var lastSecondSeek = -1.0
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var streaming: [Task<Void, Never>] = []

    init(first: SkillLabProject, second: SkillLabProject) throws {
        self.first = first
        self.second = second
        let client = SkillLabClient.shared
        playback = PlaybackController(url: try client.url(for: first.video.url), duration: first.video.duration)
        secondVideo = AVPlayer(url: try client.url(for: second.video.url))
        secondVideo.isMuted = true
        secondVideo.actionAtItemEnd = .pause
        // Required by `setRate(_:time:atHostTime:)`, which starts B in step with A.
        secondVideo.automaticallyWaitsToMinimizeStalling = false
    }

    // MARK: - Time

    /// Where B is in its own clip when A is at `time`, held at its ends.
    static func secondTime(forFirst time: Double, offset: Double, secondDuration: Double) -> Double {
        Swift.min(Swift.max(time + offset, 0), Swift.max(secondDuration, 0))
    }

    /// Enough shift either way to line up any moment of A with any moment of B.
    var offsetRange: ClosedRange<Double> { -first.video.duration...Swift.max(second.video.duration, 0.01) }

    /// Moves B by whole frames, for fine alignment.
    func nudgeOffset(frames: Int) {
        let fps = clips?.second.sequence.fps ?? second.video.fps
        offset = Swift.min(Swift.max(offset + Double(frames) / Swift.max(fps, 1), offsetRange.lowerBound),
                           offsetRange.upperBound)
    }

    // MARK: - Loading

    func load() async {
        guard !started else { return }
        started = true
        do {
            guard let firstPath = first.motion?.sequenceUrl, let secondPath = second.motion?.sequenceUrl else {
                throw ComparisonError.motionMissing
            }
            async let loadFirst = MotionClip.load(projectId: first.id, sequencePath: firstPath)
            async let loadSecond = MotionClip.load(projectId: second.id, sequencePath: secondPath)
            let clips = (first: try await loadFirst, second: try await loadSecond)
            let bodies = try makeBodies(clips, names: ("overlay-first", "overlay-second"))
            self.clips = clips
            overlayBodies = bodies
            applyTransparency()

            // Fetch the rest of both clips while the scene is being built.
            streaming = [clips.first, clips.second].map { clip in
                Task { [weak self] in
                    await clip.loadRemainingChunks { self?.redraw() }
                }
            }

            // The floor follows A; B is moved onto A, so it stands on the same floor.
            let stage = await StageBuilder.makeStage(content: [bodies.first.entity, bodies.second.entity],
                                                     floorCenter: Self.floorCenter(clips.first),
                                                     floorSize: Self.floorSize(clips.first))
            overlayRoot = stage.root
            for (orbit, distance) in [(camera, Float(4.1)), (firstCamera, 4.6), (secondCamera, 4.6)] {
                orbit.homeDistance = distance
                orbit.distanceRange = 0.7...25
                orbit.show(.source)
            }

            redraw()
            // Two clips are rarely filmed from the same side.
            matchFacing()
            observePlayback()
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func makeBodies(_ clips: (first: MotionClip, second: MotionClip),
                            names: (String, String)) throws -> (first: AnimatedBodyMesh, second: AnimatedBodyMesh) {
        (first: try makeBody(clips.first, color: SL.overlayFirst, name: names.0),
         second: try makeBody(clips.second, color: SL.overlaySecond, name: names.1))
    }

    private func makeBody(_ clip: MotionClip, color: UIColor, name: String) throws -> AnimatedBodyMesh {
        var material = StageBuilder.bodyMaterial
        material.color = .init(tint: color)
        let body = try AnimatedBodyMesh(sequence: clip.sequence, indices: clip.indices, material: material)
        body.entity.name = name
        return body
    }

    /// The pair drawn in the current layout; the other pair isn't updated.
    private var bodies: (first: AnimatedBodyMesh, second: AnimatedBodyMesh)? {
        layout == .sideBySide ? sideBodies : overlayBodies
    }

    private static func floorCenter(_ clip: MotionClip) -> SIMD3<Float> {
        (clip.sequence.lowerBound + clip.sequence.upperBound) / 2
    }

    private static func floorSize(_ clip: MotionClip) -> Float {
        Swift.max(clip.sequence.extent.x, clip.sequence.extent.z) + 10
    }

    // MARK: - Layout

    /// Shows `layout`, building the side-by-side scenes and their bodies the
    /// first time they're needed.
    func setLayout(_ layout: Layout) async {
        guard let clips else {
            self.layout = layout
            return
        }
        if layout == .sideBySide, sideStages == nil {
            sideStages = Task {
                guard let bodies = try? makeBodies(clips, names: ("side-first", "side-second")) else {
                    return (Entity(), Entity())
                }
                sideBodies = bodies
                let first = await StageBuilder.makeStage(content: [bodies.first.entity],
                                                         floorCenter: Self.floorCenter(clips.first),
                                                         floorSize: Self.floorSize(clips.first))
                let second = await StageBuilder.makeStage(content: [bodies.second.entity],
                                                          floorCenter: Self.floorCenter(clips.second),
                                                          floorSize: Self.floorSize(clips.second))
                firstCamera.show(angle)
                secondCamera.show(angle)
                return (first.root, second.root)
            }
        }
        self.layout = layout
        if layout == .sideBySide, let roots = await sideStages?.value {
            firstRoot = roots.0
            secondRoot = roots.1
        }
        redraw()
    }

    // MARK: - Controls

    func show(_ angle: CameraAngle) {
        self.angle = angle
        for orbit in [camera, firstCamera, secondCamera] {
            orbit.show(angle)
        }
    }

    /// Called after a gesture moved one side-by-side camera.
    func cameraMoved(_ moved: OrbitCamera) {
        guard linksCameras else { return }
        (moved === firstCamera ? secondCamera : firstCamera).match(moved)
    }

    /// Turns B to face the way A faces in the current frame.
    func matchFacing() {
        guard let clips, let bodies, bodies.first.entity.isEnabled, bodies.second.entity.isEnabled,
              let yaw = OverlayAlignment.facingYaw(aligning: bodies.second.positions,
                                                   about: center(of: bodies.second, in: clips.second),
                                                   to: bodies.first.positions,
                                                   about: center(of: bodies.first, in: clips.first)) else { return }
        turn = (Double(yaw) * 180 / .pi).rounded()
    }

    var canMatchFacing: Bool { state == .ready && !firstMissing && !secondMissing }

    /// Overlay bodies only: side by side, each body is alone in its stage and solid.
    private func applyTransparency() {
        guard let bodies = overlayBodies else { return }
        for (body, transparency) in [(bodies.first, firstTransparency), (bodies.second, secondTransparency)] {
            let clamped = Swift.min(Swift.max(transparency, 0), Self.maxTransparency)
            body.entity.components.set(OpacityComponent(opacity: Float(1 - clamped)))
        }
    }

    // MARK: - Playback

    private func observePlayback() {
        let interval = CMTime(value: 1, timescale: 60)
        timeObserver = playback.player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.render(time: time.seconds)
                self.syncSecondVideo(firstTime: time.seconds)
            }
        }
    }

    /// Redraws the current moment after a control changed.
    private func redraw() {
        let time = playback.player.currentTime().seconds
        render(time: time)
        syncSecondVideo(firstTime: time)
    }

    private func render(time: Double) {
        guard let clips, let bodies else { return }
        let firstTime = time.isFinite ? time : 0
        let firstSample = clips.first.sequence.sample(at: firstTime)
        let secondSample = clips.second.sequence.sample(
            at: Self.secondTime(forFirst: firstTime, offset: offset, secondDuration: second.video.duration))

        let firstShown = show(bodies.first, clip: clips.first, sample: firstSample)
        let secondShown = show(bodies.second, clip: clips.second, sample: secondSample)

        if let index = firstSample?.index, index != currentFrame { currentFrame = index }
        let firstMissing = firstSample.map { !clips.first.sequence.frames[$0.index].valid } ?? true
        let secondMissing = secondSample.map { !clips.second.sequence.frames[$0.index].valid } ?? true
        if firstMissing != self.firstMissing { self.firstMissing = firstMissing }
        if secondMissing != self.secondMissing { self.secondMissing = secondMissing }

        if firstShown {
            firstCenter = center(of: bodies.first, in: clips.first)
        }
        if secondShown {
            let center = center(of: bodies.second, in: clips.second)
            secondCenter = center
            // Overlaid, B can be moved onto A; side by side it only turns in place.
            let target = layout == .overlay && locksCenterOfMass ? (firstCenter ?? center) : center
            bodies.second.entity.transform = OverlayAlignment.transform(moving: center, onto: target,
                                                                        yaw: Float(turn * .pi / 180))
        }

        guard follow else { return }
        switch layout {
        case .overlay:
            if let firstCenter { camera.target = firstCenter }
        case .sideBySide:
            if let firstCenter { firstCamera.target = firstCenter }
            if let secondCenter { secondCamera.target = secondCenter }
        }
    }

    /// Writes the sampled pose into `body`, or hides it when there's none —
    /// missing frames hold placeholder data that must never be drawn.
    private func show(_ body: AnimatedBodyMesh, clip: MotionClip, sample: MotionSequence.Sample?) -> Bool {
        guard let sample, clip.sequence.frames[sample.index].valid, let pose = clip.pose(sample.index) else {
            body.entity.isEnabled = false
            return false
        }
        body.show(pose, blendingTo: sample.blend > 0 ? clip.pose(sample.next) : nil, amount: sample.blend)
        body.entity.isEnabled = true
        return true
    }

    private func center(of body: AnimatedBodyMesh, in clip: MotionClip) -> SIMD3<Float> {
        OverlayAlignment.centerOfMass(positions: body.positions, indices: clip.indices)
    }

    /// Keeps B's video on A's clock, shifted by `offset`.
    ///
    /// While A plays, B is started at the matching time on the system clock,
    /// and restarted only when the rate changes or it drifts noticeably —
    /// seeking a playing video every tick stutters and can crash AVFoundation.
    /// While A is paused, or B is held at one of its ends, B is parked on the
    /// exact frame.
    private func syncSecondVideo(firstTime: Double) {
        let time = firstTime.isFinite ? firstTime : 0
        let target = Self.secondTime(forFirst: time, offset: offset, secondDuration: second.video.duration)
        let rate = playback.player.rate
        let insideClip = time + offset > 0 && time + offset < second.video.duration - 0.02

        if rate != 0, insideClip {
            let drift = abs(secondVideo.currentTime().seconds - target)
            if secondVideo.rate != rate || drift > 0.2 {
                lastSecondSeek = target
                secondVideo.setRate(rate, time: CMTime(seconds: target, preferredTimescale: 600),
                                    atHostTime: CMClockGetTime(CMClockGetHostTimeClock()))
            }
        } else {
            if secondVideo.rate != 0 { secondVideo.pause() }
            if abs(lastSecondSeek - target) > 0.5 / 60 {
                lastSecondSeek = target
                secondVideo.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                                 toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
    }

    /// Stops both videos without releasing anything, e.g. on a tab switch.
    func pause() {
        playback.pause()
        secondVideo.pause()
    }

    func teardown() {
        streaming.forEach { $0.cancel() }
        sideStages?.cancel()
        if let timeObserver {
            playback.player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        playback.teardown()
        secondVideo.pause()
    }
}
