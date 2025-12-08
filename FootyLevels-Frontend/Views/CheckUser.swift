//
//  CheckUser.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-08.
//

import SwiftUI

struct CheckUser: View {
    
    @State var appState = AppStateViewModel()
    
    var body: some View {
        switch appState.isLoggedIn {
        case .loading:
            ProgressView() // Show spinner while Firebase checks auth
        case .loggedIn:
            ContentView(appState: $appState)
        case .notLoggedIn:
            // MARK: The Login Screen
            ZStack {
                // 1. The Background Layer
                Color.gray.opacity(0.1)
                    .edgesIgnoringSafeArea(.all)
                // OR use an image: Image("Background").resizable().ignoresSafeArea()
                
                // 2. The Login Card Layer
                AuthPage(appState: $appState)
                    .transition(.scale) // Adds a nice pop effect when it appears
            }
        }
    }
}

#Preview {
    CheckUser()
}
