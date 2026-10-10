import FirebaseCore
import Foundation
import GoogleSignIn

enum ApplicationEnvironment: String {
    case dev, demo

    static var current: Self {
        #if DEBUG
        return Self(rawValue: ProcessInfo.processInfo.environment["FOOTYLEVELS_ENVIRONMENT"] ?? "dev") ?? .dev
        #else
        return .demo
        #endif
    }

    var projectID: String { "footylevels-\(rawValue)-20261009" }
    var configurationName: String { "GoogleService-Info-\(self == .dev ? "Dev" : "Demo")" }

    /// This is separate from the legacy Skill Lab address. Only a release's
    /// configured application origin receives Firebase credentials.
    static var apiBaseURL: URL? {
        #if DEBUG
        if let address = ProcessInfo.processInfo.environment["FOOTYLEVELS_API_URL"] {
            return URL(string: address)
        }
        #endif
        guard let address = Bundle.main.object(forInfoDictionaryKey: "FootyLevelsAPIBaseURL") as? String,
              !address.isEmpty else { return nil }
        return URL(string: address)
    }

    static func configureFirebase() {
        guard let path = Bundle.main.path(forResource: current.configurationName, ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path),
              options.projectID == current.projectID else {
            preconditionFailure("Missing matching Firebase application configuration")
        }
        FirebaseApp.configure(options: options)
        if let clientID = options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
    }
}
