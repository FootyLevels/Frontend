import Foundation

/// Where the Skill Lab server lives, persisted across launches.
///
/// The Simulator shares the Mac's network stack, so loopback reaches a server
/// started with the default `local` policy. A physical device needs the address
/// that `scripts/serve_lan.sh` prints (e.g. `http://192.168.1.42:8000`), and the
/// server must be running in `lan` mode — so there's no sensible default there.
enum ServerSettings {
    static let storageKey = "skillLab.serverURL"

    static var defaultAddress: String {
        #if targetEnvironment(simulator)
        "http://127.0.0.1:8000"
        #else
        ""
        #endif
    }

    static var address: String {
        get { UserDefaults.standard.string(forKey: storageKey) ?? defaultAddress }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }

    static var baseURL: URL? { normalize(address) }

    /// Accepts what people actually paste: a bare `192.168.1.42:8000`, or the
    /// full `…/api/health` URL the server prints at startup.
    static func normalize(_ text: String) -> URL? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") { value = "http://" + value }
        guard var components = URLComponents(string: value),
              let host = components.host, !host.isEmpty,
              components.scheme == "http" || components.scheme == "https" else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

/// Client for the Skill Lab backend (`3d-model-backend`).
///
/// The server rejects any `Host` its network policy doesn't accept. In the
/// default `local` mode that's everything except loopback, so a physical device
/// only works once the server runs with `SKILL_LAB_NETWORK=lan`.
final class SkillLabClient {
    static let shared = SkillLabClient()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        // Upload runs FFmpeg transcoding and key-frame proposal before it
        // responds, so the connection can sit silent for minutes.
        config.timeoutIntervalForRequest = 600
        config.timeoutIntervalForResource = 900
        self.session = URLSession(configuration: config)
    }

    // MARK: - Reads

    func health() async throws -> SkillLabHealth {
        try await get("/api/health")
    }

    /// Checks a candidate address before it's saved, so a typo is caught in
    /// the settings sheet rather than as a broken project list.
    func health(at base: URL) async throws -> SkillLabHealth {
        let url = base.appendingPathComponent("api/health")
        let (data, response) = try await transport(url) { try await self.session.data(from: url) }
        try Self.validate(response, data: data)
        return try JSONDecoder().decode(SkillLabHealth.self, from: data)
    }

    func projects() async throws -> [SkillLabProject] {
        try await get("/api/projects")
    }

    func project(id: String) async throws -> SkillLabProject {
        // The example is read from the app bundle, so it opens with no server.
        if BundledSample.isSample(id), let sample = BundledSample.project {
            return sample
        }
        return try await get("/api/projects/\(id)")
    }

    func sequence(path: String) async throws -> MotionSequence {
        let data = try await data(path: path)
        return try JSONDecoder().decode(MotionSequence.self, from: data)
    }

    /// Raw bytes of any served asset — frames, GLBs, motion chunks, topology.
    func data(path: String) async throws -> Data {
        let url = try url(for: path)
        if url.isFileURL {
            // Bundled sample assets; reading off the main thread keeps a 3 MB
            // chunk from stalling playback.
            return try await Task.detached { try Data(contentsOf: url) }.value
        }
        let (data, response) = try await transport(url) { try await self.session.data(from: url) }
        try Self.validate(response, data: data)
        return data
    }

    /// Resolves a server path such as `/assets-data/...` against the base URL,
    /// or to the app bundle for the included sample.
    /// Query strings survive — `sequenceUrl` carries a `?v=` cache-buster.
    func url(for path: String) throws -> URL {
        if let bundled = BundledSample.fileURL(forAssetPath: path) {
            return bundled
        }
        if let absolute = URL(string: path), absolute.scheme != nil {
            return absolute
        }
        guard let base = ServerSettings.baseURL else { throw SkillLabError.notConfigured }
        guard let url = URL(string: path, relativeTo: base)?.absoluteURL else {
            throw SkillLabError.badPath(path)
        }
        return url
    }

    func motionAssetPath(projectId: String, file: String) -> String {
        "/assets-data/\(projectId)/motion/\(file)"
    }

    // MARK: - Project writes

