import SwiftUI

struct MiniPlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(PlayerStore.self) private var player

    let onExpand: () -> Void

    var body: some View {
        if let song = player.currentSong {
            HStack(spacing: isInline ? 8 : 6) {
                Button(action: onExpand) {
                    HStack(spacing: isInline ? 8 : 10) {
                        ArtworkImage(url: song.album?.artworkURL, cornerRadius: 6)
                            .frame(width: artworkSize, height: artworkSize)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(song.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            if !isInline {
                                Text(miniSubtitle(for: song))
                                    .font(.caption)
                                    .foregroundStyle(player.sourceLayer == .navidrome ? Color.teal : .secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                if player.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 36, height: 36)
                } else {
                    Button {
                        player.togglePlayback()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3.weight(.semibold))
                            .contentTransition(
                                accessibilityReduceMotion
                                    ? .identity
                                    : .symbolEffect(
                                        .replace.downUp.wholeSymbol,
                                        options: .speed(1.25)
                                    )
                            )
                            .animation(
                                accessibilityReduceMotion
                                    ? nil
                                    : .snappy(duration: 0.28, extraBounce: 0),
                                value: player.isPlaying
                            )
                            .frame(width: 36, height: 36)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
                }

                if !isInline {
                    Button {
                        Task { await player.previous() }
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("上一首")

                    Button {
                        Task { await player.next() }
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("下一首")
                }
            }
            .padding(.horizontal, isInline ? 8 : 10)
            .padding(.vertical, isInline ? 2 : 4)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.10), radius: 10, y: 3)
            .contentShape(.rect)
            .simultaneousGesture(playerGesture)
            .accessibilityAction(named: "上一首") {
                Task { await player.previous() }
            }
            .accessibilityAction(named: "下一首") {
                Task { await player.next() }
            }
        }
    }

    private var isInline: Bool {
        placement == .inline
    }

    private var artworkSize: CGFloat {
        isInline ? 28 : 34
    }

    private func miniSubtitle(for song: Song) -> String {
        if player.sourceLayer == .navidrome {
            return player.navidromeMatchLabel
                ?? player.sourceStatusMessage
                ?? "Navidrome"
        }
        if let status = player.sourceStatusMessage,
           player.sourceLayer == .neteaseTrial {
            return status
        }
        return song.artistText
    }

    private var playerGesture: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                if abs(value.translation.height) > abs(value.translation.width) {
                    if value.translation.height < -36 || value.predictedEndTranslation.height < -70 {
                        onExpand()
                    }
                } else if value.translation.width < 0 {
                    Task { await player.next() }
                } else {
                    Task { await player.previous() }
                }
            }
    }
}
