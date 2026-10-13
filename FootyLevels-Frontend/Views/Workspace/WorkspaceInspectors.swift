import SwiftUI

private let stageHeight: CGFloat = 380

// MARK: - Motion inspector

/// Whole-video player + football in 3D, driven by the source video.
struct MotionInspectorPanel: View {
    let project: SkillLabProject
    /// Nil until a playable sequence exists.
    let model: MotionPlayerViewModel?
    let canGenerate: Bool
    let blocker: String?
    let onGenerate: () -> Void

    private var motion: MotionState? { project.motion }

    var body: some View {
        VStack(spacing: 0) {
            PanelTopline(icon: "waveform.path.ecg", title: "MOTION INSPECTOR") {
                StatusDot(text: statusText, ready: motion?.isPlayable == true)
            }

            ZStack {
                if let model {
                    // A re-run builds a new model with a new camera; RealityView
                    // only runs its setup once, so give it a fresh identity.
                    ModelStageView(root: model.stageRoot, camera: model.camera)
                        .id(ObjectIdentifier(model))
                        .accessibilityIdentifier("motion-stage")
                        .accessibilityValue(model.accessibilityStatus)
                    MotionStageOverlays(model: model)
                } else {
                    SL.stage.overlay(DotGrid())
                    emptyState
                }
            }
            .frame(height: stageHeight)
            .clipped()

            if let model {
                PresetToolbar(selection: model.angle, enabled: model.state == .ready) { model.show($0) }
                OptionsRow(hint: "Play or scrub the video · Drag to orbit") {
                    Toggle("Follow", isOn: Binding(get: { model.follow }, set: { model.follow = $0 }))
                    Toggle("Ball", isOn: Binding(get: { model.showBall }, set: { model.showBall = $0 }))
                        .disabled((model.sequence?.validBallFrames ?? 0) == 0)
                    Toggle("Wireframe", isOn: Binding(get: { model.wireframe }, set: { model.wireframe = $0 }))
                }
            }
        }
        .slPanel()
    }

    private var statusText: String {
        guard let motion else { return "Whole-video reconstruction" }
        if motion.isPlayable {
            var parts: [String] = []
            if motion.groundAligned == true { parts.append("Ground aligned") }
            if let frames = motion.bodyFrames { parts.append("\(frames) poses") }
            if let fps = motion.fps { parts.append("\(fps.formatted()) fps") }
            return parts.joined(separator: " · ")
        }
        return motion.isActive ? "Reconstructing video" : "Whole-video reconstruction"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color(hex: "83936A"))
            Text("See the move in motion.")
                .font(SL.display(22, .semibold))
                .tracking(-0.8)
                .foregroundStyle(SL.ink)
            Text(emptyMessage)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "748069"))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 290)
            Button(action: onGenerate) {
                HStack(spacing: 8) {
                    if motion?.isActive == true {
                        ProgressView().tint(.white).controlSize(.small)
                        Text("Building motion…")
                    } else {
                        Image(systemName: "waveform.path.ecg")
                        Text("Generate body + ball motion")
                    }
                }
            }
            .buttonStyle(.slPrimary)
            .disabled(!canGenerate || motion?.isActive == true)
            .padding(.top, 6)
            if !canGenerate, motion?.isActive != true, let blocker {
                Text(blocker)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "88947F"))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
    }

    private var emptyMessage: String {
        if let motion, motion.isActive {
            return "\(motion.stage ?? "Processing") · this view updates when ready."
        }
        return motion?.error
            ?? "Reconstruct the player across the whole video and track the football in the same 3D scene."
    }
}

/// Frame counter, contact note and loading states over the motion stage.
/// Separate so its 30 Hz updates don't rebuild the RealityView's parent.
private struct MotionStageOverlays: View {
    let model: MotionPlayerViewModel

