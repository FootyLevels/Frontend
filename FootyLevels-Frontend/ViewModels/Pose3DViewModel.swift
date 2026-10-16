import Foundation
import RealityKit
import UIKit

/// Drives the single-image 3D reconstruction flow: upload a frame, fetch the
/// resulting body geometry and joint positions, and turn both into RealityKit
/// entities.
@MainActor
final class Pose3DViewModel: ObservableObject {

    enum Stage: Equatable {
        case idle
        case uploading
        case fetching
        case ready
        case failed(String)
    }

    /// Which path produced `bodyEntity`, for display and debugging.
    enum BodySource: String {
        case rawBuffers = "raw buffers"
        case usdz = "USDZ"
    }

    @Published var stage: Stage = .idle
    @Published var reconstruction: ReconstructionResponse?
    @Published var keypoints: KeypointsResponse?

    /// The body surface, built from raw buffers or loaded from the USDZ.
    @Published var bodyEntity: Entity?
    /// Procedural joint/bone geometry built from `keypoints`.
    @Published var skeletonEntity: Entity?
    /// Grid platform placed under the model so it doesn't read as floating.
    @Published var groundEntity: Entity?
    @Published var bodySource: BodySource?

    @Published var showBody = true
    @Published var showSkeleton = true
    @Published var showGround = true

    /// Axis flips for the body mesh.
    ///
    /// Identity by default: the request sends `y_up=true`, so the server has
    /// already converted the vertices out of the camera frame.
    @Published var bodyOrientation = PoseOrientation.identity {
        didSet {
            guard oldValue != bodyOrientation else { return }
            rebuildRawBody()
            // Flipping an axis moves the model's lowest point, so the grid has
            // to drop to the new one.
            positionGround()
        }
    }

    /// Axis flips for the joint skeleton.
    ///
    /// Flipped by default: the keypoints payload reports `space: "camera"`, so
    /// unlike the mesh it still needs converting. Kept separate from
    /// `bodyOrientation` because the two arrive in different frames.
    @Published var skeletonOrientation = PoseOrientation() {
        didSet {
            guard oldValue != skeletonOrientation else { return }
            rebuildSkeleton()
            positionGround()
        }
    }

    /// Retained so the body mesh can be rebuilt when the orientation changes
    /// without re-downloading ~440KB of buffers.
    private var rawBuffers: BodyMeshBuilder.Buffers?

    var isBusy: Bool { stage == .uploading || stage == .fetching }

    var errorMessage: String? {
        if case .failed(let message) = stage { return message }
        return nil
    }

    // MARK: - Flow

