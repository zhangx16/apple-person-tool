import Foundation

/// Lightweight list badge from Netease song metadata (before URL resolve).
enum SongAccessBadge: String, Sendable {
    case vip
    case paid
    case noCopyright

    var title: String {
        switch self {
        case .vip: "VIP"
        case .paid: "付费"
        case .noCopyright: "无版权"
        }
    }

    /// Heuristic from `fee` / `copyright` fields (not a live privilege API).
    static func resolve(fee: Int?, copyright: Int?) -> SongAccessBadge? {
        // copyright == 0 often means unplayable / no rights in catalog.
        if let copyright, copyright == 0 {
            return .noCopyright
        }
        switch fee {
        case 1:
            // VIP-only stream; free accounts usually get ~30s trial.
            return .vip
        case 4:
            return .paid
        default:
            return nil
        }
    }
}

extension Song {
    var accessBadge: SongAccessBadge? {
        SongAccessBadge.resolve(fee: fee, copyright: copyright)
    }

    /// Songs likely incomplete for non-VIP free accounts (list filter).
    var isLikelyIncompleteWithoutVIP: Bool {
        switch accessBadge {
        case .vip, .paid, .noCopyright:
            return true
        case nil:
            return false
        }
    }
}
