import Foundation

/// Simple Documents JSON persistence for local tools.
enum LocalJSONStore {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func url(_ fileName: String) -> URL {
        documents.appendingPathComponent(fileName)
    }

    static func load<T: Decodable>(_ type: T.Type, from fileName: String, fallback: T) -> T {
        let path = url(fileName)
        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            return fallback
        }
        return decoded
    }

    static func save<T: Encodable>(_ value: T, to fileName: String) {
        let path = url(fileName)
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: path, options: [.atomic])
        } catch {
            // Best-effort local cache; ignore disk errors.
        }
    }
}
