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
@MainActor
final class AppStateViewModel {
    var currentUser: UserInfo? = nil
    var isLoggedIn: IsLoggedIn = .loading
    var cloudProfile: CloudProfile?
    var accountError: String?
    @ObservationIgnored private var accountTask: Task<Void, Never>?

    @ObservationIgnored
    private var authListener: AuthStateDidChangeListenerHandle?

    init() {
        observeAuthState()
    }

    deinit {
        accountTask?.cancel()
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
    /// This listener tracks account changes. Protected API requests separately
    /// refresh tokens and handle server-side revocation/disabled-account checks.
    private func observeAuthState() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }

                self.accountTask?.cancel()
                self.cloudProfile = nil
                self.accountError = nil

                if let user = Auth.auth().currentUser {
                    self.currentUser = UserInfo(user: user)
                    self.isLoggedIn = .loggedIn
                    self.accountTask = Task { await self.connectAccount() }
                } else {
                    self.currentUser = nil
                    self.isLoggedIn = .notLoggedIn
                }
            }
        }
    }

    func connectAccount() async {
        guard let base = ApplicationEnvironment.apiBaseURL else { return }
        let identity = FirebaseAPICredentials.shared.currentSession
        do {
            let client = try AuthenticatedAPIClient(baseURL: base, credentials: FirebaseAPICredentials.shared)
            let profile = try await client.bootstrap()
            guard !Task.isCancelled, identity == FirebaseAPICredentials.shared.currentSession,
                  profile.id == identity?.uid else { return }
            cloudProfile = profile
            accountError = nil
        } catch {
            guard !Task.isCancelled, identity == FirebaseAPICredentials.shared.currentSession else { return }
            cloudProfile = nil
            accountError = error.localizedDescription
        }
    }

    func signOut() throws {
        try AuthManager.shared.signOut()
        accountTask?.cancel()
        cloudProfile = nil
        accountError = nil
        // The listener fires for this too; setting state here just makes the
        // transition immediate rather than waiting a frame.
        self.currentUser = nil
        self.isLoggedIn = .notLoggedIn
    }
}
