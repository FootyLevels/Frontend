import AVKit
import SwiftUI

struct CirclePostView: View {
    let circle: TrainingCircle
    let onShared: (CirclePost) -> Void
    let onRemoved: () -> Void
    @State private var model: CirclePostViewModel
    @State private var showRetry = false
    @State private var confirmRemove = false
    @State private var removingComment: CircleComment?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(post: CirclePost, circle: TrainingCircle, client: CommunityClient,
         onShared: @escaping (CirclePost) -> Void, onRemoved: @escaping () -> Void) {
        self.circle = circle; self.onShared = onShared; self.onRemoved = onRemoved
        _model = State(initialValue: CirclePostViewModel(post: post, client: client))
    }
    private var canRemove: Bool { model.post.authorId == model.client.account.uid || circle.ownerId == model.client.account.uid }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if model.hasAccess { postHeader }
                if let error = model.errorMessage { CommunityNotice(message: error) }
                video
                if model.hasAccess {
                    if model.post.motion != nil { motionPanel }
                    attemptLinks
                    commentComposer
                    comments
                }
            }.padding(20)
        }
        .background(SL.page).slScreen()
        .navigationTitle(model.hasAccess ? model.post.skill : "Shared attempt").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.hasAccess && canRemove { ToolbarItem(placement: .topBarTrailing) { Button("Remove", role: .destructive) { confirmRemove = true }.disabled(model.isWorking) } }
        }
        .refreshable { await model.refresh() }
        .task(id: scenePhase) { if scenePhase == .active { await model.watch() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.stop() } }
        .onDisappear { model.stop() }
        .onChange(of: model.hasAccess) { _, allowed in
            if !allowed { showRetry = false; confirmRemove = false; removingComment = nil }
        }
        .sheet(isPresented: $showRetry) {
            CircleShareView(circle: circle, client: model.client, previous: model.post, onShared: onShared)
        }
        .confirmationDialog("Remove this shared attempt?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove attempt", role: .destructive) {
                Task { if await model.removePost() { onRemoved(); dismiss() } }
            }
        } message: { Text("Members will lose access to this attempt and its feedback. The author's private video is kept.") }
        .confirmationDialog("Remove this comment?", isPresented: Binding(get: { removingComment != nil }, set: { if !$0 { removingComment = nil } }), titleVisibility: .visible) {
            if let comment = removingComment { Button("Remove comment", role: .destructive) { Task { await model.removeComment(comment); removingComment = nil } } }
        }
    }

    private var postHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("SHARED WITH \(circle.name.uppercased())", systemImage: "lock.shield").font(.caption.weight(.semibold)).foregroundStyle(SL.green)
            Text(model.post.projectTitle).font(SL.display(24, .bold))
            Text("By \(model.post.authorName.isEmpty ? "a circle member" : model.post.authorName)").font(.callout).foregroundStyle(SL.muted)
            if !model.post.note.isEmpty { Text(model.post.note).font(.callout) }
        }
    }

    private var video: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let playback = model.playback {
                VideoPlayer(player: playback.player).frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 10))
                    .id(ObjectIdentifier(playback)).accessibilityIdentifier("circle-shared-video")
                Picker("Playback speed", selection: Binding(get: { playback.speed }, set: { playback.speed = $0 })) {
                    ForEach(PlaybackController.speeds, id: \.self) { Text("\($0.formatted())×").tag($0) }
                }.pickerStyle(.segmented)
            } else if model.isLoading {
                SLLoadingState(title: "Loading shared video…", detail: "Verifying circle access and preparing secure playback.")
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
            else {
                Button { Task { await model.refresh() } } label: {
                    Label("Reload shared video", systemImage: "arrow.clockwise")
                }.buttonStyle(.slSecondary).disabled(model.isWorking)
            }
        }
    }
    private var motionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("SHARED 3D MOTION", systemImage: "cube").font(.caption.weight(.semibold)).foregroundStyle(SL.green)
            if let motion = model.motion {
                ZStack {
                    ModelStageView(root: motion.stageRoot, camera: motion.camera).id(ObjectIdentifier(motion))
                        .accessibilityIdentifier("circle-shared-motion").accessibilityValue(motion.accessibilityStatus)
                    switch motion.state {
                    case .loading(let message): SLLoadingState(title: message).padding(16)
                    case .failed(let message): CommunityNotice(message: message).padding(16)
                    case .ready: EmptyView()
                    }
                    if motion.isOutsideSegment {
                        Text("Play the selected motion segment to see its 3D pose.").font(.callout).foregroundStyle(SL.ink)
                            .padding(16).background(SL.panel, in: RoundedRectangle(cornerRadius: 10)).padding(16)
                    }
                }.frame(height: 320).clipped().background(SL.stage)
                if motion.missingPose && !motion.isOutsideSegment {
                    Label("Player not reconstructed in this frame", systemImage: "exclamationmark.circle")
                        .font(.callout).foregroundStyle(SL.noticeText)
                }
                if motion.waitingForChunk {
                    HStack(spacing: 8) {
                        SLActivityIndicator(size: 16)
                        Text("Loading this frame’s 3D data…").font(.callout).foregroundStyle(SL.muted)
                    }.accessibilityElement(children: .combine)
                }
                if let warning = motion.assetWarning { CommunityNotice(message: warning) }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) { ForEach(CameraAngle.allCases) { angle in Button(angle.rawValue) { motion.show(angle) }.buttonStyle(.slSecondary) } }.font(.callout)
                }
                HStack {
                    Toggle("Follow", isOn: Binding(get: { motion.follow }, set: { motion.follow = $0 }))
                    Toggle("Wireframe", isOn: Binding(get: { motion.wireframe }, set: { motion.wireframe = $0 }))
                }.font(.callout)
                Button("Close 3D motion") { model.closeMotion() }.font(.callout)
            } else {
                Button { model.openMotion() } label: { Label("Open shared 3D motion", systemImage: "cube.transparent") }
                    .buttonStyle(.slSecondary).disabled(model.isLoadingMotion || model.playback == nil)
            }
            if model.isLoadingMotion { SLLoadingState(title: "Loading shared 3D motion…", detail: "Verifying the selected motion and downloading its model data.") }
            if let error = model.motionErrorMessage { CommunityNotice(message: error) }
            if let shared = model.post.motion {
                Button("Jump to motion segment · \(CommunityValidation.timeLabel(shared.startTime))–\(CommunityValidation.timeLabel(shared.startTime + shared.duration))") { model.seekToMotion() }
                    .font(.callout).disabled(model.playback == nil)
            }
            Text("The video controls also move the 3D model. Feedback timestamps always refer to the full video. Drag the model to orbit.")
                .font(.footnote).foregroundStyle(SL.muted)
        }.padding(16).slPanel()
    }

    private var attemptLinks: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let id = model.post.previousPostId {
                NavigationLink {
                    PreviousCircleAttemptView(id: id, circle: circle, client: model.client, onShared: onShared)
                } label: { Label("View previous attempt", systemImage: "arrow.uturn.backward") }.font(.callout)
            }
            if model.post.authorId == model.client.account.uid {
                Button { showRetry = true } label: { Label("Share another attempt", systemImage: "arrow.triangle.2.circlepath") }.buttonStyle(.slSecondary).disabled(model.isWorking)
            }
        }
    }
    private var commentComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Help with the next attempt").font(.headline)
            TextField("Add specific, encouraging feedback", text: $model.commentText, axis: .vertical)
                .lineLimit(3...6).padding(12).background(SL.card, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(SL.cardBorder))
                .disabled(model.isWorking)
                .accessibilityIdentifier("circle-comment-text")
            HStack {
                if let time = model.attachedTime {
                    Button { model.attachedTime = nil } label: { Label("\(CommunityValidation.timeLabel(time)) · Remove time", systemImage: "xmark.circle") }.font(.caption.monospacedDigit()).disabled(model.isWorking)
                } else {
                    Button { model.attachCurrentTime() } label: { Label("Attach current video time", systemImage: "clock.badge.plus") }.font(.callout).disabled(model.playback == nil || model.isWorking)
                }
                Spacer()
                Text("\(model.commentText.count)/500").font(.caption).foregroundStyle(model.commentText.count > 500 ? SL.errorText : SL.muted)
            }
            Button {
                Task { _ = await model.sendComment() }
            } label: {
                HStack(spacing: 8) {
                    if model.isWorking { SLActivityIndicator(size: 16) }
                    Text(model.isWorking ? "Saving…" : "Post feedback")
                }
            }
                .buttonStyle(.slPrimary).disabled(model.isWorking || model.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.commentText.count > 500)
        }.padding(16).slPanel()
    }
    private var comments: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Feedback").font(.headline).accessibilityAddTraits(.isHeader)
            if model.isLoadingComments { SLLoadingState(title: "Loading feedback…") }
            if model.comments.isEmpty && !model.isLoadingComments {
                CommunityEmpty(title: "Start the conversation", text: "Share one specific, encouraging tip that could help the next attempt.", icon: "bubble.left.and.bubble.right")
            }
            ForEach(model.comments) { comment in commentRow(comment) }
            if model.nextCursor != nil { Button("Load more feedback") { Task { await model.loadComments(more: true) } }.buttonStyle(.slSecondary).disabled(model.isLoadingComments || model.isWorking) }
        }
    }
    private func commentRow(_ comment: CircleComment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(comment.authorName.isEmpty ? "Circle member" : comment.authorName).font(.callout.weight(.semibold))
                Spacer()
                if let time = comment.timestamp {
                    Button(CommunityValidation.timeLabel(time)) { model.seek(comment: comment) }
                        .font(.caption.monospacedDigit()).disabled(model.playback == nil)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Jump to \(CommunityValidation.timeLabel(time))")
                }
                if comment.authorId == model.client.account.uid || circle.ownerId == model.client.account.uid {
                    Button { removingComment = comment } label: {
                        Image(systemName: "trash").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                            .accessibilityLabel("Remove comment")
                    }.disabled(model.isWorking)
                }
            }
            Text(comment.text).font(.callout)
        }.padding(14).slPanel()
    }
}

private struct PreviousCircleAttemptView: View {
    let id: String
    let circle: TrainingCircle
    let client: CommunityClient
    let onShared: (CirclePost) -> Void
    @State private var post: CirclePost?
    @State private var error: String?
    var body: some View {
        Group {
            if let post { CirclePostView(post: post, circle: circle, client: client, onShared: onShared, onRemoved: {}) }
            else if let error { CommunityNotice(message: error).padding(20) }
            else { SLLoadingState(title: "Loading previous attempt…", detail: "Checking that this attempt is still shared with your circle.").padding(20) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(SL.page).slScreen()
        .task {
            do {
                let item = try await client.post(circle: circle.id, id: id)
                try client.checkSession(); guard !Task.isCancelled else { return }; post = item
            } catch { self.error = CommunityValidation.message(error) }
        }
        .onDisappear { post = nil }
    }
}
