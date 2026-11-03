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

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                // Scrolls so the largest text sizes never push the buttons off screen.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        BrandMark(size: 20, onImage: true)
                            .padding(.horizontal, 18)
                            .padding(.top, 10)
                        Spacer(minLength: 160)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Welcome to FootyLevels")
                                .font(.system(.largeTitle))
                                .tracking(-0.6)
                                .foregroundStyle(.white)
                                .accessibilityAddTraits(.isHeader)
                            Text("Choose how you want to sign in or create an account.")
                                .font(.system(.subheadline))
                                .foregroundStyle(.white.opacity(0.92))
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 24)
                        choices(bottomInset: proxy.safeAreaInsets.bottom)
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
                    LinearGradient(colors: [.black.opacity(colorScheme == .dark ? 0.45 : 0), .clear],
                                   startPoint: .top, endPoint: .center)
                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                }
                .ignoresSafeArea()
                .accessibilityHidden(true)
            }
            .toolbar(.hidden, for: .navigationBar)
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
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 12 + bottomInset)
        .frame(maxWidth: .infinity)
        .background(SL.page, in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32))
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

// Preview
#Preview {
    AuthPage(appState: .constant(AppStateViewModel()))
}
