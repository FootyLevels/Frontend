import SwiftUI

struct ContentView: View {
    @State private var isServerConnected = false
    @State private var isCheckingConnection = true

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundColor.ignoresSafeArea()

                VStack(spacing: 30) {
                    // Header
                    VStack(spacing: 10) {
                        Image(systemName: "sportscourt.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .foregroundColor(AppTheme.primaryColor)

                        Text("FootyLevels")
                            .font(.largeTitle)
                            .fontWeight(.heavy)
                            .foregroundColor(AppTheme.secondaryColor)

                        Text("Elevate Your Game")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .tracking(1.5)
                    }
                    .padding(.top, 40)

                    // Connection Status
                    connectionStatusView

                    Spacer()

                    // Menu Grid
                    VStack(spacing: 20) {
                        NavigationLink(destination: UploadVideoView()) {
                            MenuCard(
                                title: "Upload Training",
                                subtitle: "Record or upload clips",
                                icon: "video.badge.plus",
                                color: AppTheme.primaryColor
                            )
                        }

                        NavigationLink(destination: AnalysisView(viewModel: AnalysisViewModel())) {
                            MenuCard(
                                title: "Analysis History",
                                subtitle: "View past results",
                                icon: "chart.bar.doc.horizontal",
                                color: AppTheme.secondaryColor
                            )
                        }
                    }
                    .padding(.horizontal, AppTheme.Metrics.padding)

                    Spacer()
                }
            }
        }
        .onAppear {
            checkServerConnection()
        }
    }

    var connectionStatusView: some View {
        HStack(spacing: 8) {
            if isCheckingConnection {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Connecting to server...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if isServerConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppTheme.primaryColor)
                Text("Server connected")
                    .font(.caption)
                    .foregroundColor(AppTheme.primaryColor)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(AppTheme.accentColor)
                Text("Server offline - Start backend")
                    .font(.caption)
                    .foregroundColor(AppTheme.accentColor)

                Button(action: checkServerConnection) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryColor)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppTheme.surfaceColor)
                .shadow(color: .black.opacity(0.05), radius: 2)
        )
    }

    func checkServerConnection() {
        isCheckingConnection = true

        Task {
            do {
                let connected = try await APIClient.shared.healthCheck()
                await MainActor.run {
                    isServerConnected = connected
                    isCheckingConnection = false
                }
            } catch {
                await MainActor.run {
                    isServerConnected = false
                    isCheckingConnection = false
                }
            }
        }
    }
}

struct MenuCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 60, height: 60)

                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.textColor)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.gray.opacity(0.5))
        }
        .padding()
        .background(AppTheme.surfaceColor)
        .cornerRadius(AppTheme.Metrics.cornerRadius)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

#Preview {
    ContentView()
}
