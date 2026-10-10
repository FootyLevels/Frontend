//
//  EmailLoginViewModel.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-07.
//

import SwiftUI
import FirebaseAuth

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
            self.errorMessage = Self.message(for: error)
        }

        return nil
    }

    /// Maps a Firebase error to something worth showing a person.
    ///
    /// Switches on `AuthErrorCode` rather than comparing
    /// `localizedDescription` to English strings: those change between SDK
    /// releases and are translated on a non-English device, so matching them
    /// silently stops working. The `default` also guarantees a message —
    /// previously an unrecognised error left this nil and the UI showed
    /// nothing at all.
    private static func message(for error: Error) -> String {
        guard let code = AuthErrorCode(rawValue: (error as NSError).code) else {
            return error.localizedDescription
        }

        switch code {
        case .invalidEmail:
            return "Email format is incorrect."
        case .wrongPassword, .invalidCredential, .userNotFound:
            return "Wrong email or password."
        case .userDisabled:
            return "That account has been disabled."
        case .tooManyRequests:
            return "Too many attempts. Try again in a moment."
        case .networkError:
            return "Network error. Check your connection and try again."
        default:
            return error.localizedDescription
        }
    }
    
    func signInWithGoogle() async throws -> UserInfo?{
        let token = try await GoogleService().signInWithGoogle()
        let userInfo = try await AuthManager.shared.signInWithGoogle(token: token)
        
        return userInfo
    }
    
}
