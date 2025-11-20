import SwiftUI

struct ContentView: View {
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
                        
                        NavigationLink(destination: AnalysisView()) {
                            MenuCard(
                                title: "Analysis Results",
                                subtitle: "View AI insights",
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
