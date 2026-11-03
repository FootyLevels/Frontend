import RealityKit
import SwiftUI

/// What the shared lesson controls need from a lesson's model. Both the Over Fake lesson and
/// lessons made by the lesson pipeline provide it.
@MainActor
protocol LessonPlayer: AnyObject, Observable {
    var playback: PlaybackController { get }
    var stage: LessonStage { get }
    var overlays: LessonOverlays { get set }
    var mirror: Bool { get set }
    var angle: CameraAngle { get }
    var loop: ClosedRange<Double>? { get }
    var stageRoot: Entity? { get }
    var camera: OrbitCamera { get }
    var isReady: Bool { get }
    /// What the 3D panel shows while it isn't ready, and whether it is still loading.
    var stageMessage: (text: String, isLoading: Bool)? { get }

    func enter(_ stage: LessonStage)
    func togglePlayback()
    func step(frames: Int)
    func toggleLoop()
    func show(_ angle: CameraAngle)
}

extension SkillLessonModel: LessonPlayer {
    var isReady: Bool { state == .ready }

    var stageMessage: (text: String, isLoading: Bool)? {
        switch state {
        case .loading(let message): return (message, true)
        case .failed(let message): return (message, false)
        case .ready: return nil
        }
    }
}

extension PackageLessonModel: LessonPlayer {
    var isReady: Bool { state == .ready }

    var stageMessage: (text: String, isLoading: Bool)? {
        switch state {
        case .loading(let message): return (message, true)
        case .failed(let message): return (message, false)
        case .ready: return nil
        }
    }
}

// MARK: - Stage picker

/// Watch · Break it down · Practise · Test yourself: a real sequence, so numbered.
struct StagePicker<Model: LessonPlayer>: View {
    let model: Model

