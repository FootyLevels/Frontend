import Foundation
import Metal
import RealityKit
import SwiftUI
import UIKit

// MARK: - Animated body

/// The body mesh for motion playback: one `LowLevelMesh` whose vertex buffer is
/// rewritten in place for each frame.
///
/// Frames arrive quantised to `uint16` and stay that way in memory. A clip at
/// 30 fps is ~110 KB per frame quantised versus ~590 KB as position + normal
/// floats, so decoding on demand keeps a 10-second clip near 33 MB instead of
/// ~180 MB.
@MainActor
final class AnimatedBodyMesh {
    private struct Vertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
    }

    /// One frame's slice of a decoded chunk.
    struct Pose {
        let values: [UInt16]
        let offset: Int
    }

    /// Triangles whose three corners are all in `vertices` are drawn with
    /// `material` instead of the body's, e.g. to colour the feet.
    struct Highlight {
        let vertices: Set<UInt32>
        let material: SimpleMaterial
    }

    let entity = Entity()
    /// Centre of the most recently written pose — what "Follow" tracks.
    private(set) var center: SIMD3<Float> = .zero

    private let mesh: LowLevelMesh
    private let indices: [UInt32]
    private let vertexCount: Int
    private let lowerBound: SIMD3<Float>
    /// `span / 65535` — multiplying a quantised value by this recovers metres.
    private let step: SIMD3<Float>
    /// The most recently written pose, in metres — what the overlay aligns.
    private(set) var positions: [SIMD3<Float>]
    private var normals: [SIMD3<Float>]
    /// The body's material first, then one per highlight.
    private var materials: [SimpleMaterial]

    init(sequence: MotionSequence, indices: [UInt32], material: SimpleMaterial,
         highlights: [Highlight] = []) throws {
        guard let highest = indices.max(), Int(highest) < sequence.vertexCount else {
            throw MeshDecodingError.indexOutOfRange
        }
        // Group triangles by material: the body, then each highlight. Normals
        // don't depend on triangle order, so the reordered list serves both.
        var groups = Array(repeating: [UInt32](), count: highlights.count + 1)
        var t = 0
        while t + 2 < indices.count {
            let a = indices[t], b = indices[t + 1], c = indices[t + 2]
            let group = highlights.firstIndex {
                $0.vertices.contains(a) && $0.vertices.contains(b) && $0.vertices.contains(c)
            }.map { $0 + 1 } ?? 0
            groups[group] += [a, b, c]
            t += 3
        }
        let indices = groups.flatMap { $0 }
        self.indices = indices
        self.vertexCount = sequence.vertexCount
        self.lowerBound = sequence.lowerBound
        self.step = sequence.extent / 65535
        self.positions = Array(repeating: .zero, count: sequence.vertexCount)
        self.normals = Array(repeating: .zero, count: sequence.vertexCount)
        self.materials = [material] + highlights.map(\.material)

        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, offset: MemoryLayout<Vertex>.offset(of: \.position)!),
            .init(semantic: .normal, format: .float3, offset: MemoryLayout<Vertex>.offset(of: \.normal)!),
        ]
        descriptor.vertexLayouts = [.init(bufferIndex: 0, bufferStride: MemoryLayout<Vertex>.stride)]
        descriptor.indexType = .uint32
        descriptor.vertexCapacity = sequence.vertexCount
        descriptor.indexCapacity = indices.count

        mesh = try LowLevelMesh(descriptor: descriptor)
        mesh.withUnsafeMutableIndices { raw in
            let destination = raw.bindMemory(to: UInt32.self)
            _ = destination.initialize(from: indices)
        }
        // The global bounds cover every frame, so they never need updating —
        // culling stays correct however the body moves.
        let bounds = BoundingBox(min: sequence.lowerBound, max: sequence.upperBound)
        var offset = 0
        var parts: [LowLevelMesh.Part] = []
        for (index, group) in groups.enumerated() where !group.isEmpty {
            parts.append(LowLevelMesh.Part(indexOffset: offset * MemoryLayout<UInt32>.stride, indexCount: group.count,
                                           topology: .triangle, materialIndex: index, bounds: bounds))
            offset += group.count
        }
        mesh.parts.replaceAll(parts)

        let resource = try MeshResource(from: mesh)
        entity.name = "body"
        entity.components.set(ModelComponent(mesh: resource, materials: materials))
        entity.components.set(GroundingShadowComponent(castsShadow: true))
        // The vertex buffer is uninitialised until the first `show`, and would
        // render as garbage. The caller enables it once a real pose is written.
        entity.isEnabled = false
    }

    /// Replaces the highlights' materials (same count and order as at init), e.g.
    /// when the foot that works the ball changes between skills or frames.
    func setHighlightMaterials(_ highlights: [SimpleMaterial]) {
        guard highlights.count == materials.count - 1 else { return }
        materials = [materials[0]] + highlights.map { material in
            var m = material
            m.triangleFillMode = wireframe ? .lines : .fill
            return m
        }
        entity.components[ModelComponent.self]?.materials = materials
    }

    var wireframe = false {
        didSet {
            for index in materials.indices {
                materials[index].triangleFillMode = wireframe ? .lines : .fill
            }
            entity.components[ModelComponent.self]?.materials = materials
        }
    }

    /// Decodes a pose, optionally blended toward the next one, and writes it
    /// with fresh normals into the GPU vertex buffer.
    ///
    /// Blending is what keeps half- and quarter-speed playback smooth: the
    /// video advances between the 30 fps samples, and the mesh follows.
    func show(_ pose: Pose, blendingTo next: Pose? = nil, amount: Float = 0) {
        let valueCount = vertexCount * 3
        guard pose.offset >= 0, pose.offset + valueCount <= pose.values.count else { return }
        let target = next.flatMap { $0.offset >= 0 && $0.offset + valueCount <= $0.values.count ? $0 : nil }
        let t = target == nil ? 0 : Swift.min(Swift.max(amount, 0), 1)

        let low = lowerBound, step = step, count = vertexCount
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

        pose.values.withUnsafeBufferPointer { a in
            (target?.values ?? pose.values).withUnsafeBufferPointer { b in
                positions.withUnsafeMutableBufferPointer { p in
                    let ao = pose.offset, bo = target?.offset ?? pose.offset
                    for i in 0..<count {
                        let ia = ao + i * 3, ib = bo + i * 3
                        var q = SIMD3(Float(a[ia]), Float(a[ia + 1]), Float(a[ia + 2]))
                        if t > 0 {
                            let r = SIMD3(Float(b[ib]), Float(b[ib + 1]), Float(b[ib + 2]))
                            q += (r - q) * t
                        }
                        let point = low + q * step
                        p[i] = point
                        lo = simd_min(lo, point)
                        hi = simd_max(hi, point)
                    }
                }
            }
        }
        center = (lo + hi) / 2

        positions.withUnsafeBufferPointer { p in
            indices.withUnsafeBufferPointer { i in
                normals.withUnsafeMutableBufferPointer { n in
                    MeshNormals.compute(positions: p, indices: i, into: n)
                }
            }
        }

        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let vertices = raw.bindMemory(to: Vertex.self)
            positions.withUnsafeBufferPointer { p in
                normals.withUnsafeBufferPointer { n in
                    for i in 0..<count {
                        vertices[i] = Vertex(position: p[i], normal: n[i])
                    }
                }
            }
        }
    }
}

