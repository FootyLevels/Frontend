import SwiftUI

struct CircleDetailView: View {
    @State private var model: CircleDetailViewModel
    @State private var showShare = false
    @State private var showMembers = false
    @State private var showInvite = false
    @State private var confirmExit = false
    @State private var pendingPost: CirclePost?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(circle: TrainingCircle, client: CommunityClient) {
        _model = State(initialValue: CircleDetailViewModel(circle: circle, client: client))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if model.hasAccess { header }
                if let error = model.errorMessage { CommunityNotice(message: error) }
                if model.isLoading {
                    SLLoadingState(title: "Loading circle…", detail: "Checking membership and shared attempts.")
                }
                if model.isWorking {
                    HStack(spacing: 8) {
                        SLActivityIndicator(size: 16)
                        Text("Updating your circle…").font(.callout).foregroundStyle(SL.muted)
                    }.accessibilityElement(children: .combine)
                }
                if model.posts.isEmpty && !model.isLoading && model.errorMessage == nil {
                    CommunityEmpty(title: "Make the first attempt", text: "Share a prepared video and tell your circle what you're working on. Your teammates can add feedback at a specific moment.", icon: "video.badge.plus")
                }
                ForEach(model.posts) { post in postRow(post) }
                if model.nextCursor != nil {
                    Button("Load more attempts") { Task { await model.refresh(more: true) } }.buttonStyle(.slSecondary).disabled(model.isLoading || model.isWorking)
                }
            }.padding(20)
        }
        .background(SL.page).slScreen()
        .navigationTitle(model.circle.name).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { circleMenu } }
        .refreshable { await model.refresh() }
        .task(id: scenePhase) { if scenePhase == .active { await model.watch() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.stop() } }
        .onDisappear { model.stop() }
        .onChange(of: model.isRemoved) { _, removed in if removed { dismiss() } }
        .sheet(isPresented: $showShare) {
            CircleShareView(circle: model.circle, client: model.client, previous: nil, onShared: model.didShare)
        }
        .sheet(isPresented: $showMembers) { CircleMembersView(model: model) }
        .sheet(isPresented: $showInvite) { CircleInviteView(model: model) }
        .confirmationDialog(model.isOwner ? "Delete this circle?" : "Leave this circle?", isPresented: $confirmExit, titleVisibility: .visible) {
            Button(model.isOwner ? "Delete circle" : "Leave circle", role: .destructive) {
                Task {
                    if model.isOwner { await model.delete() }
                    else if let member = model.circle.members.first(where: { $0.uid == model.client.account.uid }) { await model.removeMember(member) }
                }
            }
        } message: {
            Text(model.isOwner ? "All members will lose access to the circle, its shared attempts, and feedback. Original private videos are kept." : "You will lose access to the circle and its shared attempts. Your posts and feedback will be removed from this circle. Original private videos are kept.")
        }
        .confirmationDialog("Remove this shared attempt?", isPresented: Binding(get: { pendingPost != nil }, set: { if !$0 { pendingPost = nil } }), titleVisibility: .visible) {
            if let post = pendingPost { Button("Remove attempt", role: .destructive) { Task { await model.removePost(post); pendingPost = nil } } }
        } message: { Text("Members will no longer be able to view this attempt or its feedback. The author's private video is kept.") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("PRIVATE TRAINING CIRCLE", systemImage: "lock.shield").font(.caption.weight(.semibold)).foregroundStyle(SL.green)
            if !model.circle.description.isEmpty { Text(model.circle.description).font(.callout) }
            HStack {
                Button { showMembers = true } label: {
                    Label("\(model.circle.memberCount) members", systemImage: "person.2")
                }.font(.callout.weight(.semibold))
                Spacer()
                Button { showShare = true } label: { Label("Share attempt", systemImage: "plus") }.buttonStyle(.slPrimary)
            }.disabled(model.isWorking || model.isRemoved)
            Text("Share a prepared video and optionally include its completed 3D motion. Your other projects stay private.").font(.footnote).foregroundStyle(SL.muted)
        }.padding(16).slPanel()
    }
    private var circleMenu: some View {
        Menu {
            Button("Members", systemImage: "person.3") { showMembers = true }
            if model.isOwner { Button("Invite people", systemImage: "person.badge.plus") { showInvite = true } }
            Button(model.isOwner ? "Delete circle…" : "Leave circle…", systemImage: model.isOwner ? "trash" : "rectangle.portrait.and.arrow.right", role: .destructive) { confirmExit = true }
        } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("Circle actions") }
            .disabled(model.isWorking || model.isRemoved || !model.hasAccess)
    }
    private func postRow(_ post: CirclePost) -> some View {
        NavigationLink {
            CirclePostView(post: post, circle: model.circle, client: model.client, onShared: model.didShare,
                onRemoved: { model.posts.removeAll { $0.id == post.id } })
        } label: { CirclePostCard(post: post) }
            .buttonStyle(.plain)
            .contextMenu {
                if post.authorId == model.client.account.uid || model.isOwner {
                    Button("Remove shared attempt…", role: .destructive) { pendingPost = post }.disabled(model.isWorking)
                }
            }
    }
}

