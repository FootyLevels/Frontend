import PhotosUI
import SwiftUI

/// The "Overlay" tab: choose two videos — yours and a reference — build their
/// 3D motion if needed, then open both bodies in one scene.
struct OverlayDifferenceView: View {
    let library: ProjectsListViewModel

    @State private var viewModel = OverlayDifferenceViewModel()
    @State private var picking: OverlaySlot?
    /// Owned here rather than by the comparison screen, so switching tabs
    /// only pauses it; it's released when the screen is closed.
    @State private var comparison: ComparisonModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    intro

                    if let error = viewModel.errorMessage {
                        Label {
                            Text(error)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.circle.fill")
                        }
                        .font(.system(.footnote))
                        .foregroundStyle(SL.errorText)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SL.errorFill, in: RoundedRectangle(cornerRadius: 9))
                    }

                    VStack(spacing: 12) {
                        ForEach(OverlaySlot.allCases) { slot in
                            OverlaySlotCard(slot: slot,
                                            project: viewModel.project(in: slot),
                                            isStarting: viewModel.startingId != nil
                                                && viewModel.startingId == viewModel.project(in: slot)?.id,
                                            canBuild: viewModel.project(in: slot).map(viewModel.canBuildMotion) ?? false,
                                            onChoose: { picking = slot },
                                            onBuild: { Task { await viewModel.buildMotion(for: slot) } })
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Button(action: openComparison) {
                            Label("Compare in 3D", systemImage: "square.2.layers.3d")
                        }
                        .buttonStyle(.slPrimaryWide)
                        .disabled(!viewModel.canCompare)

                        Text(comparisonGuidance)
                            .font(.system(.footnote))
                            .lineSpacing(3)
                            .foregroundStyle(SL.panelToplineText)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(SL.page)
            .slScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    BrandMark(size: 20)
                }
            }
            .navigationDestination(isPresented: isComparing) {
                if let comparison {
                    ComparisonView(model: comparison)
                }
            }
            .sheet(item: $picking) { slot in
                OverlayVideoPicker(library: library, slot: slot) { project in
                    viewModel.choose(project, for: slot)
                }
            }
            .overlay { UploadProgressOverlay(phase: library.uploadPhase) }
            .task {
                if library.isConfigured, library.health == nil {
                    await library.refresh()
                }
            }
            .task(id: viewModel.pollKey) { await viewModel.pollWhileBuilding() }
        }
        .tint(SL.green)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: "COMPARE YOUR MOVEMENT", rule: true)
            Text("Two attempts.\n\(Text("See what changes.").foregroundStyle(SL.headlineSoft))")
                .font(SL.display(.largeTitle, .semibold))
                .tracking(-1.4)
                .foregroundStyle(SL.ink)
            Text("Choose your attempt and a reference. See their 3D movements together, then explore where they differ.")
                .font(.system(.subheadline))
                .lineSpacing(4)
                .foregroundStyle(SL.panelToplineText)
        }
        .padding(.top, 12)
    }

    private var isComparing: Binding<Bool> {
        Binding(get: { comparison != nil }, set: { if !$0 { closeComparison() } })
    }

    private var comparisonGuidance: String {
        if viewModel.canCompare {
            return "Both videos are ready. Start with the bodies overlaid, or switch to side by side in the comparison."
        }
        let missing = OverlaySlot.allCases.filter { viewModel.project(in: $0) == nil }
        if missing.count == 2 {
            return "Choose a video for A and B to get started. You can use the same video in both slots."
        }
        if let slot = missing.first {
            return "Choose video \(slot.rawValue) next, then prepare any 3D motion that is missing."
        }
        if viewModel.startingId != nil || OverlaySlot.allCases.contains(where: { viewModel.project(in: $0)?.isBusy == true }) {
            return "Preparing 3D motion. Your comparison will be ready when both videos finish."
        }
        return "Build the missing 3D motion above to open your comparison."
    }

    private func openComparison() {
        guard let first = viewModel.project(in: .first), let second = viewModel.project(in: .second) else { return }
        do {
            comparison = try ComparisonModel(first: first, second: second)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func closeComparison() {
        comparison?.teardown()
        comparison = nil
    }
}

extension OverlaySlot {
    var color: Color { Color(uiColor: self == .first ? SL.overlayFirst : SL.overlaySecond) }
}

/// The lettered swatch that ties a video to its body in the scene.
struct OverlaySlotBadge: View {
    let slot: OverlaySlot
    var size: CGFloat = 30

    var body: some View {
        Text(slot.rawValue)
            .font(.system(size: size * 0.43, weight: .bold))
            .foregroundStyle(slot == .first ? Color.white : SL.videoStage)
            .frame(width: size, height: size)
            .background(slot.color, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Slot card

private struct OverlaySlotCard: View {
    let slot: OverlaySlot
    let project: SkillLabProject?
    let isStarting: Bool
    let canBuild: Bool
    let onChoose: () -> Void
    let onBuild: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                OverlaySlotBadge(slot: slot)
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "\(slot.rawValue) · \(slot.role.uppercased())", color: SL.panelToplineText)
                    Text(project?.title ?? (slot == .first ? "Your attempt" : "Reference video"))
                        .font(SL.display(.body, .heavy))
                        .tracking(-0.5)
                        .foregroundStyle(SL.ink)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Button(project == nil ? "Choose" : "Change", action: onChoose)
                    .buttonStyle(.slSecondary)
                    .accessibilityLabel(project == nil ? "Choose video \(slot.rawValue)" : "Change video \(slot.rawValue)")
            }

            if let project {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 8) {
                        if isStarting || project.isBusy {
                            SLActivityIndicator(size: 16)
                        } else {
                            Image(systemName: project.motion?.isPlayable == true ? "checkmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(project.motion?.isPlayable == true ? SL.readyDot : SL.panelToplineText)
                                .accessibilityHidden(true)
                        }
                        Text(isStarting ? "Starting 3D motion…" : motionText(project))
                            .font(.system(.footnote, weight: .medium))
                            .foregroundStyle(project.motion?.status == "failed" ? SL.errorText : SL.panelToplineText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if isStarting || project.isBusy {
                        Text("Your video stays selected while its 3D motion is prepared.")
                            .font(.system(.caption))
                            .foregroundStyle(SL.panelToplineText)
                    } else if canBuild {
                        Button(action: onBuild) {
                            Label(project.motion?.status == "failed" ? "Try 3D motion again" : "Build 3D motion", systemImage: "waveform.path.ecg")
                        }
                        .buttonStyle(.slPrimary)
                    }
                }
            } else {
                Text("Choose a video from your library or import a new attempt.")
                    .font(.system(.footnote))
                    .foregroundStyle(SL.panelToplineText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .slPanel(fill: SL.card, border: SL.cardBorder, radius: 9)
    }

    private func motionText(_ project: SkillLabProject) -> String {
        guard let motion = project.motion else { return project.isBusy ? "Preparing 3D…" : "3D motion needs to be built" }
        switch motion.status {
        case "complete": return "3D motion ready"
        case "partial": return "3D motion ready · some frames missing"
        case "queued": return "3D motion is queued"
        case "running": return "Building 3D motion…"
        case "failed": return motion.error ?? "3D motion failed"
        default: return "3D motion \(motion.status)"
        }
    }
}

// MARK: - Picker

/// Every video in the library, plus importing a new one straight into a slot.
private struct OverlayVideoPicker: View {
    let library: ProjectsListViewModel
    let slot: OverlaySlot
    let onPick: (SkillLabProject) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pickedVideo: PhotosPickerItem?

    private var videos: [SkillLabProject] {
        [BundledSample.project].compactMap { $0 } + library.projects.filter { !BundledSample.isSample($0.id) }
    }

    private var canImport: Bool { library.uploadPhase == nil && library.health != nil }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PhotosPicker(selection: $pickedVideo, matching: .videos) {
                        Label("Import a new video", systemImage: "plus")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(SL.green)
                    }
                    .disabled(!canImport)
                    .listRowBackground(SL.card)
                } footer: {
                    if library.health == nil, !library.isLoading {
                        Text("Connect to the server on the Videos tab to import. The included example works offline.")
                            .foregroundStyle(SL.panelToplineText)
                    }
                }

                Section("Your videos") {
                    if library.isLoading {
                        SLLoadingState(title: "Loading your library",
                                       detail: BundledSample.project == nil ? nil : "You can choose the included example while your videos load.")
                            .listRowBackground(SL.card)
                    } else if videos.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("No videos yet", systemImage: "video")
                                .font(.system(.subheadline, weight: .semibold))
                                .foregroundStyle(SL.ink)
                            Text(canImport ? "Import a clip above to choose your first attempt." : "Connect on the Videos tab to import your first clip.")
                                .font(.system(.footnote))
                                .foregroundStyle(SL.panelToplineText)
                        }
                        .padding(.vertical, 8)
                        .listRowBackground(SL.card)
                    }
                    ForEach(videos) { project in
                        Button {
                            onPick(project)
                            dismiss()
                        } label: {
                            OverlayVideoRow(project: project)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(SL.card)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(SL.page)
            .slScreen()
            .navigationTitle("Video \(slot.rawValue) · \(slot.role)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .refreshable { await library.refresh() }
            .onChange(of: pickedVideo) { _, item in
                guard let item else { return }
                dismiss()
                // Keeps running after the sheet closes; the tab shows progress.
                Task {
                    if let id = await library.upload(item),
                       let project = library.projects.first(where: { $0.id == id }) {
                        onPick(project)
                    }
                }
            }
        }
        .tint(SL.green)
    }
}

private struct OverlayVideoRow: View {
    let project: SkillLabProject

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(SL.ink)
                    .lineLimit(2)
                Text(String(format: "%.1f SEC", project.video.duration)
                     + (BundledSample.isSample(project.id) ? "  ·  INCLUDED EXAMPLE" : ""))
                    .font(.system(.caption2, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(SL.panelToplineText)
            }
            Spacer()
            HStack(spacing: 6) {
                if project.isBusy {
                    SLActivityIndicator(size: 12)
                }
                Text(project.motion?.isPlayable == true ? "3D ready" : (project.isBusy ? "Preparing" : "Needs 3D"))
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(SL.presetActiveText)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(SL.iconTile, in: Capsule())
        }
        .contentShape(Rectangle())
    }
}
