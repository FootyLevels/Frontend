//
//  CheckUser.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-08.
//

import SwiftUI

struct CheckUser: View {
    
    @State private var appState = AppStateViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    SL.page
                        .ignoresSafeArea()

                    AuthPage(appState: $appState)
                }
                // 3. Fade + slide up, or just a fade when Reduce Motion is on
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        // 4. The Magic Line: Animate whenever 'isLoggedIn' changes
        .animation(.easeInOut(duration: 0.5), value: appState.isLoggedIn)
    }
}

#Preview {
    CheckUser()
}
