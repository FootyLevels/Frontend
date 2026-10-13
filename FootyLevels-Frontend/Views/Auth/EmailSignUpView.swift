//
//  EmailSignUpView.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-07.
//
import SwiftUI

struct EmailSignUpView: View {
    @Binding var appState:AppStateViewModel

    @State var signUpVM = UserSigninViewModel()
    @State private var confirmPassword = ""
    
    // Simple computed property for password validation feedback
    var passwordsMatch: Bool {
        return signUpVM.password == confirmPassword
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                
                Text("Create Your Account")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom, 20)
                
                // --- Name Input ---
                VStack(alignment: .leading, spacing: 8) {
                    Text("Full Name")
                        .font(.headline)
                    
                    TextField("John Doe", text: $signUpVM.name)
                        .autocapitalization(.words)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                }
                
                // --- Email Input ---
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email Address")
                        .font(.headline)
                    
                    TextField("you@example.com", text: $signUpVM.email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                }
                
                // --- Password Input ---
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.headline)
                    
                    SecureField("Create a password", text: $signUpVM.password)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                }
                
                // --- Confirm Password Input ---
                VStack(alignment: .leading, spacing: 8) {
                    Text("Confirm Password")
                        .font(.headline)
                    
                    SecureField("Re-enter password", text: $confirmPassword)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    
                    // Validation Message
                    if !confirmPassword.isEmpty && !passwordsMatch {
                        Text("Passwords do not match.")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                if let error = signUpVM.errorMessage {
                    Text(error).foregroundStyle(.red).font(.callout)
                }

                // --- Sign Up Button ---
                Button {
                    Task{
                        if let user = await signUpVM.signUpWithEmail(){
                            appState.currentUser = user
                            appState.isLoggedIn = .loggedIn
                        }
                    }
                } label: {
                    Text("Sign Up")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(passwordsMatch ? Color.green : Color.gray) // Disable if passwords don't match
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                // Disable the button if passwords don't match or required fields are empty
                .disabled(!passwordsMatch || signUpVM.email.isEmpty || signUpVM.password.isEmpty || signUpVM.name.isEmpty || signUpVM.isLoading)
                .padding(.top, 10)
                
                Spacer() // Pushes content to the top
            }
            .padding(.horizontal, 30)
            .navigationTitle("Sign Up")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// Preview
#Preview {
    EmailSignUpView(appState: .constant(AppStateViewModel()))
}
