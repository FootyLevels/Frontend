import AVFoundation
import Foundation

struct ClipDetails {
    let duration: Double
}

enum VideoClipPreparer {
    static func inspect(_ file: URL) async throws -> ClipDetails {
        guard ["mp4", "mov", "m4v"].contains(file.pathExtension.lowercased()) else { throw ClipUploadError.invalidVideo }
        let asset = AVURLAsset(url: file)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration >= 1,
              try await asset.load(.isReadable),
              !(try await asset.loadTracks(withMediaType: .video)).isEmpty else { throw ClipUploadError.invalidVideo }
        return ClipDetails(duration: duration)
    }

    /// Keep rotation, remove audio and export just the selected video range.
    /// The existing file-based importer is reused; the whole clip is never Data.
    static func prepare(_ file: URL, start: Double, end: Double, destination: URL) async throws {
        let details = try await inspect(file)
        guard start.isFinite, end.isFinite, start >= 0, end <= details.duration + 0.05,
              end - start >= 1, end - start <= 60 else { throw ClipUploadError.invalidTrim }
        let asset = AVURLAsset(url: file)
        guard let source = try await asset.loadTracks(withMediaType: .video).first else { throw ClipUploadError.invalidVideo }
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ClipUploadError.invalidVideo
        }
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: min(end, details.duration) - start, preferredTimescale: 600))
        try track.insertTimeRange(range, of: source, at: .zero)
        track.preferredTransform = try await source.load(.preferredTransform)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1280x720) else {
            throw ClipUploadError.invalidVideo
        }
        exporter.shouldOptimizeForNetworkUse = true
        try await exporter.export(to: destination, as: .mp4)
        try Task.checkCancellation()
        _ = try await inspect(destination)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                              ofItemAtPath: destination.path)
    }
}
