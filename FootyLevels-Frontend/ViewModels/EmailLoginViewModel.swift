//
//  EmailLoginViewModel.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-07.
//

import SwiftUI
@MainActor
@Observable
final class EmailLoginViewModel{
    var email: String = ""
    var password:String = ""
    
    func loginWithEmail() async -> UserInfo?{
        
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else{
            return nil
        }
        
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else{
            return nil
        }
        
        do{
            let user = try await AuthManager.shared.loginWithEmail(email: email, password: password)
            return user
        }catch{
            print(error)
        }
        
        return nil
    }
}
