import Foundation

/// Public iTunes Search API (no MusicKit developer token required).
/// Used when MusicKit catalog fails with "Failed to request developer token".
enum ITunesMusicLookup {
    struct Hit: Sendable, Equatable {
        let trackID: Int
        let trackName: String
        let artistName: String
        let collectionName: String?
        let trackTimeMillis: Int?
        let trackViewURL: URL?
        let previewURL: URL?

        /// Deep link that opens the system Apple Music app when possible.
        var appleMusicOpenURL: URL? {
            // music:// is more reliable for hopping into the Music app.
            if let music = URL(string: "music://music.apple.com/song/\(trackID)") {
                return music
            }
            return trackViewURL
        }
    }

    static func search(
        title: String,
        artist: String,
        limit: Int = 8
    ) async throws -> [Hit] {
        let cleanedTitle = scrub(title)
        let cleanedArtist = scrub(artist)
        let terms: [String] = {
            var list: [String] = []
            let both = [cleanedTitle, cleanedArtist].filter { !$0.isEmpty }.joined(separator: " ")
            if !both.isEmpty { list.append(both) }
            if !cleanedTitle.isEmpty { list.append(cleanedTitle) }
            return list
        }()

        var seen = Set<Int>()
        var hits: [Hit] = []
        // Prefer CN storefront for 华语曲；US as fallback.
        let countries = ["cn", "hk", "tw", "us"]

        for term in terms {
            for country in countries {
                let batch = try await request(term: term, country: country, limit: limit)
                for hit in batch {
                    if seen.insert(hit.trackID).inserted {
                        hits.append(hit)
                    }
                }
                if hits.count >= 3 { return rank(hits, title: cleanedTitle, artist: cleanedArtist) }
            }
        }
        return rank(hits, title: cleanedTitle, artist: cleanedArtist)
    }

    static func bestMatch(title: String, artist: String) async throws -> Hit? {
        let hits = try await search(title: title, artist: artist)
        return hits.first
    }

    // MARK: - Private

    private static func request(term: String, country: String, limit: Int) async throws -> [Hit] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("PersonalToolbox/MeloX", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        struct Root: Decodable {
            let results: [Item]
        }
        struct Item: Decodable {
            let trackId: Int?
            let trackName: String?
            let artistName: String?
            let collectionName: String?
            let trackTimeMillis: Int?
            let trackViewUrl: String?
            let previewUrl: String?
            let wrapperType: String?
            let kind: String?
        }

        let root = try JSONDecoder().decode(Root.self, from: data)
        return root.results.compactMap { item in
            guard let id = item.trackId,
                  let name = item.trackName,
                  let artist = item.artistName else { return nil }
            // Prefer song results.
            if let kind = item.kind, kind != "song" { return nil }
            return Hit(
                trackID: id,
                trackName: name,
                artistName: artist,
                collectionName: item.collectionName,
                trackTimeMillis: item.trackTimeMillis,
                trackViewURL: item.trackViewUrl.flatMap(URL.init(string:)),
                previewURL: item.previewUrl.flatMap(URL.init(string:))
            )
        }
    }

    private static func rank(_ hits: [Hit], title: String, artist: String) -> [Hit] {
        let t = title.lowercased()
        let a = artist.lowercased()
        return hits.sorted { lhs, rhs in
            score(lhs, title: t, artist: a) > score(rhs, title: t, artist: a)
        }
    }

    private static func score(_ hit: Hit, title: String, artist: String) -> Int {
        var s = 0
        let ht = hit.trackName.lowercased()
        let ha = hit.artistName.lowercased()
        if ht == title { s += 50 }
        else if ht.contains(title) || title.contains(ht) { s += 30 }
        if !artist.isEmpty {
            if ha == artist { s += 40 }
            else if ha.contains(artist) || artist.contains(ha) { s += 20 }
            for part in artist.split(whereSeparator: { "/,、&".contains($0) }) {
                let p = part.trimmingCharacters(in: .whitespaces).lowercased()
                if !p.isEmpty, ha.contains(p) { s += 10 }
            }
        }
        return s
    }

    private static func scrub(_ raw: String) -> String {
        var s = raw
        for p in [#"\(.*?\)"#, #"（.*?）"#, #"\[.*?\]"#, #"【.*?】"#] {
            s = s.replacingOccurrences(of: p, with: " ", options: .regularExpression)
        }
        return s
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
