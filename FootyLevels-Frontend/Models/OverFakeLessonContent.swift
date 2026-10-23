import Foundation

/// The four steps from watching the move to doing it.
enum LessonStage: String, CaseIterable, Identifiable {
    case watch = "Watch"
    case breakdown = "Break it down"
    case practise = "Practise"
    case test = "Test yourself"

    var id: String { rawValue }
    var number: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }
}

/// Which 3D cues are drawn.
struct LessonOverlays: Equatable {
    var footprints = true
    var paths = true
    var ghost = false
    var direction = true
    var follow = true
}

/// The info-bar reading a phase draws attention to.
enum LessonFocus {
    case weight, stepFoot, turn, ball
}

/// How far a statement drawn from the 3D can be trusted.
enum LessonConfidence {
    case high, medium, low

    var label: String {
        switch self {
        case .high: return "High confidence"
        case .medium: return "Medium confidence"
        case .low: return "Low confidence"
        }
    }
}

/// What the lesson says about one phase. Numbers come from the measurements.
struct LessonPhaseContent {
    let name: String
    let cue: String
    let watch: String
    let shows: (SkillLesson) -> String
    var confidence: LessonConfidence?
    var confidenceWhy = ""
    var overlays = LessonOverlays()
    var focus: LessonFocus?
    var angle: CameraAngle?
}

struct LessonDrill: Identifiable {
    let id: String
    let title: String
    let level: String
    let reps: Int
    let how: String
    let start: Double
    let end: Double
    let rate: Float
    var skipsPause = false
    let checks: [String]
}

/// The Over Fake lesson's text: grounded in the included tutorial clip and
/// its reconstructed motion. Nothing here rates the player.
enum OverFakeLessonContent {
    private static func at(_ lesson: SkillLesson, _ frame: Int) -> String {
        String(format: "%.2f s", lesson.time(ofFrame: frame))
    }

    static func phase(_ id: String) -> LessonPhaseContent {
        switch id {
        case "approach":
            return .init(name: "Approach", cue: "Run at the defender, ball close.",
                         watch: "The ball stays within a stride as he drives straight at the defender.",
                         shows: { _ in "" })
        case "fake":
            return .init(name: "The fake", cue: "Long, low step across the ball.",
                         watch: "He steps across the ball and his body drops much lower than in the slow tutorial.",
                         shows: { lesson in
                             let drop = lesson.frames.comDropCm[28..<55].max() ?? 0
                             return "His body drops about \(Int(drop.rounded())) cm here, against about \(Int(lesson.events.sell.dropCm.rounded())) cm in the tutorial."
                         })
        case "turn":
            return .init(name: "Turn and take", cue: "Turn on the planted foot, take it the other way.",
                         watch: "He turns back toward the ball and takes it the other way with his other foot.",
                         shows: { _ in "" })
        case "burst":
            return .init(name: "Burst past", cue: "Push it past and go.",
                         watch: "He pushes the ball past the defender and accelerates into the space.",
                         shows: { _ in "" })
        case "setup":
            return .init(name: "Set up", cue: "Ball just ahead of your front foot.",
                         watch: "He walks in side-on with the ball ahead of him.",
                         shows: { _ in "Both feet planted about 0.65 m apart, weight in the middle. The front (left) foot is about 0.6 m from the ball, the back (right) foot about 1.2 m." },
                         confidence: .high, confidenceWhy: "Both feet are flat and visible; slow movement.",
                         overlays: .init(footprints: true, paths: false, ghost: false, direction: false), focus: .weight)
        case "sell":
            return .init(name: "Sell it", cue: "Dip and lean onto your front foot.",
                         watch: "The upper body leans as he arrives at the ball.",
                         shows: { l in "His body drops about \(Self.cm(l.events.sell.dropCm)) by \(Self.at(l, l.events.sell.frame)) and his weight moves toward the front foot as the back foot starts to swing." },
                         confidence: .medium, confidenceWhy: "Weight is inferred from where the body sits between the feet.",
                         overlays: .init(footprints: true, paths: true, ghost: false, direction: false), focus: .weight)
        case "step":
            return .init(name: "Step across", cue: "Swing the back foot across, low and quick.",
                         watch: "Look at the stepping foot and the supporting knee from the side.",
                         shows: { l in "The right foot passes about \(Int((l.events.pass.footToBallM * 100).rounded())) cm from the ball\u{2019}s centre at \(Self.at(l, l.events.pass.frame)), only about \(Self.cm(l.events.pass.soleCm)) off the turf. It goes around the ball, not over the top, and never touches it." },
                         confidence: .medium, confidenceWhy: "One camera: the foot\u{2019}s exact path relative to the ball is approximate.",
                         overlays: .init(footprints: false, paths: true, ghost: true, direction: false), focus: .stepFoot, angle: .right)
        case "plant":
            return .init(name: "Plant past the ball", cue: "Land beyond the ball, then move onto it.",
                         watch: "The ball is now behind the planted foot.",
                         shows: { l in "The right foot lands at \(Self.at(l, l.events.plant.frame)); his weight is fully across by \(Self.at(l, l.events.plant.transferFrame)) while the front foot comes through." },
                         confidence: .high, confidenceWhy: "Foot contact and timing are clear in both the video and the 3D.",
                         overlays: .init(footprints: true, paths: false, ghost: true, direction: false), focus: .stepFoot)
        case "pause":
            return .init(name: "Tutorial pause", cue: "The coach resets for step 2.",
                         watch: "Nothing to copy here.",
                         shows: { _ in "In the tutorial he stops here. In a match the next part follows straight after the plant, as in the full-speed demo." },
                         overlays: .init(footprints: true, paths: false, ghost: false, direction: false))
        case "shift":
            return .init(name: "Shift weight", cue: "Load the planted foot; let the other leg swing.",
                         watch: "Compare the hips with the planted foot.",
                         shows: { l in "His weight moves over and past the planted right foot by \(Self.at(l, l.events.shift.frame)); the other leg swings out, the foot about \(Self.cm(l.events.shift.leftLiftCm)) up at \(Self.at(l, l.events.shift.liftFrame))." },
                         confidence: .medium, confidenceWhy: "Weight is inferred, not measured force.",
                         overlays: .init(footprints: true, paths: true, ghost: false, direction: false), focus: .weight)
        case "change":
            return .init(name: "Change direction", cue: "Turn on the planted foot, back to the ball.",
                         watch: "Use the side view to check knee bend as the body turns.",
                         shows: { l in "His feet turn about \(Int(l.events.turn.degrees.rounded()))\u{00B0} between \(Self.at(l, l.events.turn.from)) and \(Self.at(l, l.events.turn.to)): half a second to face the other way." },
                         confidence: .medium, confidenceWhy: "The turn is measured from the feet; the camera\u{2019}s own turn isn\u{2019}t recovered, but it barely moves here.",
                         overlays: .init(footprints: true, paths: false, ghost: true, direction: true), focus: .turn, angle: .above)
        default: // "go"
            return .init(name: "Take it and go", cue: "Take it with the other foot and accelerate.",
                         watch: "Look at the push-off and torso angle, then the ball\u{2019}s path.",
                         shows: { l in "The front foot meets the ball and it leaves at \(Self.at(l, l.events.go.frame)) at roughly \(String(format: "%.1f", l.events.go.ballSpeedMs)) m/s. He runs off after it, away from the camera." },
                         confidence: .low, confidenceWhy: "Which part of the foot touches the ball can\u{2019}t be seen reliably; speeds are rough.",
                         overlays: .init(footprints: false, paths: true, ghost: false, direction: true), focus: .ball)
        }
    }

