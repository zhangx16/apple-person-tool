import Foundation

/// Local follow list for a few streamers (no cloud / no recommend feed).
@MainActor
final class LiveFollowStore: ObservableObject {
    static let shared = LiveFollowStore()

    @Published private(set) var items: [LiveFollowItem] = []

    private let defaultsKey = "liveFollowItems.v1"

    private init() {
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            items = []
            return
        }
        // Drop entries whose platform was removed (e.g. bilibili).
        if let decoded = try? JSONDecoder().decode([LiveFollowItem].self, from: data) {
            items = decoded.sorted { $0.addedAt > $1.addedAt }
            return
        }
        // Lenient path: decode array of dicts and skip unknown platforms.
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            items = []
            return
        }
        var out: [LiveFollowItem] = []
        for dict in raw {
            guard let pRaw = dict["platform"] as? String,
                  let platform = LivePlatform(rawValue: pRaw),
                  let roomId = dict["roomId"] as? String else { continue }
            let added: Date
            if let t = dict["addedAt"] as? TimeInterval {
                added = Date(timeIntervalSinceReferenceDate: t)
            } else if let t = dict["addedAt"] as? Double {
                added = Date(timeIntervalSinceReferenceDate: t)
            } else {
                added = Date()
            }
            out.append(LiveFollowItem(
                platform: platform,
                roomId: roomId,
                title: dict["title"] as? String ?? "",
                userName: dict["userName"] as? String ?? "",
                cover: dict["cover"] as? String ?? "",
                addedAt: added
            ))
        }
        items = out.sorted { $0.addedAt > $1.addedAt }
        persist()
    }

    func isFollowing(platform: LivePlatform, roomId: String) -> Bool {
        let rid = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.contains { $0.platform == platform && $0.roomId == rid }
    }

    func follow(_ room: LiveRoomItem) {
        let rid = room.roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return }
        if let idx = items.firstIndex(where: { $0.platform == room.platform && $0.roomId == rid }) {
            var updated = items[idx]
            updated.title = room.title.isEmpty ? updated.title : room.title
            updated.userName = room.userName.isEmpty ? updated.userName : room.userName
            let avatar = room.displayAvatar
            if !avatar.isEmpty { updated.cover = avatar }
            items[idx] = updated
        } else {
            items.insert(
                LiveFollowItem(
                    platform: room.platform,
                    roomId: rid,
                    title: room.title,
                    userName: room.userName,
                    cover: room.displayAvatar.isEmpty ? room.cover : room.displayAvatar,
                    addedAt: Date()
                ),
                at: 0
            )
        }
        persist()
    }

    func unfollow(platform: LivePlatform, roomId: String) {
        let rid = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        items.removeAll { $0.platform == platform && $0.roomId == rid }
        persist()
    }

    func unfollow(_ item: LiveFollowItem) {
        unfollow(platform: item.platform, roomId: item.roomId)
    }

    func asRoomItem(_ item: LiveFollowItem) -> LiveRoomItem {
        LiveRoomItem(
            platform: item.platform,
            roomId: item.roomId,
            title: item.title,
            cover: item.cover,
            userName: item.userName,
            online: 0
        )
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

struct LiveFollowItem: Codable, Identifiable, Hashable {
    var id: String { "\(platform.rawValue)-\(roomId)" }
    var platform: LivePlatform
    var roomId: String
    var title: String
    var userName: String
    var cover: String
    var addedAt: Date
}
