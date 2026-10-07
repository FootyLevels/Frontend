import PhotosUI
import SwiftUI

/// Root screen: the included example, every uploaded clip, server readiness,
/// and video import — styled after the web workspace's landing page.
struct ProjectsListView: View {
    /// Supplied behind the auth gate to enable log-out.
    var appState: AppStateViewModel?

    @State private var viewModel = ProjectsListViewModel()
    @State private var path: [String] = []
    @State private var pickedVideo: PhotosPickerItem?
    @State private var showServerSettings = false

    /// Server projects, minus the example — that one always opens from the
    /// bundle, so it isn't listed twice when the server has it too.
    private var serverProjects: [SkillLabProject] {
        viewModel.projects.filter { !BundledSample.isSample($0.id) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    intro

                    Button {
                        showServerSettings = true
                    } label: {
                        ServerStatusCard(health: viewModel.health,
                                         isLoading: viewModel.isLoading && viewModel.health == nil,
                                         offlineReason: viewModel.errorMessage)
                    }
                    .buttonStyle(.plain)

                    // When the server is unreachable the status card already
                    // says so; repeating it as an error adds nothing.
                    if let error = viewModel.errorMessage, viewModel.health != nil {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(SL.errorText)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SL.errorFill, in: RoundedRectangle(cornerRadius: 6))
                    }

                    if let sample = BundledSample.project {
                        section("INCLUDED EXAMPLE") {
                            NavigationLink(value: sample.id) {
                                ProjectCard(project: sample, number: 1, isSample: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    section("YOUR PROJECTS") {
                        if serverProjects.isEmpty, !viewModel.isLoading {
                            welcome
                        }
                        ForEach(Array(serverProjects.enumerated()), id: \.element.id) { index, project in
                            NavigationLink(value: project.id) {
                                ProjectCard(project: project, number: index + 2, isSample: false)
                            }
                            .buttonStyle(.plain)
                        }
                        if !serverProjects.isEmpty {
                            addAnother
                        }
                    }

                    footer
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(SL.page)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { projectId in
                ProjectDetailView(projectId: projectId, projectNumber: number(for: projectId))
            }
            .refreshable { await viewModel.refresh() }
            .toolbar { toolbar }
            .overlay { uploadOverlay }
            .sheet(isPresented: $showServerSettings) {
                ServerSettingsView(suggestions: viewModel.health?.network?.urls ?? []) {
                    Task { await viewModel.refresh() }
                }
            }
            .task {
                // With no address yet (a fresh device install) there's nothing to
                // fetch — the example still works, and the status card offers setup.
                if viewModel.isConfigured {
                    await viewModel.refresh()
                }
            }
            .onChange(of: pickedVideo) { _, item in
                guard let item else { return }
                pickedVideo = nil
                Task {
                    if let projectId = await viewModel.upload(item) {
                        path.append(projectId)
                    }
                }
            }
        }
        .tint(SL.green)
    }

    private func number(for projectId: String) -> Int {
        if BundledSample.isSample(projectId) { return 1 }
        return (serverProjects.firstIndex { $0.id == projectId } ?? 0) + 2
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Eyebrow(text: "THE SKILL BREAKDOWN", rule: true)
                Text("/").font(.system(size: 10)).foregroundStyle(Color(hex: "B6BEB0"))
                Eyebrow(text: "FOOTBALL")
            }
            (Text("See the move.\n") + Text("Understand the motion.").foregroundColor(SL.headlineSoft))
                .font(SL.display(34, .semibold))
                .tracking(-1.6)
                .lineSpacing(2)
                .foregroundStyle(SL.ink)
            Text("Slow it down. Find the key moments.\nExplore the body position from every angle.")
                .font(.system(size: 14))
                .lineSpacing(5)
                .foregroundStyle(Color(hex: "77816F"))
        }
        .padding(.top, 12)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: title, color: SL.muted)
            content()
        }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(systemName: "film")
                .font(.system(size: 38, weight: .light))
            Text("Every skill starts with a moment.")
                .font(SL.display(18, .bold))
                .foregroundStyle(Color(hex: "35502D"))
            Text("Import a short skill video — up to 60 seconds — to select frames and build your breakdown.")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "89967B"))
                .multilineTextAlignment(.center)
            importPicker {
                HStack(spacing: 8) {
                    Text("Import a video")
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(.slPrimary)
        }
        .foregroundStyle(Color(hex: "738B5C"))
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(Color(hex: "CAD6BB"), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }

    /// Shown under existing projects. `welcome` disappears after the first
    /// upload, and without this the only way to import another clip is the
    /// toolbar icon, which is easy to miss.
    private var addAnother: some View {
        importPicker {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text("Import another video")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color(hex: "738B5C"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "CAD6BB"), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .opacity(canImport ? 1 : 0.5)
    }

    /// False while an upload is running or the server is unreachable.
    private var canImport: Bool {
        viewModel.uploadPhase == nil && viewModel.health != nil
    }

    /// The video picker behind every import entry point.
    private func importPicker<Content: View>(@ViewBuilder label: () -> Content) -> some View {
        PhotosPicker(selection: $pickedVideo, matching: .videos, label: label)
            .disabled(!canImport)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("SKILL LAB")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(Color(hex: "7C8B6C"))
            Text("Watch closely. Move with intention.")
                .font(.system(size: 11))
            Text("POWERED BY META SAM 3D BODY")
                .font(.system(size: 9))
                .tracking(0.8)
        }
        .foregroundStyle(Color(hex: "98A08C"))
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .overlay(alignment: .top) { Rectangle().fill(SL.line).frame(height: 1) }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            BrandMark(size: 20)
        }
        ToolbarItem(placement: .topBarTrailing) {
            // "plus", not "square.and.arrow.up": the latter reads as Share on iOS.
            importPicker {
                Label("Import video", systemImage: "plus")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showServerSettings = true
            } label: {
                Label("Server", systemImage: "server.rack")
            }
        }
        if let appState {
            ToolbarItem(placement: .topBarLeading) {
                Button(role: .destructive) {
                    try? appState.signOut()
                } label: {
                    Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
    }

    @ViewBuilder
    private var uploadOverlay: some View {
        if let phase = viewModel.uploadPhase {
            VStack(spacing: 14) {
                switch phase {
                case .importing:
                    ProgressView().tint(Color(hex: "EEF5E2"))
                    Text("Preparing video…")
                case .uploading(let fraction):
                    ProgressView(value: fraction)
                        .tint(SL.lime)
                        .frame(width: 180)
                    Text("Uploading \(Int(fraction * 100))%")
                case .processing:
                    ProgressView().tint(Color(hex: "EEF5E2"))
                    Text("Transcoding and picking key frames…")
                    Text("This runs on the server and can take a minute.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "B9C9B0"))
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(Color(hex: "EEF5E2"))
            .padding(24)
            .background(Color(hex: "183D2C"), in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color(hex: "183D2C").opacity(0.3), radius: 20, y: 6)
        }
    }
}

// MARK: - Cards

private struct ProjectCard: View {
    let project: SkillLabProject
    let number: Int
    let isSample: Bool

    var body: some View {
        HStack(spacing: 14) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(String(format: "%02d", number))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(SL.ink)
                        .frame(width: 24, height: 24)
                        .background(Color(hex: "EAF0DF"), in: Circle())
                    if isSample {
                        Text("OFFLINE")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(Color(hex: "63814A"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(hex: "E0EDCD"), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(project.title)
                    .font(SL.display(17, .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(SL.ink)
                    .lineLimit(2)
                Text(String(format: "%.1f SEC  ·  %d KEY FRAMES", project.video.duration, project.frames.count))
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(Color(hex: "7C8578"))
                StatusDot(text: motionText, ready: project.motion?.isPlayable == true)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.right")
                .font(.system(size: 13))
                .foregroundStyle(SL.muted)
        }
        .padding(12)
        .slPanel(fill: SL.card, border: SL.cardBorder, radius: 9)
        .contentShape(RoundedRectangle(cornerRadius: 9))
    }

    private var thumbnail: some View {
        ZStack {
            SL.videoStage
            if let first = project.frames.first {
                AsyncImage(url: try? SkillLabClient.shared.url(for: first.imageUrl)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "film").foregroundStyle(SL.videoMuted)
                }
            } else {
                Image(systemName: "film").foregroundStyle(SL.videoMuted)
            }
        }
        .frame(width: 72, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var motionText: String {
        guard let motion = project.motion else { return "Key frames only" }
        switch motion.status {
        case "complete": return motion.groundAligned == true ? "3D motion · ground aligned" : "3D motion ready"
        case "partial": return "3D motion · partial"
        case "queued", "running": return motion.stage ?? "Reconstructing"
        case "failed": return "Motion failed"
        default: return "Motion \(motion.status)"
        }
    }
}

/// Whether the backend is reachable, and which reconstruction paths it can run.
private struct ServerStatusCard: View {
    let health: SkillLabHealth?
    let isLoading: Bool
    /// Shown when offline — the client's errors say what usually fixes it.
    let offlineReason: String?

    private var address: String {
        ServerSettings.baseURL?.absoluteString ?? "No server address set"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(health != nil ? SL.iconTileText : SL.noticeText)
                .frame(width: 34, height: 34)
                .background(health != nil ? SL.iconTile : SL.noticeFill, in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Eyebrow(text: title, color: Color(hex: "81916F"))
                    Spacer()
                    if let mode = health?.network?.mode {
                        Text(mode.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(SL.muted)
                    }
                }
                if isLoading {
                    Text("Connecting to \(address)…")
                        .font(.system(size: 12))
                        .foregroundStyle(SL.muted)
                } else if let health {
                    Text(address)
                        .font(.system(size: 12))
                        .foregroundStyle(SL.muted)
                    HStack(spacing: 12) {
                        StatusDot(text: "Motion", ready: health.motion.ready)
                        ForEach(health.providers) { provider in
                            StatusDot(text: provider.label, ready: provider.ready)
                        }
                    }
                } else {
                    Text(offlineReason ?? (ServerSettings.baseURL == nil
                                           ? "Connect a Skill Lab server to import videos. The included example works offline."
                                           : "Can't reach \(address)."))
                        .font(.system(size: 12))
                        .lineSpacing(2)
                        .foregroundStyle(Color(hex: "7A8370"))
                    Text("Tap to set the server address.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SL.green)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .slPanel(fill: SL.insight, border: SL.line, radius: 8)
    }

    private var icon: String {
        if isLoading { return "network" }
        return health != nil ? "checkmark.circle" : "exclamationmark.triangle"
    }

    private var title: String {
        if isLoading { return "CONNECTING" }
        return health != nil ? "SERVER CONNECTED" : "SERVER OFFLINE"
    }
}

#Preview {
    ProjectsListView()
}
