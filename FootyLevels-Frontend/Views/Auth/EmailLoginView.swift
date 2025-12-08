//
//  EmailLoginView.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-07.
//

import SwiftUI

struct EmailLoginView: View {
    @State var emailVM = EmailLoginViewModel()
    @Binding var appState:AppStateViewModel

    var body: some View {
        // Remove NavigationView if this view is already inside one (from AuthPage)
                // If it's not, keep it. I'll keep a Vstack wrapper for safety.
                VStack(spacing: 20) {
                    
                    Text("Welcome Back")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.bottom, 30)
                    
                    // --- Email Input ---
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email Address").font(.headline)
                        TextField("you@example.com", text: $emailVM.email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never) // Updated syntax
                            .autocorrectionDisabled(true)        // Updated syntax
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                    }
                    
                    // --- Password Input ---
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password").font(.headline)
                        SecureField("Enter your password", text: $emailVM.password)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                    }
                    
                    // MARK: --- Error Message Display ---
                    if let errorMessage = emailVM.errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .transition(.opacity) // Fade in effect
                    }
                    
                    // --- Login Button ---
                    Button {
                        print("🔵 BUTTON WAS CLICKED") // <--- Add this
                        Task {
                            if let user = await emailVM.loginWithEmail() {
                                 print("🟢 LOGIN SUCCESS") // <--- Add this
                                 appState.currentUser = user
                                 appState.isLoggedIn = .loggedIn
                            }
                        }
                    } label: {
                        Text("Log In")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .disabled(emailVM.isLoading) // Prevent double clicking
                            .padding(.top, 20)
                                
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 30)
                .navigationTitle("Log In")
                .navigationBarTitleDisplayMode(.inline)
            }
}

// Preview
#Preview {
    EmailLoginView(appState: .constant(AppStateViewModel()))
}
