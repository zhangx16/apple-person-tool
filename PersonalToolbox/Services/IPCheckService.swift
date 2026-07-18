import Foundation
import Network

/// Multi-source public IP check + heuristic VPN/proxy risk (IP检测.scripting).
actor IPCheckService {
    static let shared = IPCheckService()

    /// Prefer HTTPS sources for ATS.
    private let geoEndpoints: [(url: String, label: String)] = [
        ("https://ipwho.is/", "ipwho.is"),
        ("http://ip-api.com/json/?lang=zh-CN&fields=status,message,country,countryCode,regionName,city,isp,org,as,query", "ip-api"),
        ("https://ipapi.co/json/", "ipapi.co")
    ]

    private let compareEndpoints: [(url: String, label: String)] = [
        ("https://ip.3322.net", "3322"),
        ("https://api.ipify.org?format=json", "ipify"),
        ("https://checkip.amazonaws.com", "aws")
    ]

    func check() async -> (result: IPCheckResult?, error: String?) {
        let pathNote = await Self.currentPathDescription()
        let hasVPNPath = pathNote.lowercased().contains("vpn")
            || pathNote.lowercased().contains("tunnel")
            || pathNote.lowercased().contains("other")

        async let primaryTask = fetchPrimaryGeo()
        async let compareTask = fetchCompareIP()

        let (primary, primaryErr) = await primaryTask
        let (compareIP, compareLabel) = await compareTask

        guard var info = primary else {
            return (nil, primaryErr ?? "无法获取公网 IP")
        }

        var result = IPCheckAnalysis.calculateRisk(
            ipInfo: info,
            compareIP: compareIP,
            hasVPNInterface: hasVPNPath
        )
        result.compareIP = compareIP
        result.compareSource = compareLabel
        result.pathStatus = pathNote
        // Prefer showing primary query filled
        if info.query.isEmpty, let compareIP {
            info.query = compareIP
            result.primary = info
        }
        return (result, nil)
    }

    // MARK: - Geo sources

    private func fetchPrimaryGeo() async -> (IPGeoInfo?, String?) {
        var lastError: String?
        for ep in geoEndpoints {
            do {
                let info = try await fetchGeo(from: ep.url, label: ep.label)
                if !info.query.isEmpty { return (info, nil) }
            } catch {
                lastError = error.localizedDescription
            }
        }
        return (nil, lastError)
    }

    private func fetchGeo(from urlString: String, label: String) async throws -> IPGeoInfo {
        guard let url = URL(string: urlString) else { throw NetworkError.invalidURL }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        req.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NetworkError.message("\(label) HTTP 失败")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.message("\(label) 非 JSON")
        }
        // ip-api failure
        if let status = obj["status"] as? String, status == "fail" {
            throw NetworkError.message((obj["message"] as? String) ?? "ip-api 失败")
        }
        // ipwho.is
        if let success = obj["success"] as? Bool, success == false {
            throw NetworkError.message((obj["message"] as? String) ?? "ipwho 失败")
        }

        let query = string(obj, keys: ["query", "ip", "ipAddress"]) ?? ""
        let country = string(obj, keys: ["country", "country_name"]) ?? ""
        let countryCode = string(obj, keys: ["countryCode", "country_code"]) ?? ""
        let region = string(obj, keys: ["regionName", "region", "region_name"]) ?? ""
        let city = string(obj, keys: ["city"]) ?? ""
        var isp = string(obj, keys: ["isp", "org", "connection"]) ?? ""
        // ipwho nested connection
        if isp.isEmpty, let conn = obj["connection"] as? [String: Any] {
            isp = string(conn, keys: ["isp", "org"]) ?? ""
        }
        var org = string(obj, keys: ["org", "organization"]) ?? isp
        if org.isEmpty, let conn = obj["connection"] as? [String: Any] {
            org = string(conn, keys: ["org", "isp"]) ?? ""
        }
        let asInfo = string(obj, keys: ["as", "asn"]) ?? ""
        // ipapi.co uses "error"
        if let err = obj["error"] as? Bool, err == true {
            throw NetworkError.message((obj["reason"] as? String) ?? "ipapi 错误")
        }

        guard !query.isEmpty || !country.isEmpty else {
            throw NetworkError.message("\(label) 字段不完整")
        }
        return IPGeoInfo(
            query: query,
            country: country,
            countryCode: countryCode,
            regionName: region,
            city: city,
            isp: isp.isEmpty ? org : isp,
            org: org,
            asInfo: asInfo,
            sourceLabel: label
        )
    }

    private func string(_ obj: [String: Any], keys: [String]) -> String? {
        for k in keys {
            if let s = obj[k] as? String, !s.isEmpty { return s }
            if let n = obj[k] as? NSNumber { return n.stringValue }
        }
        return nil
    }

    // MARK: - Compare IP (second egress)

    private func fetchCompareIP() async -> (String?, String?) {
        for ep in compareEndpoints {
            if let ip = try? await fetchPlainOrJSONIP(urlString: ep.url) {
                if !IPCheckAnalysis.isPrivateIP(ip) {
                    return (ip, ep.label)
                }
            }
        }
        return (nil, nil)
    }

    private func fetchPlainOrJSONIP(urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw NetworkError.invalidURL }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NetworkError.message("compare fail")
        }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let ip = obj["ip"] as? String ?? obj["query"] as? String ?? obj["origin"] as? String {
                return ip.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let match = text.range(of: #"\d{1,3}(\.\d{1,3}){3}"#, options: .regularExpression) {
            return String(text[match])
        }
        throw NetworkError.message("no ip")
    }

    // MARK: - Path

    nonisolated private static func currentPathDescription() async -> String {
        await withCheckedContinuation { cont in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "ipcheck.path")
            let lock = NSLock()
            var finished = false
            let finish: (String) -> Void = { text in
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                monitor.cancel()
                cont.resume(returning: text)
            }
            monitor.pathUpdateHandler = { path in
                var parts: [String] = []
                if path.status == .satisfied {
                    parts.append("已联网")
                } else {
                    parts.append("无网络")
                }
                if path.usesInterfaceType(.wifi) { parts.append("Wi‑Fi") }
                if path.usesInterfaceType(.cellular) { parts.append("蜂窝") }
                if path.usesInterfaceType(.wiredEthernet) { parts.append("有线") }
                if path.usesInterfaceType(.other) { parts.append("其他/隧道") }
                if path.isExpensive { parts.append("计费网络") }
                if path.isConstrained { parts.append("受限") }
                finish(parts.joined(separator: " · "))
            }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 1.5) {
                finish("路径检测超时")
            }
        }
    }
}
