//
//  SignUpViewModel.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-07.
//

import SwiftUI
import FirebaseAuth

@MainActor
@Observable
final class UserSigninViewModel{
    var name: String = ""
    var password: String = ""
    var confirm: String = ""
    var email: String = ""
    var isLoading = false
    var errorMessage: String?
    
    func signUpWithEmail() async -> UserInfo?{
        guard !isLoading else { return nil }
        errorMessage = nil
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !password.isEmpty else {
            errorMessage = "Enter your name, email and password."
            return nil
        }
        isLoading = true
        defer { isLoading = false }
        
        do {
            let user = try await AuthManager.shared.createUserAccount(withEmail: email, password: password, name: name)
            return user
        } catch {
            switch AuthErrorCode(rawValue: (error as NSError).code) {
            case .invalidEmail: errorMessage = "Email format is incorrect."
            case .weakPassword: errorMessage = "Please choose a stronger password."
            case .emailAlreadyInUse: errorMessage = "Unable to create this account. Try signing in instead."
            case .networkError: errorMessage = "Couldn't connect. Please try again."
            case .tooManyRequests: errorMessage = "Please wait a moment and try again."
            default: errorMessage = "Couldn't create your account. Please try again."
            }
        }
        return nil
    }
}
