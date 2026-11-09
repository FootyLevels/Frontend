import SwiftUI

/// What fills the lesson screen; the other one sits in the corner.
enum LessonMainView {
    case video, body
}

/// The lesson's video and 3D body. One fills the screen and the other sits in the top-right
/// corner; tapping the corner swaps them. The 3D body only takes the part of the screen
/// above the open sheet, so it stays in view while the sheet is up.
struct LessonMediaStage<Model: LessonPlayer>: View {
    let model: Model
    @Binding var main: LessonMainView
    /// How much of the screen's bottom the open sheet covers.
    let covered: CGFloat
    /// Where the content starts, below the status and navigation bars.
    let top: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cornerSize = CGSize(width: 108, height: 160)

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let corner = CGRect(x: size.width - 16 - cornerSize.width, y: top + 8, width: cornerSize.width, height: cornerSize.height)
            let whole = CGRect(origin: .zero, size: size)
            let aboveSheet = CGRect(x: 0, y: 0, width: size.width, height: Swift.max(size.height - covered, cornerSize.height))
            ZStack(alignment: .topLeading) {
                (main == .body ? SL.stage : Color.black)
                video(in: main == .video ? whole : corner, isMain: main == .video)
                    .zIndex(main == .video ? 0 : 1)
                stage(in: main == .body ? aboveSheet : corner, isMain: main == .body)
                    .zIndex(main == .body ? 0 : 1)
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: main)
            .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: covered)
        }
        .ignoresSafeArea()
    }

    private func video(in frame: CGRect, isMain: Bool) -> some View {
        VideoSurface(player: model.playback.player, gravity: .resizeAspectFill)
            .scaleEffect(x: model.mirror ? -1 : 1, y: 1)
            .background(Color.black)
            .frame(width: frame.width, height: frame.height)
            .clipShape(RoundedRectangle(cornerRadius: isMain ? 0 : 20))
            .overlay { if !isMain { CornerChrome(tag: "Video") } }
            .contentShape(Rectangle())
            .onTapGesture { isMain ? model.togglePlayback() : swap() }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isMain ? "Original video. Tap to play or pause." : "Show the video full screen")
            .offset(x: frame.minX, y: frame.minY)
    }

    private func stage(in frame: CGRect, isMain: Bool) -> some View {
        ZStack {
            ModelStageView(root: model.stageRoot, camera: model.camera)
                .allowsHitTesting(isMain)
            if let message = model.stageMessage {
                StageMessage(message: message.text, isLoading: message.isLoading)
            }
            if !isMain {
                CornerChrome(tag: "3D · \(model.angle.rawValue)")
                Button(action: swap) { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show the 3D body full screen")
            }
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(RoundedRectangle(cornerRadius: isMain ? 0 : 20))
        .offset(x: frame.minX, y: frame.minY)
    }

    private func swap() {
        main = main == .video ? .body : .video
    }
}

/// The corner tile's border, shadow and label.
private struct CornerChrome: View {
    let tag: String

    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white.opacity(0.4))
            .overlay(alignment: .bottomLeading) {
                Text(tag)
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(8)
            }
            .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
