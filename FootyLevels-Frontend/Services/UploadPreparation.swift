import AVFoundation
import Foundation

/// Gets a picked clip ready for upload by removing its audio on the phone.
///
/// Nothing on the other side uses sound: the 3D pipeline reads only video
/// frames and the app always plays clips muted. Dropping it here means voices
/// and background conversation never leave the device, and the upload gets a
/// little smaller.
enum UploadPreparation {

    enum Failure: LocalizedError {
        case unsupportedContainer(String)
        case noVideoTrack
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .unsupportedContainer(let fileExtension):
                return "Can't prepare a .\(fileExtension) video for upload. Use a MOV or MP4 clip."
            case .noVideoTrack:
                return "This file doesn't contain a video."
            case .exportFailed:
                return "Couldn't remove the audio from this video, so it wasn't uploaded."
            }
        }
    }

    /// Returns a copy of `source` without audio, written into `directory` under
    /// the same file name, which the server uses as the project title. A clip
    /// with no audio is returned unchanged.
    ///
    /// Video samples are copied, not re-encoded, so quality is untouched and the
    /// work is quick. It fails rather than falling back to the original, so a
    /// clip with audio is never uploaded by accident.
    static func removingAudio(from source: URL, into directory: URL) async throws -> URL {
        // Checked first: a container that can't be rewritten can't be shown to
        // be silent either.
        guard let fileType = fileType(for: source) else {
            throw Failure.unsupportedContainer(source.pathExtension.lowercased())
        }

        let asset = AVURLAsset(url: source)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        guard !audio.isEmpty else { return source }
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw Failure.noVideoTrack
        }

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video,
                                                      preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw Failure.exportFailed
        }
        try track.insertTimeRange(try await video.load(.timeRange), of: video, at: .zero)
        // Portrait iPhone clips are stored landscape plus a rotation; without it
        // the server would see the clip sideways.
        track.preferredTransform = try await video.load(.preferredTransform)

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw Failure.exportFailed
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        do {
            try await export.export(to: destination, as: fileType)
        } catch {
            throw Failure.exportFailed
        }
        return destination
    }

    private static func fileType(for url: URL) -> AVFileType? {
        switch url.pathExtension.lowercased() {
        case "mov": return .mov
        case "mp4": return .mp4
        case "m4v": return .m4v
        default: return nil
        }
    }
}
