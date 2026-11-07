import Foundation
import Testing
@testable import FootyLevels_Frontend

/// The profile card: the name it shows, the photo it asks Google for, and the counts it
/// makes from the drill progress saved on the phone.
@MainActor
struct ProfileTests {

    private let lessons = [
        ProfileStats.Lesson(title: "Chop and Spin", sets: [
            .init(key: "a.chop", drills: [.init(id: "spot", reps: 10, checks: 2), .init(id: "walk", reps: 10, checks: 1)]),
            .init(key: "a.spin", drills: [.init(id: "spot", reps: 8, checks: 0)]),
        ]),
        ProfileStats.Lesson(title: "Hocus Pocus", sets: [
            .init(key: "b.flick", drills: [.init(id: "roll", reps: 10, checks: 1)]),
        ]),
        ProfileStats.Lesson(title: "Skill Ladder", sets: [.init(key: "c.one", drills: [.init(id: "x", reps: 5, checks: 0)])]),
    ]

    @Test func nothingLoggedCountsNothing() {
        let stats = ProfileStats.compute(lessons) { _ in [:] }
        #expect(stats == ProfileStats())
        #expect(stats.mostPractised == nil)
    }

    @Test func countsRepsFinishedDrillsAndStartedLessons() {
        let saved: [String: [String: DrillProgress]] = [
            // Finished: every rep and both checks.
            "a.chop": ["spot": DrillProgress(reps: 10, checks: [true, true]), "walk": DrillProgress(reps: 4, checks: [true])],
            // Same drill id in another skill is a different drill; no checks to tick, so 8 reps finish it.
            "a.spin": ["spot": DrillProgress(reps: 8, checks: [])],
            // Started with a tick but no reps.
            "b.flick": ["roll": DrillProgress(reps: 0, checks: [true])],
        ]
        let stats = ProfileStats.compute(lessons) { saved[$0] ?? [:] }
        #expect(stats.repsLogged == 22)
        #expect(stats.drillsDone == 2)
        #expect(stats.lessonsStarted == 2)
        #expect(stats.mostPractised == "Chop and Spin")
    }

    @Test func theLessonWithTheMostRepsIsTheMostPractised() {
        let saved: [String: [String: DrillProgress]] = [
            "a.chop": ["spot": DrillProgress(reps: 3, checks: [])],
            "c.one": ["x": DrillProgress(reps: 7, checks: [])],
        ]
        #expect(ProfileStats.compute(lessons) { saved[$0] ?? [:] }.mostPractised == "Skill Ladder")
    }

    /// Reads the real keys the lesson screens save under, for the lessons shipped in the app.
    @Test func readsTheProgressTheLessonsSave() throws {
        let defaults = try #require(UserDefaults(suiteName: "ProfileTests-\(UUID().uuidString)"))
        DrillProgressStore(defaults: defaults, key: "lesson.chop-and-spin.chop.drills").update("static") { $0.reps = 6 }
        DrillProgressStore(defaults: defaults, key: "lesson.chop-and-spin.spin.drills").update("walk") { $0.reps = 3 }
        DrillProgressStore(defaults: defaults, key: "lesson.overfake.drills").update("footwork") { $0.reps = 7 }
        // A drill the lesson doesn't have isn't counted.
        DrillProgressStore(defaults: defaults, key: "lesson.chop-and-spin.chop.drills").update("gone") { $0.reps = 50 }
        let stats = ProfileStats.onThisPhone(defaults: defaults)
        #expect(stats.repsLogged == 16)
        #expect(stats.lessonsStarted == 2)
        #expect(stats.drillsDone == 0)
        #expect(stats.mostPractised == "Chop and Spin")
    }

    @Test func theNameFallsBackToTheEmail() {
        #expect(UserInfo(uid: "1", email: "a@b.com", displayName: "Digaant Singh Dogra").shownName == "Digaant Singh Dogra")
        #expect(UserInfo(uid: "1", email: "a@b.com", displayName: "  ").shownName == "a@b.com")
        #expect(UserInfo(uid: "1", email: nil, displayName: nil).shownName == "Your account")
    }

    @Test func googlePhotosAreAskedForAtTheSizeShown() throws {
        let google = try #require(URL(string: "https://lh3.googleusercontent.com/a/ACg8ocK=s96-c"))
        #expect(ProfilePhoto.sized(google, pixels: 300).absoluteString == "https://lh3.googleusercontent.com/a/ACg8ocK=s300-c")
        let other = try #require(URL(string: "https://example.com/me.jpg"))
        #expect(ProfilePhoto.sized(other, pixels: 300) == other)
    }
}
