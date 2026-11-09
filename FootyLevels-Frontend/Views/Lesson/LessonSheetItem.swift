import Foundation

/// One row in the lesson sheet: a moment to notice, a phase, a drill or a challenge.
struct LessonSheetItem: Identifiable, Equatable {
    let id: String
    /// The left column: a time, a rep count or the question number.
    let tag: String
    let title: String
    let detail: String
    /// Where the row sits in the clip, for moments and phases.
    var time: Double?
}

extension LessonDocument.Skill {
    /// The rows the lesson sheet lists for a stage, in lesson order.
    func sheetItems(for stage: LessonStage) -> [LessonSheetItem] {
        switch stage {
        case .watch:
            return notice.enumerated().map { index, moment in
                LessonSheetItem(id: "notice-\(index)", tag: String(format: "%.1f s", moment.t), title: moment.title, detail: moment.text, time: moment.t)
            }
        case .breakdown:
            return phases.map { LessonSheetItem(id: $0.id, tag: String(format: "%.2f", $0.start), title: $0.name, detail: $0.cue, time: $0.start) }
        case .practise:
            return drills.map { LessonSheetItem(id: $0.id, tag: "\($0.reps) reps", title: $0.title, detail: $0.lvl) }
        case .test:
            return challenges.enumerated().map { index, challenge in
                LessonSheetItem(id: "challenge-\(index)", tag: "Q\(index + 1)", title: challenge.title, detail: challenge.prompt)
            }
        }
    }
}
