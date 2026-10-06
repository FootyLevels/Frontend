import Foundation

/// API Client for FootyLevels backend communication
class APIClient {
    /// Shared singleton instance
    static let shared = APIClient()

    /// Base URL for the API
    /// - For iOS Simulator: use localhost
    /// - For physical device: use your Mac's local IP (e.g., "http://192.168.1.100:8000")
    #if targetEnvironment(simulator)
    private let baseURL = "http://localhost:8000"
    #else
    private let baseURL = "http://192.168.2.205:8000" // Change to your Mac's IP for physical device
    #endif

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        // Reconstruction runs inline on the server — one forward pass through
        // an 840M-parameter model, plus a cold start that loads ~2.8GB of
        // weights on the first request. Hence the generous timeouts.
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Health Check

    /// Check if the API server is reachable
    func healthCheck() async throws -> Bool {
        let url = URL(string: "\(baseURL)/")!
        let (_, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        return httpResponse.statusCode == 200
    }

    // MARK: - 3D Reconstruction (SAM 3D Body)

    /// Upload a still frame for 3D body reconstruction.
    /// - Parameters:
    ///   - imageData: JPEG data. Downscale first — the model doesn't need full
    ///     camera resolution, and smaller uploads cut round-trip time.
    ///   - filename: Reported to the server as the source image name.
    ///   - raw: Requests the `raw` block with binary vertex buffers, which is
    ///     what the renderer prefers. Sent as a multipart field; if the FastAPI
    ///     route declares it as a query parameter instead, append it to `url`.
    ///   - preview: Whether the server should render a preview JPEG. Off by
    ///     default — the app renders the mesh itself and never fetches it, so
    ///     generating one is wasted server work.
    ///   - yUp: Whether the server converts the mesh from its camera frame to
    ///     the Y-up convention. Left on (the server's own default) so the
    ///     vertices arrive in RealityKit's orientation already. Note this
    ///     appears to apply to the mesh only — the keypoints payload still
    ///     reports `space: "camera"`, so the skeleton is converted separately.
    ///   - fieldName: Multipart field name the endpoint expects. Change this if
    ///     the FastAPI route declares something other than `image`.
    func reconstruct(
        imageData: Data,
        filename: String = "frame.jpg",
        raw: Bool = true,
        preview: Bool = false,
        yUp: Bool = true,
        fieldName: String = "image"
    ) async throws -> ReconstructionResponse {
        let url = URL(string: "\(baseURL)/api/reconstruct")!

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        for (name, value) in [("raw", raw), ("preview", preview), ("y_up", yUp)] {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        return try JSONDecoder().decode(ReconstructionResponse.self, from: data)
    }

    /// Re-fetch an existing reconstruction by ID, without re-uploading the image.
    func fetchReconstruction(id: String) async throws -> ReconstructionResponse {
        let url = URL(string: "\(baseURL)/api/reconstruct/\(id)")!
        let (data, response) = try await session.data(from: url)
        try validate(response: response, data: data)

        return try JSONDecoder().decode(ReconstructionResponse.self, from: data)
    }

    /// Fetch the 3D/2D joint positions for a reconstruction.
    /// - Parameter path: The `keypointsPath` from a `ReconstructionResponse`.
    func fetchKeypoints(path: String) async throws -> KeypointsResponse {
        let url = try resolve(path: path)
        let (data, response) = try await session.data(from: url)
        try validate(response: response, data: data)

        return try JSONDecoder().decode(KeypointsResponse.self, from: data)
    }

    /// Download the reconstructed body mesh to a local file.
    /// - Parameter path: The `modelPath` from a `ReconstructionResponse`.
    /// - Returns: A temporary file URL ending in `.usdz`.
    func downloadModel(path: String) async throws -> URL {
        let url = try resolve(path: path)
        let (temporaryURL, response) = try await session.download(from: url)
        try validate(response: response, data: nil)

        // RealityKit infers the format from the file extension, and URLSession
        // names downloads with a random extensionless path — so rename before
        // handing the file to `Entity(contentsOf:)` or it fails to load.
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("reconstruction_\(UUID().uuidString).usdz")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)

        return destination
    }

    /// Download one of the raw binary geometry buffers.
    /// - Parameter path: A `positionsPath` or `normalsPath` from `RawGeometryInfo`.
    func fetchBinary(path: String) async throws -> Data {
        let url = try resolve(path: path)
        let (data, response) = try await session.data(from: url)
        try validate(response: response, data: data)
        return data
    }

    /// Download the shared triangle index buffer, caching it for the process
    /// lifetime.
    ///
    /// `indicesPath` points at `/api/topology` rather than a per-reconstruction
    /// path because the triangle list is the same for every body, so this is
    /// fetched once no matter how many frames are reconstructed. The server
    /// marks it `immutable`, so URLSession's own cache backs this up too.
    func fetchTopology(path: String) async throws -> TopologyBuffer {
        if let cached = await Self.topologyCache.value {
            return cached
        }

        let url = try resolve(path: path)
        let (data, response) = try await session.data(from: url)
        try validate(response: response, data: data)

        // The endpoint self-describes via `X-Triangle-Count` / `X-Index-Dtype`.
        // Trusting that header beats inferring the count from `model.faces`,
        // which belongs to a different part of the response.
        let http = response as? HTTPURLResponse
        let triangleCount = http?
            .value(forHTTPHeaderField: "X-Triangle-Count")
            .flatMap(Int.init)

        let buffer = TopologyBuffer(data: data, triangleCount: triangleCount)
        await Self.topologyCache.store(buffer)
        return buffer
    }

    private static let topologyCache = TopologyCache()

    /// Resolves a server-relative path (`/api/...`) against the base URL.
    /// Absolute URLs are passed through unchanged.
    private func resolve(path: String) throws -> URL {
        if let absolute = URL(string: path), absolute.scheme != nil {
            return absolute
        }
        guard let url = URL(string: baseURL + path) else {
            throw APIError.networkError("Malformed URL for path: \(path)")
        }
        return url
    }

    private func validate(response: URLResponse, data: Data?) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError("No response")
        }

