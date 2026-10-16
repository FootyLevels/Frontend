import AVFoundation
import Foundation
import Observation

/// The source video, shared by the video panel and the 3D motion inspector.
///
/// As in the web workspace, the video is the clock: playing or scrubbing it
/// moves the 3D, so the two can never drift apart. Only small subviews read
/// `currentTime`, so its 60 Hz updates don't rebuild the whole screen.
@MainActor
@Observable
final class PlaybackController {
    let player: AVPlayer
    let duration: Double

    private(set) var currentTime: Double = 0
    private(set) var isPlaying = false

    /// The web viewer opens at half speed: slow enough to read the move.
    var speed: Float = 0.5 {
        didSet {
            player.defaultRate = speed
            if isPlaying { player.rate = speed }
        }
    }
    var isMuted = true { didSet { player.isMuted = isMuted } }
    var loops = true

    static let speeds: [Float] = [0.25, 0.5, 1]

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endTask: Task<Void, Never>?

    init(url: URL, duration: Double) {
        self.player = AVPlayer(url: url)
        self.duration = duration
        player.isMuted = true
        player.defaultRate = speed
        player.actionAtItemEnd = .pause

        let interval = CMTime(value: 1, timescale: 60)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                if time.seconds.isFinite { self.currentTime = time.seconds }
                self.isPlaying = self.player.timeControlStatus != .paused
            }
        }

        let item = player.currentItem
        endTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVPlayerItem.didPlayToEndTimeNotification,
                                                                    object: item) {
                guard let self else { return }
                if self.loops {
                    await self.player.seek(to: .zero)
                    self.player.rate = self.speed
                } else {
                    self.isPlaying = false
                }
            }
        }
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            if currentTime >= duration - 0.05 { seek(to: 0) }
            player.rate = speed
            isPlaying = true
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    /// Frame-accurate, so a key-frame seek lands on that exact frame.
    func seek(to seconds: Double) {
        let clamped = Swift.max(0, Swift.min(seconds, duration))
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func teardown() {
        player.pause()
        endTask?.cancel()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }
}
