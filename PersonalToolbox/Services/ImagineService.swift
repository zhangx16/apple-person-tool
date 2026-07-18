import Foundation
import UIKit

// MARK: - Assets & job status

struct ImagineAsset: Sendable, Equatable {
    /// Remote URL when the gateway returns one.
    var remoteURL: String?
    /// Decoded image/video bytes (b64 response or after download).
    var data: Data?
    /// Suggested file extension without dot (`png`, `jpg`, `mp4`).
    var fileExtension: String

    init(remoteURL: String? = nil, data: Data? = nil, fileExtension: String = "png") {
        self.remoteURL = remoteURL
        self.data = data
        self.fileExtension = fileExtension
    }
}

enum VideoJobStatus: Sendable, Equatable {
    case pending
    case processing
    case completed(url: String?, data: Data?)
    case failed(message: String)
    /// Wall-clock poll deadline exceeded (terminal; keeps request_id for retry).
    case timedOut

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .timedOut: return true
        case .pending, .processing: return false
        }
    }
}

// MARK: - Service

/// Grok Imagine media client (images / edits / videos) via sub2api OpenAI-compatible routes.
actor ImagineService {
    static let shared = ImagineService()

    private let client = NetworkClient.shared

    /// Poll interval for video status (DESIGN: 2–3s).
    static let videoPollIntervalNanoseconds: UInt64 = 2_500_000_000
    /// Max wait for video completion (DESIGN: 5–10 min). Default 8 min.
    static let videoTimeout: TimeInterval = 8 * 60

    // MARK: Headers

    private func jsonHeaders(apiKey: String) -> [String: String] {
        [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
    }

    private func authHeaders(apiKey: String) -> [String: String] {
        [
            "Authorization": "Bearer \(apiKey)",
            "Accept": "application/json"
        ]
    }

    // MARK: Image generation

    /// POST `/v1/images/generations`
    func generateImage(
        baseURL: String,
        apiKey: String,
        model: String,
        prompt: String,
        n: Int = 1,
        size: String = "1024x1024"
    ) async throws -> [ImagineAsset] {
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "n": max(1, min(n, 4)),
            "size": size,
            "response_format": "b64_json"
        ]
        let data = try await postJSON(
            baseURL: baseURL,
            path: "/v1/images/generations",
            apiKey: apiKey,
            body: body,
            profile: .sse
        )
        return try Self.parseImageAssets(from: data)
    }

    // MARK: Image edit

    /// POST `/v1/images/edits` using JSON + data URL (multipart not required; backend accepts data URLs).
    func editImage(
        baseURL: String,
        apiKey: String,
        model: String,
        prompt: String,
        imageData: Data,
        maskData: Data? = nil,
        size: String = "1024x1024"
    ) async throws -> [ImagineAsset] {
        let mime = Self.imageMIME(for: imageData)
        let dataURL = "data:\(mime);base64,\(imageData.base64EncodedString())"
        var body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "image": dataURL,
            "size": size,
            "response_format": "b64_json"
        ]
        if let maskData, !maskData.isEmpty {
            let maskMIME = Self.imageMIME(for: maskData)
            body["mask"] = ["image_url": "data:\(maskMIME);base64,\(maskData.base64EncodedString())"]
        }
        let data = try await postJSON(
            baseURL: baseURL,
            path: "/v1/images/edits",
            apiKey: apiKey,
            body: body,
            profile: .sse
        )
        return try Self.parseImageAssets(from: data)
    }

    // MARK: Video

    /// POST `/v1/videos/generations` → request_id
    func generateVideo(
        baseURL: String,
        apiKey: String,
        model: String,
        prompt: String,
        size: String = "1280x720"
    ) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "size": size
        ]
        let data = try await postJSON(
            baseURL: baseURL,
            path: "/v1/videos/generations",
            apiKey: apiKey,
            body: body,
            profile: .sse
        )
        guard let requestID = Self.extractVideoRequestID(from: data) else {
            throw NetworkError.message("未能解析视频任务 ID")
        }
        return requestID
    }

    /// GET `/v1/videos/{request_id}`
    func videoStatus(
        baseURL: String,
        apiKey: String,
        requestID: String
    ) async throws -> VideoJobStatus {
        let (data, http) = try await client.data(
            base: baseURL,
            path: "/v1/videos/\(requestID)",
            method: "GET",
            headers: authHeaders(apiKey: apiKey),
            profile: .rest
        )
        if http.statusCode == 401 { throw NetworkError.unauthorized }
        if http.statusCode == 403 {
            let msg = Self.extractErrorMessage(from: data) ?? "无权限访问视频任务"
            throw NetworkError.message(msg)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        return Self.parseVideoStatus(from: data)
    }

    /// Poll until completed / failed / timedOut. Throws only on cancellation or non-recoverable poll errors.
    /// Wall-clock timeout returns `.timedOut` (does **not** throw) so callers can update the message store.
    func pollVideoUntilDone(
        baseURL: String,
        apiKey: String,
        requestID: String,
        timeout: TimeInterval = videoTimeout,
        onProgress: (@Sendable (VideoJobStatus) async -> Void)? = nil
    ) async throws -> VideoJobStatus {
        let deadline = Date().addingTimeInterval(timeout)
        var last: VideoJobStatus = .pending
        while Date() < deadline {
            try Task.checkCancellation()
            last = try await videoStatus(baseURL: baseURL, apiKey: apiKey, requestID: requestID)
            await onProgress?(last)
            if last.isTerminal { return last }
            try await Task.sleep(nanoseconds: Self.videoPollIntervalNanoseconds)
        }
        let timedOut: VideoJobStatus = .timedOut
        await onProgress?(timedOut)
        return timedOut
    }

    // MARK: Download remote media

    func downloadData(from remoteURL: String) async throws -> Data {
        guard let url = URL(string: remoteURL) else { throw NetworkError.invalidURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        return data
    }

    // MARK: Local cache (Application Support/Imagine/)

    /// Ensures `Application Support/Imagine/` exists and returns it.
    nonisolated static func imagineDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = root.appendingPathComponent("Imagine", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Writes bytes under Imagine/ and returns a **relative** path (`Imagine/<name>`).
    nonisolated static func cacheMedia(data: Data, fileExtension: String, preferredName: String? = nil) throws -> String {
        let dir = try imagineDirectory()
        let ext = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        let name = preferredName ?? "\(UUID().uuidString).\(ext.isEmpty ? "bin" : ext)"
        let fileURL = dir.appendingPathComponent(name)
        try data.write(to: fileURL, options: .atomic)
        return "Imagine/\(name)"
    }

    /// Resolves a relative `Imagine/...` path or absolute path to a file URL.
    nonisolated static func resolveLocalURL(_ path: String) -> URL? {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return nil }
        // path may be "Imagine/foo.png" or just "foo.png"
        if path.hasPrefix("Imagine/") {
            return support.appendingPathComponent(path)
        }
        return support.appendingPathComponent("Imagine", isDirectory: true).appendingPathComponent(path)
    }

    /// Deletes a cached media file if present.
    nonisolated static func deleteCachedMedia(relativePath: String?) {
        guard let relativePath, !relativePath.isEmpty,
              let url = resolveLocalURL(relativePath) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Materialize an asset to disk (download remote if needed).
    func materializeToCache(_ asset: ImagineAsset, preferredExtension: String? = nil) async throws -> (relativePath: String, remoteURL: String?) {
        var bytes = asset.data
        if bytes == nil, let remote = asset.remoteURL, !remote.isEmpty {
            bytes = try await downloadData(from: remote)
        }
        guard let data = bytes, !data.isEmpty else {
            throw NetworkError.message("媒体内容为空")
        }
        let ext = preferredExtension ?? asset.fileExtension
        let path = try Self.cacheMedia(data: data, fileExtension: ext)
        return (path, asset.remoteURL)
    }

    // MARK: HTTP helper

    private func postJSON(
        baseURL: String,
        path: String,
        apiKey: String,
        body: [String: Any],
        profile: TimeoutProfile
    ) async throws -> Data {
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let (data, http) = try await client.data(
            base: baseURL,
            path: path,
            method: "POST",
            headers: jsonHeaders(apiKey: apiKey),
            body: bodyData,
            profile: profile
        )
        if http.statusCode == 401 { throw NetworkError.unauthorized }
        if http.statusCode == 403 {
            let msg = Self.extractErrorMessage(from: data)
                ?? "无权限（组可能未开启图片/视频生成）"
            throw NetworkError.message(msg)
        }
        guard (200..<300).contains(http.statusCode) else {
            if let msg = Self.extractErrorMessage(from: data) {
                throw NetworkError.message(msg)
            }
            throw NetworkClient.httpError(status: http.statusCode, body: data)
        }
        return data
    }

    // MARK: Parsing

    nonisolated static func parseImageAssets(from data: Data) throws -> [ImagineAsset] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.message("无法解析生图响应")
        }
        if let err = root["error"] as? [String: Any],
           let msg = err["message"] as? String, !msg.isEmpty {
            throw NetworkError.message(msg)
        }

        var items: [[String: Any]] = []
        if let dataArr = root["data"] as? [[String: Any]] {
            items = dataArr
        } else if let images = root["images"] as? [[String: Any]] {
            items = images
        }

        var assets: [ImagineAsset] = []
        for item in items {
            let url = (item["url"] as? String)
                ?? (item["image_url"] as? String)
                ?? ((item["image_url"] as? [String: Any])?["url"] as? String)
            let b64 = (item["b64_json"] as? String) ?? (item["b64"] as? String)
            var imageData: Data?
            if let b64, !b64.isEmpty {
                imageData = Data(base64Encoded: b64)
                    ?? Data(base64Encoded: b64, options: .ignoreUnknownCharacters)
            }
            if imageData == nil, let url, url.hasPrefix("data:"),
               let comma = url.firstIndex(of: ",") {
                let encoded = String(url[url.index(after: comma)...])
                imageData = Data(base64Encoded: encoded)
                    ?? Data(base64Encoded: encoded, options: .ignoreUnknownCharacters)
            }
            let remote = (url?.hasPrefix("data:") == true) ? nil : url
            if imageData != nil || (remote != nil && !(remote?.isEmpty ?? true)) {
                let ext: String
                if let remote, remote.lowercased().contains(".jpg") || remote.lowercased().contains(".jpeg") {
                    ext = "jpg"
                } else {
                    ext = "png"
                }
                assets.append(ImagineAsset(remoteURL: remote, data: imageData, fileExtension: ext))
            }
        }

        // Single-object fallbacks
        if assets.isEmpty {
            if let url = root["url"] as? String {
                assets.append(ImagineAsset(remoteURL: url, fileExtension: "png"))
            } else if let b64 = root["b64_json"] as? String, let d = Data(base64Encoded: b64) {
                assets.append(ImagineAsset(data: d, fileExtension: "png"))
            }
        }

        guard !assets.isEmpty else {
            throw NetworkError.message("生图响应中没有图片")
        }
        return assets
    }

    nonisolated static func extractVideoRequestID(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return firstString(in: root, keys: [
            "request_id", "id", "requestId"
        ], nestedPaths: [
            ["data", "request_id"], ["data", "id"],
            ["video", "request_id"], ["video", "id"]
        ])
    }

    nonisolated static func parseVideoStatus(from data: Data) -> VideoJobStatus {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failed(message: "无法解析视频状态")
        }
        if let err = root["error"] as? [String: Any] {
            let msg = (err["message"] as? String) ?? "视频生成失败"
            // Some gateways put error alongside status — only hard-fail if status says so or no status.
            let status = (root["status"] as? String)?.lowercased() ?? ""
            if status.isEmpty || status.contains("fail") || status.contains("error") {
                return .failed(message: msg)
            }
        }

        let statusRaw = (
            (root["status"] as? String)
                ?? (root["state"] as? String)
                ?? ((root["video"] as? [String: Any])?["status"] as? String)
                ?? ((root["data"] as? [String: Any])?["status"] as? String)
                ?? ""
        ).lowercased()

        let url = firstString(in: root, keys: ["url", "video_url", "output_url"], nestedPaths: [
            ["video", "url"], ["data", "url"], ["data", "video_url"],
            ["output", "url"], ["result", "url"]
        ])

        if statusRaw.contains("fail") || statusRaw.contains("error") || statusRaw == "cancelled" {
            let msg = extractErrorMessage(from: data) ?? "视频生成失败"
            return .failed(message: msg)
        }
        if statusRaw.contains("complete") || statusRaw == "succeeded" || statusRaw == "success" || statusRaw == "done" {
            return .completed(url: url, data: nil)
        }
        // If URL already present without explicit status, treat as done.
        if let url, !url.isEmpty, statusRaw.isEmpty {
            return .completed(url: url, data: nil)
        }
        if statusRaw.contains("process") || statusRaw.contains("run") || statusRaw == "in_progress" {
            return .processing
        }
        return .pending
    }

    nonisolated static func extractErrorMessage(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let err = root["error"] as? [String: Any], let msg = err["message"] as? String, !msg.isEmpty {
            return msg
        }
        if let msg = root["message"] as? String, !msg.isEmpty { return msg }
        if let err = root["error"] as? String, !err.isEmpty { return err }
        return nil
    }

    nonisolated private static func firstString(
        in value: Any,
        keys: [String],
        nestedPaths: [[String]]
    ) -> String? {
        if let dict = value as? [String: Any] {
            for k in keys {
                if let s = dict[k] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return s
                }
            }
            for path in nestedPaths {
                var cur: Any? = dict
                for segment in path {
                    cur = (cur as? [String: Any])?[segment]
                }
                if let s = cur as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return s
                }
            }
        }
        return nil
    }

    nonisolated static func imageMIME(for data: Data) -> String {
        if data.count >= 3, data[0] == 0xFF, data[1] == 0xD8, data[2] == 0xFF { return "image/jpeg" }
        if data.count >= 8, data[0] == 0x89, data[1] == 0x50 { return "image/png" }
        if data.count >= 3, data[0] == 0x47, data[1] == 0x49, data[2] == 0x46 { return "image/gif" }
        if data.count >= 12,
           data[0] == 0x52, data[1] == 0x49, data[2] == 0x46, data[3] == 0x46 {
            return "image/webp"
        }
        return "image/png"
    }

    /// Downscale / re-encode picker images to keep edit payloads reasonable (~1.5MB JPEG).
    nonisolated static func compressImageData(_ data: Data, maxDimension: CGFloat = 1536, quality: CGFloat = 0.82) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let size = image.size
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: max(1, floor(size.width * scale)), height: max(1, floor(size.height * scale)))
        let renderer = UIGraphicsImageRenderer(size: target)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: quality) ?? data
    }
}
