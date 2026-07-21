import Foundation
import Citadel
import NIOCore
import NIOSSH

/// Interactive SSH shell session (PTY) backed by Citadel.
@MainActor
final class SSHTerminalSession: ObservableObject {
    @Published private(set) var output: String = ""
    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false
    @Published var statusText: String = "未连接"
    @Published var lastError: String?

    private var client: SSHClient?
    private var writer: TTYStdinWriter?
    private var sessionTask: Task<Void, Never>?
    private let maxChars = 200_000

    var cols: Int = 80
    var rows: Int = 24

    func connect(host: String, port: Int, username: String, password: String) {
        disconnect()
        isConnecting = true
        statusText = "连接中…"
        lastError = nil
        output = ""

        let cols = self.cols
        let rows = self.rows

        sessionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let settings = SSHClientSettings(
                    host: host,
                    port: port,
                    authenticationMethod: {
                        .passwordBased(username: username, password: password)
                    },
                    hostKeyValidator: .acceptAnything()
                )
                let client = try await SSHClient.connect(to: settings)
                await MainActor.run {
                    self.client = client
                    self.statusText = "已连接 · 启动 shell…"
                }

                let pty = SSHChannelRequestEvent.PseudoTerminalRequest(
                    wantReply: true,
                    term: "xterm-256color",
                    terminalCharacterWidth: cols,
                    terminalRowHeight: rows,
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0,
                    terminalModes: SSHTerminalModes([:])
                )

                // withPTY keeps the shell open until we return from the closure.
                try await client.withPTY(pty) { inbound, outbound in
                    await MainActor.run {
                        self.writer = outbound
                        self.isConnected = true
                        self.isConnecting = false
                        self.statusText = "\(username)@\(host)"
                    }

                    for try await chunk in inbound {
                        if Task.isCancelled { break }
                        let text: String
                        switch chunk {
                        case .stdout(let buf), .stderr(let buf):
                            text = Self.string(from: buf)
                        }
                        if !text.isEmpty {
                            await MainActor.run {
                                self.appendOutput(text)
                            }
                        }
                    }

                    await MainActor.run {
                        self.isConnected = false
                        self.writer = nil
                        if !Task.isCancelled {
                            self.statusText = "会话已结束"
                        }
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isConnecting = false
                    self.isConnected = false
                    self.statusText = "已断开"
                }
            } catch {
                await MainActor.run {
                    self.isConnecting = false
                    self.isConnected = false
                    self.lastError = error.localizedDescription
                    self.statusText = "连接失败"
                    self.appendOutput("\r\n[错误] \(error.localizedDescription)\r\n")
                }
            }
        }
    }

    func disconnect() {
        sessionTask?.cancel()
        sessionTask = nil
        let client = self.client
        self.client = nil
        self.writer = nil
        isConnected = false
        isConnecting = false
        if statusText != "连接失败" {
            statusText = "未连接"
        }
        Task {
            try? await client?.close()
        }
    }

    /// Send raw text (include `\n` yourself when needed).
    func send(_ text: String) {
        guard let writer, isConnected else { return }
        Task {
            do {
                var buf = ByteBufferAllocator().buffer(capacity: text.utf8.count)
                buf.writeString(text)
                try await writer.write(buf)
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.appendOutput("\r\n[写入失败] \(error.localizedDescription)\r\n")
                }
            }
        }
    }

    func sendLine(_ line: String) {
        send(line + "\n")
    }

    func sendControl(_ c: Character) {
        guard let ascii = c.asciiValue else { return }
        let ctrl = UInt8(ascii & 0x1F)
        send(String(UnicodeScalar(ctrl)))
    }

    func resize(cols: Int, rows: Int) {
        self.cols = max(20, cols)
        self.rows = max(8, rows)
        guard let writer, isConnected else { return }
        let c = self.cols
        let r = self.rows
        Task {
            try? await writer.changeSize(cols: c, rows: r, pixelWidth: 0, pixelHeight: 0)
        }
    }

    func appendLocal(_ text: String) {
        appendOutput(text)
    }

    deinit {
        sessionTask?.cancel()
    }

    private func appendOutput(_ text: String) {
        output += text
        if output.count > maxChars {
            output = String(output.suffix(maxChars))
        }
    }

    private static func string(from buffer: ByteBuffer) -> String {
        var buf = buffer
        return buf.readString(length: buf.readableBytes) ?? ""
    }
}
