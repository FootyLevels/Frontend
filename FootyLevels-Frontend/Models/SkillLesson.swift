import Foundation
import Observation

/// The Over Fake lesson's measurements, taken offline from the included
/// example's 3D motion and shipped as `OverFake.bundle/lesson.json`.
///
/// Positions are in the motion's own space (Y-up metres, filming camera at +z).
/// The anatomical left foot is the "front" foot in this lesson and the right
/// foot the "stepping" foot; `weight` runs from 0 (over the left foot) to 1
/// (over the right).
struct SkillLesson: Decodable {
    struct Shot: Decodable {
        let id: Int
        let start: Double
        let end: Double
    }

    struct FootSets: Decodable {
        let left: [UInt32]
        let right: [UInt32]
    }

    struct Phase: Decodable, Identifiable, Equatable {
        let id: String
        let shot: Int
        let start: Double
        let end: Double
        /// The moment that best shows the phase, for freezing on it.
        let key: Double
    }

    struct Events: Decodable {
        struct Sell: Decodable { let frame: Int; let dropCm: Double; let weight: Double }
        struct Pass: Decodable { let frame: Int; let footToBallM: Double; let soleCm: Double }
        struct Plant: Decodable { let frame: Int; let transferFrame: Int }
        struct Shift: Decodable { let frame: Int; let leftLiftCm: Double; let liftFrame: Int }
        struct Turn: Decodable { let from: Int; let to: Int; let degrees: Double }
        struct Go: Decodable { let frame: Int; let ballSpeedMs: Double }

        let sell: Sell
        let pass: Pass
        let plant: Plant
        let shift: Shift
        let turn: Turn
        let go: Go
    }

    /// One value per video frame.
    struct Frames: Decodable {
        let com: [[Float]]
        let comDropCm: [Double]
        let weight: [Double]
        let leftPlanted: [Int]
        let rightPlanted: [Int]
        let left: [[Float]]
        let right: [[Float]]
        let yaw: [Double]
        let ballSpeed: [Double]
    }

    struct Ball: Decodable {
        let diameter: Double
        let positions: [[Float]?]
    }

    let fps: Double
    let frameCount: Int
    let duration: Double
    let shots: [Shot]
    let footSets: FootSets
    let events: Events
    let phases: [Phase]
    let frames: Frames
    let ball: Ball

    enum LoadError: LocalizedError {
        case missing
        case inconsistent

        var errorDescription: String? {
            switch self {
            case .missing: return "The lesson data isn't in this build of the app."
            case .inconsistent: return "The lesson data is damaged."
            }
        }
    }

    static func decode(_ data: Data) throws -> SkillLesson {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let lesson = try decoder.decode(SkillLesson.self, from: data)
        // Every per-frame series must cover the clip, or lookups would trap.
        let n = lesson.frameCount
        let f = lesson.frames
        guard n > 0, lesson.shots.count == 2, !lesson.phases.isEmpty,
              [f.com.count, f.comDropCm.count, f.weight.count, f.leftPlanted.count, f.rightPlanted.count,
               f.left.count, f.right.count, f.yaw.count, f.ballSpeed.count, lesson.ball.positions.count].allSatisfy({ $0 == n }),
              f.com.allSatisfy({ $0.count == 3 }), f.left.allSatisfy({ $0.count == 3 }), f.right.allSatisfy({ $0.count == 3 })
        else { throw LoadError.inconsistent }
        return lesson
    }

    /// The lesson that ships inside the included example's bundle.
    static func bundled() throws -> SkillLesson {
        guard let url = BundledSample.fileURL(forAssetPath: "/assets-data/\(BundledSample.id)/lesson.json") else {
            throw LoadError.missing
        }
        return try decode(Data(contentsOf: url))
    }

    // MARK: - Time

    func frame(at seconds: Double) -> Int {
        let t = seconds.isFinite ? seconds : 0
        return Swift.min(Swift.max(Int((t * fps).rounded()), 0), frameCount - 1)
    }

    func time(ofFrame frame: Int) -> Double { Double(frame) / fps }

    /// 0 for the full-speed demo, 1 for the slow tutorial.
    func shot(ofFrame frame: Int) -> Int {
        frame < Int((shots[1].start * fps).rounded()) ? 0 : 1
    }

    func phase(at seconds: Double) -> Phase {
        phases.first { seconds >= $0.start && seconds < $0.end } ?? phases[phases.count - 1]
    }

    func phase(_ id: String) -> Phase? { phases.first { $0.id == id } }

    /// The phase before `phase` in the same shot, skipping the tutorial pause:
    /// what the ghost pose shows.
    func previousKeyPhase(before phase: Phase) -> Phase? {
        phases.last { $0.shot == phase.shot && $0.key < phase.start && $0.id != "pause" }
    }
}

// MARK: - Challenges

/// How a "tap when it happens" answer compares with the measured moment.
enum TapVerdict: Equatable {
    case missed
    case onTime(Double)
    case early(Double)
    case late(Double)

    /// `tolerance` seconds either side counts as on time.
    static func judge(tapped: Double?, target: Double, tolerance: Double = 0.1) -> TapVerdict {
        guard let tapped else { return .missed }
        let error = tapped - target
        if abs(error) <= tolerance { return .onTime(error) }
        return error < 0 ? .early(-error) : .late(error)
    }

    var isCorrect: Bool { if case .onTime = self { return true } else { return false } }
}

enum PhaseOrder {
    /// How many picks sit in the wrong place.
    static func misplaced(_ picked: [String], correct: [String]) -> Int {
        zip(picked, correct).filter { $0 != $1 }.count + abs(correct.count - picked.count)
    }
}

// MARK: - Drill progress

struct DrillProgress: Codable, Equatable {
    var reps = 0
    var checks: [Bool] = []

    func isComplete(targetReps: Int, checkCount: Int) -> Bool {
        reps >= targetReps && (0..<checkCount).allSatisfy { $0 < checks.count && checks[$0] }
    }

    mutating func setCheck(_ index: Int, _ on: Bool) {
        if checks.count <= index { checks += Array(repeating: false, count: index - checks.count + 1) }
        checks[index] = on
    }
}

/// Keeps drill progress on this device, between launches.
@MainActor
@Observable
final class DrillProgressStore {
    private(set) var all: [String: DrillProgress]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String

    init(defaults: UserDefaults = .standard, key: String = "lesson.overfake.drills") {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([String: DrillProgress].self, from: data) {
            all = saved
        } else {
            all = [:]
        }
    }

    func progress(_ id: String) -> DrillProgress { all[id] ?? DrillProgress() }

    func update(_ id: String, _ change: (inout DrillProgress) -> Void) {
        var progress = progress(id)
        change(&progress)
        all[id] = progress
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: key)
        }
    }

    func reset(_ id: String) { update(id) { $0 = DrillProgress() } }
}
