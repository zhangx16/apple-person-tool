import SwiftUI
import UIKit
import WebKit

/// Message detail: plain-text first; optional HTML via JS-disabled WKWebView.
struct MessageDetailView: View {
    @ObservedObject var viewModel: MailViewModel
    let messageID: String

    @State private var showHTML = false
    @State private var copiedCode: String?

    var body: some View {
        Group {
            if viewModel.isLoadingDetail && viewModel.detail == nil {
                ProgressView("加载正文…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.detailError, viewModel.detail == nil {
                errorState(message: error)
            } else if let message = viewModel.detail {
                detailContent(message)
            } else {
                EmptyStateView(
                    symbol: "doc.text",
                    title: "无内容",
                    message: "未能获取邮件正文。"
                )
            }
        }
        .background(AppleTheme.canvas)
        .navigationTitle("邮件详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let html = viewModel.detail?.htmlBody, !html.isEmpty {
                    Button(showHTML ? "纯文本" : "查看 HTML") {
                        withAnimation(AppleTheme.snappy) {
                            showHTML.toggle()
                        }
                    }
                }
            }
        }
        .task {
            await viewModel.loadDetail(messageID: messageID)
        }
        .onDisappear {
            // Keep list cache; clear only detail loading flags when leaving.
            viewModel.clearDetail()
        }
    }

    @ViewBuilder
    private func detailContent(_ message: MailMessage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let code = message.extractedVerificationCode {
                    VerificationCodeBanner(code: code) {
                        UIPasteboard.general.string = code
                        copiedCode = code
                        Haptics.success()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(message.subject)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)

                    labeled("发件人", message.from.isEmpty ? "—" : message.from)
                    if let to = message.to, !to.isEmpty {
                        labeled("收件人", to)
                    }
                    labeled("时间", message.displayDate.isEmpty ? "—" : message.displayDate)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))

                if showHTML, let html = message.htmlBody, !html.isEmpty {
                    HTMLWebView(html: html)
                        .frame(minHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
                } else {
                    plainBody(message)
                }

                if let error = viewModel.detailError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
        }
        .overlay(alignment: .bottom) {
            if let copiedCode {
                Text("已复制验证码 \(copiedCode)")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            withAnimation { self.copiedCode = nil }
                        }
                    }
            }
        }
    }

    private func plainBody(_ message: MailMessage) -> some View {
        let text = message.body?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Group {
            if let text, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(16)
                    .background(AppleTheme.card, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
            } else if let html = message.htmlBody, !html.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("此邮件仅有 HTML 正文，可点击右上角「查看 HTML」。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("查看 HTML") {
                        withAnimation(AppleTheme.snappy) { showHTML = true }
                    }
                    .buttonStyle(PressableButtonStyle())
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppleTheme.card, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
            } else if !message.preview.isEmpty {
                Text(message.preview)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(AppleTheme.card, in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous))
            } else {
                Text("（无正文）")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
        }
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
            EmptyStateView(
                symbol: "exclamationmark.triangle",
                title: "无法加载详情",
                message: message
            )
            Button {
                Haptics.light()
                Task { await viewModel.loadDetail(messageID: messageID) }
            } label: {
                PrimaryButtonLabel(title: "重试", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Verification banner

struct VerificationCodeBanner: View {
    let code: String
    var onCopy: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("验证码")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(code)
                    .font(.title2.monospacedDigit().weight(.bold))
                    .textSelection(.enabled)
            }
            Spacer()
            Button("复制", action: onCopy)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(PressableButtonStyle())
        }
        .padding(16)
        .background(
            Color.accentColor.opacity(0.12),
            in: RoundedRectangle(cornerRadius: AppleTheme.cornerRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("验证码 \(code)")
        .accessibilityHint("轻点复制")
        .accessibilityAction(named: "复制", onCopy)
    }
}

// MARK: - HTML (JS disabled)

/// Renders HTML with JavaScript disabled for safety (K17).
struct HTMLWebView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let wrapped = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
          body { font-family: -apple-system, sans-serif; font-size: 16px; line-height: 1.5;
                 color: #111; margin: 12px; word-wrap: break-word; }
          img { max-width: 100%; height: auto; }
          a { color: #007AFF; }
          @media (prefers-color-scheme: dark) {
            body { color: #f2f2f7; }
            a { color: #0A84FF; }
          }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
        webView.loadHTMLString(wrapped, baseURL: nil)
    }
}

#Preview {
    NavigationStack {
        MessageDetailView(viewModel: MailViewModel(), messageID: "demo")
    }
}
