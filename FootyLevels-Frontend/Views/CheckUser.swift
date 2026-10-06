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
        // 1. Wrap everything in a Group so we can animate the changes
        Group {
            switch appState.isLoggedIn {
            case .loading:
                ProgressView()
                    .scaleEffect(1.5) // Make it a bit bigger
                    .transition(.opacity)
                
            case .loggedIn:
                // Skill Lab projects: upload a clip, reconstruct key frames or
                // the whole video. It owns its NavigationStack; appState is
                // handed down so it can offer sign-out.
                ProjectsListView(appState: appState)
                // 2. Define how this view enters/exits
                .transition(.opacity)
                
            case .notLoggedIn:
                ZStack {
                    Color.gray.opacity(0.1)
                        .edgesIgnoringSafeArea(.all)
                    
                    AuthPage(appState: $appState)
                }
                // 3. You can combine transitions (e.g., Fade + Slide Up)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // 4. The Magic Line: Animate whenever 'isLoggedIn' changes
        .animation(.easeInOut(duration: 0.5), value: appState.isLoggedIn)
    }
}

#Preview {
    CheckUser()
}
