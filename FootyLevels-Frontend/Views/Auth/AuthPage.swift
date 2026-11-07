//
//  AuthPage.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-07.
//

import SwiftUI
import FirebaseAuth

/// The two email screens reachable from the sign-in page.
private enum AuthRoute: Hashable {
    case signUp, logIn
}

struct AuthPage: View {

    // Use the environment object or state object for your service
    @State private var authVM = UserLoginViewModel()
    @Binding var appState:AppStateViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// On for the launch: the logo springs up, the words rise, the sheet slides in.
    @State private var launched = false
    /// On once the launch has settled: the logo moves like a level meter and "Levels" shines.
    @State private var alive = false
    @State private var drifting = false
    @State private var tilt = TiltReader()

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                // Scrolls so the largest text sizes never push the buttons off screen.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        BrandMark(size: 20, onImage: true, drawn: launched, levels: alive)
                            .offset(x: 3 * tilt.x, y: 3 * tilt.y)
                            .padding(.horizontal, 18)
                            .padding(.top, 10)
                        Spacer(minLength: 160)
                        VStack(alignment: .leading, spacing: 10) {
                            SignInTitle(shown: launched, alive: alive)
                            Text("Choose how you want to sign in or create an account.")
                                .font(.system(.subheadline))
                                .foregroundStyle(.white.opacity(0.92))
                                .modifier(FadeUp(shown: launched, delay: 0.72))
                        }
                        // The words move a little with the phone; the photo moves the other way.
                        .offset(x: 6 * tilt.x, y: 5 * tilt.y)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 24)
                        choices(bottomInset: proxy.safeAreaInsets.bottom)
                            .offset(y: launched ? 0 : 440)
                            .animation(reduceMotion ? nil : .timingCurve(0.32, 0.72, 0, 1, duration: 0.64).delay(0.42), value: launched)
                    }
                    .frame(minHeight: proxy.size.height + proxy.safeAreaInsets.bottom)
                }
                .scrollBounceBehavior(.basedOnSize)
                // The sheet runs to the bottom edge; its buttons pad above the home indicator.
                .ignoresSafeArea(edges: .bottom)
            }
            .background {
                ZStack {
                    Image("LearnHero")
                        .resizable()
                        .scaledToFill()
                        // A slow drift, and a shift against the phone's tilt.
                        .scaleEffect(drifting ? 1.18 : 1.08, anchor: UnitPoint(x: 0.6, y: 0.4))
                        .offset(x: (drifting ? -14 : 0) - 16 * tilt.x, y: (drifting ? -22 : 0) - 20 * tilt.y)
                    LinearGradient(colors: [.black.opacity(colorScheme == .dark ? 0.45 : 0), .clear],
                                   startPoint: .top, endPoint: .center)
                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                }
                .ignoresSafeArea()
                .opacity(launched ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.9), value: launched)
                .accessibilityHidden(true)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await launch() }
            .onAppear { if !reduceMotion { tilt.start() } }
            .onDisappear { tilt.stop() }
            .navigationDestination(for: AuthRoute.self) { route in
                switch route {
                case .signUp: EmailSignUpView(appState: $appState)
                case .logIn: EmailLoginView(appState: $appState)
                }
            }
        }
    }

    /// The bottom sheet: the three ways in, padded above the home indicator.
    private func choices(bottomInset: CGFloat) -> some View {
        VStack(spacing: 10) {
            NavigationLink(value: AuthRoute.signUp) {
                Label("Sign Up with Email", systemImage: "envelope.fill")
            }
            .buttonStyle(.slPrimaryWide)
            .modifier(FadeUp(shown: launched, delay: 0.7))

            // A pill in the app's style carrying Google's official four-colour mark.
            Button(action: signInWithGoogle) {
                HStack(spacing: 10) {
                    Image("GoogleG")
                        .resizable()
                        .scaledToFit()
                        .scaledFrame(width: 20, relativeTo: .subheadline)
                        .accessibilityHidden(true)
                    Text("Continue with Google")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
            }
            .buttonStyle(.slSecondary)
            .modifier(FadeUp(shown: launched, delay: 0.77))

            if let message = authVM.errorMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(SL.errorText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("signInError")
            }

            NavigationLink(value: AuthRoute.logIn) {
                Text("Log In with Email")
                    .font(.system(.callout, weight: .semibold))
                    .foregroundStyle(SL.link)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .modifier(FadeUp(shown: launched, delay: 0.84))
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 12 + bottomInset)
        .frame(maxWidth: .infinity)
        .background(SL.page, in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32))
    }

    /// Plays the launch once per visit; after it settles, the logo and photo keep moving.
    /// With Reduce Motion everything simply shows, still.
    private func launch() async {
        if !launched {
            if reduceMotion {
                launched = true
                return
            }
            // Let the screen lay out first, so only the launch's own pieces animate.
            try? await Task.sleep(for: .milliseconds(80))
            launched = true
            try? await Task.sleep(for: .seconds(1.4))
        }
        guard !reduceMotion, !alive else { return }
        alive = true
        withAnimation(.easeInOut(duration: 22).repeatForever(autoreverses: true)) { drifting = true }
    }

    private func signInWithGoogle() {
        Task {
            do {
                if let user = try await authVM.signInWithGoogle() {
                    appState.currentUser = user
                    appState.isLoggedIn = .loggedIn
                    dismiss()
                }
            } catch {
                authVM.errorMessage = error.localizedDescription
            }
        }
    }
}

/// Fades a piece of the sign-in screen up into place during the launch.
private struct FadeUp: ViewModifier {
    let shown: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.5).delay(delay), value: shown)
    }
}

// Preview
#Preview {
    AuthPage(appState: .constant(AppStateViewModel()))
}
