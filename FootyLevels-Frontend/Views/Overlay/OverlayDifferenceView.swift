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
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(SL.errorText)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SL.errorFill, in: RoundedRectangle(cornerRadius: 6))
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

                        Text(viewModel.canCompare
                             ? "Opens as an overlay, with B moved onto your center of mass. Switch to side by side on the next screen."
                             : "Choose two videos with 3D motion. The same video can fill both slots.")
                            .font(.system(size: 12))
                            .foregroundStyle(SL.muted)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(SL.page)
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
            Eyebrow(text: "OVERLAY DIFFERENCE", rule: true)
            (Text("Two attempts.\n") + Text("One body space.").foregroundColor(SL.headlineSoft))
                .font(SL.display(32, .semibold))
                .tracking(-1.4)
                .foregroundStyle(SL.ink)
            Text("Lay one 3D model over another, centered on the same point, to see exactly where the movements differ.")
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(Color(hex: "77816F"))
        }
        .padding(.top, 12)
    }

    private var isComparing: Binding<Bool> {
        Binding(get: { comparison != nil }, set: { if !$0 { closeComparison() } })
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
            .foregroundStyle(.white)
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
                    Eyebrow(text: "\(slot.rawValue) · \(slot.role.uppercased())", color: SL.muted)
                    Text(project?.title ?? "No video chosen")
                        .font(SL.display(17, .heavy))
                        .tracking(-0.5)
                        .foregroundStyle(project == nil ? SL.muted : SL.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button(project == nil ? "Choose" : "Change", action: onChoose)
                    .buttonStyle(.slSecondary)
                    .accessibilityLabel(project == nil ? "Choose video \(slot.rawValue)" : "Change video \(slot.rawValue)")
            }

            if let project {
                HStack(spacing: 10) {
                    StatusDot(text: motionText(project), ready: project.motion?.isPlayable == true)
                    Spacer()
                    if isStarting || project.isBusy {
                        ProgressView().controlSize(.small)
                    } else if canBuild {
                        Button(action: onBuild) {
                            Label("Build 3D motion", systemImage: "waveform.path.ecg")
                        }
                        .buttonStyle(.slPrimary)
                    }
                }
            }
        }
        .padding(14)
        .slPanel(fill: SL.card, border: SL.cardBorder, radius: 9)
    }

    private func motionText(_ project: SkillLabProject) -> String {
        guard let motion = project.motion else { return "No 3D motion yet" }
        switch motion.status {
        case "complete": return "3D motion ready"
        case "partial": return "3D motion ready · some frames missing"
        case "queued", "running": return motion.stage ?? "Building 3D motion…"
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
                    }
                    .disabled(!canImport)
                } footer: {
                    if library.health == nil {
                        Text("Connect to the server on the Videos tab to import. The included example works offline.")
                    }
                }

                Section("Your videos") {
                    ForEach(videos) { project in
                        Button {
                            onPick(project)
                            dismiss()
                        } label: {
                            OverlayVideoRow(project: project)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SL.ink)
                    .lineLimit(1)
                Text(String(format: "%.1f SEC", project.video.duration)
                     + (BundledSample.isSample(project.id) ? "  ·  INCLUDED EXAMPLE" : ""))
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(Color(hex: "7C8578"))
            }
            Spacer()
            StatusDot(text: project.motion?.isPlayable == true ? "3D motion" : "No 3D motion",
                      ready: project.motion?.isPlayable == true)
        }
        .contentShape(Rectangle())
    }
}
