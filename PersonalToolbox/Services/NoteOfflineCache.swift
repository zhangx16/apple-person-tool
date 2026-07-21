import Foundation

struct OfflineNote: Identifiable, Codable, Hashable {
    var id: String { path }
    var path: String
    var vault: String
    var title: String
    var content: String
    var favorite: Bool
    var updatedAt: Date
}

/// Local cache of Fast Note contents for offline read + favorites.
@MainActor
final class NoteOfflineCache: ObservableObject {
    static let shared = NoteOfflineCache()
    private let fileName = "note_offline_cache.json"
    private let maxNotes = 80

    @Published private(set) var notes: [OfflineNote] = []

    private init() {
        notes = LocalJSONStore.load([OfflineNote].self, from: fileName, fallback: [])
    }

    private func persist() {
        LocalJSONStore.save(notes, to: fileName)
    }

    func upsert(path: String, vault: String, title: String, content: String, favorite: Bool? = nil) {
        let fav = favorite ?? notes.first(where: { $0.path == path })?.favorite ?? false
        let note = OfflineNote(
            path: path,
            vault: vault,
            title: title,
            content: content,
            favorite: fav,
            updatedAt: Date()
        )
        if let i = notes.firstIndex(where: { $0.path == path }) {
            notes[i] = note
        } else {
            notes.insert(note, at: 0)
        }
        if notes.count > maxNotes {
            // Prefer dropping non-favorites first
            notes.sort { a, b in
                if a.favorite != b.favorite { return a.favorite && !b.favorite }
                return a.updatedAt > b.updatedAt
            }
            notes = Array(notes.prefix(maxNotes))
        }
        persist()
    }

    func toggleFavorite(path: String) {
        guard let i = notes.firstIndex(where: { $0.path == path }) else { return }
        notes[i].favorite.toggle()
        persist()
    }

    func note(path: String) -> OfflineNote? {
        notes.first { $0.path == path }
    }

    func search(_ q: String) -> [OfflineNote] {
        let s = q.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else {
            return notes.sorted { $0.updatedAt > $1.updatedAt }
        }
        return notes.filter {
            $0.title.lowercased().contains(s)
                || $0.path.lowercased().contains(s)
                || $0.content.lowercased().contains(s)
        }
    }

    var favorites: [OfflineNote] {
        notes.filter(\.favorite).sorted { $0.updatedAt > $1.updatedAt }
    }
}
