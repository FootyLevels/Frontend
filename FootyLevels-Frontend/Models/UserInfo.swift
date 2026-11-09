//
//  User.swift
//  FootyLevels-Frontend
//
//  Created by Digaant Dogra on 2025-12-07.
//
import FirebaseAuth

struct UserInfo{
    let uid:String
    let email: String?
    let displayName: String?
    /// The account's photo, for Google accounts that have one.
    let photoURL: URL?
    let signInMethod: SignInMethod

    enum SignInMethod: Equatable {
        case google, email, other
    }

    init(user: User) {
        self.uid = user.uid
        self.email = user.email
        self.displayName = user.displayName
        self.photoURL = user.photoURL
        let providers = user.providerData.map(\.providerID)
        self.signInMethod = providers.contains("google.com") ? .google : providers.contains("password") ? .email : .other
    }

    init(uid: String, email: String?, displayName: String?, photoURL: URL? = nil, signInMethod: SignInMethod = .other) {
        self.uid = uid
        self.email = email
        self.displayName = displayName
        self.photoURL = photoURL
        self.signInMethod = signInMethod
    }

    /// The name the profile shows: the account's name, else its email.
    var shownName: String {
        if let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        if let email, !email.isEmpty { return email }
        return "Your account"
    }
}
