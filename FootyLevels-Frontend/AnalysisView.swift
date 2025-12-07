import SwiftUI

struct AnalysisView: View {
    @ObservedObject var viewModel: AnalysisViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if viewModel.isLoading {
                    loadingState
                } else if viewModel.analysisResult != nil || viewModel.feedbackResult != nil {
                    resultsContent
                } else {
                    emptyState
                }
            }
            .padding(AppTheme.Metrics.padding)
        }
        .background(AppTheme.backgroundColor.ignoresSafeArea())
        .navigationTitle("AI Analysis")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Loading State

    var loadingState: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 100)
            ProgressView()
                .scaleEffect(1.5)
                .tint(AppTheme.primaryColor)

            Text("Analyzing Movement...")
                .font(.headline)
                .foregroundColor(AppTheme.secondaryColor)

            Text("Comparing to professional reference data")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Empty State

    var emptyState: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 100)
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Analysis Yet")
                .font(.headline)
                .foregroundColor(AppTheme.secondaryColor)

            Text("Upload a video to get AI-powered feedback on your technique")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
    }

    // MARK: - Results Content

    var resultsContent: some View {
        VStack(spacing: 24) {
            // Overall Score Card
            scoreCard

            // Performance Metrics
            metricsSection

            // Strengths
            if !viewModel.strengths.isEmpty {
                feedbackSection(
                    title: "Strengths",
                    items: viewModel.strengths,
                    isPositive: true
                )
            }

            // Areas for Improvement
            if !viewModel.improvements.isEmpty {
                feedbackSection(
                    title: "Areas to Improve",
                    items: viewModel.improvements,
                    isPositive: false
                )
            }

            // Tips
            if !viewModel.tips.isEmpty {
                tipsSection
            }

            // Encouragement
            encouragementCard
        }
    }

    var scoreCard: some View {
        VStack(spacing: 16) {
            Text(viewModel.selectedSkill?.name ?? "Skill Analysis")
                .font(.headline)
                .foregroundColor(AppTheme.textColor)

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: viewModel.overallScore / 10)
                    .stroke(
                        Color(hex: viewModel.scoreColor),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 4) {
                    Text(String(format: "%.1f", viewModel.overallScore))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(AppTheme.textColor)
                    Text("/ 10")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(viewModel.overallRating)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(Color(hex: viewModel.scoreColor))

            Text(viewModel.summary)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(24)
        .background(AppTheme.surfaceColor)
        .cornerRadius(AppTheme.Metrics.cornerRadius)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Metrics")
                .font(.headline)
                .foregroundColor(AppTheme.textColor)

            HStack(spacing: 12) {
                MetricCard(
                    title: "Score",
                    value: String(format: "%.0f%%", viewModel.overallScore * 10),
                    icon: "target",
                    color: Color(hex: viewModel.scoreColor)
                )
                MetricCard(
                    title: "Rating",
                    value: viewModel.overallRating,
                    icon: "star.fill",
                    color: AppTheme.accentColor
                )
                MetricCard(
                    title: "Tips",
                    value: "\(viewModel.tips.count)",
                    icon: "lightbulb.fill",
                    color: AppTheme.primaryColor
                )
            }
        }
    }

    func feedbackSection(title: String, items: [DisplayFeedbackItem], isPositive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(AppTheme.textColor)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(items) { item in
                    FeedbackItemView(
                        title: item.title,
                        message: item.message,
                        isPositive: isPositive
                    )

                    if item.id != items.last?.id {
                        Divider()
                    }
                }
            }
            .padding()
            .background(AppTheme.surfaceColor)
            .cornerRadius(AppTheme.Metrics.cornerRadius)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
    }

    var tipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coach's Tips")
                .font(.headline)
                .foregroundColor(AppTheme.textColor)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(viewModel.tips.enumerated()), id: \.offset) { index, tip in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(AppTheme.primaryColor)
                            .clipShape(Circle())

                        Text(tip.message.isEmpty ? tip.title : tip.message)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(AppTheme.surfaceColor)
            .cornerRadius(AppTheme.Metrics.cornerRadius)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
    }

    var encouragementCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundColor(AppTheme.accentColor)

            Text(viewModel.encouragement)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(AppTheme.textColor)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(AppTheme.accentColor.opacity(0.1))
        .cornerRadius(AppTheme.Metrics.cornerRadius)
    }
}

// MARK: - Components

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(AppTheme.textColor)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(AppTheme.surfaceColor)
        .cornerRadius(AppTheme.Metrics.cornerRadius)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct FeedbackItemView: View {
    let title: String
    let message: String
    let isPositive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isPositive ? "hand.thumbsup.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(isPositive ? AppTheme.primaryColor : AppTheme.accentColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.textColor)

                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    NavigationView {
        AnalysisView(viewModel: AnalysisViewModel.sample)
    }
}
