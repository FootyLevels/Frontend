import Foundation

/// A lesson made by the lesson pipeline (`3d-model-backend/lesson_pipeline`) and shipped
/// as `Lesson-<id>.bundle`: the lesson text, the measurements taken from the 3D motion,
/// the light body mesh's foot sets, the motion itself and the video.
///
/// The format is described in `lesson_pipeline/SPEC.md`. Feet are named by their job
/// in each skill: the *ball foot* works the ball, the *standing foot* is the other one.
struct LessonPackage {
    let url: URL
    let document: LessonDocument
    let analysis: LessonAnalysis
    let footSets: FootSets

    var videoURL: URL { url.appendingPathComponent("video.mp4") }
    var motionDirectory: URL { url.appendingPathComponent("motion", isDirectory: true) }

    struct FootSets: Decodable {
        let left: [UInt32]
        let right: [UInt32]
    }

    private struct Mesh: Decodable {
        let vertexCount: Int
        let footSets: FootSets
    }

    enum LoadError: LocalizedError, Equatable {
        case missing(String)
        case inconsistent(String)

        var errorDescription: String? {
            switch self {
            case .missing(let file): return "This lesson is missing \(file)."
            case .inconsistent(let why): return "This lesson's data doesn't fit together: \(why)."
            }
        }
    }

    static func load(_ url: URL) throws -> LessonPackage {
        func read(_ name: String) throws -> Data {
            do { return try Data(contentsOf: url.appendingPathComponent(name)) } catch { throw LoadError.missing(name) }
        }
        let decoder = JSONDecoder()
        let document = try decoder.decode(LessonDocument.self, from: read("lesson.json"))
        let analysis = try decoder.decode(LessonAnalysis.self, from: read("analysis.json"))
        let mesh = try decoder.decode(Mesh.self, from: read("mesh.json"))
        let package = LessonPackage(url: url, document: document, analysis: analysis, footSets: mesh.footSets)
        try package.check(meshVertexCount: mesh.vertexCount)
        return package
    }

    /// Everything a screen indexes into must exist, or a lookup could trap.
    func check(meshVertexCount: Int) throws {
        let n = analysis.frameCount
        let f = analysis.frames
        let lengths = [f.com.count, f.comDropCm.count, f.weight.count, f.left.count, f.right.count,
                       f.leftPlanted.count, f.rightPlanted.count, f.yaw.count, f.ball.count, f.ballSpeed.count,
                       f.valid.count, f.ballAir.count, f.legSwap.count]
        guard n > 0, analysis.fps > 0, lengths.allSatisfy({ $0 == n }) else {
            throw LoadError.inconsistent("the measurements don't cover every frame")
        }
        guard !analysis.shots.isEmpty, analysis.shots.allSatisfy({ $0.start >= 0 && $0.start < $0.end && $0.end <= n }) else {
            throw LoadError.inconsistent("the shots don't fit the clip")
        }
        guard (footSets.left + footSets.right).allSatisfy({ Int($0) < meshVertexCount }),
              !footSets.left.isEmpty, !footSets.right.isEmpty else {
            throw LoadError.inconsistent("the foot sets don't fit the body mesh")
        }
        guard document.schemaVersion == 1, !document.skills.isEmpty else {
            throw LoadError.inconsistent("unsupported lesson format")
        }
        let duration = analysis.duration + 0.05
        for skill in document.skills {
            let range = skill.range
            guard range.lowerBound >= 0, range.upperBound <= duration, skill.phases.count >= 2 else {
                throw LoadError.inconsistent("skill \(skill.id) is outside the clip")
            }
            var previous = range.lowerBound - 0.01
            for phase in skill.phases {
                guard phase.start >= previous - 0.01, phase.start < phase.end,
                      phase.end <= range.upperBound + 0.01, (phase.start - 0.01...phase.end + 0.01).contains(phase.key) else {
                    throw LoadError.inconsistent("phase \(phase.id) of \(skill.id) is out of order or outside its skill")
                }
                previous = phase.end
            }
            for drill in skill.drills where !(range.lowerBound - 0.01...range.upperBound + 0.01).contains(drill.model.lowerBound)
                || drill.model.upperBound > range.upperBound + 0.01 {
                throw LoadError.inconsistent("drill \(drill.id) of \(skill.id) is outside its skill")
            }
            let ids = Set(skill.phases.map(\.id))
            for challenge in skill.challenges {
                if case .order(let order) = challenge, !Set(order.ids).isSubset(of: ids) {
                    throw LoadError.inconsistent("an order challenge in \(skill.id) names a phase that doesn't exist")
                }
                if case .choice(let choice) = challenge, !choice.options.indices.contains(choice.answer) {
                    throw LoadError.inconsistent("a question in \(skill.id) has no right answer")
                }
            }
        }
    }

