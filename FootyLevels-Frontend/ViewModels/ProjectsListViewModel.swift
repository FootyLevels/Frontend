import CoreTransferable
import Foundation
import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class ProjectsListViewModel {

    enum UploadPhase: Equatable {
        case importing
        case uploading(Double)
        /// Bytes are sent; the server is transcoding and picking key frames,
        /// which can take a while with no progress to report.
        case processing
    }

    var projects: [SkillLabProject] = []
    var health: SkillLabHealth?
    var isLoading = false
    var errorMessage: String?
    var uploadPhase: UploadPhase?

    /// Health and the project list are independent, so fetch them together. A
    /// health failure alone just means the status row reads "offline".
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        await load()
        // On a device's first connection iOS shows the Local Network prompt and
        // may fail that request before the person answers. One quiet retry
        // covers it, rather than leaving them on an "offline" screen.
        if health == nil, ServerSettings.baseURL != nil {
            try? await Task.sleep(for: .seconds(2))
            await load()
        }
    }

    private func load() async {
        async let healthTask = try? SkillLabClient.shared.health()
        do {
            projects = try await SkillLabClient.shared.projects()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        health = await healthTask
    }

    var isConfigured: Bool { ServerSettings.baseURL != nil }

    /// Imports the picked video as a file, uploads it, and returns the new
    /// project's ID so the caller can navigate straight into it.
    func upload(_ item: PhotosPickerItem) async -> String? {
        uploadPhase = .importing
        errorMessage = nil
        defer { uploadPhase = nil }

        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                errorMessage = "Couldn't read that video."
                return nil
            }
            defer { try? FileManager.default.removeItem(at: movie.url.deletingLastPathComponent()) }

            uploadPhase = .uploading(0)
            let project = try await SkillLabClient.shared.uploadVideo(at: movie.url) { [weak self] fraction in
                Task { @MainActor in
                    guard let self, case .uploading = self.uploadPhase else { return }
                    self.uploadPhase = fraction >= 1 ? .processing : .uploading(fraction)
                }
            }

            projects.insert(project, at: 0)
            return project.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

/// A video from the photo library, copied to a temporary file.
///
/// A file representation rather than `Data` keeps a large clip out of memory.
/// The original filename is preserved because the server both validates the
/// extension and uses the name as the project title.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("picked-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMovie(url: destination)
        }
    }
}
