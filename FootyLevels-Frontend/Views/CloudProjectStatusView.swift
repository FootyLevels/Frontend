import AVKit
import SwiftUI

/// Owned preparation, durable motion jobs and the existing RealityKit player.
struct CloudProjectStatusView: View {
    @State private var model: CloudProjectViewModel
    @State private var startFrame = 0.0
    @State private var length = 30.0
    @Environment(\.scenePhase) private var scenePhase

    init(project: CloudProject) { _model = State(initialValue: CloudProjectViewModel(project: project)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Label("PRIVATE PROJECT", systemImage: "lock.shield").font(.caption).foregroundStyle(SL.muted)
                Text(model.project.title).font(SL.display(28, .bold))
                if let label = model.project.label { Text(label).foregroundStyle(SL.muted) }
                Text(model.project.statusText).font(.headline)
                if let message = model.errorMessage ?? model.playbackError {
                    Text(message).font(.callout).foregroundStyle(SL.errorText)
                }
                if let message = model.loadingMessage { ProgressView(message).font(.callout) }
                if let prepared = model.preparedPlayback {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOUR VIDEO").font(.caption).foregroundStyle(SL.muted)
                        VideoPlayer(player: prepared.player).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                if let media = model.project.preparedMedia, model.project.state == "ready" { segmentPicker(media) }
                if let job = model.job {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(job.statusText).font(.headline)
                        if job.isActive {
                            Text("You can leave this screen and return later. Generation continues on the team server.")
                                .font(.callout).foregroundStyle(SL.muted)
                            if job.kind != "prepareMedia" {
                                Button("Cancel generation", role: .destructive) { model.cancelGeneration() }.disabled(model.isMutating)
                            }
                        }
                    }
                }
                if let motion = model.motion, let playback = model.playback { motionPlayer(motion, playback) }
                HStack {
                    Button("Refresh status") { Task { await model.refresh() } }.disabled(model.isLoading || model.isMutating)
                    Spacer()
                    Button("Reload playback") { model.reloadPlayback() }.disabled(model.isLoading || model.isMutating)
                }.font(.callout)
                Text("The included example remains available offline in the library.").font(.footnote).foregroundStyle(SL.muted)
            }.padding(22)
        }
        .background(SL.page).navigationTitle("Private project").navigationBarTitleDisplayMode(.inline)
        .task { await model.watch() }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            model.isForeground = phase == .active
            if phase != .active { model.playback?.pause(); model.preparedPlayback?.pause() }
        }
    }

    private func segmentPicker(_ media: CloudPreparedMedia) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CHOOSE YOUR MOTION CLIP").font(.caption).foregroundStyle(SL.muted)
            Text("Select 1–10 seconds from your video.").font(.callout)
            Text("Start: \((startFrame / 30).formatted(.number.precision(.fractionLength(2)))) s").font(.callout.monospacedDigit())
            if media.frameCount > 30 {
                Slider(value: $startFrame, in: 0...Double(media.frameCount - 30), step: 1).accessibilityLabel("Motion clip start")
            }
            Text("Length: \((length / 30).formatted(.number.precision(.fractionLength(2)))) s").font(.callout.monospacedDigit())
            let maximum = Double(min(300, media.frameCount - Int(startFrame)))
            if maximum > 30 {
                Slider(value: $length, in: 30...maximum, step: 1).accessibilityLabel("Motion clip length")
            }
            Button {
                model.preparedPlayback?.pause()
                model.generate(startFrame: Int(startFrame), endFrame: Int(startFrame + length))
            } label: { Label(model.isMutating ? "Submitting…" : "Generate 3D motion", systemImage: "cube") }
                .buttonStyle(.slPrimary).disabled(!model.canGenerate)
        }
        .disabled(model.job?.isActive == true || model.isMutating)
        .onChange(of: startFrame) { _, value in
            length = min(length, Double(media.frameCount) - value)
            model.preparedPlayback?.seek(to: value / 30)
        }
        .onChange(of: media.frameCount, initial: true) { _, count in
            startFrame = min(startFrame, Double(max(0, count - 30)))
            length = min(length, Double(min(300, count - Int(startFrame))))
        }
    }

    private func motionPlayer(_ motion: MotionPlayerViewModel, _ playback: PlaybackController) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR 3D MOTION").font(.caption).foregroundStyle(SL.muted)
            ZStack {
                ModelStageView(root: motion.stageRoot, camera: motion.camera).id(ObjectIdentifier(motion))
                    .accessibilityIdentifier("private-motion-stage").accessibilityValue(motion.accessibilityStatus)
                switch motion.state {
                case .loading(let message): ProgressView(message)
                case .failed(let message): Text(message).font(.callout).foregroundStyle(SL.errorText).padding()
                case .ready: EmptyView()
                }
            }.frame(height: 340).clipped().background(SL.stage)
            if motion.missingPose { Text("Player not reconstructed in this frame").font(.callout).foregroundStyle(SL.noticeText) }
            if motion.waitingForChunk { Text("Loading this frame’s 3D data…").font(.callout).foregroundStyle(SL.muted) }
            if let warning = motion.assetWarning { Text(warning).font(.callout).foregroundStyle(SL.errorText) }
            Text("Source time: \(motion.sourceTime.formatted(.number.precision(.fractionLength(2)))) s")
                .font(.caption.monospacedDigit()).foregroundStyle(SL.muted)
            ScrollView(.horizontal) {
                HStack {
                    ForEach(CameraAngle.allCases) { angle in Button(angle.rawValue) { motion.show(angle) } }
                    Button("Reset camera") { motion.show(.source) }
                }.font(.callout)
            }
            HStack {
                Toggle("Follow", isOn: Binding(get: { motion.follow }, set: { motion.follow = $0 }))
                Toggle("Wireframe", isOn: Binding(get: { motion.wireframe }, set: { motion.wireframe = $0 }))
            }.font(.callout)
            VideoPlayer(player: playback.player).frame(height: 210).clipShape(RoundedRectangle(cornerRadius: 8))
            Picker("Playback speed", selection: Binding(get: { playback.speed }, set: { playback.speed = $0 })) {
                ForEach(PlaybackController.speeds, id: \.self) { speed in Text("\(speed.formatted())×").tag(speed) }
            }.pickerStyle(.segmented)
            Text("Video and 3D playback stay in sync. Drag the model to orbit.").font(.footnote).foregroundStyle(SL.muted)
        }
    }
}
