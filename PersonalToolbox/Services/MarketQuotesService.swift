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

    private init() {}

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let fx = fetchFX()
        async let gold = fetchGold()
        async let oil = fetchOilNote()

        var list: [MarketQuote] = []
        list.append(contentsOf: await fx)
        if let g = await gold { list.append(g) }
        list.append(contentsOf: await oil)
        quotes = list
        updatedAt = Date()
        if list.isEmpty {
            errorMessage = "行情拉取失败，请检查网络"
        }
    }

    /// Frankfurter — free, no key.
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

    /// Best-effort gold via free endpoints (may fail; then omit).
    private func fetchGold() async -> MarketQuote? {
        // metals.live style
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
        // Fallback: gold vs USD approximated via currency pair not available — skip
        return nil
    }

    /// Oil: WTI crude via free stooq CSV (no key).
    private func fetchOilNote() async -> [MarketQuote] {
        guard let url = URL(string: "https://stooq.com/q/l/?s=cl.f&f=sd2t2ohlcv&h&e=csv") else { return [] }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let text = String(data: data, encoding: .utf8) else { return [] }
            let lines = text.split(whereSeparator: \.isNewline)
            guard lines.count >= 2 else { return [] }
            let cols = lines[1].split(separator: ",").map(String.init)
            // Symbol,Date,Time,Open,High,Low,Close,...
            guard cols.count >= 7, let close = Double(cols[6]) else { return [] }
            return [
                MarketQuote(
                    id: "wti",
                    title: "WTI 原油",
                    value: String(format: "%.2f USD/桶", close),
                    subtitle: "期货参考 · stooq cl.f",
                    systemImage: "flame"
                ),
                MarketQuote(
                    id: "gas-note",
                    title: "国内油价",
                    value: "见当地加油站",
                    subtitle: "国内零售价需地区源；此处提供国际原油参考",
                    systemImage: "fuelpump"
                )
            ]
        } catch {
            return [
                MarketQuote(
                    id: "gas-note",
                    title: "国内油价",
                    value: "暂无数据源",
                    subtitle: "可后续接入省级油价 API",
                    systemImage: "fuelpump"
                )
            ]
        }
    }
}
