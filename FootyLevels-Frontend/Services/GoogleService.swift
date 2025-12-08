//
//  SignInService.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-07.
//

import Foundation
import FirebaseAuth
import GoogleSignIn
import GoogleSignInSwift
import UIKit // Needed for UIViewController type

struct GoogleResultTokens{
    let accessToken: String
    let idToken: String
}

final class GoogleService: ObservableObject {
    
    // Update the function signature to accept the required presenting UIViewController
    @MainActor
    func signInWithGoogle() async throws -> GoogleResultTokens {
        
        // 1. The presentingViewController is passed in from the GoogleSignInButton closure.
        guard let presentingViewController = Utils.shared.getTopViewController() else{
            throw URLError(.cannotFindHost)
        }
        
        // 2. Start Google Sign-In
        let signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
        
        // 3. Get Google Credentials (ID Token)
        guard let idToken = signInResult.user.idToken?.tokenString else {
            throw NSError(domain: "AuthError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No ID Token found from Google."])
        }
        
        let accessToken = signInResult.user.accessToken.tokenString
        return GoogleResultTokens(accessToken: accessToken, idToken: idToken)
    }
    
}
