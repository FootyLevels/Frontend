import Foundation

// MARK: - Skill Models

/// Basic skill information from /api/skills
struct SkillInfo: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let difficulty: String
    let playerId: String?
    let playerName: String?
    let videoUrl: String?
    let thumbnailUrl: String?
    let originStory: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, difficulty
        case playerId = "player_id"
        case playerName = "player_name"
        case videoUrl = "video_url"
        case thumbnailUrl = "thumbnail_url"
        case originStory = "origin_story"
    }

    var difficultyColor: String {
        switch difficulty.lowercased() {
        case "beginner": return "2ECC71" // Green
        case "intermediate": return "F1C40F" // Yellow
        case "advanced": return "E74C3C" // Red
        default: return "2C3E50"
        }
    }

    var difficultyIcon: String {
        switch difficulty.lowercased() {
        case "beginner": return "1.circle.fill"
        case "intermediate": return "2.circle.fill"
        case "advanced": return "3.circle.fill"
        default: return "circle.fill"
        }
    }
}

/// Player information from /api/players
struct PlayerInfo: Codable, Identifiable {
    let id: String
    let name: String
    let nickname: String
    let nationality: String
    let era: String
    let category: String
    let imageUrl: String
    let bio: String
    let skills: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, nickname, nationality, era, category, bio, skills
        case imageUrl = "image_url"
    }

    var isLegend: Bool {
        category == "legend"
    }

    var categoryDisplayName: String {
        isLegend ? "Legend" : "Current Star"
    }

    var flagEmoji: String {
        switch nationality.lowercased() {
        case "netherlands": return "🇳🇱"
        case "brazil": return "🇧🇷"
        case "argentina": return "🇦🇷"
        case "france": return "🇫🇷"
        case "portugal": return "🇵🇹"
        default: return "⚽"
        }
    }
}

/// Category information from /api/categories
struct CategoryInfo: Codable, Identifiable {
    let id: String
    let name: String
    let skills: [String]

    var icon: String {
        switch id {
        case "turns": return "arrow.triangle.2.circlepath"
        case "feints": return "figure.walk.motion"
        case "flicks": return "arrow.up.right"
        case "cuts": return "scissors"
        default: return "sportscourt"
        }
    }
}

/// Progression information from /api/progression
struct ProgressionInfo: Codable {
    let beginner: [String]
    let intermediate: [String]
    let advanced: [String]
}

/// Detailed skill information from /api/skills/{skill_id}
struct SkillDetails: Codable {
    let id: String
    let name: String
    let description: String
    let difficulty: String
    let playerId: String?
    let player: PlayerDetailInfo?
    let videoUrl: String?
    let thumbnailUrl: String?
    let originStory: String?
    let phases: [SkillPhase]?
    let checkpoints: [SkillCheckpoint]

    enum CodingKeys: String, CodingKey {
        case id, name, description, difficulty, player, phases, checkpoints
        case playerId = "player_id"
        case videoUrl = "video_url"
        case thumbnailUrl = "thumbnail_url"
        case originStory = "origin_story"
    }
}

/// Player detail info embedded in skill details
struct PlayerDetailInfo: Codable {
    let id: String?
    let name: String?
    let nickname: String?
    let nationality: String?
    let era: String?
    let category: String?
    let imageUrl: String?
    let bio: String?

    enum CodingKeys: String, CodingKey {
        case id, name, nickname, nationality, era, category, bio
        case imageUrl = "image_url"
    }
}

struct SkillPhase: Codable {
    let name: String
    let description: String?
}

struct SkillCheckpoint: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
}

// MARK: - Analysis Response Models

/// Main response from /api/analyze and /api/analyze/quick
struct AnalysisAPIResponse: Codable {
    let success: Bool
    let analysis: AnalysisResultRaw?
    let feedback: FeedbackResultRaw?
    let error: String?
}

/// Raw analysis result from backend (matches analyzer.py to_dict)
struct AnalysisResultRaw: Codable {
    let skillName: String?
    let overallScore: Double?
    let similarityScore: Double?
    let checkpoints: [CheckpointResult]?
    let strengths: [String]?  // Backend returns plain strings here
    let improvements: [String]?  // Backend returns plain strings here
    let metadata: AnalysisMetadata?

