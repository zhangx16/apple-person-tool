import SwiftUI

struct MediaCardView: View {
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    var circular = false
    var artworkSize: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkImage(
                url: artworkURL,
                cornerRadius: circular ? 1_000 : 8
            )
            .frame(width: artworkSize, height: artworkSize)
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
