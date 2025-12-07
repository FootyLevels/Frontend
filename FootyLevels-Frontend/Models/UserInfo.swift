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
    
    init(user: User) {
        self.uid = user.uid
        self.email = user.email
        self.displayName = user.displayName
    }
}
