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
                    Text("Choose a prepared video and, if you want, its completed 3D motion. Only the items you confirm become available to this circle.").font(.callout).foregroundStyle(SL.muted)
                    if let previous { Label("Linked to your earlier \(previous.skill) attempt", systemImage: "arrow.triangle.2.circlepath").font(.callout).foregroundStyle(SL.green) }
                }
                Section("Your prepared video") { projectChoices }
                if selected != nil { motionChoice }
                Section("What are you practising?") {
                    TextField("Skill or move", text: $skill).accessibilityIdentifier("share-skill").disabled(model.isWorking)
                    TextField("What would you like feedback on? (optional)", text: $note, axis: .vertical).lineLimit(3...6).accessibilityIdentifier("share-note").disabled(model.isWorking)
                    Text("Skill: \(skill.count)/60 · Note: \(note.count)/500").font(.caption).foregroundStyle(SL.muted)
                }
                if let error = model.errorMessage { Section { CommunityNotice(message: error) } }
                Section {
                    Button { confirmShare = true } label: {
                        if model.isWorking {
                            HStack(spacing: 8) {
                                SLActivityIndicator(size: 16)
                                Text("Sharing attempt…")
                            }
                        }
                        else { Label("Review and share", systemImage: "person.3") }
                    }.buttonStyle(.slPrimary).disabled(!valid || model.isWorking)
                }
            }
            .scrollContentBackground(.hidden).background(SL.page).slScreen()
            .navigationTitle(previous == nil ? "Share attempt" : "Another attempt").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.isWorking) } }
            .interactiveDismissDisabled(model.isWorking)
            .task { await model.load() }
            .task(id: projectID) { await model.selectProject(selected) }
            .onDisappear { model.stop() }
            .confirmationDialog("Share \(model.includeMotion ? "video and 3D motion" : "this video") with \(circle.name)?", isPresented: $confirmShare, titleVisibility: .visible) {
                Button(model.includeMotion ? "Share video and 3D motion" : "Share prepared video") {
                    guard let selected else { return }
                    Task {
                        if let post = await model.share(project: selected, skill: skill, note: note) { onShared(post); dismiss() }
                    }
                }
            } message: {
                Text("Current and future members of this circle can watch the prepared video\(model.includeMotion ? " and explore the selected 3D motion" : ""), read your note, and leave feedback. Members may save a copy\(model.includeMotion ? " of the video and motion files" : ""). You can remove the shared attempt later; your private originals are kept.")
            }
        }.tint(SL.green)
    }

    private var motionChoice: some View {
        Section("3D motion · optional") {
            if model.isLoadingMotion { SLLoadingState(title: "Checking for 3D motion…", detail: "Looking for a completed result linked to this video.") }
            if let motion = model.motionCandidate {
                Toggle("Include this 3D motion", isOn: $model.includeMotion)
                    .accessibilityIdentifier("share-include-motion")
                Text("Selected motion: \(CommunityValidation.timeLabel(motion.startTime))–\(CommunityValidation.timeLabel(motion.startTime + motion.duration)) in your video.")
                    .font(.caption.monospacedDigit()).foregroundStyle(SL.muted)
                if motion.reconstruction.outcome == "partial" {
                    Label("Some frames have no reconstructed pose.", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(SL.noticeText)
                }
                Text("This shares the current result with the circle. Future generated results stay private until you share them separately.").font(.footnote).foregroundStyle(SL.muted)
            } else if let message = model.motionMessage { Text(message).font(.callout).foregroundStyle(SL.muted) }
            Text("Video only is the default. You can share a video even when no 3D motion is available.").font(.footnote).foregroundStyle(SL.muted)
        }.disabled(model.isWorking)
    }

    private var projectChoices: some View {
        Group {
            if model.isLoading { SLLoadingState(title: "Loading your videos…", detail: "Only prepared videos from your private library can be shared.") }
            if model.projects.isEmpty && !model.isLoading && model.errorMessage == nil {
                CommunityEmpty(title: "Your next attempt starts here", text: "Import a private video from Videos and wait for preparation to finish, then return here to share it.", icon: "video.badge.plus")
            }
            ForEach(model.projects) { project in
                Button {
                    if projectID != project.id { model.clearMotionSelection(); projectID = project.id }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.title).font(.callout.weight(.semibold))
                            if let media = project.preparedMedia { Text(CommunityValidation.timeLabel(media.duration)).font(.caption.monospacedDigit()).foregroundStyle(SL.muted) }
                        }
                        Spacer()
                        Image(systemName: projectID == project.id ? "checkmark.circle.fill" : "circle").foregroundStyle(SL.green).accessibilityHidden(true)
                    }.foregroundStyle(SL.ink).frame(minHeight: 44)
                }.accessibilityAddTraits(projectID == project.id ? .isSelected : [])
            }
            if model.nextCursor != nil {
                Button("Load more videos") { Task { await model.load(more: true) } }.disabled(model.isLoading)
            }
            Button { Task { await model.load() } } label: {
                Label("Refresh videos", systemImage: "arrow.clockwise")
            }.disabled(model.isLoading || model.isWorking)
        }.disabled(model.isWorking)
    }
}
