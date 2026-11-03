import Testing
@testable import FootyLevels_Frontend

/// Signing in or out plays the logo splash; opening the app and Reduce Motion cross-fade.
struct AuthTransitionTests {

    @Test func signingInPlaysTheSplash() {
        #expect(AuthTransition.between(.notLoggedIn, .loggedIn, reduceMotion: false) == .splash(.signingIn))
    }

    @Test func signingOutPlaysTheGoodbyeSplash() {
        #expect(AuthTransition.between(.loggedIn, .notLoggedIn, reduceMotion: false) == .splash(.signingOut))
    }

    @Test func openingTheAppCrossFades() {
        #expect(AuthTransition.between(.loading, .loggedIn, reduceMotion: false) == .fade)
        #expect(AuthTransition.between(.loading, .notLoggedIn, reduceMotion: false) == .fade)
    }

    @Test func reduceMotionCrossFades() {
        #expect(AuthTransition.between(.notLoggedIn, .loggedIn, reduceMotion: true) == .fade)
        #expect(AuthTransition.between(.loggedIn, .notLoggedIn, reduceMotion: true) == .fade)
    }

    /// A sign-in that is undone before the splash swaps screens just fades the splash away.
    @Test func unchangedStateCrossFades() {
        #expect(AuthTransition.between(.notLoggedIn, .notLoggedIn, reduceMotion: false) == .fade)
        #expect(AuthTransition.between(.loggedIn, .loggedIn, reduceMotion: false) == .fade)
    }
}
