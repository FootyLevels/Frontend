import SwiftUI
import GoogleSignInSwift

struct ContentView: View {
    @State private var isServerConnected = false
    @State private var isCheckingConnection = true
    @State private var players: [PlayerInfo] = []
    @State private var skills: [SkillInfo] = []
    @State private var isLoading = true
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            ZStack {
                
                AppTheme.backgroundColor.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerView
                            .padding(.top, 20)

                        // Connection Status
                        connectionStatusView

                        // Tab Selector
                        browseTabSelector

                        // Content based on selected tab
                        if isLoading {
                            loadingView
                        } else {
                            switch selectedTab {
                            case 0:
                                allSkillsView
                            case 1:
                                playerBrowseView
                            case 2:
                                difficultyBrowseView
                            default:
                                allSkillsView
                            }
                        }

                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, AppTheme.Metrics.padding)
                }

                // Floating Action Button
                VStack {
                    Spacer()
                    NavigationLink(destination: UploadVideoView()) {
                        HStack {
                            Image(systemName: "video.badge.plus")
                                .font(.title2)
                            Text("Start Training")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [AppTheme.primaryColor, AppTheme.primaryColor.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(30)
                        .shadow(color: AppTheme.primaryColor.opacity(0.4), radius: 10, x: 0, y: 5)
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .onAppear {
            checkServerConnection()
            loadData()
        }
    }

    // MARK: - Header

    var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "sportscourt.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 50)
                    .foregroundColor(AppTheme.primaryColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("FootyLevels")
                        .font(.title)
                        .fontWeight(.heavy)
                        .foregroundColor(AppTheme.secondaryColor)

                    Text("Master Iconic Skills")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                NavigationLink(destination: AnalysisView(viewModel: AnalysisViewModel())) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.title2)
                        .foregroundColor(AppTheme.secondaryColor)
                        .padding(12)
                        .background(AppTheme.surfaceColor)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 2)
                }
            }
        }
    }

    // MARK: - Connection Status

    var connectionStatusView: some View {
        HStack(spacing: 8) {
            if isCheckingConnection {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Connecting...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if isServerConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppTheme.primaryColor)
                Text("Connected")
                    .font(.caption)
                    .foregroundColor(AppTheme.primaryColor)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(AppTheme.accentColor)
                Text("Offline")
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

    // MARK: - Tab Selector

    var browseTabSelector: some View {
        HStack(spacing: 0) {
            ForEach(Array(["All Skills", "By Player", "By Level"].enumerated()), id: \.offset) { index, title in
                Button(action: { withAnimation { selectedTab = index } }) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(selectedTab == index ? .semibold : .regular)
                        .foregroundColor(selectedTab == index ? .white : AppTheme.textColor)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(
                            selectedTab == index ?
                            AppTheme.primaryColor : Color.clear
                        )
                        .cornerRadius(20)
                }
            }
        }
        .padding(4)
        .background(AppTheme.surfaceColor)
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.05), radius: 2)
    }

    // MARK: - Loading View

    var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading skills...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(height: 200)
    }

    // MARK: - All Skills View

    var allSkillsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("All Skills")
                .font(.headline)
                .foregroundColor(AppTheme.textColor)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(skills) { skill in
                    NavigationLink(destination: SkillDetailView(skill: skill)) {
                        SkillCard(skill: skill)
                    }
                }
            }
        }
    }

    // MARK: - Player Browse View

    var playerBrowseView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Legends Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(AppTheme.accentColor)
                    Text("Legends")
                        .font(.headline)
                        .foregroundColor(AppTheme.textColor)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(players.filter { $0.isLegend }) { player in
                            NavigationLink(destination: PlayerDetailView(player: player, allSkills: skills)) {
                                PlayerCard(player: player)
                            }
                        }
                    }
                }
            }

            // Current Stars Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(AppTheme.primaryColor)
                    Text("Current Stars")
                        .font(.headline)
                        .foregroundColor(AppTheme.textColor)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(players.filter { !$0.isLegend }) { player in
                            NavigationLink(destination: PlayerDetailView(player: player, allSkills: skills)) {
                                PlayerCard(player: player)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Difficulty Browse View

    var difficultyBrowseView: some View {
        VStack(alignment: .leading, spacing: 20) {
            DifficultySection(
                title: "Beginner",
                icon: "1.circle.fill",
                color: Color(hex: "2ECC71"),
                skills: skills.filter { $0.difficulty == "beginner" }
            )

            DifficultySection(
                title: "Intermediate",
                icon: "2.circle.fill",
                color: Color(hex: "F1C40F"),
                skills: skills.filter { $0.difficulty == "intermediate" }
            )

            DifficultySection(
                title: "Advanced",
                icon: "3.circle.fill",
                color: Color(hex: "E74C3C"),
                skills: skills.filter { $0.difficulty == "advanced" }
            )
        }
    }

    // MARK: - Actions

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

    func loadData() {
        Task {
            do {
                async let fetchedSkills = APIClient.shared.fetchSkills()
                async let fetchedPlayers = APIClient.shared.fetchPlayers()

                let (skillsResult, playersResult) = try await (fetchedSkills, fetchedPlayers)

                await MainActor.run {
                    self.skills = skillsResult
                    self.players = playersResult
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    // Use sample data as fallback
                    self.skills = SkillInfo.samples
                    self.players = PlayerInfo.samples
                }
            }
        }
    }
}

// MARK: - Skill Card

struct SkillCard: View {
    let skill: SkillInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Difficulty Badge
            HStack {
                Image(systemName: skill.difficultyIcon)
                    .font(.caption)
                Text(skill.difficulty.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(Color(hex: skill.difficultyColor))

            Text(skill.name)
                .font(.headline)
                .foregroundColor(AppTheme.textColor)
                .lineLimit(1)

            if let playerName = skill.playerName {
                Text(playerName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(skill.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceColor)
        .cornerRadius(AppTheme.Metrics.cornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Player Card

struct PlayerCard: View {
    let player: PlayerInfo

    var body: some View {
        VStack(spacing: 8) {
            // Player Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: player.isLegend ?
                                [Color(hex: "F1C40F"), Color(hex: "F39C12")] :
                                [AppTheme.primaryColor, AppTheme.primaryColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 70, height: 70)

                Text(player.flagEmoji)
                    .font(.system(size: 30))
            }

            Text(player.name.components(separatedBy: " ").last ?? player.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.textColor)
                .lineLimit(1)

            Text("\(player.skills.count) skill\(player.skills.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(AppTheme.surfaceColor)
        .cornerRadius(AppTheme.Metrics.cornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Difficulty Section

struct DifficultySection: View {
    let title: String
    let icon: String
    let color: Color
    let skills: [SkillInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
                    .foregroundColor(AppTheme.textColor)
                Spacer()
                Text("\(skills.count) skills")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(skills) { skill in
                        NavigationLink(destination: SkillDetailView(skill: skill)) {
                            CompactSkillCard(skill: skill, accentColor: color)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Compact Skill Card

struct CompactSkillCard: View {
    let skill: SkillInfo
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(skill.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.textColor)
                .lineLimit(1)

            if let playerName = skill.playerName {
                Text(playerName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 140)
        .background(AppTheme.surfaceColor)
        .overlay(
            Rectangle()
                .fill(accentColor)
                .frame(width: 4),
            alignment: .leading
        )
        .cornerRadius(AppTheme.Metrics.cornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Menu Card (kept for compatibility)

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
