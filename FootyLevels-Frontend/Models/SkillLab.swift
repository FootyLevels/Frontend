import Foundation

// Wire types for the Skill Lab backend (`3d-model-backend`). Field names match
// the JSON exactly — the backend writes camelCase — so no CodingKeys are
// needed. Unknown keys (meshInfo, shots, failures…) are ignored by Decodable.

// MARK: - Health

/// `GET /api/health`
struct SkillLabHealth: Decodable {
    let status: String
    let providers: [ProviderCapability]
    let motion: Capability
    /// Absent on servers older than the network-policy change.
    let network: NetworkPolicy?

    var readyProviders: [ProviderCapability] { providers.filter(\.ready) }
}

/// `backend/network.py`'s `describe()`: who the server accepts, and the
/// addresses other devices can use to reach it.
struct NetworkPolicy: Decodable {
    /// `local` (loopback only) | `lan` (private network) | `open` (no checks)
    let mode: String
    /// `http://<address>:<port>` for each non-loopback interface. Empty in
    /// `local` mode, because no other device could use them.
    let urls: [String]

    var acceptsOtherDevices: Bool { mode != "local" }
}

/// One key-frame inference backend (`local` CUDA or `fal` hosted).
struct ProviderCapability: Decodable, Identifiable, Hashable {
    let id: String
    let label: String
    let ready: Bool
    let reason: String?
    let remote: Bool
}

struct Capability: Decodable {
    let ready: Bool
    let reason: String?
}

// MARK: - Project

/// `GET /api/projects/{id}` — the single document the whole UI renders from.
struct SkillLabProject: Decodable, Identifiable {
    let id: String
    let title: String
    let createdAt: String
    let video: ProjectVideo
    var frames: [KeyFrame]
    let job: ReconstructionJob?
    let motion: MotionState?

    /// While either job runs the backend returns 409 for any frame edit, so
    /// the UI locks editing rather than letting requests fail.
    var isBusy: Bool {
        (job?.isActive ?? false) || (motion?.isActive ?? false)
    }

    var createdDate: Date? {
        ISO8601DateFormatter.fractional.date(from: createdAt)
            ?? ISO8601DateFormatter().date(from: createdAt)
    }
}

struct ProjectVideo: Decodable {
    let width: Int
    let height: Int
    let fps: Double
    let duration: Double
    let frameCount: Int
    let url: String

    var aspectRatio: Double { height > 0 ? Double(width) / Double(height) : 16 / 9 }
}

struct KeyFrame: Decodable, Identifiable {
    let id: String
    let timestamp: Double
    let frameIndex: Int
    let label: String
    let note: String?
    let imageUrl: String
    /// Normalised `[left, top, right, bottom]` subject box.
    let bbox: [Double]
    /// `pending` | `queued` | `running` | `ready` | `failed`
    let status: String
    let meshUrl: String?
    let error: String?
    let provider: String?

    var isReady: Bool { status == "ready" && meshUrl != nil }
    var isActive: Bool { status == "queued" || status == "running" }
}

/// The key-frame mesh job. Every field except `status` is optional because the
/// backend writes partial job objects during restart recovery.
struct ReconstructionJob: Decodable {
    let id: String?
    /// `queued` | `running` | `complete` | `partial` | `failed` | `interrupted`
    let status: String
    let provider: String?
    let completed: Int?
    let failed: Int?
    let total: Int?

    var isActive: Bool { status == "queued" || status == "running" }
}

/// The whole-video motion job.
struct MotionState: Decodable {
    /// `queued` | `running` | `complete` | `partial` | `failed` | `interrupted`
    let status: String
    let stage: String?
    let error: String?
    let sequenceUrl: String?
    let bodyFrames: Int?
    let ballFrames: Int?
    let fps: Double?
    let ballReady: Bool?
    let groundAligned: Bool?

    var isActive: Bool { status == "queued" || status == "running" }
    /// `partial` still has a playable sequence — only some frames failed.
    var isPlayable: Bool { sequenceUrl != nil && !isActive }
}

// MARK: - Motion sequence

/// `motion/sequence.json`, written by `scripts/reconstruct_motion.py`.
///
/// Vertices are not in here. They live in gzip'd chunks of 30 frames, each a
/// flat little-endian `uint16` array of `count × vertexCount × 3`, quantised
/// against the global `min` / `span` bounds. Topology is a separate `uint32`
/// file shared by every frame.
struct MotionSequence: Decodable {
    let vertexCount: Int
    let faceCount: Int
    let frameCount: Int
    let min: [Float]
    let span: [Float]
    let topologyFile: String
    /// Expected to be `uint16-le-xyz-gzip`; anything else is rejected.
    let encoding: String
    let chunks: [Chunk]
    let revision: String?
    let fps: Double
    let duration: Double
    let validBodyFrames: Int
    let validBallFrames: Int
    let ball: Ball
    let frames: [Frame]
    let ground: Ground?

    struct Chunk: Decodable {
        let start: Int
        let count: Int
        let file: String
        let bytes: Int
    }

    struct Ball: Decodable {
        /// `ball.glb` once SAM 3D Objects has run, otherwise nil.
        let file: String?
        let diameter: Double
    }

    struct Frame: Decodable {
        let index: Int
        let time: Double
        let shot: Int
        /// False where SAM 3D Body failed or found no person — the chunk still
        /// holds placeholder data there, which must not be shown as a pose.
        let valid: Bool
        /// Ball centre in the same space as the body, or nil if untracked.
        let ball: [Float]?
    }

    /// Present only after the reviewed contact-alignment pass.
    struct Ground: Decodable {
        let method: String?
        /// One per sequence frame.
        let frames: [GroundFrame]?
    }

    struct GroundFrame: Decodable {
        /// `reviewed-ground` (ball on the pitch) | `nonpenetration` | `unconstrained`
        let ballConstraint: String?
    }

    /// The web viewer's per-frame contact note, or nil without alignment.
    func contactLabel(frame: Int) -> String? {
        guard let ground else { return nil }
        let constraint = ground.frames?.indices.contains(frame) == true ? ground.frames?[frame].ballConstraint : nil
        return constraint == "reviewed-ground" ? "Ball on pitch" : "Ball depth estimated"
    }

    var lowerBound: SIMD3<Float> { SIMD3(min[0], min[1], min[2]) }
    var extent: SIMD3<Float> { SIMD3(span[0], span[1], span[2]) }
    var upperBound: SIMD3<Float> { lowerBound + extent }
}

// MARK: - Helpers

extension ISO8601DateFormatter {
    /// Python's `isoformat()` includes microseconds, which the default
    /// formatter rejects.
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
