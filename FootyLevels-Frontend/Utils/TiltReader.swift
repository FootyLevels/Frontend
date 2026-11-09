import CoreMotion
import Observation

/// How far the phone has tilted since reading began, from -1 to 1 on each axis and smoothed.
/// The sign-in screen uses it to shift its layers, like looking through a window.
@MainActor
@Observable
final class TiltReader {
    private(set) var x: Double = 0
    private(set) var y: Double = 0

    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var reference: (roll: Double, pitch: Double)?

    /// The tilt, in radians, that moves the layers all the way.
    nonisolated static let fullTilt = 0.35

    /// Starts reading. The way the phone is held at that moment counts as level.
    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        reference = nil
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let attitude = data?.attitude else { return }
            MainActor.assumeIsolated { self?.update(roll: attitude.roll, pitch: attitude.pitch) }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        x = 0
        y = 0
    }

    private func update(roll: Double, pitch: Double) {
        let level = reference ?? (roll, pitch)
        reference = level
        let target = Self.tilt(roll: roll, pitch: pitch, level: level)
        // Smoothed, so a hand's tremor doesn't shake the photo.
        x += (target.x - x) * 0.15
        y += (target.y - y) * 0.15
    }

    /// The tilt away from `level`, scaled so `fullTilt` reaches 1, and held within -1...1.
    nonisolated static func tilt(roll: Double, pitch: Double, level: (roll: Double, pitch: Double)) -> (x: Double, y: Double) {
        let clamp = { (value: Double) in Swift.min(Swift.max(value, -1), 1) }
        return (clamp((roll - level.roll) / fullTilt), clamp((pitch - level.pitch) / fullTilt))
    }
}
