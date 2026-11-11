import SwiftUI

/// Learn's "From your videos": lessons the backend built from the user's own uploads.
/// Hidden when signed out, when no account server is configured, or when there are none.
@MainActor
@Observable
final class UserLessonsModel {
    private(set) var lessons: [CloudLesson] = []
    private(set) var client: CloudLessonClient?
    private(set) var store: UserLessonStore?
    private(set) var errorMessage: String?

    func load() async {
        do {
            guard let url = ApplicationEnvironment.apiBaseURL, FirebaseAPICredentials.shared.currentSession != nil else {
                lessons = []; return
            }
            var reusable = self.client
            if let existing = reusable, (try? existing.checkSession()) == nil { reusable = nil; self.store = nil }
            let client = try reusable
                ?? CloudLessonClient(apiURL: url, credentials: FirebaseAPICredentials.shared, environment: .current)
            let store = try self.store ?? UserLessonStore(uid: client.account.uid)
            self.client = client; self.store = store
            let found = try await client.lessons()
            lessons = found
            store.prune(keeping: Set(found.map(\.id)))
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
            client = nil
        }
    }
}

struct UserLessonsSection: View {
    @State private var model = UserLessonsModel()

    var body: some View {
        Group {
            if let client = model.client, let store = model.store, !model.lessons.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("From your videos").font(.system(.title2)).foregroundStyle(SL.ink)
                        Spacer(minLength: 8)
                        Label("AI-generated", systemImage: "sparkles").font(.footnote).foregroundStyle(SL.muted)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(model.lessons.enumerated()), id: \.element.id) { index, lesson in
                            if index > 0 { Divider().overlay(SL.line).padding(.leading, 16) }
                            NavigationLink {
                                UserLessonScreen(lesson: lesson, client: client, store: store) {
                                    Task { await model.load() }
                                }
                            } label: { row(lesson) }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(SL.card, in: RoundedRectangle(cornerRadius: 22))
                }
            }
        }
        .task { await model.load() }
    }

    private func row(_ lesson: CloudLesson) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(lesson.title).font(.system(.callout, weight: .semibold)).foregroundStyle(SL.ink)
                Text(lesson.skills.map(\.name).joined(separator: " · "))
                    .font(.footnote).foregroundStyle(SL.muted).lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(SL.muted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens your AI-generated lesson")
    }
}

/// Downloads one lesson into the device cache if needed, then plays it with the same
/// screen as the bundled lessons, plus the AI-generated notice.
struct UserLessonScreen: View {
    let lesson: CloudLesson
    let client: CloudLessonClient
    let store: UserLessonStore
    var onDeleted: () -> Void = {}

    @State private var entry: LessonLibrary.Entry?
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let entry {
                PackageLessonView(entry: entry, accessory: AnyView(
                    AILessonNotice(lesson: lesson, client: client, store: store) { onDeleted(); dismiss() }))
            } else if let errorMessage {
                ContentUnavailableView("Lesson unavailable", systemImage: "exclamationmark.triangle",
                                       description: Text(errorMessage))
            } else {
                SLLoadingState(title: "Downloading your lesson…", detail: "It stays on this device for offline practice.")
                    .padding(22).frame(maxWidth: .infinity, maxHeight: .infinity).background(SL.page)
            }
        }
        .task {
            guard entry == nil else { return }
            do {
                if store.hasBundle(for: lesson.id), let cached = store.entry(for: lesson.id) { entry = cached; return }
                let assets = try client.assets(for: lesson)
                defer { assets.close() }
                let url = try await store.install(lesson, assets: assets)
                entry = LessonLibrary.entry(at: url)
                if entry == nil { errorMessage = CloudPlaybackError.invalidResult.localizedDescription }
            } catch is CancellationError {
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