        if (200...299).contains(httpResponse.statusCode) { return }

        // FastAPI puts the useful message in `detail` for every error it raises:
        // 415 for a non-image upload, 422 for undecodable bytes or no person
        // found, 503 for an incomplete model checkpoint. Decode it for any
        // status, so those reach the user as the server worded them rather
        // than as a bare status code.
        let detail = data
            .flatMap { try? JSONDecoder().decode(ErrorResponse.self, from: $0) }?
            .detail

        switch httpResponse.statusCode {
        case 404:
            throw APIError.notFound(detail ?? "Not found")
        case 400...499:
            throw APIError.badRequest(detail ?? "Request rejected (\(httpResponse.statusCode))")
        default:
            throw APIError.serverError(detail ?? "Server error (\(httpResponse.statusCode))")
        }
    }
}

// MARK: - Topology Cache

/// The shared triangle index buffer, plus what the server said about it.
struct TopologyBuffer: Sendable {
    let data: Data
    /// From the `X-Triangle-Count` response header, when present.
    let triangleCount: Int?
}

/// In-memory cache for the shared triangle index buffer.
///
/// An actor because `APIClient` is a singleton reachable from any task. Two
/// concurrent first-calls can both fetch, which wastes one request but is
/// otherwise harmless — not worth serialising the download to avoid.
private actor TopologyCache {
    private var cached: TopologyBuffer?

    var value: TopologyBuffer? { cached }

    func store(_ buffer: TopologyBuffer) {
        cached = buffer
    }
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case networkError(String)
    case serverError(String)
    case badRequest(String)
    case notFound(String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .networkError(let message): return "Network error: \(message)"
        case .serverError(let message): return "Server error: \(message)"
        case .badRequest(let message): return "Bad request: \(message)"
        case .notFound(let message): return "Not found: \(message)"
        case .decodingError(let message): return "Data error: \(message)"
        }
    }
}

// MARK: - Error Response Model

struct ErrorResponse: Codable {
    let success: Bool?
    let error: String?
    let detail: String?
}
