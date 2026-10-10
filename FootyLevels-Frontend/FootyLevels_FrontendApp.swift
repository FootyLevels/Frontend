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
            FirebaseApp.configure()
            print("Firebase configured successfully.")
        }
    
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                // Temporary local testing: open the bundled example without login.
                // CheckUser()
                ProjectsListView()
                #else
                CheckUser()
                #endif
            }
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
