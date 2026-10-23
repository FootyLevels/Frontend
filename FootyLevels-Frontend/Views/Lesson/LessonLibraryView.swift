import SwiftUI

/// The "Learn" tab: the Over Fake lesson and every lesson the lesson pipeline added
/// to the app. All play from the app bundle, so they work offline and without an account.
struct LessonLibraryView: View {
    @State private var lessons = LessonLibrary.lessons()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "LEARN A SKILL", rule: true)
                        Text("Lessons")
                            .font(SL.display(32, .heavy))
                            .tracking(-1.2)
                            .foregroundStyle(SL.ink)
                        Text("Each lesson is built from one video and the 3D body reconstructed from it: watch the move, break it down, practise it, then test yourself.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "77816F"))
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                    NavigationLink {
                        LessonView()
                    } label: {
                        LessonRow(title: "The over fake", subtitle: "Shape one way, step across the ball, then take it the other way.",
                                  skills: ["Over fake"])
                    }
                    ForEach(lessons) { lesson in
                        NavigationLink {
                            PackageLessonView(entry: lesson)
                        } label: {
                            LessonRow(title: lesson.title, subtitle: lesson.subtitle, skills: lesson.skills)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(SL.page)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    BrandMark(size: 20)
                }
            }
        }
        .tint(SL.green)
    }
}

private struct LessonRow: View {
    let title: String
    let subtitle: String
    let skills: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(SL.display(20, .heavy))
                    .foregroundStyle(SL.ink)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "5E6B58"))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                FlowRow(spacing: 5) {
                    ForEach(Array(skills.enumerated()), id: \.offset) { _, skill in
                        Text(skill)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(SL.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .overlay(Capsule().stroke(SL.cardBorder))
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SL.muted)
                .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .slPanel(fill: SL.card, border: SL.cardBorder, radius: 10)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the lesson")
    }
}
