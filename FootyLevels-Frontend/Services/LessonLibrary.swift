import Foundation

/// The lessons that ship inside the app: every `Lesson-*.bundle` the lesson pipeline
/// added to `SampleData/Lessons`. Adding a lesson needs no code change.
/// Lessons made from the user's own videos use the same entries (`UserLessonStore`).
enum LessonLibrary {
    struct Entry: Identifiable, Hashable {
        let id: String
        let title: String
        let subtitle: String
        let skills: [String]
        /// The first skill's opening drills, for a "practise next" preview.
        var practice: [Drill] = []
        let url: URL
    }

    struct Drill: Hashable {
        let title: String
        let level: String
        let reps: Int
    }

    private struct Summary: Decodable {
        struct Skill: Decodable {
            let short: String
            let drills: [SummaryDrill]?
        }
        struct SummaryDrill: Decodable {
            let title: String
            let lvl: String
            let reps: Int
        }
        let id: String
        let title: String
        let subtitle: String
        let skills: [Skill]
    }

    /// Lesson bundles found in `bundle`, sorted by title. Unreadable ones are left out;
    /// `LessonPackage.load` reports what is wrong with them.
    static func lessons(in bundle: Bundle = .main) -> [Entry] {
        guard let root = bundle.resourceURL,
              let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return [] }
        return names
            .filter { $0.hasPrefix("Lesson-") && $0.hasSuffix(".bundle") }
            .compactMap { entry(at: root.appendingPathComponent($0, isDirectory: true)) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The entry for one lesson bundle folder, or nil when its lesson.json can't be read.
    static func entry(at url: URL) -> Entry? {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("lesson.json")),
              let summary = try? JSONDecoder().decode(Summary.self, from: data) else { return nil }
        let drills = (summary.skills.first?.drills ?? []).prefix(2)
            .map { Drill(title: $0.title, level: $0.lvl, reps: $0.reps) }
        return Entry(id: summary.id, title: summary.title, subtitle: summary.subtitle,
                     skills: summary.skills.map(\.short), practice: drills, url: url)
    }
}
