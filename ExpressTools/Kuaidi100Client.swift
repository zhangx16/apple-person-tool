import CryptoKit
import Foundation

enum QueryError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { value } else { "查询失败" } }
}

struct Kuaidi100Client {
    let customer: String
    let key: String

    func query(number: String, carrier: String, phone: String) async throws -> (String?, [TrackingEvent], String) {
        let codes = candidates(carrier, number: number)
        var last: Error = QueryError.message("未查到物流信息")
        for code in codes {
            do { let result = try await queryOnce(number: number, carrier: code, phone: phone); return (result.0, result.1, code) }
            catch { last = error }
        }
        throw last
    }

    private func queryOnce(number: String, carrier: String, phone: String) async throws -> (String?, [TrackingEvent]) {
        let values = [("com", carrier), ("num", number), ("phone", phone), ("resultv2", "1"), ("show", "0"), ("order", "desc")]
        let param = "{" + values.map { "\"\($0.0)\":\"\($0.1.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ",") + "}"
        let digest = Insecure.MD5.hash(data: Data((param + key + customer).utf8)).map { String(format: "%02X", $0) }.joined()
        var components = URLComponents(); components.queryItems = [("customer", customer), ("sign", digest), ("param", param)].map { URLQueryItem(name: $0.0, value: $0.1) }
        var request = URLRequest(url: URL(string: "https://poll.kuaidi100.com/poll/query.do")!)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw QueryError.message("服务暂时不可用") }
        guard "\(json["status"] ?? "")" == "200" else { throw QueryError.message((json["message"] as? String) ?? "查询失败") }
        let events = (json["data"] as? [[String: Any]] ?? []).compactMap { row -> TrackingEvent? in
            guard let description = row["context"] as? String, !description.isEmpty else { return nil }
            return TrackingEvent(time: row["time"] as? String ?? "", description: description, location: row["location"] as? String ?? row["areaName"] as? String)
        }
        return (json["state"] as? String, events)
    }

    private func candidates(_ primary: String, number: String) -> [String] {
        var result = primary == "unknown" ? [] : [primary]
        let guessed = CarrierCatalog.guess(number).0
        if guessed != "unknown", !result.contains(guessed) { result.append(guessed) }
        for code in ["shunfeng", "yuantong", "zhongtong", "shentong", "yunda", "jtexpress", "jd", "ems", "youzhengguonei"] where !result.contains(code) { result.append(code) }
        return result
    }
}
