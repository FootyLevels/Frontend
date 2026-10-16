import SwiftUI
import RealityKit
import PhotosUI

/// Uploads a still frame to the SAM 3D Body endpoint and renders the result:
/// the reconstructed body mesh plus a procedural joint skeleton.
struct Pose3DView: View {
    @StateObject private var viewModel = Pose3DViewModel()
    @State private var pickedItem: PhotosPickerItem?

    /// Supplied when the view is shown behind the auth gate, which adds the
    /// sign-out control. Optional so the view still stands alone in previews
    /// and when launched directly.
    var appState: AppStateViewModel?

    var body: some View {
        VStack(spacing: 0) {
            sceneArea

            if viewModel.reconstruction != nil {
                controls
                    .padding(AppTheme.Metrics.padding)
                    .background(AppTheme.surfaceColor)
            }
        }
        .background(AppTheme.backgroundColor.ignoresSafeArea())
        .navigationTitle("3D Pose")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    Image(systemName: "photo.badge.plus")
                }
                .disabled(viewModel.isBusy)
            }

            // Only present behind the auth gate — Pose3DView is also used
            // standalone, where there's no session to end.
            if let appState {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(role: .destructive) {
                        try? appState.signOut()
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
        }
        .onChange(of: pickedItem) { _, newItem in
            guard let newItem else { return }
            Task { await handlePick(newItem) }
        }
    }

    // MARK: - Scene

    @ViewBuilder
    private var sceneArea: some View {
        ZStack {
            if viewModel.bodyEntity != nil || viewModel.skeletonEntity != nil {
                RealityView { content in
                    let root = Entity()
                    root.name = "root"
                    content.add(root)
                } update: { content in
                    guard let root = content.entities.first(where: { $0.name == "root" }) else { return }
                    root.children.removeAll()

                    if viewModel.showGround, let ground = viewModel.groundEntity {
                        root.addChild(ground)
                    }
                    if viewModel.showBody, let body = viewModel.bodyEntity {
                        root.addChild(body)
                    }
                    if viewModel.showSkeleton, let skeleton = viewModel.skeletonEntity {
                        root.addChild(skeleton)
                    }
                }
                // Drag to orbit the virtual camera — no manual gesture handling needed.
                .realityViewCameraControls(.orbit)
            }

            switch viewModel.stage {
            case .idle:
                emptyState
            case .uploading, .fetching:
                busyState
            case .failed(let message):
                failureState(message)
            case .ready:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.stand")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Reconstruction Yet")
                .font(.headline)
                .foregroundColor(AppTheme.secondaryColor)

            Text("Pick a photo of a player to build a 3D body from a single frame.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            PhotosPicker(selection: $pickedItem, matching: .images) {
                Text("Choose Photo")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AppTheme.primaryColor)
                    .foregroundColor(.white)
                    .cornerRadius(AppTheme.Metrics.cornerRadius)
            }
        }
    }

    private var busyState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
                .tint(AppTheme.primaryColor)

            Text(viewModel.stage == .uploading ? "Reconstructing..." : "Loading mesh...")
                .font(.headline)
                .foregroundColor(AppTheme.secondaryColor)
        }
        .padding(32)
        .background(AppTheme.surfaceColor.opacity(0.9))
        .cornerRadius(AppTheme.Metrics.cornerRadius)
    }

    private func failureState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(AppTheme.errorColor)

            Text("Reconstruction Failed")
                .font(.headline)
                .foregroundColor(AppTheme.secondaryColor)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Try Again") { viewModel.reset() }
                .fontWeight(.medium)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let model = viewModel.reconstruction?.model {
                HStack(spacing: 12) {
                    Label("\(model.vertices) verts", systemImage: "circle.grid.3x3")
                    Label("\(model.faces) faces", systemImage: "triangle")
                    if let joints = viewModel.keypoints?.numJoints {
                        Label("\(joints) joints", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    if let source = viewModel.bodySource {
                        Label(source.rawValue, systemImage: "shippingbox")
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                Toggle("Body", isOn: $viewModel.showBody)
                Toggle("Joints", isOn: $viewModel.showSkeleton)
                Toggle("Grid", isOn: $viewModel.showGround)
            }
            .font(.subheadline)
            .toggleStyle(.button)

            // The mesh and the joints arrive in different frames — the server
            // applies `y_up` to the mesh but the keypoints stay camera-space —
            // so each gets its own flips. If the two layers disagree with each
            // other, correct them here.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text("Body")
                        .foregroundColor(.secondary)
                        .frame(width: 48, alignment: .leading)
                    Toggle("Flip Y", isOn: $viewModel.bodyOrientation.flipY)
                    Toggle("Flip Z", isOn: $viewModel.bodyOrientation.flipZ)
                }

                HStack(spacing: 12) {
                    Text("Joints")
                        .foregroundColor(.secondary)
                        .frame(width: 48, alignment: .leading)
                    Toggle("Flip Y", isOn: $viewModel.skeletonOrientation.flipY)
                    Toggle("Flip Z", isOn: $viewModel.skeletonOrientation.flipZ)
                }
            }
            .font(.caption)
            .toggleStyle(.button)

            if viewModel.keypoints?.parents == nil, viewModel.keypoints != nil {
                Text("Joints only — the keypoints endpoint sends no parent hierarchy, so bones can't be connected yet.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func handlePick(_ item: PhotosPickerItem) async {
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else {
                viewModel.stage = .failed("Could not read that image.")
                return
            }
            guard let prepared = Pose3DViewModel.prepareForUpload(raw) else {
                viewModel.stage = .failed("Could not encode that image.")
                return
            }
            await viewModel.reconstruct(imageData: prepared)
        } catch {
            viewModel.stage = .failed(error.localizedDescription)
        }
    }
}

#Preview {
    NavigationStack {
        Pose3DView()
    }
}
