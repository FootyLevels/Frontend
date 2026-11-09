import AVFoundation
import RealityKit
import SwiftUI

private let stageHeight: CGFloat = 380

/// Two clips compared in 3D — A in blue, B in orange — overlaid in one scene
/// or side by side, with both source videos on A's clock and the controls for
/// lining them up.
struct ComparisonView: View {
    let model: ComparisonModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                videos
                OverlayTransport(playback: model.playback)
                ComparisonLayoutSwitch(model: model)
                switch model.layout {
                case .overlay: overlayPanel
                case .sideBySide: sideBySidePanel
                }
                ComparisonControls(model: model)
                Text("The comparison shows where two movements differ. It doesn't score or rank either one.")
                    .font(.system(.caption2))
                    .foregroundStyle(SL.muted)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(SL.page)
        .navigationTitle(model.layout == .overlay ? "Overlay difference" : "Side by side")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        // A tab switch lands here too; the owner releases the model on close.
        .onDisappear { model.pause() }
    }

    // MARK: - Videos

    private var videos: some View {
        HStack(spacing: 8) {
            videoTile(.first, project: model.first, player: model.playback.player)
            videoTile(.second, project: model.second, player: model.secondVideo)
        }
    }

    private func videoTile(_ slot: OverlaySlot, project: SkillLabProject, player: AVPlayer) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                OverlaySlotBadge(slot: slot, size: 18)
                Text(project.title)
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(SL.videoText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)

            ZStack {
                SL.videoStage
                VideoSurface(player: player)
            }
            .frame(height: 210)
            .contentShape(Rectangle())
            .onTapGesture { model.playback.togglePlayback() }
        }
        .slPanel(fill: SL.videoPanel, border: slot.color.opacity(0.7))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Video \(slot.rawValue), \(slot.role): \(project.title)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Plays or pauses both videos")
    }

    // MARK: - Stage

    private var overlayPanel: some View {
        VStack(spacing: 0) {
            PanelTopline(icon: "square.2.layers.3d", title: "OVERLAY") {
                StatusDot(text: model.locksCenterOfMass ? "Centers of mass aligned" : "Own positions",
                          ready: model.state == .ready)
            }

            ZStack {
                ModelStageView(root: model.overlayRoot, camera: model.camera)
                OverlayStageOverlays(model: model)
            }
            .frame(height: stageHeight)
            .clipped()

            PresetToolbar(selection: model.angle, enabled: model.state == .ready) { model.show($0) }
        }
        .slPanel()
    }

    /// Two stages, one body each. Narrow, so each is tall enough for a standing player.
    private var sideBySidePanel: some View {
        VStack(spacing: 0) {
            PanelTopline(icon: "rectangle.split.2x1", title: "SIDE BY SIDE") {
                StatusDot(text: model.linksCameras ? "Cameras linked" : "Cameras independent",
                          ready: model.state == .ready)
            }

            HStack(spacing: 1) {
                SideStage(model: model, slot: .first)
                SideStage(model: model, slot: .second)
            }
            .background(SL.panelBorder)
            .frame(height: stageHeight)
            .clipped()

            PresetToolbar(selection: model.angle, enabled: model.state == .ready) { model.show($0) }
        }
        .slPanel()
    }
}

// MARK: - Layout switch

/// Overlay · Side by side, styled like the workspace's mode switch.
private struct ComparisonLayoutSwitch: View {
    let model: ComparisonModel

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ComparisonModel.Layout.allCases) { layout in
                let selected = model.layout == layout
                Button {
                    Task { await model.setLayout(layout) }
                } label: {
                    Text(layout.rawValue)
                        .font(.system(.footnote, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? SL.onGreen : SL.modeText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selected ? SL.greenActive : .clear, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .slPanel(fill: SL.modeTrack, border: SL.modeBorder, radius: 8)
        .disabled(model.state != .ready)
    }
}

// MARK: - Side-by-side stage

/// One body's stage, with its label and pose note. Orbiting it moves the
/// other stage too while the cameras are linked.
private struct SideStage: View {
    let model: ComparisonModel
    let slot: OverlaySlot

    private var root: Entity? { slot == .first ? model.firstRoot : model.secondRoot }
    private var camera: OrbitCamera { slot == .first ? model.firstCamera : model.secondCamera }
    private var missing: Bool { slot == .first ? model.firstMissing : model.secondMissing }

    var body: some View {
        ZStack {
            ModelStageView(root: root, camera: camera) { model.cameraMoved(camera) }
            if root == nil {
                StageMessage(message: "", isLoading: true)
            }
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    OverlaySlotBadge(slot: slot, size: 16)
                    Text(slot.role)
                }
                if missing, model.state == .ready {
                    Text("No pose in this frame").foregroundStyle(SL.noticeText)
                }
            }
            .font(.system(.caption2))
            .foregroundStyle(SL.ink)
            .padding(7)
            .background(SL.toolbar.opacity(0.92), in: RoundedRectangle(cornerRadius: 5))
            .padding(8)
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(slot.role) in 3D")
    }
}

// MARK: - Transport

/// Play, time, speed and a scrubber for A's clock. Separate so its 60 Hz
/// time updates don't rebuild the stage.
private struct OverlayTransport: View {
    let playback: PlaybackController

    @State private var wasPlaying = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    playback.togglePlayback()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(.title3))
                        .foregroundStyle(SL.videoText)
                        .scaledFrame(width: 28, relativeTo: .title3)
                        .minimumTapArea()
                }
                .accessibilityLabel(playback.isPlaying ? "Pause both videos" : "Play both videos")

                Text("\(String(format: "%.2f", playback.currentTime))\(Text(String(format: "  / %.2f", playback.duration)).foregroundStyle(SL.videoMuted))")
                    .font(.system(.caption).monospacedDigit())
                    .foregroundStyle(SL.videoText)

                Spacer()

                Menu {
                    Picker("Playback speed", selection: Binding(get: { playback.speed }, set: { playback.speed = $0 })) {
                        ForEach(PlaybackController.speeds, id: \.self) { speed in
                            Text("\(speed.formatted())× speed").tag(speed)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("\(playback.speed.formatted())× speed")
                        Image(systemName: "chevron.down").font(.system(.caption2, weight: .bold)).imageScale(.small)
                    }
                    .font(.system(.caption2))
                    .foregroundStyle(SL.videoText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(SL.videoTopline, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(SL.videoBorder))
                }
            }

            Slider(value: Binding(get: { playback.currentTime }, set: { playback.seek(to: $0) }),
                   in: 0...Swift.max(playback.duration, 0.01)) { editing in
                if editing {
                    wasPlaying = playback.isPlaying
                    playback.pause()
                } else if wasPlaying {
                    playback.togglePlayback()
                }
            } label: {
                Text("Time in video A")
            }
            .tint(SL.lime)
            .accessibilityValue(String(format: "%.2f seconds", playback.currentTime))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .slPanel(fill: SL.videoPanel, border: SL.videoBorder)
    }
}

