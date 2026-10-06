import SwiftUI

/// One clip's workspace, laid out like the web viewer: the source video, a 3D
/// inspector for the whole motion or a single key frame, then the key-frame
/// strip and the reconstruction pipeline.
struct ProjectDetailView: View {
    var projectNumber = 1

    @State private var viewModel: ProjectDetailViewModel
    @State private var playback: PlaybackController?
    @State private var motion: MotionPlayerViewModel?
    @State private var pose = PoseInspectorModel()
    @State private var showCrop = false
    @State private var showPipeline = false
    @State private var confirmRemove = false

    init(projectId: String, projectNumber: Int = 1) {
        self.projectNumber = projectNumber
        _viewModel = State(initialValue: ProjectDetailViewModel(projectId: projectId))
    }

    var body: some View {
        Group {
            if let project = viewModel.project, let playback {
                workspace(project, playback: playback)
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView("Couldn't load project", systemImage: "exclamationmark.triangle",
                                       description: Text(error))
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Opening your workspace…")
                        .font(.system(size: 13))
                        .foregroundStyle(SL.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(SL.page)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                BrandMark(size: 17)
            }
            if !viewModel.isSample {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refreshHealth() }
                        showPipeline = true
                    } label: {
                        Label("Pipeline", systemImage: "slider.horizontal.3")
                    }
                }
            }
        }
        .task { await viewModel.load() }
        // Build the player once the video is known, and the motion inspector
        // once a sequence exists — or changes, after a re-run.
        .task(id: viewModel.project?.video.url) { preparePlayback() }
        .task(id: motionKey) { await prepareMotion() }
        .task(id: poseKey) { await pose.show(meshPath: viewModel.mode == .frames ? viewModel.selectedFrame?.meshUrl : nil) }
        .onDisappear {
            viewModel.stopPolling()
            motion?.teardown()
            playback?.teardown()
        }
        .sheet(isPresented: $showCrop) {
            if let project = viewModel.project, let frame = viewModel.selectedFrame {
                CropEditorView(frame: frame, aspectRatio: project.video.aspectRatio) { box in
                    pose.invalidate()
                    return await viewModel.updateBox(frameId: frame.id, bbox: box)
                }
            }
        }
        .sheet(isPresented: $showPipeline) {
            PipelineSettingsView(viewModel: viewModel)
        }
        .confirmationDialog("Remove this key frame?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                guard let id = viewModel.selectedFrame?.id else { return }
                Task { _ = await viewModel.deleteFrame(id) }
            }
        }
    }

    private var motionKey: String? {
        guard playback != nil, let motion = viewModel.project?.motion, motion.isPlayable else { return nil }
        return motion.sequenceUrl
    }

    private var poseKey: String {
        "\(viewModel.mode.rawValue)|\(viewModel.selectedFrame?.meshUrl ?? "-")"
    }

    // MARK: - Layout

    private func workspace(_ project: SkillLabProject, playback: PlaybackController) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heading(project)

                if let error = viewModel.errorMessage {
                    errorBanner(error)
                }

                modeSwitch

                WorkspaceVideoPanel(project: project, playback: playback,
                                    selectedFrameId: viewModel.mode == .frames ? viewModel.selectedFrame?.id : nil,
                                    canCapture: viewModel.canEdit && project.frames.count < 24,
                                    onCapture: { seconds in Task { await viewModel.addFrame(at: seconds) } },
                                    onChoose: choose)

                inspector(project)

                InsightCard(mode: viewModel.mode, project: project, frame: viewModel.selectedFrame,
                            frameNumber: viewModel.selectedIndex + 1,
                            canSelectPlayer: viewModel.canEdit,
                            onSelectPlayer: { showCrop = true })

                KeyFramesSection(project: project,
                                 selectedFrameId: viewModel.mode == .frames ? viewModel.selectedFrame?.id : nil,
                                 onChoose: choose)
                    .padding(.top, 8)

                PipelineBar(project: project, readyCount: viewModel.readyFrameCount,
                            isRunning: viewModel.isRunning, isSample: viewModel.isSample,
                            providerReady: viewModel.selectedProvider != nil,
                            busy: viewModel.isSubmitting,
                            onGenerate: { Task { await viewModel.generateMeshes() } },
                            onConnect: { showPipeline = true })

                WorkspaceFootnote(canRemove: viewModel.canEdit && project.frames.count >= 2) {
                    confirmRemove = true
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .refreshable {
            await viewModel.refresh()
            if !viewModel.isSample { await viewModel.refreshHealth() }
        }
        .overlay(alignment: .bottom) {
            if viewModel.isSubmitting {
                Label("Working on your video…", systemImage: "hourglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "EEF5E2"))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 13)
                    .background(Color(hex: "183D2C"), in: RoundedRectangle(cornerRadius: 7))
                    .shadow(color: Color(hex: "183D2C").opacity(0.27), radius: 12, y: 4)
                    .padding(.bottom, 24)
            }
        }
    }

    private func heading(_ project: SkillLabProject) -> some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", projectNumber))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SL.ink)
                .frame(width: 38, height: 38)
                .background(Color(hex: "EAF0DF"), in: Circle())
                .overlay(Circle().stroke(Color(hex: "DCE5CD")))
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(SL.display(19, .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(SL.ink)
                    .lineLimit(1)
                Text(String(format: "%.1f SEC  ·  %.0f FPS  ·  %d KEY FRAMES",
                            project.video.duration, project.video.fps, project.frames.count))
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.1)
                    .foregroundStyle(Color(hex: "7C8578"))
            }
            Spacer()
            Label(viewModel.isSample ? "Included example" : "Saved on server",
                  systemImage: viewModel.isSample ? "shippingbox" : "checkmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "809073"))
                .labelStyle(.iconOnly)
                .accessibilityLabel(viewModel.isSample ? "Included example" : "Saved on server")
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(SL.line).frame(height: 1) }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top) {
            Text(message)
            Spacer()
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Dismiss error")
        }
        .font(.system(size: 13))
        .foregroundStyle(SL.errorText)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(SL.errorFill, in: RoundedRectangle(cornerRadius: 6))
    }

    private var modeSwitch: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 3) {
                ForEach(ProjectDetailViewModel.Mode.allCases) { mode in
                    Button {
                        viewModel.mode = mode
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 13, weight: viewModel.mode == mode ? .semibold : .regular))
                            .foregroundStyle(viewModel.mode == mode ? Color(hex: "F1F6E9") : SL.modeText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(viewModel.mode == mode ? SL.greenActive : .clear,
                                        in: RoundedRectangle(cornerRadius: 5))
                            .shadow(color: viewModel.mode == mode ? Color(hex: "173A22").opacity(0.12) : .clear,
                                    radius: 3, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(viewModel.mode == mode ? .isSelected : [])
                }
            }
            .padding(4)
            .slPanel(fill: SL.modeTrack, border: SL.modeBorder, radius: 8)

            Text(viewModel.mode == .motion ? "Player + football · synchronized playback"
                                           : "Freeze a moment. Explore every angle.")
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "819174"))
        }
    }

    @ViewBuilder
    private func inspector(_ project: SkillLabProject) -> some View {
        switch viewModel.mode {
        case .motion:
            MotionInspectorPanel(project: project, model: motion,
                                 canGenerate: viewModel.canGenerateMotion,
                                 blocker: viewModel.motionBlocker,
                                 onGenerate: { Task { await viewModel.startMotion() } })
        case .frames:
            if let frame = viewModel.selectedFrame {
                PoseInspectorPanel(frame: frame, model: pose,
                                   canGenerate: viewModel.canEdit && viewModel.selectedProvider != nil,
                                   blocker: frameBlocker,
                                   onGenerate: { Task { await viewModel.generateMeshes(frameIds: [frame.id]) } })
            }
        }
    }

    private var frameBlocker: String? {
        if viewModel.isSample { return "The included example is read-only." }
        if viewModel.selectedProvider == nil { return "Connect the GPU worker in Pipeline settings." }
        if viewModel.isRunning { return "Wait for the current job to finish." }
        return nil
    }

    // MARK: - Actions

    /// Selecting a key frame freezes the video on it and shows its pose.
    private func choose(_ frame: KeyFrame) {
        viewModel.mode = .frames
        viewModel.selectedFrameId = frame.id
        playback?.pause()
        playback?.seek(to: frame.timestamp)
    }

    private func preparePlayback() {
        guard playback == nil, let project = viewModel.project,
              let url = try? SkillLabClient.shared.url(for: project.video.url) else { return }
        playback = PlaybackController(url: url, duration: project.video.duration)
    }

    private func prepareMotion() async {
        guard let playback, let project = viewModel.project,
              let motionState = project.motion, motionState.isPlayable,
              let path = motionState.sequenceUrl else { return }
        motion?.teardown()
        let model = MotionPlayerViewModel(projectId: project.id, sequencePath: path, player: playback.player)
        motion = model
        await model.load()
    }
}

#Preview("The over fake") {
    NavigationStack {
        ProjectDetailView(projectId: BundledSample.id)
    }
}
