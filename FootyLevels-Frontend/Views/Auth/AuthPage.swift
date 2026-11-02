//
//  AuthPage.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-07.
//

import SwiftUI
import GoogleSignInSwift
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

    var body: some View {
        NavigationStack {
            // Scrolls so the largest text sizes never push the buttons off screen.
            ScrollView {
                VStack(spacing: 20) {
                    Text("Welcome to FootyLevels")
                        .font(SL.display(.largeTitle, .heavy))
                        .foregroundStyle(SL.ink)
                        .multilineTextAlignment(.center)

                    Text("Choose how you want to sign in or create an account.")
                        .font(.subheadline)
                        .foregroundStyle(SL.muted)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 40)

                    // --- 1. Google Login Button ---
                    // Uses the dedicated GIDSignInButton
                    GoogleSignInButton(action: signInWithGoogle)
                        .frame(minHeight: 50) // Standard button height; taller when the text is larger

                    if let message = authVM.errorMessage {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(SL.errorText)
                            .accessibilityIdentifier("signInError")
                    }

                    // --- Divider ---
                    HStack {
                        VStack { Divider() }
                        Text("OR")
                            .font(.caption)
                            .foregroundStyle(SL.muted)
                        VStack { Divider() }
                    }
                    .padding(.horizontal)

                    // --- 2. Email Sign Up Button ---
                    NavigationLink(value: AuthRoute.signUp) {
                        Label("Sign Up with Email", systemImage: "person.badge.plus.fill")
                    }
                    .buttonStyle(.slPrimaryWide)

                    // --- 3. Regular Email Login Button ---
                    NavigationLink(value: AuthRoute.logIn) {
                        Label("Log In with Email", systemImage: "envelope.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.slSecondary)
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 64)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(SL.page.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar) // Hide the default navigation bar for a clean look
            .navigationDestination(for: AuthRoute.self) { route in
                switch route {
                case .signUp: EmailSignUpView(appState: $appState)
                case .logIn: EmailLoginView(appState: $appState)
                }
            }
        }
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
