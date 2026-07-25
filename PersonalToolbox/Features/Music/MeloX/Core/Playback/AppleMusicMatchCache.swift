import Foundation

/// Persists Netease song id → Apple Music catalog id for faster rematch.
final class AppleMusicMatchCache: @unchecked Sendable {
    static let shared = AppleMusicMatchCache()

    private let defaults = UserDefaults.standard
    private let key = "melox.appleMusicMatchCache.v1"
    private let lock = NSLock()
    private var map: [String: String]

    private init() {
        map = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    func musicItemID(forNeteaseSongID id: Int) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return map[String(id)]
    }

    func store(neteaseSongID: Int, musicItemID: String) {
        lock.lock()
        map[String(neteaseSongID)] = musicItemID
        let snapshot = map
        lock.unlock()
        defaults.set(snapshot, forKey: key)
    }

    func remove(neteaseSongID: Int) {
        lock.lock()
        map.removeValue(forKey: String(neteaseSongID))
        let snapshot = map
        lock.unlock()
        defaults.set(snapshot, forKey: key)
    }

    func clear() {
        lock.lock()
        map = [:]
        lock.unlock()
        defaults.removeObject(forKey: key)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return map.count
    }
}
