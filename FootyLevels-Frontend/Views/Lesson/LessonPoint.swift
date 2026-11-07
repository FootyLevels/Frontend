import Foundation

/// The one thing to look at right now, shown in the island over the video while the lesson
/// sheet is slid away.
struct LessonPoint: Equatable {
    /// The sheet row it comes from.
    let id: String
    let title: String
    let text: String
    /// Its place among the stage's points, from 0.
    let index: Int
    let count: Int
}

extension LessonDocument.Skill {
    /// The point for this moment of a stage: the latest moment to notice while watching, the
    /// phase being played while breaking it down, or the chosen drill or question.
    /// `selected` is the sheet's chosen row for Practise and Test.
    func point(for stage: LessonStage, at time: Double, phase: LessonDocument.Phase?, selected: String?) -> LessonPoint? {
        switch stage {
        case .watch:
            guard !notice.isEmpty else { return nil }
            // A moment early, so the point is up as the thing happens.
            let index = notice.lastIndex { $0.t - 0.15 <= time } ?? 0
            let moment = notice[index]
            return LessonPoint(id: "notice-\(index)", title: moment.title, text: moment.text, index: index, count: notice.count)
        case .breakdown:
            guard let current = phase ?? phases.first, let index = phases.firstIndex(of: current) else { return nil }
            return LessonPoint(id: current.id, title: current.name, text: current.cue, index: index, count: phases.count)
        case .practise:
            guard !drills.isEmpty else { return nil }
            let index = drills.firstIndex { $0.id == selected } ?? 0
            let drill = drills[index]
            let text = drill.checks.first.map { "Watch for: \(Self.sentenceTail($0))" } ?? drill.how
            return LessonPoint(id: drill.id, title: drill.title, text: text, index: index, count: drills.count)
        case .test:
            let items = sheetItems(for: .test)
            guard !items.isEmpty else { return nil }
            let index = items.firstIndex { $0.id == selected } ?? 0
            return LessonPoint(id: items[index].id, title: items[index].title, text: items[index].detail, index: index, count: items.count)
        }
    }

    /// A check ("The ball went behind my standing leg") as the end of a sentence: lower case
    /// first, except "I", with a full stop.
    private static func sentenceTail(_ check: String) -> String {
        let first = check.prefix { $0.isLetter }
        let lowered = first == "I" ? check : check.prefix(1).lowercased() + check.dropFirst()
        return lowered.last.map { ".!?".contains($0) } == true ? lowered : lowered + "."
    }
}
