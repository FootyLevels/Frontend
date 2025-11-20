import SwiftUI

struct AnalysisView: View {
    @State private var isLoading = true
    @State private var showResults = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if isLoading {
                    loadingState
                } else {
                    resultsContent
                }
            }
            .padding(AppTheme.Metrics.padding)
        }
        .background(AppTheme.backgroundColor.ignoresSafeArea())
        .navigationTitle("AI Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            simulateAnalysis()
        }
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
    
    // MARK: - Results Content
    
    var resultsContent: some View {
        VStack(spacing: 24) {
            // 1. Visual Feedback Placeholder
            VStack(alignment: .leading, spacing: 12) {
                Text("Motion Analysis")
                    .font(.headline)
                    .foregroundColor(AppTheme.textColor)
                
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.Metrics.cornerRadius)
                        .fill(Color.black.opacity(0.8))
                        .frame(height: 200)
                    
                    Image(systemName: "figure.soccer")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 100)
                        .foregroundColor(.white.opacity(0.3))
                    
                    Text("AI Overlay & Heatmap Placeholder")
                        .foregroundColor(.white)
                        .font(.footnote)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Metrics.cornerRadius)
                        .stroke(AppTheme.accentColor, lineWidth: 2)
                )
            }
            
            // 2. Performance Metrics
            VStack(alignment: .leading, spacing: 12) {
                Text("Performance Metrics")
                    .font(.headline)
                    .foregroundColor(AppTheme.textColor)
                
                HStack(spacing: 12) {
                    MetricCard(title: "Balance", value: "85%", icon: "scalemass.fill", color: .blue)
                    MetricCard(title: "Accuracy", value: "92%", icon: "target", color: AppTheme.primaryColor)
                    MetricCard(title: "Speed", value: "12 m/s", icon: "speedometer", color: AppTheme.accentColor)
                }
            }
            
            // 3. Personalized Feedback
            VStack(alignment: .leading, spacing: 12) {
                Text("Coach's Feedback")
                    .font(.headline)
                    .foregroundColor(AppTheme.textColor)
                
                VStack(alignment: .leading, spacing: 16) {
                    FeedbackItem(
                        title: "Good Form",
                        message: "Your body positioning during the strike is excellent. Knee over the ball is consistent.",
                        isPositive: true
                    )
                    
                    Divider()
                    
                    FeedbackItem(
                        title: "Improvement Area",
                        message: "Try to reduce the backswing time to increase shot surprise. Your follow-through drifts slightly left.",
                        isPositive: false
                    )
                }
                .padding()
                .background(AppTheme.surfaceColor)
                .cornerRadius(AppTheme.Metrics.cornerRadius)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            }
        }
    }
    
    // MARK: - Logic
    
    func simulateAnalysis() {
        // Simulate network delay for AI processing
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                isLoading = false
                showResults = true
            }
        }
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

struct FeedbackItem: View {
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
        AnalysisView()
    }
}

