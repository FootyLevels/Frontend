import AVFoundation
import Foundation
import Testing
@testable import FootyLevels_Frontend

/// Audio is removed on the phone before upload, so it never reaches the server.
final class UploadPreparationTests {

    /// A fresh folder per test, like the per-upload temporary folder the app uses.
    private let workspace = FileManager.default.temporaryDirectory
        .appendingPathComponent("UploadPreparationTests-\(UUID().uuidString)", isDirectory: true)

    private var uploadFolder: URL { workspace.appendingPathComponent("upload", isDirectory: true) }

    deinit {
        try? FileManager.default.removeItem(at: workspace)
    }

    /// Copies a bundled fixture into the workspace so no test touches the original.
    private func fixture(_ name: String) throws -> URL {
        let original = try #require(Bundle(for: UploadPreparationTests.self).url(forResource: name, withExtension: nil))
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let copy = workspace.appendingPathComponent(name)
        try FileManager.default.copyItem(at: original, to: copy)
        return copy
    }

    private func videoTransform(of url: URL) async throws -> CGAffineTransform {
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        return try await track.load(.preferredTransform)
    }

    @Test func removesTheAudioAndKeepsTheVideo() async throws {
        let source = try fixture("fixture-with-audio.mov")
        let result = try await UploadPreparation.removingAudio(from: source, into: uploadFolder)

        let asset = AVURLAsset(url: result)
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(abs(try await asset.load(.duration).seconds - 1) < 0.15)
    }

    @Test func keepsTheFileNameTheServerUsesAsTheTitle() async throws {
        let source = try fixture("fixture-with-audio.mov")
        let result = try await UploadPreparation.removingAudio(from: source, into: uploadFolder)

        #expect(result.lastPathComponent == source.lastPathComponent)
        #expect(result.deletingLastPathComponent().standardizedFileURL == uploadFolder.standardizedFileURL)
    }

    @Test func keepsTheRotationSoPortraitClipsStayUpright() async throws {
        let source = try fixture("fixture-with-audio.mov")
        let result = try await UploadPreparation.removingAudio(from: source, into: uploadFolder)

        let original = try await videoTransform(of: source)
        #expect(original != .identity)  // the fixture really is rotated
        #expect(try await videoTransform(of: result) == original)
    }

    @Test func aClipWithoutAudioIsUploadedAsIs() async throws {
        let source = try fixture("fixture-video-only.mp4")
        #expect(try await UploadPreparation.removingAudio(from: source, into: uploadFolder) == source)
    }

    @Test func refusesAContainerItCannotRewriteRatherThanUploadingItsAudio() async throws {
        let mov = try fixture("fixture-with-audio.mov")
        let webm = mov.deletingPathExtension().appendingPathExtension("webm")
        try FileManager.default.moveItem(at: mov, to: webm)

        await #expect(throws: UploadPreparation.Failure.self) {
            _ = try await UploadPreparation.removingAudio(from: webm, into: self.uploadFolder)
        }
    }
}
