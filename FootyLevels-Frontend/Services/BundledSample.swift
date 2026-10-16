import Foundation

/// **The over fake** — the finished example from `3d-model-backend/data/over-fake`,
/// shipped inside the app so the full workspace works with no server.
///
/// Only the files a renderer needs are bundled (see `SampleData/OverFake.bundle`):
/// `project.json`, the video, key-frame images and meshes, and the final
/// ground-aligned motion. Paths in `project.json` stay as the server writes them
/// (`/assets-data/over-fake/...`); `fileURL(forAssetPath:)` maps them into the
/// bundle, so every view loads the sample exactly as it would a server project.
enum BundledSample {
    static let id = "over-fake"

    private static let assetPrefix = "/assets-data/\(id)/"

    private static var root: URL? {
        Bundle.main.url(forResource: "OverFake", withExtension: "bundle")
    }

    /// Decoded once; nil only if the bundle is missing from the build.
    static let project: SkillLabProject? = {
        guard let url = root?.appendingPathComponent("project.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SkillLabProject.self, from: data)
    }()

    static func isSample(_ projectId: String) -> Bool { projectId == id }

    /// The bundled file for a server asset path, ignoring any `?v=` cache-buster.
    static func fileURL(forAssetPath path: String) -> URL? {
        let clean = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        guard clean.hasPrefix(assetPrefix), let root else { return nil }
        let relative = String(clean.dropFirst(assetPrefix.count))
        // Reject anything that could climb out of the bundle.
        guard !relative.isEmpty, !relative.split(separator: "/").contains("..") else { return nil }
        let url = root.appendingPathComponent(relative)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
