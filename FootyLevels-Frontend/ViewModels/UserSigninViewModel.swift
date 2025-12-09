//
//  SignUpViewModel.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-07.
//

import SwiftUI

@MainActor
@Observable
final class UserSigninViewModel{
    var name: String = ""
    var password: String = ""
    var confirm: String = ""
    var email: String = ""
    
    func signUpWithEmail() async -> UserInfo?{
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else{
            return nil
        }
        
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else{
            return nil
        }
        
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else{
            return nil
        }
        
        do {
            let user = try await AuthManager.shared.createUserAccount(withEmail: email, password: password, name: name)
            return user
        } catch{
            print(error)
        }
        return nil
    }
}