struct CirclePostCard: View {
    let post: CirclePost
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(post.skill, systemImage: "figure.soccer").font(.headline).foregroundStyle(SL.ink)
                Spacer()
                Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(SL.green)
            }
            Text(post.projectTitle).font(.callout.weight(.semibold)).foregroundStyle(SL.ink)
            if !post.note.isEmpty { Text(post.note).font(.callout).foregroundStyle(SL.muted).lineLimit(4) }
            HStack {
                Text(post.authorName.isEmpty ? "Circle member" : post.authorName)
                Spacer()
                Text(CommunityValidation.timeLabel(post.video.duration)).monospacedDigit()
            }.font(.caption).foregroundStyle(SL.muted)
            if post.motion != nil { Label("Video + 3D motion", systemImage: "cube").font(.caption.weight(.semibold)).foregroundStyle(SL.green) }
            if post.previousPostId != nil { Label("Another attempt", systemImage: "arrow.triangle.2.circlepath").font(.caption.weight(.semibold)).foregroundStyle(SL.green) }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).slPanel()
            .accessibilityElement(children: .combine)
    }
}

private struct CircleMembersView: View {
    @Bindable var model: CircleDetailViewModel
    @State private var removing: TrainingCircle.Member?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if let error = model.errorMessage { CommunityNotice(message: error) }
                if model.isWorking { SLLoadingState(title: "Updating members…") }
                ForEach(model.circle.members) { member in
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(member.displayName.isEmpty ? "Circle member" : member.displayName).foregroundStyle(SL.ink)
                            if member.uid == model.circle.ownerId { Text("Circle owner").font(.caption).foregroundStyle(SL.muted) }
                            else if member.uid == model.client.account.uid { Text("You").font(.caption).foregroundStyle(SL.muted) }
                        }
                        Spacer()
                        if model.isOwner && member.uid != model.circle.ownerId {
                            Button("Remove", role: .destructive) { removing = member }.font(.callout).disabled(model.isWorking)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(SL.page).slScreen()
            .navigationTitle("Members").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(model.isWorking) } }
            .interactiveDismissDisabled(model.isWorking)
            .confirmationDialog("Remove this member?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                if let member = removing { Button("Remove member", role: .destructive) { Task { await model.removeMember(member); removing = nil } } }
            } message: { Text("They will lose circle access, and their shared attempts and feedback will be removed. The existing invite code will stop working. Their private videos are kept.") }
        }.tint(SL.tint)
    }
}

private struct CircleInviteView: View {
    @Bindable var model: CircleDetailViewModel
    @State private var rotate = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CommunityEmpty(title: "Invite your training partners", text: "Anyone with this code can join the circle and see its shared attempts. Share it only with people you want in the group. The code expires after seven days.", icon: "person.badge.plus")
                    if let invite = model.invite {
                        Text(invite.code).font(.system(.body, design: .monospaced, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                            .background(SL.card, in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityIdentifier("generated-circle-code")
                        ShareLink(item: "Join my FootyLevels training circle ‘\(model.circle.name)’ with invite code: \(invite.code)") {
                            Label("Share invite", systemImage: "square.and.arrow.up")
                        }.buttonStyle(.slPrimary).disabled(model.isWorking)
                        Text("Expires \(invite.expiresAt)").font(.caption).foregroundStyle(SL.muted)
                    }
                    if let error = model.errorMessage { CommunityNotice(message: error) }
                    Button(model.invite == nil ? "Generate invite code" : "Replace invite code…") {
                        if model.invite == nil { Task { await model.generateInvite() } }
                        else { rotate = true }
                    }.buttonStyle(.slSecondary).disabled(model.isWorking)
                    if model.isWorking { SLLoadingState(title: "Generating invite…", detail: "Creating a private code for your training circle.") }
                }.padding(20)
            }.background(SL.page).slScreen()
                .navigationTitle("Invite people").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(model.isWorking) } }
                .interactiveDismissDisabled(model.isWorking)
                .confirmationDialog("Replace the current invite code?", isPresented: $rotate, titleVisibility: .visible) {
                    Button("Replace code") { Task { await model.generateInvite() } }
                } message: { Text("The previous code will stop working. Existing members keep their access.") }
        }.tint(SL.tint)
    }
}
