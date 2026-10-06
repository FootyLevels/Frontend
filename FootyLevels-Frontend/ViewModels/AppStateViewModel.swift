//
//  AppStateViewModel.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-07.
//

import Foundation
import SwiftUI
import FirebaseAuth

enum IsLoggedIn{
    case loading
    case loggedIn
    case notLoggedIn
}

@Observable
final class AppStateViewModel {
    var currentUser: UserInfo? = nil
    var isLoggedIn: IsLoggedIn = .loading

    @ObservationIgnored
    private var authListener: AuthStateDidChangeListenerHandle?

    init() {
        observeAuthState()
    }

    deinit {
        if let authListener {
            Auth.auth().removeStateDidChangeListener(authListener)
        }
    }

    /// Tracks the signed-in user for the lifetime of the app.
    ///
    /// Firebase already persists the session to the Keychain, so a signed-in
    /// account survives app restarts — but it restores that session
    /// **asynchronously** after `FirebaseApp.configure()`. Reading
    /// `Auth.auth().currentUser` synchronously at launch (what this used to do)
    /// therefore often returned nil for an account that was still signed in,
    /// which is why the login screen kept reappearing.
    ///
    /// The listener fires once restoration completes, and again on every
    /// sign-in, sign-out, and token refresh — so an expired or revoked token
    /// now also propagates instead of going unnoticed until the next launch.
    private func observeAuthState() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }

            if let user {
                self.currentUser = UserInfo(user: user)
                self.isLoggedIn = .loggedIn
            } else {
                self.currentUser = nil
                self.isLoggedIn = .notLoggedIn
            }
        }
    }

    func signOut() throws {
        try AuthManager.shared.signOut()
        // The listener fires for this too; setting state here just makes the
        // transition immediate rather than waiting a frame.
        self.currentUser = nil
        self.isLoggedIn = .notLoggedIn
    }
}
