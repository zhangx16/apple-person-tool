import Foundation

struct YTTask: Identifiable, Hashable {
    let id: String
    var url: String
    var title: String
    var status: String
    var progress: Double
    var speed: String
    var eta: String
    var filepath: String?
    var error: String?

    var isActive: Bool {
        let s = status.lowercased()
        return s.contains("run") || s.contains("pend") || s.contains("download") || s.contains("queue") || s == "pending" || s == "downloading" || s.contains("process")
    }

    var isCompleted: Bool {
        let s = status.lowercased()
        return s.contains("complete") || s.contains("done") || s == "finished" || (filepath != nil && progress >= 0.999)
    }
}

struct YTFormatOption: Identifiable, Hashable {
    let id: String
    let label: String
    /// yt-dlp -f format string
    let format: String

    static let presets: [YTFormatOption] = [
        .init(id: "best", label: "最佳", format: "bv*+ba/b"),
        .init(id: "4k", label: "4K", format: "bv*[height<=2160]+ba/b[height<=2160]"),
        .init(id: "1080", label: "1080P", format: "bv*[height<=1080]+ba/b[height<=1080]"),
        .init(id: "720", label: "720P", format: "bv*[height<=720]+ba/b[height<=720]"),
        .init(id: "480", label: "480P", format: "bv*[height<=480]+ba/b[height<=480]")
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
