import Foundation
import Network

/// 出口 IP 检测 · 对齐 MaYIHEI/paperclip `ipquality`（Loon 脚本）口径。
/// 在 iOS 上检测当前 App 出口（非 Loon 节点），聚合 check.place / ipapi.is 等公开源 + 流媒体探测。
actor IPCheckService {
    static let shared = IPCheckService()

    private let ua =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1"
    private let backend = "https://ipinfo.check.place"

    // MARK: - Public

    func check(includeMedia: Bool = true) async -> (result: IPCheckResult?, error: String?) {
        let pathNote = await Self.currentPathDescription()
        let hasVPNPath = pathNote.lowercased().contains("vpn")
            || pathNote.lowercased().contains("tunnel")
            || pathNote.lowercased().contains("other")

        // 1) Discover egress IP (multi-probe consensus, like ipquality.js)
        let discovery = await discoverIP()
        guard let ip = discovery.ip, !ip.isEmpty else {
            return (nil, "无法获取出口 IP")
        }

        // 2) Parallel DB + media
        async let dbTask = collectDatabases(ip: ip)
        async let mediaTask: [IPMediaRow] = includeMedia ? collectMedia() : []
        let dbs = await dbTask
        let media = await mediaTask

        // 3) Build geo profile
        let geo = buildGeo(ip: ip, dbs: dbs)

        // 4) Legacy heuristic (keep as summary score)
        var result = IPCheckAnalysis.calculateRisk(
            ipInfo: geo,
            compareIP: discovery.secondaryIP,
            hasVPNInterface: hasVPNPath
        )
        result.primary = geo
        result.compareIP = discovery.secondaryIP
        result.compareSource = discovery.secondarySource
        result.pathStatus = pathNote
        result.probeMatched = discovery.matched
        result.probeTotal = discovery.total
        result.typeRows = buildTypes(dbs)
        result.riskRows = buildRisks(dbs)
        result.factorRows = buildFactors(dbs)
        result.mediaRows = media
        result.qualityNote =
            "类型与风险分档对齐 xykt/IPQuality · MaYIHEI/ipquality 展示口径；各库独立展示，不合成单一结论。缺失数据不参与判断。"

        // Refine 原生/家宽 using quality factors when available
        if let native = geo.nature.nilIfEmpty {
            result.isNative = native.contains("原生") ? "原生" : "非原生"
        }
        if result.typeRows.contains(where: { $0.usage.lowercased().contains("isp") || $0.company.lowercased().contains("isp") }) {
            // leave as-is
        }
        if dbs.ipapi?.isDatacenter == true {
            result.isHomeBroadband = "非家宽"
        }

        return (result, nil)
    }

    // MARK: - Discover IP

    private struct Discovery {
        var ip: String?
        var secondaryIP: String?
        var secondarySource: String?
        var matched: Int
        var total: Int
    }

    private func discoverIP() async -> Discovery {
        struct Probe {
            let name: String
            let task: () async throws -> String
        }
        let probes: [Probe] = [
            Probe(name: "check.place", task: { [self] in
                let text = try await requestText("\(backend)/cdn-cgi/trace")
                return cloudflareTraceIP(text)
            }),
            Probe(name: "myip.check.place", task: { [self] in
                try await requestText("https://myip.check.place").trimmingCharacters(in: .whitespacesAndNewlines)
            }),
            Probe(name: "ipify", task: { [self] in
                let obj = try await requestJSON("https://api4.ipify.org?format=json")
                return string(obj, keys: ["ip"]) ?? ""
            }),
            Probe(name: "ident.me", task: { [self] in
                try await requestText("https://v4.ident.me/").trimmingCharacters(in: .whitespacesAndNewlines)
            }),
            Probe(name: "icanhazip", task: { [self] in
                try await requestText("https://ipv4.icanhazip.com/").trimmingCharacters(in: .whitespacesAndNewlines)
            }),
            Probe(name: "ip-api", task: { [self] in
                let obj = try await requestJSON("http://ip-api.com/json/?fields=status,message,query")
                return string(obj, keys: ["query"]) ?? ""
            })
        ]

        var counts: [String: Int] = [:]
        var sources: [String: String] = [:]
        var total = 0
        await withTaskGroup(of: (String, String)?.self) { group in
            for p in probes {
                group.addTask {
                    do {
                        let ip = try await p.task()
                        let n = Self.normalizeIP(ip)
                        guard !n.isEmpty, !IPCheckAnalysis.isPrivateIP(n) else { return nil }
                        return (p.name, n)
                    } catch {
                        return nil
                    }
                }
            }
            for await item in group {
                guard let (name, ip) = item else { continue }
                total += 1
                counts[ip, default: 0] += 1
                if sources[ip] == nil { sources[ip] = name }
            }
        }

        guard !counts.isEmpty else {
            return Discovery(ip: nil, secondaryIP: nil, secondarySource: nil, matched: 0, total: 0)
        }
        let ranked = counts.keys.sorted { a, b in
            let d = counts[b, default: 0] - counts[a, default: 0]
            if d != 0 { return d > 0 }
            return a < b
        }
        let primary = ranked[0]
        let secondary = ranked.count > 1 ? ranked[1] : nil
        return Discovery(
            ip: primary,
            secondaryIP: secondary,
            secondarySource: secondary.flatMap { sources[$0] },
            matched: counts[primary, default: 0],
            total: total
        )
    }

    // MARK: - Databases

    private struct DBBundle {
        var maxmind: [String: Any]?
        var ipapi: IPAPIIS?
        var ipwhois: [String: Any]?
        var ip2: [String: Any]?
        var abuse: [String: Any]?
        var ipqs: [String: Any]?
        var scamalytics: [String: Any]?
        var proxycheck: [String: Any]?
        var ipdata: [String: Any]?
        var ipApiCom: [String: Any]?
    }

    private struct IPAPIIS {
        var ip: String
        var isVPN: Bool
        var isProxy: Bool
        var isTor: Bool
        var isDatacenter: Bool
        var isAbuser: Bool
        var isCrawler: Bool
        var asnType: String
        var companyType: String
        var abuserScore: String
        var countryCode: String
        var country: String
        var region: String
        var city: String
        var org: String
        var asn: String
        var route: String
        var lat: Double?
        var lon: Double?
        var timezone: String
    }

    private func collectDatabases(ip: String) async -> DBBundle {
        let enc = ip.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ip
        async let mm = optionalJSON("\(backend)/\(enc)?lang=cn")
        async let ipapi = optionalIPAPIIS(ip)
        async let whois = optionalJSON("https://ipwho.is/\(enc)")
        async let ip2 = optionalJSON("\(backend)/\(enc)?db=ip2location")
        async let abuse = optionalJSON("\(backend)/\(enc)?db=abuseipdb")
        async let ipqs = optionalJSON("\(backend)/\(enc)?db=ipqualityscore")
        async let scam = optionalJSON("\(backend)/\(enc)?db=scamalytics")
        async let pc = optionalJSON("https://proxycheck.io/v2/\(enc)?vpn=1&asn=1&risk=1")
        async let ipdata = optionalJSON("\(backend)/\(enc)?db=ipdata")
        async let ipApiCom = optionalJSON(
            "http://ip-api.com/json/\(enc)?fields=status,message,country,countryCode,regionName,city,lat,lon,timezone,isp,org,as,asname,mobile,proxy,hosting,query&lang=zh-CN"
        )
        return await DBBundle(
            maxmind: mm,
            ipapi: ipapi,
            ipwhois: whois,
            ip2: ip2,
            abuse: abuse,
            ipqs: ipqs,
            scamalytics: scam,
            proxycheck: pc,
            ipdata: ipdata,
            ipApiCom: ipApiCom
        )
    }

    private func optionalJSON(_ url: String) async -> [String: Any]? {
        try? await requestJSON(url)
    }

    private func optionalIPAPIIS(_ ip: String) async -> IPAPIIS? {
        let enc = ip.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ip
        guard let obj = try? await requestJSON("https://api.ipapi.is/?q=\(enc)") else { return nil }
        let asn = obj["asn"] as? [String: Any] ?? [:]
        let company = obj["company"] as? [String: Any] ?? [:]
        let loc = obj["location"] as? [String: Any] ?? [:]
        return IPAPIIS(
            ip: string(obj, keys: ["ip"]) ?? ip,
            isVPN: bool(obj, "is_vpn"),
            isProxy: bool(obj, "is_proxy"),
            isTor: bool(obj, "is_tor"),
            isDatacenter: bool(obj, "is_datacenter"),
            isAbuser: bool(obj, "is_abuser"),
            isCrawler: bool(obj, "is_crawler"),
            asnType: string(asn, keys: ["type"]) ?? "",
            companyType: string(company, keys: ["type"]) ?? "",
            abuserScore: string(company, keys: ["abuser_score"]) ?? string(asn, keys: ["abuser_score"]) ?? "",
            countryCode: string(loc, keys: ["country_code"]) ?? "",
            country: string(loc, keys: ["country"]) ?? "",
            region: string(loc, keys: ["state"]) ?? "",
            city: string(loc, keys: ["city"]) ?? "",
            org: string(asn, keys: ["org", "descr"]) ?? string(company, keys: ["name"]) ?? "",
            asn: string(asn, keys: ["asn"]) ?? "",
            route: string(asn, keys: ["route"]) ?? "",
            lat: double(loc, "latitude"),
            lon: double(loc, "longitude"),
            timezone: string(loc, keys: ["timezone"]) ?? ""
        )
    }

    // MARK: - Build geo / types / risks / factors

    private func buildGeo(ip: String, dbs: DBBundle) -> IPGeoInfo {
        // Prefer MaxMind (check.place), then ipapi.is, ip-api, ipwho
        let mm = dbs.maxmind ?? [:]
        let city = mm["City"] as? [String: Any] ?? [:]
        let country = mm["Country"] as? [String: Any] ?? [:]
        let asn = mm["ASN"] as? [String: Any] ?? [:]
        let mmCountry = country["IsoCode"] as? String
            ?? (city["Country"] as? [String: Any])?["IsoCode"] as? String
            ?? ""
        let mmCountryName = country["Name"] as? String
            ?? (city["Country"] as? [String: Any])?["Name"] as? String
            ?? ""
        let reg = country["RegisteredCountry"] as? [String: Any] ?? [:]
        let regCode = string(reg, keys: ["IsoCode"]) ?? ""
        let regName = string(reg, keys: ["Name"]) ?? ""

        var code = mmCountry
        var cname = mmCountryName
        var region = ""
        if let subs = city["Subdivisions"] as? [[String: Any]], let first = subs.first {
            region = string(first, keys: ["Name"]) ?? ""
        }
        var cityName = string(city, keys: ["Name"]) ?? ""
        var org = string(asn, keys: ["AutonomousSystemOrganization"]) ?? ""
        var asInfo = ""
        if let n = asn["AutonomousSystemNumber"] as? Int {
            asInfo = "AS\(n)"
        } else if let s = string(asn, keys: ["AutonomousSystemNumber"]), !s.isEmpty {
            asInfo = s.hasPrefix("AS") ? s : "AS\(s)"
        }
        var lat = double(city, "Latitude")
        var lon = double(city, "Longitude")
        var tz = string(city["Location"] as? [String: Any] ?? [:], keys: ["TimeZone"]) ?? ""
        var route = string(asn, keys: ["Network"]) ?? ""
        var source = mm.isEmpty ? "" : "MaxMind"

        if code.isEmpty, let api = dbs.ipapi {
            code = api.countryCode
            cname = api.country
            region = api.region
            cityName = api.city
            org = api.org.isEmpty ? org : api.org
            if asInfo.isEmpty, !api.asn.isEmpty {
                asInfo = api.asn.hasPrefix("AS") ? api.asn : "AS\(api.asn)"
            }
            lat = api.lat ?? lat
            lon = api.lon ?? lon
            tz = api.timezone.isEmpty ? tz : api.timezone
            route = api.route.isEmpty ? route : api.route
            source = source.isEmpty ? "ipapi" : source + " · ipapi"
        }

        if code.isEmpty, let com = dbs.ipApiCom, string(com, keys: ["status"]) != "fail" {
            code = string(com, keys: ["countryCode"]) ?? code
            cname = string(com, keys: ["country"]) ?? cname
            region = string(com, keys: ["regionName"]) ?? region
            cityName = string(com, keys: ["city"]) ?? cityName
            let isp = string(com, keys: ["isp"]) ?? ""
            org = org.isEmpty ? (string(com, keys: ["org", "asname"]) ?? isp) : org
            asInfo = asInfo.isEmpty ? (string(com, keys: ["as"]) ?? "") : asInfo
            lat = double(com, "lat") ?? lat
            lon = double(com, "lon") ?? lon
            tz = string(com, keys: ["timezone"]) ?? tz
            source = source.isEmpty ? "ip-api" : source
        }

        if code.isEmpty, let who = dbs.ipwhois, bool(who, "success") != false {
            code = string(who, keys: ["country_code"]) ?? code
            cname = string(who, keys: ["country"]) ?? cname
            region = string(who, keys: ["region"]) ?? region
            cityName = string(who, keys: ["city"]) ?? cityName
            let conn = who["connection"] as? [String: Any] ?? [:]
            org = org.isEmpty ? (string(conn, keys: ["org", "isp"]) ?? "") : org
            if asInfo.isEmpty, let a = conn["asn"] as? Int { asInfo = "AS\(a)" }
            lat = double(who, "latitude") ?? lat
            lon = double(who, "longitude") ?? lon
            source = source.isEmpty ? "ipwhois" : source
        }

        var nature = ""
        if !code.isEmpty, !regCode.isEmpty {
            nature = code.uppercased() == regCode.uppercased() ? "原生 IP" : "广播 IP"
        }

        let registered = regCode.isEmpty
            ? ""
            : "[\(regCode.uppercased())] \(regName)".trimmingCharacters(in: .whitespaces)

        return IPGeoInfo(
            query: ip,
            country: cname,
            countryCode: code,
            regionName: region,
            city: cityName,
            isp: org,
            org: org,
            asInfo: asInfo,
            sourceLabel: source.isEmpty ? "多源" : source,
            latitude: lat,
            longitude: lon,
            timezone: tz,
            route: route,
            nature: nature,
            registeredRegion: registered
        )
    }

    private func buildTypes(_ dbs: DBBundle) -> [IPTypeRow] {
        var rows: [IPTypeRow] = []
        if let api = dbs.ipapi {
            let u = translateType(api.asnType)
            let c = translateType(api.companyType)
            if !u.isEmpty || !c.isEmpty {
                rows.append(IPTypeRow(name: "ipapi", usage: u, company: c))
            }
        }
        if let ip2 = dbs.ip2 {
            let u = translateType(string(ip2, keys: ["usage_type"]) ?? "")
            let asInfo = ip2["as_info"] as? [String: Any] ?? [:]
            let c = translateType(string(asInfo, keys: ["as_usage_type"]) ?? "")
            if !u.isEmpty || !c.isEmpty {
                rows.append(IPTypeRow(name: "IP2Location", usage: u, company: c))
            }
        }
        if let abuse = dbs.abuse?["data"] as? [String: Any] {
            let u = translateType(string(abuse, keys: ["usageType"]) ?? "")
            if !u.isEmpty {
                rows.append(IPTypeRow(name: "AbuseIPDB", usage: u, company: ""))
            }
        }
        if let com = dbs.ipApiCom, bool(com, "hosting") || bool(com, "proxy") || bool(com, "mobile") {
            var parts: [String] = []
            if bool(com, "hosting") { parts.append("机房") }
            if bool(com, "proxy") { parts.append("代理") }
            if bool(com, "mobile") { parts.append("移动") }
            if !parts.isEmpty {
                rows.append(IPTypeRow(name: "ip-api", usage: parts.joined(separator: " · "), company: ""))
            }
        }
        return rows
    }

    private func buildRisks(_ dbs: DBBundle) -> [IPRiskRow] {
        var rows: [IPRiskRow] = []

        // ipapi abuser_score "0.0044 (Low)"
        if let api = dbs.ipapi, !api.abuserScore.isEmpty {
            let (sev, label, detail) = parseIpapiScore(api.abuserScore)
            rows.append(IPRiskRow(name: "ipapi", available: true, severity: sev, label: label, detail: detail))
        }

        // IPQS fraud_score
        if let ipqs = dbs.ipqs, bool(ipqs, "success") != false {
            if let score = number(ipqs, "fraud_score") {
                let (sev, label) = scoreBand(score, bands: [(90, 4, "高风险"), (85, 3, "存在风险"), (75, 2, "可疑"), (0, 0, "低风险")])
                rows.append(IPRiskRow(name: "IPQS", available: true, severity: sev, label: label, detail: "\(Int(score))"))
            }
        }

        // Scamalytics
        if let root = dbs.scamalytics, let scam = root["scamalytics"] as? [String: Any] {
            if let score = number(scam, "scamalytics_score") {
                let (sev, label) = scoreBand(score, bands: [(90, 4, "极高风险"), (60, 3, "高风险"), (20, 2, "中风险"), (0, 0, "低风险")])
                rows.append(IPRiskRow(name: "Scamalytics", available: true, severity: sev, label: label, detail: "\(Int(score))"))
            }
        }

        // AbuseIPDB
        if let data = dbs.abuse?["data"] as? [String: Any], let score = number(data, "abuseConfidenceScore") {
            let (sev, label) = scoreBand(score, bands: [(75, 4, "建议封禁"), (25, 3, "高风险"), (0, 0, "低风险")])
            rows.append(IPRiskRow(name: "AbuseIPDB", available: true, severity: sev, label: label, detail: "\(Int(score))%"))
        }

        // IP2Location fraud if present
        if let ip2 = dbs.ip2, let score = number(ip2, "fraud_score") {
            let (sev, label) = scoreBand(score, bands: [(66, 3, "高风险"), (33, 2, "中风险"), (0, 0, "低风险")])
            rows.append(IPRiskRow(name: "IP2Location", available: true, severity: sev, label: label, detail: "\(Int(score))"))
        }

        // proxycheck risk
        if let pc = proxycheckRecord(dbs.proxycheck), let risk = number(pc, "risk") {
            let (sev, label) = scoreBand(risk, bands: [(66, 3, "高风险"), (33, 2, "中风险"), (0, 0, "低风险")])
            rows.append(IPRiskRow(name: "proxycheck", available: true, severity: sev, label: label, detail: "\(Int(risk))"))
        }

        return rows
    }

    private func buildFactors(_ dbs: DBBundle) -> [IPFactorRow] {
        var rows: [IPFactorRow] = []
        if let api = dbs.ipapi {
            rows.append(IPFactorRow(
                name: "ipapi",
                country: api.countryCode.uppercased(),
                checks: [
                    ("VPN", yn(api.isVPN)),
                    ("代理", yn(api.isProxy)),
                    ("Tor", yn(api.isTor)),
                    ("机房", yn(api.isDatacenter)),
                    ("滥用", yn(api.isAbuser)),
                    ("爬虫", yn(api.isCrawler))
                ]
            ))
        }
        if let ip2 = dbs.ip2 {
            let proxy = ip2["proxy"] as? [String: Any] ?? [:]
            rows.append(IPFactorRow(
                name: "IP2Location",
                country: (string(ip2, keys: ["country_code"]) ?? "").uppercased(),
                checks: [
                    ("代理", yn(bool(ip2, "is_proxy") || bool(proxy, "is_public_proxy"))),
                    ("Tor", yn(bool(proxy, "is_tor"))),
                    ("VPN", yn(bool(proxy, "is_vpn"))),
                    ("机房", yn(bool(proxy, "is_data_center")))
                ]
            ))
        }
        if let ipqs = dbs.ipqs, bool(ipqs, "success") != false {
            rows.append(IPFactorRow(
                name: "IPQS",
                country: (string(ipqs, keys: ["country_code"]) ?? "").uppercased(),
                checks: [
                    ("VPN", yn(bool(ipqs, "vpn") || bool(ipqs, "active_vpn"))),
                    ("代理", yn(bool(ipqs, "proxy"))),
                    ("Tor", yn(bool(ipqs, "tor") || bool(ipqs, "active_tor"))),
                    ("机器人", yn(bool(ipqs, "bot_status"))),
                    ("滥用", yn(bool(ipqs, "recent_abuse")))
                ]
            ))
        }
        if let com = dbs.ipApiCom, string(com, keys: ["status"]) == "success" {
            rows.append(IPFactorRow(
                name: "ip-api",
                country: (string(com, keys: ["countryCode"]) ?? "").uppercased(),
                checks: [
                    ("代理", yn(bool(com, "proxy"))),
                    ("机房", yn(bool(com, "hosting"))),
                    ("移动", yn(bool(com, "mobile")))
                ]
            ))
        }
        if let pc = proxycheckRecord(dbs.proxycheck) {
            let proxy = string(pc, keys: ["proxy"]) ?? ""
            let type = string(pc, keys: ["type"]) ?? ""
            rows.append(IPFactorRow(
                name: "proxycheck",
                country: (string(pc, keys: ["isocode"]) ?? "").uppercased(),
                checks: [
                    ("代理", proxy.uppercased() == "YES" ? "是" : (proxy.isEmpty ? "—" : "否")),
                    ("类型", type.isEmpty ? "—" : type)
                ]
            ))
        }
        return rows
    }

    // MARK: - Media / AI

    private func collectMedia() async -> [IPMediaRow] {
        async let tiktok = testTikTok()
        async let netflix = testNetflix()
        async let youtube = testYouTube()
        async let chatgpt = testChatGPT()
        async let disney = testDisney()
        return await [tiktok, netflix, youtube, chatgpt, disney]
    }

    private func testTikTok() async -> IPMediaRow {
        do {
            let (status, body) = try await requestRaw("https://www.tiktok.com/")
            if let r = body.range(of: #""region"\s*:\s*"([A-Z]{2})""#, options: .regularExpression) {
                let m = String(body[r])
                let code = m.replacingOccurrences(of: #""region"\s*:\s*""#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: "\"", with: "")
                if code.count == 2 {
                    return IPMediaRow(name: "TikTok", status: "yes", region: code, note: "页面地区")
                }
            }
            if status == 403 || body.range(of: "not available|access denied", options: .regularExpression) != nil {
                return IPMediaRow(name: "TikTok", status: "no", region: "", note: "HTTP \(status)")
            }
            return IPMediaRow(name: "TikTok", status: "unknown", region: "", note: "地区未识别")
        } catch {
            return IPMediaRow(name: "TikTok", status: "unknown", region: "", note: "请求失败")
        }
    }

    private func testNetflix() async -> IPMediaRow {
        // 81280792 self-produced; 70143836 licensed — simplified availability probe
        do {
            let (status, _) = try await requestRaw("https://www.netflix.com/title/81280792", method: "GET")
            if status == 200 {
                return IPMediaRow(name: "Netflix", status: "yes", region: "", note: "标题页可访问")
            }
            if status == 404 || status == 403 {
                return IPMediaRow(name: "Netflix", status: "no", region: "", note: "HTTP \(status)")
            }
            return IPMediaRow(name: "Netflix", status: "unknown", region: "", note: "HTTP \(status)")
        } catch {
            return IPMediaRow(name: "Netflix", status: "unknown", region: "", note: "请求失败")
        }
    }

    private func testYouTube() async -> IPMediaRow {
        do {
            let (status, body) = try await requestRaw("https://www.youtube.com/premium")
            if body.range(of: "www.google.cn|premium.*not available|无法提供", options: [.regularExpression, .caseInsensitive]) != nil {
                return IPMediaRow(name: "YouTube", status: "no", region: "", note: "地区限制")
            }
            if status == 200 {
                return IPMediaRow(name: "YouTube", status: "yes", region: "", note: "Premium 页可访问")
            }
            return IPMediaRow(name: "YouTube", status: "unknown", region: "", note: "HTTP \(status)")
        } catch {
            return IPMediaRow(name: "YouTube", status: "unknown", region: "", note: "请求失败")
        }
    }

    private func testChatGPT() async -> IPMediaRow {
        do {
            let (status, body) = try await requestRaw("https://chatgpt.com/cdn-cgi/trace")
            if status == 200, body.contains("loc=") {
                let loc = body.split(separator: "\n")
                    .first(where: { $0.hasPrefix("loc=") })
                    .map { String($0.dropFirst(4)) } ?? ""
                let unsupported = ["CN", "HK", "RU", "KP"]
                if unsupported.contains(loc.uppercased()) {
                    return IPMediaRow(name: "ChatGPT", status: "no", region: loc, note: "地区不可用")
                }
                return IPMediaRow(name: "ChatGPT", status: "yes", region: loc, note: "cdn-cgi")
            }
            if status == 403 {
                return IPMediaRow(name: "ChatGPT", status: "no", region: "", note: "HTTP 403")
            }
            return IPMediaRow(name: "ChatGPT", status: "unknown", region: "", note: "HTTP \(status)")
        } catch {
            return IPMediaRow(name: "ChatGPT", status: "unknown", region: "", note: "请求失败")
        }
    }

    private func testDisney() async -> IPMediaRow {
        do {
            let (status, _) = try await requestRaw("https://www.disneyplus.com/")
            if status == 200 {
                return IPMediaRow(name: "Disney+", status: "yes", region: "", note: "首页可访问")
            }
            if status == 403 || status == 451 {
                return IPMediaRow(name: "Disney+", status: "no", region: "", note: "HTTP \(status)")
            }
            return IPMediaRow(name: "Disney+", status: "unknown", region: "", note: "HTTP \(status)")
        } catch {
            return IPMediaRow(name: "Disney+", status: "unknown", region: "", note: "请求失败")
        }
    }

    // MARK: - HTTP helpers

    private func requestJSON(_ urlString: String) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw NetworkError.invalidURL }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NetworkError.message("HTTP 失败")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.message("非 JSON")
        }
        return obj
    }

    private func requestText(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw NetworkError.invalidURL }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NetworkError.message("HTTP 失败")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func requestRaw(_ urlString: String, method: String = "GET") async throws -> (Int, String) {
        guard let url = URL(string: urlString) else { throw NetworkError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 10
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml,application/json,*/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let body = String(data: data, encoding: .utf8) ?? ""
        return (status, body)
    }

    private func cloudflareTraceIP(_ text: String) -> String {
        for line in text.split(separator: "\n") {
            if line.hasPrefix("ip=") {
                return String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    private static func normalizeIP(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = t.range(of: #"\d{1,3}(\.\d{1,3}){3}"#, options: .regularExpression) {
            return String(t[r])
        }
        // basic IPv6 keep as-is if looks like
        if t.contains(":") { return t }
        return ""
    }

    private func string(_ obj: [String: Any], keys: [String]) -> String? {
        for k in keys {
            if let s = obj[k] as? String, !s.isEmpty { return s }
            if let n = obj[k] as? NSNumber { return n.stringValue }
        }
        return nil
    }

    private func bool(_ obj: [String: Any], _ key: String) -> Bool {
        if let b = obj[key] as? Bool { return b }
        if let n = obj[key] as? NSNumber { return n.boolValue }
        if let s = obj[key] as? String {
            return ["1", "true", "yes", "y"].contains(s.lowercased())
        }
        return false
    }

    private func double(_ obj: [String: Any], _ key: String) -> Double? {
        if let d = obj[key] as? Double { return d }
        if let n = obj[key] as? NSNumber { return n.doubleValue }
        if let s = obj[key] as? String { return Double(s) }
        return nil
    }

    private func number(_ obj: [String: Any], _ key: String) -> Double? {
        double(obj, key)
    }

    private func yn(_ v: Bool) -> String { v ? "是" : "否" }

    private func translateType(_ raw: String) -> String {
        let t = raw.lowercased()
        if t.isEmpty { return "" }
        let map: [String: String] = [
            "isp": "家宽/ISP",
            "hosting": "机房",
            "business": "商业",
            "education": "教育",
            "government": "政府",
            "military": "军事",
            "cdn": "CDN",
            "banking": "银行",
            "content": "内容",
            "library": "图书馆"
        ]
        return map[t] ?? raw
    }

    private func parseIpapiScore(_ text: String) -> (Int, String, String) {
        // "0.0044 (Low)"
        if let r = text.range(of: #"([0-9.]+)\s*\(([^)]+)\)"#, options: .regularExpression) {
            let m = String(text[r])
            let parts = m.split(separator: "(")
            let ratio = Double(parts[0].trimmingCharacters(in: .whitespaces)) ?? 0
            let level = parts.count > 1
                ? String(parts[1]).replacingOccurrences(of: ")", with: "").trimmingCharacters(in: .whitespaces)
                : ""
            let sev: Int
            switch level.lowercased() {
            case "very high", "critical": sev = 4
            case "high": sev = 3
            case "elevated", "medium", "moderate": sev = 2
            default: sev = 0
            }
            let label: String
            switch level.lowercased() {
            case "very high", "critical": label = "极高风险"
            case "high": label = "高风险"
            case "elevated", "medium", "moderate": label = "中风险"
            case "low": label = "低风险"
            default: label = level.isEmpty ? "未知" : level
            }
            return (sev, label, String(format: "%.2f%%", ratio * 100))
        }
        return (0, "未知", text)
    }

    private func scoreBand(
        _ score: Double,
        bands: [(Double, Int, String)]
    ) -> (Int, String) {
        for (threshold, sev, label) in bands {
            if score >= threshold { return (sev, label) }
        }
        return (0, "低风险")
    }

    private func proxycheckRecord(_ root: [String: Any]?) -> [String: Any]? {
        guard let root else { return nil }
        for (k, v) in root {
            if Self.normalizeIP(k).isEmpty == false, let dict = v as? [String: Any] {
                return dict
            }
        }
        return nil
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

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
