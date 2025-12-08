//
//  AppStateViewModel.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-07.
//

import Foundation
import SwiftUI

enum IsLoggedIn{
    case loading
    case loggedIn
    case notLoggedIn
}

@Observable
final class AppStateViewModel: ObservableObject{
    var currentUser: UserInfo? = nil
    var isLoggedIn: IsLoggedIn = .loading
    
    init() {
            checkLoginStatus()
        }
        
        private func checkLoginStatus() {
            // 2. Check if a user exists
            if let currentUser = AuthManager.shared.getLoggedInUser() {
                print("User found: \(currentUser)")
                self.currentUser = currentUser
                self.isLoggedIn = .loggedIn
            } else {
                print("No user found.")
                self.currentUser = nil
                self.isLoggedIn = .notLoggedIn
            }
        }
        
        func signOut() throws {
            // Ensure you update state when signing out
            try AuthManager.shared.signOut()
            self.currentUser = nil
            self.isLoggedIn = .notLoggedIn
        }
}
