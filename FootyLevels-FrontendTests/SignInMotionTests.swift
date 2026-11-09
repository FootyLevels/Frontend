import Foundation
import Testing
@testable import FootyLevels_Frontend

/// The sign-in screen's motion: the logo's level meter, the shine across "Levels", and the
/// tilt that shifts the layers.
@MainActor
struct SignInMotionTests {

    @Test func theLevelMeterBarsStayInTheirRanges() {
        for step in 0..<600 {
            let t = Double(step) * 0.01
            #expect((0.5...1).contains(BrandMark.levelScale(bar: 0, at: t)))
            #expect((0.7...1).contains(BrandMark.levelScale(bar: 1, at: t)))
            #expect((1...1.45).contains(BrandMark.levelScale(bar: 2, at: t)))
        }
        #expect(BrandMark.levelScale(bar: 0, at: 0) == 1)
        #expect(abs(BrandMark.levelScale(bar: 0, at: 0.85) - 0.5) < 0.001, "the first bar dips to half halfway through its 1.7 s beat")
        #expect(abs(BrandMark.levelScale(bar: 2, at: 0.65) - 1.45) < 0.001)
    }

    @Test func theShineCrossesLevelsOnceEverySixSeconds() throws {
        #expect(SignInTitle.shinePosition(at: 0) == -0.2)
        #expect(abs(try #require(SignInTitle.shinePosition(at: 0.9)) - 0.5) < 0.001)
        #expect(SignInTitle.shinePosition(at: 1.8) == nil)
        #expect(SignInTitle.shinePosition(at: 4) == nil)
        #expect(SignInTitle.shinePosition(at: 6) == -0.2)
    }

    @Test func tiltIsMeasuredFromHowThePhoneWasHeld() {
        let level = (roll: 0.2, pitch: 0.9)
        #expect(TiltReader.tilt(roll: 0.2, pitch: 0.9, level: level) == (0, 0))
        let half = TiltReader.tilt(roll: 0.2 + TiltReader.fullTilt / 2, pitch: 0.9 - TiltReader.fullTilt / 2, level: level)
        #expect(abs(half.x - 0.5) < 0.0001 && abs(half.y + 0.5) < 0.0001)
    }

    @Test func tiltStopsAtTheEdges() {
        let far = TiltReader.tilt(roll: 2, pitch: -2, level: (0, 0))
        #expect(far == (1, -1))
    }
}