    enum CodingKeys: String, CodingKey {
        case skillName = "skill_name"
        case overallScore = "overall_score"
        case similarityScore = "similarity_score"
        case checkpoints
        case strengths
        case improvements
        case metadata
    }
}

struct CheckpointResult: Codable, Identifiable {
    let id: String
    let name: String
    let score: Double?
    let rating: String?
    let feedback: String?
    let value: Double?
    let ideal: Double?
}

struct AnalysisMetadata: Codable {
    let refFrames: Int?
    let userFrames: Int?
    let alignmentDistance: Double?

    enum CodingKeys: String, CodingKey {
        case refFrames = "ref_frames"
        case userFrames = "user_frames"
        case alignmentDistance = "alignment_distance"
    }
}

/// Raw feedback result from backend (matches feedback.py to_dict)
struct FeedbackResultRaw: Codable {
    let skillName: String?
    let overallRating: String?
    let overallScore: Double?
    let summary: String?
    let strengths: [FeedbackItemRaw]?
    let improvements: [FeedbackItemRaw]?
    let tips: [FeedbackItemRaw]?
    let encouragement: String?

    enum CodingKeys: String, CodingKey {
        case skillName = "skill_name"
        case overallRating = "overall_rating"
        case overallScore = "overall_score"
        case summary
        case strengths
        case improvements
        case tips
        case encouragement
    }
}

/// Individual feedback item from backend (uses 'detail' not 'message')
struct FeedbackItemRaw: Codable, Identifiable {
    var id: String { title ?? UUID().uuidString }

    let title: String?
    let detail: String?  // Backend uses 'detail' not 'message'
    let priority: Int?
    let currentValue: Double?
    let targetValue: Double?

    enum CodingKeys: String, CodingKey {
        case title
        case detail
        case priority
        case currentValue = "current_value"
        case targetValue = "target_value"
    }
}

// MARK: - View Models

/// ViewModel to pass analysis data between views
class AnalysisViewModel: ObservableObject {
    @Published var analysisResult: AnalysisResultRaw?
    @Published var feedbackResult: FeedbackResultRaw?
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var selectedSkill: SkillInfo?

    /// Computed property to get overall score (prefer feedback, fallback to analysis)
    var overallScore: Double {
        // Feedback score is 0-100, analysis score might be 0-10
        if let score = feedbackResult?.overallScore {
            return score / 10.0  // Convert to 0-10 scale for display
        }
        return analysisResult?.overallScore ?? 0
    }

    var overallRating: String {
        feedbackResult?.overallRating?.capitalized ?? "N/A"
    }

    var summary: String {
        feedbackResult?.summary ?? ""
    }

    /// Get strengths from feedback (structured) or analysis (plain strings)
    var strengths: [DisplayFeedbackItem] {
        if let feedbackStrengths = feedbackResult?.strengths {
            return feedbackStrengths.map { DisplayFeedbackItem(title: $0.title ?? "Strength", message: $0.detail ?? "") }
        }
        if let analysisStrengths = analysisResult?.strengths {
            return analysisStrengths.map { DisplayFeedbackItem(title: "Strength", message: $0) }
        }
        return []
    }

    /// Get improvements from feedback (structured) or analysis (plain strings)
    var improvements: [DisplayFeedbackItem] {
        if let feedbackImprovements = feedbackResult?.improvements {
            return feedbackImprovements.map { DisplayFeedbackItem(title: $0.title ?? "Improvement", message: $0.detail ?? "") }
        }
        if let analysisImprovements = analysisResult?.improvements {
            return analysisImprovements.map { DisplayFeedbackItem(title: "Improvement", message: $0) }
        }
        return []
    }

    var tips: [DisplayFeedbackItem] {
        guard let feedbackTips = feedbackResult?.tips else { return [] }
        return feedbackTips.map { DisplayFeedbackItem(title: $0.title ?? "Tip", message: $0.detail ?? "") }
    }

    var encouragement: String {
        feedbackResult?.encouragement ?? "Keep practicing!"
    }

    /// Score as percentage string
    var scorePercentage: String {
        "\(Int(overallScore * 10))%"
    }