// MARK: - Stage

/// Builds a scene in the backend's own space — Y-up metres with the floor at
/// y = 0 — so the grid, body and ball agree without any rescaling. The camera
/// rig does the framing instead.
enum StageBuilder {
    /// Neutral floor lines that read on the light and the dark stage.
    static let gridTint = UIColor(light: "ABABAB", dark: "3C3C3C")

    @MainActor
    static func makeStage(content: [Entity], floorCenter: SIMD3<Float>, floorSize: Float,
                          cellSize: Float = 0.25) async -> (root: Entity, ground: Entity?) {
        let root = Entity()
        root.name = "stage"
        for entity in content {
            root.addChild(entity)
        }

        var grid = GroundGridBuilder()
        grid.extent = floorSize
        grid.divisions = Swift.max(8, Int((floorSize / cellSize).rounded()))
        // Keep ~20 px per cell however large the floor is.
        grid.resolution = Swift.min(4096, Swift.max(512, grid.divisions * 20))
        grid.lineWidth = 1.6
        grid.solidRadius = 0.2
        grid.tint = gridTint

        var ground: Entity?
        if let entity = try? await grid.makeEntity() {
            entity.position = SIMD3(floorCenter.x, -0.002, floorCenter.z)
            root.addChild(entity)
            ground = entity
        }
        return (root, ground)
    }

