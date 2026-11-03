//
//  EmailLoginView.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-07.
//

import SwiftUI

/// Pushed onto `AuthPage`'s navigation stack, so it has no stack of its own.
struct EmailLoginView: View {
    @State private var emailVM = UserLoginViewModel()
    @Binding var appState:AppStateViewModel

    private enum Field { case email, password }
    @FocusState private var focus: Field?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Welcome Back")
                    .font(SL.display(.largeTitle))
                    .foregroundStyle(SL.ink)
                    .padding(.bottom, 30)

                // --- Email Input ---
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email Address").font(.headline).foregroundStyle(SL.ink)
                    TextField("you@example.com", text: $emailVM.email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                        .slField()
                }

                // --- Password Input ---
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password").font(.headline).foregroundStyle(SL.ink)
                    SecureField("Enter your password", text: $emailVM.password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(logIn)
                        .slField()
                }

                // MARK: --- Error Message Display ---
                if let errorMessage = emailVM.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(SL.errorText)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .transition(.opacity) // Fade in effect
                }

                // --- Login Button ---
                Button("Log In", action: logIn)
                    .buttonStyle(.slPrimaryWide)
                    .disabled(emailVM.isLoading)
                    .padding(.top, 20)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(SL.page.ignoresSafeArea())
        .slScreen()
        .navigationTitle("Log In")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func logIn() {
        guard !emailVM.isLoading else { return }
        Task {
            if let user = await emailVM.loginWithEmail() {
                appState.currentUser = user
                appState.isLoggedIn = .loggedIn
            }
        }
    }
}

// Preview
#Preview {
    NavigationStack {
        EmailLoginView(appState: .constant(AppStateViewModel()))
    }
}
