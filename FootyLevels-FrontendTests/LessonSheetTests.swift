import CoreGraphics
import Testing
@testable import FootyLevels_Frontend

/// The lesson sheet over the player: its heights, how a drag settles, and the steps it
/// lists for each stage.
struct LessonSheetTests {

    /// An iPhone 17: 844 points tall, the home indicator 34, the bars above 108.
    private let layout = LessonSheetLayout(screenHeight: 844, headerHeight: 230, bottomInset: 34, topReserve: 120)

    @Test func theHeightsRiseFromTheHeaderToNearlyTheWholeScreen() {
        #expect(layout.height(.peek) == 264)
        #expect(layout.height(.half) == 844 * 0.56)
        #expect(layout.height(.full) == 724)
    }

    @Test func theSmallestHeightFitsALargerHeaderButNeverPassesTheTop() {
        var big = layout
        big.headerHeight = 400
        #expect(big.height(.peek) == 434)
        #expect(big.height(.half) == 634)
        big.headerHeight = 900
        #expect(big.height(.peek) == big.height(.full))
    }

    @Test func aDragSettlesOnTheHeightItIsHeadingFor() {
        #expect(layout.settle(at: 300, velocity: 0) == .peek)
        #expect(layout.settle(at: 300, velocity: 1200) == .half)
        #expect(layout.settle(at: 690, velocity: 0) == .full)
        #expect(layout.settle(at: 700, velocity: -1000) == .half)
    }

    @Test func theHandleStepsUpThenBackToTheSmallestHeight() {
        #expect(LessonSheetDetent.peek.next == .half)
        #expect(LessonSheetDetent.half.next == .full)
        #expect(LessonSheetDetent.full.next == .peek)
        #expect(LessonSheetDetent.hidden.next == .peek, "the handle never hides the sheet")
    }

    @Test func aSwipeDownFromTheSmallestHeightSlidesTheSheetAway() {
        #expect(layout.height(.hidden) == 0)
        #expect(layout.settle(at: 100, velocity: 0) == .hidden)
        #expect(layout.settle(at: 240, velocity: -800) == .hidden, "a quick flick down hides it")
        #expect(layout.settle(at: 240, velocity: 0) == .peek, "a small nudge springs back")
    }

    @Test func belowTheSmallestHeightTheSheetSlidesInsteadOfSquashing() {
        #expect(layout.slide(toShow: layout.height(.peek)) == 0)
        #expect(layout.slide(toShow: 100) == 164)
        #expect(layout.slide(toShow: 0) == 264)
        #expect(layout.slide(toShow: layout.height(.full)) == 0)
    }

    @Test func eachStageListsItsStepsInLessonOrder() throws {
        let entry = try #require(LessonLibrary.lessons().first { $0.id == "chop-and-spin" })
        let chop = try #require(try LessonPackage.load(entry.url).document.skills.first { $0.id == "chop" })

        #expect(chop.sheetItems(for: .breakdown).map(\.title) == ["Run at him", "Plant and chop", "Turn away", "Accelerate"])
        #expect(chop.sheetItems(for: .breakdown).map(\.tag) == ["4.43", "4.95", "5.30", "5.85"])
        #expect(chop.sheetItems(for: .watch).map(\.tag) == ["4.7 s", "5.0 s", "5.4 s", "6.1 s"])
        #expect(chop.sheetItems(for: .watch).map(\.time) == [4.7, 5.0, 5.4, 6.1])
        let drill = try #require(chop.sheetItems(for: .practise).first)
        #expect(drill.title == "Chop on the spot")
        #expect(drill.tag == "10 reps")
        #expect(drill.detail == "Ball · standing still")
        #expect(drill.time == nil)
        #expect(chop.sheetItems(for: .test).map(\.tag) == ["Q1", "Q2", "Q3"])
        #expect(chop.sheetItems(for: .test).last?.detail == "Tap the moments in the order they happen.")
    }
}
