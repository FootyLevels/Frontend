import Foundation
import Observation
import RealityKit

/// The "Pose inspector": one key frame's SAM 3D Body mesh, standing on a grid.
///
/// Meshes are cached by URL, so stepping back and forth through the key-frame
/// strip only parses each GLB once.
@MainActor
@Observable
final class PoseInspectorModel {
    var stageRoot: Entity?
    var isLoading = false
    var errorMessage: String?
    var angle: CameraAngle = .source
    var wireframe = false { didSet { applyMaterial() } }
    var autoRotate = false { didSet { camera.autoRotate = autoRotate } }
    /// e.g. "18,439 vertices · 1.60 m"
    var info: String?
    var missingPose = false

    @ObservationIgnored let camera = OrbitCamera()
    @ObservationIgnored private var cache: [String: TriangleMesh] = [:]
    @ObservationIgnored private var body: Entity?
    @ObservationIgnored private var loadedPath: String?
    @ObservationIgnored private var selectionGeneration = UUID()

    func showPrivate(frameIndex: Int, source: PrivateKeyframeAssetSource) async {
        clear()
        let generation = selectionGeneration
        isLoading = true
        defer { if selectionGeneration == generation { isLoading = false } }
        do {
            guard let mesh = try await source.mesh(frameIndex: frameIndex) else {
                guard generation == selectionGeneration else { return }
                missingPose = true; return
            }
            try source.checkSession(); guard generation == selectionGeneration else { return }
            let stage = try await makeStage(mesh)
            try source.checkSession(); guard generation == selectionGeneration else { return }
            present(stage,mesh: mesh)
        } catch {
            guard generation == selectionGeneration else { return }
            body = nil; stageRoot = nil; info = nil
            errorMessage = (error as? CloudPlaybackError)?.errorDescription ?? "The selected pose couldn't be loaded. Please reload playback."
        }
    }

    func clear() {
        selectionGeneration = UUID(); loadedPath = nil; cache.removeAll()
        body = nil; stageRoot = nil; info = nil; missingPose = false; isLoading = false; errorMessage = nil
    }

    /// Shows `meshPath`, or clears the stage when the frame has no mesh yet.
    func show(meshPath: String?) async {
        guard meshPath != loadedPath else { return }
        loadedPath = meshPath
        errorMessage = nil
        guard let meshPath else {
            stageRoot = nil
            info = nil
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let mesh: TriangleMesh
            if let cached = cache[meshPath] {
                mesh = cached
            } else {
                let data = try await SkillLabClient.shared.data(path: meshPath)
                // Parsing ~18k vertices is cheap but not free; keep it off the main actor.
                mesh = try await Task.detached { try GLBLoader.load(data) }.value
                cache[meshPath] = mesh
            }
            // A newer selection may have started while this one loaded.
            guard loadedPath == meshPath else { return }

            let stage = try await makeStage(mesh)
            guard loadedPath == meshPath else { return }
            present(stage,mesh: mesh)
        } catch {
            errorMessage = "The mesh could not be loaded. Retry reconstruction or check the saved file."
        }
    }

    private func makeStage(_ mesh: TriangleMesh) async throws -> (root: Entity, body: Entity) {
        let bounds = mesh.bounds, height = Swift.max(bounds.extents.y, 0.5)
        let entity = Entity(); entity.name = "body"
        entity.components.set(ModelComponent(mesh: try mesh.makeResource(name: "key-frame"), materials: [material]))
        entity.components.set(GroundingShadowComponent(castsShadow: true))
        entity.position = -SIMD3(bounds.center.x, bounds.min.y, bounds.center.z)
        let stage = await StageBuilder.makeStage(content: [entity], floorCenter: .zero, floorSize: 10)
        return (stage.root,entity)
    }

    private func present(_ stage: (root: Entity, body: Entity), mesh: TriangleMesh) {
        let bounds = mesh.bounds, height = Swift.max(bounds.extents.y,0.5)
        body = stage.body; stageRoot = stage.root
        camera.target = SIMD3(0, height * 0.49, 0); camera.homeDistance = height * 2.15
        camera.distanceRange = (height * 0.5)...(height * 6); camera.show(angle)
        info = "\(mesh.positions.count.formatted()) vertices · estimated height \(String(format: "%.2f", bounds.extents.y)) m"
    }

    /// Forces a reload, e.g. after the frame's box changed and it was rebuilt.
    func invalidate() {
        loadedPath = nil
    }

    func show(_ angle: CameraAngle) {
        self.angle = angle
        camera.show(angle)
    }

    private var material: SimpleMaterial {
        var material = StageBuilder.bodyMaterial
        material.triangleFillMode = wireframe ? .lines : .fill
        return material
    }

    private func applyMaterial() {
        body?.components[ModelComponent.self]?.materials = [material]
    }
}
