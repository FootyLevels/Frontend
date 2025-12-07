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
    @State private var showSkillPicker = false

    // Optional preselected skill
    var preselectedSkill: SkillInfo? = nil

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "video.badge.checkmark")
                    .resizable()
                    .frame(width: 60, height: 50)
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
        .sheet(isPresented: $showSkillPicker) {
            SkillPickerSheet(skills: skills, selectedSkill: $selectedSkill)
        }
        .onAppear {
            loadSkills()
            if let preselected = preselectedSkill {
                selectedSkill = preselected
            }
        }
    }

    // MARK: - Subviews

    var selectionView: some View {
        VStack(spacing: 20) {
            // Skill Selector
            if isLoadingSkills {
                ProgressView("Loading skills...")
                    .padding()
            } else {
                skillSelectorCard
            }

            // Video Selection
            if let videoName = selectedVideoName {
                selectedVideoCard(videoName: videoName)
            } else {
                videoPickerButton
            }

            // Analyze Button
            if selectedVideoName != nil {
                analyzeButton
            }
        }
    }

    var skillSelectorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected Skill")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: { showSkillPicker = true }) {
                HStack {
                    if let skill = selectedSkill {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(skill.name)
                                .font(.headline)
                                .foregroundColor(AppTheme.textColor)

                            HStack(spacing: 8) {
                                Image(systemName: skill.difficultyIcon)
                                    .font(.caption)
                                Text(skill.difficulty.capitalized)
                                    .font(.caption)

                                if let playerName = skill.playerName {
                                    Text("•")
                                        .font(.caption)
                                    Text(playerName)
                                        .font(.caption)
                                }
                            }
                            .foregroundColor(Color(hex: skill.difficultyColor))
                        }
                    } else {
                        Text("Choose a skill...")
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.down.circle.fill")
                        .foregroundColor(AppTheme.primaryColor)
                }
                .padding()
                .background(AppTheme.surfaceColor)
                .cornerRadius(AppTheme.Metrics.cornerRadius)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            }
        }
    }

    func selectedVideoCard(videoName: String) -> some View {
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
    }

    var videoPickerButton: some View {
        PhotosPicker(
            selection: $selectedItem,
            matching: .videos
        ) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(AppTheme.primaryColor.opacity(0.1))
                        .frame(width: 80, height: 80)

                    Image(systemName: "video.badge.plus")
                        .font(.title)
                        .foregroundColor(AppTheme.primaryColor)
                }

                Text("Select Video")
                    .font(.headline)
                    .foregroundColor(AppTheme.secondaryColor)

                Text("Choose from your gallery")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .background(AppTheme.surfaceColor)
            .cornerRadius(AppTheme.Metrics.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Metrics.cornerRadius)
                    .stroke(AppTheme.primaryColor.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
            )
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 2)
        }
        .onChange(of: selectedItem) { newItem in
            handleVideoSelection(newItem)
        }
    }

    var analyzeButton: some View {
        Button(action: startUpload) {
            HStack {
                Image(systemName: "wand.and.stars")
                Text("Analyze Video")
            }
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding()
            .background(selectedSkill != nil ? AppTheme.primaryColor : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(AppTheme.Metrics.cornerRadius)
        }
        .disabled(selectedSkill == nil)
    }

    var uploadingView: some View {
        VStack(spacing: 20) {
            // Animated progress ring
            ZStack {
                Circle()
                    .stroke(AppTheme.primaryColor.opacity(0.2), lineWidth: 8)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: uploadProgress)
                    .stroke(AppTheme.primaryColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear, value: uploadProgress)

                Text("\(Int(uploadProgress * 100))%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.primaryColor)
            }

            Text(uploadProgress < 0.5 ? "Uploading Video..." : "Analyzing Movement...")
                .font(.headline)
                .foregroundColor(AppTheme.secondaryColor)

            if uploadProgress >= 0.5 {
                HStack(spacing: 8) {
                    Image(systemName: "brain")
                        .foregroundColor(AppTheme.accentColor)
                    Text("AI comparing to pro reference")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(32)
        .background(AppTheme.surfaceColor)
        .cornerRadius(AppTheme.Metrics.cornerRadius)
        .shadow(radius: 4)
    }

    var successView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppTheme.primaryColor.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .frame(width: 50, height: 50)
                    .foregroundColor(AppTheme.primaryColor)
            }

            Text("Analysis Complete!")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(AppTheme.textColor)

            Text("Your performance has been analyzed by our AI coach.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button(action: resetFlow) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("New Video")
                    }
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
                    HStack {
                        Image(systemName: "chart.bar.fill")
                        Text("View Results")
                    }
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
                    // Auto-select first skill if none preselected
                    if selectedSkill == nil && preselectedSkill == nil && !fetchedSkills.isEmpty {
                        selectedSkill = fetchedSkills.first
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingSkills = false
                    // Fallback: use sample skills
                    self.skills = SkillInfo.samples
                    if selectedSkill == nil {
                        self.selectedSkill = self.skills.first
                    }
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

// MARK: - Skill Picker Sheet

struct SkillPickerSheet: View {
    let skills: [SkillInfo]
    @Binding var selectedSkill: SkillInfo?
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var filteredSkills: [SkillInfo] {
        if searchText.isEmpty {
            return skills
        }
        return skills.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.playerName?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(["beginner", "intermediate", "advanced"], id: \.self) { difficulty in
                    let skillsInLevel = filteredSkills.filter { $0.difficulty == difficulty }
                    if !skillsInLevel.isEmpty {
                        Section(header: difficultyHeader(difficulty)) {
                            ForEach(skillsInLevel) { skill in
                                Button(action: {
                                    selectedSkill = skill
                                    dismiss()
                                }) {
                                    SkillPickerRow(skill: skill, isSelected: selectedSkill?.id == skill.id)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Search skills...")
            .navigationTitle("Choose Skill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    func difficultyHeader(_ difficulty: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: difficultyIcon(difficulty))
                .foregroundColor(Color(hex: difficultyColor(difficulty)))
            Text(difficulty.capitalized)
                .foregroundColor(Color(hex: difficultyColor(difficulty)))
        }
    }

    func difficultyIcon(_ difficulty: String) -> String {
        switch difficulty {
        case "beginner": return "1.circle.fill"
        case "intermediate": return "2.circle.fill"
        case "advanced": return "3.circle.fill"
        default: return "circle.fill"
        }
    }

    func difficultyColor(_ difficulty: String) -> String {
        switch difficulty {
        case "beginner": return "2ECC71"
        case "intermediate": return "F1C40F"
        case "advanced": return "E74C3C"
        default: return "2C3E50"
        }
    }
}

struct SkillPickerRow: View {
    let skill: SkillInfo
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(skill.name)
                    .font(.headline)
                    .foregroundColor(AppTheme.textColor)

                if let playerName = skill.playerName {
                    Text(playerName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppTheme.primaryColor)
            }
        }
        .contentShape(Rectangle())
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
