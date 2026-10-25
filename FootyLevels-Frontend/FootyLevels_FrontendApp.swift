//
//  FootyLevels_FrontendApp.swift
//  FootyLevels-Frontend
//
//  Created by Kunal Bajaj on 2025-11-20.
//

import SwiftUI
import FirebaseCore
import GoogleSignIn


@main
struct FootyLevels_FrontendApp: App {
    init() {
            ApplicationEnvironment.configureFirebase()
        }
    
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                // Local sample entry remains available; it grants no API identity.
                if ProcessInfo.processInfo.arguments.contains("--require-login") {
                    CheckUser()
                } else {
                    MainTabView(appState: nil)
                }
                #else
                CheckUser()
                #endif
            }
                .preferredColorScheme(.light)
                .tint(SL.green)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
