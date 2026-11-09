//
//  CheckUser.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-08.
//

import SwiftUI

struct CheckUser: View {

    @State private var appState = AppStateViewModel()
    /// The screen on show. While the splash plays it trails `appState.isLoggedIn`,
    /// so the old screen stays put until the splash covers it.
    @State private var shown: IsLoggedIn = .loading
    /// Set while the logo splash covers the screen.
    @State private var splash: AuthDirection?
    @State private var splashTask: Task<Void, Never>?
    /// The signed-in tabs start fresh for each account, but keep their identity
    /// while the log-out splash covers them.
    @State private var accountID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Group {
                switch shown {
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
                        .id(accountID)
                        .transition(.opacity)

                case .notLoggedIn:
                    ZStack {
                        SL.page
                            .ignoresSafeArea()

                        AuthPage(appState: $appState)
                    }
                    // Just a fade: the sign-in screen plays its own launch as it appears.
                    .transition(.opacity)
                }
            }

            if let splash {
                AuthSplashView(direction: splash)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onChange(of: appState.isLoggedIn, initial: true) { _, state in
            show(state)
        }
        .onChange(of: appState.currentUser?.uid, initial: true) { _, uid in
            if let uid { accountID = uid }
        }
    }

    private func show(_ state: IsLoggedIn) {
        splashTask?.cancel()
        switch AuthTransition.between(shown, state, reduceMotion: reduceMotion) {
        case .fade:
            withAnimation(.easeInOut(duration: reduceMotion ? 0.25 : 0.5)) {
                shown = state
                splash = nil
            }
        case .splash(let direction):
            splashTask = Task { await playSplash(direction) }
        }
    }

    /// Covers the old screen, swaps to whatever the account state is by then, and fades off.
    private func playSplash(_ direction: AuthDirection) async {
        withAnimation(.easeOut(duration: AuthSplashView.cover)) {
            splash = direction
        }
        try? await Task.sleep(for: .seconds(AuthSplashView.swapAfter))
        guard !Task.isCancelled else { return }
        shown = appState.isLoggedIn
        withAnimation(.easeInOut(duration: AuthSplashView.reveal)) {
            splash = nil
        }
    }
}

#Preview {
    CheckUser()
}
