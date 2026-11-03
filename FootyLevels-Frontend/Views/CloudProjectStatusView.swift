import AVKit
import SwiftUI

/// Owned preparation, durable motion jobs and the existing RealityKit player.
struct CloudProjectStatusView: View {
    @State private var model: CloudProjectViewModel
    @State private var startFrame = 0.0
    @State private var length = 30.0
    @State private var selectedMode = "motion"
    @Environment(\.scenePhase) private var scenePhase

    init(project: CloudProject) { _model = State(initialValue: CloudProjectViewModel(project: project)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Label("PRIVATE PROJECT", systemImage: "lock.shield").font(.caption).foregroundStyle(SL.muted)
                Text(model.project.title).font(SL.display(.title))
                if let label = model.project.label { Text(label).foregroundStyle(SL.muted) }
                if model.project.state == "preparing" {
                    SLLoadingState(title: "Preparing your video…",
                                   detail: "Your upload is complete. Playback and key frames will appear here when ready. You can leave this screen and return later.")
                } else {
                    Text(model.project.statusText).font(.headline)
                }
                if let message = model.errorMessage ?? model.playbackError {
                    Text(message).font(.callout).foregroundStyle(SL.errorText)
                }
                if let message = model.loadingMessage { SLLoadingState(title: message) }
                if let prepared = model.preparedPlayback {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOUR VIDEO").font(.caption).foregroundStyle(SL.muted)
                        VideoPlayer(player: prepared.player).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                if let media = model.project.preparedMedia, model.project.state == "ready" {
                    Picker("Generation type",selection: $selectedMode) {
                        Text("Motion clip").tag("motion"); Text("Selected pose").tag("pose")
                    }.pickerStyle(.segmented).disabled(model.isMutating || model.job?.isActive == true)
                    if selectedMode == "motion" { segmentPicker(media) }
                    else if let prepared = model.preparedPlayback {
                        PrivateKeyframePicker(media: media, playback: prepared, canGenerate: model.canGenerate,
                            checkSession: model.checkPlaybackSession, onGenerate: model.generatePose)
                            .id(ObjectIdentifier(prepared))
                            .disabled(model.isMutating || model.job?.isActive == true)
                    }
                }
                if let job = model.job {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            if job.isActive { SLActivityIndicator() }
                            Text(job.statusText).font(.headline)
                        }
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
                if let pose = model.pose { posePlayer(pose) }
                HStack {
                    Button("Refresh status") { Task { await model.refresh() } }.disabled(model.isLoading || model.isMutating)
                    Spacer()
                    Button("Reload playback") { model.reloadPlayback() }.disabled(model.isLoading || model.isMutating)
                }.font(.callout)
                Text("The included example remains available offline in the library.").font(.footnote).foregroundStyle(SL.muted)
            }.padding(22)
        }
        .background(SL.page).slScreen().navigationTitle("Private project").navigationBarTitleDisplayMode(.inline)
        .task { await model.watch() }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            model.isForeground = phase == .active
            if phase != .active { model.playback?.pause(); model.preparedPlayback?.pause() }
        }
    }

    private func posePlayer(_ pose: PoseInspectorModel) -> some View {
        VStack(alignment: .leading,spacing: 12) {
            Text("YOUR SELECTED 3D POSE").font(.caption).foregroundStyle(SL.muted)
            ScrollView(.horizontal) {
                HStack {
                    ForEach(model.keyframeIndices,id: \.self) { index in
                        Button("\((Double(index)/30).formatted(.number.precision(.fractionLength(2)))) s") { model.selectPose(index) }
                            .buttonStyle(.slSecondary)
                            .accessibilityAddTraits(model.selectedKeyframe == index ? .isSelected : [])
                    }
                }
            }
            ZStack {
                ModelStageView(root: pose.stageRoot,camera: pose.camera).id(ObjectIdentifier(pose))
                    .accessibilityIdentifier("private-pose-stage")
                    .accessibilityValue(pose.isLoading ? "Loading" : pose.missingPose ? "Missing pose" : pose.stageRoot == nil ? "Unavailable" : "Ready")
                if pose.isLoading { SLLoadingState(title: "Loading selected pose…").padding(20) }
                if pose.missingPose { Text("Player not reconstructed at this moment").font(.callout) }
                if let error = pose.errorMessage { Text(error).foregroundStyle(SL.errorText).font(.callout).padding() }
            }.frame(height: 340).clipped().background(SL.stage)
            if let index = model.selectedKeyframe {
                Text("Source time: \((Double(index)/30).formatted(.number.precision(.fractionLength(2)))) s")
                    .font(.caption.monospacedDigit()).foregroundStyle(SL.muted)
            }
            ScrollView(.horizontal) { HStack { ForEach(CameraAngle.allCases) { angle in Button(angle.rawValue) { pose.show(angle) } } } }
            HStack {
                Toggle("Wireframe",isOn: Binding(get: { pose.wireframe },set: { pose.wireframe = $0 }))
                Toggle("Rotate",isOn: Binding(get: { pose.autoRotate },set: { pose.autoRotate = $0 }))
            }.font(.callout)
            Text("Selecting a pose pauses the source video at that moment. Drag the model to orbit.").font(.footnote).foregroundStyle(SL.muted)
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
                case .loading(let message): SLLoadingState(title: message).padding(20)
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
