import SwiftUI

struct CommunityView: View {
    let hasAccount: Bool
    @State private var model = CommunityViewModel()
    @State private var form: CircleEntryForm.Kind?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    introduction
                    if hasAccount { signedInContent }
                    else { signInMessage }
                }.padding(20)
            }
            .background(SL.page).foregroundStyle(SL.ink)
            .navigationTitle("Community")
            .refreshable { if hasAccount { await model.refresh() } }
            .task(id: scenePhase) { if hasAccount && scenePhase == .active { await model.watch() } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { model.stop() } }
            .onDisappear { model.stop() }
            .sheet(item: $form) { kind in CircleEntryForm(kind: kind, model: model) }
        }.tint(SL.green)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "TRAIN TOGETHER", rule: true)
            Text("Your people.\nYour next attempt.").font(SL.display(30, .bold)).tracking(-0.6)
            Text("Create a private training circle, share an attempt, and help each other improve with feedback at the right moment.")
                .font(.callout).foregroundStyle(SL.ink)
        }.accessibilityIdentifier("community-introduction")
    }

    private var signInMessage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sign in to train together", systemImage: "person.crop.circle.badge.checkmark").font(.headline)
            Text("Training circles belong to your account. Sign in from the app's account screen to create or join a circle. The local example stays on this device and can't be shared.")
                .font(.callout)
        }.padding(18).slPanel().accessibilityIdentifier("community-sign-in-required")
    }

    private var signedInContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button { form = .create } label: { Label("Create circle", systemImage: "plus") }.buttonStyle(.slPrimary)
                Button { form = .join } label: { Label("Join", systemImage: "person.badge.plus") }.buttonStyle(.slSecondary)
            }.disabled(model.client == nil || model.isWorking)
            if let error = model.errorMessage { CommunityNotice(message: error) }
            if model.isLoading { ProgressView("Loading your circles…") }
            if !model.isLoading && model.circles.isEmpty && model.errorMessage == nil {
                CommunityEmpty(title: "Start with your training partners", text: "Create a circle for friends or teammates, or enter an invite code from someone you know.", icon: "person.3")
            }
            if let client = model.client {
                ForEach(model.circles) { circle in
                    NavigationLink {
                        CircleDetailView(circle: circle, client: client)
                    } label: { CircleCard(circle: circle) }.buttonStyle(.plain)
                }
            }
            Button("Refresh circles") { Task { await model.refresh() } }.font(.callout).disabled(model.isLoading || model.client == nil)
            Text("Only circle members can view shared attempts. Your other videos stay private.")
                .font(.footnote).foregroundStyle(SL.ink)
        }
    }
}

private struct CircleCard: View {
    let circle: TrainingCircle
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.3.fill").font(.title3).foregroundStyle(SL.green).frame(width: 44, height: 44).background(SL.iconTile, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(circle.name).font(.headline)
                Text("\(circle.memberCount) \(circle.memberCount == 1 ? "member" : "members") · Private circle").font(.caption).foregroundStyle(SL.ink)
                if !circle.description.isEmpty { Text(circle.description).font(.callout).lineLimit(2) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption)
        }.padding(16).slPanel()
    }
}

struct CommunityNotice: View {
    let message: String
    var body: some View {
        Text(message).font(.callout).foregroundStyle(SL.errorText).frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).background(SL.errorFill, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("community-error")
    }
}

struct CommunityEmpty: View {
    let title: String
    let text: String
    let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.title2).foregroundStyle(SL.green)
            Text(title).font(.headline)
            Text(text).font(.callout)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).slPanel()
    }
}

private struct CircleEntryForm: View {
    enum Kind: String, Identifiable { case create, join; var id: String { rawValue } }
    let kind: Kind
    @Bindable var model: CommunityViewModel
    @State private var name = ""
    @State private var description = ""
    @State private var code = ""
    @Environment(\.dismiss) private var dismiss
    private var valid: Bool {
        if kind == .join { return !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && code.count <= 128 }
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80 && description.count <= 240
    }
    var body: some View {
        NavigationStack {
            Form {
                if kind == .create {
                    Section("Your training circle") {
                        TextField("Circle name", text: $name).accessibilityIdentifier("circle-name")
                        TextField("What are you working on? (optional)", text: $description, axis: .vertical).lineLimit(3...5)
                        Text("Name: \(name.count)/80 · Description: \(description.count)/240").font(.caption)
                    }
                    Section { Text("Your circle starts with you. Generate an invite code inside the circle when you're ready to add people.") }
                } else {
                    Section("Invite code") {
                        TextField("Enter the code", text: $code).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("circle-invite-code")
                        Text("Ask the circle owner for a current invite code. By joining, you can see shared attempts and your name appears to other members.")
                    }
                }
                if let error = model.errorMessage { Section { CommunityNotice(message: error) } }
                Section {
                    Button {
                        Task {
                            let saved = kind == .create ? await model.create(name: name, description: description) : await model.join(code: code)
                            if saved { dismiss() }
                        }
                    } label: {
                        if model.isWorking { ProgressView("Saving…") }
                        else { Text(kind == .create ? "Create private circle" : "Join circle") }
                    }.disabled(!valid || model.isWorking)
                }
            }
            .navigationTitle(kind == .create ? "Create circle" : "Join circle").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.isWorking) } }
            .interactiveDismissDisabled(model.isWorking)
        }.tint(SL.green)
    }
}
