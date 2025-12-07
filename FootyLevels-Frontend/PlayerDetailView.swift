import SwiftUI

struct PlayerDetailView: View {
    let player: PlayerInfo
    let allSkills: [SkillInfo]

    var playerSkills: [SkillInfo] {
        allSkills.filter { player.skills.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero Section
                heroSection

                // Player Stats
                statsSection

                // Bio
                bioSection

                // Player's Skills
                skillsSection

                Spacer(minLength: 40)
            }
            .padding(AppTheme.Metrics.padding)
        }
        .background(AppTheme.backgroundColor.ignoresSafeArea())
        .navigationTitle(player.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hero Section

    var heroSection: some View {
        VStack(spacing: 16) {
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
                    .frame(width: 120, height: 120)
                    .shadow(color: player.isLegend ? Color(hex: "F1C40F").opacity(0.4) : AppTheme.primaryColor.opacity(0.4), radius: 15, x: 0, y: 8)

                Text(player.flagEmoji)
                    .font(.system(size: 50))
            }

            // Name & Nickname
            VStack(spacing: 4) {
                Text(player.name)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.textColor)

                Text("\"\(player.nickname)\"")
                    .font(.title3)
                    .italic()
                    .foregroundColor(.secondary)
            }

            // Category Badge
            HStack(spacing: 6) {
                Image(systemName: player.isLegend ? "star.fill" : "bolt.fill")
                    .font(.caption)
                Text(player.categoryDisplayName)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .foregroundColor(player.isLegend ? Color(hex: "F1C40F") : AppTheme.primaryColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                (player.isLegend ? Color(hex: "F1C40F") : AppTheme.primaryColor).opacity(0.1)
            )
            .cornerRadius(20)
        }
    }

    // MARK: - Stats Section

    var statsSection: some View {
        HStack(spacing: 12) {
            StatCard(
                icon: "flag.fill",
                title: "Nationality",
                value: player.nationality
            )

            StatCard(
                icon: "calendar",
                title: "Era",
                value: player.era
            )

            StatCard(
                icon: "figure.soccer",
                title: "Skills",
                value: "\(player.skills.count)"
            )
        }
    }

    // MARK: - Bio Section

    var bioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.text.rectangle.fill")
                    .foregroundColor(AppTheme.secondaryColor)
                Text("About")
                    .font(.headline)
                    .foregroundColor(AppTheme.textColor)
            }

            Text(player.bio)
                .font(.body)
                .foregroundColor(.secondary)
                .lineSpacing(4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceColor)
        .cornerRadius(AppTheme.Metrics.cornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    // MARK: - Skills Section

    var skillsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "star.circle.fill")
                    .foregroundColor(AppTheme.accentColor)
                Text("Signature Skills")
                    .font(.headline)
                    .foregroundColor(AppTheme.textColor)
            }

            if playerSkills.isEmpty {
                Text("No skills associated yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(playerSkills) { skill in
                    NavigationLink(destination: SkillDetailView(skill: skill)) {
                        PlayerSkillRow(skill: skill)
                    }
                }
            }
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(AppTheme.primaryColor)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(AppTheme.surfaceColor)
        .cornerRadius(AppTheme.Metrics.cornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Player Skill Row

struct PlayerSkillRow: View {
    let skill: SkillInfo

    var body: some View {
        HStack(spacing: 16) {
            // Skill icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: skill.difficultyColor).opacity(0.1))
                    .frame(width: 50, height: 50)

                Image(systemName: "figure.soccer")
                    .font(.title3)
                    .foregroundColor(Color(hex: skill.difficultyColor))
            }

            // Skill info
            VStack(alignment: .leading, spacing: 4) {
                Text(skill.name)
                    .font(.headline)
                    .foregroundColor(AppTheme.textColor)

                Text(skill.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Difficulty badge
            VStack {
                Image(systemName: skill.difficultyIcon)
                    .font(.caption)
                    .foregroundColor(Color(hex: skill.difficultyColor))
                Text(skill.difficulty.capitalized)
                    .font(.caption2)
                    .foregroundColor(Color(hex: skill.difficultyColor))
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray.opacity(0.5))
        }
        .padding()
        .background(AppTheme.surfaceColor)
        .cornerRadius(AppTheme.Metrics.cornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    NavigationStack {
        PlayerDetailView(player: PlayerInfo.samples[0], allSkills: SkillInfo.samples)
    }
}
