import Foundation
import RealityKit
import UIKit

/// Builds a flat grid to sit under the reconstructed body, so it reads as
/// standing on a surface rather than floating in empty space.
///
/// The grid is a single textured quad rather than one quad per line. Drawing it
/// into a texture means the lines can fade out radially, so the plane dissolves
/// at its rim instead of ending on a hard square edge — and mipmapping softens
/// the lines as they recede, which reads as a natural blur.
struct GroundGridBuilder {

    /// Total width and depth, in the same normalised units the body uses
    /// (where the model's tallest axis measures `targetHeight`, i.e. 1.0).
    var extent: Float = 1.8
    /// Cells per side.
    var divisions: Int = 12
    /// Texture resolution. 512 is plenty for lines this thin.
    var resolution: Int = 412
    /// Line thickness in texture pixels.
    var lineWidth: CGFloat = 2.5
    /// Fraction of the radius that stays at full strength before the fade
    /// begins. Lower values start dissolving closer to the centre.
    var solidRadius: CGFloat = 0.30
    var tint: UIColor = UIColor(red: 0.45, green: 0.83, blue: 1, alpha: 1)

    /// Builds the grid as a ready-to-add entity, positioned at y = 0.
    ///
    /// `@MainActor` because `TextureResource` and `MeshResource` both require it.
    @MainActor
    func makeEntity() async throws -> Entity {
        guard let mask = makeFalloffMask() else {
            throw GroundGridError.maskGenerationFailed
        }

        // `.raw` rather than `.color` so colour management doesn't shift the
        // mask's values — this image is data, not something to look at.
        let texture = try await TextureResource(
            image: mask,
            withName: "ground-grid-opacity",
            options: .init(semantic: .raw, mipmapsMode: .allocateAndGenerateAll)
        )

        var material = UnlitMaterial()
        material.color = .init(tint: tint)
        // RealityKit reads the red channel of an opacity texture, which is why
        // the mask is drawn as white lines on black.
        material.blending = .transparent(opacity: .init(texture: .init(texture)))
        // Visible from underneath too, so orbiting below the model doesn't make
        // the ground disappear.
        material.faceCulling = .none

        let mesh = MeshResource.generatePlane(width: extent, depth: extent)

        let entity = Entity()
        entity.name = "ground"
        entity.components.set(ModelComponent(mesh: mesh, materials: [material]))
        return entity
    }

    /// Draws the grid as a greyscale opacity mask: white lines on black, then
    /// multiplied by a radial gradient so they fade to nothing at the rim.
    private func makeFalloffMask() -> CGImage? {
        let side = CGFloat(resolution)
        let size = CGSize(width: side, height: side)

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1

        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext

            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(lineWidth)

            let step = side / CGFloat(max(1, divisions))
            for line in 0...max(1, divisions) {
                let offset = CGFloat(line) * step
                cg.move(to: CGPoint(x: offset, y: 0))
                cg.addLine(to: CGPoint(x: offset, y: side))
                cg.move(to: CGPoint(x: 0, y: offset))
                cg.addLine(to: CGPoint(x: side, y: offset))
            }
            cg.strokePath()

            // Multiply, so white lines dim toward the edge while the black
            // background stays black. The square boundary ends up invisible.
            cg.setBlendMode(.multiply)

            let centre = CGPoint(x: side / 2, y: side / 2)
            let colors = [UIColor.white.cgColor,
                          UIColor.white.cgColor,
                          UIColor.black.cgColor] as CFArray

            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors,
                                         locations: [0, solidRadius, 1]) {
                cg.drawRadialGradient(gradient,
                                      startCenter: centre, startRadius: 0,
                                      endCenter: centre, endRadius: side / 2,
                                      options: .drawsAfterEndLocation)
            }
        }

        return image.cgImage
    }
}

enum GroundGridError: LocalizedError {
    case maskGenerationFailed

    var errorDescription: String? {
        switch self {
        case .maskGenerationFailed: return "Could not render the grid's opacity mask."
        }
    }
}