    private static func cm(_ value: Double) -> String { "\(Int(value.rounded())) cm" }

    /// Moments to look for in the full-speed demo.
    static let watchMoments: [(time: Double, phase: String)] = [
        (0.6, "approach"), (1.15, "fake"), (1.7, "turn"), (2.3, "burst"),
    ]

    /// The tutorial phases in order, without the pause.
    static let order = ["setup", "sell", "step", "plant", "shift", "change", "go"]

    static let drills: [LessonDrill] = [
        .init(id: "footwork", title: "Footwork only", level: "No ball · walking pace", reps: 10,
              how: "Mark a spot as the ball. Dip, swing your back foot across it and plant past it. Hold your balance for one second.",
              start: 4.1, end: 5.1, rate: 0.5,
              checks: ["My swinging foot stayed low and quick", "I landed past where the ball would be", "My weight ended on the planted foot"]),
        .init(id: "still", title: "Step across a still ball", level: "Ball · walking pace", reps: 10,
              how: "Walk in side-on with the ball just ahead of your front foot. Step across without touching it and plant past it.",
              start: 3.1, end: 5.1, rate: 0.5,
              checks: ["I didn\u{2019}t touch the ball", "The ball ended behind my planted foot", "I could hold the plant for a second"]),
        .init(id: "exit", title: "Add the turn and exit", level: "Ball · half pace", reps: 8,
              how: "From the plant, load the planted foot, let the other leg swing, turn back to the ball and push it away with your other foot. Accelerate for five metres.",
              start: 6.2, end: 7.8, rate: 0.5,
              checks: ["I turned on my planted foot", "My other foot took the ball away", "I sped up after the touch"]),
        .init(id: "flow", title: "The whole move, no pause", level: "Ball · building speed", reps: 8,
              how: "Join the two steps. The tutorial stops between them; you shouldn\u{2019}t. The model skips its pause.",
              start: 3.6, end: 8.05, rate: 0.5, skipsPause: true,
              checks: ["No stop between the plant and the turn", "I stayed low through the change of direction", "I could do it at jogging speed"]),
        .init(id: "live", title: "Beat a cone at speed", level: "Cone or passive defender · full speed", reps: 6,
              how: "Dribble at a cone two metres away. Sell it, step across, then take it the other way and burst past.",
              start: 0, end: 3.0, rate: 1,
              checks: ["I got lower than in the walking drills", "I changed speed after the turn", "The ball stayed close until the burst"]),
    ]

    /// When the tutorial's pause runs; the no-pause drill skips it.
    static let pause = 5.1...6.2
}
