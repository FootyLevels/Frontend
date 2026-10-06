import SwiftUI

/// Enter and verify the Skill Lab server address.
///
/// The address is only saved after `/api/health` answers from it, so a typo or
/// a server still in `local` mode is caught here rather than surfacing later as
/// an empty project list.
struct ServerSettingsView: View {
    /// Addresses the server last reported for other devices, offered as
    /// one-tap choices.
    var suggestions: [String] = []
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var address = ServerSettings.address
    @State private var isTesting = false
    @State private var result: TestResult?

    private enum TestResult {
        case success(SkillLabHealth)
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://192.168.1.42:8000", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: address) { _, _ in result = nil }
                } header: {
                    Text("Server Address")
                } footer: {
                    Text(instructions)
                }

                if !suggestions.isEmpty {
                    Section("Reported by the Server") {
                        ForEach(suggestions, id: \.self) { url in
                            Button(url) { address = url }
                        }
                    }
                }

                if let result {
                    Section { resultRow(result) }
                }

                Section {
                    Button {
                        Task { await testAndSave() }
                    } label: {
                        HStack {
                            Text("Test and Save")
                            if isTesting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isTesting || ServerSettings.normalize(address) == nil)

                    #if targetEnvironment(simulator)
                    Button("Use This Mac (127.0.0.1)") { address = ServerSettings.defaultAddress }
                    #endif
                }
            }
            .navigationTitle("Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var instructions: String {
        #if targetEnvironment(simulator)
        "The Simulator reaches a server on this Mac at 127.0.0.1 in the default local mode."
        #else
        "On the server machine run: bash scripts/serve_lan.sh — then enter the address it prints. The server must be in lan mode, and this device on the same network."
        #endif
    }

    @ViewBuilder
    private func resultRow(_ result: TestResult) -> some View {
        switch result {
        case .success(let health):
            VStack(alignment: .leading, spacing: 4) {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.primaryColor)
                if let network = health.network {
                    Text("Network mode: \(network.mode)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.errorColor)
                .font(.subheadline)
        }
    }

    private func testAndSave() async {
        guard let url = ServerSettings.normalize(address) else { return }
        isTesting = true
        defer { isTesting = false }
        do {
            let health = try await SkillLabClient.shared.health(at: url)
            result = .success(health)
            // Store the normalised form, so a pasted `/api/health` URL doesn't
            // get the path appended twice later.
            ServerSettings.address = url.absoluteString
            onSave()
            try? await Task.sleep(for: .milliseconds(600))
            dismiss()
        } catch {
            result = .failure(error.localizedDescription)
        }
    }
}