// MARK: - Stage overlays

/// Legend, missing-pose notes, frame label and load states over the stage.
/// Separate so its per-frame updates don't rebuild the RealityView's parent.
private struct OverlayStageOverlays: View {
    let model: ComparisonModel

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
        // Fill the stage, so the corner overlays sit in its corners rather
        // than around an empty view's zero size.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(OverlaySlot.allCases) { slot in
                    HStack(spacing: 6) {
                        OverlaySlotBadge(slot: slot, size: 16)
                        Text(slot.role)
                        if missing(slot), model.state == .ready {
                            Text("· no pose in this frame").foregroundStyle(SL.noticeText)
                        }
                    }
                }
            }
            .font(.system(.caption2))
            .foregroundStyle(SL.ink)
            .padding(9)
            .background(SL.toolbar.opacity(0.92), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(SL.modeBorder))
            .padding(12)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomLeading) {
            if model.state == .ready {
                Text(String(format: "A FRAME %03d", model.currentFrame))
                    .font(.system(.caption2, weight: .medium).monospacedDigit())
                    .tracking(1)
                    .foregroundStyle(SL.muted)
                    .padding(14)
                    .allowsHitTesting(false)
            }
        }
    }

    private func missing(_ slot: OverlaySlot) -> Bool {
        slot == .first ? model.firstMissing : model.secondMissing
    }
}

// MARK: - Alignment controls

/// B's time shift and turn for both layouts; transparency and the center-of-mass
/// lock for the overlay; camera linking side by side.
private struct ComparisonControls: View {
    @Bindable var model: ComparisonModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow(text: "ALIGNMENT", color: SL.muted)

            if model.layout == .overlay {
                transparencyRow(.first, value: $model.firstTransparency)
                transparencyRow(.second, value: $model.secondTransparency)

                Divider()
            }

            VStack(alignment: .leading, spacing: 8) {
                row(title: "Shift B in time", value: String(format: "%+.2f s", model.offset))
                HStack(spacing: 10) {
                    nudge("minus", label: "Shift B back one frame") { model.nudgeOffset(frames: -1) }
                    Slider(value: $model.offset, in: model.offsetRange) {
                        Text("Shift B in time")
                    }
                    .accessibilityValue(String(format: "%+.2f seconds", model.offset))
                    nudge("plus", label: "Shift B forward one frame") { model.nudgeOffset(frames: 1) }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                row(title: "Turn B", value: "\(Int(model.turn))°")
                HStack(spacing: 10) {
                    Slider(value: $model.turn, in: -180...180, step: 1) {
                        Text("Turn B")
                    }
                    .accessibilityValue("\(Int(model.turn)) degrees")
                    Button("Match facing") { model.matchFacing() }
                        .buttonStyle(.slSecondary)
                        .disabled(!model.canMatchFacing)
                }
            }

            HStack(spacing: 16) {
                if model.layout == .overlay {
                    Toggle("Lock center of mass", isOn: $model.locksCenterOfMass)
                } else {
                    Toggle("Link cameras", isOn: $model.linksCameras)
                }
                Toggle("Follow", isOn: $model.follow)
                Spacer(minLength: 0)
            }
            .toggleStyle(CheckToggleStyle())
            .font(.system(.caption))
            .foregroundStyle(SL.muted)
        }
        .tint(SL.tint)
        .disabled(model.state != .ready)
        .padding(16)
        .slPanel()
    }

    private func transparencyRow(_ slot: OverlaySlot, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                OverlaySlotBadge(slot: slot, size: 18)
                row(title: "\(slot.role) transparency", value: "\(Int((value.wrappedValue * 100).rounded()))%")
            }
            Slider(value: value, in: 0...ComparisonModel.maxTransparency) {
                Text("\(slot.role) transparency")
            }
            .tint(slot.color)
            .accessibilityValue("\(Int((value.wrappedValue * 100).rounded())) percent")
        }
    }

    private func row(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(SL.ink)
            Spacer()
            Text(value)
                .font(.system(.caption).monospacedDigit())
                .foregroundStyle(SL.muted)
        }
    }

    private func nudge(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(.caption, weight: .semibold))
                .scaledFrame(width: 32, relativeTo: .caption)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(SL.controlBorder))
                .minimumTapArea()
        }
        .buttonStyle(.plain)
        .foregroundStyle(SL.ink)
        .accessibilityLabel(label)
    }
}
