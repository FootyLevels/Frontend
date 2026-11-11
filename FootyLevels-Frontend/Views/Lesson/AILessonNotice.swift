import SwiftUI

/// The toolbar item on a lesson made from the user's own video: says it's AI-generated, and
/// offers Report a problem and Delete.
struct AILessonNotice: View {
    let lesson: CloudLesson
    let client: CloudLessonClient
    let store: UserLessonStore
    var onDeleted: () -> Void = {}

    @State private var reporting = false
    @State private var confirmingDelete = false
    @State private var message: String?

    var body: some View {
        Menu {
            Section("AI-generated from your video. It can be wrong.") {
                Button { reporting = true } label: { Label("Report a problem", systemImage: "flag") }
                Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete lesson", systemImage: "trash") }
            }
        } label: {
            Label("AI-generated", systemImage: "sparkles").labelStyle(.titleAndIcon).font(.caption.weight(.semibold))
        }
        .accessibilityHint("Report a problem with this AI-generated lesson, or delete it")
        .confirmationDialog("What's wrong?", isPresented: $reporting, titleVisibility: .visible) {
            ForEach(CloudLessonClient.reportReasons, id: \.code) { reason in
                Button(reason.label) { send(reason.code) }
            }
        }
        .confirmationDialog("Delete this lesson?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete lesson", role: .destructive) { delete() }
        } message: { Text("Your video stays. You can create the lesson again later.") }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func send(_ reason: String) {
        Task {
            do { try await client.report(lesson, reason: reason, note: nil); message = "Thanks, we'll look into it." }
            catch { message = error.localizedDescription }
        }
    }

    private func delete() {
        Task {
            do { try await client.delete(lesson); store.remove(lesson.id); onDeleted() }
            catch { message = error.localizedDescription }
        }
    }
}
