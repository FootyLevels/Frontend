//
//  EmailLoginViewModel.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-07.
//

import SwiftUI
@MainActor
@Observable
final class UserLoginViewModel{
    var email: String = ""
    var password:String = ""
    var errorMessage: String? = nil
    var isLoading: Bool = false
    
    func loginWithEmail() async -> UserInfo?{
        // Reset error at start of attempt
        self.errorMessage = nil
        self.isLoading = true
        defer { self.isLoading = false } // Turn off loading when function finishes
        
        // Basic Validation
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !password.isEmpty else {
            self.errorMessage = "Please fill in all fields."
            return nil
        }
        
        do {
            let user = try await AuthManager.shared.loginWithEmail(email: email, password: password)
            return user
        } catch {
            // 2. Capture the actual error message from Firebase
            print("Login error: \(error.localizedDescription)")
            if error.localizedDescription == "The email address is badly formatted." {
                self.errorMessage = "Email format is incorrect."
            }else if error.localizedDescription == "The supplied auth credential is malformed or has expired." {
                self.errorMessage = "Wrong Password"
            }
        }
        
        return nil
    }
    
    func signInWithGoogle() async throws -> UserInfo?{
        let token = try await GoogleService().signInWithGoogle()
        let userInfo = try await AuthManager.shared.signInWithGoogle(token: token)
        
        return userInfo
    }
    
}
