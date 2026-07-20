import Foundation

/// Download queue task, aligned with yt-dlp-web-ui nested `info`/`progress`/`output`.
struct YTTask: Identifiable, Hashable {
    let id: String
    var url: String
    var title: String
    /// Free-text label for UI (e.g. 等待中 / 下载中 / 已完成 / 失败).
    var status: String
    /// Authoritative backend code: 0 pending, 1 running, 2 completed, 3 failed.
    var processStatus: Int
    /// Raw percentage string from backend, e.g. `"45.2%"` or `"-1"` (complete).
    var percentageRaw: String
    /// Normalized 0...1 progress for ProgressView.
    var progress: Double
    var speed: String
    var eta: String
    var filepath: String?
    var error: String?
    var thumbnail: String?

    /// Pending or running.
    var isActive: Bool {
        processStatus == 0 || processStatus == 1
    }

    /// Completed (status 2 or percentage sentinel `-1`).
    var isCompleted: Bool {
        processStatus == 2 || percentageRaw == "-1"
    }

    var isFailed: Bool {
        processStatus == 3
    }

    /// 0...1 progress; completed → 1.
    var progress01: Double {
        if percentageRaw == "-1" || processStatus == 2 { return 1 }
        return progress
    }

    var statusLabel: String {
        switch processStatus {
        case 0: return "等待中"
        case 1: return "下载中"
        case 2: return "已完成"
        case 3: return "失败"
        case 4: return "直播"
        default: return status.isEmpty ? "未知" : status
        }
    }

    var progressPercentText: String {
        if isCompleted { return "100%" }
        if isFailed { return "" }
        let pct = Int((progress01 * 100).rounded())
        return "\(pct)%"
    }
}

struct YTFormatOption: Identifiable, Hashable {
    let id: String
    let label: String
    /// yt-dlp `-f` format string — copied from frontend `qualityFormats`.
    let format: String

    /// Production frontend presets (`/root/yt-dlp-web-ui/frontend/app.js` `qualityFormats`).
    static let presets: [YTFormatOption] = [
        .init(
            id: "best",
            label: "最佳",
            format: "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b"
        ),
        .init(
            id: "4k",
            label: "4K",
            format: "bv*[height<=2160][ext=mp4]+ba[ext=m4a]/b[height<=2160][ext=mp4]/bv*[height<=2160]+ba/b[height<=2160]"
        ),
        .init(
            id: "1080",
            label: "1080P",
            format: "bv*[height<=1080][ext=mp4]+ba[ext=m4a]/b[height<=1080][ext=mp4]/bv*[height<=1080]+ba/b[height<=1080]"
        ),
        .init(
            id: "720",
            label: "720P",
            format: "bv*[height<=720][ext=mp4]+ba[ext=m4a]/b[height<=720][ext=mp4]/bv*[height<=720]+ba/b[height<=720]"
        ),
        .init(
            id: "480",
            label: "480P",
            format: "bv*[height<=480][ext=mp4]+ba[ext=m4a]/b[height<=480][ext=mp4]/bv*[height<=480]+ba/b[height<=480]"
        )
    ]
}

struct YTFileItem: Identifiable, Hashable {
    let id: String
    let name: String
    let size: Int64?
    let path: String

    var sizeText: String {
        guard let size, size > 0 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

struct VideoMetadata: Hashable {
    var title: String
    var duration: String?
    var thumbnail: String?
    var uploader: String?
}

// MARK: - Local media helpers (Douyin)

extension YTTask {
    /// Local Douyin task id prefix.
    static let localDouyinPrefix = "local-douyin-"
    static let localBilibiliPrefix = "local-bili-"

    var isLocalDouyin: Bool {
        id.hasPrefix(Self.localDouyinPrefix)
    }

    var isLocalBilibili: Bool {
        id.hasPrefix(Self.localBilibiliPrefix)
    }

    var isLocalDownload: Bool {
        isLocalDouyin || isLocalBilibili
    }

    static func makeLocalDouyin(
        id: String = UUID().uuidString,
        url: String,
        title: String,
        processStatus: Int,
        progress: Double,
        stage: String,
        filepath: String? = nil,
        error: String? = nil
    ) -> YTTask {
        YTTask(
            id: localDouyinPrefix + id,
            url: url,
            title: title.isEmpty ? url : title,
            status: stage,
            processStatus: processStatus,
            percentageRaw: processStatus == 2 ? "-1" : String(format: "%.1f%%", progress * 100),
            progress: progress,
            speed: "",
            eta: "",
            filepath: filepath,
            error: error,
            thumbnail: nil
        )
    }

    static func makeLocalBilibili(
        id: String = UUID().uuidString,
        url: String,
        title: String,
        processStatus: Int,
        progress: Double,
        stage: String,
        filepath: String? = nil,
        error: String? = nil
    ) -> YTTask {
        YTTask(
            id: localBilibiliPrefix + id,
            url: url,
            title: title.isEmpty ? url : title,
            status: stage,
            processStatus: processStatus,
            percentageRaw: processStatus == 2 ? "-1" : String(format: "%.1f%%", progress * 100),
            progress: progress,
            speed: "",
            eta: "",
            filepath: filepath,
            error: error,
            thumbnail: nil
        )
    }
}

extension YTFileItem {
    var isLocalFile: Bool {
        id.hasPrefix("local:") || (path.hasPrefix("/") && FileManager.default.fileExists(atPath: path))
    }
}
