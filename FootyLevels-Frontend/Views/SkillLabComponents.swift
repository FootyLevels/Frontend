import RealityKit
import SwiftUI

/// Hosts a prepared stage with an app-driven orbit camera.
///
/// The root is attached once and then left alone: animation writes straight
/// into the body's vertex buffer and toggles flip `isEnabled`, so nothing
/// forces SwiftUI to rebuild the scene per frame. Drag orbits, pinch zooms.
struct ModelStageView: View {
    let root: Entity?
    let camera: OrbitCamera

    @State private var dragStart: (yaw: Float, pitch: Float)?
    @State private var zoomStart: Float?

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            let anchor = Entity()
            anchor.name = "stage-anchor"
            content.add(anchor)
            content.add(camera.entity)
            content.add(StageBuilder.makeKeyLight())
            camera.attach(to: content)
        } update: { content in
            guard let anchor = content.entities.first(where: { $0.name == "stage-anchor" }) else { return }
            if let root {
                if root.parent !== anchor {
                    anchor.children.removeAll()
                    anchor.addChild(root)
                }
            } else if !anchor.children.isEmpty {
                anchor.children.removeAll()
            }
        }
        .background(SL.stage)
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let start = dragStart ?? camera.orientation
                    dragStart = start
                    camera.orbit(from: start, translation: value.translation)
                }
                .onEnded { _ in dragStart = nil }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let start = zoomStart ?? camera.currentDistance
                    zoomStart = start
                    camera.zoom(from: start, magnification: value.magnification)
                }
                .onEnded { _ in zoomStart = nil }
        )
        .accessibilityLabel("3D view. Drag to orbit, pinch to zoom.")
    }
}

/// Compact colour-coded status for frames and jobs.
struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var label: String {
        switch status {
        case "ready", "complete": return "Ready"
        case "partial": return "Partial"
        case "running": return "Running"
        case "queued": return "Queued"
        case "failed": return "Failed"
        case "interrupted": return "Interrupted"
        default: return "Pending"
        }
    }

    private var color: Color {
        switch status {
        case "ready", "complete": return AppTheme.primaryColor
        case "partial", "interrupted": return .orange
        case "running", "queued": return .blue
        case "failed": return AppTheme.errorColor
        default: return .secondary
        }
    }
}

/// Shows loading and failure states over a stage.
struct StageStatusOverlay: View {
    let message: String
    var isError = false

    var body: some View {
        VStack(spacing: 12) {
            if isError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(AppTheme.errorColor)
            } else {
                ProgressView().controlSize(.large)
            }
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Double {
    /// `m:ss.s` for timestamps inside a clip.
    var clipTimestamp: String {
        let minutes = Int(self) / 60
        let seconds = self - Double(minutes * 60)
        return String(format: "%d:%04.1f", minutes, seconds)
    }
}