    var body: some View {
        ZStack {
            switch model.state {
            case .loading(let message):
                StageMessage(message: message, isLoading: true)
            case .failed(let message):
                StageMessage(message: message, isLoading: false)
            case .ready:
                EmptyView()
            }
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 8) {
                if let contact = model.contactLabel, model.state == .ready {
                    Text(contact)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "5B7250"))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color(hex: "F6F8EF").opacity(0.92), in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(SL.modeBorder))
                }
                if model.missingPose {
                    Text("Player not reconstructed in this frame")
                        .font(.system(size: 11))
                        .foregroundStyle(SL.noticeText)
                        .padding(8)
                        .background(SL.noticeFill, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(14)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomLeading) {
            StageFrameLabel(frame: model.currentFrame, seconds: Double(model.currentFrame) / model.fps)
        }
        .overlay(alignment: .topTrailing) {
            if let sequence = model.sequence, model.loadedChunks < sequence.chunks.count, model.state == .ready {
                Label("\(model.loadedChunks)/\(sequence.chunks.count)", systemImage: "arrow.down.circle")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(SL.presetText)
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Pose inspector

/// One key frame's reconstructed body.
struct PoseInspectorPanel: View {
    let frame: KeyFrame
    let model: PoseInspectorModel
    let canGenerate: Bool
    let blocker: String?
    let onGenerate: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PanelTopline(icon: "cube", title: "POSE INSPECTOR") {
                StatusDot(text: statusText, ready: frame.isReady)
            }

            ZStack {
                if frame.isReady {
                    ModelStageView(root: model.stageRoot, camera: model.camera)
                    if model.isLoading {
                        StageMessage(message: "Loading mesh", isLoading: true)
                    } else if let error = model.errorMessage {
                        StageMessage(message: error, isLoading: false)
                    }
                } else {
                    SL.stage.overlay(DotGrid())
                    emptyState
                }
            }
            .frame(height: stageHeight)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                StageFrameLabel(frame: frame.frameIndex, seconds: frame.timestamp)
            }
            .overlay(alignment: .bottomTrailing) {
                if frame.isReady {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("↑ Y")
                        Text("→ X")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: "8A9C7B"))
                    .padding(16)
                    .allowsHitTesting(false)
                }
            }

            PresetToolbar(selection: model.angle, enabled: frame.isReady && model.stageRoot != nil) { model.show($0) }
            OptionsRow(hint: model.info ?? "Drag to orbit · Pinch to zoom") {
                Toggle("Wireframe", isOn: Binding(get: { model.wireframe }, set: { model.wireframe = $0 }))
                    .disabled(!frame.isReady)
                Toggle(isOn: Binding(get: { model.autoRotate }, set: { model.autoRotate = $0 })) {
                    Label("Rotate", systemImage: "rotate.3d")
                }
                .disabled(!frame.isReady)
            }
        }
        .slPanel()
    }

    private var pending: Bool { frame.isActive }

    private var statusText: String {
        if frame.isReady { return "3D model ready" }
        if pending { return "Reconstructing" }
        return frame.status == "failed" ? "Needs attention" : "Awaiting reconstruction"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            ZStack {
                Ellipse()
                    .stroke(Color(hex: "BDCAAA"))
                    .frame(width: 83, height: 29)
                    .rotationEffect(.degrees(-30))
                Image(systemName: "cube")
                    .font(.system(size: 34, weight: .ultraLight))
                    .foregroundStyle(Color(hex: "83936A"))
            }
            .frame(height: 64)
            Eyebrow(text: "A NEW PERSPECTIVE", color: Color(hex: "829173"))
            Text(pending ? "Building this pose…" : "Turn a moment into 3D.")
                .font(SL.display(22, .semibold))
                .tracking(-0.8)
                .foregroundStyle(SL.ink)
            Text(pending
                 ? "SAM 3D Body is reconstructing the selected person. This view will update when the mesh is ready."
                 : frame.error ?? "Reconstruct this key frame to explore the player’s body position from every angle.")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "748069"))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 290)
            if pending {
                ProgressView().padding(.top, 6)
            } else {
                Button(action: onGenerate) {
                    Label("Reconstruct this frame", systemImage: "cube")
                }
                .buttonStyle(.slPrimary)
                .disabled(!canGenerate)
                .padding(.top, 6)
                if !canGenerate, let blocker {
                    Text(blocker)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "88947F"))
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(24)
    }
}

// MARK: - Shared stage pieces

/// "105  FRAME / 3.50s" in the stage's lower-left corner.
private struct StageFrameLabel: View {
    let frame: Int
    let seconds: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(String(format: "%03d", frame))
                .font(SL.display(20, .medium).monospacedDigit())
                .tracking(-0.5)
                .foregroundStyle(Color(hex: "839574"))
            Text("FRAME /\n\(String(format: "%.2f", seconds))s")
                .font(.system(size: 8, weight: .medium))
                .tracking(1)
                .foregroundStyle(Color(hex: "8D9A82"))
        }
        .padding(.leading, 18)
        .padding(.bottom, 14)
        .allowsHitTesting(false)
    }
}

struct StageMessage: View {
    let message: String
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView()
            } else {
                Image(systemName: "exclamationmark.circle")
            }
            Text(message)
                .multilineTextAlignment(.center)
        }
        .font(.system(size: 13))
        .foregroundStyle(isLoading ? SL.ink : SL.errorText)
        .padding(25)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SL.stage.opacity(0.8))
    }
}

/// The faint dot texture behind empty stages.
private struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 20
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6)),
                                 with: .color(Color(hex: "ACBBA5").opacity(0.25)))
                    x += spacing
                }
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

/// Source · Left · Right · Back · Above, plus reset.
struct PresetToolbar: View {
    let selection: CameraAngle
    let enabled: Bool
    let onSelect: (CameraAngle) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CameraAngle.allCases) { angle in
                Button(angle.rawValue) { onSelect(angle) }
                    .font(.system(size: 12))
                    .foregroundStyle(selection == angle ? SL.presetActiveText : SL.presetText)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(selection == angle ? SL.presetActive : .clear, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(selection == angle ? SL.presetActiveBorder : .clear))
                    .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Button {
                onSelect(.source)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14))
                    .foregroundStyle(SL.ink)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reset camera")
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(SL.toolbar)
        .overlay(alignment: .top) { Rectangle().fill(Color(hex: "DCE3D3")).frame(height: 1) }
    }
}

/// Hint text on the left, checkbox toggles on the right.
private struct OptionsRow<Toggles: View>: View {
    let hint: String
    @ViewBuilder var toggles: Toggles

    var body: some View {
        HStack(spacing: 8) {
            Text(hint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            HStack(spacing: 12) { toggles }
                .toggleStyle(CheckToggleStyle())
        }
        .font(.system(size: 11))
        .foregroundStyle(Color(hex: "8A9481"))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Color(hex: "E0E7D6")).frame(height: 1) }
    }
}
