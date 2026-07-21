import SwiftUI
import UIKit

/// Full-screen interactive SSH terminal (PTY) — landscape by default.
struct SSHTerminalView: View {
    let host: SSHHost
    let password: String

    @StateObject private var session = SSHTerminalSession()
    @State private var input = ""
    @State private var autoScroll = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            terminalScroll
            if let err = session.lastError, !session.isConnected {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.85))
            }
            quickKeys
            inputBar
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(true)
        .onAppear {
            OrientationHelper.lockLandscape()
            session.connect(
                host: host.host,
                port: host.port,
                username: host.username,
                password: password
            )
        }
        .onDisappear {
            session.disconnect()
            OrientationHelper.lockPortrait()
        }
        .background(sizeReader)
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(session.isConnected ? Color.green : (session.isConnecting ? Color.orange : Color.gray))
                .frame(width: 8, height: 8)
            Text(session.statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            if session.isConnected || session.isConnecting {
                Button("断开") { session.disconnect() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.85))
            }
            .accessibilityLabel("关闭终端")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.92))
    }

    private var terminalScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(displayOutput)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.green.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .textSelection(.enabled)
                    .id("bottom")
            }
            .background(Color.black)
            .onChange(of: session.output) { _, _ in
                guard autoScroll else { return }
                withAnimation(.linear(duration: 0.05)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var quickKeys: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                termKey("Tab") { session.send("\t") }
                termKey("Ctrl+C") { session.sendControl("C") }
                termKey("Ctrl+D") { session.sendControl("D") }
                termKey("Ctrl+Z") { session.sendControl("Z") }
                termKey("Esc") { session.send("\u{1B}") }
                termKey("↑") { session.send("\u{1B}[A") }
                termKey("↓") { session.send("\u{1B}[B") }
                termKey("←") { session.send("\u{1B}[D") }
                termKey("→") { session.send("\u{1B}[C") }
                Toggle(isOn: $autoScroll) {
                    Text("自动滚").font(.caption2)
                }
                .toggleStyle(.button)
                .font(.caption2)
                .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Color(white: 0.12))
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("输入后回车发送", text: $input)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.white)
                .submitLabel(.send)
                .onSubmit { sendInput() }
                .disabled(!session.isConnected)

            Button(action: sendInput) {
                Image(systemName: "return")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
            }
            .disabled(!session.isConnected)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(white: 0.08))
    }

    private var sizeReader: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { resize(from: geo.size) }
                .onChange(of: geo.size) { _, size in resize(from: size) }
        }
    }

    private var displayOutput: String {
        stripANSI(session.output)
    }

    private func sendInput() {
        let line = input
        // Allow empty Enter (just newline)
        session.appendLocal(line + "\n")
        session.sendLine(line)
        input = ""
    }

    private func resize(from size: CGSize) {
        let c = max(40, Int(size.width / 7.2))
        let r = max(12, Int((size.height - 100) / 16))
        session.resize(cols: c, rows: r)
    }

    private func termKey(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12), in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(!session.isConnected)
    }

    private func stripANSI(_ s: String) -> String {
        guard s.contains("\u{1B}") else { return s }
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\u{1B}" {
                let next = s.index(after: i)
                if next < s.endIndex, s[next] == "[" {
                    var j = s.index(after: next)
                    while j < s.endIndex {
                        let ch = s[j]
                        j = s.index(after: j)
                        if ("a"..."z").contains(ch) || ("A"..."Z").contains(ch) { break }
                    }
                    i = j
                    continue
                } else if next < s.endIndex {
                    i = s.index(after: next)
                    continue
                }
            }
            out.append(s[i])
            i = s.index(after: i)
        }
        return out
    }
}
