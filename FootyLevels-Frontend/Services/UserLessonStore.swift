import Foundation

/// Lessons built from the user's own videos, cached on this device as ordinary lesson bundles:
/// `Caches/UserLessons/<uid>/Lesson-<id>.bundle/`. A bundle is downloaded into a staging folder,
/// checked with `LessonPackage.load` and only then moved into place, so a half-finished
/// download never shows up as a lesson. Other accounts' folders are removed on use.
@MainActor
final class UserLessonStore {
    let root: URL
    private let uid: String

    init(uid: String, root: URL? = nil) throws {
        guard uid.range(of: "^[a-zA-Z0-9_-]{1,128}$", options: .regularExpression) != nil else {
            throw CloudPlaybackError.invalidResult
        }
        let base = root ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UserLessons", isDirectory: true)
        self.root = base
        self.uid = uid
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var location = base; try? location.setResourceValues(values)
        Self.removeOtherAccounts(in: base, keeping: uid)
    }

    var folder: URL { root.appendingPathComponent(uid, isDirectory: true) }

    func bundleURL(for id: String) -> URL { folder.appendingPathComponent("Lesson-\(id).bundle", isDirectory: true) }

    func hasBundle(for id: String) -> Bool {
        FileManager.default.fileExists(atPath: bundleURL(for: id).appendingPathComponent("lesson.json").path)
    }

    /// The cached lesson as a library entry, or nil when it is missing or unreadable.
    func entry(for id: String) -> LessonLibrary.Entry? {
        hasBundle(for: id) ? LessonLibrary.entry(at: bundleURL(for: id)) : nil
    }

    /// Download every file (each verified by size and SHA-256), check the bundle opens, install it.
    func install(_ lesson: CloudLesson, assets: PrivatePlaybackAssets) async throws -> URL {
        let files = try lesson.bundleFiles(owner: uid)
        let destination = bundleURL(for: lesson.id)
        if hasBundle(for: lesson.id) { return destination }
        let staging = folder.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        let manager = FileManager.default
        try manager.createDirectory(at: staging.appendingPathComponent("motion", isDirectory: true),
                                    withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            for name in files.keys.sorted() {
                let data = try await assets.data(file: name)
                try assets.checkSession()
                try data.write(to: staging.appendingPathComponent(name), options: [.atomic])
            }
            _ = try LessonPackage.load(staging)
            if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
            try manager.moveItem(at: staging, to: destination)
            return destination
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
    }

    func remove(_ id: String) {
        try? FileManager.default.removeItem(at: bundleURL(for: id))
    }

    /// Drop cached lessons the server no longer lists (deleted here or on another device).
    func prune(keeping ids: Set<String>) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names where name.hasPrefix("Lesson-") || name.hasPrefix(".staging-") {
            let id = name.dropFirst("Lesson-".count).dropLast(".bundle".count)
            if name.hasPrefix(".staging-") || !ids.contains(String(id)) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
        }
    }

    /// Signing out or switching accounts must not leave another person's lessons readable.
    static func removeOtherAccounts(in root: URL, keeping uid: String?) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return }
        for name in names where name != uid {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(name))
        }
    }
}
