import SwiftUI

struct SkillDetailView: View {
    let skill: SkillInfo
    @State private var skillDetails: SkillDetails?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Hero Section
                heroSection

                // Origin Story
                if let origin = skill.originStory ?? skillDetails?.originStory {
                    originSection(origin)
                }

                // Difficulty & Player Info
                infoCards

                // Skill Phases
                if let phases = skillDetails?.phases, !phases.isEmpty {
                    phasesSection(phases)
                }

                // Checkpoints
                if let checkpoints = skillDetails?.checkpoints, !checkpoints.isEmpty {
                    checkpointsSection(checkpoints)
                }

                // Start Training Button
                NavigationLink(destination: UploadVideoView(preselectedSkill: skill)) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Training")
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(AppTheme.primaryColor)
                    .cornerRadius(AppTheme.Metrics.cornerRadius)
                }
                .padding(.top, 10)

                Spacer(minLength: 40)
            }
            .padding(AppTheme.Metrics.padding)
        }
        .background(AppTheme.backgroundColor.ignoresSafeArea())
        .navigationTitle(skill.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadDetails()
        }
    }

    // MARK: - Hero Section

    var heroSection: some View {
        VStack(spacing: 16) {
            // Skill Icon/Preview placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: skill.difficultyColor).opacity(0.3), Color(hex: skill.difficultyColor).opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 180)

                VStack(spacing: 12) {
                    Image(systemName: "figure.soccer")
                        .font(.system(size: 50))
                        .foregroundColor(Color(hex: skill.difficultyColor))

                    if let playerName = skill.playerName {
                        Text("Made famous by \(playerName)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Skill Name & Description
            VStack(spacing: 8) {
                Text(skill.name)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.textColor)

                Text(skill.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Origin Section

    func originSection(_ origin: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "book.fill")
                    .foregroundColor(AppTheme.accentColor)
                Text("Origin Story")
                    .font(.headline)
                    .foregroundColor(AppTheme.textColor)
            }

            Text(origin)
                .font(.body)
                .foregroundColor(.secondary)
                .italic()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceColor)
        .cornerRadius(AppTheme.Metrics.cornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    // MARK: - Info Cards

    var infoCards: some View {
        HStack(spacing: 12) {
            // Difficulty Card
            VStack(spacing: 8) {
                Image(systemName: skill.difficultyIcon)
                    .font(.title2)
                    .foregroundColor(Color(hex: skill.difficultyColor))

                Text("Difficulty")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(skill.difficulty.capitalized)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.textColor)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(AppTheme.surfaceColor)
            .cornerRadius(AppTheme.Metrics.cornerRadius)
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)

            // Player Card
            if let playerName = skill.playerName {
                VStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.title2)
                        .foregroundColor(AppTheme.accentColor)

                    Text("Iconic Player")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(playerName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(AppTheme.textColor)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppTheme.surfaceColor)
                .cornerRadius(AppTheme.Metrics.cornerRadius)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            }
        }
    }

    // MARK: - Phases Section

    func phasesSection(_ phases: [SkillPhase]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.number")
                    .foregroundColor(AppTheme.primaryColor)
                Text("Phases")
                    .font(.headline)
                    .foregroundColor(AppTheme.textColor)
            }

            VStack(spacing: 8) {
                ForEach(Array(phases.enumerated()), id: \.offset) { index, phase in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(AppTheme.primaryColor)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(phase.name.capitalized)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(AppTheme.textColor)

                            if let desc = phase.description {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(AppTheme.surfaceColor)
        .cornerRadius(AppTheme.Metrics.cornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    // MARK: - Checkpoints Section

    func checkpointsSection(_ checkpoints: [SkillCheckpoint]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppTheme.primaryColor)
                Text("Key Checkpoints")
                    .font(.headline)
                    .foregroundColor(AppTheme.textColor)
            }

            Text("What we'll analyze in your performance:")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                ForEach(checkpoints) { checkpoint in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "target")
                            .foregroundColor(AppTheme.accentColor)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(checkpoint.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(AppTheme.textColor)

                            Text(checkpoint.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(AppTheme.surfaceColor)
        .cornerRadius(AppTheme.Metrics.cornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    // MARK: - Actions

    func loadDetails() {
        Task {
            do {
                let details = try await APIClient.shared.fetchSkillDetails(skillId: skill.id)
                await MainActor.run {
                    self.skillDetails = details
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SkillDetailView(skill: SkillInfo.samples[0])
    }
}
