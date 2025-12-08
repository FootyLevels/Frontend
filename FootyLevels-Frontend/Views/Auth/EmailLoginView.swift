//
//  EmailLoginView.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-07.
//

import SwiftUI

struct EmailLoginView: View {
    @State var emailVM = EmailLoginViewModel()
//    @Binding var appState:AppStateViewModel

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                
                Text("Welcome Back")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom, 30)
                
                // --- Email Input ---
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email Address")
                        .font(.headline)
                    
                    TextField("you@example.com", text: $emailVM.email)
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
                    
                    SecureField("Enter your password", text: $emailVM.password)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                }
                
                // --- Login Button ---
                Button {
                    Task{
                        if let user = await emailVM.loginWithEmail(){
                            print(user.displayName ?? "John Doe")
                        }
                    }
                    print("Attempting to log in with Email: \(emailVM.email)")
                } label: {
                    Text("Log In")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.top, 20)
                
                Spacer() // Pushes content to the top
                
            }
            .padding(.horizontal, 30)
            .navigationTitle("Log In") // Title shown on the navigation bar
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// Preview
#Preview {
    EmailLoginView()
}
