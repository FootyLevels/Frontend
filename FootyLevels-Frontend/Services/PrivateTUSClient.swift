import Foundation

private final class RejectStorageRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Storage gets only the scoped upload signature, never Firebase credentials.
/// At most one 6 MiB block is held in memory. Every confirmed offset comes from TUS.
@MainActor
final class PrivateTUSClient {
    static let chunkSize = 6 * 1024 * 1024
    let host: String
    private let session: URLSession
    private let redirects = RejectStorageRedirects()

    init(environment: ApplicationEnvironment, session: URLSession? = nil) {
        host = environment.storageHost
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 60
        self.session = session ?? URLSession(configuration: config)
    }

    func validate(_ grant: PrivateUploadGrant, draft: UploadDraft) throws -> URL {
        guard grant.status == "uploading", grant.protocol == "tus", grant.id == draft.uploadId, grant.expectedBytes == draft.byteSize,
              grant.chunkSize == Self.chunkSize,
              let text = grant.endpoint, let url = URL(string: text),
              validURL(url, creation: true),
              let headers = grant.headers, Set(headers.keys) == ["x-signature", "x-upsert"],
              let signature = headers["x-signature"], !signature.isEmpty,
              signature.utf8.count <= 8192, !signature.contains("\n"), !signature.contains("\r"),
              headers["x-upsert"] == "false",
              let metadata = grant.metadata, Set(metadata.keys) == ["bucketName", "objectName", "contentType", "cacheControl"],
              metadata["bucketName"] == "private-media", metadata["contentType"] == "video/mp4",
              metadata["cacheControl"] == "0", let pid = draft.projectId,
              metadata["objectName"] == "users/\(draft.ownerId)/projects/\(pid)/source/\(grant.id).mp4"
        else { throw ClipUploadError.invalidGrant }
        return url
    }

    func validURL(_ url: URL, creation: Bool = false) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host == host, parts.port == nil || parts.port == 443,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              !parts.percentEncodedPath.contains("%"), !parts.path.contains("\\"),
              !parts.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return false }
        let path = "/storage/v1/upload/resumable/sign"
        return creation ? parts.path == path : parts.path.hasPrefix(path + "/") && parts.path.count > path.count + 1
    }

    func create(_ grant: PrivateUploadGrant, draft: UploadDraft,
                checkSession: () throws -> Void) async throws -> URL {
        let endpoint = try validate(grant, draft: draft)
        var request = try makeRequest("POST", url: endpoint, grant: grant)
        request.setValue(String(draft.byteSize), forHTTPHeaderField: "Upload-Length")
        request.setValue(grant.metadata!.keys.sorted().map {
            $0 + " " + Data(grant.metadata![$0]!.utf8).base64EncodedString()
        }.joined(separator: ","), forHTTPHeaderField: "Upload-Metadata")
        request.httpBody = Data()
        let response = try await send(request, checkSession: checkSession)
        if [400, 409].contains(response.statusCode) { throw ClipUploadError.alreadyStored }
        try status(response, allowed: [201])
        guard let text = response.value(forHTTPHeaderField: "Location"),
              let url = URL(string: text, relativeTo: endpoint)?.absoluteURL, validURL(url) else {
            throw ClipUploadError.invalidGrant
        }
        return url
    }

    func offset(at url: URL, grant: PrivateUploadGrant, total: Int,
                checkSession: () throws -> Void) async throws -> Int {
        let response = try await send(makeRequest("HEAD", url: url, grant: grant), checkSession: checkSession)
        try status(response, allowed: [200, 204])
        guard let length = response.value(forHTTPHeaderField: "Upload-Length"), Int(length) == total,
              let value = response.value(forHTTPHeaderField: "Upload-Offset"),
              let offset = Int(value), (0...total).contains(offset) else { throw ClipUploadError.invalidOffset }
        return offset
    }

    func transfer(file: URL, at url: URL, grant: PrivateUploadGrant, total: Int,
                  checkSession: () throws -> Void, progress: (Double) -> Void) async throws {
        var position = try await offset(at: url, grant: grant, total: total, checkSession: checkSession)
        progress(Double(position) / Double(total))
        let reader = try FileHandle(forReadingFrom: file)
        defer { try? reader.close() }
        var conflicts = 0
        while position < total {
            try checkSession()
            try reader.seek(toOffset: UInt64(position))
            guard let bytes = try reader.read(upToCount: min(Self.chunkSize, total - position)), !bytes.isEmpty else {
                throw ClipUploadError.changedFile
            }
            var request = try makeRequest("PATCH", url: url, grant: grant)
            request.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
            request.setValue(String(position), forHTTPHeaderField: "Upload-Offset")
            request.httpBody = bytes
            let response = try await send(request, checkSession: checkSession)
            if response.statusCode == 409 {
                conflicts += 1
                guard conflicts <= 3 else { throw ClipUploadError.invalidOffset }
                position = try await offset(at: url, grant: grant, total: total, checkSession: checkSession)
                continue
            }
            try status(response, allowed: [204])
            guard let value = response.value(forHTTPHeaderField: "Upload-Offset"),
                  let next = Int(value), next == position + bytes.count, next <= total else {
                throw ClipUploadError.invalidOffset
            }
            position = next
            conflicts = 0
            progress(Double(position) / Double(total))
        }
    }

    private func makeRequest(_ method: String, url: URL, grant: PrivateUploadGrant) throws -> URLRequest {
        guard validURL(url, creation: method == "POST"),
              let signature = grant.headers?["x-signature"], !signature.isEmpty,
              !signature.contains("\r"), !signature.contains("\n") else { throw ClipUploadError.invalidGrant }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue(signature, forHTTPHeaderField: "x-signature")
        request.setValue("false", forHTTPHeaderField: "x-upsert")
        return request
    }

    private func send(_ request: URLRequest, checkSession: () throws -> Void) async throws -> HTTPURLResponse {
        try checkSession()
        let response: URLResponse
        do { (_, response) = try await session.data(for: request, delegate: redirects) }
        catch { try checkSession(); throw error }
        try checkSession()
        guard let response = response as? HTTPURLResponse else { throw ClipUploadError.invalidGrant }
        return response
    }

    private func status(_ response: HTTPURLResponse, allowed: Set<Int>) throws {
        if allowed.contains(response.statusCode) { return }
        switch response.statusCode {
        case 401, 403: throw ClipUploadError.capabilityExpired
        case 404, 410: throw ClipUploadError.resourceMissing
        default: throw ClipUploadError.storage(response.statusCode)
        }
    }
}
