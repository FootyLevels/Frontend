import CryptoKit
import Foundation
import Security

struct UploadDraft: Codable, Identifiable, Equatable {
    let id: String
    let ownerId: String
    let scope: String
    let title: String
    let label: String?
    let source: String
    let byteSize: Int
    let sha256: String
    var projectId: String?
    var uploadId: String?
    var discarding = false
}

/// Private local files contain no Firebase token or signed storage capability.
/// Upload Location is a bearer capability, so keep it separately in Keychain.
struct UploadDraftStore {
    let root: URL
    let scope: String
    private let service = "ca.sheridan.FootyLevels.upload-locations"

    init(ownerId: String, environment: ApplicationEnvironment, apiURL: URL, root: URL? = nil) throws {
        let key = [ownerId, environment.projectID, apiURL.absoluteString].joined(separator: "\n")
        scope = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PrivateUploads", isDirectory: true)
        self.root = base.appendingPathComponent(scope, isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var privateRoot = self.root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try privateRoot.setResourceValues(values)
    }

    func directory(_ id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw ClipUploadError.localStorage }
        return root.appendingPathComponent(id, isDirectory: true)
    }

    func file(_ draft: UploadDraft) throws -> URL { try directory(draft.id).appendingPathComponent("clip.mp4") }

    func save(_ draft: UploadDraft) throws {
        guard draft.scope == scope else { throw AccountAPIError.sessionChanged }
        let dir = try directory(draft.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try JSONEncoder().encode(draft).write(to: dir.appendingPathComponent("draft.json"),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func load() throws -> [UploadDraft] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .compactMap { dir in
                guard UUID(uuidString: dir.lastPathComponent) != nil,
                      let data = try? Data(contentsOf: dir.appendingPathComponent("draft.json")),
                      let draft = try? JSONDecoder().decode(UploadDraft.self, from: data),
                      draft.id == dir.lastPathComponent, draft.scope == scope else { return nil }
                return draft
            }
            .sorted { $0.id < $1.id }
    }

    func location(for draft: UploadDraft) throws -> URL? {
        var query = keyQuery(draft)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let text = String(data: data, encoding: .utf8), let url = URL(string: text) else {
            throw ClipUploadError.localStorage
        }
        return url
    }

    func setLocation(_ url: URL?, for draft: UploadDraft) throws {
        let query = keyQuery(draft)
        let deleted = SecItemDelete(query as CFDictionary)
        guard deleted == errSecSuccess || deleted == errSecItemNotFound else { throw ClipUploadError.localStorage }
        if let url {
            var item = query
            item[kSecValueData as String] = Data(url.absoluteString.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw ClipUploadError.localStorage }
        }
    }

    func remove(_ draft: UploadDraft) throws {
        try setLocation(nil, for: draft)
        try FileManager.default.removeItem(at: directory(draft.id))
    }

    private func keyQuery(_ draft: UploadDraft) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: scope + "/" + draft.id]
    }

    static func fingerprint(_ file: URL) throws -> (bytes: Int, hash: String) {
        let reader = try FileHandle(forReadingFrom: file)
        defer { try? reader.close() }
        var hasher = SHA256()
        var bytes = 0
        while let block = try reader.read(upToCount: 1024 * 1024), !block.isEmpty {
            try Task.checkCancellation()
            bytes += block.count
            guard bytes <= 52_428_800 else { throw ClipUploadError.tooLarge }
            hasher.update(data: block)
        }
        guard bytes > 0 else { throw ClipUploadError.invalidVideo }
        return (bytes, hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }
}