    static var bodyMaterial: SimpleMaterial {
        var material = SimpleMaterial()
        material.color = .init(tint: SL.bodyTint)
        material.roughness = 0.75
        material.metallic = 0.04
        // SAM 3D Body meshes are not always closed; draw both sides.
        material.faceCulling = .none
        return material
    }

    static var ballMaterial: SimpleMaterial {
        var material = SimpleMaterial()
        material.color = .init(tint: .white)
        material.roughness = 0.8
        material.metallic = 0
        return material
    }

    /// Key light from above and in front, as in the web viewer.
    @MainActor
    static func makeKeyLight() -> Entity {
        let light = Entity()
        light.name = "key-light"
        light.components.set(DirectionalLightComponent(color: UIColor(red: 1, green: 0.98, blue: 0.94, alpha: 1),
                                                       intensity: 2600))
        light.components.set(DirectionalLightComponent.Shadow(maximumDistance: 12, depthBias: 1))
        light.look(at: .zero, from: SIMD3(-3, 12, 8), relativeTo: nil)
        return light
    }
}

// MARK: - Camera

/// The web viewer's preset angles. "Source" looks from where the filming
/// camera stood, down the backend's +z axis.
enum CameraAngle: String, CaseIterable, Identifiable {
    case source = "Source", left = "Left", right = "Right", back = "Back", above = "Above"

    var id: String { rawValue }

    /// (yaw, pitch) in radians, matching `setCamera` in `MotionViewer.tsx`.
    var orientation: (yaw: Float, pitch: Float) {
        let level = atan(Float(0.12))
        switch self {
        case .source: return (0, level)
        case .left: return (-.pi / 2, level)
        case .right: return (.pi / 2, level)
        case .back: return (.pi, level)
        case .above: return (0, .pi / 2 - 0.001)
        }
    }
}

/// A camera orbiting a target, driven by gestures, presets and "Follow".
///
/// RealityKit's built-in `.orbit` controls can't be positioned from code, so
/// this owns the camera entity and places it itself.
@MainActor
final class OrbitCamera {
    let entity = Entity()

    var target: SIMD3<Float> = [0, 0.9, 0] { didSet { apply() } }
    private(set) var yaw: Float = 0
    private(set) var pitch: Float = CameraAngle.source.orientation.pitch
    private(set) var distance: Float = 4.1
    var distanceRange: ClosedRange<Float> = 0.7...25
    /// Turntable spin for the key-frame pose view, in radians per second.
    var autoRotate = false

    /// Where a preset puts the camera; also what "reset" returns to.
    var homeDistance: Float = 4.1

    private var updates: EventSubscription?

    init() {
        entity.name = "orbit-camera"
        var camera = PerspectiveCameraComponent()
        camera.fieldOfViewInDegrees = 38
        camera.near = 0.01
        camera.far = 200
        entity.components.set(camera)
        apply()
    }

    func show(_ angle: CameraAngle) {
        (yaw, pitch) = angle.orientation
        distance = homeDistance
        apply()
    }

    /// Takes another camera's angle and distance but keeps this one's target,
    /// so two stages side by side view their bodies from the same direction.
    func match(_ other: OrbitCamera) {
        (yaw, pitch, distance) = (other.yaw, other.pitch, other.distance)
        apply()
    }

    /// Adds a drag, in points, to the orbit angles.
    func orbit(from start: (yaw: Float, pitch: Float), translation: CGSize) {
        yaw = start.yaw - Float(translation.width) * 0.008
        pitch = Swift.min(Swift.max(start.pitch + Float(translation.height) * 0.008, -0.15), .pi / 2 - 0.001)
        apply()
    }

    var orientation: (yaw: Float, pitch: Float) { (yaw, pitch) }

    func zoom(from start: Float, magnification: CGFloat) {
        distance = Swift.min(Swift.max(start / Float(Swift.max(magnification, 0.01)), distanceRange.lowerBound),
                             distanceRange.upperBound)
        apply()
    }

    var currentDistance: Float { distance }

    /// Ticks auto-rotation from the scene's update loop.
    func attach(to content: RealityViewCameraContent) {
        updates = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.autoRotate else { return }
                self.yaw += Float(event.deltaTime) * 0.5
                self.apply()
            }
        }
    }

    private func apply() {
        let direction = SIMD3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
        entity.look(at: target, from: target + direction * distance, relativeTo: nil)
    }
}
