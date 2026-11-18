import Foundation

/// The part of a picked clip to upload: 1 to 60 seconds, chosen on sliders in 0.1 s steps.
enum ClipTrim {
    static let step = 0.1
    static let shortest = 1.0
    static let longest = 60.0

    /// Where the selection can start, or nil when the clip is too short to move the start.
    static func startRange(duration: Double) -> ClosedRange<Double>? {
        sliderRange(0, duration - shortest)
    }

    /// Where the selection can end after this start, or nil when the end is already fixed.
    static func endRange(start: Double, duration: Double) -> ClosedRange<Double>? {
        sliderRange(start + shortest, min(duration, start + longest))
    }

    /// The end, moved if needed so the selection stays 1 to 60 seconds and inside the clip.
    static func end(_ end: Double, start: Double, duration: Double) -> Double {
        min(duration, max(start + shortest, min(end, start + longest)))
    }

    /// SwiftUI stops the app when a stepped Slider's range is narrower than one step, so a
    /// range that narrow gets no slider.
    private static func sliderRange(_ lower: Double, _ upper: Double) -> ClosedRange<Double>? {
        upper - lower >= step ? lower...upper : nil
    }
}
