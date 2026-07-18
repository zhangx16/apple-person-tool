import Foundation
import SwiftUI

// MARK: - IP 检测 (aligned with riccilnl IP检测.scripting)

struct IPGeoInfo: Hashable, Sendable {
    var query: String
    var country: String
    var countryCode: String
    var regionName: String
    var city: String
    var isp: String
    var org: String
    var asInfo: String
    var sourceLabel: String
}

struct IPCheckResult: Hashable, Sendable {
    var primary: IPGeoInfo?
    var compareIP: String?
    var compareSource: String?
    var riskValue: Int
    var isHomeBroadband: String
    var isNative: String
    var vpnStatus: String
    var vpnConfidence: Int
    var vpnMethod: String
    var pathStatus: String
}

enum IPCheckAccent {
    /// Match script rgba(174, 109, 216)
    static let color = Color(hex: 0xAE6DD8)
}

enum IPCheckAnalysis {
    private static let dataCenterKeywords = [
        "数据中心", "Amazon", "Google", "Tencent", "Alibaba", "Cloudflare",
        "IDC", "DMIT", "Vultr", "DigitalOcean", "Linode", "OVH", "Hetzner",
        "AWS", "Azure", "GCP", "Oracle Cloud", "Bandwagon", "搬瓦工"
    ]
    private static let homeBroadbandKeywords = [
        "电信", "移动", "联通", "宽带", "Comcast", "Verizon", "ChinaNet",
        "家庭", "住宅", "Residential", "Chinanet", "CMCC", "China Unicom", "China Mobile"
    ]
    private static let highRiskCountries = ["俄罗斯", "印度", "乌克兰", "Russia", "India", "Ukraine"]
    private static let vpnKeywords = [
        "VPN", "Proxy", "Tunnel", "虚拟", "加速器", "节点", "Mullvad", "NordVPN", "ExpressVPN"
    ]

    static func isPrivateIP(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 10 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 127 { return true }
        return false
    }

    static func analyzeISP(isp: String, org: String) -> (
        isDataCenter: Bool,
        isHomeBroadband: Bool,
        isVPNService: Bool,
        confidence: Int
    ) {
        let combined = "\(isp) \(org)".lowercased()
        let isDataCenter = dataCenterKeywords.contains { combined.contains($0.lowercased()) }
        let isHomeBroadband = homeBroadbandKeywords.contains { combined.contains($0.lowercased()) }
        let isVPNService = vpnKeywords.contains { combined.contains($0.lowercased()) }
        var confidence = 50
        if isDataCenter { confidence += 30 }
        if isVPNService { confidence += 20 }
        if isHomeBroadband { confidence -= 20 }
        return (isDataCenter, isHomeBroadband, isVPNService, max(0, min(100, confidence)))
    }

    static func isOverseas(_ info: IPGeoInfo) -> Bool {
        if !info.countryCode.isEmpty, info.countryCode.uppercased() != "CN" { return true }
        if !info.country.isEmpty, !info.country.contains("中国"), info.countryCode.uppercased() != "CN" {
            return true
        }
        return false
    }

    static func detectVPN(
        ipInfo: IPGeoInfo,
        compareIP: String?,
        hasVPNInterface: Bool
    ) -> (isVPN: Bool, isProxy: Bool, proxyType: String, confidence: Int, method: String) {
        let isp = analyzeISP(isp: ipInfo.isp, org: ipInfo.org)
        var vpnScore = 0
        var isProxy = false
        var proxyType = ""
        var methods: [String] = []

        if let china = compareIP, !china.isEmpty, china != ipInfo.query {
            isProxy = true
            proxyType = "分流代理"
            vpnScore += 50
            methods.append("IP分流")
        }

        if compareIP == nil, isOverseas(ipInfo) {
            isProxy = true
            proxyType = "代理"
            vpnScore += 45
            methods.append("海外IP")
        }

        if hasVPNInterface {
            vpnScore += 40
            methods.append("VPN路径")
        }

        if isp.isVPNService {
            vpnScore += 35
            methods.append("VPN服务商")
        } else if isp.isDataCenter {
            vpnScore += 25
            methods.append("数据中心")
        }

        if isp.isHomeBroadband && !isp.isDataCenter {
            vpnScore -= 20
            methods.append("家宽特征")
        }

        var confidence = isp.confidence
        if vpnScore > 0 {
            confidence = min(95, confidence + vpnScore)
        } else {
            confidence = max(5, confidence)
        }

        let isVPN = vpnScore >= 60
        if isProxy && hasVPNInterface {
            return (true, true, "VPN", min(95, confidence), methods.joined(separator: "+"))
        }
        return (
            isVPN,
            isProxy,
            proxyType,
            confidence,
            methods.isEmpty ? "直连" : methods.joined(separator: "+")
        )
    }

    static func calculateRisk(
        ipInfo: IPGeoInfo,
        compareIP: String?,
        hasVPNInterface: Bool
    ) -> IPCheckResult {
        let vpn = detectVPN(ipInfo: ipInfo, compareIP: compareIP, hasVPNInterface: hasVPNInterface)
        let isp = analyzeISP(isp: ipInfo.isp, org: ipInfo.org)
        var risk = 0.0
        if vpn.isVPN || vpn.isProxy {
            risk += Double(vpn.confidence) * 0.5
        }
        if isp.isDataCenter { risk += 20 }
        if isp.isHomeBroadband { risk -= 15 }
        if highRiskCountries.contains(where: { ipInfo.country.contains($0) }) {
            risk += 25
        }
        let riskValue = max(0, min(100, Int(risk.rounded())))

        var vpnStatusText = "未连接"
        if vpn.isVPN {
            vpnStatusText = "已连接"
        } else if vpn.isProxy {
            vpnStatusText = vpn.proxyType
        }

        return IPCheckResult(
            primary: ipInfo,
            compareIP: compareIP,
            compareSource: nil,
            riskValue: riskValue,
            isHomeBroadband: isp.isHomeBroadband ? "家宽" : "非家宽",
            isNative: riskValue < 50 ? "原生" : "非原生",
            vpnStatus: vpnStatusText,
            vpnConfidence: vpn.confidence,
            vpnMethod: vpn.method,
            pathStatus: ""
        )
    }

    /// Flag emoji from ISO country code (regional indicator symbols).
    static func flagEmoji(countryCode: String) -> String {
        let code = countryCode.uppercased()
        guard code.count == 2, code.unicodeScalars.allSatisfy({ CharacterSet.uppercaseLetters.contains($0) }) else {
            return "🌐"
        }
        let base: UInt32 = 127397
        var s = ""
        for u in code.unicodeScalars {
            if let scalar = UnicodeScalar(base + u.value) {
                s.unicodeScalars.append(scalar)
            }
        }
        return s.isEmpty ? "🌐" : s
    }
}