    /// Runs the full round trip for one image.
    func reconstruct(imageData: Data) async {
        stage = .uploading
        reconstruction = nil
        keypoints = nil
        bodyEntity = nil
        skeletonEntity = nil
        bodySource = nil
        rawBuffers = nil

        do {
            let result = try await APIClient.shared.reconstruct(imageData: imageData, raw: true)
            reconstruction = result

            guard result.peopleDetected > 0 else {
                stage = .failed("No person detected in that image.")
                return
            }

            stage = .fetching

            let fetchedKeypoints: KeypointsResponse

            if let raw = result.raw {
                // Four independent downloads — keypoints (~13KB), positions and
                // normals (~216KB each) and the topology (~432KB, usually
                // already cached). Run them concurrently rather than serially.
                async let keypointsTask = APIClient.shared.fetchKeypoints(path: result.keypointsPath)
                async let positionsTask = APIClient.shared.fetchBinary(path: raw.positionsPath)
                async let indicesTask = APIClient.shared.fetchTopology(path: raw.indicesPath)
                async let normalsTask: Data? = {
                    guard let path = raw.normalsPath else { return nil }
                    return try await APIClient.shared.fetchBinary(path: path)
                }()

                let (keypointsResult, positions, topology, normals) =
                    try await (keypointsTask, positionsTask, indicesTask, normalsTask)

                fetchedKeypoints = keypointsResult
                rawBuffers = BodyMeshBuilder.Buffers(
                    positions: positions,
                    normals: normals,
                    indices: topology.data,
                    vertexCount: raw.vertexCount,
                    // The topology endpoint's own header wins; `model.faces`
                    // describes the USDZ and is only a fallback.
                    faceCount: topology.triangleCount ?? result.model.faces
                )
            } else {
                // Server didn't honour `raw=true` — fall back to the USDZ so the
                // view still shows something.
                async let keypointsTask = APIClient.shared.fetchKeypoints(path: result.keypointsPath)
                async let modelTask = APIClient.shared.downloadModel(path: result.modelPath)
                let (keypointsResult, modelURL) = try await (keypointsTask, modelTask)

                fetchedKeypoints = keypointsResult
                bodyEntity = try await loadBody(from: modelURL)
                bodySource = .usdz
            }

            keypoints = fetchedKeypoints
            rebuildSkeleton()
            if rawBuffers != nil {
                rebuildRawBody()
            }
            await prepareGround()

            stage = .ready
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    func reset() {
        stage = .idle
        reconstruction = nil
        keypoints = nil
        bodyEntity = nil
        skeletonEntity = nil
        bodySource = nil
        rawBuffers = nil
        // groundEntity is deliberately kept — its mesh and texture are
        // reconstruction-independent, and it isn't rendered while idle anyway.
    }

    // MARK: - Entity construction

    /// Rebuilds the body mesh from the retained raw buffers.
    ///
    /// Called on every orientation change, so no network traffic is involved —
    /// the buffers are already in memory.
    private func rebuildRawBody() {
        guard let rawBuffers else { return }

        var builder = BodyMeshBuilder()
        builder.orientation = bodyOrientation

        do {
            let mesh = try builder.makeMesh(from: rawBuffers)
            var material = SimpleMaterial()
            material.color = .init(tint: UIColor(red: 0.90, green: 0.92, blue: 0.95, alpha: 1))
            material.roughness = 0.6
            material.metallic = 0

            let entity = Entity()
            entity.name = "body"
            entity.components.set(ModelComponent(mesh: mesh, materials: [material]))
            bodyEntity = entity
            bodySource = .rawBuffers
        } catch {
            stage = .failed("Could not build body mesh: \(error.localizedDescription)")
            bodyEntity = nil
            bodySource = nil
        }
    }

    /// Builds the grid platform if needed, then drops it to the model's feet.
    ///
    /// The geometry and its texture never change, so this builds once and
    /// reuses the entity — only the height is updated afterwards.
    private func prepareGround() async {
        if groundEntity == nil {
            do {
                groundEntity = try await GroundGridBuilder().makeEntity()
            } catch {
                // A missing grid is cosmetic — don't fail the reconstruction.
                print("Ground grid failed: \(error.localizedDescription)")
                return
            }
        }
        positionGround()
    }

    /// Drops the grid to the lowest point of the loaded geometry.
    ///
    /// Both layers are recentred on the origin so orbit rotates about the
    /// model's middle — which means y = 0 sits around waist height. Leaving the
    /// grid there would slice through the body.
    private func positionGround() {
        groundEntity?.position = SIMD3(0, floorLevel(), 0)
    }

    /// The lowest point of whatever geometry is loaded.
    ///
    /// Falls back to half the normalised height, which is where the bottom of
    /// the bounding box lands for an upright figure.
    private func floorLevel() -> Float {
        let lowestPoints = [bodyEntity, skeletonEntity]
            .compactMap { $0 }
            .map { $0.visualBounds(relativeTo: nil).min.y }
            .filter { $0.isFinite }

        guard let lowest = lowestPoints.min(), lowest < 0 else {
            return -SkeletonMeshBuilder().targetHeight / 2
        }
        return lowest
    }

    /// Rebuilds the procedural skeleton from the current keypoints and orientation.
    private func rebuildSkeleton() {
        guard let keypoints else { return }

        var builder = SkeletonMeshBuilder()
        builder.orientation = skeletonOrientation

        let joints = builder.normalized(joints: keypoints.joints)
        guard !joints.isEmpty else {
            skeletonEntity = nil
            return
        }

        do {
            let mesh = try builder.makeMesh(joints: joints, bones: keypoints.boneIndices)
            var material = SimpleMaterial()
            material.color = .init(tint: UIColor(red: 0.18, green: 0.80, blue: 0.44, alpha: 1))
            material.roughness = 0.35
            material.metallic = 0

            let entity = Entity()
            entity.name = "skeleton"
            entity.components.set(ModelComponent(mesh: mesh, materials: [material]))
            skeletonEntity = entity
        } catch {
            stage = .failed("Could not build skeleton geometry: \(error.localizedDescription)")
            skeletonEntity = nil
        }
    }

    /// Loads the server's USDZ and normalises it to roughly match the
    /// skeleton's scale, so the two overlay sensibly.
    private func loadBody(from url: URL) async throws -> Entity {
        let loaded = try await Entity(contentsOf: url)

        let wrapper = Entity()
        wrapper.name = "body"
        wrapper.addChild(loaded)

        // The mesh arrives in metres, life-sized. Fit it to the same normalised
        // extent the skeleton uses so both sit in frame together.
        let bounds = loaded.visualBounds(relativeTo: nil)
        let extent = bounds.extents
        let largestAxis = max(extent.x, max(extent.y, extent.z))
        if largestAxis > 1e-5 {
            let scale = SkeletonMeshBuilder().targetHeight / largestAxis
            loaded.scale = .init(repeating: scale)
            loaded.position = -bounds.center * scale
        }

        return wrapper
    }

    // MARK: - Image preparation

    /// Downscales and JPEG-encodes a picked image before upload.
    ///
    /// A full-resolution phone photo is far larger than the model needs, and
    /// building the multipart body keeps the whole thing in memory.
    nonisolated static func prepareForUpload(
        _ data: Data,
        maxDimension: CGFloat = 1024,
        quality: CGFloat = 0.85
    ) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let size = image.size
        let largestSide = max(size.width, size.height)
        guard largestSide > maxDimension else {
            return image.jpegData(compressionQuality: quality) ?? data
        }

        let scale = maxDimension / largestSide
        let target = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }

        return resized.jpegData(compressionQuality: quality)
    }
}