    /// Color based on score (0-10 scale)
    var scoreColor: String {
        if overallScore >= 8.5 { return "2ECC71" } // Green - excellent
        if overallScore >= 7.0 { return "F1C40F" } // Yellow - good
        if overallScore >= 5.0 { return "F39C12" } // Orange - needs work
        return "E74C3C" // Red - beginner
    }

    func reset() {
        analysisResult = nil
        feedbackResult = nil
        isLoading = false
        error = nil
    }
}

/// Simplified feedback item for display
struct DisplayFeedbackItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - Sample Data for Previews

extension AnalysisViewModel {
    static var sample: AnalysisViewModel {
        let vm = AnalysisViewModel()
        vm.feedbackResult = FeedbackResultRaw(
            skillName: "Cruyff Turn",
            overallRating: "good",
            overallScore: 75.0,
            summary: "Your Cruyff Turn shows good fundamentals with room for improvement in hip rotation.",
            strengths: [
                FeedbackItemRaw(title: "Plant Foot", detail: "Excellent positioning close to the ball", priority: 1, currentValue: nil, targetValue: nil),
                FeedbackItemRaw(title: "Balance", detail: "Good stability throughout the move", priority: 2, currentValue: nil, targetValue: nil)
            ],
            improvements: [
                FeedbackItemRaw(title: "Hip Rotation", detail: "Try to rotate your hips more fully - aim for 180 degrees", priority: 1, currentValue: 120, targetValue: 180),
                FeedbackItemRaw(title: "Speed", detail: "Increase acceleration after completing the turn", priority: 2, currentValue: nil, targetValue: nil)
            ],
            tips: [
                FeedbackItemRaw(title: "Practice Tip", detail: "Practice the motion slowly first, then build up speed", priority: 1, currentValue: nil, targetValue: nil),
                FeedbackItemRaw(title: "Pro Tip", detail: "Focus on selling the fake with your shoulder movement", priority: 2, currentValue: nil, targetValue: nil)
            ],
            encouragement: "Great job! You're on the right track. A few tweaks and you'll master this!"
        )
        return vm
    }
}

extension SkillInfo {
    static var samples: [SkillInfo] {
        [
            SkillInfo(id: "cruyff_turn", name: "Cruyff Turn", description: "Drag the ball behind your standing leg while turning 180°", difficulty: "intermediate", playerId: "cruyff", playerName: "Johan Cruyff", videoUrl: nil, thumbnailUrl: nil, originStory: "Johan Cruyff first performed this move against Sweden at the 1974 World Cup"),
            SkillInfo(id: "elastico", name: "Elastico", description: "Quick inside-outside touch to change direction", difficulty: "advanced", playerId: "ronaldinho", playerName: "Ronaldinho", videoUrl: nil, thumbnailUrl: nil, originStory: "Made famous by Ronaldinho"),
            SkillInfo(id: "step_over", name: "Step Over", description: "Circular foot motion over the ball", difficulty: "beginner", playerId: "ronaldo", playerName: "Cristiano Ronaldo", videoUrl: nil, thumbnailUrl: nil, originStory: "CR7 made the step over his signature move")
        ]
    }
}

extension PlayerInfo {
    static var samples: [PlayerInfo] {
        [
            PlayerInfo(id: "cruyff", name: "Johan Cruyff", nickname: "The Dutch Master", nationality: "Netherlands", era: "1970s", category: "legend", imageUrl: "players/cruyff.jpg", bio: "Revolutionary Dutch player who invented the Cruyff Turn at the 1974 World Cup", skills: ["cruyff_turn"]),
            PlayerInfo(id: "ronaldinho", name: "Ronaldinho", nickname: "The Magician", nationality: "Brazil", era: "2000s", category: "legend", imageUrl: "players/ronaldinho.jpg", bio: "Brazilian genius known for his incredible flair", skills: ["elastico", "sombrero"]),
            PlayerInfo(id: "messi", name: "Lionel Messi", nickname: "La Pulga", nationality: "Argentina", era: "2000s-present", category: "current", imageUrl: "players/messi.jpg", bio: "The greatest of all time", skills: ["la_croqueta"])
        ]
    }
}
