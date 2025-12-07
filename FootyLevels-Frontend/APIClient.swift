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
        config.timeoutIntervalForRequest = 120 // 2 minutes for video uploads
        config.timeoutIntervalForResource = 300 // 5 minutes total
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

    // MARK: - Skills

    /// Fetch all available skills from the backend
    func fetchSkills() async throws -> [SkillInfo] {
        let url = URL(string: "\(baseURL)/api/skills")!
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError("Failed to fetch skills")
        }

        return try JSONDecoder().decode([SkillInfo].self, from: data)
    }

    /// Fetch skills filtered by difficulty
    func fetchSkillsByDifficulty(_ difficulty: String) async throws -> [SkillInfo] {
        let url = URL(string: "\(baseURL)/api/skills/difficulty/\(difficulty)")!
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError("Failed to fetch skills by difficulty")
        }

        return try JSONDecoder().decode([SkillInfo].self, from: data)
    }

    /// Fetch details for a specific skill
    func fetchSkillDetails(skillId: String) async throws -> SkillDetails {
        let url = URL(string: "\(baseURL)/api/skills/\(skillId)")!
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError("No response")
        }

        if httpResponse.statusCode == 404 {
            throw APIError.notFound("Skill not found: \(skillId)")
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError("Failed to fetch skill details")
        }

        return try JSONDecoder().decode(SkillDetails.self, from: data)
    }

    // MARK: - Players

    /// Fetch all players from the backend
    func fetchPlayers() async throws -> [PlayerInfo] {
        let url = URL(string: "\(baseURL)/api/players")!
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError("Failed to fetch players")
        }

        return try JSONDecoder().decode([PlayerInfo].self, from: data)
    }

    /// Fetch players by category (legend or current)
    func fetchPlayersByCategory(_ category: String) async throws -> [PlayerInfo] {
        let url = URL(string: "\(baseURL)/api/players/category/\(category)")!
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError("Failed to fetch players by category")
        }

        return try JSONDecoder().decode([PlayerInfo].self, from: data)
    }

    /// Fetch details for a specific player
    func fetchPlayerDetails(playerId: String) async throws -> PlayerInfo {
        let url = URL(string: "\(baseURL)/api/players/\(playerId)")!
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError("No response")
        }

        if httpResponse.statusCode == 404 {
            throw APIError.notFound("Player not found: \(playerId)")
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError("Failed to fetch player details")
        }

        return try JSONDecoder().decode(PlayerInfo.self, from: data)
    }

    // MARK: - Categories & Progression

    /// Fetch skill categories
    func fetchCategories() async throws -> [CategoryInfo] {
        let url = URL(string: "\(baseURL)/api/categories")!
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError("Failed to fetch categories")
        }

        return try JSONDecoder().decode([CategoryInfo].self, from: data)
    }

    /// Fetch skill progression by difficulty
    func fetchProgression() async throws -> ProgressionInfo {
        let url = URL(string: "\(baseURL)/api/progression")!
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError("Failed to fetch progression")
        }

        return try JSONDecoder().decode(ProgressionInfo.self, from: data)
    }

    // MARK: - Video Analysis

    /// Analyze a user's video using the quick analysis endpoint (pre-stored reference)
    /// - Parameters:
    ///   - skill: The skill ID to analyze (e.g., "cruyff_turn")
    ///   - videoURL: Local URL to the user's video file
    ///   - progressHandler: Optional callback for upload progress (0.0 to 1.0)
    /// - Returns: Analysis response from the server
    func analyzeVideo(
        skill: String,
        videoURL: URL,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> AnalysisAPIResponse {
        let url = URL(string: "\(baseURL)/api/analyze/quick")!

        // Create multipart form data
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build body
        var body = Data()

        // Add skill field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"skill\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(skill)\r\n".data(using: .utf8)!)

        // Add video file
        let videoData = try Data(contentsOf: videoURL)
        let filename = videoURL.lastPathComponent
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"user_video\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(videoData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // Perform request
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError("No response")
        }

        // Handle error responses
        if httpResponse.statusCode == 400 {
            let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw APIError.badRequest(errorResponse?.detail ?? "Invalid request")
        }

        if httpResponse.statusCode == 404 {
            throw APIError.notFound("No reference video available for this skill")
        }

        if httpResponse.statusCode >= 500 {
            let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw APIError.serverError(errorResponse?.detail ?? "Server error")
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError("Unexpected status code: \(httpResponse.statusCode)")
        }

        return try JSONDecoder().decode(AnalysisAPIResponse.self, from: data)
    }

    /// Analyze with custom reference video
    func analyzeWithReference(
        skill: String,
        referenceVideoURL: URL,
        userVideoURL: URL
    ) async throws -> AnalysisAPIResponse {
        let url = URL(string: "\(baseURL)/api/analyze")!

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add skill field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"skill\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(skill)\r\n".data(using: .utf8)!)

        // Add reference video
        let refData = try Data(contentsOf: referenceVideoURL)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"reference_video\"; filename=\"reference.mp4\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(refData)
        body.append("\r\n".data(using: .utf8)!)

        // Add user video
        let userData = try Data(contentsOf: userVideoURL)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"user_video\"; filename=\"user.mp4\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(userData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.serverError("Analysis failed")
        }

        return try JSONDecoder().decode(AnalysisAPIResponse.self, from: data)
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
