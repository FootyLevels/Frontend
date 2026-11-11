import SwiftUI

/// Asked once per account, before any video is sent to an AI model to write a lesson.
/// The server enforces the answer too: a lesson can't be created without it.
struct LessonConsentSheet: View {
    let onAnswer: (Bool) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 34)).foregroundStyle(SL.tint)
                        .accessibilityHidden(true)
                    Text("Make lessons with AI").font(SL.display(.title2))
                    point("video", "Your prepared clip is sent to Google's Gemini model, which watches it and writes the lesson. Our team's server builds the 3D motion.")
                    point("lock", "The lesson is private to your account. Delete it, or the video, at any time.")
                    point("exclamationmark.bubble", "AI can get things wrong. Each lesson is labelled AI-generated and has Report a problem.")
                    point("hand.raised", "Lessons explain the move. They never score you or judge your technique.")
                    Text("You can change this later by deleting your account data.")
                        .font(.footnote).foregroundStyle(SL.muted)
                }
                .padding(22)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button("Allow and create lesson") { onAnswer(true) }.buttonStyle(.slPrimaryWide)
                    Button("Not now") { onAnswer(false) }.buttonStyle(.slSecondary)
                }
                .padding(22).background(SL.page)
            }
            .background(SL.page)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        Label { Text(text).foregroundStyle(SL.ink) } icon: { Image(systemName: symbol).foregroundStyle(SL.tint) }
            .font(.callout)
    }
}
