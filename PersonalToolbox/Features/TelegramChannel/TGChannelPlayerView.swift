import AVKit
import SwiftUI

/// Simple full-screen AVPlayer for tg-channel-api `/play` streams.
struct TGChannelPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let request: URLRequest

    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ProgressView("加载视频…")
                        .tint(.white)
                        .foregroundStyle(.white)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        player?.pause()
                        dismiss()
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task {
            // AVPlayer doesn't send custom Authorization headers by default.
            // Download via URLSession with headers into a temp file, then play.
            await load()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private func load() async {
        do {
            let (url, response) = try await URLSession.shared.download(for: request)
            let http = response as? HTTPURLResponse
            if let http, !(200...299).contains(http.statusCode) {
                return
            }
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("tg-\(UUID().uuidString).mp4")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: url, to: dest)
            let p = AVPlayer(url: dest)
            player = p
            p.play()
        } catch {
            // leave empty; user can dismiss
        }
    }
}
