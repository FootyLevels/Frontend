import Foundation

struct AccountSession: Equatable {
    let uid: String
    let generation: UUID
}

@MainActor
protocol APICredentials: AnyObject {
    var currentSession: AccountSession? { get }
    func token(for session: AccountSession, forceRefresh: Bool) async throws -> String
    func invalidate(_ session: AccountSession)
}

enum AccountAPIError: LocalizedError, Equatable {
    case notConfigured, unsafeAddress, signInRequired, sessionChanged, unavailable, forbidden, notFound
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "The account server is not configured yet."
        case .unsafeAddress: return "The account server address isn't supported."
        case .signInRequired: return "Please sign in again to continue."
        case .sessionChanged: return "Your account changed. Please try again."
        case .unavailable: return "The account service is unavailable. Please try again."
        case .forbidden: return "This account isn't available for this action."
        case .notFound: return "This item is no longer available."
        case .server(409): return "The upload or project changed. Refresh, or discard the unfinished draft and import it again."
        case .server(429): return "Private storage is currently full. Your draft is saved; try again after space is available."
        case .server: return "The request couldn't be completed. Please try again."
        }
    }
}

/// No automatic redirects: a redirect must never forward a bearer token or
/// silently change a mutation's method. Signed asset downloads use a separate client.
private final class RejectAPIRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct CloudProfile: Decodable {
    let id: String
    let displayName: String
    let accountState: String
}

@MainActor
final class AuthenticatedAPIClient {
    private let baseURL: URL
    private let credentials: any APICredentials
    private let session: URLSession
    private let redirects = RejectAPIRedirects()

    init(baseURL: URL, credentials: any APICredentials, session: URLSession? = nil) throws {
        guard Self.validBaseURL(baseURL) else { throw AccountAPIError.unsafeAddress }
        self.baseURL = baseURL
        self.credentials = credentials
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        self.session = session ?? URLSession(configuration: config)
    }

    static func validBaseURL(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else { return false }
        if parts.scheme == "https" { return true }
        #if DEBUG && targetEnvironment(simulator)
        return parts.scheme == "http" && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)
        #else
        return false
        #endif
    }

    func bootstrap() async throws -> CloudProfile {
        try JSONDecoder().decode(CloudProfile.self, from: await request("POST", path: "/api/me/bootstrap"))
    }

    func profile() async throws -> CloudProfile {
        try JSONDecoder().decode(CloudProfile.self, from: await request("GET", path: "/api/me"))
    }

    /// Relative API paths only. A server-provided asset URL cannot receive tokens.
    func request(_ method: String, path: String, body: Data? = nil, idempotencyKey: String? = nil) async throws -> Data {
        if let key = idempotencyKey {
            guard key.range(of: "^[a-zA-Z0-9_-]{16,80}$", options: .regularExpression) != nil else {
                throw AccountAPIError.unsafeAddress
            }
        }
        guard path.hasPrefix("/api/"), !path.contains("\\"),
              let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              url.standardized.path.hasPrefix("/api/"),
              url.scheme == baseURL.scheme, url.host == baseURL.host, url.port == baseURL.port,
              url.user == nil, url.password == nil, url.fragment == nil else {
            throw AccountAPIError.unsafeAddress
        }
        guard let account = credentials.currentSession else { throw AccountAPIError.signInRequired }
        for attempt in 0...1 {
            let token = try await credentials.token(for: account, forceRefresh: attempt == 1)
            try requireCurrent(account)
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.httpMethod = method
            request.httpBody = body
            if let key = idempotencyKey { request.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request, delegate: redirects)
            } catch {
                try requireCurrent(account)
                throw error
            }
            try requireCurrent(account)
            guard let http = response as? HTTPURLResponse else { throw AccountAPIError.unavailable }
            switch http.statusCode {
            case 200...299: return data
            case 401 where attempt == 0: continue
            case 401:
                credentials.invalidate(account)
                throw AccountAPIError.signInRequired
            case 403: throw AccountAPIError.forbidden
            case 404: throw AccountAPIError.notFound
            case 503: throw AccountAPIError.unavailable
            default: throw AccountAPIError.server(http.statusCode)
            }
        }
        throw AccountAPIError.signInRequired
    }

    private func requireCurrent(_ account: AccountSession) throws {
        guard !Task.isCancelled, credentials.currentSession == account else {
            throw AccountAPIError.sessionChanged
        }
    }
}
