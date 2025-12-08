//
//  AppStateViewModel.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-07.
//

import Foundation
import SwiftUI

@Observable
final class AppStateViewModel: ObservableObject{
    var currentUser: UserInfo? = nil
    
    init() {
        self.currentUser = AuthManager.shared.getLoggedInUser()
    }
    
    func signOut() throws{
        try AuthManager.shared.signOut()
    }
}
