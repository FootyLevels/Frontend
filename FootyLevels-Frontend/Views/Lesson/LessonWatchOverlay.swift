import SwiftUI

/// Over the video while the lesson sheet is slid away: the island with the key point for
/// this moment, and a pill in the bottom-right corner that names the stage and brings the
/// sheet back.
struct LessonWatchOverlay: View {
    let model: PackageLessonModel
    /// The sheet's chosen drill or question for this stage.
    let selected: String?
    let bottomInset: CGFloat
    var showSheet: () -> Void

    /// Where the island was last dropped; empty until it's first moved.
    @AppStorage("lesson.island.spot") private var savedSpot = ""
    @State private var pillHeight: CGFloat = 48

    private var spot: LessonIslandSpot {
        LessonIslandSpot(rawValue: savedSpot) ?? .home(abovePill: pillHeight)
    }

    /// Saves where the island was dropped. Dropped close to home, it snaps home, and home
    /// then keeps clear of the pill at any text size.
    private func place(_ dropped: LessonIslandSpot) {
        savedSpot = dropped.isNear(.home(abovePill: pillHeight)) ? "" : dropped.rawValue
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            CurrentPoint(model: model, selected: selected) { point in
                LessonIsland(point: point, spot: spot, move: place, reset: { savedSpot = "" })
            }
            SectionPill(stage: model.stage, action: showSheet)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pillHeight = $0 }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, Swift.max(bottomInset, 16))
    }
}

/// Works out the point in its own view: in Watch it follows the 60 Hz clock, and only this
/// view reads it.
private struct CurrentPoint<Content: View>: View {
    let model: PackageLessonModel
    let selected: String?
    @ViewBuilder var content: (LessonPoint) -> Content

    var body: some View {
        let time = model.stage == .watch ? model.playback.currentTime : 0
        if let point = model.skill.point(for: model.stage, at: time, phase: model.phase, selected: selected) {
            content(point)
        }
    }
}

/// "⌃ Break it down": where you are in the lesson, and the way back to it.
private struct SectionPill: View {
    let stage: LessonStage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.up")
                    .font(.system(.footnote, weight: .bold))
                // Wraps rather than cut off at the largest text sizes.
                Text(stage.rawValue)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(SL.bubbleInk)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .frame(minHeight: 48)
            .lessonGlass(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show the lesson")
        .accessibilityValue(stage.rawValue)
        .accessibilityInputLabels(["Show the lesson", stage.rawValue])
    }
}