    // MARK: - Time

    func frame(at seconds: Double) -> Int {
        let t = seconds.isFinite ? seconds : 0
        return Swift.min(Swift.max(Int((t * analysis.fps).rounded()), 0), analysis.frameCount - 1)
    }

    func time(ofFrame frame: Int) -> Double { Double(frame) / analysis.fps }

    /// Index into `analysis.shots` of the shot holding `frame`.
    func shotIndex(ofFrame frame: Int) -> Int {
        analysis.shots.firstIndex { frame >= $0.start && frame < $0.end } ?? 0
    }

    /// The label and quality of the shot playing at `seconds`, from the lesson.
    func shotLabel(at seconds: Double) -> LessonDocument.Shot? {
        document.shots.first { seconds >= $0.start && seconds < $0.end }
    }
}

// MARK: - lesson.json

struct LessonDocument: Decodable {
    let schemaVersion: Int
    let id: String
    let title: String
    let accent: String?
    let subtitle: String
    let videoLabel: String?
    let sourceNote: String
    let shots: [Shot]
    let skills: [Skill]

    struct Shot: Decodable {
        let start: Double
        let end: Double
        let label: String
        let quality: String?

        var isRough: Bool { quality == "low" }
    }

    struct Skill: Decodable, Identifiable {
        let id: String
        let name: String
        let short: String
        let tab: String
        let ballFoot: Side
        let ballLeavesGround: Bool?
        private let rangeValues: [Double]
        private let watchValues: [Double]
        let watchTitle: String?
        let intro: String
        let notice: [Notice]
        let adds: String?
        let unsure: [String]?
        let breakdownIntro: String?
        let phases: [Phase]
        let drills: [Drill]
        let challenges: [Challenge]

        var range: ClosedRange<Double> { rangeValues[0]...Swift.max(rangeValues[0], rangeValues[1]) }
        var watch: ClosedRange<Double> { watchValues[0]...Swift.max(watchValues[0], watchValues[1]) }

        enum CodingKeys: String, CodingKey {
            case id, name, short, tab, ballFoot, ballLeavesGround, watchTitle, intro, notice, adds, unsure,
                 breakdownIntro, phases, drills, challenges
            case rangeValues = "range", watchValues = "watch"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            short = try c.decode(String.self, forKey: .short)
            tab = try c.decode(String.self, forKey: .tab)
            ballFoot = try c.decode(Side.self, forKey: .ballFoot)
            ballLeavesGround = try c.decodeIfPresent(Bool.self, forKey: .ballLeavesGround)
            rangeValues = try c.decode([Double].self, forKey: .rangeValues)
            watchValues = try c.decode([Double].self, forKey: .watchValues)
            guard rangeValues.count == 2, watchValues.count == 2 else {
                throw DecodingError.dataCorruptedError(forKey: .rangeValues, in: c, debugDescription: "range and watch are [start, end]")
            }
            watchTitle = try c.decodeIfPresent(String.self, forKey: .watchTitle)
            intro = try c.decode(String.self, forKey: .intro)
            notice = try c.decodeIfPresent([Notice].self, forKey: .notice) ?? []
            adds = try c.decodeIfPresent(String.self, forKey: .adds)
            unsure = try c.decodeIfPresent([String].self, forKey: .unsure)
            breakdownIntro = try c.decodeIfPresent(String.self, forKey: .breakdownIntro)
            phases = try c.decode([Phase].self, forKey: .phases)
            drills = try c.decode([Drill].self, forKey: .drills)
            challenges = try c.decodeIfPresent([Challenge].self, forKey: .challenges) ?? []
        }

        func phase(at seconds: Double) -> Phase? {
            phases.first { seconds >= $0.start && seconds < $0.end }
        }
    }

    enum Side: String, Decodable {
        case left, right

        var other: Side { self == .left ? .right : .left }
    }

    struct Notice: Decodable {
        let t: Double
        let title: String
        let text: String
    }

