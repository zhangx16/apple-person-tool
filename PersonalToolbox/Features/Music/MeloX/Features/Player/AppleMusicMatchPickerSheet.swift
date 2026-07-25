import SwiftUI

struct AppleMusicMatchPickerSheet: View {
    @Environment(PlayerStore.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if player.isLoadingAppleMusicCandidates {
                    ProgressView("正在搜索 Apple Music…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = player.appleMusicCandidateError {
                    ContentUnavailableView(
                        "匹配失败",
                        systemImage: "music.note.list",
                        description: Text(error)
                    )
                } else if player.appleMusicCandidates.isEmpty {
                    ContentUnavailableView(
                        "没有候选",
                        systemImage: "magnifyingglass",
                        description: Text("换个关键词或检查网络后重试。")
                    )
                } else {
                    List {
                        if let song = player.currentSong {
                            Section {
                                Text("网易云：\(song.name) · \(song.artistText)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Section {
                            ForEach(player.appleMusicCandidates) { candidate in
                                Button {
                                    Task {
                                        await player.playAppleMusicCandidate(candidate)
                                        dismiss()
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        ArtworkImage(url: candidate.artworkURL, cornerRadius: 6)
                                            .frame(width: 48, height: 48)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(candidate.title)
                                                .font(.body.weight(.medium))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Text(candidate.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        Spacer(minLength: 4)
                                        Image(systemName: "play.circle.fill")
                                            .foregroundStyle(.pink)
                                    }
                                }
                            }
                        } header: {
                            Text("选择正确匹配")
                        } footer: {
                            Text("选定后会记住，下次同曲优先用该匹配。")
                        }
                    }
                }
            }
            .navigationTitle("更换匹配")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("刷新") {
                        Task { await player.presentAppleMusicMatchPicker() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