    /// Uploads a video and returns the prepared project.
    ///
    /// The multipart body is assembled on disk and streamed with
    /// `upload(for:fromFile:)`, so a 200 MB clip never sits in memory whole.
    func uploadVideo(
        at fileURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> SkillLabProject {
        let boundary = "SkillLab-\(UUID().uuidString)"
        let bodyURL = try Self.writeMultipartBody(file: fileURL, boundary: boundary)
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        var request = URLRequest(url: try url(for: "/api/projects"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let delegate = UploadProgressDelegate(onProgress: progress)
        let (data, response) = try await transport(request.url) {
            try await self.session.upload(for: request, fromFile: bodyURL, delegate: delegate)
        }
        try Self.validate(response, data: data)
        return try JSONDecoder().decode(SkillLabProject.self, from: data)
    }

    /// Permanently removes a project — its video, key frames and 3D results —
    /// from the server. Fails with `.server(status: 409, …)` while a
    /// reconstruction is running, and 404 once it is already gone.
    func deleteProject(id: String) async throws {
        try await perform("DELETE", "/api/projects/\(id)", body: nil)
    }

    func addFrame(projectId: String, timestamp: Double, label: String = "") async throws -> SkillLabProject {
        try await send("POST", "/api/projects/\(projectId)/frames",
                       body: ["timestamp": timestamp, "label": label])
    }

    /// `bbox` is normalised `[left, top, right, bottom]`. Changing it resets the
    /// frame to `pending` server-side and discards its old mesh.
    func updateFrame(projectId: String, frameId: String, bbox: [Double]) async throws -> SkillLabProject {
        try await send("PATCH", "/api/projects/\(projectId)/frames/\(frameId)", body: ["bbox": bbox])
    }

    func deleteFrame(projectId: String, frameId: String) async throws -> SkillLabProject {
        try await send("DELETE", "/api/projects/\(projectId)/frames/\(frameId)", body: nil)
    }

    /// Queues key-frame mesh generation. With `frameIds` nil the server picks
    /// every frame that isn't already `ready`.
    func generateMeshes(projectId: String, provider: String, frameIds: [String]? = nil) async throws {
        var body: [String: Any] = ["provider": provider]
        if let frameIds { body["frameIds"] = frameIds }
        let _: ReconstructionJob = try await send("POST", "/api/projects/\(projectId)/generate", body: body)
    }

    /// Queues whole-video tracking, body and ball reconstruction.
    func startMotion(projectId: String) async throws {
        let _: MotionState = try await send("POST", "/api/projects/\(projectId)/motion", body: nil)
    }

    // MARK: - Plumbing

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let url = try url(for: path)
        let (data, response) = try await transport(url) { try await self.session.data(from: url) }
        try Self.validate(response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Runs a request, turning connection-level failures into an error that
    /// names the address and says what usually fixes it.
    private func transport<T>(_ url: URL?, _ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as URLError where SkillLabError.isUnreachable(error) {
            throw SkillLabError.unreachable(host: url?.host() ?? "the server", underlying: error)
        }
    }

    private func send<T: Decodable>(_ method: String, _ path: String, body: [String: Any]?) async throws -> T {
        let data = try await perform(method, path, body: body)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Sends a request and returns its validated body, which is empty for 204.
    @discardableResult
    private func perform(_ method: String, _ path: String, body: [String: Any]?) async throws -> Data {
        var request = URLRequest(url: try url(for: path))
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await transport(request.url) { try await self.session.data(for: request) }
        try Self.validate(response, data: data)
        return data
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SkillLabError.noResponse
        }
        guard !(200...299).contains(http.statusCode) else { return }
        throw SkillLabError.server(status: http.statusCode,
                                   message: ServerErrorBody.message(from: data))
    }

    private static func writeMultipartBody(file: URL, boundary: String) throws -> URL {
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-\(UUID().uuidString).multipart")
        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: bodyURL)
        defer { try? output.close() }

        // The server validates by extension, so the original name must survive.
        let filename = file.lastPathComponent
        let header = "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
            + "Content-Type: \(mimeType(for: file))\r\n\r\n"
        try output.write(contentsOf: Data(header.utf8))

        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }

        try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
        return bodyURL
    }

    private static func mimeType(for file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "mov": return "video/quicktime"
        case "mp4", "m4v": return "video/mp4"
        case "webm": return "video/webm"
        case "mkv": return "video/x-matroska"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Errors

enum SkillLabError: LocalizedError {
    case noResponse
    case notConfigured
    case badPath(String)
    case unreachable(host: String, underlying: URLError)
    case server(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .noResponse:
            return "The server didn't respond."
        case .notConfigured:
            return "Set the server address first. Run scripts/serve_lan.sh on the server and enter the URL it prints."
        case .badPath(let path):
            return "Malformed asset path: \(path)"
        case .unreachable(let host, _):
            #if targetEnvironment(simulator)
            return "Can't reach \(host). Is the API running on port 8000?"
            #else
            return "Can't reach \(host). Start the server with scripts/serve_lan.sh (it binds 0.0.0.0), check this device is on the same network, and allow Local Network access in Settings if asked."
            #endif
        case .server(let status, let message):
            // network.py's rejection when the Host isn't allowed — which, from
            // a device, almost always means the server is still in `local` mode.
            if status == 400, message == "Invalid host header" {
                return "The server refused this device. Restart it with scripts/serve_lan.sh, or set SKILL_LAB_NETWORK=lan."
            }
            return message ?? "Server error (\(status))."
        }
    }

    /// Failures where no HTTP exchange happened at all.
    static func isUnreachable(_ error: URLError) -> Bool {
        [.cannotConnectToHost, .cannotFindHost, .timedOut, .networkConnectionLost,
         .notConnectedToInternet, .dnsLookupFailed].contains(error.code)
    }
}

/// FastAPI error bodies: `detail` is a string for `HTTPException`, but a list
/// of `{msg, loc, …}` objects for request-validation failures.
private struct ServerErrorBody: Decodable {
    let detail: Detail

    enum Detail: Decodable {
        case message(String)
        case validation([ValidationIssue])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .message(text)
            } else {
                self = .validation(try container.decode([ValidationIssue].self))
            }
        }
    }

    struct ValidationIssue: Decodable {
        let msg: String
    }

    static func message(from data: Data) -> String? {
        guard let body = try? JSONDecoder().decode(ServerErrorBody.self, from: data) else {
            return nil
        }
        switch body.detail {
        case .message(let text): return text
        case .validation(let issues): return issues.map(\.msg).joined(separator: "\n")
        }
    }
}

// MARK: - Upload progress

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
