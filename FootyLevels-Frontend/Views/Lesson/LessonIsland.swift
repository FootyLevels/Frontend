import SwiftUI

/// A glass capsule over the video with the key point for this moment. It opens with each
/// new point, then shrinks back to the point's name; tap it to read it again. Drag it
/// anywhere: it stays where it's dropped, or snaps home when dropped near there.
struct LessonIsland: View {
    let point: LessonPoint
    let spot: LessonIslandSpot
    var move: (LessonIslandSpot) -> Void
    var reset: () -> Void

    @State private var open = true
    /// How far it's being dragged. It settles back to zero on the same curve as the new spot
    /// moves in, so a drop stays put, a snap home glides there, and a cancelled drag glides back.
    @GestureState(reset: { _, transaction in
        transaction.animation = UIAccessibility.isReduceMotionEnabled ? nil : LessonIsland.settle
    }) private var drag: CGSize = .zero
    @State private var size: CGSize = .zero
    @ScaledMetric(relativeTo: .subheadline) private var closedWidth: CGFloat = 220
    @ScaledMetric(relativeTo: .subheadline) private var openWidth: CGFloat = 272
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long a new point stays open before the island shrinks to its name.
    static let readTime: Duration = .seconds(3.2)
    private static let settle = Animation.snappy(duration: 0.3)

    var body: some View {
        GeometryReader { geo in
            let area = geo.size
            let width = Swift.min(open ? openWidth : closedWidth, area.width)
            let gap = spot.gaps(for: CGSize(width: width, height: size.height), in: area)
            capsule(width: width)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                .offset(drag)
                .gesture(moveOrTap(in: area, width: width))
                .padding(spot.trailing ? .trailing : .leading, gap.x)
                .padding(spot.bottom ? .bottom : .top, gap.y)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: spot.alignment)
                .animation(reduceMotion ? nil : Self.settle, value: spot)
        }
        .task(id: point.id) {
            open = true
            try? await Task.sleep(for: Self.readTime)
            if !Task.isCancelled { open = false }
        }
    }

    private func capsule(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(SL.lime)
                    .frame(width: 8, height: 8)
                    .shadow(color: SL.lime.opacity(0.9), radius: 4)
                Text(point.title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(SL.bubbleInk)
                    .lineLimit(open ? 2 : 1)
                Spacer(minLength: 0)
                Text("\(point.index + 1)/\(point.count)")
                    .font(.system(.caption, weight: .semibold).monospacedDigit())
                    .foregroundStyle(SL.bubbleMuted)
            }
            if open {
                Text(point.text)
                    .font(.system(.subheadline))
                    .foregroundStyle(SL.bubbleMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(point.id)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: width, alignment: .leading)
        .lessonGlass(RoundedRectangle(cornerRadius: open ? 26 : 999))
        .scaleEffect(drag == .zero ? 1 : 1.04)
        .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: open)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: point.id)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: drag == .zero)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Key point \(point.index + 1) of \(point.count): \(point.title)")
        .accessibilityValue(point.text)
        .accessibilityHint("Shows or hides the point. Drag to move it.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open.toggle() }
        .accessibilityAction(named: "Move to the bottom left", reset)
        .accessibilityIdentifier("LessonIsland")
    }

    /// One gesture for both, so dropping the island never also opens or closes it. It only
    /// moves once the finger has gone a few points; less than that is a tap.
    private func moveOrTap(in area: CGSize, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($drag) { value, drag, _ in
                if drag != .zero || Self.isMove(value.translation) { drag = value.translation }
            }
            .onEnded { value in
                guard Self.isMove(value.translation) else {
                    open.toggle()
                    return
                }
                let start = spot.frame(for: CGSize(width: width, height: size.height), in: area)
                move(.dropped(at: start.offsetBy(dx: value.translation.width, dy: value.translation.height), in: area))
            }
    }

    private static func isMove(_ translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) > 6
    }
}

extension SL {
    // Glass over the video: the island and the pill that brings the sheet back.
    static let bubble = Color(light: "E0FFFFFF", dark: "B8121212")
    static let bubbleInk = Color(light: "0B0B0B", dark: "FFFFFF")
    static let bubbleMuted = Color(light: "4A4A4A", dark: "C9C9C9")
    static let bubbleLine = Color(light: "14000000", dark: "24FFFFFF")
}

extension View {
    /// Frosted glass that follows the appearance, for controls floating over the video.
    func lessonGlass(_ shape: some Shape) -> some View {
        background(SL.bubble, in: shape)
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(SL.bubbleLine))
            .shadow(color: .black.opacity(0.3), radius: 14, y: 10)
    }
}
