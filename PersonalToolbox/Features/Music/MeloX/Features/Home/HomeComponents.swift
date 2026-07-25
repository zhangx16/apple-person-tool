import SwiftUI

struct HomeEditorialCard: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let systemImage: String
    let colors: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: systemImage)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.22))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(12)
            }
            .aspectRatio(1.55, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 12))
            .padding(.top, 4)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

struct HomeFeaturedPlaylistCard: View {
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("编辑推荐")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(playlist.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(playlist.copywriter ?? playlist.creator?.nickname ?? "网易云音乐歌单")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ArtworkImage(url: playlist.artworkURL, cornerRadius: 12, aspectRatio: 1.55)
                .frame(maxWidth: .infinity)
                .aspectRatio(1.55, contentMode: .fit)
                .clipped()
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

struct HomeHorizontalSection<Content: View>: View {
    let title: String
    var destination: MusicRoute?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: title, destination: destination)
                .padding(.horizontal, 16)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 10) {
                    content()
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
    }
}

struct HomePlaylistCard: View {
    let playlist: Playlist

    var body: some View {
        MediaCardView(
            title: playlist.name,
            subtitle: playlist.copywriter ?? playlist.updateFrequency ?? playlist.creator?.nickname,
            artworkURL: playlist.artworkURL,
            artworkSize: 118
        )
        .frame(width: 118)
    }
}

struct HomeAlbumCard: View {
    let album: Album

    var body: some View {
        MediaCardView(
            title: album.name,
            subtitle: album.artistText,
            artworkURL: album.artworkURL,
            artworkSize: 118
        )
        .frame(width: 118)
    }
}

struct HomeArtistCard: View {
    let artist: Artist

    var body: some View {
        MediaCardView(
            title: artist.name,
            subtitle: artist.aliases.first ?? "歌手",
            artworkURL: artist.artworkURL,
            circular: true,
            artworkSize: 104
        )
        .frame(width: 104)
    }
}
