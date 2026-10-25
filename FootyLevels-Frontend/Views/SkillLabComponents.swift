import RealityKit
import SwiftUI

/// A small indeterminate animation. Reduced Motion uses a static waiting symbol.
struct SLActivityIndicator: View {
    var size: CGFloat = 18
    var color: Color = SL.green
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotating = false

    var body: some View {
        Group {
            if reduceMotion {
                Image(systemName: "hourglass")
                    .font(.system(size: size * 0.8, weight: .medium))
            } else {
                ZStack {
                    Circle().stroke(color.opacity(0.16), lineWidth: 2)
                    Circle().trim(from: 0.08, to: 0.75)
                        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(rotating ? 360 : 0))
                        .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: rotating)
                }
                .onAppear { rotating = true }
                .onDisappear { rotating = false }
            }
        }
        .foregroundStyle(color)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Honest waiting feedback for requests without a measurable progress value.
struct SLLoadingState: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            SLActivityIndicator(size: 22)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(SL.ink)
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(SL.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .slPanel(fill: SL.iconTile)
        .accessibilityElement(children: .combine)
    }
}

/// Hosts a prepared stage with an app-driven orbit camera.
///
/// The root is attached once and then left alone: animation writes straight
/// into the body's vertex buffer and toggles flip `isEnabled`, so nothing
/// forces SwiftUI to rebuild the scene per frame. Drag orbits, pinch zooms.
struct ModelStageView: View {
    let root: Entity?
    let camera: OrbitCamera
    /// Called after a drag or pinch moved the camera, e.g. to move a linked one.
    var onCameraChange: (() -> Void)? = nil

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
                    onCameraChange?()
                }
                .onEnded { _ in dragStart = nil }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let start = zoomStart ?? camera.currentDistance
                    zoomStart = start
                    camera.zoom(from: start, magnification: value.magnification)
                    onCameraChange?()
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
                SLActivityIndicator(size: 28)
            }
            Text(message)
                .font(.subheadline)
                .foregroundStyle(SL.muted)
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
