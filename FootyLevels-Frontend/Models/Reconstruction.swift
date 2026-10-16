import Foundation

// MARK: - Reconstruction Response

/// Response from `POST /api/reconstruct` and `GET /api/reconstruct/{id}`.
///
/// Both endpoints return this identical shape, so a result can be re-fetched by
/// `id` without re-uploading the source image.
struct ReconstructionResponse: Codable, Identifiable {
    let id: String
    /// ISO-8601 with fractional seconds. Kept as a `String` because
    /// `JSONDecoder.DateDecodingStrategy.iso8601` rejects fractional seconds.
    let createdAt: String
    let sourceImage: String?
    let image: ImageDimensions
    let peopleDetected: Int
    let model: ReconstructedModelInfo
    let subject: ReconstructedSubject
    let hasPreview: Bool
    let modelPath: String
    let keypointsPath: String
    let previewPath: String?
    /// Present only when the request was made with `raw=true`.
    let raw: RawGeometryInfo?

    enum CodingKeys: String, CodingKey {
        case id, image, model, subject, raw
        case createdAt = "created_at"
        case sourceImage = "source_image"
        case peopleDetected = "people_detected"
        case hasPreview = "has_preview"
        case modelPath = "model_url"
        case keypointsPath = "keypoints_url"
        case previewPath = "preview_url"
    }
}

struct ImageDimensions: Codable {
    let width: Int
    let height: Int
}

struct ReconstructedModelInfo: Codable {
    let format: String
    let filename: String
    let bytes: Int
    let vertices: Int
    let faces: Int
    let upAxis: String
    let units: String

    enum CodingKeys: String, CodingKey {
        case format, filename, bytes, vertices, faces, units
        case upAxis = "up_axis"
    }

    var isUSDZ: Bool { format.lowercased() == "usdz" }
}

struct ReconstructedSubject: Codable {
    let numJoints: Int
    /// `[x, y, width, height]` in source-image pixels.
    let bbox: [Double]
    let focalLength: Double
    /// Camera translation, metres.
    let camT: [Double]

    enum CodingKeys: String, CodingKey {
        case bbox
        case numJoints = "num_joints"
        case focalLength = "focal_length"
        case camT = "cam_t"
    }
}

// MARK: - Raw Geometry

/// Descriptor for the binary vertex buffers served when `raw=true`.
struct RawGeometryInfo: Codable {
    let vertexCount: Int
    let positions: RawBufferInfo
    let normals: RawBufferInfo?
    let positionsPath: String
    let normalsPath: String?
    /// Shared topology endpoint — not scoped to this reconstruction, because the
    /// triangle list is identical for every body the model produces. Fetch once
    /// and cache; re-downloading it per request is pure waste.
    let indicesPath: String

    enum CodingKeys: String, CodingKey {
        case positions, normals
        case vertexCount = "vertex_count"
        case positionsPath = "positions_url"
        case normalsPath = "normals_url"
        case indicesPath = "indices_url"
    }
}

struct RawBufferInfo: Codable {
    let bytes: Int
    let dtype: String
    let components: Int
    let layout: String?
}

// MARK: - Keypoints

/// Response from the reconstruction's `keypoints_url`.
struct KeypointsResponse: Codable {
    let numJoints: Int
    let units: String
    /// Reference frame of `keypoints3D` — currently always `"camera"`.
    let space: String
    /// 3D joint positions in `space`, metres.
    let keypoints3D: [[Float]]
    /// 2D joint projections in source-image pixels.
    let keypoints2D: [[Float]]?
    /// Parent joint index per joint, `-1` for a root.
    ///
    /// Not currently sent by the API, so bones can't be drawn yet — only joints.
    /// Add a `parents` array to the keypoints payload and bones render
    /// automatically, no client change needed.
    let parents: [Int]?

    enum CodingKeys: String, CodingKey {
        case units, space, parents
        case numJoints = "num_joints"
        case keypoints3D = "keypoints_3d"
        case keypoints2D = "keypoints_2d"
    }

    /// `keypoints3D` as vectors, skipping any row that isn't a full triple.
    var joints: [SIMD3<Float>] {
        keypoints3D.compactMap { row in
            guard row.count >= 3 else { return nil }
            return SIMD3<Float>(row[0], row[1], row[2])
        }
    }

    /// `(parent, child)` index pairs. Empty when the API supplies no hierarchy.
    var boneIndices: [(Int, Int)] {
        guard let parents else { return [] }
        return parents.enumerated().compactMap { child, parent in
            guard parent >= 0, parent < parents.count, parent != child else { return nil }
            return (parent, child)
        }
    }
}
