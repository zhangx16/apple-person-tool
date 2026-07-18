import Foundation

/// High-level in-app actions that tools / chat / clipboard can trigger.
enum AppDeepAction: String, Codable, CaseIterable, Identifiable, Hashable {
    case downloadYouTube
    case downloadDouyin
    case translate
    case scanQRHint
    case openClipboard
    case openRSS
    case openHabits
    case openTodos
    case openMarket
    case openExpress
    case openPassword
    case openHealth
    case openQuickActions
    case openSettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloadYouTube: return "YouTube 下载"
        case .downloadDouyin: return "抖音下载"
        case .translate: return "翻译"
        case .scanQRHint: return "二维码助手"
        case .openClipboard: return "剪贴板"
        case .openRSS: return "RSS 阅读"
        case .openHabits: return "习惯打卡"
        case .openTodos: return "待办"
        case .openMarket: return "行情"
        case .openExpress: return "快递查询"
        case .openPassword: return "密码生成"
        case .openHealth: return "服务健康"
        case .openQuickActions: return "快捷动作"
        case .openSettings: return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .downloadYouTube: return "play.rectangle.fill"
        case .downloadDouyin: return "music.note.tv.fill"
        case .translate: return "translate"
        case .scanQRHint: return "qrcode.viewfinder"
        case .openClipboard: return "doc.on.clipboard"
        case .openRSS: return "dot.radiowaves.up.forward"
        case .openHabits: return "checkmark.circle"
        case .openTodos: return "checklist"
        case .openMarket: return "chart.line.uptrend.xyaxis"
        case .openExpress: return "shippingbox"
        case .openPassword: return "key.fill"
        case .openHealth: return "heart.text.square"
        case .openQuickActions: return "bolt.horizontal.circle"
        case .openSettings: return "gearshape"
        }
    }
}

/// Payload carried when routing into a feature (e.g. prefilled URL).
struct AppActionPayload: Hashable {
    var action: AppDeepAction
    var text: String?
    var url: String?

    init(action: AppDeepAction, text: String? = nil, url: String? = nil) {
        self.action = action
        self.text = text
        self.url = url
    }
}

/// Detects actionable content from free text / clipboard / chat.
enum ActionRouter {
    static func extractFirstURL(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http") {
            return trimmed.components(separatedBy: .whitespacesAndNewlines).first
        }
        let pattern = #"https?://[^\s<>"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range),
              let r = Range(match.range, in: trimmed) else { return nil }
        var url = String(trimmed[r])
        while let last = url.last, ".,);]》」』".contains(last) { url.removeLast() }
        return url
    }

    static func extractVerificationCode(from text: String) -> String? {
        // 4–8 digit codes not looking like phone numbers
        let pattern = #"(?<!\d)(\d{4,8})(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        for m in matches where m.numberOfRanges > 1 {
            if let r = Range(m.range(at: 1), in: text) {
                let code = String(text[r])
                if code.count <= 6 || text.contains("验证码") || text.lowercased().contains("code") {
                    return code
                }
            }
        }
        return nil
    }

    static func extractTrackingNumber(from text: String) -> String? {
        // Common CN express patterns (simplified)
        let patterns = [
            #"(?:SF|YT|YD|ZT|STO|YTO|ZTO|JT|JD|EMS)[A-Z0-9]{10,}"#,
            #"(?<![A-Z0-9])([A-Z]{2}\d{9}[A-Z]{2})(?![A-Z0-9])"#,
            #"(?<!\d)(\d{10,15})(?!\d)"#
        ]
        for p in patterns {
            guard let regex = try? NSRegularExpression(pattern: p, options: .caseInsensitive) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let m = regex.firstMatch(in: text, range: range),
               let r = Range(m.range, in: text) {
                return String(text[r]).uppercased()
            }
        }
        return nil
    }

    /// Ranked suggestions for a blob of text.
    static func suggest(from text: String) -> [AppActionPayload] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return [] }
        var out: [AppActionPayload] = []
        if let url = extractFirstURL(from: t) {
            if isDouyinURL(url) {
                out.append(.init(action: .downloadDouyin, text: t, url: url))
            } else {
                out.append(.init(action: .downloadYouTube, text: t, url: url))
            }
            out.append(.init(action: .translate, text: t, url: url))
            out.append(.init(action: .openRSS, text: t, url: url))
        } else if t.count >= 2 {
            out.append(.init(action: .translate, text: t))
        }
        if extractTrackingNumber(from: t) != nil {
            out.append(.init(action: .openExpress, text: t, url: extractTrackingNumber(from: t)))
        }
        if extractVerificationCode(from: t) != nil {
            // just informational — copy handled in UI
        }
        return out
    }

    /// Chat natural language → action (keyword heuristics, no LLM required).
    static func parseChatCommand(_ text: String) -> AppActionPayload? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = t.lowercased()
        if let url = extractFirstURL(from: t) {
            if lower.contains("下载") || lower.contains("download") {
                if DouyinService.isDouyinURL(url) {
                    return .init(action: .downloadDouyin, text: t, url: url)
                }
                return .init(action: .downloadYouTube, text: t, url: url)
            }
            if lower.contains("翻译") || lower.contains("translate") {
                return .init(action: .translate, text: t, url: url)
            }
        }
        if lower.contains("翻译") {
            let stripped = t.replacingOccurrences(of: "翻译", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !stripped.isEmpty {
                return .init(action: .translate, text: stripped)
            }
        }
        if lower.contains("快递") || lower.contains("查件") {
            return .init(action: .openExpress, text: t, url: extractTrackingNumber(from: t))
        }
        if lower.contains("油价") || lower.contains("汇率") || lower.contains("金价") {
            return .init(action: .openMarket, text: t)
        }
        if lower.contains("打卡") || lower.contains("习惯") {
            return .init(action: .openHabits, text: t)
        }
        if lower.contains("待办") || lower.contains("todo") {
            return .init(action: .openTodos, text: t)
        }
        if lower.contains("密码") && (lower.contains("生成") || lower.contains("随机")) {
            return .init(action: .openPassword, text: t)
        }
        if lower.contains("健康") || lower.contains("探测") || lower.contains("服务状态") {
            return .init(action: .openHealth, text: t)
        }
        return suggest(from: t).first
    }
}
