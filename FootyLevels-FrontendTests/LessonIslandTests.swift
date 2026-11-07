import CoreGraphics
import Testing
@testable import FootyLevels_Frontend

/// The island over the video while the lesson sheet is slid away: which point it shows, and
/// where it sits when it's dragged.
struct LessonIslandTests {

    private func chop() throws -> LessonDocument.Skill {
        let entry = try #require(LessonLibrary.lessons().first { $0.id == "chop-and-spin" })
        return try #require(try LessonPackage.load(entry.url).document.skills.first { $0.id == "chop" })
    }

    @Test func watchingShowsTheLatestMomentJustBeforeItHappens() throws {
        let skill = try chop()
        let early = try #require(skill.point(for: .watch, at: 4.43, phase: nil, selected: nil))
        #expect(early.id == "notice-0", "before the first moment, it shows the first")
        #expect(early.count == 4)
        let second = try #require(skill.point(for: .watch, at: 4.86, phase: nil, selected: nil))
        #expect(second.id == "notice-1", "5.0 s shows from 4.85 s")
        #expect(second.index == 1)
        #expect(second.title == skill.notice[1].title)
        #expect(skill.point(for: .watch, at: 9, phase: nil, selected: nil)?.id == "notice-3")
    }

    @Test func breakingItDownShowsThePhaseThatIsPlaying() throws {
        let skill = try chop()
        let point = try #require(skill.point(for: .breakdown, at: 0, phase: skill.phases[2], selected: nil))
        #expect(point.title == "Turn away")
        #expect(point.text == skill.phases[2].cue)
        #expect(point.index == 2 && point.count == 4)
        #expect(skill.point(for: .breakdown, at: 0, phase: nil, selected: nil)?.title == "Run at him")
    }

    @Test func practiseShowsTheChosenDrillAndWhatToWatchFor() throws {
        let skill = try chop()
        let first = try #require(skill.point(for: .practise, at: 0, phase: nil, selected: nil))
        #expect(first.title == "Chop on the spot")
        #expect(first.text == "Watch for: the ball went behind my standing leg.")
        let chosen = try #require(skill.point(for: .practise, at: 0, phase: nil, selected: skill.drills[2].id))
        #expect(chosen.title == "At pace along a line")
        #expect(chosen.text == "Watch for: I didn’t slow right down before the chop.", "\"I\" keeps its capital")
        #expect(chosen.index == 2)
    }

    @Test func testShowsTheChosenQuestion() throws {
        let skill = try chop()
        let point = try #require(skill.point(for: .test, at: 0, phase: nil, selected: "challenge-1"))
        #expect(point.title == "Where does the ball go?")
        #expect(point.index == 1 && point.count == 3)
        #expect(skill.point(for: .test, at: 0, phase: nil, selected: "gone")?.index == 0)
    }

    // MARK: Where it sits

    private let area = CGSize(width: 358, height: 700)
    private let island = CGSize(width: 190, height: 40)

    @Test func itStartsBottomLeftAboveThePill() {
        let home = LessonIslandSpot.home(abovePill: 48)
        #expect(home.frame(for: island, in: area) == CGRect(x: 0, y: 700 - 66 - 40, width: 190, height: 40))
    }

    @Test func aDropPinsItToTheNearestCorner() {
        let topRight = LessonIslandSpot.dropped(at: CGRect(x: 150, y: 30, width: 190, height: 40), in: area)
        #expect(topRight == LessonIslandSpot(trailing: true, bottom: false, dx: 18, dy: 30))
        #expect(topRight.alignment == .topTrailing)
        #expect(topRight.frame(for: island, in: area).origin == CGPoint(x: 150, y: 30), "it stays where it was dropped")

        let bottomLeft = LessonIslandSpot.dropped(at: CGRect(x: 10, y: 500, width: 190, height: 40), in: area)
        #expect(bottomLeft == LessonIslandSpot(trailing: false, bottom: true, dx: 10, dy: 160))
    }

    @Test func itOpensAwayFromThePinnedCorner() {
        let topRight = LessonIslandSpot(trailing: true, bottom: false, dx: 18, dy: 30)
        let open = topRight.frame(for: CGSize(width: 252, height: 110), in: area)
        #expect(open.maxX == 340 && open.minY == 30, "the right and top edges stay put")
    }

    @Test func aDropPastTheEdgeStaysOnScreen() {
        let spot = LessonIslandSpot.dropped(at: CGRect(x: -80, y: 680, width: 190, height: 40), in: area)
        #expect(spot.frame(for: island, in: area) == CGRect(x: 0, y: 660, width: 190, height: 40))
        let opened = spot.frame(for: CGSize(width: 400, height: 900), in: area)
        #expect(opened.minX == 0 && opened.maxY == 700, "an island bigger than the area still starts at its corner")
    }

    @Test func aDropNearHomeCountsAsPuttingItBack() {
        let home = LessonIslandSpot.home(abovePill: 48)
        #expect(LessonIslandSpot(dx: 10, dy: 80).isNear(home))
        #expect(!LessonIslandSpot(dx: 30, dy: 66).isNear(home), "more than 24 points away")
        #expect(!LessonIslandSpot(trailing: true, dx: 0, dy: 66).isNear(home), "another corner")
    }

    @Test func theSpotIsSavedAndRead() throws {
        let spot = LessonIslandSpot(trailing: true, bottom: false, dx: 18.5, dy: 30)
        #expect(LessonIslandSpot(rawValue: spot.rawValue) == spot)
        #expect(LessonIslandSpot(rawValue: "") == nil)
        #expect(LessonIslandSpot(rawValue: "1,0,nan,3") == nil)
        #expect(LessonIslandSpot(rawValue: "1,0,4") == nil)
    }
}
