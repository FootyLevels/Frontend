import Foundation

/// What the profile card counts: reps logged, drills finished and lessons started, from the
/// drill progress kept on this phone, plus the lesson with the most reps.
struct ProfileStats: Equatable {
    var repsLogged = 0
    var drillsDone = 0
    var lessonsStarted = 0
    /// The lesson with the most reps logged; nil until a rep is logged.
    var mostPractised: String?

    /// A lesson's drills, grouped by the key their progress is saved under.
    struct Lesson {
        let title: String
        let sets: [DrillSet]
    }

    struct DrillSet {
        let key: String
        let drills: [Target]
    }

    /// What finishing a drill takes.
    struct Target {
        let id: String
        let reps: Int
        let checks: Int
    }

    static func compute(_ lessons: [Lesson], progress: (String) -> [String: DrillProgress]) -> ProfileStats {
        var stats = ProfileStats()
        var most = 0
        for lesson in lessons {
            var reps = 0
            var started = false
            for set in lesson.sets {
                let saved = progress(set.key)
                for target in set.drills {
                    guard let drill = saved[target.id] else { continue }
                    reps += drill.reps
                    if drill.reps > 0 || drill.checks.contains(true) { started = true }
                    if drill.isComplete(targetReps: target.reps, checkCount: target.checks) { stats.drillsDone += 1 }
                }
            }
            stats.repsLogged += reps
            if started { stats.lessonsStarted += 1 }
            if reps > most {
                most = reps
                stats.mostPractised = lesson.title
            }
        }
        return stats
    }

    /// Counts every lesson in the app: the Over Fake and each bundled lesson's skills.
    @MainActor
    static func onThisPhone(defaults: UserDefaults = .standard, bundle: Bundle = .main) -> ProfileStats {
        var lessons = [Lesson(title: "The over fake", sets: [
            DrillSet(key: "lesson.overfake.drills",
                     drills: OverFakeLessonContent.drills.map { Target(id: $0.id, reps: $0.reps, checks: $0.checks.count) }),
        ])]
        for entry in LessonLibrary.lessons(in: bundle) {
            guard let data = try? Data(contentsOf: entry.url.appendingPathComponent("lesson.json")),
                  let document = try? JSONDecoder().decode(LessonDocument.self, from: data) else { continue }
            lessons.append(Lesson(title: entry.title.replacingOccurrences(of: " Lesson", with: ""), sets: document.skills.map { skill in
                DrillSet(key: "lesson.\(document.id).\(skill.id).drills",
                         drills: skill.drills.map { Target(id: $0.id, reps: $0.reps, checks: $0.checks.count) })
            }))
        }
        return compute(lessons) { DrillProgressStore(defaults: defaults, key: $0).all }
    }
}
