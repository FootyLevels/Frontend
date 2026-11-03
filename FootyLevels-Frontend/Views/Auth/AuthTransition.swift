/// Which way the account changed. The splash says goodbye only on the way out.
enum AuthDirection: Equatable {
    case signingIn, signingOut
}

/// How the root view moves between the signed-out and signed-in screens.
enum AuthTransition: Equatable {
    /// Swap screens behind the logo splash.
    case splash(AuthDirection)
    /// Cross-fade straight to the new screen.
    case fade

    /// Signing in or out plays the splash. Opening the app (leaving `.loading`),
    /// a state that hasn't changed, and Reduce Motion all get a plain cross-fade.
    static func between(_ old: IsLoggedIn, _ new: IsLoggedIn, reduceMotion: Bool) -> AuthTransition {
        guard !reduceMotion else { return .fade }
        switch (old, new) {
        case (.notLoggedIn, .loggedIn): return .splash(.signingIn)
        case (.loggedIn, .notLoggedIn): return .splash(.signingOut)
        default: return .fade
        }
    }
}
