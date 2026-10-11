import Foundation
import Observation
import PhotosUI
import SwiftUI

struct PendingClip: Identifiable {
    let id = UUID()
    let url: URL
    let source: String
    let duration: Double
}

@MainActor
@Observable
final class CloudUploadsViewModel {
    var projects: [CloudProject] = []
    var drafts: [UploadDraft] = []
    var pending: PendingClip?
    var errorMessage: String?
    var isLoading = false
    var phase: String?
    var progress: Double?
    var isConfigured: Bool { coordinator != nil }
    var isBusy: Bool { task != nil }
    private var nextCursor: String?
    var hasMore: Bool { nextCursor != nil }
    private var coordinator: CloudUploadCoordinator?
    private var task: Task<Void, Never>?

    func configure() {
        do {
            guard let url = ApplicationEnvironment.apiBaseURL else { throw AccountAPIError.notConfigured }
            coordinator = try CloudUploadCoordinator(apiURL: url, environment: .current, credentials: FirebaseAPICredentials.shared)
            drafts = try coordinator!.store.load()
        } catch { errorMessage = error.localizedDescription }
    }

    func refresh(more: Bool = false, afterMutation: Bool = false) async {
        guard !isLoading, afterMutation || !isBusy, let coordinator else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await coordinator.list(cursor: more ? nextCursor : nil)
            if more { projects += page.items.filter { p in !projects.contains(where: { $0.id == p.id }) } }
            else { projects = page.items }
            nextCursor = page.nextCursor
            drafts = try coordinator.store.load()
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func importGallery(_ item: PhotosPickerItem) {
        start("Reading video…") { [weak self] in
            guard let self, let movie = try await item.loadTransferable(type: PickedMovie.self) else { throw ClipUploadError.invalidVideo }
            do { try await self.accept(movie.url, source: "gallery") }
            catch { try? FileManager.default.removeItem(at: movie.url.deletingLastPathComponent()); throw error }
        }
    }

    func importCamera(_ file: URL) {
        start("Reading recording…") { [weak self] in
            guard let self else { return }
            do { try await self.accept(file, source: "capture") }
            catch { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()); throw error }
        }
    }

    private func accept(_ file: URL, source: String) async throws {
        let details = try await VideoClipPreparer.inspect(file)
        try coordinator?.checkSession()
        try Task.checkCancellation()
        pending = PendingClip(url: file, source: source, duration: details.duration)
    }

    func cancelEditor() {
        if let pending { try? FileManager.default.removeItem(at: pending.url.deletingLastPathComponent()) }
        pending = nil
    }

    func submit(title: String, label: String, start: Double, end: Double) {
        guard let pending, let coordinator else { return }
        self.pending = nil
        startTask("Preparing private clip…") { [weak self] in
            guard let self else { return }
            defer { try? FileManager.default.removeItem(at: pending.url.deletingLastPathComponent()) }
            try coordinator.checkSession()
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...120).contains(title.count), label.count <= 80 else { throw ClipUploadError.invalidVideo }
            let id = UUID().uuidString.lowercased()
            let directory = try coordinator.store.directory(id)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("clip.mp4")
            var saved = false
            defer { if !saved { try? FileManager.default.removeItem(at: directory) } }
            try await VideoClipPreparer.prepare(pending.url, start: start, end: end, destination: file)
            let fingerprint = try await Task.detached(priority: .utility) { try UploadDraftStore.fingerprint(file) }.value
            try coordinator.checkSession()
            let draft = UploadDraft(id: id, ownerId: FirebaseAPICredentials.shared.currentSession!.uid,
                scope: coordinator.store.scope, title: title, label: label.isEmpty ? nil : label,
                source: pending.source, byteSize: fingerprint.bytes, sha256: fingerprint.hash)
            try coordinator.store.save(draft)
            saved = true
            self.drafts = try coordinator.store.load()
            try await self.runUpload(draft, coordinator: coordinator)
        }
    }

    func resume(_ draft: UploadDraft) {
        guard let coordinator else { return }
        start("Resuming upload…") { [weak self] in
            guard let self else { return }
            if draft.discarding { try await coordinator.discard(draft); await self.refresh(afterMutation: true) }
            else { try await self.runUpload(draft, coordinator: coordinator) }
        }
    }

    func discard(_ draft: UploadDraft) {
        guard let coordinator else { return }
        start("Removing unfinished upload…") { [weak self] in
            try await coordinator.discard(draft)
            await self?.refresh(afterMutation: true)
        }
    }

    private func runUpload(_ draft: UploadDraft, coordinator: CloudUploadCoordinator) async throws {
        phase = "Uploading private video…"
        progress = 0
        let project = try await coordinator.upload(draft) { [weak self] value in
            self?.progress = value
            if value == 1 { self?.phase = "Verifying private upload…" }
        }
        projects.removeAll { $0.id == project.id }
        projects.insert(project, at: 0)
        drafts = try coordinator.store.load()
        phase = nil
    }

    func pause() { task?.cancel() }

    private func start(_ label: String, operation: @escaping @MainActor () async throws -> Void) {
        startTask(label, operation: operation)
    }

    private func startTask(_ label: String, operation: @escaping @MainActor () async throws -> Void) {
        guard task == nil else { return }
        phase = label
        progress = nil
        errorMessage = nil
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil; self.phase = nil; self.progress = nil }
            do { try await operation() }
            catch is CancellationError { self.errorMessage = "Paused. Any saved draft can be resumed below." }
            catch { self.errorMessage = error.localizedDescription }
            if let coordinator = self.coordinator, (try? coordinator.checkSession()) != nil {
                self.drafts = (try? coordinator.store.load()) ?? self.drafts
            }
        }
    }
}
