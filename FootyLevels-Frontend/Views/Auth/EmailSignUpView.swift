//
//  EmailSignUpView.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-07.
//
import SwiftUI

/// Pushed onto `AuthPage`'s navigation stack, so it has no stack of its own.
struct EmailSignUpView: View {
    @Binding var appState:AppStateViewModel

    @State private var signUpVM = UserSigninViewModel()
    @State private var confirmPassword = ""

    private enum Field { case name, email, password, confirm }
    @FocusState private var focus: Field?

    // Simple computed property for password validation feedback
    var passwordsMatch: Bool {
        return signUpVM.password == confirmPassword
    }

    /// Disable the button if passwords don't match or required fields are empty.
    private var canSignUp: Bool {
        passwordsMatch && !signUpVM.email.isEmpty && !signUpVM.password.isEmpty && !signUpVM.name.isEmpty && !signUpVM.isLoading
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Create Your Account")
                    .font(SL.display(.largeTitle, .heavy))
                    .foregroundStyle(SL.ink)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 20)

                // --- Name Input ---
                VStack(alignment: .leading, spacing: 8) {
                    Text("Full Name").font(.headline).foregroundStyle(SL.ink)
                    TextField("John Doe", text: $signUpVM.name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .focused($focus, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focus = .email }
                        .slField()
                }

                // --- Email Input ---
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email Address").font(.headline).foregroundStyle(SL.ink)
                    TextField("you@example.com", text: $signUpVM.email)
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
                // .newPassword lets iOS suggest a strong password and save it.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password").font(.headline).foregroundStyle(SL.ink)
                    SecureField("Create a password", text: $signUpVM.password)
                        .textContentType(.newPassword)
                        .focused($focus, equals: .password)
                        .submitLabel(.next)
                        .onSubmit { focus = .confirm }
                        .slField()
                }

                // --- Confirm Password Input ---
                VStack(alignment: .leading, spacing: 8) {
                    Text("Confirm Password").font(.headline).foregroundStyle(SL.ink)
                    SecureField("Re-enter password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .focused($focus, equals: .confirm)
                        .submitLabel(.go)
                        .onSubmit(signUp)
                        .slField()

                    // Validation Message
                    if !confirmPassword.isEmpty && !passwordsMatch {
                        Text("Passwords do not match.")
                            .foregroundStyle(SL.errorText)
                            .font(.callout)
                    }
                }

                if let error = signUpVM.errorMessage {
                    Text(error).foregroundStyle(SL.errorText).font(.callout)
                }

                // --- Sign Up Button ---
                Button("Sign Up", action: signUp)
                    .buttonStyle(.slPrimaryWide)
                    .disabled(!canSignUp)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(SL.page.ignoresSafeArea())
        .slScreen()
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func signUp() {
        guard canSignUp else { return }
        Task {
            if let user = await signUpVM.signUpWithEmail() {
                appState.currentUser = user
                appState.isLoggedIn = .loggedIn
            }
        }
    }
}

// Preview
#Preview {
    NavigationStack {
        EmailSignUpView(appState: .constant(AppStateViewModel()))
    }
}
