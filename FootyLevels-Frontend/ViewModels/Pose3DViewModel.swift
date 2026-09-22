import Foundation
import RealityKit
import UIKit

/// Drives the single-image 3D reconstruction flow: upload a frame, fetch the
/// resulting body mesh and joint positions, and turn both into RealityKit entities.
@MainActor
final class Pose3DViewModel: ObservableObject {

    enum Stage: Equatable {
        case idle
        case uploading
        case fetching
        case ready
        case failed(String)
    }

    @Published var stage: Stage = .idle
    @Published var reconstruction: ReconstructionResponse?
    @Published var keypoints: KeypointsResponse?

    /// The body surface loaded from the server's USDZ.
    @Published var bodyEntity: Entity?
    /// Procedural joint/bone geometry built from `keypoints`.
    @Published var skeletonEntity: Entity?

    @Published var showBody = true
    @Published var showSkeleton = true

    /// Axis flips applied to the camera-space keypoints. Exposed so the
    /// convention can be confirmed visually instead of guessed at.
    @Published var orientation = SkeletonMeshBuilder.Orientation() {
        didSet {
            guard oldValue != orientation, keypoints != nil else { return }
            rebuildSkeleton()
        }
    }

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

        do {
            let result = try await APIClient.shared.reconstruct(imageData: imageData)
            reconstruction = result

            guard result.peopleDetected > 0 else {
                stage = .failed("No person detected in that image.")
                return
            }

            stage = .fetching

            // Keypoints are small (~7KB) and the mesh is ~500KB, so fetch both
            // at once rather than serially.
            async let keypointsTask = APIClient.shared.fetchKeypoints(path: result.keypointsPath)
            async let modelTask = APIClient.shared.downloadModel(path: result.modelPath)
            let (fetchedKeypoints, modelURL) = try await (keypointsTask, modelTask)

            keypoints = fetchedKeypoints
            bodyEntity = try await loadBody(from: modelURL)
            rebuildSkeleton()

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
    }

    // MARK: - Entity construction

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

    /// Rebuilds the procedural skeleton from the current keypoints and orientation.
    private func rebuildSkeleton() {
        guard let keypoints else { return }

        var builder = SkeletonMeshBuilder()
        builder.orientation = orientation

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
