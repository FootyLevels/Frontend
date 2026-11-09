import SwiftUI

/// Where the lesson island sits over the video: pinned to one corner of the free area, a gap
/// in from each of that corner's edges. Pinned this way it opens away from the edges it's
/// near, so it stays on screen at any size.
struct LessonIslandSpot: Equatable {
    /// Pinned to the right edge rather than the left.
    var trailing = false
    /// Pinned to the bottom edge rather than the top.
    var bottom = true
    /// The gap from the pinned side edge.
    var dx: CGFloat = 0
    /// The gap from the pinned top or bottom edge.
    var dy: CGFloat = 0

    /// Bottom left, just clear of the pill that brings the sheet back.
    static func home(abovePill pillHeight: CGFloat) -> LessonIslandSpot {
        LessonIslandSpot(dy: pillHeight + 18)
    }

    var alignment: Alignment {
        switch (trailing, bottom) {
        case (false, false): return .topLeading
        case (true, false): return .topTrailing
        case (false, true): return .bottomLeading
        case (true, true): return .bottomTrailing
        }
    }

    /// The gaps, cut down so an island of `size` stays inside `area`.
    func gaps(for size: CGSize, in area: CGSize) -> (x: CGFloat, y: CGFloat) {
        (Swift.min(Swift.max(dx, 0), Swift.max(area.width - size.width, 0)),
         Swift.min(Swift.max(dy, 0), Swift.max(area.height - size.height, 0)))
    }

    /// The island's frame in the area.
    func frame(for size: CGSize, in area: CGSize) -> CGRect {
        let gap = gaps(for: size, in: area)
        return CGRect(x: trailing ? area.width - size.width - gap.x : gap.x,
                      y: bottom ? area.height - size.height - gap.y : gap.y,
                      width: size.width, height: size.height)
    }

    /// Within `distance` of `other` and pinned to the same corner, so a drop there counts
    /// as putting it back.
    func isNear(_ other: LessonIslandSpot, within distance: CGFloat = 24) -> Bool {
        trailing == other.trailing && bottom == other.bottom
            && abs(dx - other.dx) <= distance && abs(dy - other.dy) <= distance
    }

    /// The spot for an island dropped at `frame`: pinned to the corner nearest its middle.
    static func dropped(at frame: CGRect, in area: CGSize) -> LessonIslandSpot {
        let trailing = frame.midX > area.width / 2
        let bottom = frame.midY > area.height / 2
        let spot = LessonIslandSpot(trailing: trailing, bottom: bottom,
                                    dx: trailing ? area.width - frame.maxX : frame.minX,
                                    dy: bottom ? area.height - frame.maxY : frame.minY)
        let gap = spot.gaps(for: frame.size, in: area)
        return LessonIslandSpot(trailing: trailing, bottom: bottom, dx: gap.x, dy: gap.y)
    }
}

/// Saved as "trailing,bottom,dx,dy", so the island stays where it was put.
extension LessonIslandSpot: RawRepresentable {
    init?(rawValue: String) {
        let parts = rawValue.split(separator: ",").map(String.init)
        guard parts.count == 4, let dx = Double(parts[2]), let dy = Double(parts[3]),
              dx.isFinite, dy.isFinite else { return nil }
        self.init(trailing: parts[0] == "1", bottom: parts[1] == "1", dx: dx, dy: dy)
    }

    var rawValue: String {
        "\(trailing ? 1 : 0),\(bottom ? 1 : 0),\(Double(dx)),\(Double(dy))"
    }
}
