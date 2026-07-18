import Foundation
import JavaScriptCore

/// Thin JavaScriptCore host for SimpleLive sign scripts (Douyu / Douyin a_bogus).
final class LiveJSEngine: @unchecked Sendable {
    static let shared = LiveJSEngine()

    private let queue = DispatchQueue(label: "com.xinstool.live.js")
    private var cryptoJS: String?
    private var abogusJS: String?
    private var webmssdkJS: String?

    private init() {}

    func douyuSign(encryptedJS: String, roomId: String) throws -> String {
        try queue.sync {
            let crypto = try loadResource("cryptojs", ext: "js", cached: &cryptoJS)
            guard let ctx = JSContext() else {
                throw NetworkError.message("JavaScriptCore 不可用")
            }
            ctx.exceptionHandler = { _, exc in
                // swallow intermediate; final check below
                _ = exc
            }
            ctx.evaluateScript(crypto)
            ctx.evaluateScript(encryptedJS)
            let did = "10000000000000000000000000001501"
            let time = Int(Date().timeIntervalSince1970)
            let result = ctx.evaluateScript("ub98484234('\(roomId)','\(did)','\(time)')")
            if let exc = ctx.exception {
                throw NetworkError.message("斗鱼签名 JS 异常: \(exc)")
            }
            guard let s = result?.toString(), !s.isEmpty, s != "undefined" else {
                throw NetworkError.message("斗鱼签名失败")
            }
            return s
        }
    }

    func douyinAbogusURL(url: String, userAgent: String) throws -> String {
        try queue.sync {
            let script = try loadResource("abogus", ext: "js", cached: &abogusJS)
            guard let ctx = JSContext() else {
                throw NetworkError.message("JavaScriptCore 不可用")
            }
            ctx.exceptionHandler = { _, _ in }
            ctx.evaluateScript(script)
            let msToken = Self.randomMsToken(107)
            // Sign query = original query + msToken (SimpleLive getAbogusUrl)
            let baseWithToken: String
            if url.contains("?") {
                baseWithToken = url + (url.hasSuffix("&") || url.hasSuffix("?") ? "" : "&") + "msToken=\(msToken)"
            } else {
                baseWithToken = url + "?msToken=\(msToken)"
            }
            let query: String
            if let qIndex = baseWithToken.firstIndex(of: "?") {
                query = String(baseWithToken[baseWithToken.index(after: qIndex)...])
            } else {
                query = ""
            }
            let qEsc = query
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let uaEsc = userAgent
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let ab = ctx.evaluateScript("getABogus('\(qEsc)', '\(uaEsc)')")?.toString() ?? ""
            if let exc = ctx.exception {
                throw NetworkError.message("抖音 a_bogus 异常: \(exc)")
            }
            guard !ab.isEmpty, ab != "undefined" else {
                throw NetworkError.message("抖音 a_bogus 生成失败")
            }
            let encToken = msToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? msToken
            let encAb = ab.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ab
            // Rebuild: original url + encoded msToken + a_bogus
            // Drop empty msToken= if present in original
            var cleaned = url.replacingOccurrences(of: "msToken=&", with: "").replacingOccurrences(of: "&msToken=", with: "")
            if cleaned.hasSuffix("msToken=") {
                cleaned = String(cleaned.dropLast("msToken=".count))
                if cleaned.hasSuffix("?") || cleaned.hasSuffix("&") {
                    cleaned = String(cleaned.dropLast())
                }
            }
            let join = cleaned.contains("?") ? "&" : "?"
            return "\(cleaned)\(join)msToken=\(encToken)&a_bogus=\(encAb)"
        }
    }

    /// Douyin webcast WS signature (SimpleLive DouyinSign.getSignature).
    func douyinMSSDKSignature(roomId: String, userUniqueId: String) throws -> String {
        try queue.sync {
            let script = try loadResource("webmssdk", ext: "js", cached: &webmssdkJS)
            guard let ctx = JSContext() else {
                throw NetworkError.message("JavaScriptCore 不可用")
            }
            ctx.exceptionHandler = { _, _ in }
            // Provide minimal browser stubs for the SDK
            ctx.evaluateScript("""
            var document = document || {};
            var window = window || {};
            var navigator = navigator || { userAgent: '' };
            """)
            ctx.evaluateScript(script)
            let ua =
                "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.5845.97 Safari/537.36 Core/1.116.567.400 QQBrowser/19.7.6764.400"
            // msStub = md5 of ordered params string (SimpleLive)
            let params = [
                "live_id=1",
                "aid=6383",
                "version_code=180800",
                "webcast_sdk_version=1.3.0",
                "room_id=\(roomId)",
                "sub_room_id=",
                "sub_channel_id=",
                "did_rule=3",
                "user_unique_id=\(userUniqueId)",
                "device_platform=web",
                "device_type=",
                "ac=",
                "identity=audience"
            ].joined(separator: ",")
            let msStub = LiveCryptoMD5.hex(params)
            let uaEsc = ua.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
            var signature = ctx.evaluateScript("getMSSDKSignature('\(msStub)', '\(uaEsc)')")?.toString() ?? ""
            var attempts = 0
            while (signature.contains("-") || signature.contains("=") || signature.isEmpty || signature == "undefined"),
                  attempts < 5 {
                signature = ctx.evaluateScript("getMSSDKSignature('\(msStub)', '\(uaEsc)')")?.toString() ?? ""
                attempts += 1
            }
            if let exc = ctx.exception {
                throw NetworkError.message("抖音签名 JS 异常: \(exc)")
            }
            guard !signature.isEmpty, signature != "undefined" else {
                throw NetworkError.message("抖音弹幕签名失败")
            }
            return signature
        }
    }

    private func loadResource(_ name: String, ext: String, cached: inout String?) throws -> String {
        if let cached { return cached }
        // Prefer bundle Resources/LiveJS/
        let url =
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "LiveJS")
            ?? Bundle.main.url(forResource: name, withExtension: ext)
        guard let url,
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.isEmpty else {
            throw NetworkError.message("缺少 LiveJS/\(name).\(ext)")
        }
        cached = text
        return text
    }

    private static func randomMsToken(_ length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return String((0..<length).map { _ in chars.randomElement()! })
    }
}
