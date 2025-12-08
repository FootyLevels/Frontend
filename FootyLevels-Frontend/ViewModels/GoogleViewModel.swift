//
//  GoogleViewModel.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-07.
//
import SwiftUI

@MainActor
@Observable
final class GoogleViewModel{
    func signInWithGoogle() async throws -> UserInfo?{
        let token = try await GoogleService().signInWithGoogle()
        let userInfo = try await AuthManager.shared.signInWithGoogle(token: token)
        
        return userInfo
    }
}
