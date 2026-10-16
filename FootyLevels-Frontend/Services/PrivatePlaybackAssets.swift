import CryptoKit
import Foundation

/// One bounded transfer; only the signed storage capability is sent. State is
/// guarded because URLSession callbacks and task cancellation use different queues.
final class BoundedPlaybackDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private let configuration: URLSessionConfiguration
    private var bytes = Data()
    private var continuation: CheckedContinuation<Data, Error>?
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var cancelled = false

    init(limit: Int, configuration: URLSessionConfiguration = .ephemeral) {
        self.limit = limit; self.configuration = configuration
    }

    func get(_ url: URL) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard !cancelled else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                let config = configuration
                config.urlCache = nil; config.httpCookieStorage = nil
                config.requestCachePolicy = .reloadIgnoringLocalCacheData
                config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 120
                let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
                self.session = session
                var request = URLRequest(url: url)
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                let task = session.dataTask(with: request)
                self.task = task
                lock.unlock()
                task.resume()
            }
        } onCancel: { self.cancel() }
    }

    private func cancel() {
        lock.lock(); cancelled = true; let task = task; lock.unlock()
        task?.cancel()
    }

    private func finish(_ result: Result<Data, Error>) {
        lock.lock()
        let continuation = continuation, session = session
        self.continuation = nil; self.session = nil; task = nil; bytes = Data()
        lock.unlock()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            completionHandler(.cancel)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            finish(.failure([400, 401, 403].contains(code) ? CloudPlaybackError.expired : CloudPlaybackError.unavailable))
            return
        }
        guard response.expectedContentLength <= Int64(limit) else {
            completionHandler(.cancel); finish(.failure(CloudPlaybackError.corruptFile)); return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard continuation != nil else { lock.unlock(); return }
        guard data.count <= limit - bytes.count else { lock.unlock(); finish(.failure(CloudPlaybackError.corruptFile)); return }
        bytes.append(data); lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let bytes = bytes, cancelled = cancelled; lock.unlock()
        if cancelled { finish(.failure(CancellationError())) }
        else if error != nil { finish(.failure(CloudPlaybackError.unavailable)) }
        else { finish(.success(bytes)) }
    }
}

/// Capabilities and a bounded byte cache live only in this account session.
/// Files are verified before local playback; no URL/token is written to disk.
@MainActor
final class PrivatePlaybackAssets {
    typealias Transport = @Sendable (URL, Int) async throws -> Data
    private let api: AuthenticatedAPIClient
    private let credentials: any APICredentials
    private let account: AccountSession
    private let host: String
    private let grantPath: String
    private let artifacts: [String: CloudAssetReference]
    private let transport: Transport
    private var grant: PrivateReadGrant?
    private var refreshing: Task<PrivateReadGrant, Error>?
    private var cache: [String: Data] = [:]
    private var cacheBytes = 0
    private var closed = false
    private let directory: URL

    init(api: AuthenticatedAPIClient, credentials: any APICredentials, environment: ApplicationEnvironment,
         grantPath: String, artifacts: [String: CloudAssetReference], transport: Transport? = nil) throws {
        guard let account = credentials.currentSession else { throw AccountAPIError.signInRequired }
        self.api = api; self.credentials = credentials; self.account = account
        self.host = environment.storageHost.replacingOccurrences(of: ".storage.supabase.co", with: ".supabase.co")
        self.grantPath = grantPath; self.artifacts = artifacts
        self.transport = transport ?? { url, limit in try await BoundedPlaybackDownload(limit: limit).get(url) }
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("footylevels-playback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var resource = URLResourceValues(); resource.isExcludedFromBackup = true
        var location = directory; try location.setResourceValues(resource)
    }

    func checkSession() throws {
        try Task.checkCancellation()
        guard !closed, credentials.currentSession == account else { throw AccountAPIError.sessionChanged }
    }

    func validate(_ value: PrivateReadGrant) throws {
        guard let expiry = value.expiry, expiry > Date(), expiry < Date().addingTimeInterval(360),
              Set(value.assets.keys) == Set(artifacts.keys) else { throw CloudPlaybackError.invalidAsset }
        for (name, asset) in artifacts {
            guard let item = value.assets[name], item.sha256 == asset.sha256, item.byteSize == asset.byteSize,
                  item.contentType == asset.contentType, let url = URL(string: item.url),
                  let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  parts.scheme == "https", parts.host == host, parts.port == nil || parts.port == 443,
                  parts.user == nil, parts.password == nil, parts.fragment == nil,
                  parts.path == "/storage/v1/object/sign/\(asset.bucket)/\(asset.objectKey)",
                  parts.queryItems?.count == 1, parts.queryItems?.first?.name == "token",
                  let token = parts.queryItems?.first?.value, !token.isEmpty, token.utf8.count <= 16_384
            else { throw CloudPlaybackError.invalidAsset }
        }
    }

    private func freshGrant(force: Bool) async throws -> PrivateReadGrant {
        try checkSession()
        if !force, let grant, let expiry = grant.expiry, expiry.timeIntervalSinceNow > 15 { return grant }
        let task: Task<PrivateReadGrant, Error>
        if let refreshing { task = refreshing }
        else {
            task = Task { try JSONDecoder().decode(PrivateReadGrant.self, from: await api.request("POST", path: grantPath)) }
            refreshing = task
        }
        do {
            let result = try await task.value
            try checkSession(); try validate(result)
            grant = result; refreshing = nil
            return result
        } catch { refreshing = nil; throw error }
    }

    func data(file: String) async throws -> Data {
        try checkSession()
        guard let asset = artifacts[file] else { throw CloudPlaybackError.invalidAsset }
        if let cached = cache[file] { return cached }
        for attempt in 0...1 {
            let grant = try await freshGrant(force: attempt > 0)
            try checkSession()
            guard let item = grant.assets[file], let url = URL(string: item.url) else { throw CloudPlaybackError.invalidAsset }
            do {
                let data = try await transport(url, asset.byteSize)
                try checkSession()
                guard data.count == asset.byteSize,
                      SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == asset.sha256
                else { throw CloudPlaybackError.corruptFile }
                if data.count <= 8 * 1024 * 1024, asset.contentType != "video/mp4" {
                    if cacheBytes + data.count > 8 * 1024 * 1024 { cache.removeAll(); cacheBytes = 0 }
                    cache[file] = data; cacheBytes += data.count
                }
                return data
            } catch CloudPlaybackError.expired where attempt == 0 { continue }
        }
        throw CloudPlaybackError.expired
    }

    func localFile(file: String) async throws -> URL {
        let data = try await data(file: file)
        try checkSession()
        let name = SHA256.hash(data: Data(file.utf8)).map { String(format: "%02x", $0) }.joined()
        let url = directory.appendingPathComponent(name).appendingPathExtension(artifacts[file]?.contentType == "video/mp4" ? "mp4" : "bin")
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }

    func close() {
        closed = true; refreshing?.cancel(); refreshing = nil; grant = nil
        cache.removeAll(); cacheBytes = 0
        try? FileManager.default.removeItem(at: directory)
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
}
