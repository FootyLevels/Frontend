import FirebaseAuth
import Foundation

@MainActor
final class FirebaseAPICredentials: APICredentials {
    static let shared = FirebaseAPICredentials()
    private var generation = UUID()
    private var observedUID: String?
    private var listener: AuthStateDidChangeListenerHandle?

    private init() {
        observedUID = Auth.auth().currentUser?.uid
        listener = Auth.auth().addStateDidChangeListener { [weak self] _, _ in
            Task { @MainActor in self?.observe(Auth.auth().currentUser?.uid) }
        }
    }

    private func observe(_ uid: String?) {
        if observedUID != uid {
            observedUID = uid
            generation = UUID()
        }
    }

    var currentSession: AccountSession? {
        observe(Auth.auth().currentUser?.uid)
        return observedUID.map { AccountSession(uid: $0, generation: generation) }
    }

    func token(for session: AccountSession, forceRefresh: Bool) async throws -> String {
        guard currentSession == session, let user = Auth.auth().currentUser else {
            throw AccountAPIError.sessionChanged
        }
        do {
            let token = try await user.getIDToken(forcingRefresh: forceRefresh)
            guard currentSession == session else { throw AccountAPIError.sessionChanged }
            return token
        } catch {
            guard currentSession == session else { throw AccountAPIError.sessionChanged }
            if let code = AuthErrorCode(rawValue: (error as NSError).code),
               [.userTokenExpired, .invalidUserToken, .userDisabled, .userNotFound].contains(code) {
                invalidate(session)
                throw AccountAPIError.signInRequired
            }
            throw error
        }
    }

    func invalidate(_ session: AccountSession) {
        guard currentSession == session else { return }
        try? Auth.auth().signOut()
        reset()
    }

    func reset() {
        generation = UUID()
        observedUID = Auth.auth().currentUser?.uid
        URLCache.shared.removeAllCachedResponses()
    }
}
