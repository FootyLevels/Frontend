import SwiftUI

struct CircleShareView: View {
    let circle: TrainingCircle
    let previous: CirclePost?
    let onShared: (CirclePost) -> Void
    @State private var model: CircleShareViewModel
    @State private var projectID = ""
    @State private var skill: String
    @State private var note = ""
    @State private var confirmShare = false
    @Environment(\.dismiss) private var dismiss

    init(circle: TrainingCircle, client: CommunityClient, previous: CirclePost?, onShared: @escaping (CirclePost) -> Void) {
        self.circle = circle; self.previous = previous; self.onShared = onShared
        _model = State(initialValue: CircleShareViewModel(client: client, circleID: circle.id, previous: previous))
        _skill = State(initialValue: previous?.skill ?? "")
    }
    private var selected: CloudProject? { model.projects.first { $0.id == projectID } }
    private var valid: Bool {
        selected != nil && !skill.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && skill.count <= 60 && note.count <= 500
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Share with \(circle.name)").font(.headline)
                    Text("Only a video you choose here becomes available to this circle. Your other videos and generated 3D stay private.").font(.callout)
                    if let previous { Label("Linked to your earlier \(previous.skill) attempt", systemImage: "arrow.triangle.2.circlepath").font(.callout) }
                }
                Section("Your prepared video") { projectChoices }
                Section("What are you practising?") {
                    TextField("Skill or move", text: $skill).accessibilityIdentifier("share-skill")
                    TextField("What would you like feedback on? (optional)", text: $note, axis: .vertical).lineLimit(3...6).accessibilityIdentifier("share-note")
                    Text("Skill: \(skill.count)/60 · Note: \(note.count)/500").font(.caption)
                }
                if let error = model.errorMessage { Section { CommunityNotice(message: error) } }
                Section {
                    Button { confirmShare = true } label: {
                        if model.isWorking { ProgressView("Sharing attempt…") }
                        else { Label("Review and share", systemImage: "person.3") }
                    }.disabled(!valid || model.isWorking)
                }
            }
            .navigationTitle(previous == nil ? "Share attempt" : "Another attempt").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.isWorking) } }
            .interactiveDismissDisabled(model.isWorking)
            .task { await model.load() }
            .onDisappear { model.stop() }
            .confirmationDialog("Share this video with \(circle.name)?", isPresented: $confirmShare, titleVisibility: .visible) {
                Button("Share prepared video") {
                    guard let selected else { return }
                    Task {
                        if let post = await model.share(project: selected, skill: skill, note: note) { onShared(post); dismiss() }
                    }
                }
            } message: {
                Text("Current and future members of this circle can watch the prepared video, read your note, and leave feedback. Members may save a copy. You can remove the shared attempt later; your private original is kept.")
            }
        }.tint(SL.green)
    }

    private var projectChoices: some View {
        Group {
            if model.isLoading { ProgressView("Loading your videos…") }
            if model.projects.isEmpty && !model.isLoading {
                Text("No prepared videos yet. Import a private video from Videos and wait for preparation to finish, then return here.").font(.callout)
            }
            ForEach(model.projects) { project in
                Button { projectID = project.id } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.title)
                            if let media = project.preparedMedia { Text(CommunityValidation.timeLabel(media.duration)).font(.caption.monospacedDigit()) }
                        }
                        Spacer()
                        Image(systemName: projectID == project.id ? "checkmark.circle.fill" : "circle").foregroundStyle(SL.green)
                    }.foregroundStyle(SL.ink)
                }.accessibilityAddTraits(projectID == project.id ? .isSelected : [])
            }
            if model.nextCursor != nil {
                Button("Load more videos") { Task { await model.load(more: true) } }.disabled(model.isLoading)
            }
            Button("Refresh videos") { Task { await model.load() } }.disabled(model.isLoading || model.isWorking)
        }.disabled(model.isWorking)
    }
}
