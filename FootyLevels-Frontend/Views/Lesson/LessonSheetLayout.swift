import CoreGraphics

/// The lesson sheet's resting heights.
enum LessonSheetDetent: CaseIterable {
    /// Slid fully down, so the whole video shows.
    case hidden
    /// The stage, the current step and the play controls.
    case peek
    /// Adds the list of steps in the stage.
    case half
    /// Adds the measurements and what one camera can't show.
    case full

    /// The next height up, wrapping from full back to peek.
    var next: LessonSheetDetent {
        switch self {
        case .hidden, .full: return .peek
        case .peek: return .half
        case .half: return .full
        }
    }
}

/// Works out the sheet's heights from the screen and the sheet's own header, so the
/// smallest height always fits the header at any text size.
struct LessonSheetLayout: Equatable {
    /// The whole screen, safe areas included.
    var screenHeight: CGFloat
    /// The sheet's fixed header: grabber, stages, current step and play controls.
    var headerHeight: CGFloat
    /// The home indicator's inset; the sheet runs under it.
    var bottomInset: CGFloat
    /// Kept clear at the top for the status bar and the navigation buttons.
    var topReserve: CGFloat

    private var tallest: CGFloat { Swift.max(screenHeight - topReserve, 0) }

    func height(_ detent: LessonSheetDetent) -> CGFloat {
        let peek = Swift.min(headerHeight + bottomInset, tallest)
        switch detent {
        case .hidden: return 0
        case .peek: return peek
        case .half: return Swift.min(Swift.max(peek + 200, screenHeight * 0.56), tallest)
        case .full: return tallest
        }
    }

    /// How far the sheet slides down to show only `height` of it. The header never squashes:
    /// below the smallest height the sheet moves off the bottom instead.
    func slide(toShow height: CGFloat) -> CGFloat {
        Swift.max(self.height(.peek) - height, 0)
    }

    /// Where a drag settles: the height nearest to where it is heading. `velocity` is in
    /// points per second, positive when the sheet is moving up.
    func settle(at height: CGFloat, velocity: CGFloat) -> LessonSheetDetent {
        let heading = height + velocity * 0.2
        return LessonSheetDetent.allCases.min { abs(self.height($0) - heading) < abs(self.height($1) - heading) } ?? .peek
    }
}
