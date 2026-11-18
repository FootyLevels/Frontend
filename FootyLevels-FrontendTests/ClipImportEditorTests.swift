import SwiftUI
import Testing
import UIKit
@testable import FootyLevels_Frontend

/// The clip editor's Start and End sliders. SwiftUI stops the app when a stepped slider's
/// range is narrower than one step, so every range the editor shows must be at least that wide.
struct ClipImportEditorTests {

    @Test func aLongClipCanStartAnywhereThatLeavesOneSecond() {
        #expect(ClipTrim.startRange(duration: 90) == 0...89)
        #expect(ClipTrim.endRange(start: 10, duration: 90) == 11...70)
        #expect(ClipTrim.end(80, start: 10, duration: 90) == 70)
    }

    /// The reported crash: with the start at, or within a step of, its latest point, the end
    /// has no room to move, so it stays one second after the start and gets no slider.
    @Test(arguments: zip([8.33, 8.3, 8.25], [9.33, 9.3, 9.25]))
    func aStartNearTheEndFixesTheEnd(start: Double, end: Double) {
        #expect(ClipTrim.startRange(duration: 9.33)?.upperBound == 8.33)
        #expect(ClipTrim.endRange(start: start, duration: 9.33) == nil)
        #expect(abs(ClipTrim.end(5, start: start, duration: 9.33) - end) < 1e-9)
    }

    @Test func aClipUnderOnePointOneSecondsHasNoSliders() {
        #expect(ClipTrim.startRange(duration: 1.05) == nil)
        #expect(ClipTrim.endRange(start: 0, duration: 1.05) == nil)
    }

    /// Every start the Start slider can reach, for clips from 1 to 12 seconds, leaves either no
    /// End slider or one at least a step wide, despite floating-point rounding.
    @Test func everySliderRangeIsAtLeastOneStepWide() {
        for hundredths in 100...1200 {
            let duration = Double(hundredths) / 100
            guard let starts = ClipTrim.startRange(duration: duration) else { continue }
            #expect(starts.upperBound - starts.lowerBound >= ClipTrim.step)
            let reachable = stride(from: starts.lowerBound, to: starts.upperBound, by: ClipTrim.step).map { $0 } + [starts.upperBound]
            for start in reachable {
                if let ends = ClipTrim.endRange(start: start, duration: duration) {
                    #expect(ends.upperBound - ends.lowerBound >= ClipTrim.step, "\(duration) s clip, start \(start)")
                }
            }
        }
    }

    /// A 1.05 s clip used to stop the app as the editor opened: both sliders had 0.05 s ranges.
    @MainActor
    @Test func aClipJustOverOneSecondOpensTheEditor() {
        let clip = PendingClip(url: URL(fileURLWithPath: "/missing.mov"), source: "gallery", duration: 1.05)
        let host = UIHostingController(rootView: ClipImportEditor(clip: clip, onCancel: {}, onSubmit: { _, _, _, _ in }))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: .now + 0.3)
        #expect(host.view.window === window)
    }
}
