import SwiftUI
import UIKit

/// The "Learn" tab: the Over Fake lesson and every lesson the lesson pipeline added
/// to the app. All play from the app bundle, so they work offline and without an account.
struct LessonLibraryView: View {
    /// Nil for the Debug local-sample entry, which has no account to show.
    var appState: AppStateViewModel? = nil
    @State private var lessons = LessonLibrary.lessons()
    /// True once the hero has scrolled away, so the status bar gets a backdrop.
    @State private var scrolledPastHero = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The lesson the hero image comes from, when it ships.
    private var featured: LessonLibrary.Entry? {
        lessons.first { $0.id == "chop-and-spin" } ?? lessons.first
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let statusBar = proxy.safeAreaInsets.top
                // The scroll view runs under the status bar so the hero image reaches
                // the top edge; the hero pads its own content below the status bar.
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        LearnHero(featured: featured, appState: appState, topInset: statusBar)
                        lessonList
                            .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 32)
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y > 240
                } action: { _, scrolled in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { scrolledPastHero = scrolled }
                }
                .ignoresSafeArea(edges: .top)
                .overlay(alignment: .top) {
                    // Keeps list text from sitting under the clock once the hero is gone.
                    Rectangle()
                        .fill(.bar)
                        .frame(height: statusBar)
                        .ignoresSafeArea(edges: .top)
                        .opacity(scrolledPastHero ? 1 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .background(SL.page)
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(SL.tint)
    }

    private var lessonList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Lessons")
                    .font(.system(.title2))
                    .foregroundStyle(SL.ink)
                Spacer(minLength: 8)
                Text("\(lessons.count + 1) · available offline")
                    .font(.system(.footnote))
                    .foregroundStyle(SL.muted)
            }
            VStack(spacing: 0) {
                NavigationLink {
                    LessonView()
                } label: {
                    LessonRow(thumbnail: "LessonThumb-over-fake", title: "The over fake",
                              subtitle: "Shape one way, step across the ball, then take it the other way.",
                              isStartingLesson: true)
                }
                .buttonStyle(.plain)
                ForEach(lessons) { lesson in
                    Divider().overlay(SL.line).padding(.leading, 84)
                    NavigationLink {
                        PackageLessonView(entry: lesson)
                    } label: {
                        LessonRow(thumbnail: "LessonThumb-\(lesson.id)", title: lesson.title, subtitle: lesson.subtitle)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(SL.card, in: RoundedRectangle(cornerRadius: 22))
        }
    }
}

/// The top of Learn: a colour-graded, motion-blurred still of a real lesson clip with the
/// brand, the profile photo, the drills to practise next and the way into the featured lesson.
private struct LearnHero: View {
    let featured: LessonLibrary.Entry?
    let appState: AppStateViewModel?
    /// The status bar's height: the image runs under it, the content starts below it.
    let topInset: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                BrandMark(size: 20, onImage: true)
                    .padding(.top, 10)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 10) {
                    if let appState, appState.isLoggedIn == .loggedIn {
                        ProfileButton(user: appState.currentUser)
                    }
                    if let featured, !featured.practice.isEmpty {
                        // Opens the lesson at Practise, where these drills are.
                        NavigationLink {
                            PackageLessonView(entry: featured, startStage: .practise)
                        } label: {
                            PracticeCard(drills: featured.practice)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: 200)
                        .accessibilityHint("Opens \(featured.title) at Practise")
                    }
                }
            }
            Spacer(minLength: 56)
            Text("Learn the move,\nin motion.")
                .font(.system(.largeTitle))
                .tracking(-0.6)
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text("Watch the move, explore it in 3D, then practise one step at a time.")
                .font(.system(.subheadline))
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            if let featured {
                FlowRow(spacing: 10) {
                    NavigationLink {
                        PackageLessonView(entry: featured)
                    } label: {
                        HStack(spacing: 10) {
                            Text("Start \(featured.title.replacingOccurrences(of: " Lesson", with: ""))")
                                .font(.system(.subheadline, weight: .semibold))
                            Image(systemName: "arrow.up.right")
                                .font(.system(.footnote, weight: .bold))
                                .foregroundStyle(SL.onGreen)
                                .scaledFrame(width: 32, relativeTo: .footnote)
                                .background(SL.tint, in: Circle())
                        }
                        .foregroundStyle(Color.black)
                        .padding(.leading, 18)
                        .padding(.trailing, 7)
                        .frame(minHeight: 46)
                        .background(Color.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Text("\(featured.skills.count) skills · offline")
                        .font(.system(.footnote))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(minHeight: 46)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, topInset + 8)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, minHeight: 440 + topInset, alignment: .topLeading)
        .background {
            ZStack {
                Image("LearnHero")
                    .resizable()
                    .scaledToFill()
                    .accessibilityHidden(true)
                // Dark mode's status bar is white, so it gets a dark band to sit on.
                if colorScheme == .dark {
                    LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .center)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
            }
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 36, bottomTrailingRadius: 36))
        }
    }
}

/// Frosted card on the hero listing the featured lesson's first drills.
private struct PracticeCard: View {
    let drills: [LessonLibrary.Drill]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label("Practise next", systemImage: "clock")
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .accessibilityHidden(true)
            }
            .font(.system(.caption, weight: .semibold))
            .padding(.horizontal, 4)
            ForEach(Array(drills.enumerated()), id: \.offset) { index, drill in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if index == 0 {
                            Circle().fill(SL.lime).frame(width: 6, height: 6)
                        }
                        Text(drill.title)
                            .font(.system(.footnote, weight: .semibold))
                            .lineLimit(2)
                    }
                    HStack {
                        Text(drill.level.components(separatedBy: " · ").last ?? drill.level)
                        Spacer(minLength: 6)
                        Text("\(drill.reps) reps").monospacedDigit()
                    }
                    .font(.system(.caption2))
                    .opacity(0.92)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(index == 0 ? 0.2 : 0.1), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .slGlass(radius: 22)
        .accessibilityElement(children: .combine)
    }
}

private struct LessonRow: View {
    let thumbnail: String
    let title: String
    let subtitle: String
    var isStartingLesson = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            LessonThumbnail(name: thumbnail)
            VStack(alignment: .leading, spacing: 3) {
                FlowRow(spacing: 8) {
                    Text(title)
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(SL.ink)
                    if isStartingLesson {
                        Text("Start here")
                            .font(.system(.caption2, weight: .semibold))
                            .foregroundStyle(SL.onGreen)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(SL.green, in: Capsule())
                    }
                }
                Text(subtitle)
                    .font(.system(.footnote))
                    .foregroundStyle(SL.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(SL.muted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the lesson")
    }
}

/// A lesson's colour-graded still, or a plain tile when the lesson has none yet.
private struct LessonThumbnail: View {
    let name: String

    var body: some View {
        Group {
            if UIImage(named: name) != nil {
                Image(name)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "figure.soccer")
                    .font(.system(.title3))
                    .foregroundStyle(SL.iconTileText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SL.iconTile)
            }
        }
        .scaledFrame(width: 58, relativeTo: .callout)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityHidden(true)
    }
}
