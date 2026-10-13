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
    /// The project being deleted, so its card can show progress and a second
    /// delete can't start until the server answers.
    var deletingId: String?

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

            // Still "Preparing video…": the audio stays on the phone. The copy
            // goes in the picked file's folder, so the line above removes it too.
            let clip = try await UploadPreparation.removingAudio(
                from: movie.url,
                into: movie.url.deletingLastPathComponent().appendingPathComponent("upload", isDirectory: true))

            uploadPhase = .uploading(0)
            let project = try await SkillLabClient.shared.uploadVideo(at: clip) { [weak self] fraction in
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

    /// The bundled example can't be deleted, and neither can a clip the server
    /// is still reconstructing (it would answer 409 anyway).
    func canDelete(_ project: SkillLabProject) -> Bool {
        deletingId == nil && !BundledSample.isSample(project.id) && !project.isBusy
    }

    /// Deletes a project on the server, then drops it from the list. On failure
    /// the card stays and the error is shown, so the person can retry.
    func delete(_ project: SkillLabProject) async {
        guard canDelete(project) else { return }
        deletingId = project.id
        errorMessage = nil
        defer { deletingId = nil }

        do {
            try await SkillLabClient.shared.deleteProject(id: project.id)
        } catch SkillLabError.server(status: 404, _) {
            // Already gone, e.g. deleted from another device; the list catches up.
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        projects.removeAll { $0.id == project.id }
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
