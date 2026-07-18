import Foundation

struct MarketQuote: Identifiable, Hashable {
    var id: String
    var title: String
    var value: String
    var subtitle: String
    var systemImage: String
}

@MainActor
final class MarketQuotesService: ObservableObject {
    static let shared = MarketQuotesService()

    @Published private(set) var quotes: [MarketQuote] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var updatedAt: Date?

    /// Default focus province for domestic retail fuel prices.
    var province: String = "安徽"

    private init() {}

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let anhui = fetchAnhuiOil()
        async let fx = fetchFX()
        async let gold = fetchGold()
        async let oil = fetchWTI()

        var list: [MarketQuote] = []
        list.append(contentsOf: await anhui)
        list.append(contentsOf: await fx)
        if let g = await gold { list.append(g) }
        list.append(contentsOf: await oil)
        quotes = list
        updatedAt = Date()
        if list.isEmpty {
            errorMessage = "行情拉取失败，请检查网络"
        }
    }

    // MARK: - 安徽零售油价 (iamwawa free API)

    private func fetchAnhuiOil() async -> [MarketQuote] {
        let area = province.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "安徽"
        guard let url = URL(string: "https://www.iamwawa.cn/oilprice/api?area=\(area)") else { return [] }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 20
            req.setValue("XIN's Tool", forHTTPHeaderField: "User-Agent")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = root["status"] as? Int, status == 1,
                  let d = root["data"] as? [String: Any] else { return [] }

            let date = d["date"] as? String ?? ""
            let next = d["next_update_time"] as? String ?? ""
            let name = d["name"] as? String ?? province
            let p92 = d["p92"] as? String ?? "—"
            let p95 = d["p95"] as? String ?? "—"
            let p98 = d["p98"] as? String ?? "—"
            let p0 = d["p0"] as? String ?? "—"
            let footer = [date, next.isEmpty ? nil : "下次调整 \(next)"].compactMap { $0 }.joined(separator: " · ")

            return [
                MarketQuote(id: "ah-92", title: "\(name) 92# 汽油", value: "\(p92) 元/升", subtitle: footer, systemImage: "fuelpump.fill"),
                MarketQuote(id: "ah-95", title: "\(name) 95# 汽油", value: "\(p95) 元/升", subtitle: footer, systemImage: "fuelpump"),
                MarketQuote(id: "ah-98", title: "\(name) 98# 汽油", value: "\(p98) 元/升", subtitle: footer, systemImage: "fuelpump"),
                MarketQuote(id: "ah-0", title: "\(name) 0# 柴油", value: "\(p0) 元/升", subtitle: footer, systemImage: "flame.fill")
            ]
        } catch {
            return [
                MarketQuote(
                    id: "ah-err",
                    title: "\(province) 油价",
                    value: "暂不可用",
                    subtitle: error.localizedDescription,
                    systemImage: "fuelpump"
                )
            ]
        }
    }

    private func fetchFX() async -> [MarketQuote] {
        let pairs: [(String, String, String)] = [
            ("USD", "CNY", "美元 / 人民币"),
            ("EUR", "CNY", "欧元 / 人民币"),
            ("JPY", "CNY", "日元 / 人民币"),
            ("HKD", "CNY", "港币 / 人民币")
        ]
        var out: [MarketQuote] = []
        for (from, to, title) in pairs {
            guard let url = URL(string: "https://api.frankfurter.app/latest?from=\(from)&to=\(to)") else { continue }
            do {
                let (data, resp) = try await URLSession.shared.data(from: url)
                guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rates = obj["rates"] as? [String: Any],
                      let rate = rates[to] as? Double else { continue }
                out.append(MarketQuote(
                    id: "fx-\(from)-\(to)",
                    title: title,
                    value: String(format: "%.4f", rate),
                    subtitle: "1 \(from) = \(String(format: "%.4f", rate)) \(to) · Frankfurter",
                    systemImage: "coloncurrencysign.circle"
                ))
            } catch { continue }
        }
        return out
    }

    private func fetchGold() async -> MarketQuote? {
        if let url = URL(string: "https://api.metals.live/v1/spot/gold") {
            if let (data, resp) = try? await URLSession.shared.data(from: url),
               let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let first = arr.first,
               let price = first["price"] as? Double ?? (first["price"] as? NSNumber)?.doubleValue {
                return MarketQuote(
                    id: "gold",
                    title: "黄金 (XAU/USD)",
                    value: String(format: "%.2f USD/oz", price),
                    subtitle: "现货参考 · metals.live",
                    systemImage: "circle.hexagongrid.fill"
                )
            }
        }
        return nil
    }

    private func fetchWTI() async -> [MarketQuote] {
        guard let url = URL(string: "https://stooq.com/q/l/?s=cl.f&f=sd2t2ohlcv&h&e=csv") else { return [] }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let text = String(data: data, encoding: .utf8) else { return [] }
            let lines = text.split(whereSeparator: \.isNewline)
            guard lines.count >= 2 else { return [] }
            let cols = lines[1].split(separator: ",").map(String.init)
            guard cols.count >= 7, let close = Double(cols[6]) else { return [] }
            return [
                MarketQuote(
                    id: "wti",
                    title: "WTI 原油",
                    value: String(format: "%.2f USD/桶", close),
                    subtitle: "国际期货参考 · stooq cl.f",
                    systemImage: "flame"
                )
            ]
        } catch {
            return []
        }
    }
}
