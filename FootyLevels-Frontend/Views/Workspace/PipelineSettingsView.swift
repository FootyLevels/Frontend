import SwiftUI

/// "Reconstruction pipeline": where key frames are reconstructed, and which
/// server the app talks to.
struct PipelineSettingsView: View {
    let viewModel: ProjectDetailViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var showServer = false
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    steps

                    Text("Choose where to reconstruct the selected player. The app loads saved meshes; it does not run the model.")
                        .font(.system(.footnote))
                        .lineSpacing(3)
                        .foregroundStyle(SL.muted)

                    if let health = viewModel.health {
                        ForEach(health.providers) { provider in
                            providerOption(provider)
                        }
                    } else {
                        Label("Not connected to a FootyLevels server.", systemImage: "network.slash")
                            .font(.system(.footnote))
                            .foregroundStyle(SL.errorText)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .slPanel(fill: SL.errorFill, border: .clear, radius: 7)
                    }

                    serverRow
                    setupTip
                }
                .padding(20)
            }
            .background(SL.panel)
            .navigationTitle("Reconstruction pipeline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        Task {
                            isRefreshing = true
                            await viewModel.refreshHealth()
                            isRefreshing = false
                        }
                    } label: {
                        Label(isRefreshing ? "Refreshing…" : "Refresh connection", systemImage: "arrow.clockwise")
                    }
                    .disabled(isRefreshing)
                }
            }
            .sheet(isPresented: $showServer) {
                ServerSettingsView(suggestions: viewModel.health?.network?.urls ?? []) {
                    Task { await viewModel.refreshHealth() }
                }
            }
        }
    }

    private var steps: some View {
        HStack(spacing: 6) {
            ForEach(Array(["Video", "Key frames", "SAM 3D Body", "3D inspection"].enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Image(systemName: "arrow.right").font(.system(.caption2))
                }
                Text(step)
            }
        }
        .font(.system(.caption2))
        .foregroundStyle(SL.muted)
    }

    private func providerOption(_ provider: ProviderCapability) -> some View {
        let selected = viewModel.providerId == provider.id
        return Button {
            viewModel.providerId = provider.id
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(SL.green)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(provider.label)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(SL.ink)
                        Spacer()
                        Text(provider.ready ? "Configured" : "Setup needed")
                            .font(.system(.caption2))
                            .foregroundStyle(provider.ready ? SL.good : SL.noticeText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(provider.ready ? SL.tick : SL.noticeFill,
                                        in: RoundedRectangle(cornerRadius: 4))
                    }
                    Text(provider.reason ?? (provider.remote
                        ? "Selected frame crops are sent to fal. Usage is billed to your configured account."
                        : "Frames and models stay on the machine running the API."))
                        .font(.system(.caption))
                        .lineSpacing(2)
                        .foregroundStyle(SL.muted)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .slPanel(fill: selected ? SL.presetActive : .clear,
                     border: selected ? SL.green : SL.cardBorder, radius: 7)
        }
        .buttonStyle(.plain)
        .disabled(!provider.ready)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var serverRow: some View {
        Button {
            showServer = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "server.rack")
                    .foregroundStyle(SL.iconTileText)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Server")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(SL.ink)
                    Text(ServerSettings.baseURL?.absoluteString ?? "No server address set")
                        .font(.system(.caption))
                        .foregroundStyle(SL.muted)
                }
                Spacer()
                if let mode = viewModel.health?.network?.mode {
                    Text(mode.uppercased())
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(SL.muted)
                }
                Image(systemName: "chevron.right")
                    .font(.system(.caption))
                    .foregroundStyle(SL.muted)
            }
            .padding(14)
            .slPanel(fill: .clear, border: SL.cardBorder, radius: 7)
        }
        .buttonStyle(.plain)
    }

    private var setupTip: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "terminal")
                .foregroundStyle(SL.ink)
            VStack(alignment: .leading, spacing: 8) {
                Text("Using your GPU server")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(SL.ink)
                Text("Run the API in the SAM 3D Body environment on the server with scripts/serve_lan.sh, then enter the address it prints. Check the models with:")
                    .font(.system(.caption))
                    .lineSpacing(2)
                    .foregroundStyle(SL.muted)
                Text("python -m backend.cli doctor")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(SL.ink)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SL.insight, in: RoundedRectangle(cornerRadius: 4))
                    .textSelection(.enabled)
            }
        }
        .padding(17)
        .background(SL.iconTile, in: RoundedRectangle(cornerRadius: 6))
    }
}
