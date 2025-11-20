import SwiftUI

struct UploadVideoView: View {
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0.0
    @State private var uploadComplete = false
    @State private var selectedVideoName: String? = nil
    @State private var showError = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "arrow.up.circle.fill")
                    .resizable()
                    .frame(width: 60, height: 60)
                    .foregroundColor(AppTheme.primaryColor)
                
                Text("Upload Training Video")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.textColor)
                
                Text("Record or select a clip to analyze")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)
            
            Spacer()
            
            // Main Action Area
            if uploadComplete {
                successView
            } else if isUploading {
                uploadingView
            } else {
                selectionView
            }
            
            Spacer()
        }
        .padding(AppTheme.Metrics.padding)
        .background(AppTheme.backgroundColor.ignoresSafeArea())
        .navigationTitle("Upload")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Subviews
    
    var selectionView: some View {
        VStack(spacing: 20) {
            if let videoName = selectedVideoName {
                // Selected Video Preview Placeholder
                HStack {
                    Image(systemName: "film")
                        .foregroundColor(AppTheme.secondaryColor)
                    Text(videoName)
                        .fontWeight(.medium)
                    Spacer()
                    Button(action: { selectedVideoName = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppTheme.errorColor)
                    }
                }
                .padding()
                .background(AppTheme.surfaceColor)
                .cornerRadius(AppTheme.Metrics.cornerRadius)
                .shadow(radius: 2)
                
                Button(action: startUpload) {
                    Text("Upload Video")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppTheme.primaryColor)
                        .foregroundColor(.white)
                        .cornerRadius(AppTheme.Metrics.cornerRadius)
                }
            } else {
                // Action Buttons
                ActionButton(icon: "camera.fill", title: "Record New Clip") {
                    // Placeholder: Simulate recording logic
                    simulateVideoSelection(name: "Recorded_Session_001.mov")
                }
                
                ActionButton(icon: "photo.on.rectangle", title: "Select from Gallery") {
                    // Placeholder: Simulate gallery selection
                    simulateVideoSelection(name: "Practice_Drill_A.mp4")
                }
            }
        }
    }
    
    var uploadingView: some View {
        VStack(spacing: 16) {
            ProgressView(value: uploadProgress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle(tint: AppTheme.primaryColor))
                .scaleEffect(x: 1, y: 2, anchor: .center)
            
            Text("Compressing & Uploading...")
                .font(.headline)
                .foregroundColor(AppTheme.secondaryColor)
            
            Text("\(Int(uploadProgress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(AppTheme.surfaceColor)
        .cornerRadius(AppTheme.Metrics.cornerRadius)
        .shadow(radius: 2)
    }
    
    var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .frame(width: 50, height: 50)
                .foregroundColor(AppTheme.primaryColor)
            
            Text("Video Uploaded Successfully")
                .font(.headline)
                .foregroundColor(AppTheme.textColor)
            
            Text("Your clip has been queued for AI analysis.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: resetFlow) {
                Text("Upload Another")
                    .fontWeight(.medium)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AppTheme.secondaryColor)
                    .foregroundColor(.white)
                    .cornerRadius(AppTheme.Metrics.cornerRadius)
            }
        }
        .padding(32)
        .background(AppTheme.surfaceColor)
        .cornerRadius(AppTheme.Metrics.cornerRadius)
        .shadow(radius: 4)
    }
    
    // MARK: - Logic Actions
    
    func simulateVideoSelection(name: String) {
        // Simulate user selecting a video
        selectedVideoName = name
    }
    
    func startUpload() {
        isUploading = true
        uploadProgress = 0.0
        
        // Simulate upload process
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if uploadProgress < 1.0 {
                uploadProgress += 0.2
            } else {
                timer.invalidate()
                isUploading = false
                uploadComplete = true
                // Placeholder: Metadata storage call would happen here
                print("Metadata stored for user_id: 123, skill_type: 'dribbling'")
            }
        }
    }
    
    func resetFlow() {
        uploadComplete = false
        selectedVideoName = nil
        uploadProgress = 0.0
    }
}

struct ActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(AppTheme.surfaceColor)
            .foregroundColor(AppTheme.secondaryColor)
            .cornerRadius(AppTheme.Metrics.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Metrics.cornerRadius)
                    .stroke(AppTheme.secondaryColor.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 2)
        }
    }
}

#Preview {
    NavigationView {
        UploadVideoView()
    }
}

