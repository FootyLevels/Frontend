import SwiftUI
import PhotosUI
import AVKit

struct UploadVideoView: View {
    @StateObject private var viewModel = AnalysisViewModel()
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0.0
    @State private var uploadComplete = false
    @State private var selectedVideoURL: URL? = nil
    @State private var selectedVideoName: String? = nil
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var navigateToAnalysis = false

    // Photo picker
    @State private var selectedItem: PhotosPickerItem? = nil

    // Available skills
    @State private var skills: [SkillInfo] = []
    @State private var selectedSkill: SkillInfo? = nil
    @State private var isLoadingSkills = true

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

            // Navigation to Analysis
            NavigationLink(
                destination: AnalysisView(viewModel: viewModel),
                isActive: $navigateToAnalysis
            ) {
                EmptyView()
            }
        }
        .padding(AppTheme.Metrics.padding)
        .background(AppTheme.backgroundColor.ignoresSafeArea())
        .navigationTitle("Upload")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            loadSkills()
        }
    }

    // MARK: - Subviews

    var selectionView: some View {
        VStack(spacing: 20) {
            // Skill Picker
            if isLoadingSkills {
                ProgressView("Loading skills...")
                    .padding()
            } else if !skills.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Skill")
                        .font(.headline)
                        .foregroundColor(AppTheme.textColor)

                    Menu {
                        ForEach(skills) { skill in
                            Button(action: { selectedSkill = skill }) {
                                VStack(alignment: .leading) {
                                    Text(skill.name)
                                    Text(skill.difficulty.capitalized)
                                        .font(.caption)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(selectedSkill?.name ?? "Choose a skill...")
                                .foregroundColor(selectedSkill != nil ? AppTheme.textColor : .secondary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(AppTheme.surfaceColor)
                        .cornerRadius(AppTheme.Metrics.cornerRadius)
                    }
                }
            }

            if let videoName = selectedVideoName {
                // Selected Video Preview
                VStack(spacing: 12) {
                    // Video thumbnail
                    if let videoURL = selectedVideoURL {
                        VideoThumbnailView(url: videoURL)
                            .frame(height: 150)
                            .cornerRadius(AppTheme.Metrics.cornerRadius)
                    }

                    HStack {
                        Image(systemName: "film")
                            .foregroundColor(AppTheme.secondaryColor)
                        Text(videoName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Spacer()
                        Button(action: clearSelection) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(AppTheme.errorColor)
                        }
                    }
                    .padding()
                    .background(AppTheme.surfaceColor)
                    .cornerRadius(AppTheme.Metrics.cornerRadius)
                    .shadow(radius: 2)
                }

                Button(action: startUpload) {
                    Text("Analyze Video")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedSkill != nil ? AppTheme.primaryColor : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(AppTheme.Metrics.cornerRadius)
                }
                .disabled(selectedSkill == nil)
            } else {
                // Action Buttons
                PhotosPicker(
                    selection: $selectedItem,
                    matching: .videos
                ) {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title2)
                        Text("Select from Gallery")
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
                .onChange(of: selectedItem) { newItem in
                    handleVideoSelection(newItem)
                }
            }
        }
    }

    var uploadingView: some View {
        VStack(spacing: 16) {
            ProgressView(value: uploadProgress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle(tint: AppTheme.primaryColor))
                .scaleEffect(x: 1, y: 2, anchor: .center)

            Text(uploadProgress < 0.5 ? "Uploading Video..." : "Analyzing Movement...")
                .font(.headline)
                .foregroundColor(AppTheme.secondaryColor)

            Text("\(Int(uploadProgress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)

            if uploadProgress >= 0.5 {
                Text("AI is comparing to professional reference")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
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

            Text("Analysis Complete!")
                .font(.headline)
                .foregroundColor(AppTheme.textColor)

            Text("Your performance has been analyzed by our AI coach.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button(action: resetFlow) {
                    Text("Upload Another")
                        .fontWeight(.medium)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(AppTheme.surfaceColor)
                        .foregroundColor(AppTheme.secondaryColor)
                        .cornerRadius(AppTheme.Metrics.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Metrics.cornerRadius)
                                .stroke(AppTheme.secondaryColor.opacity(0.3), lineWidth: 1)
                        )
                }

                Button(action: { navigateToAnalysis = true }) {
                    Text("View Results")
                        .fontWeight(.medium)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(AppTheme.primaryColor)
                        .foregroundColor(.white)
                        .cornerRadius(AppTheme.Metrics.cornerRadius)
                }
            }
        }
        .padding(32)
        .background(AppTheme.surfaceColor)
        .cornerRadius(AppTheme.Metrics.cornerRadius)
        .shadow(radius: 4)
    }

    // MARK: - Logic Actions

    func loadSkills() {
        Task {
            do {
                let fetchedSkills = try await APIClient.shared.fetchSkills()
                await MainActor.run {
                    self.skills = fetchedSkills
                    self.isLoadingSkills = false
                    // Auto-select first skill if available
                    if selectedSkill == nil && !fetchedSkills.isEmpty {
                        selectedSkill = fetchedSkills.first
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingSkills = false
                    // Fallback: add a default skill
                    self.skills = [
                        SkillInfo(id: "cruyff_turn", name: "Cruyff Turn", description: "Classic turn move", difficulty: "intermediate")
                    ]
                    self.selectedSkill = self.skills.first
                    print("Failed to load skills: \(error)")
                }
            }
        }
    }

    func handleVideoSelection(_ item: PhotosPickerItem?) {
        guard let item = item else { return }

        Task {
            do {
                // Load the video data
                guard let videoData = try await item.loadTransferable(type: Data.self) else {
                    throw APIError.networkError("Could not load video")
                }

                // Save to temporary file
                let tempDir = FileManager.default.temporaryDirectory
                let fileName = "video_\(UUID().uuidString).mp4"
                let fileURL = tempDir.appendingPathComponent(fileName)

                try videoData.write(to: fileURL)

                await MainActor.run {
                    self.selectedVideoURL = fileURL
                    self.selectedVideoName = fileName
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load video: \(error.localizedDescription)"
                    self.showError = true
                }
            }
        }
    }

    func clearSelection() {
        selectedVideoName = nil
        selectedVideoURL = nil
        selectedItem = nil
    }

    func startUpload() {
        guard let videoURL = selectedVideoURL,
              let skill = selectedSkill else {
            errorMessage = "Please select a video and skill"
            showError = true
            return
        }

        isUploading = true
        uploadProgress = 0.0
        viewModel.selectedSkill = skill

        Task {
            do {
                // Simulate progress for better UX
                let progressTask = Task {
                    for i in 1...5 {
                        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                        await MainActor.run {
                            uploadProgress = min(Double(i) * 0.15, 0.75)
                        }
                    }
                }

                // Make the actual API call
                let response = try await APIClient.shared.analyzeVideo(
                    skill: skill.id,
                    videoURL: videoURL
                )

                // Cancel progress simulation
                progressTask.cancel()

                await MainActor.run {
                    uploadProgress = 1.0

                    if response.success, response.feedback != nil || response.analysis != nil {
                        viewModel.analysisResult = response.analysis
                        viewModel.feedbackResult = response.feedback
                        isUploading = false
                        uploadComplete = true
                    } else {
                        isUploading = false
                        errorMessage = response.error ?? "Analysis failed - no data returned"
                        showError = true
                    }
                }
            } catch {
                await MainActor.run {
                    isUploading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    func resetFlow() {
        uploadComplete = false
        selectedVideoName = nil
        selectedVideoURL = nil
        selectedItem = nil
        uploadProgress = 0.0
        viewModel.reset()
    }
}

// MARK: - Video Thumbnail View

struct VideoThumbnailView: View {
    let url: URL
    @State private var thumbnail: UIImage? = nil

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color.black.opacity(0.1))
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                }
            }
        }
        .onAppear {
            generateThumbnail()
        }
    }

    func generateThumbnail() {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)

        Task {
            do {
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                await MainActor.run {
                    self.thumbnail = UIImage(cgImage: cgImage)
                }
            } catch {
                print("Thumbnail generation failed: \(error)")
            }
        }
    }
}

#Preview {
    NavigationView {
        UploadVideoView()
    }
}
