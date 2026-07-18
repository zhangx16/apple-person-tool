import Foundation
import WebKit
import UIKit

/// Local Douyin (抖音) share-link resolver + media downloader.
/// Ported from BlackCCCat Media-Downloader `services/douyin.ts` (Scripting),
/// using WKWebView instead of Scripting's WebViewController.
@MainActor
final class DouyinService: NSObject {
    static let shared = DouyinService()

    static let mobileUA = [
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)",
        "AppleWebKit/605.1.15 (KHTML, like Gecko)",
        "Version/18.0 Mobile/15E148 Safari/604.1"
    ].joined(separator: " ")

    private var activeWebView: WKWebView?
    private var activeNav: DouyinWebNav?

    private override init() {
        super.init()
    }

    // MARK: - Paths

    var rootDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("douyin-downloader", isDirectory: true)
    }

    var videosDirectory: URL {
        rootDirectory.appendingPathComponent("videos", isDirectory: true)
    }

    var imagesDirectory: URL {
        rootDirectory.appendingPathComponent("images", isDirectory: true)
    }

    func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }

    /// List completed local media files under douyin-downloader.
    func listLocalFiles() -> [YTFileItem] {
        var items: [YTFileItem] = []
        let fm = FileManager.default
        for dir in [videosDirectory, imagesDirectory] {
            guard let urls = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in urls {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) }
                items.append(YTFileItem(
                    id: "local:\(url.path)",
                    name: url.lastPathComponent,
                    size: size,
                    path: url.path
                ))
            }
        }
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Detection

    nonisolated static func isDouyinURL(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let host = URL(string: s)?.host?.lowercased()
                ?? URL(string: s.hasPrefix("http") ? s : "https://\(s)")?.host?.lowercased()
        else {
            // short share text often embeds the host
            return s.contains("douyin.com")
                || s.contains("iesdouyin.com")
                || s.contains("v.douyin.com")
                || s.contains("抖音")
        }
        return host == "douyin.com"
            || host.hasSuffix(".douyin.com")
            || host == "iesdouyin.com"
            || host.hasSuffix(".iesdouyin.com")
            || host.contains("douyin")
    }

    /// Pull first http(s) URL from share text / clipboard paste.
    nonisolated static func extractURL(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http") {
            return trimmed.components(separatedBy: .whitespacesAndNewlines).first
        }
        let pattern = #"https?://[^\s<>"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range),
              let swiftRange = Range(match.range, in: trimmed) else { return nil }
        var url = String(trimmed[swiftRange])
        // Strip common trailing punctuation from share text.
        while let last = url.last, ".,);]》」』".contains(last) {
            url.removeLast()
        }
        return url
    }

    // MARK: - Public API

    /// Resolve page metadata only (title / thumbnail).
    func parseMetadata(
        sourceURL: String,
        onLog: ((String) -> Void)? = nil
    ) async throws -> VideoMetadata {
        let url = Self.extractURL(from: sourceURL) ?? sourceURL
        onLog?("正在解析抖音页面…")
        let extracted = try await extractFromWebView(url: url, onLog: onLog)
        let title = extracted.title.isEmpty ? "抖音视频" : extracted.title
        let thumb = Self.extractThumbnailURL(extracted)
        return VideoMetadata(
            title: title,
            duration: nil,
            thumbnail: thumb,
            uploader: nil
        )
    }

    /// Full parse + download pipeline. Reports progress 0...1.
    func download(
        sourceURL: String,
        preferNoWatermark: Bool = true,
        onProgress: ((Double, String) -> Void)? = nil,
        onLog: ((String) -> Void)? = nil
    ) async throws -> DouyinDownloadResult {
        let url = Self.extractURL(from: sourceURL) ?? sourceURL
        onProgress?(0.03, "正在分析分享页面")
        onLog?("开始解析分享链接…")

        let extracted = try await extractFromWebView(url: url, onLog: onLog, onProgress: onProgress)
        let imageURLs = Self.extractImageURLs(extracted)
        let galleryLike = Self.isGalleryURL(url)
            || Self.isGalleryURL(extracted.canonical)
            || Self.isGalleryURL(extracted.pageURL)

        if extracted.videoSrc == nil,
           Self.extractInlineDetailRoot(extracted) == nil,
           imageURLs.isEmpty {
            throw NetworkError.message("未能从页面中提取到视频地址、图片地址或作品数据")
        }

        try ensureDirectories()
        onLog?("下载目录：Documents/douyin-downloader/")

        if galleryLike && !imageURLs.isEmpty {
            onLog?("识别为图文，批量下载图片…")
            return try await downloadImages(
                sourceURL: url,
                extracted: extracted,
                imageURLs: imageURLs,
                onProgress: onProgress,
                onLog: onLog
            )
        }

        let candidates = Self.buildDownloadCandidates(extracted, preferNoWatermark: preferNoWatermark)
        if candidates.isEmpty {
            if !imageURLs.isEmpty {
                return try await downloadImages(
                    sourceURL: url,
                    extracted: extracted,
                    imageURLs: imageURLs,
                    onProgress: onProgress,
                    onLog: onLog
                )
            }
            throw NetworkError.message("未生成可用下载候选地址")
        }

        onLog?("共 \(candidates.count) 个候选：\(candidates.map(\.label).joined(separator: ", "))")
        onProgress?(0.22, "已生成 \(candidates.count) 个候选")

        var lastError = "未命中可用视频资源"
        for (index, candidate) in candidates.enumerated() {
            try Task.checkCancellation()
            let attemptBase = 0.22 + (Double(index) / Double(candidates.count)) * 0.5
            onProgress?(attemptBase, "尝试候选 \(index + 1)/\(candidates.count)：\(candidate.label)")
            onLog?("尝试 \(index + 1)/\(candidates.count)：\(candidate.label)")

            do {
                let result = try await tryDownloadCandidate(
                    candidate: candidate,
                    extracted: extracted,
                    sourceURL: url,
                    progressStart: min(0.78, attemptBase + 0.04),
                    progressEnd: min(0.94, attemptBase + 0.5 / Double(candidates.count)),
                    onProgress: onProgress,
                    onLog: onLog
                )
                return result
            } catch {
                lastError = "\(candidate.label): \(error.localizedDescription)"
                onLog?("候选失败：\(lastError)")
            }
        }

        if !imageURLs.isEmpty {
            onLog?("视频候选均失败，回退图文下载。")
            return try await downloadImages(
                sourceURL: url,
                extracted: extracted,
                imageURLs: imageURLs,
                onProgress: onProgress,
                onLog: onLog
            )
        }

        throw NetworkError.message("所有下载候选均失败：\(lastError)")
    }

    // MARK: - WebView extract

    private func extractFromWebView(
        url: String,
        onLog: ((String) -> Void)?,
        onProgress: ((Double, String) -> Void)? = nil
    ) async throws -> DouyinExtractedInfo {
        guard let pageURL = URL(string: url) else {
            throw NetworkError.message("无效的链接")
        }

        try Task.checkCancellation()
        onLog?("创建 WebView 并加载页面…")
        onProgress?(0.05, "正在打开分享链接")

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        webView.customUserAgent = Self.mobileUA
        webView.isOpaque = false
        webView.backgroundColor = .clear

        // Keep a reference so the view is not deallocated mid-load.
        let nav = DouyinWebNav()
        activeWebView = webView
        activeNav = nav
        webView.navigationDelegate = nav

        defer {
            webView.stopLoading()
            webView.navigationDelegate = nil
            activeWebView = nil
            activeNav = nil
        }

        var request = URLRequest(url: pageURL)
        request.setValue(Self.mobileUA, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 45
        webView.load(request)

        try await nav.waitForLoad(timeout: 35)
        onProgress?(0.1, "页面已加载，等待内嵌数据")
        try await Task.sleep(nanoseconds: 2_500_000_000)

        // Try to kick the player.
        _ = try? await webView.evaluateJavaScript("""
        (async () => {
          const video = document.querySelector('video');
          if (video) {
            try { video.muted = true; await video.play(); } catch (e) {}
          }
          return true;
        })()
        """)

        try await Task.sleep(nanoseconds: 3_500_000_000)
        onProgress?(0.16, "正在读取页面数据")
        onLog?("正在读取页面内嵌数据…")

        let raw = try await webView.evaluateJavaScript(Self.extractPageJS)
        guard let dict = raw as? [String: Any] else {
            throw NetworkError.message("页面数据解析失败")
        }
        var extracted = DouyinExtractedInfo(dict: dict)
        onLog?("页面：\(extracted.title.isEmpty ? "(无标题)" : extracted.title)")

        let preliminaryImages = Self.extractImageURLs(extracted)
        let galleryLike = Self.isGalleryURL(url)
            || Self.isGalleryURL(extracted.canonical)
            || Self.isGalleryURL(extracted.pageURL)
        let shouldFetchDetail = galleryLike
            || (extracted.videoSrc == nil && preliminaryImages.isEmpty)

        if shouldFetchDetail {
            let awemeId = Self.extractAwemeId(extracted.canonical)
                ?? Self.extractAwemeId(extracted.pageURL)
                ?? Self.extractAwemeId(url)
            if let awemeId {
                onProgress?(0.18, "正在读取作品详情")
                onLog?("尝试拉取 aweme 详情 \(awemeId)…")
                if let json = try? await fetchAwemeDetail(webView: webView, awemeId: awemeId) {
                    extracted.apiDetailJSON = json
                    onLog?("作品详情已命中")
                } else {
                    onLog?("作品详情未命中，继续使用页面数据")
                }
            }
        }

        onProgress?(0.2, "解析完成")
        return extracted
    }

    private func fetchAwemeDetail(webView: WKWebView, awemeId: String) async throws -> String? {
        let js = """
        (async () => {
          const timeout = (ms) => new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), ms));
          const fetchDetail = async () => {
            const endpoints = [
              `https://www.iesdouyin.com/web/api/v2/aweme/iteminfo/?item_ids=${"\(awemeId)"}`,
              `https://www.douyin.com/aweme/v1/web/aweme/detail/?aweme_id=${"\(awemeId)"}&aid=1128&version_name=23.5.0&device_platform=webapp&pc_client_type=1`
            ];
            for (const endpoint of endpoints) {
              try {
                const res = await fetch(endpoint, {
                  credentials: 'include',
                  headers: { 'Accept': 'application/json, text/plain, */*' }
                });
                if (!res.ok) continue;
                const text = await res.text();
                if (text && text.length > 20) return text;
              } catch (e) {}
            }
            return null;
          };
          try {
            return await Promise.race([fetchDetail(), timeout(4500)]);
          } catch (e) {
            return null;
          }
        })()
        """
        let result = try await webView.evaluateJavaScript(js)
        return result as? String
    }

    // MARK: - Download helpers

    private func tryDownloadCandidate(
        candidate: DouyinDownloadCandidate,
        extracted: DouyinExtractedInfo,
        sourceURL: String,
        progressStart: Double,
        progressEnd: Double,
        onProgress: ((Double, String) -> Void)?,
        onLog: ((String) -> Void)?
    ) async throws -> DouyinDownloadResult {
        var request = URLRequest(url: URL(string: candidate.url)!)
        request.httpMethod = "GET"
        request.timeoutInterval = 180
        for (k, v) in candidate.headers {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let (tempURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.message("无响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkError.message("HTTP \(http.statusCode)")
        }

        let finalURL = http.url?.absoluteString ?? candidate.url
        let mime = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard Self.isLikelyMediaResponse(finalURL: finalURL, mimeType: mime) else {
            throw NetworkError.message("响应不是视频资源 (\(mime))")
        }

        let baseName = Self.sanitizeFileName(extracted.title.isEmpty ? "douyin_video" : extracted.title)
        let dest = uniqueFileURL(in: videosDirectory, preferredName: "\(baseName).mp4")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tempURL, to: dest)

        let bytes = (try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard bytes > 0 else { throw NetworkError.message("视频文件为空") }

        onProgress?(1, "下载完成：\(dest.lastPathComponent)")
        onLog?("文件写入完成：\(dest.lastPathComponent) (\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)))")

        return DouyinDownloadResult(
            id: UUID().uuidString,
            sourceURL: sourceURL,
            title: extracted.title.isEmpty ? dest.lastPathComponent : extracted.title,
            filePath: dest.path,
            fileName: dest.lastPathComponent,
            mediaType: .video,
            bytesWritten: Int64(bytes),
            finalURL: finalURL,
            matchedCandidateLabel: candidate.label,
            thumbnailURL: Self.extractThumbnailURL(extracted)
        )
    }

    private func downloadImages(
        sourceURL: String,
        extracted: DouyinExtractedInfo,
        imageURLs: [String],
        onProgress: ((Double, String) -> Void)?,
        onLog: ((String) -> Void)?
    ) async throws -> DouyinDownloadResult {
        let baseName = Self.sanitizeFileName(extracted.title.isEmpty ? "douyin_images" : extracted.title)
        var savedPaths: [String] = []
        var totalBytes: Int64 = 0
        let total = max(imageURLs.count, 1)

        for (index, imageURL) in imageURLs.enumerated() {
            let fraction = 0.25 + 0.7 * (Double(index) / Double(total))
            onProgress?(fraction, "下载图片 \(index + 1)/\(total)")
            onLog?("图片 \(index + 1)/\(total)…")

            guard let url = URL(string: imageURL) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 60
            request.setValue(Self.mobileUA, forHTTPHeaderField: "User-Agent")
            request.setValue("https://www.douyin.com/", forHTTPHeaderField: "Referer")

            do {
                let (tempURL, response) = try await URLSession.shared.download(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    continue
                }
                let finalURL = http.url?.absoluteString ?? imageURL
                let mime = http.value(forHTTPHeaderField: "Content-Type") ?? ""
                guard Self.isLikelyImageResponse(finalURL: finalURL, mimeType: mime) else { continue }
                let ext = Self.imageExtension(finalURL: finalURL, mimeType: mime)
                let dest = uniqueFileURL(in: imagesDirectory, preferredName: "\(baseName)_\(index + 1).\(ext)")
                if FileManager.default.fileExists(atPath: dest.path) {
                    try? FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: tempURL, to: dest)
                let bytes = Int64((try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                if bytes > 0 {
                    savedPaths.append(dest.path)
                    totalBytes += bytes
                }
            } catch {
                onLog?("图片 \(index + 1) 失败：\(error.localizedDescription)")
            }
        }

        guard let first = savedPaths.first else {
            throw NetworkError.message("图文图片下载失败")
        }

        onProgress?(1, "图片下载完成（\(savedPaths.count) 张）")
        return DouyinDownloadResult(
            id: UUID().uuidString,
            sourceURL: sourceURL,
            title: extracted.title.isEmpty ? "抖音图文" : extracted.title,
            filePath: first,
            fileName: (first as NSString).lastPathComponent,
            mediaType: .image,
            bytesWritten: totalBytes,
            finalURL: imageURLs.first ?? sourceURL,
            matchedCandidateLabel: "image_batch_\(savedPaths.count)",
            thumbnailURL: Self.extractThumbnailURL(extracted),
            extraFilePaths: Array(savedPaths.dropFirst())
        )
    }

    private func uniqueFileURL(in directory: URL, preferredName: String) -> URL {
        let ext = (preferredName as NSString).pathExtension
        let stem = (preferredName as NSString).deletingPathExtension
        var candidate = directory.appendingPathComponent(preferredName)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            candidate = directory.appendingPathComponent(name)
            index += 1
        }
        return candidate
    }

    // MARK: - Candidate building (ported)

    private static func buildDownloadCandidates(
        _ extracted: DouyinExtractedInfo,
        preferNoWatermark: Bool
    ) -> [DouyinDownloadCandidate] {
        let baseHeaders = [
            "User-Agent": mobileUA,
            "Origin": "https://www.douyin.com",
            "Accept": "*/*"
        ]
        let pageReferer = extracted.pageURL
        let canonicalReferer = extracted.canonical ?? extracted.pageURL
        var candidates: [DouyinDownloadCandidate] = []

        if let inlineRoot = extractInlineDetailRoot(extracted),
           let video = inlineRoot["video"] as? [String: Any] {
            func pushAddress(label: String, address: Any?) {
                guard let address = address as? [String: Any] else { return }
                let urls = stringArray(from: address["url_list"])
                for url in urls {
                    if preferNoWatermark, url.contains("/playwm/") {
                        candidates.append(.init(
                            label: "\(label)_replace_playwm_to_play",
                            url: url.replacingOccurrences(of: "/playwm/", with: "/play/"),
                            headers: baseHeaders.merging(["Referer": pageReferer]) { _, n in n }
                        ))
                    }
                    candidates.append(.init(
                        label: label,
                        url: url,
                        headers: baseHeaders.merging(["Referer": pageReferer]) { _, n in n }
                    ))
                }
            }

            pushAddress(label: "inline_play_addr_h264", address: video["play_addr_h264"])
            pushAddress(label: "inline_play_addr", address: video["play_addr"])
            pushAddress(label: "inline_play_addr_265", address: video["play_addr_265"])
            pushAddress(label: "inline_download_addr", address: video["download_addr"])

            if let bitRates = video["bit_rate"] as? [Any] {
                for item in bitRates {
                    guard let dict = item as? [String: Any] else { continue }
                    let gear = (dict["gear_name"] as? String)
                        ?? (dict["quality_type"] as? String)
                        ?? "bit_rate"
                    pushAddress(label: "inline_bit_rate_\(gear)", address: dict["play_addr"])
                }
            }
        }

        if let videoSrc = extracted.videoSrc {
            if preferNoWatermark, videoSrc.contains("/playwm/") {
                candidates.append(.init(
                    label: "replace_playwm_to_play",
                    url: videoSrc.replacingOccurrences(of: "/playwm/", with: "/play/"),
                    headers: baseHeaders.merging(["Referer": pageReferer]) { _, n in n }
                ))
            }
            if preferNoWatermark, let videoId = extractVideoId(videoSrc) {
                candidates.append(.init(
                    label: "constructed_play_watermark0",
                    url: "https://www.iesdouyin.com/aweme/v1/play/?video_id=\(videoId)&ratio=720p&line=0&is_play_url=1&watermark=0&source=PackSourceEnum_PUBLISH",
                    headers: baseHeaders.merging(["Referer": canonicalReferer]) { _, n in n }
                ))
            }
            candidates.append(.init(
                label: "videoSrc_pageReferer",
                url: videoSrc,
                headers: baseHeaders.merging(["Referer": pageReferer]) { _, n in n }
            ))
            candidates.append(.init(
                label: "videoSrc_canonicalReferer",
                url: videoSrc,
                headers: baseHeaders.merging(["Referer": canonicalReferer]) { _, n in n }
            ))
        }

        var seen = Set<String>()
        return candidates.filter { c in
            guard !c.url.isEmpty, !seen.contains(c.url) else { return false }
            seen.insert(c.url)
            return true
        }
    }

    // MARK: - JSON helpers

    private static func extractInlineDetailRoot(_ extracted: DouyinExtractedInfo) -> [String: Any]? {
        let direct: [Any?] = [
            parseJSON(extracted.apiDetailJSON),
            parseJSON(extracted.videoInfoResJSON),
            parseJSON(extracted.routerDataJSON)
        ]
        for candidate in direct {
            if let root = extractAwemeDetailRoot(candidate) { return root }
            if let dict = candidate as? [String: Any],
               let loader = dict["loaderData"] as? [String: Any] {
                for value in loader.values {
                    if let hit = extractAwemeDetailRoot(value) { return hit }
                    if let v = value as? [String: Any] {
                        if let nested = extractAwemeDetailRoot(v["data"]) { return nested }
                        if let nested = extractAwemeDetailRoot(v["videoInfoRes"]) { return nested }
                    }
                }
            }
        }
        for hint in extracted.resourceHints {
            if let root = extractAwemeDetailRoot(parseJSON(hint)) { return root }
        }
        return nil
    }

    private static func extractAwemeDetailRoot(_ data: Any?) -> [String: Any]? {
        guard let record = data as? [String: Any] else { return nil }
        if let detail = record["aweme_detail"] as? [String: Any] { return detail }
        if record["video"] is [String: Any] || record["aweme_id"] is String { return record }
        if let list = record["item_list"] as? [Any], let first = list.first as? [String: Any] {
            return first
        }
        if let nested = record["data"] as? [String: Any],
           let detail = nested["aweme_detail"] as? [String: Any] {
            return detail
        }
        return nil
    }

    private static func extractImageURLs(_ extracted: DouyinExtractedInfo) -> [String] {
        var urls: [String] = []
        if let root = extractInlineDetailRoot(extracted) {
            let imagePost = root["image_post_info"] as? [String: Any]
            var images: [Any] = []
            if let post = imagePost {
                images = (post["images"] as? [Any]) ?? (post["image_list"] as? [Any]) ?? []
            }
            if images.isEmpty {
                images = (root["images"] as? [Any]) ?? (root["image_list"] as? [Any]) ?? []
            }
            for image in images {
                guard let img = image as? [String: Any] else { continue }
                var candidates: [String] = []
                for key in [
                    "watermark_free_download_url_list", "origin_image", "display_image",
                    "download_url", "download_addr", "download_url_list", "owner_watermark_image"
                ] {
                    candidates.append(contentsOf: collectMediaURLs(img[key]))
                }
                candidates.append(contentsOf: collectMediaURLs(img))
                let sorted = Array(Set(candidates)).sorted { mediaURLPriority($0) < mediaURLPriority($1) }
                if let first = sorted.first { urls.append(first) }
            }
        }
        if urls.isEmpty {
            urls.append(contentsOf: extracted.imageURLs.filter { url in
                let lower = url.lowercased()
                return lower.hasPrefix("http")
                    && (lower.contains("douyinpic") || lower.contains("p3-sign") || lower.contains("tos-cn"))
                    && !lower.contains("avatar")
            })
        }
        return dedupeMediaURLs(urls.filter { url in
            let lower = url.lowercased()
            return lower.hasPrefix("http")
                && !lower.contains("avatar")
                && !lower.contains("emoji")
                && !lower.contains("logo")
        })
    }

    private static func extractThumbnailURL(_ extracted: DouyinExtractedInfo) -> String? {
        if let t = extracted.thumbnailURL, !t.isEmpty { return t }
        guard let root = extractInlineDetailRoot(extracted),
              let video = root["video"] as? [String: Any] else { return nil }
        for key in ["cover", "origin_cover", "dynamic_cover", "animated_cover"] {
            if let url = firstURL(from: video[key]) { return url }
        }
        return nil
    }

    private static func collectMediaURLs(_ source: Any?) -> [String] {
        guard let source else { return [] }
        if let s = source as? String { return s.isEmpty ? [] : [s] }
        if let arr = source as? [Any] { return arr.flatMap { collectMediaURLs($0) } }
        guard let dict = source as? [String: Any] else { return [] }
        var urls: [String] = []
        for key in ["url_list", "urlList"] {
            urls.append(contentsOf: stringArray(from: dict[key]))
        }
        for key in ["url", "uri"] {
            if let s = dict[key] as? String, !s.isEmpty { urls.append(s) }
        }
        return urls
    }

    private static func firstURL(from address: Any?) -> String? {
        collectMediaURLs(address).first
    }

    private static func stringArray(from value: Any?) -> [String] {
        guard let arr = value as? [Any] else { return [] }
        return arr.compactMap { $0 as? String }.filter { !$0.isEmpty }
    }

    private static func mediaURLPriority(_ url: String) -> Int {
        let lower = url.lowercased()
        let watermarked = ["tplv-dy-water", "dy-water", "owner_watermark", "watermark_image", "watermark=1", "playwm"]
            .contains { lower.contains($0) }
        return (watermarked ? 100 : 0) + (lower.contains(".webp") ? 1 : 0)
    }

    private static func dedupeMediaURLs(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in items {
            let key = item.split(separator: "?").first.map(String.init) ?? item
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(item)
        }
        return result
    }

    private static func extractVideoId(_ url: String?) -> String? {
        guard let url else { return nil }
        guard let regex = try? NSRegularExpression(pattern: #"[?&]video_id=([^&]+)"#) else { return nil }
        let range = NSRange(url.startIndex..<url.endIndex, in: url)
        guard let match = regex.firstMatch(in: url, range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: url) else { return nil }
        return String(url[r])
    }

    private static func extractAwemeId(_ url: String?) -> String? {
        guard let url else { return nil }
        let patterns = [
            #"/(?:share/)?(?:video|note|gallery|slides)/(\d{15,20})"#,
            #"[?&](?:modal_id|aweme_id|item_id)=(\d{15,20})"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(url.startIndex..<url.endIndex, in: url)
            if let match = regex.firstMatch(in: url, range: range),
               match.numberOfRanges > 1,
               let r = Range(match.range(at: 1), in: url) {
                return String(url[r])
            }
        }
        return nil
    }

    private static func isGalleryURL(_ url: String?) -> Bool {
        guard let url else { return false }
        return url.range(of: #"/(?:share/)?(?:note|gallery|slides)/"#, options: .regularExpression) != nil
    }

    private static func isLikelyMediaResponse(finalURL: String, mimeType: String) -> Bool {
        if mimeType.hasPrefix("video/") { return true }
        if mimeType == "application/octet-stream" { return true }
        let tokens = ["douyinvod", ".mp4", "video_mp4", "tos-cn", "aweme.snssdk.com/aweme/v1/play"]
        return tokens.contains { finalURL.contains($0) }
    }

    private static func isLikelyImageResponse(finalURL: String, mimeType: String) -> Bool {
        if mimeType.hasPrefix("image/") { return true }
        let lower = finalURL.lowercased()
        return [".jpg", ".jpeg", ".png", ".webp", "douyinpic", "p3-sign", "tos-cn"]
            .contains { lower.contains($0) }
    }

    private static func imageExtension(finalURL: String, mimeType: String) -> String {
        if mimeType.contains("png") { return "png" }
        if mimeType.contains("webp") { return "webp" }
        if mimeType.contains("jpeg") || mimeType.contains("jpg") { return "jpg" }
        let lower = finalURL.lowercased()
        if lower.contains(".png") { return "png" }
        if lower.contains(".webp") { return "webp" }
        return "jpg"
    }

    private static func sanitizeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name
            .components(separatedBy: invalid)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return "douyin_\(Int(Date().timeIntervalSince1970))" }
        return String(cleaned.prefix(80))
    }

    private static func parseJSON(_ text: String?) -> Any? {
        guard let text, let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// JS blob that returns page-side extraction payload (mirrors Media-Downloader).
    private static let extractPageJS = """
    (function() {
      const mediaEntries = performance.getEntriesByType('resource')
        .map((item) => item.name)
        .filter((name) => ['video','playwm','/play/','mp4','m3u8','aweme','douyinvod','tos-cn','iteminfo','image','douyinpic'].some((token) => name.includes(token)));
      const scripts = Array.from(document.scripts)
        .map((s) => s.textContent || '')
        .filter((text) => ['aweme_detail','play_addr','bit_rate','playwm','video_id','iteminfo','_ROUTER_DATA','videoInfoRes','image_post_info','images'].some((token) => text.includes(token)))
        .slice(0, 8)
        .map((text) => text.slice(0, 12000));
      let routerDataJSON = null;
      let videoInfoResJSON = null;
      try {
        if (typeof window._ROUTER_DATA !== 'undefined') {
          routerDataJSON = JSON.stringify(window._ROUTER_DATA);
          const loaderValues = Object.values(window._ROUTER_DATA?.loaderData || {});
          const matched = loaderValues.find((item) => item?.videoInfoRes)?.videoInfoRes;
          if (matched) videoInfoResJSON = JSON.stringify(matched);
        }
      } catch (e) {}
      try {
        if (!videoInfoResJSON && typeof window.videoInfoRes !== 'undefined') {
          videoInfoResJSON = JSON.stringify(window.videoInfoRes);
        }
      } catch (e) {}
      return {
        pageURL: location.href,
        canonical: document.querySelector('link[rel="canonical"]')?.href || null,
        title: document.title || '',
        description: document.querySelector('meta[name="description"]')?.content || null,
        thumbnailURL: document.querySelector('meta[property="og:image"]')?.content
          || document.querySelector('meta[name="twitter:image"]')?.content
          || document.querySelector('video')?.poster
          || null,
        imageURLs: Array.from(document.images)
          .map((img) => img.currentSrc || img.src)
          .filter(Boolean)
          .slice(0, 80),
        videoSrc: document.querySelector('video')?.currentSrc || document.querySelector('video')?.src || null,
        apiDetailJSON: null,
        routerDataJSON,
        videoInfoResJSON,
        bodyTextPreview: document.body?.innerText?.slice(0, 600) || '',
        resourceHints: scripts,
        performanceMedia: mediaEntries
      };
    })()
    """
}

// MARK: - Models

struct DouyinExtractedInfo {
    var pageURL: String
    var canonical: String?
    var title: String
    var description: String?
    var thumbnailURL: String?
    var imageURLs: [String]
    var videoSrc: String?
    var apiDetailJSON: String?
    var routerDataJSON: String?
    var videoInfoResJSON: String?
    var bodyTextPreview: String
    var resourceHints: [String]
    var performanceMedia: [String]

    init(dict: [String: Any]) {
        pageURL = dict["pageURL"] as? String ?? ""
        canonical = dict["canonical"] as? String
        title = dict["title"] as? String ?? ""
        description = dict["description"] as? String
        thumbnailURL = dict["thumbnailURL"] as? String
        imageURLs = dict["imageURLs"] as? [String] ?? []
        videoSrc = dict["videoSrc"] as? String
        apiDetailJSON = dict["apiDetailJSON"] as? String
        routerDataJSON = dict["routerDataJSON"] as? String
        videoInfoResJSON = dict["videoInfoResJSON"] as? String
        bodyTextPreview = dict["bodyTextPreview"] as? String ?? ""
        resourceHints = dict["resourceHints"] as? [String] ?? []
        performanceMedia = dict["performanceMedia"] as? [String] ?? []
    }
}

struct DouyinDownloadCandidate {
    var label: String
    var url: String
    var headers: [String: String]
}

struct DouyinDownloadResult {
    enum MediaType: String {
        case video
        case image
    }

    var id: String
    var sourceURL: String
    var title: String
    var filePath: String
    var fileName: String
    var mediaType: MediaType
    var bytesWritten: Int64
    var finalURL: String
    var matchedCandidateLabel: String
    var thumbnailURL: String?
    var extraFilePaths: [String] = []

    var allFilePaths: [String] {
        [filePath] + extraFilePaths
    }
}

// MARK: - Navigation waiter

@MainActor
private final class DouyinWebNav: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var settled = false
    private var timeoutTask: Task<Void, Never>?

    func waitForLoad(timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await MainActor.run {
                    self?.finish(error: NetworkError.message("页面加载超时"))
                }
            }
        }
    }

    private func finish(error: Error?) {
        guard !settled else { return }
        settled = true
        timeoutTask?.cancel()
        timeoutTask = nil
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Give SPA a short settle window then complete.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            self.finish(error: nil)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // Redirect failures are common; only fail hard if never finished.
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled {
            return
        }
        // Soft-fail: still allow JS read after partial load.
        finish(error: nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled {
            return
        }
        finish(error: NetworkError.message("页面打开失败：\(error.localizedDescription)"))
    }
}
