import Foundation

/// Local follow list for a few streamers (no cloud / no recommend feed).
@MainActor
final class LiveFollowStore: ObservableObject {
    static let shared = LiveFollowStore()

    @Published private(set) var items: [LiveFollowItem] = []
    @Published private(set) var isRefreshingStatus = false

    private let defaultsKey = "liveFollowItems.v1"
    private var isRefreshingMeta = false

    private init() {
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            items = []
            return
        }
        if let decoded = try? JSONDecoder().decode([LiveFollowItem].self, from: data) {
            items = Self.sorted(decoded)
            return
        }
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
                userAvatar: dict["userAvatar"] as? String ?? "",
                categoryName: dict["categoryName"] as? String ?? "",
                isLive: dict["isLive"] as? Bool,
                online: dict["online"] as? Int ?? 0,
                addedAt: added
            ))
        }
        items = Self.sorted(out)
        persist()
    }

    /// Live first, then most recently added.
    static func sorted(_ list: [LiveFollowItem]) -> [LiveFollowItem] {
        list.sorted { a, b in
            let al = a.isLive == true
            let bl = b.isLive == true
            if al != bl { return al && !bl }
            return a.addedAt > b.addedAt
        }
    }

    func items(for platform: LivePlatform) -> [LiveFollowItem] {
        Self.sorted(items.filter { $0.platform == platform })
    }

    func isFollowing(platform: LivePlatform, roomId: String) -> Bool {
        let rid = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.contains { $0.platform == platform && $0.roomId == rid }
    }

    func follow(_ room: LiveRoomItem, isLive: Bool? = nil) {
        let rid = room.roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return }
        let avatar = room.userAvatar.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = room.categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let idx = items.firstIndex(where: { $0.platform == room.platform && $0.roomId == rid }) {
            var updated = items[idx]
            updated.title = room.title.isEmpty ? updated.title : room.title
            updated.userName = room.userName.isEmpty ? updated.userName : room.userName
            if !room.cover.isEmpty { updated.cover = room.cover }
            if !avatar.isEmpty { updated.userAvatar = avatar }
            if !category.isEmpty { updated.categoryName = category }
            if room.online > 0 { updated.online = room.online }
            if let isLive { updated.isLive = isLive }
            if updated.userAvatar.isEmpty, Self.looksLikeProfileAvatar(updated.cover) {
                updated.userAvatar = updated.cover
            }
            items[idx] = updated
        } else {
            var item = LiveFollowItem(
                platform: room.platform,
                roomId: rid,
                title: room.title,
                userName: room.userName,
                cover: room.cover,
                userAvatar: avatar,
                categoryName: category,
                isLive: isLive,
                online: room.online,
                addedAt: Date()
            )
            if item.userAvatar.isEmpty {
                let display = room.displayAvatar
                if Self.looksLikeProfileAvatar(display) {
                    item.userAvatar = display
                } else if item.cover.isEmpty {
                    item.cover = display
                }
            }
            items.insert(item, at: 0)
        }
        items = Self.sorted(items)
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
            online: item.online,
            userAvatar: item.userAvatar,
            categoryName: item.categoryName
        )
    }

    /// Backfill avatar / category / live status (rate-limited).
    func refreshMissingAvatars(for platform: LivePlatform? = nil) {
        refreshMetadata(for: platform, forceStatus: true)
    }

    func refreshMetadata(for platform: LivePlatform? = nil, forceStatus: Bool = false) {
        guard !isRefreshingMeta else { return }
        let targets = items.filter { item in
            if let platform, item.platform != platform { return false }
            if forceStatus { return true }
            let noFace = item.userAvatar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let noCate = item.categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return noFace || noCate || item.isLive == nil
        }
        guard !targets.isEmpty else { return }
        isRefreshingMeta = true
        isRefreshingStatus = true
        Task { @MainActor in
            defer {
                isRefreshingMeta = false
                isRefreshingStatus = false
            }
            var changed = false
            // Limit concurrent pressure: sequential is safer for rate limits.
            for item in targets.prefix(12) {
                do {
                    let detail = try await LiveSiteRouter.roomDetail(
                        platform: item.platform,
                        roomId: item.roomId
                    )
                    guard let idx = items.firstIndex(where: {
                        $0.platform == item.platform && $0.roomId == item.roomId
                    }) else { continue }
                    var updated = items[idx]
                    let face = detail.userAvatar.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !face.isEmpty { updated.userAvatar = face; changed = true }
                    let cate = detail.categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cate.isEmpty { updated.categoryName = cate; changed = true }
                    if updated.title.isEmpty, !detail.title.isEmpty {
                        updated.title = detail.title
                        changed = true
                    }
                    if updated.userName.isEmpty, !detail.userName.isEmpty {
                        updated.userName = detail.userName
                        changed = true
                    }
                    if !detail.cover.isEmpty { updated.cover = detail.cover; changed = true }
                    updated.isLive = detail.isLive
                    if detail.online > 0 { updated.online = detail.online }
                    updated.lastStatusAt = Date()
                    items[idx] = updated
                    changed = true
                } catch {
                    continue
                }
            }
            if changed {
                items = Self.sorted(items)
                persist()
            }
        }
    }

    private static func looksLikeProfileAvatar(_ url: String) -> Bool {
        let u = url.lowercased()
        return u.contains("avatar") || u.contains("head") || u.contains("face")
            || u.contains("profile")
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
    var userAvatar: String
    var categoryName: String
    /// nil = unknown / not refreshed yet
    var isLive: Bool?
    var online: Int
    var lastStatusAt: Date?
    var addedAt: Date

    var displayAvatar: String {
        let a = userAvatar.trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty { return a }
        return cover
    }

    var displayName: String {
        let n = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { return n }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return "主播 \(roomId)"
    }

    enum CodingKeys: String, CodingKey {
        case platform, roomId, title, userName, cover, userAvatar, categoryName
        case isLive, online, lastStatusAt, addedAt
    }

    init(
        platform: LivePlatform,
        roomId: String,
        title: String,
        userName: String,
        cover: String,
        userAvatar: String = "",
        categoryName: String = "",
        isLive: Bool? = nil,
        online: Int = 0,
        lastStatusAt: Date? = nil,
        addedAt: Date
    ) {
        self.platform = platform
        self.roomId = roomId
        self.title = title
        self.userName = userName
        self.cover = cover
        self.userAvatar = userAvatar
        self.categoryName = categoryName
        self.isLive = isLive
        self.online = online
        self.lastStatusAt = lastStatusAt
        self.addedAt = addedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        platform = try c.decode(LivePlatform.self, forKey: .platform)
        roomId = try c.decode(String.self, forKey: .roomId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        userName = try c.decodeIfPresent(String.self, forKey: .userName) ?? ""
        cover = try c.decodeIfPresent(String.self, forKey: .cover) ?? ""
        userAvatar = try c.decodeIfPresent(String.self, forKey: .userAvatar) ?? ""
        categoryName = try c.decodeIfPresent(String.self, forKey: .categoryName) ?? ""
        isLive = try c.decodeIfPresent(Bool.self, forKey: .isLive)
        online = try c.decodeIfPresent(Int.self, forKey: .online) ?? 0
        lastStatusAt = try c.decodeIfPresent(Date.self, forKey: .lastStatusAt)
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        if userAvatar.isEmpty {
            let lower = cover.lowercased()
            if lower.contains("avatar") || lower.contains("head") || lower.contains("face") {
                userAvatar = cover
            }
        }
    }
}