    struct Phase: Decodable, Identifiable, Equatable {
        let id: String
        let name: String
        let start: Double
        let end: Double
        let key: Double
        let cue: String
        let video: String?
        let shows: String?
        let conf: String?
        let why: String?
        let ov: Overlays?
        let focus: String?
        let view: String?
        let turn: Bool?

        static func == (a: Phase, b: Phase) -> Bool { a.id == b.id && a.start == b.start }

        var confidence: LessonConfidence? {
            switch conf {
            case "high": return .high
            case "medium": return .medium
            case "low": return .low
            default: return nil
            }
        }

        /// The 3D camera this phase asks for.
        var angle: CameraAngle? { LessonDocument.angle(for: view) }
    }

    /// The 3D camera a lesson's `view` names: video, side, behind or top.
    static func angle(for view: String?) -> CameraAngle? {
        switch view {
        case "video": return .source
        case "side": return .right
        case "behind": return .back
        case "top": return .above
        default: return nil
        }
    }

    struct Overlays: Decodable {
        let prints: Bool?
        let paths: Bool?
        let ghost: Bool?
        let arrow: Bool?
        let follow: Bool?

        var lessonOverlays: LessonOverlays {
            LessonOverlays(footprints: prints ?? true, paths: paths ?? true, ghost: ghost ?? false,
                           direction: arrow ?? true, follow: follow ?? true)
        }
    }

    struct Drill: Decodable, Identifiable {
        let id: String
        let title: String
        let lvl: String
        let reps: Int
        let how: String
        private let modelValues: [Double]
        let checks: [String]

        var model: ClosedRange<Double> {
            guard modelValues.count >= 2 else { return 0...0 }
            return modelValues[0]...Swift.max(modelValues[0], modelValues[1])
        }
        var rate: Float { modelValues.count > 2 ? Float(modelValues[2]) : 0.5 }

        enum CodingKeys: String, CodingKey {
            case id, title, lvl, reps, how, checks
            case modelValues = "model"
        }
    }

    enum Challenge: Decodable {
        case choice(Choice)
        case tap(Tap)
        case order(Order)

        struct Choice: Decodable {
            let t: Double
            let title: String
            let prompt: String
            let options: [String]
            let answer: Int
            let explain: String
            let play: [Double]?
            let view: String?
        }

        struct Tap: Decodable {
            let from: Double
            let target: Double
            let label: String
            let rate: Double?
            let tolerance: Double?
            let title: String
            let prompt: String
            let explain: String
        }

        struct Order: Decodable {
            let title: String?
            let prompt: String?
            let ids: [String]
            let shuffled: [String]?
        }

        var title: String {
            switch self {
            case .choice(let c): return c.title
            case .tap(let c): return c.title
            case .order(let c): return c.title ?? "Put it in order"
            }
        }

        private enum Kind: String, Decodable { case choice, tap, order }
        private enum TypeKey: String, CodingKey { case type }

        init(from decoder: Decoder) throws {
            let kind = try decoder.container(keyedBy: TypeKey.self).decode(Kind.self, forKey: .type)
            switch kind {
            case .choice: self = .choice(try Choice(from: decoder))
            case .tap: self = .tap(try Tap(from: decoder))
            case .order: self = .order(try Order(from: decoder))
            }
        }
    }
}

// MARK: - analysis.json

struct LessonAnalysis: Decodable {
    let fps: Double
    let frameCount: Int
    let duration: Double
    let shots: [Shot]
    let ballDiameter: Double
    let frames: Frames
    let events: Events

    struct Shot: Decodable {
        let start: Int
        let end: Int
        let camera: [Float]?
        let ballTrusted: Bool?
    }

    /// One value per video frame. Positions are metres, Y up, pitch at y = 0.
    struct Frames: Decodable {
        let com: [[Float]]
        let comDropCm: [Double]
        /// 0 = over the left foot, 1 = over the right.
        let weight: [Double]
        let left: [[Float]]
        let right: [[Float]]
        let leftPlanted: [Int]
        let rightPlanted: [Int]
        let yaw: [Double]
        let ball: [[Float]?]
        let ballSpeed: [Double]
        let valid: [Int]
        let ballAir: [Int]
        /// 1 where the mesh's left and right legs are swapped relative to the measured feet.
        let legSwap: [Int]
    }

    struct Events: Decodable {
        struct Plant: Decodable {
            let foot: LessonDocument.Side
            let start: Int
            let end: Int
        }
        let plants: [Plant]
    }
}
