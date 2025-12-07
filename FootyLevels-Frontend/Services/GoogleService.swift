//
//  SignInService.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-07.
//

import Foundation
import FirebaseAuth
import GoogleSignIn
import UIKit // Needed for UIViewController type

class GoogleService: ObservableObject {
    
    // Update the function signature to accept the required presenting UIViewController
    @MainActor
    func signInWithGoogle() async throws {
        
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
        
        // 4. Create Firebase Credential
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: signInResult.user.accessToken.tokenString
        )
        
        // 5. Sign in to Firebase
        let authResult = try await Auth.auth().signIn(with: credential)
        
        print("Firebase Sign-In Success: User \(authResult.user.uid)")
    }
    
}
