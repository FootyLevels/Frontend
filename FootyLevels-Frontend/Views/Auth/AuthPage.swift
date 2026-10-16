//
//  AuthPage.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-07.
//

import SwiftUI
import GoogleSignInSwift
import FirebaseAuth

struct AuthPage: View {
    
    // Use the environment object or state object for your service
    @State private var authVM = UserLoginViewModel()
    @Binding var appState:AppStateViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                
                Spacer()
                
                Text("Welcome to FootyLevels")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Choose how you want to sign in or create an account.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 40)
                
                // --- 1. Google Login Button ---
                // Uses the dedicated GIDSignInButton
                GoogleSignInButton {
                    Task {
                        do {
                            if let user = try await authVM.signInWithGoogle(){
                                appState.currentUser = user
                                appState.isLoggedIn = .loggedIn
                                dismiss()
                            }
                            

                            // Optional: Add logic to dismiss the view or navigate on success
                        } catch {
                            authVM.errorMessage = error.localizedDescription
                        }
                    }
                }
                .frame(height: 50) // Standard button height

                if let message = authVM.errorMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("signInError")
                }
                
                // --- Divider ---
                HStack {
                    VStack { Divider() }
                    Text("OR")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    VStack { Divider() }
                }
                .padding(.horizontal)
                
                // --- 2. Email Sign Up Button ---
                NavigationLink(destination: EmailSignUpView(appState: $appState)) {
                    HStack {
                        Image(systemName: "person.badge.plus.fill")
                        Text("Sign Up with Email")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                
                // --- 3. Regular Email Login Button ---
                NavigationLink(destination: EmailLoginView( appState: $appState)) {
                    HStack {
                        Image(systemName: "envelope.fill")
                        Text("Log In with Email")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                
                Spacer()
                Spacer()
            }
            .padding(.horizontal, 30)
            .toolbar(.hidden, for: .navigationBar) // Hide the default navigation bar for a clean look
        }
    }
}

// Preview
#Preview {
    AuthPage(appState: .constant(AppStateViewModel()))
}
