import SwiftUI

/// The "Learn" tab: the Over Fake lesson and every lesson the lesson pipeline added
/// to the app. All play from the app bundle, so they work offline and without an account.
struct LessonLibraryView: View {
    @State private var lessons = LessonLibrary.lessons()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "LEARN A SKILL", rule: true)
                        Text("Lessons")
                            .font(SL.display(.largeTitle, .heavy))
                            .tracking(-1.2)
                            .foregroundStyle(SL.ink)
                        Text("Watch the move, explore it in 3D, then practise one step at a time.")
                            .font(.system(.subheadline))
                            .lineSpacing(4)
                            .foregroundStyle(SL.panelToplineText)
                        Label("\(lessons.count + 1) \(lessons.count == 0 ? "lesson" : "lessons") · Available offline", systemImage: "checkmark.circle")
                            .font(.system(.caption, weight: .medium))
                            .foregroundStyle(SL.presetActiveText)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                    NavigationLink {
                        LessonView()
                    } label: {
                        LessonRow(title: "The over fake", subtitle: "Shape one way, step across the ball, then take it the other way.",
                                  skills: ["Over fake"], isStartingLesson: true)
                    }
                    .buttonStyle(.plain)
                    ForEach(lessons) { lesson in
                        NavigationLink {
                            PackageLessonView(entry: lesson)
                        } label: {
                            LessonRow(title: lesson.title, subtitle: lesson.subtitle, skills: lesson.skills)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(SL.page)
            .slScreen()
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
    var isStartingLesson = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                if isStartingLesson {
                    Eyebrow(text: "START HERE", color: SL.presetActiveText)
                }
                Text(title)
                    .font(SL.display(.title3, .heavy))
                    .foregroundStyle(SL.ink)
                Text(subtitle)
                    .font(.system(.subheadline))
                    .lineSpacing(3)
                    .foregroundStyle(SL.panelToplineText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                FlowRow(spacing: 5) {
                    ForEach(Array(skills.enumerated()), id: \.offset) { _, skill in
                        Text(skill)
                            .font(.system(.caption2, weight: .medium))
                            .foregroundStyle(SL.presetActiveText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(SL.iconTile, in: Capsule())
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(SL.green)
                .scaledFrame(width: 30, relativeTo: .footnote)
                .background(SL.iconTile, in: Circle())
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .slPanel(fill: SL.card, border: SL.cardBorder, radius: 10)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the lesson")
    }
}