    var body: some View {
        HStack(spacing: 3) {
            ForEach(LessonStage.allCases) { stage in
                let selected = model.stage == stage
                Button {
                    model.enter(stage)
                } label: {
                    VStack(spacing: 2) {
                        Text("\(stage.number)")
                            .font(.system(.caption2, weight: .semibold).monospacedDigit())
                        Text(stage.rawValue)
                            .font(.system(.caption, weight: selected ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(selected ? SL.onGreen : SL.modeText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(selected ? SL.green : .clear, in: Capsule())
                    .minimumTapArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stage \(stage.number): \(stage.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(SL.modeTrack, in: Capsule())
        .disabled(!model.isReady)
    }
}

// MARK: - Video + 3D

/// The original video beside the 3D body, with the camera presets underneath.
struct LessonStageView<Model: LessonPlayer>: View {
    let model: Model
    /// Small label over the video, e.g. which part of the clip is playing.
    let shotLabel: String
    /// The current phase's name and cue, over the video.
    let cue: (name: String, text: String)?

    /// The video is 9:16; it takes this share of the width and sets the height.
    private let videoShare: CGFloat = 0.44

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let videoWidth = geo.size.width * videoShare
                HStack(spacing: 6) {
                    videoTile.frame(width: videoWidth)
                    stageTile
                }
            }
            .aspectRatio(1 / (videoShare * 16 / 9), contentMode: .fit)
            .padding(6)
            .background(SL.videoPanel)

            PresetToolbar(selection: model.angle, enabled: model.isReady) { model.show($0) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(SL.videoBorder))
    }

    private var videoTile: some View {
        ZStack {
            SL.videoStage
            VideoSurface(player: model.playback.player)
                .scaleEffect(x: model.mirror ? -1 : 1, y: 1)
                .onTapGesture { model.togglePlayback() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Original video. Tap to play or pause.")
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topLeading) {
            if !shotLabel.isEmpty {
                Text(shotLabel.uppercased())
                    .font(.system(.caption2, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(SL.videoText)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(SL.videoStage.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if let cue {
                PhaseCue(name: cue.name, text: cue.text)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        // Labels over the picture stop growing at the largest standard size, so they never hide it.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var stageTile: some View {
        ZStack {
            ModelStageView(root: model.stageRoot, camera: model.camera)
            if let message = model.stageMessage {
                StageMessage(message: message.text, isLoading: message.isLoading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topLeading) {
            if model.mirror {
                Text("MIRRORED")
                    .font(.system(.caption2, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(SL.lime, in: Capsule())
                    .padding(6)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// A phase's name and cue, over the video.
private struct PhaseCue: View {
    let name: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name.uppercased())
                .font(SL.display(.subheadline))
                .foregroundStyle(SL.videoText)
            Text(text)
                .font(.system(.caption2))
                .foregroundStyle(SL.videoText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(SL.videoStage.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Transport

/// Play, frame steps, speed, loop, mirror, the lesson's timeline and the 3D cue toggles.
struct LessonTransport<Model: LessonPlayer, Timeline: View>: View {
    @Bindable var model: Model
    @ViewBuilder var timeline: Timeline

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowRow(spacing: 6) {
                PlayButton(playback: model.playback) { model.togglePlayback() }
                iconButton("chevron.left", label: "Back one frame") { model.step(frames: -1) }
                iconButton("chevron.right", label: "Forward one frame") { model.step(frames: 1) }
                Menu {
                    Picker("Playback speed", selection: Binding(get: { model.playback.speed }, set: { model.playback.speed = $0 })) {
                        ForEach(PlaybackController.speeds, id: \.self) { Text("\($0.formatted())× speed").tag($0) }
                    }
                } label: {
                    Text("\(model.playback.speed.formatted())×")
                        .font(.system(.caption, weight: .semibold).monospacedDigit())
                        .frame(minWidth: 34, minHeight: 32)
                        .overlay(Capsule().stroke(SL.controlBorder))
                        .minimumTapArea()
                }
                .accessibilityLabel("Playback speed")
                toggle("Loop", on: model.loop != nil) { model.toggleLoop() }
                toggle("Mirror", on: model.mirror) { model.mirror.toggle() }
                TimeLabel(playback: model.playback)
                    .frame(minHeight: 44)
            }
            .foregroundStyle(SL.ink)

            timeline

            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    Toggle("Footprints", isOn: $model.overlays.footprints)
                    Toggle("Paths", isOn: $model.overlays.paths)
                    Toggle("Ghost of last step", isOn: $model.overlays.ghost)
                    Toggle("Direction", isOn: $model.overlays.direction)
                    Toggle("Follow", isOn: $model.overlays.follow)
                }
                .toggleStyle(CheckToggleStyle())
                .font(.system(.caption))
                .foregroundStyle(SL.muted)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .slPanel(fill: SL.panel, border: SL.panelBorder, radius: 22)
        .disabled(!model.isReady)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(.caption, weight: .semibold))
                .scaledFrame(width: 32, relativeTo: .caption)
                .overlay(Capsule().stroke(SL.controlBorder))
                .minimumTapArea()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func toggle(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.caption, weight: .semibold))
                .padding(.horizontal, 9)
                .frame(minHeight: 32)
                .foregroundStyle(on ? SL.onGreen : SL.ink)
                .background(on ? SL.green : .clear, in: Capsule())
                .overlay(Capsule().stroke(on ? SL.green : SL.controlBorder))
                .minimumTapArea()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Reads the playing state in its own view, so only this button redraws.
struct PlayButton: View {
    let playback: PlaybackController
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(SL.onGreen)
                .scaledFrame(width: 40, height: 32, relativeTo: .footnote)
                .background(SL.green, in: Capsule())
                .minimumTapArea()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
    }
}

/// Reads the 60 Hz clock in its own view.
struct TimeLabel: View {
    let playback: PlaybackController

    var body: some View {
        Text(String(format: "%.2f s", playback.currentTime))
            .font(.system(.caption).monospacedDigit())
            .foregroundStyle(SL.muted)
    }
}

/// The current time on a timeline that spans `range`.
struct Playhead: View {
    let playback: PlaybackController
    let range: ClosedRange<Double>
    let width: CGFloat

    var body: some View {
        let span = Swift.max(range.upperBound - range.lowerBound, 0.001)
        let share = Swift.min(Swift.max((playback.currentTime - range.lowerBound) / span, 0), 1)
        Rectangle()
            .fill(SL.ink)
            .frame(width: 2, height: 30)
            .offset(x: width * CGFloat(share) - 1, y: 10)
            .allowsHitTesting(false)
    }
}

// MARK: - Section pieces

struct SectionCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .slPanel(fill: SL.card, border: SL.cardBorder, radius: 10)
    }
}

struct SectionHeading: View {
    let eyebrow: String
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: eyebrow, color: SL.muted)
            Text(title)
                .font(SL.display(.title2))
                .tracking(-0.6)
                .foregroundStyle(SL.ink)
            Text(text)
                .font(.system(.subheadline))
                .foregroundStyle(SL.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct NumberBadge: View {
    let text: String
    var filled = false
    var color: Color = SL.green

    var body: some View {
        Text(text)
            .font(.system(.caption, weight: .semibold).monospacedDigit())
            .foregroundStyle(filled ? .white : SL.ink)
            .scaledFrame(width: 26, relativeTo: .caption)
            .background(filled ? color : .clear, in: Circle())
            .overlay(Circle().stroke(filled ? color : SL.cardBorder, lineWidth: 1.5))
    }
}

extension LessonConfidence {
    var color: Color {
        switch self {
        case .high: return SL.good
        case .medium: return SL.fair
        case .low: return SL.miss
        }
    }
}

/// Lays children out left to right, wrapping onto new rows.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            widest = Swift.max(widest, x - spacing)
            rowHeight = Swift.max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = Swift.max(rowHeight, size.height)
        }
    }
}
