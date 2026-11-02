import AVFoundation
import SwiftUI
import UIKit

/// The dark "ORIGINAL VIDEO" panel: the source clip with the web workspace's
/// custom controls and key-frame marks on the timeline.
struct WorkspaceVideoPanel: View {
    let project: SkillLabProject
    let playback: PlaybackController
    let selectedFrameId: String?
    let canCapture: Bool
    let onCapture: (Double) -> Void
    let onChoose: (KeyFrame) -> Void

    var body: some View {
        VStack(spacing: 0) {
            PanelTopline(icon: "film", title: "ORIGINAL VIDEO", dark: true) {
                HStack(spacing: 8) {
                    Text("\(project.video.width) × \(project.video.height)")
                    Circle().fill(Color(hex: "D5EC95")).frame(width: 5, height: 5)
                }
                .font(.system(.caption2))
                .foregroundStyle(Color(hex: "A0B29E"))
            }

            stage
            controls
        }
        .slPanel(fill: SL.videoPanel, border: Color(hex: "2B3B32"))
    }

    // MARK: - Stage

    private var stage: some View {
        ZStack {
            SL.videoStage
            VideoSurface(player: playback.player)
                .onTapGesture { playback.togglePlayback() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(playback.isPlaying ? "Pause video" : "Play video")

            // Soft vignettes at the sides, as on the web stage.
            HStack {
                LinearGradient(colors: [Color(hex: "10251F").opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 60)
                Spacer()
                LinearGradient(colors: [.clear, Color(hex: "10251F").opacity(0.4)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 60)
            }
            .allowsHitTesting(false)
        }
        .frame(height: 360)
        .overlay(alignment: .topLeading) {
            Text(BundledSample.isSample(project.id) ? "THE OVER FAKE TUTORIAL" : "SKILL BREAKDOWN")
                .font(.system(.caption2, weight: .medium))
                .tracking(1)
                .foregroundStyle(Color(hex: "F4F6DF"))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(hex: "0E261C").opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(hex: "92A979").opacity(0.2)))
                .padding(14)
        }
        .overlay(alignment: .bottom) {
            if canCapture {
                Button {
                    onCapture(Swift.min(playback.currentTime, project.video.duration - 0.04))
                } label: {
                    Label("Capture this moment", systemImage: "plus")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(SL.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color(hex: "F7F9EF").opacity(0.93), in: RoundedRectangle(cornerRadius: 5))
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    playback.togglePlayback()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(.title3))
                        .foregroundStyle(Color(hex: "EAF5D9"))
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel(playback.isPlaying ? "Pause video" : "Play video")

                Timecode(playback: playback)

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
                    .foregroundStyle(Color(hex: "D5E4C9"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(hex: "193B2B"), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "526854")))
                }

                Button {
                    playback.isMuted.toggle()
                } label: {
                    Image(systemName: playback.isMuted ? "speaker.slash" : "speaker.wave.2")
                        .font(.system(.subheadline))
                        .foregroundStyle(SL.videoText)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel(playback.isMuted ? "Unmute video" : "Mute video")
            }

            VideoTimeline(project: project, playback: playback,
                          selectedFrameId: selectedFrameId, onChoose: onChoose)

            HStack {
                Toggle(isOn: Binding(get: { playback.loops }, set: { playback.loops = $0 })) {
                    Text("Loop video")
                }
                .toggleStyle(CheckToggleStyle(tint: Color(hex: "CDDD9C"), dark: true))
                Spacer()
                Text("Take your time. Notice the details.")
            }
            .font(.system(.caption2))
            .foregroundStyle(Color(hex: "95AA92"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

/// Reads `currentTime` in its own view so only this text updates at 60 Hz.
private struct Timecode: View {
    let playback: PlaybackController

    var body: some View {
        Text("\(String(format: "%.2f", playback.currentTime))\(Text(String(format: "  / %.2f", playback.duration)).foregroundStyle(SL.videoMuted))")
            .font(.system(.caption).monospacedDigit())
            .foregroundStyle(SL.videoText)
    }
}

/// Lime-filled scrubber with a mark for each key frame underneath.
private struct VideoTimeline: View {
    let project: SkillLabProject
    let playback: PlaybackController
    let selectedFrameId: String?
    let onChoose: (KeyFrame) -> Void

    @State private var wasPlaying = false
    @State private var isScrubbing = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let duration = Swift.max(project.video.duration, 0.01)
            let progress = CGFloat(Swift.min(Swift.max(playback.currentTime / duration, 0), 1))

            ZStack(alignment: .topLeading) {
                Capsule().fill(SL.track).frame(height: 3)
                Capsule().fill(SL.lime).frame(width: width * progress, height: 3)
                Circle()
                    .fill(SL.knob)
                    .frame(width: isScrubbing ? 14 : 10, height: isScrubbing ? 14 : 10)
                    .offset(x: width * progress - (isScrubbing ? 7 : 5), y: isScrubbing ? -5.5 : -3.5)

                ForEach(project.frames) { frame in
                    Button {
                        onChoose(frame)
                    } label: {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(frame.id == selectedFrameId ? SL.lime : SL.mark)
                            .frame(width: 6, height: 6)
                            .frame(width: 22, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: width * CGFloat(frame.timestamp / duration) - 11, y: 6)
                    .accessibilityLabel("Seek to \(frame.label)")
                }
            }
            .frame(height: 24, alignment: .top)
            .contentShape(Rectangle().inset(by: -8))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isScrubbing {
                            isScrubbing = true
                            wasPlaying = playback.isPlaying
                            playback.pause()
                        }
                        let fraction = Swift.min(Swift.max(value.location.x / Swift.max(width, 1), 0), 1)
                        playback.seek(to: Double(fraction) * duration)
                    }
                    .onEnded { _ in
                        isScrubbing = false
                        if wasPlaying { playback.togglePlayback() }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Video time")
            .accessibilityValue(String(format: "%.2f seconds", playback.currentTime))
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 0.5 : -0.5
                playback.seek(to: playback.currentTime + step)
            }
        }
        .frame(height: 24)
    }
}

/// A bare `AVPlayerLayer`, so the workspace can draw its own controls.
struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer?.player = player
        view.playerLayer?.videoGravity = .resizeAspect
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        if view.playerLayer?.player !== player {
            view.playerLayer?.player = player
        }
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }
    }
}

/// The web workspace's small square checkboxes.
struct CheckToggleStyle: ToggleStyle {
    var tint: Color = SL.green
    var dark = false

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(configuration.isOn ? tint : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 3)
                        .stroke(configuration.isOn ? tint : (dark ? Color(hex: "95AA92") : Color(hex: "A9B39F")), lineWidth: 1))
                    .overlay {
                        if configuration.isOn {
                            Image(systemName: "checkmark")
                                .font(.system(.caption2, weight: .heavy))
                                .imageScale(.small)
                                .foregroundStyle(dark ? SL.videoPanel : .white)
                        }
                    }
                    .scaledFrame(width: 13, relativeTo: .caption)
                configuration.label
            }
            .minimumTapArea()
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}
