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
                SLLoadingState(title: "Opening FootyLevels…", detail: "Connecting your account securely.")
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SL.page)
                    .transition(.opacity)
                
            case .loggedIn:
                // Videos (upload a clip, reconstruct key frames or the whole
                // video) and Overlay (compare two clips' 3D motion), as tabs.
                // appState is handed down so the Videos tab can offer sign-out.
                MainTabView(appState: appState)
                .id(appState.currentUser?.uid)
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
