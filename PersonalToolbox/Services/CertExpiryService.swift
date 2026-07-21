import Foundation
import Security

struct CertWatchItem: Identifiable, Codable, Hashable {
    var id: String
    var host: String
    var port: Int
    var note: String
    var notAfter: Date?
    var issuer: String?
    var lastChecked: Date?
    var lastOK: Bool?
    var error: String?

    var daysLeft: Int? {
        guard let notAfter else { return nil }
        return Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: notAfter)
        ).day
    }
}

@MainActor
final class CertExpiryStore: ObservableObject {
    static let shared = CertExpiryStore()
    private let fileName = "cert_watchlist.json"

    @Published private(set) var items: [CertWatchItem] = []
    @Published private(set) var isChecking = false

    private init() {
        items = LocalJSONStore.load([CertWatchItem].self, from: fileName, fallback: [])
    }

    private func persist() {
        LocalJSONStore.save(items, to: fileName)
    }

    func add(host: String, port: Int = 443, note: String = "", notAfter: Date? = nil) {
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        h = h.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        if let slash = h.firstIndex(of: "/") {
            h = String(h[..<slash])
        }
        guard !h.isEmpty else { return }
        if items.contains(where: { $0.host.caseInsensitiveCompare(h) == .orderedSame && $0.port == port }) {
            return
        }
        items.append(
            CertWatchItem(
                id: UUID().uuidString,
                host: h,
                port: port,
                note: note,
                notAfter: notAfter,
                issuer: nil,
                lastChecked: nil,
                lastOK: nil,
                error: nil
            )
        )
        persist()
    }

    func update(_ item: CertWatchItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i] = item
        persist()
    }

    func delete(id: String) {
        items.removeAll { $0.id == id }
        persist()
    }

    func refreshAll() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        for i in items.indices {
            let host = items[i].host
            let port = items[i].port
            let result = await TLSCertProbe.fetchLeaf(host: host, port: port)
            items[i].lastChecked = Date()
            switch result {
            case .success(let info):
                items[i].notAfter = info.notAfter
                items[i].issuer = info.issuer
                items[i].lastOK = true
                items[i].error = nil
            case .failure(let err):
                items[i].lastOK = false
                items[i].error = err
            }
        }
        persist()
        AppGroupShared.publish(
            checkinHealthy: AppGroupShared.defaults.integer(forKey: AppGroupShared.Key.checkinHealthy),
            checkinTotal: AppGroupShared.defaults.integer(forKey: AppGroupShared.Key.checkinTotal),
            checkinFailed: AppGroupShared.defaults.integer(forKey: AppGroupShared.Key.checkinFailed),
            dueSubs: SubscriptionStore.shared.dueSoon.count,
            nextSubName: SubscriptionStore.shared.dueSoon.first?.name,
            nextSubDays: SubscriptionStore.shared.dueSoon.first?.daysUntilDue
        )
    }

    var expiringSoon: [CertWatchItem] {
        items.filter { ($0.daysLeft ?? 999) <= 30 }
    }
}

// MARK: - TLS leaf certificate probe

enum TLSCertProbe {
    struct Info: Sendable {
        var notAfter: Date?
        var issuer: String?
    }

    static func fetchLeaf(host: String, port: Int) async -> Result<Info, String> {
        await withCheckedContinuation { cont in
            let catcher = TrustCatcher(host: host) { result in
                cont.resume(returning: result)
            }
            catcher.start(port: port)
        }
    }

    private final class TrustCatcher: NSObject, URLSessionDelegate, @unchecked Sendable {
        private let host: String
        private let completion: (Result<Info, String>) -> Void
        private var finished = false
        private var session: URLSession?

        init(host: String, completion: @escaping (Result<Info, String>) -> Void) {
            self.host = host
            self.completion = completion
        }

        func start(port: Int) {
            var comps = URLComponents()
            comps.scheme = "https"
            comps.host = host
            if port != 443 { comps.port = port }
            comps.path = "/"
            guard let url = comps.url else {
                finish(.failure("无效主机"))
                return
            }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            self.session = session
            var req = URLRequest(url: url)
            req.httpMethod = "HEAD"
            session.dataTask(with: req) { [weak self] _, _, error in
                guard let self else { return }
                // If challenge already finished us, ignore.
                if self.finished { return }
                if let error {
                    self.finish(.failure(error.localizedDescription))
                } else {
                    self.finish(.failure("未拿到证书"))
                }
            }.resume()
        }

        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  let trust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            var cert: SecCertificate?
            if #available(iOS 15.0, *) {
                if let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] {
                    cert = chain.first
                }
            }
            if cert == nil {
                cert = SecTrustGetCertificateAtIndex(trust, 0)
            }

            var info = Info()
            if let cert {
                info = Self.parse(cert)
            }
            finish(.success(info))
            // Allow the request to complete (or fail) normally.
            completionHandler(.performDefaultHandling, URLCredential(trust: trust))
        }

        private func finish(_ result: Result<Info, String>) {
            guard !finished else { return }
            finished = true
            session?.invalidateAndCancel()
            completion(result)
        }

        private static func parse(_ cert: SecCertificate) -> Info {
            var info = Info()
            var error: Unmanaged<CFError>?
            let keys = [
                kSecOIDX509V1ValidityNotAfter,
                kSecOIDX509V1IssuerName
            ] as CFArray
            guard let values = SecCertificateCopyValues(cert, keys, &error) as? [CFString: Any] else {
                return info
            }

            if let notAfterBox = values[kSecOIDX509V1ValidityNotAfter] as? [CFString: Any],
               let raw = notAfterBox[kSecPropertyKeyValue] {
                if let date = raw as? Date {
                    info.notAfter = date
                } else if let num = raw as? NSNumber {
                    // Absolute time relative to reference date
                    info.notAfter = Date(timeIntervalSinceReferenceDate: num.doubleValue)
                } else if let str = raw as? String {
                    let f = ISO8601DateFormatter()
                    info.notAfter = f.date(from: str)
                }
            }

            if let issuerBox = values[kSecOIDX509V1IssuerName] as? [CFString: Any],
               let arr = issuerBox[kSecPropertyKeyValue] as? [[CFString: Any]] {
                let parts = arr.compactMap { dict -> String? in
                    guard let label = dict[kSecPropertyKeyLabel] as? String,
                          let value = dict[kSecPropertyKeyValue] as? String else { return nil }
                    return "\(label)=\(value)"
                }
                if let cn = parts.first(where: { $0.hasPrefix("CN=") }) {
                    info.issuer = String(cn.dropFirst(3))
                } else {
                    info.issuer = parts.prefix(2).joined(separator: ", ")
                }
            }
            return info
        }
    }
}
