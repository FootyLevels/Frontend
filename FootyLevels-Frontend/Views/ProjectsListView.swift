import PhotosUI
import SwiftUI

/// Root screen: the included example, every uploaded clip, server readiness,
/// and video import — styled after the web workspace's landing page.
struct ProjectsListView: View {
    /// Supplied behind the auth gate to enable log-out.
    var appState: AppStateViewModel?
    /// Owned by the tab bar, so a video imported on another tab shows up here.
    let viewModel: ProjectsListViewModel

    @State private var cloud = CloudUploadsViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showCamera = false
    @State private var recordedFile: URL?
    @State private var requestingCamera = false
    @State private var cameraError: String?
    private var hasAccount: Bool { appState?.isLoggedIn == .loggedIn }
    @State private var path = NavigationPath()
    @State private var pickedVideo: PhotosPickerItem?
    @State private var showServerSettings = false
    /// Set by "Delete Video…"; non-nil while the confirmation dialog is up.
    @State private var pendingDelete: SkillLabProject?
    @State private var deletionTarget: CloudProject?

    private var isWatchingPrivateProjects: Bool {
        hasAccount && scenePhase == .active
    }

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

                    if let error = appState?.accountError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error).font(.callout)
                            Button("Retry account connection") {
                                Task { await appState?.connectAccount() }
                            }
                        }
                        .foregroundStyle(SL.errorText)
                    }

                    if !hasAccount {
                        Button {
                            showServerSettings = true
                    } label: {
                        ServerStatusCard(health: viewModel.health,
                                         isLoading: viewModel.isLoading && viewModel.health == nil,
                                         offlineReason: viewModel.errorMessage)
                    }
                    .buttonStyle(.plain)

                    }

                    // When the server is unreachable the status card already
                    // says so; repeating it as an error adds nothing.
                    if !hasAccount, let error = viewModel.errorMessage, viewModel.health != nil {
                        Text(error)
                            .font(.system(.footnote))
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

                    if hasAccount {
                        privateProjects
                    } else {
                        legacyProjects
                    }

                    footer
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(SL.page)
            .slScreen()
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { projectId in
                ProjectDetailView(projectId: projectId, projectNumber: number(for: projectId))
            }
            .navigationDestination(for: CloudProject.self) { CloudProjectStatusView(project: $0) }
            .refreshable { if hasAccount { await cloud.refresh() } else { await viewModel.refresh() } }
            .toolbar { toolbar }
            .overlay { uploadOverlay }
            .sheet(isPresented: $showServerSettings) {
                ServerSettingsView(suggestions: viewModel.health?.network?.urls ?? []) {
                    Task { await viewModel.refresh() }
                }
            }
            .confirmationDialog("Delete this video?", isPresented: isConfirmingDelete,
                                titleVisibility: .visible, presenting: pendingDelete) { project in
                Button("Delete Video", role: .destructive) {
                    Task { await viewModel.delete(project) }
                }
            } message: { project in
                Text("“\(project.title)” and its key frames and 3D results will be removed from the server. This can't be undone.")
            }
            .sheet(item: Binding(get: { cloud.pending }, set: { if $0 == nil { cloud.cancelEditor() } })) { clip in
                ClipImportEditor(clip: clip, onCancel: { cloud.cancelEditor() }) { title, label, start, end in
                    cloud.submit(title: title, label: label, start: start, end: end)
                }
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: {
                if let file = recordedFile { recordedFile = nil; cloud.importCamera(file) }
            }) {
                VideoRecordingPicker(onCancel: { showCamera = false }, onRecorded: { file in
                    showCamera = false
                    recordedFile = file
                }, onError: { message in showCamera = false; cameraError = message })
                .ignoresSafeArea()
            }
            .alert("Recording unavailable", isPresented: Binding(get: { cameraError != nil }, set: { if !$0 { cameraError = nil } })) {
                Button("OK", role: .cancel) { cameraError = nil }
            } message: { Text(cameraError ?? "") }
            .confirmationDialog("Delete recording?", isPresented: Binding(
                get: { deletionTarget != nil }, set: { if !$0 { deletionTarget = nil } }),
                titleVisibility: .visible, presenting: deletionTarget) { project in
                Button("Delete recording", role: .destructive) { cloud.delete(project); deletionTarget = nil }
                Button("Cancel", role: .cancel) { deletionTarget = nil }
            } message: { project in
                Text("Remove \(project.title) and its 3D results from your library? Stored files are cleared after outstanding links expire.")
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { cloud.pause() }
                else if hasAccount, !showCamera, !requestingCamera { Task { await cloud.refresh() } }
            }
            .onDisappear { cloud.pause(); cloud.cancelEditor() }
            .task {
                if hasAccount { await appState?.connectAccount(); cloud.configure(); await cloud.refresh(); return }
                // With no address yet (a fresh device install) there's nothing to
                // fetch — the example still works, and the status card offers setup.
                if viewModel.isConfigured {
                    await viewModel.refresh()
                }
            }
            .task(id: isWatchingPrivateProjects) {
                await watchPreparingProjects()
            }
            .onChange(of: pickedVideo) { _, item in
                guard let item else { return }
                pickedVideo = nil
                if hasAccount { cloud.importGallery(item); return }
                Task {
                    if let projectId = await viewModel.upload(item) {
                        path.append(projectId)
                    }
                }
            }
        }
        .tint(SL.tint)
    }

    private func watchPreparingProjects() async {
        guard isWatchingPrivateProjects else { return }
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(12)) }
            catch { return }
            guard !Task.isCancelled else { return }
            if showCamera || requestingCamera { continue }
            if cloud.pending != nil { continue }
            await cloud.refreshPreparingProjects()
        }
    }

    private var legacyProjects: some View {
        section("YOUR PROJECTS") {
            if serverProjects.isEmpty, !viewModel.isLoading {
                welcome
            }
            ForEach(Array(serverProjects.enumerated()), id: \.element.id) { index, project in
                serverProjectCard(project, number: index + 2)
            }
            if !serverProjects.isEmpty {
                addAnother
            }
        }
    }

    private func serverProjectCard(_ project: SkillLabProject, number: Int) -> some View {
        let isDeleting = viewModel.deletingId == project.id
        return NavigationLink(value: project.id) {
            ProjectCard(project: project, number: number, isSample: false)
        }
        .buttonStyle(.plain)
        .opacity(isDeleting ? 0.5 : 1)
        .disabled(isDeleting)
        .overlay(alignment: .topTrailing) { projectMenu(for: project, isDeleting: isDeleting) }
        .contextMenu { deleteButton(for: project) }
    }

    private var privateProjects: some View {
        section("YOUR PRIVATE PROJECTS") {
            if let error = cloud.errorMessage {
                Text(error).font(.callout).foregroundStyle(SL.errorText)
            }
            if ApplicationEnvironment.apiBaseURL == nil {
                Text("Private uploads need the account API connection. The included example is available on this page.")
                    .font(.callout).foregroundStyle(SL.muted)
            }
            if cloud.isLoading && cloud.projects.isEmpty && cloud.drafts.isEmpty {
                SLLoadingState(title: "Loading your videos…", detail: "Finding the clips saved to your account.")
            }
            if !cloud.isLoading && cloud.projects.isEmpty && cloud.drafts.isEmpty && cloud.errorMessage == nil {
                Label("Your next attempt starts here", systemImage: "video.badge.plus")
                    .font(.headline).foregroundStyle(SL.ink)
                Text("Import or record a clip. Your videos are private until you choose to share them.")
                    .font(.callout).foregroundStyle(SL.muted)
            }
            ForEach(cloud.drafts) { draft in
                VStack(alignment: .leading, spacing: 10) {
                    Text(draft.title).font(.headline)
                    Text(draft.discarding ? "Removal waiting to complete" : "Saved on this device · upload unfinished")
                        .font(.caption).foregroundStyle(SL.muted)
                    HStack {
                        Button(draft.discarding ? "Retry removal" : "Resume") { cloud.resume(draft) }
                        if !draft.discarding {
                            Button("Discard", role: .destructive) { cloud.discard(draft) }
                        }
                    }.disabled(cloud.isBusy || cloud.isLoading)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .slPanel()
            }
            ForEach(cloud.projects.filter { project in !cloud.drafts.contains(where: { $0.projectId == project.id }) }) { project in
                privateProjectCard(project)
            }
            if !cloud.deletions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("REMOVAL STATUS").font(.caption.bold())
                    ForEach(cloud.deletions) { removal in
                        Text(removal.statusText).font(.callout).foregroundStyle(SL.muted)
                    }
                    Button("Check removal status") { Task { await cloud.refresh() } }
                        .disabled(cloud.isBusy || cloud.isLoading)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(SL.page, in: RoundedRectangle(cornerRadius: 12))
            }
            if cloud.hasMore { Button("Load more projects") { Task { await cloud.refresh(more: true) } }.disabled(cloud.isBusy || cloud.isLoading) }
            importPicker { Label(cloud.projects.isEmpty ? "Import a video" : "Import another video", systemImage: "photo.on.rectangle") }
                .buttonStyle(.slPrimaryWide)
            Button {
                requestingCamera = true
                Task {
                    defer { requestingCamera = false }
                    cameraError = await VideoRecordingPicker.permissionError()
                    if cameraError == nil { showCamera = true }
                }
            } label: {
                HStack {
                    if requestingCamera { SLActivityIndicator() }
                    Label(requestingCamera ? "Opening camera…" : "Record a video", systemImage: "video")
                }.frame(maxWidth: .infinity)
            }
                .buttonStyle(.slSecondary)
                .disabled(!canImport).accessibilityIdentifier("recordPrivateVideo")
        }
    }

    private func privateProjectCard(_ project: CloudProject) -> some View {
        HStack(spacing: 8) {
            NavigationLink(value: project) {
                HStack(spacing: 14) {
                    Group {
                        if project.state == "preparing" { SLActivityIndicator(size: 22) }
                        else { Image(systemName: "lock.fill").foregroundStyle(SL.green) }
                    }
                    .scaledFrame(width: 42, height: 48)
                    .background(SL.iconTile, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(project.title).font(.headline).foregroundStyle(SL.ink)
                        Text(project.state == "preparing" ? "Preparing your video…" : project.statusText)
                            .font(.subheadline).foregroundStyle(project.state == "rejected" ? SL.errorText : SL.muted)
                        if project.state == "preparing" {
                            Text("Upload complete. Playback and key frames are next.")
                                .font(.caption).foregroundStyle(SL.muted)
                        }
                        if let label = project.label { Text(label).font(.caption).foregroundStyle(SL.muted) }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(SL.muted)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button(role: .destructive) { deletionTarget = project } label: {
                Image(systemName: "trash").frame(width: 44, height: 44)
            }
            .tint(SL.errorText)
            .accessibilityLabel("Delete \(project.title)")
            .disabled(cloud.isBusy || cloud.isLoading)
        }.padding(14).slPanel()
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
                Text("/").font(.system(.caption2)).foregroundStyle(SL.muted)
                Eyebrow(text: "FOOTBALL")
            }
            Text("See the move.\n\(Text("Understand the motion.").foregroundStyle(SL.headlineSoft))")
                .font(SL.display(.largeTitle))
                .tracking(-1.6)
                .lineSpacing(2)
                .foregroundStyle(SL.ink)
            Text("Slow it down. Find the key moments.\nExplore the body position from every angle.")
                .font(.system(.subheadline))
                .lineSpacing(5)
                .foregroundStyle(SL.muted)
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
                .font(.system(.largeTitle, weight: .light))
            Text("Every skill starts with a moment.")
                .font(SL.display(.title3))
                .foregroundStyle(SL.presetActiveText)
            Text("Import a short skill video — up to 60 seconds — to select frames and build your breakdown.")
                .font(.system(.footnote))
                .foregroundStyle(SL.muted)
                .multilineTextAlignment(.center)
            importPicker {
                HStack(spacing: 8) {
                    Text("Import a video")
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(.slPrimary)
        }
        .foregroundStyle(SL.green)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(SL.panelBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
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
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(SL.green)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(SL.panelBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .opacity(canImport ? 1 : 0.5)
    }

    /// False while an upload is running or the server is unreachable.
    private var canImport: Bool {
        hasAccount ? (!cloud.isBusy && !cloud.isLoading && !requestingCamera && cloud.pending == nil && cloud.isConfigured) : (viewModel.uploadPhase == nil && viewModel.health != nil)
    }

    /// The video picker behind every import entry point.
    private func importPicker<Content: View>(@ViewBuilder label: () -> Content) -> some View {
        PhotosPicker(selection: $pickedVideo, matching: .videos, label: label)
            .disabled(!canImport)
    }

    // MARK: - Deleting

    /// A visible "…" button on each of the person's cards, so deleting doesn't
    /// depend on discovering the long-press menu.
    private func projectMenu(for project: SkillLabProject, isDeleting: Bool) -> some View {
        Menu {
            deleteButton(for: project)
        } label: {
            Group {
                if isDeleting {
                    SLActivityIndicator()
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(SL.muted)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("More actions for \(project.title)")
    }

    private func deleteButton(for project: SkillLabProject) -> some View {
        Button(role: .destructive) {
            pendingDelete = project
        } label: {
            Label("Delete Video…", systemImage: "trash")
        }
        // The server also refuses a busy or bundled project; offline, the error
        // couldn't be shown (the status card replaces it), so don't offer it.
        .disabled(!viewModel.canDelete(project) || viewModel.health == nil)
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("FOOTYLEVELS")
                .font(.system(.caption2, weight: .bold))
                .tracking(2)
                .foregroundStyle(SL.muted)
            Text("Watch closely. Move with intention.")
                .font(.system(.caption2))
            Text("POWERED BY META SAM 3D BODY")
                .font(.system(.caption2))
                .tracking(0.8)
        }
        .foregroundStyle(SL.muted)
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
        if !hasAccount {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showServerSettings = true
            } label: {
                Label("Server", systemImage: "server.rack")
            }
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
        if hasAccount, let phase = cloud.phase {
            VStack(spacing: 18) {
                SLActivityIndicator(size: 28)
                Text(phase).font(.headline).multilineTextAlignment(.center)
                if let progress = cloud.progress {
                    ProgressView(value: progress).tint(SL.tint)
                    Text("\(Int(progress * 100))%").font(.subheadline.monospacedDigit())
                }
                if cloud.progress != nil {
                    Text("Your draft is saved. You can pause this upload and resume it later.")
                        .font(.footnote).foregroundStyle(SL.muted).multilineTextAlignment(.center)
                    Button("Pause upload") { cloud.pause() }.buttonStyle(.slSecondary).accessibilityIdentifier("pausePrivateUpload")
                } else {
                    Text("Please keep the app open while this step completes.")
                        .font(.footnote).foregroundStyle(SL.muted).multilineTextAlignment(.center)
                }
            }
            .padding(24).frame(maxWidth: 300).slPanel(fill: SL.header, radius: 20)
            .shadow(color: SL.green.opacity(0.16), radius: 24, y: 8)
        } else {
            UploadProgressOverlay(phase: viewModel.uploadPhase)
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
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(SL.ink)
                        .scaledFrame(width: 24, relativeTo: .caption2)
                        .background(SL.iconTile, in: Circle())
                    if isSample {
                        Text("OFFLINE")
                            .font(.system(.caption2, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(SL.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(SL.tick, in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(project.title)
                    .font(SL.display(.body))
                    .tracking(-0.5)
                    .foregroundStyle(SL.ink)
                    .lineLimit(2)
                Text(String(format: "%.1f SEC  ·  %d KEY FRAMES", project.video.duration, project.frames.count))
                    .font(.system(.caption2, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(SL.muted)
                StatusDot(text: motionText, ready: project.motion?.isPlayable == true)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.right")
                .font(.system(.footnote))
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
                .font(.system(.callout))
                .foregroundStyle(health != nil ? SL.iconTileText : SL.noticeText)
                .scaledFrame(width: 34, relativeTo: .callout)
                .background(health != nil ? SL.iconTile : SL.noticeFill, in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Eyebrow(text: title, color: SL.muted)
                    Spacer()
                    if let mode = health?.network?.mode {
                        Text(mode.uppercased())
                            .font(.system(.caption2, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(SL.muted)
                    }
                }
                if isLoading {
                    Text("Connecting to \(address)…")
                        .font(.system(.caption))
                        .foregroundStyle(SL.muted)
                } else if let health {
                    Text(address)
                        .font(.system(.caption))
                        .foregroundStyle(SL.muted)
                    HStack(spacing: 12) {
                        StatusDot(text: "Motion", ready: health.motion.ready)
                        ForEach(health.providers) { provider in
                            StatusDot(text: provider.label, ready: provider.ready)
                        }
                    }
                } else {
                    Text(offlineReason ?? (ServerSettings.baseURL == nil
                                           ? "Connect a FootyLevels server to import videos. The included example works offline."
                                           : "Can't reach \(address)."))
                        .font(.system(.caption))
                        .lineSpacing(2)
                        .foregroundStyle(SL.muted)
                    Text("Tap to set the server address.")
                        .font(.system(.caption2, weight: .medium))
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
    ProjectsListView(viewModel: ProjectsListViewModel())
}
