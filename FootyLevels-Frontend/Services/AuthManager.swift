//
//  AuthManager.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-07.
//

import Foundation
import FirebaseAuth
import GoogleSignIn

@MainActor
class AuthManager{
    static let shared = AuthManager()
    
    private init(){}
    
    func getLoggedInUser() -> UserInfo? {
        guard let user = Auth.auth().currentUser else{
            return nil
        }
        return UserInfo(user: user)
    }
    
    func createUserAccount(withEmail email:String, password:String, name:String) async throws -> UserInfo{
        let authResult = try await Auth.auth().createUser(withEmail: email, password: password)
        let changeRequest = authResult.user.createProfileChangeRequest()
        changeRequest.displayName = name
        try await changeRequest.commitChanges()
        FirebaseAPICredentials.shared.reset()
        return UserInfo(user: authResult.user)
    }
    
    func loginWithEmail(email:String, password:String) async throws -> UserInfo {
        let authResult = try await Auth.auth().signIn(withEmail: email, password: password)
        FirebaseAPICredentials.shared.reset()
        return UserInfo(user: authResult.user)
    }
    
    func signInWithGoogle(token: GoogleResultTokens) async throws -> UserInfo{
        let credentials = GoogleAuthProvider.credential(withIDToken: token.idToken, accessToken: token.accessToken)
        let authResult = try await Auth.auth().signIn(with: credentials)
        FirebaseAPICredentials.shared.reset()
        
        return UserInfo(user: authResult.user)
    }
    
    @MainActor
    func signOut() throws{
        try Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
        FirebaseAPICredentials.shared.reset()
    }
    
}
